# Task 1 — LED Blink (Easy)

**Goal:** Blink all LED strips red: 0.5s on, 0.5s off, indefinitely until Ctrl+C.

**You will learn:**
- How to import modules (`hardware.py` and `led_controller.py`)
- How to initialize a ROS node (`rospy.init_node`)
- How to use an infinite loop and shut down cleanly

## Setup

```bash
cd /home/lb/catkin_ws/src/bumblebee_bridge/nodes/
touch task1_led_blink.py && chmod +x task1_led_blink.py
nano task1_led_blink.py
```

## Run

```bash
rosrun bumblebee_bridge task1_led_blink.py
# Stop: Ctrl+C — LEDs will turn off automatically
```

## Code — task1_led.py

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import rospy
import time
from bumblebee_bridge.hardware import ShmelHardware
from led_controller import LedController

def main():
    # Register node in ROS.
    # Without this rospy.is_shutdown() won't work.
    rospy.init_node("task1_led_blink", anonymous=True)
    rospy.loginfo("Starting: LED blink...")

    # Create driver — opens I2C.
    hw = ShmelHardware(bus_id=1)
    # Create LED controller.
    led = LedController(hw)

    try:
        # Infinite loop — interrupted by Ctrl+C.
        while not rospy.is_shutdown():
            led.fill_all(255, 0, 0)  # Red on  (R=255, G=0, B=0)
            time.sleep(0.5)
            led.clear_all()          # Off
            time.sleep(0.5)
    except rospy.ROSInterruptException:
        pass
    finally:
        # Cleanup block — always runs on exit.
        led.clear_all()
        hw.stop_all()
        hw.close()
        rospy.loginfo("LEDs off.")

if __name__ == "__main__":
    main()
```

## Code Breakdown

| Line | Explanation |
| --- | --- |
| `#!/usr/bin/env python3` | Shebang — tells Linux to run with Python 3. Must be the first line. |
| `from bumblebee_bridge.hardware import ShmelHardware` | Import driver via package name — not just `from hardware`. |
| `from led_controller import LedController` | Import LED controller from the neighboring file in `nodes/`. |
| `rospy.init_node(...)` | Registers the node in ROS. `anonymous=True` adds a unique suffix. |
| `hw = ShmelHardware(bus_id=1)` | Opens I2C bus #1. |
| `led = LedController(hw)` | Creates LED controller, passing the driver to it. |
| `while not rospy.is_shutdown()` | Loop runs while ROS is active. Ctrl+C will break it. |
| `led.fill_all(255, 0, 0)` | Fill all strips red. |
| `led.clear_all()` | Turn off all strips. |
| `finally:` | Cleanup block. Runs always on exit — guarantees LEDs won't stay on. |

> **🧪 Experiment:** Try `(0,255,0)` for green or `(0,0,255)` for blue. Change the delay: `0.1` = fast, `2.0` = slow.
