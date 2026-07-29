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
vpe_mavlink.py — sim-only Vision Position Estimate bridge for macOS.

RoboStack-jazzy on osx-arm64 ships mavros core but NOT mavros_extras, so the
vision_pose plugin (which would normally subscribe to /mavros/vision_pose/pose
and forward as MAVLink VISION_POSITION_ESTIMATE) is missing. Without it PX4
EKF runs on GPS+IMU only and OFFBOARD horizontal flight drifts.

This script bridges the gap: subscribes to /aruco_map/pose (ArUco map pose,
sparse, only when detection succeeds), keeps the last pose, and republishes
it as MAVLink VISION_POSITION_ESTIMATE to PX4 SITL on UDP :14580 at 30 Hz.
This matches what mavros vision_pose plugin would do.

Coordinate frames:
  /aruco_map/pose is in the ROS-style 'map' frame: x-east, y-north, z-up
    (matches gazebo world; aruco_pose uses ENU).
  PX4's VISION_POSITION_ESTIMATE expects a LOCAL NED frame: x-north, y-east,
    z-down. We convert per the standard ENU→NED rotation.
  Yaw: ENU yaw (CCW from east) → NED yaw (CW from north): yaw_ned = pi/2 - yaw_enu.

Gating: like vpe_fix.py, only publish when the FCU is DISARMED or in OFFBOARD
mode. This prevents fighting the GPS-only EKF during takeoff transitions.

Usage (alongside the launch):
    sim-run vpe_mavlink.py
"""
import math
import time

import rclpy
from rclpy.node import Node
from rclpy.qos import (
    QoSProfile, QoSReliabilityPolicy, QoSHistoryPolicy, QoSDurabilityPolicy
)
from geometry_msgs.msg import PoseWithCovarianceStamped

from pymavlink import mavutil

try:
    from mavros_msgs.msg import State
    HAS_MAVROS_STATE = True
except ImportError:
    HAS_MAVROS_STATE = False


PX4_UDP    = "udpout:127.0.0.1:14580"
SOURCE_SYS = 2
SOURCE_COMP = 197       # MAV_COMP_ID_OBSTACLE_AVOIDANCE
RATE_HZ    = 30.0
POSE_TIMEOUT_S = 0.5    # don't republish poses older than this
GATE_USE_STATE = True   # if False, always publish when last_pose is fresh


def _quat_to_yaw_enu(qx, qy, qz, qw):
    siny_cosp = 2.0 * (qw * qz + qx * qy)
    cosy_cosp = 1.0 - 2.0 * (qy * qy + qz * qz)
    return math.atan2(siny_cosp, cosy_cosp)


class VpeBridge(Node):
    def __init__(self):
        super().__init__("vpe_mavlink_bridge")

        self.mav = mavutil.mavlink_connection(
            PX4_UDP, source_system=SOURCE_SYS, source_component=SOURCE_COMP
        )
        self.get_logger().info(f"connected MAVLink to {PX4_UDP}")

        # Last sample from aruco_map.
        self.last_pose = None
        self.last_pose_t = None

        # FCU state gate (mirrors vpe_fix logic: DISARMED or OFFBOARD).
        self.gate_open = True   # default: send if no state info yet

        # Stats.
        self.t0 = time.time()
        self.sent = 0
        self.dropped_stale = 0
        self.dropped_gated = 0
        self.last_log = 0.0

        # Subs. /aruco_map/pose comes in sparse; vpe_fix publishes at 30Hz to
        # /mavros/mavros/pose_cov but MAVROS doesn't subscribe (missing plugin)
        # so we sub directly to the source.
        qos = QoSProfile(
            reliability=QoSReliabilityPolicy.RELIABLE,
            history=QoSHistoryPolicy.KEEP_LAST,
            depth=1,
        )
        self.create_subscription(
            PoseWithCovarianceStamped, "/aruco_map/pose", self._pose_cb, qos
        )

        if HAS_MAVROS_STATE and GATE_USE_STATE:
            state_qos = QoSProfile(
                depth=1,
                reliability=QoSReliabilityPolicy.RELIABLE,
                durability=QoSDurabilityPolicy.TRANSIENT_LOCAL,
            )
            self.create_subscription(
                State, "/mavros/state", self._state_cb, state_qos
            )

        # 30 Hz publishing timer.
        self.create_timer(1.0 / RATE_HZ, self._tick)

        self.get_logger().info(
            f"VPE bridge ready: rate={RATE_HZ}Hz, pose_timeout={POSE_TIMEOUT_S}s, "
            f"gate_via_state={HAS_MAVROS_STATE and GATE_USE_STATE}"
        )

    def _pose_cb(self, msg):
        self.last_pose = msg.pose.pose
        self.last_pose_t = time.time()

    def _state_cb(self, msg):
        new_gate = (not msg.armed) or (msg.mode == "OFFBOARD")
        if new_gate != self.gate_open:
            self.get_logger().info(
                f"VPE gate {'OPEN' if new_gate else 'CLOSED'} "
                f"(armed={msg.armed} mode={msg.mode})"
            )
            self.gate_open = new_gate

    def _tick(self):
        # Periodic stats log every 5s.
        now = time.time()
        if now - self.last_log >= 5.0:
            self.get_logger().info(
                f"VPE sent={self.sent} stale={self.dropped_stale} "
                f"gated={self.dropped_gated} (window {now - self.t0:.1f}s) "
                f"last_pose_age={'-' if not self.last_pose_t else f'{now-self.last_pose_t:.2f}s'}"
            )
            self.last_log = now

        if self.last_pose is None:
            return
        if not self.gate_open:
            self.dropped_gated += 1
            return

        age = now - self.last_pose_t
        if age > POSE_TIMEOUT_S:
            self.dropped_stale += 1
            return

        p = self.last_pose.position
        o = self.last_pose.orientation

        # ENU -> NED:
        #   north = y_enu  (ROS aruco map: y is forward/north relative to grid)
        #   east  = x_enu  (x is right/east)
        #   down  = -z_enu
        # But aruco_pose in this project uses ROS REP-103: x-forward, y-left, z-up
        # which is FLU not strict ENU. The map frame's "x" points along marker 0's
        # forward direction. In our world the markers grid is laid x=row, y=col;
        # so we treat aruco map x→east, y→north, z→up. If headings look 90deg off
        # in flight, this is the place to flip.
        x_n = p.y
        y_n = p.x
        z_n = -p.z

        yaw_enu = _quat_to_yaw_enu(o.x, o.y, o.z, o.w)
        yaw_ned = math.pi / 2.0 - yaw_enu

        # PX4 wants timestamps in microseconds since system boot or UTC.
        # The simplest stable choice: monotonic micros since this script started.
        usec = int((now - self.t0) * 1e6)

        # NaN covariance → PX4 uses defaults from EKF2_EV_*_NOISE params.
        cov = [float("nan")] * 21
        self.mav.mav.vision_position_estimate_send(
            usec, x_n, y_n, z_n, 0.0, 0.0, yaw_ned, cov
        )
        self.sent += 1


def main():
    rclpy.init()
    n = VpeBridge()
    try:
        rclpy.spin(n)
    except KeyboardInterrupt:
        pass
    finally:
        n.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
