# Copyright 2026 FutureLab
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
drone_sim.py — sim shim around the production drone.py.

Production scripts import `drone` and call e.g. drone.set_servo_angle(0).
On the real drone those go to I2C ATtiny @ 0x30. In sim there is no I2C bus,
so smbus2 imports raise or the writes fail.

Use this shim instead of patching the production drone.py:

    import sys, importlib
    sys.path.insert(0, '/home/bumblebee/ros2_ws/install/bumblebee_sim/share/bumblebee_sim/python')
    import drone_sim          # patches drone in-place
    import drone               # works as if I2C succeeded (no-op)

`sim-run <script>` does this automatically (it imports drone_sim first).
"""
import math
import os
import sys
import importlib
import subprocess
import threading

# Production drone.py lives in <bumblebee>/share/bumblebee/examples/drone.py
# but the production package installs that path; resolve it via ros2.
_PROD_DRONE_PATHS = [
    '/home/lb/ros2_ws/src/bumblebee/examples',
    '/home/bumblebee/ros2_ws/src/bumblebee/examples',
    os.path.expanduser('~/ros2_ws/src/bumblebee/examples'),
]
for _p in _PROD_DRONE_PATHS:
    if os.path.isdir(_p) and _p not in sys.path:
        sys.path.insert(0, _p)
        break

import drone  # noqa: E402  -- import after path setup


def _noop(*_args, **_kwargs):
    """Replacement for I2C-only methods in sim."""
    return None


def _read_temperature_stub():
    """Return plausible board temps for sim (no I2C)."""
    return (35, 40)


def _aruco_check_stub_pass(*_args, **kwargs):
    """Pretend ArUco preflight always passes. Used when running flight scripts
    against the gz ground-truth VPE bridge (vpe_groundtruth.py) where there's
    no real ArUco vision source to satisfy require_aruco / wait_yaw_lock /
    check_aruco. Returns 'OK'-shaped values per each function's contract."""
    return [0]   # require_aruco / check_aruco return list of marker ids


def _aruco_yaw_lock_stub_pass(*_args, **kwargs):
    return True


# ──── LED bridge: drone.set_led → gz visual_config ──────────────────────────
# Real drone: 6 RGB strips controlled via I2C ATtiny @0x30.
# Sim:        6 visible bars on x500_base SDF (led_1..led_6 visuals on base_link).
# strip ID    → SDF visual name. Mapping mirrors drone.py LED_1..LED_6 constants.
# pixel index → ignored (sim has 1 colour per whole strip, not per pixel).
_GZ_BIN   = "gz"
_GZ_WORLD = os.environ.get("PX4_GZ_WORLD", "clover_aruco")
_GZ_SVC   = f"/world/{_GZ_WORLD}/visual_config"
# gz visual_config looks up visuals by `name` within the link named
# `parent_name`. The bare link name works ("base_link") — model-prefixed form
# ("x500_mono_cam_down_0::base_link") returns "data: true" but silently fails
# with "[error] [UserCommands.cc] Failed to find visual entity" in gz log.
_GZ_PARENT = "base_link"
# drone.py constants → SDF visual name (PA-pin order):
#   LED_1=0 → led_1   LED_2=5 → led_2   LED_3=1 → led_3
#   LED_4=3 → led_4   LED_5=2 → led_5   LED_6=4 → led_6
_STRIP_TO_VISUAL = {0: "led_1", 5: "led_2", 1: "led_3", 3: "led_4", 2: "led_5", 4: "led_6"}
_ALL_VISUALS = ["led_1", "led_2", "led_3", "led_4", "led_5", "led_6"]
_LED_ENV = os.environ.copy()
_LED_ENV.setdefault("GZ_IP", "127.0.0.1")


def _send_led_color(visual_name, r, g, b):
    """Fire-and-forget gz service call to update a single LED visual material."""
    rf, gf, bf = r / 255.0, g / 255.0, b / 255.0
    req = (f'name: "{visual_name}", parent_name: "{_GZ_PARENT}", '
           f'material {{ ambient: {{ r: {rf} g: {gf} b: {bf} a: 1 }} '
           f'diffuse: {{ r: {rf} g: {gf} b: {bf} a: 1 }} '
           f'emissive: {{ r: {rf} g: {gf} b: {bf} a: 1 }} }}')
    # gz CLI takes ~1.5-2.0s end-to-end (transport discovery + RPC). The inner
    # --timeout is the gz service request budget and must exceed the
    # round-trip; the subprocess timeout must exceed the full CLI cost. Older
    # values (500ms / 1s) killed every call before it landed, silently
    # dropping all LED updates.
    try:
        subprocess.run(
            [_GZ_BIN, "service", "-s", _GZ_SVC,
             "--reqtype", "gz.msgs.Visual", "--reptype", "gz.msgs.Boolean",
             "--timeout", "3000", "--req", req],
            env=_LED_ENV, capture_output=True, timeout=5.0,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass  # gz not available — don't crash the flight script


# One worker thread per LED visual, each with a 1-slot latest-wins mailbox.
# A single shared worker would serialise all six gz CLI calls (each ~1.6s),
# so a 0.5s blinker would never toggle visibly. Per-visual workers send their
# subprocesses in parallel — gz CLI overhead amortises to ~500ms per call when
# six fire concurrently, so each visual visibly updates at ~2 Hz. Latest-wins
# also collapses led_strip.py's per-pixel off-then-on sequence (which targets
# the same visual twice in sim because pixel index is ignored) into a single
# coherent colour, eliminating the off/on race that left LEDs stuck off.
_LED_PENDING = {v: None for v in _ALL_VISUALS}
_LED_LAST_SENT = {}
_LED_LOCK = threading.Lock()
_LED_EVENTS = {v: threading.Event() for v in _ALL_VISUALS}


def _visual_worker(visual):
    event = _LED_EVENTS[visual]
    while True:
        event.wait()
        with _LED_LOCK:
            color = _LED_PENDING[visual]
            _LED_PENDING[visual] = None
            event.clear()
        if color is None or _LED_LAST_SENT.get(visual) == color:
            continue
        _send_led_color(visual, *color)
        _LED_LAST_SENT[visual] = color


for _v in _ALL_VISUALS:
    threading.Thread(target=_visual_worker, args=(_v,),
                     daemon=True, name=f"drone_sim_{_v}").start()


def _sim_set_led(strip, _led_unused, r, g, b):
    """Replacement for drone.set_led in sim. Maps strip → visual name and
    enqueues the colour update. Pixel index (per-strip) is ignored because
    the sim has 1 colour per whole strip, not per pixel."""
    if strip == 255:           # STRIP_ALL
        targets = _ALL_VISUALS
    else:
        v = _STRIP_TO_VISUAL.get(strip)
        if v is None:
            return
        targets = [v]
    color = (r, g, b)
    with _LED_LOCK:
        for visual in targets:
            _LED_PENDING[visual] = color
            _LED_EVENTS[visual].set()


def _sim_led_off():
    """Real drone.led_off calls set_led(STRIP_ALL, LED_ALL, 0, 0, 0)."""
    _sim_set_led(255, 255, 0, 0, 0)


# ──── Servo bridge: drone.set_servo_angle → gz JointPositionController ─────
# Real drone: position servo on ATtiny @0x30 register _REG_SERVO. Angle 0-255
# maps 0=full-left, 128=center, 255=full-right (drone.py:224).
# Sim:        the bumblebee's neck/head bulb is its own link (servo_arm_link)
#             connected to base_link via servo_joint (revolute, axis Z). The
#             gz-sim JointPositionController plugin subscribes to /bumblebee/servo
#             expecting gz.msgs.Double in radians, and drives the joint via PID.
#             We use `gz topic` (not the visual_config service used by the LED
#             bridge) because visual_config only updates material —
#             pose changes are accepted and silently dropped, so visuals can't
#             be rotated without a joint behind them.
_GZ_SERVO_TOPIC = "/bumblebee/servo"


def _servo_angle_to_yaw(angle):
    """Map 0..255 → 0..π/2 rad (clamped). drone.py uses the byte 0-255 as a
    raw servo command (0 = full one direction, 255 = full the other). In sim
    we treat 0 as "retracted/upright" and 255 as "fully extended forward" so
    a 0↔255 sweep visualises the bumblebee's proboscis dipping forward and
    coming back up (the actual motion the real drone performs)."""
    a = max(0, min(255, int(angle)))
    return (a / 255.0) * (math.pi / 2.0)


def _send_servo_target(yaw_rad):
    """Fire-and-forget gz topic pub: command the servo joint to yaw_rad."""
    try:
        subprocess.run(
            [_GZ_BIN, "topic", "-t", _GZ_SERVO_TOPIC,
             "-m", "gz.msgs.Double",
             "-p", f"data: {yaw_rad}"],
            env=_LED_ENV, capture_output=True, timeout=1.0,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass  # gz not available — don't crash the flight script


def _sim_set_servo_angle(angle):
    """Replacement for drone.set_servo_angle in sim. Fires in a daemon thread
    so callers (e.g. servo.py RC callback) aren't blocked on the gz subprocess."""
    yaw = _servo_angle_to_yaw(angle)
    threading.Thread(target=_send_servo_target, args=(yaw,), daemon=True).start()


def patch():
    """Replace drone.py I2C functions with sim-safe no-ops."""
    drone._led_init = _noop
    drone._i2c_write_block = _noop
    drone._i2c_write_byte = _noop
    drone.set_led = _sim_set_led
    drone.led_off = _sim_led_off
    drone.led_take_control = _noop
    drone.led_release_control = _noop
    drone.set_servo_angle = _sim_set_servo_angle
    drone.set_servo_speed = _noop
    drone.read_temperature = _read_temperature_stub
    drone._SMBUS2_OK = False
    drone._SIM_PATCHED = True

    # Optional ArUco-preflight bypass for flight scripts when a ground-truth
    # VPE bridge is providing pose. Set BUMBLEBEE_SIM_FAKE_ARUCO=1 to enable.
    # set_aruco_map always stubbed in sim: it writes to /home/lb/... and restarts
    # the aruco_map node — both drone-only. The sim's aruco_detect node reads
    # its map from the launch file (bumblebee_sim/map/sim_default.txt) so the
    # drone.py write would be silently ignored anyway.
    drone.set_aruco_map = _noop

    # PX4 v1.16 SITL has no LOCAL_POSITION_NED_COV mavlink stream, so mavros
    # never publishes /mavros/mavros/pose_cov and require_vpe_link can never
    # pass here. The sim pose source is vpe_groundtruth.py (gz ground truth),
    # whose health that gate was designed to verify -- safe to skip in sim.
    drone.require_vpe_link = _noop

    if os.environ.get("BUMBLEBEE_SIM_FAKE_ARUCO", "").lower() in ("1", "true", "yes"):
        import time as _time
        drone.check_aruco = _aruco_check_stub_pass
        drone.require_aruco = _aruco_check_stub_pass
        drone.wait_yaw_lock = _aruco_yaw_lock_stub_pass
        # Also fake the in-flight vision watchdog: pretend markers ARE used
        # continuously, so flight.py's "VISION SILENT >3s -> safe_land" guard
        # never fires.
        drone._aruco_markers_used = 1
        drone._aruco_markers_used_time = _time.monotonic()
        drone._markers_used_age = lambda: 0.0
        drone._SIM_FAKE_ARUCO = True


# Auto-patch on import.
patch()

# Re-export everything from drone so callers can write `from drone_sim import *`
# or `import drone_sim as drone`.
_orig_drone_dir = [n for n in dir(drone) if not n.startswith('_')]
for _name in _orig_drone_dir:
    globals()[_name] = getattr(drone, _name)


def __getattr__(name):
    """Forward any attribute lookup to the patched drone module."""
    return getattr(drone, name)
