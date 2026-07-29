# Information: https://bumblebee.coex.tech/en/simple_offboard.html#gettelemetry

import rclpy
from rclpy.node import Node
from bumblebee.srv import GetTelemetry

rclpy.init()
node = Node('flight')
client = node.create_client(GetTelemetry, 'get_telemetry')
client.wait_for_service()

future = client.call_async(GetTelemetry.Request())
rclpy.spin_until_future_complete(node, future)

# Print drone's state
print(future.result())

node.destroy_node()
rclpy.shutdown()
