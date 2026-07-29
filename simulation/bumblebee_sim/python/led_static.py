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

"""led_static.py -- one-shot static LED setup for sim.

Sets the default Bumblebee navigation light pattern and exits:
  - LED_5, LED_6 (Y− motors): solid GREEN  (front, by user's camera angle)
  - LED_2, LED_4 (Y+ motors): solid RED    (rear)
  - LED_1, LED_3 (side strips): solid CYAN

Replaces the looped led_default.py rainbow-chase in sim — the chase fired
~26 set_led/sec, each launching a gz CLI subprocess; gz transport overloaded
and most updates were silently dropped ("Host unreachable" on responses).
Static setup runs each call sequentially with 0.2s spacing → reliable.
"""
import os
import sys
import time

sys.path.insert(0, os.path.expanduser('~/ros2_ws/src/bumblebee/examples'))
import drone_sim  # patches drone.set_led to forward to gz visual_config
import drone

FRONT_COLOR = (0, 100, 0)   # green
REAR_COLOR  = (100, 0, 0)   # red
SIDE_COLOR  = (0, 50, 50)   # dim cyan

# Direct (non-threaded) update so we know each call really completed.
# drone_sim._send_led_color sends the gz service request synchronously.
_send = drone_sim._send_led_color

print('led_static: applying default pattern')

# Front motors (Y−)
_send('led_5', *FRONT_COLOR); time.sleep(0.2)
_send('led_6', *FRONT_COLOR); time.sleep(0.2)
# Rear motors (Y+)
_send('led_2', *REAR_COLOR);  time.sleep(0.2)
_send('led_4', *REAR_COLOR);  time.sleep(0.2)
# Side strips
_send('led_1', *SIDE_COLOR);  time.sleep(0.2)
_send('led_3', *SIDE_COLOR);  time.sleep(0.2)

print('led_static: done -- LEDs will hold this state until overwritten')
