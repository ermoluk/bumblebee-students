# Information: https://bumblebee.coex.tech/en/laser.html

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Range


class RangefinderNode(Node):
    def __init__(self):
        super().__init__('process_rangefinder')
        self.create_subscription(Range, 'rangefinder/range', self.range_callback, 1)

    def range_callback(self, msg):
        # Process data from the rangefinder
        print('Rangefinder distance:', msg.range)


rclpy.init()
node = RangefinderNode()
rclpy.spin(node)
node.destroy_node()
rclpy.shutdown()
