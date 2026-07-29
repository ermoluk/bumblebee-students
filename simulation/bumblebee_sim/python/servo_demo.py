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

"""servo_demo.py — sim-side programmable servo demo (no RC needed).

The production ~/bumblebee/examples/servo.py drives the servo from RC channel 9.
In sim there is no RC source, so this script exercises drone.set_servo_angle
directly via the drone_sim bridge — the servo_arm visual on the x500 rotates
in Gazebo as the angle changes.

Usage:
    sim-run servo_demo.py                 # 3 full sweeps 0↔255 then centre
    sim-run servo_demo.py 128             # one-shot: set angle and exit
    sim-run servo_demo.py 0 128 255 128   # play angle sequence (1s each)
    sim-run servo_demo.py --sweep 5       # N sweeps then centre
    sim-run servo_demo.py --hold 64 3     # hold angle for N seconds then centre
"""
import sys
import time

import drone_sim  # noqa: F401  -- patches drone.set_servo_angle to gz bridge
import drone

CENTER = 128
STEP_DELAY = 0.25   # seconds between intermediate angles in a sweep
SWEEP_STEP = 5      # angle delta per intermediate step
SEQUENCE_DWELL = 1.0  # seconds to hold each angle in an explicit sequence


def sweep(cycles=3):
    """Sweep 0 → 255 → 0 the given number of times, finish at centre."""
    print(f"servo sweep: {cycles} cycle(s)")
    for i in range(cycles):
        for a in range(0, 256, SWEEP_STEP):
            drone.set_servo_angle(a)
            time.sleep(STEP_DELAY)
        for a in range(255, -1, -SWEEP_STEP):
            drone.set_servo_angle(a)
            time.sleep(STEP_DELAY)
        print(f"  cycle {i + 1}/{cycles} done")
    drone.set_servo_angle(CENTER)


def play_sequence(angles, dwell=SEQUENCE_DWELL):
    """Step through an explicit angle list, holding `dwell` seconds at each."""
    for a in angles:
        a_clamped = max(0, min(255, int(a)))
        print(f"servo angle = {a_clamped}")
        drone.set_servo_angle(a_clamped)
        time.sleep(dwell)


def hold(angle, seconds):
    print(f"servo hold angle={angle} for {seconds}s")
    drone.set_servo_angle(max(0, min(255, int(angle))))
    time.sleep(seconds)
    drone.set_servo_angle(CENTER)


def main(argv):
    args = argv[1:]
    if not args:
        sweep(3)
        return 0
    head = args[0]
    if head == "--sweep":
        cycles = int(args[1]) if len(args) > 1 else 3
        sweep(cycles)
        return 0
    if head == "--hold":
        if len(args) < 3:
            print("usage: servo_demo.py --hold <angle> <seconds>", file=sys.stderr)
            return 2
        hold(int(args[1]), float(args[2]))
        return 0
    # Otherwise: list of angles to play back.
    try:
        angles = [int(x) for x in args]
    except ValueError:
        print(f"unrecognised args: {args}", file=sys.stderr)
        print(__doc__, file=sys.stderr)
        return 2
    play_sequence(angles)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except KeyboardInterrupt:
        drone.set_servo_angle(CENTER)
        print("\ninterrupted — servo returned to center")
