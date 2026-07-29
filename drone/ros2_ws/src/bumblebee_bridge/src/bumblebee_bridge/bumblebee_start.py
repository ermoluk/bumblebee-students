#!/usr/bin/env python3
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
