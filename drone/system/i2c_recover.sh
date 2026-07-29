#!/bin/sh
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

# Send 9 SCL pulses on GPIO3 + STOP condition to unstick any I2C slave.
# GPIO514 = SDA (GPIO2), GPIO515 = SCL (GPIO3) on RPi5 (gpiochip512 base=512).
SDA=514
SCL=515
echo $SDA > /sys/class/gpio/export 2>/dev/null
echo $SCL > /sys/class/gpio/export 2>/dev/null
sleep 0.05
echo out > /sys/class/gpio/gpio${SCL}/direction
echo out > /sys/class/gpio/gpio${SDA}/direction
echo 1   > /sys/class/gpio/gpio${SCL}/value
echo 1   > /sys/class/gpio/gpio${SDA}/value
sleep 0.01
for i in 1 2 3 4 5 6 7 8 9; do
  echo 0 > /sys/class/gpio/gpio${SCL}/value; sleep 0.001
  echo 1 > /sys/class/gpio/gpio${SCL}/value; sleep 0.001
done
echo 0 > /sys/class/gpio/gpio${SDA}/value; sleep 0.001
echo 1 > /sys/class/gpio/gpio${SCL}/value; sleep 0.001
echo 1 > /sys/class/gpio/gpio${SDA}/value; sleep 0.001
echo $SDA > /sys/class/gpio/unexport 2>/dev/null
echo $SCL > /sys/class/gpio/unexport 2>/dev/null
