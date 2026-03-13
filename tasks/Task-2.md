# Task 3 — LED Status Indicator (Advanced)

**Goal:** Add LED status indication to the main node:
- 🟢 Solid green — RC signal present, all OK
- 🔴 Blinking red — FailSafe, signal lost for >2 seconds
- 🟡 Pulsing yellow — autonomous mission running

## Setup

```bash
cd /home/lb/catkin_ws/src/bumblebee_bridge/nodes/
touch task3_led_status.py && chmod +x task3_led_status.py
nano task3_led_status.py
```

## Run

```bash
# Manual mode (default)
rosrun bumblebee_bridge task3_led_status.py

# Autonomous mode
rosrun bumblebee_bridge task3_led_status.py _mode:=auto
```

## Code — task3_led_status.py

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import rospy
import sys
from mavros_msgs.msg import RCIn
from bumblebee_bridge.hardware import ShmelHardware
from led_controller import LedController

class ShmelNodeWithLED:
    """Main node with LED status indication."""

    def __init__(self):
        rospy.init_node('shmel_led_status')
        rospy.loginfo("Starting with LED indication...")

        # Hardware
        self.hw = ShmelHardware(bus_id=1)
        if not self.hw.bus:
            rospy.logfatal("No I2C!")
            sys.exit(1)
        self.led = LedController(self.hw)

        # Parameters
        self.mode = rospy.get_param('~mode', 'manual')
        self.rc_timeout = 2

        # State
        self.last_rc_time = rospy.get_time()
        self.target_motor = 128
        self.target_servo = 128
        self.mission_active = False

        # Blink counter.
        # We do NOT use time.sleep to avoid
        # blocking motor control.
        self.blink_counter = 0
        self.blink_on = True

        if self.mode == 'manual':
            rospy.Subscriber(
                '/mavros/rc/in', RCIn,
                self.rc_callback, queue_size=1)
            rospy.loginfo("Mode: MANUAL")
        else:
            rospy.loginfo("Mode: AUTO")
            self.mission_active = True

        self.rate = rospy.Rate(20)

    def rc_callback(self, msg):
        if len(msg.channels) < 9:
            return
        self.last_rc_time = rospy.get_time()
        rc_wheel = msg.channels[8]
        rc_clamp = msg.channels[6]
        self.target_motor = 128 if 1450 <= rc_wheel <= 1550 else self.map_val(rc_wheel, 1000, 2000, 0, 255)
        self.target_servo = 128 if 1450 <= rc_clamp <= 1550 else self.map_val(rc_clamp, 1000, 2000, 0, 255)

    def map_val(self, x, i_min, i_max, o_min, o_max):
        x = max(i_min, min(i_max, x))
        return int((x - i_min) * (o_max - o_min) / (i_max - i_min) + o_min)

    def update_leds(self):
        """LED logic — called 20 times/sec."""
        self.blink_counter += 1
        if self.blink_counter >= 5:
            self.blink_counter = 0
            self.blink_on = not self.blink_on

        rc_lost = (rospy.get_time() - self.last_rc_time > self.rc_timeout)

        if self.mission_active:
            # Pulsing yellow
            self.led.fill_all(255, 200, 0) if self.blink_on else self.led.fill_all(60, 40, 0)
        elif rc_lost and self.mode == 'manual':
            # Blinking red
            self.led.fill_all(255, 0, 0) if self.blink_on else self.led.clear_all()
        else:
            # Solid green
            self.led.fill_all(0, 255, 0)

    def spin(self):
        try:
            while not rospy.is_shutdown():
                if self.mode == 'manual':
                    if rospy.get_time() - self.last_rc_time > self.rc_timeout:
                        self.target_motor = 128
                        self.target_servo = 128
                    self.hw.set_motor(self.target_motor)
                    self.hw.set_servo(self.target_servo)
                self.update_leds()
                self.rate.sleep()
        except KeyboardInterrupt:
            pass
        finally:
            self.led.clear_all()
            self.hw.stop_all()
            self.hw.close()
            rospy.loginfo("Node stopped.")

if __name__ == "__main__":
    try:
        node = ShmelNodeWithLED()
        node.spin()
    except Exception as e:
        rospy.logfatal(f"Error: {e}")
```

## Key Points

**Why a counter instead of `time.sleep()`?**

Using `time.sleep(0.5)` in the main loop would freeze motor control for 0.5s — the drone couldn't react to the RC transmitter. Instead we count iterations: at 20 Hz, every 5 iterations = 0.25s — toggle blink state.

**LED priority in `update_leds()`**

The method checks three states in order of priority:

| Priority | State | Color |
| --- | --- | --- |
| 1 (highest) | Mission active | 🟡 Pulsing yellow |
| 2 | RC signal lost | 🔴 Blinking red |
| 3 (default) | Normal operation | 🟢 Solid green |
