#!/bin/bash
source /opt/ros/jazzy/setup.bash
source /home/lb/ros2_ws/install/setup.bash
# diagnostic: flush ROS/DDS logs immediately so the last lines before a freeze land on disk
export RCUTILS_LOGGING_BUFFERED_STREAM=0
export RCUTILS_CONSOLE_OUTPUT_FORMAT='[{severity} {time}] [{name}]: {message}'
exec ros2 launch bumblebee bumblebee.launch.py
