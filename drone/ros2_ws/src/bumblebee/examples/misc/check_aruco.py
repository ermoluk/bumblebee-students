import rclpy
from rclpy.node import Node
from aruco_pose.msg import MarkerArray


class ArucoWatcher(Node):
    def __init__(self):
        super().__init__('check_aruco')
        self.last_ids = []
        self.create_subscription(MarkerArray, '/aruco_detect/markers', self.cb, 1)

    def cb(self, msg):
        ids = [m.id for m in msg.markers]
        if ids != self.last_ids:
            if ids:
                print('Markers VISIBLE:', ids)
            else:
                print('No markers in frame')
            self.last_ids = ids


rclpy.init()
node = ArucoWatcher()
print('Watching camera... point it at ArUco markers')
print('Press Ctrl+C to stop')
rclpy.spin(node)
node.destroy_node()
rclpy.shutdown()
