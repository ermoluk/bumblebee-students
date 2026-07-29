#!/usr/bin/env python3
"""theater — chase pattern (every 3rd pixel lit) cycling around all strips."""
import signal
import sys
import time

sys.path.insert(0, '/home/lb/ros2_ws/src/bumblebee/examples')
import drone

STEP_MS = 120
NUM_LEDS = 11
STRIPS = (drone.LED_1, drone.LED_2, drone.LED_3,
          drone.LED_4, drone.LED_5, drone.LED_6)
COLOR = (245, 200, 66)  # match dashboard accent

_running = True


def _stop(*_):
    global _running
    _running = False


signal.signal(signal.SIGTERM, _stop)
signal.signal(signal.SIGINT, _stop)

drone.led_take_control()
try:
    offset = 0
    while _running:
        for s in STRIPS:
            for i in range(NUM_LEDS):
                if (i + offset) % 3 == 0:
                    drone.set_led(s, i, *COLOR)
                else:
                    drone.set_led(s, i, 0, 0, 0)
        time.sleep(STEP_MS / 1000.0)
        offset = (offset + 1) % 3
finally:
    try:
        drone.led_off()
    except OSError:
        pass
    drone.led_release_control()
