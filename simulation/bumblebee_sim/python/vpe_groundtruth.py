#!/usr/bin/env python3
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
vpe_groundtruth.py — sim-only ground-truth VPE bridge.

Bypasses the ArUco vision pipeline entirely. Reads drone pose from gz
ground truth (`/world/.../pose/info`) via the `gz topic -e --json-output`
CLI subprocess (sidesteps gz Python binding version mismatch on Tahoe),
parses out the x500 entity, and sends VISION_POSITION_ESTIMATE MAVLink
messages to PX4 SITL on UDP :14580 at ~30 Hz.

Use this to validate that the PX4 EV fusion + flight control work, and
that horizontal flight is feasible given a clean pose source. The ArUco
chain (vpe_mavlink.py) can then be debugged independently.

Run alongside the launch:
    sim-run vpe_groundtruth.py
or, since this script doesn't need ROS at all:
    GZ_IP=127.0.0.1 python3 vpe_groundtruth.py

Coordinate frames:
  Gazebo world frame: x-forward, y-left, z-up (ENU-ish, REP-103).
  PX4 NED expected by VISION_POSITION_ESTIMATE: x-north, y-east, z-down.
  Mapping: x_n = y_w, y_n = x_w, z_n = -z_w. Yaw similarly flipped.
"""
import json
import math
import os
import subprocess
import sys
import time

from pymavlink import mavutil


PX4_UDP = "udpout:127.0.0.1:14580"
WORLD = os.environ.get("PX4_GZ_WORLD", "clover_aruco")
# dynamic_pose/info carries only moving entities; pose/info dumps the
# whole world each tick and the gz CLI JSON path chokes at ~2 Hz on it.
GZ_TOPIC = f"/world/{WORLD}/dynamic_pose/info"
ENTITY_NAME = "x500_mono_cam_down_0"
SOURCE_SYS = 2
SOURCE_COMP = 197
RATE_HZ = 30.0


def quat_to_yaw(qx, qy, qz, qw):
    siny_cosp = 2.0 * (qw * qz + qx * qy)
    cosy_cosp = 1.0 - 2.0 * (qy * qy + qz * qz)
    return math.atan2(siny_cosp, cosy_cosp)


def main():
    # Make sure GZ_IP is set so the CLI talks to PX4's gz server.
    env = os.environ.copy()
    env.setdefault("GZ_IP", "127.0.0.1")

    print(f"[vpe_gt] world={WORLD}", flush=True)
    print(f"[vpe_gt] starting gz subscribe on {GZ_TOPIC} (entity={ENTITY_NAME})", flush=True)
    proc = subprocess.Popen(
        ["gz", "topic", "-e", "-t", GZ_TOPIC, "--json-output"],
        env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        bufsize=1,
    )

    print(f"[vpe_gt] connecting MAVLink to {PX4_UDP}", flush=True)
    mav = mavutil.mavlink_connection(
        PX4_UDP, source_system=SOURCE_SYS, source_component=SOURCE_COMP
    )

    t0 = time.time()
    last_send = 0.0
    sent = 0
    last_log = t0
    last_pose = None  # (x_n, y_n, z_n, yaw_n)
    last_pose_t = 0.0

    try:
        for line in proc.stdout:
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue

            for ent in msg.get("pose", []):
                if ent.get("name") != ENTITY_NAME:
                    continue
                p = ent.get("position", {})
                o = ent.get("orientation", {})
                xw = p.get("x", 0.0)
                yw = p.get("y", 0.0)
                zw = p.get("z", 0.0)
                qx = o.get("x", 0.0)
                qy = o.get("y", 0.0)
                qz = o.get("z", 0.0)
                qw = o.get("w", 1.0)

                # ENU → NED
                x_n = yw
                y_n = xw
                z_n = -zw
                yaw_enu = quat_to_yaw(qx, qy, qz, qw)
                yaw_n = math.pi / 2.0 - yaw_enu

                last_pose = (x_n, y_n, z_n, yaw_n)
                last_pose_t = time.time()
                break  # done with this msg

            # Throttle send to RATE_HZ.
            now = time.time()
            if last_pose is None:
                continue
            if now - last_send < 1.0 / RATE_HZ:
                continue
            last_send = now

            usec = int((now - t0) * 1e6)
            cov = [float("nan")] * 21
            mav.mav.vision_position_estimate_send(
                usec, last_pose[0], last_pose[1], last_pose[2],
                0.0, 0.0, last_pose[3], cov,
            )
            sent += 1

            if now - last_log >= 5.0:
                print(
                    f"[vpe_gt] sent={sent} last_pose=({last_pose[0]:.2f},{last_pose[1]:.2f},{last_pose[2]:.2f}) "
                    f"yaw={math.degrees(last_pose[3]):.1f}° (window {now - t0:.1f}s)",
                    flush=True,
                )
                last_log = now
    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()
        proc.wait(timeout=2.0)


if __name__ == "__main__":
    main()
