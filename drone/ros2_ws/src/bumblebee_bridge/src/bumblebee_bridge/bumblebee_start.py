#!/usr/bin/env python3
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

"""
bumblebee_unified_controller -- starts in idle mode.
RC control is handled separately by servo.py and wheel.py.
"""
import rclpy
from rclpy.node import Node


class UnifiedController(Node):
    def __init__(self):
        super().__init__('bumblebee_unified_controller')
        self.current_mode = self.declare_parameter('mode', 'manual').get_parameter_value().string_value
        self.get_logger().info(f'UnifiedController started (mode={self.current_mode}), idle')


def main(args=None):
    rclpy.init(args=args)
    node = UnifiedController()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        try:
            rclpy.shutdown()
        except Exception:
            pass


if __name__ == '__main__':
    main()
