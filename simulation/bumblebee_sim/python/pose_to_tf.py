#!/usr/bin/env python3
"""
pose_to_tf.py — bridge MAVROS pose to TF.

MAVROS 2.x's local_position.tf.send parameter requires a specific YAML config
shape (per-plugin namespace) that's awkward to set from a launch dict. Easier:
subscribe to /mavros/mavros/pose and broadcast map -> base_link directly.

Production drone has MAVROS publish this TF via mavros_params.yaml; sim uses
this shim instead.
"""
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy, HistoryPolicy
from geometry_msgs.msg import PoseStamped, TransformStamped
from tf2_ros import TransformBroadcaster


class PoseToTf(Node):
    def __init__(self):
        super().__init__('pose_to_tf')
        self.declare_parameter('input_topic', '/mavros/mavros/pose')
        self.declare_parameter('parent_frame', 'map')
        self.declare_parameter('child_frame', 'base_link')

        topic = self.get_parameter('input_topic').get_parameter_value().string_value
        self.parent = self.get_parameter('parent_frame').get_parameter_value().string_value
        self.child = self.get_parameter('child_frame').get_parameter_value().string_value

        # MAVROS publishes pose as BEST_EFFORT + VOLATILE.
        qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            durability=DurabilityPolicy.VOLATILE,
            history=HistoryPolicy.KEEP_LAST,
            depth=5,
        )
        self.br = TransformBroadcaster(self)
        self.create_subscription(PoseStamped, topic, self.cb, qos)
        self.get_logger().info(
            f'pose_to_tf ready: {topic} -> tf({self.parent} -> {self.child})')

    def cb(self, msg: PoseStamped) -> None:
        t = TransformStamped()
        t.header.stamp = msg.header.stamp
        t.header.frame_id = self.parent
        t.child_frame_id = self.child
        t.transform.translation.x = msg.pose.position.x
        t.transform.translation.y = msg.pose.position.y
        t.transform.translation.z = msg.pose.position.z
        t.transform.rotation = msg.pose.orientation
        self.br.sendTransform(t)


def main():
    rclpy.init()
    node = PoseToTf()
    try:
        rclpy.spin(node)
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
