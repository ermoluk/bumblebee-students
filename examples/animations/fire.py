#!/usr/bin/env python3
"""fire — flickering orange/red per-pixel until SIGTERM."""
import random
import signal
import sys
import time

sys.path.insert(0, '/home/lb/ros2_ws/src/bumblebee/examples')
import drone

FPS = 15
FRAME = 1.0 / FPS
NUM_LEDS = 11
STRIPS = (drone.LED_1, drone.LED_2, drone.LED_3,
          drone.LED_4, drone.LED_5, drone.LED_6)

_running = True


def _stop(*_):
    global _running
    _running = False


signal.signal(signal.SIGTERM, _stop)
signal.signal(signal.SIGINT, _stop)


def flicker():
    intensity = random.random()
    r = int(180 + 75 * intensity)
    g = int(30 + 70 * intensity * random.random())
    b = int(5 * random.random())
    return r, g, b


drone.led_take_control()
try:
    while _running:
        for s in STRIPS:
            for i in range(NUM_LEDS):
                drone.set_led(s, i, *flicker())
        time.sleep(FRAME)
finally:
    try:
        drone.led_off()
    except OSError:
        pass
    drone.led_release_control()
