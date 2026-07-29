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

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    mode_arg = DeclareLaunchArgument('mode', default_value='manual',
                                     description='Controller mode: manual or auto')

    controller_node = Node(
        package='bumblebee_bridge',
        executable='bumblebee_controller',
        name='bumblebee_unified_controller',
        output='screen',
        parameters=[{'mode': LaunchConfiguration('mode')}],
        respawn=True,
        respawn_delay=5.0,
    )

    return LaunchDescription([mode_arg, controller_node])
