#!/usr/bin/env python3
"""
wheel_rc.py -- RC channel 7 controls wheel motor speed.
  CH7 knob: 1000 us = full reverse
            1500 us = stop
            2000 us = full forward
  Speed is proportional to knob position.

MAVROS 2.x publishes RC on /mavros/mavros/in
"""
import sys
import time
sys.path.insert(0, '/home/lb/ros2_ws/src/bumblebee/examples')
import drone

import rclpy
from rclpy.node import Node
from mavros_msgs.msg import RCIn

CH7_IDX = 6    # channel 7 is index 6 (0-based)
STOP    = 128  # neutral 0-255 value
SPEED_GAIN = 2.0  # multiply wheel speed 2x (saturates at extremes)
MIN_WRITE_INTERVAL = 0.1  # s -- floor between I2C writes when value is unchanged


class WheelRC(Node):
    def __init__(self):
        super().__init__('wheel_rc')
        self._last_speed = None      # last value written to the ATtiny
        self._last_write = 0.0       # monotonic time of last I2C write
        self.sub = self.create_subscription(
            RCIn, '/mavros/mavros/in', self._cb, 10)
        self.get_logger().info(
            'WheelRC ready -- CH7 knob: -100=full rev, 0=stop, +100=full fwd')

    def _cb(self, msg):
        if len(msg.channels) <= CH7_IDX:
            return
        ch7 = msg.channels[CH7_IDX]
        # 1000-2000 us -> -100..+100
        normalized = max(-100.0, min(100.0, (ch7 - 1500) / 5.0))
        # dead zone
        if abs(normalized) < 5:
            normalized = 0.0
        # -100..+100 -> 0..255 (128 = stop)
        speed = int(128 + normalized * SPEED_GAIN * 127 / 100)
        speed = max(0, min(255, speed))
        # Throttle I2C traffic: skip unchanged values, and rate-limit repeats.
        # RCIn streams continuously (~10-50 Hz); writing every frame was the
        # biggest source of in-flight 0x30 bus contention.
        now = time.monotonic()
        if speed == self._last_speed and (now - self._last_write) < MIN_WRITE_INTERVAL:
            return
        self._last_speed = speed
        self._last_write = now
        drone.set_servo_speed(speed)
        if normalized > 0:
            direction = f'FWD {normalized:.0f}%'
        elif normalized < 0:
            direction = f'REV {abs(normalized):.0f}%'
        else:
            direction = 'STOP'
        self.get_logger().info(f'Wheel: {direction} (CH7={ch7}us, speed={speed})')


def main():
    rclpy.init()
    node = WheelRC()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        drone.set_servo_speed(STOP)
        node.destroy_node()
        try:
            rclpy.shutdown()
        except Exception:
            pass


if __name__ == '__main__':
    main()
