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
camera_fix.py — fixes YUYV images from v4l2_camera + libcamerify on RPi5 PiSP.

Problem: PiSP ISP writes YUYV output with a 5-row tile pattern:
  - Row N (N % 5 == 0): all columns valid YUYV data
  - Rows N+1..N+4: one 160-pixel tile-column is zeros (rotating pattern)
v4l2_camera reads the buffer with wrong stride assumption, producing green
scan lines.

Fix: extract every 5th row (valid rows), convert YUYV→RGB, resize to
original resolution, and republish.

Subscribe to: <camera>/image_raw  (yuv422_yuy2)
Publish to:   <camera>/image_rgb  (rgb8)
"""

import time
import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, QoSReliabilityPolicy, QoSHistoryPolicy, qos_profile_sensor_data
from sensor_msgs.msg import Image, CameraInfo
import numpy as np
import cv2

WATCHDOG_SEC = 10.0  # recreate subscription if no frames for this long


class CameraFix(Node):
    def __init__(self):
        super().__init__('camera_fix')
        self.declare_parameter('input_topic', 'image_raw_yuv')
        self.declare_parameter('output_topic', 'image_raw')
        self.declare_parameter('row_period', 5)  # every Nth row is valid

        self.in_topic = self.get_parameter('input_topic').value
        self.out_topic = self.get_parameter('output_topic').value
        self.period = self.get_parameter('row_period').value

        self.sub_qos = QoSProfile(
            reliability=QoSReliabilityPolicy.RELIABLE,
            history=QoSHistoryPolicy.KEEP_LAST,
            depth=1,
        )
        # Publish RELIABLE so image_transport CameraSubscriber (RELIABLE sub) can receive
        self.pub = self.create_publisher(Image, self.out_topic, 10)

        # Republish camera_info with same timestamp for image_transport sync
        # Subscribe to 'camera_info_raw' (v4l2 output), publish to 'camera_info' (for aruco/optical_flow)
        self.info_pub = self.create_publisher(CameraInfo, 'camera_info', 10)
        self.last_info = None
        self.create_subscription(CameraInfo, 'camera_info_raw', self._info_cb,
                                 QoSProfile(reliability=QoSReliabilityPolicy.BEST_EFFORT,
                                            history=QoSHistoryPolicy.KEEP_LAST, depth=1))

        self.sub = None
        self.last_frame = time.monotonic()
        self._create_sub()

        # Watchdog: recreate subscription if no frames received
        self.create_timer(WATCHDOG_SEC, self._watchdog)

        self.get_logger().info(
            f'camera_fix: {self.in_topic} -> {self.out_topic} (period={self.period})')

    def _info_cb(self, msg):
        self.last_info = msg

    def _create_sub(self):
        # Do not destroy old subscription — destroying + recreating can cause
        # the executor to lose track of callbacks in rclpy. Old sub is garbage collected.
        self.sub = self.create_subscription(
            Image, self.in_topic, self.cb, self.sub_qos)
        self.last_frame = time.monotonic()

    def _watchdog(self):
        if time.monotonic() - self.last_frame > WATCHDOG_SEC:
            self.get_logger().warn('No frames received, recreating subscription...')
            self._create_sub()

    def cb(self, msg):
        self.last_frame = time.monotonic()

        if msg.encoding != 'yuv422_yuy2':
            self.get_logger().warn(
                f'Expected yuv422_yuy2, got {msg.encoding}', throttle_duration_sec=5)
            return

        raw = np.frombuffer(bytes(msg.data), dtype=np.uint8)
        H, W, step = msg.height, msg.width, msg.step

        try:
            rows = raw.reshape(H, step)
            valid = rows[0::self.period]          # (H/period, step)
            yuyv = valid.reshape(-1, W, 2)        # 2-channel YUYV
            bgr = cv2.cvtColor(yuyv, cv2.COLOR_YUV2BGR_YUYV)

            if bgr.shape[0] != H:
                bgr = cv2.resize(bgr, (W, H), interpolation=cv2.INTER_LINEAR)

            rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        except Exception as e:
            self.get_logger().error(f'camera_fix error: {e}', throttle_duration_sec=2)
            return

        out = Image()
        out.header = msg.header
        out.height = H
        out.width = W
        out.encoding = 'rgb8'
        out.step = W * 3
        out.data = rgb.tobytes()
        self.pub.publish(out)

        # Republish camera_info with matching timestamp for image_transport sync
        if self.last_info is not None:
            info = CameraInfo()
            info = self.last_info
            info.header.stamp = msg.header.stamp
            info.header.frame_id = msg.header.frame_id
            self.info_pub.publish(info)


def main(args=None):
    rclpy.init(args=args)
    node = CameraFix()
    rclpy.spin(node)
    rclpy.shutdown()


if __name__ == '__main__':
    main()
