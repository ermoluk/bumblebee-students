# Task 4 — Full Mission (Expert)

**Goal:** Autonomous scenario — drive to object, grab it, carry it back, release.

> **⚠️ Remember:** Bumblebee can only move **forward and backward** — no turning!

## Mission Sequence

| Step | Action | LED Color |
| --- | --- | --- |
| 1 | Drive forward 3s | 🔵 Blue |
| 2 | Grab object | 🟠 Orange blinking |
| 3 | Drive backward 3s | 🟣 Purple |
| 4 | Release | 🟢 Green (success) |

## Setup

```bash
cd /home/lb/catkin_ws/src/bumblebee_bridge/nodes/
touch task4_full_mission.py && chmod +x task4_full_mission.py
nano task4_full_mission.py
```

## Run

```bash
rosrun bumblebee_bridge task4_full_mission.py
```

> **⚠️ Before running:** Place the drone on a flat surface with clear space ahead. Put an object in front of the gripper at approximately 3 seconds of travel distance.

## Code — task4_full_mission.py

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import rospy
import sys
from bumblebee_bridge.hardware import ShmelHardware
from led_controller import LedController

class FullMission:
    """Drive to object → Grab → Carry back → Release"""

    def __init__(self):
        rospy.init_node('full_mission')
        rospy.loginfo("Starting mission...")
        self.hw = ShmelHardware(bus_id=1)
        if not self.hw.bus:
            rospy.logfatal("No I2C!")
            sys.exit(1)
        self.led = LedController(self.hw)
        self.rate = rospy.Rate(20)

    def drive(self, speed, duration, r, g, b):
        """
        Drive with LED color.
        speed: >128 = forward, <128 = reverse
        duration: seconds
        r, g, b: LED color while driving
        """
        self.led.fill_all(r, g, b)
        start = rospy.get_time()
        while rospy.get_time() - start < duration and not rospy.is_shutdown():
            self.hw.set_motor(speed)
            self.rate.sleep()
        self.hw.set_motor(128)  # Stop

    def blink_led(self, times, r, g, b, on_t=0.3, off_t=0.3):
        """Blink LEDs N times."""
        for _ in range(times):
            if rospy.is_shutdown():
                return
            self.led.fill_all(r, g, b)
            rospy.sleep(on_t)
            self.led.clear_all()
            rospy.sleep(off_t)

    def grab(self):
        """Close the gripper."""
        rospy.loginfo("  Gripper: closing...")
        self.hw.set_servo(255)
        rospy.sleep(1.0)

    def release(self):
        """Open the gripper."""
        rospy.loginfo("  Gripper: opening...")
        self.hw.set_servo(0)
        rospy.sleep(1.0)
        self.hw.set_servo(128)  # Center

    def run(self):
        try:
            rospy.loginfo("[1/4] Driving forward...")
            self.drive(speed=180, duration=3.0, r=0, g=100, b=255)  # Blue
            rospy.sleep(0.5)

            rospy.loginfo("[2/4] Grabbing...")
            self.blink_led(times=3, r=255, g=128, b=0)              # Orange
            self.grab()

            rospy.loginfo("[3/4] Driving backward...")
            self.drive(speed=80, duration=3.0, r=150, g=0, b=255)   # Purple
            rospy.sleep(0.5)

            rospy.loginfo("[4/4] Releasing...")
            self.release()

            rospy.loginfo("Mission complete!")
            self.led.fill_all(0, 255, 0)                             # Green
            rospy.sleep(2.0)

        except rospy.ROSInterruptException:
            pass
        finally:
            self.led.clear_all()
            self.hw.stop_all()
            self.hw.close()
            rospy.loginfo("All stopped.")

if __name__ == "__main__":
    try:
        m = FullMission()
        m.run()
    except Exception as e:
        rospy.logfatal(f"Error: {e}")
```

## Code Breakdown

**`drive(speed, duration, r, g, b)`** — Universal drive method. `128` = stop, above `128` = forward, below `128` = reverse. Command sent 20 times/sec via `rate.sleep()`. Motor stops automatically after the loop.

**`grab()` and `release()`** — `grab()` sends servo = `255` and waits 1s for the mechanism. `release()` opens (`0`), waits, then centers (`128`). Using `rospy.sleep()` here is fine — drone is stationary.

**`run()` — orchestration** — Calls methods in order, logs `[1/4]...[4/4]` to terminal, guarantees cleanup in `finally`.

## Ideas for Modification

- Add a "running fire" effect on strip #4 during movement
- Repeat the mission 3 times in a loop
- Change speed: `speed=200` = fast, `speed=150` = slow
- Add a 5-second pulsing wait before launch
