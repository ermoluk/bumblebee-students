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
vpe_fix.py -- publishes vision_pose at 30Hz using last known pose.

Fills gaps between sparse ArUco detections so PX4 EKF stays valid.
No smoothing filter here -- the PX4 EKF handles noise internally via
EKF2_EVP_NOISE. Adding a filter here only introduces lag in the control loop.

MAVROS 2.x topic note:
  The vision_pose plugin subscribes to ~/pose_cov (/mavros/mavros/pose_cov).
  Publishing PoseWithCovarianceStamped there reaches MAVROS correctly.

Gate logic (publish-only, driven by ArUco quality signals):
  multi_marker_fresh  = (markers_used >= 2 within last 1.0s)
  single_marker_fresh = (yaw_locked AND markers_used >= 1 within last 0.5s)

  EKF2_EV_CTRL bitmask (PX4): 1=hpos, 2=vpos, 4=vel, 8=yaw.

  EKF2_EV_CTRL = 15 is set ONCE at startup and is NEVER toggled in flight.
  DO NOT set EV_CTRL=0 mid-flight -- causes IMU-only dead-reckoning runaway
  (incident 2026-05-13: EV_CTRL was zeroed when vision degraded mid-flight,
  PX4 EKF abandoned vision fusion, drone ran away in +X at 6 m/s, EKF
  position diverged and triggered auto-disarm).

  Vision flow is gated solely by whether vpe_fix publishes /mavros/mavros/
  pose_cov. When the publish flag is False, the 30 Hz publish_timer simply
  emits nothing -- PX4 EKF then coasts on baro+IMU (baro fusion stays enabled
  as secondary altitude source for graceful coast) and resumes fusion the
  instant a fresh pose arrives.

  Publish = True when:
    - Drone is DISARMED  -- pre-arm warm-up; quality ignored on the ground.
    - ARMED + OFFBOARD + (multi_marker_fresh OR single_marker_fresh).

  Publish = False when:
    - ARMED in non-OFFBOARD mode (manual RC, POSCTL, STABILIZED).
    - ARMED + OFFBOARD + vision bad (no fresh single or multi marker).
      EKF coasts on baro+IMU until vision returns. Z drifts toward baro during
      coast but converges back to vision z within a few EKF cycles once vision
      returns (EKF2_EV_DELAY=150ms keeps the fusion stable).

Altitude reference history:
  Until 2026-05-19 we ran EKF2_HGT_REF=0 (baro primary) and Z variance 4.0 m^2
  (vision z effectively ignored). Symptoms on drone .2 in an indoor flight:
  z oscillated ±40 cm during landing on a stationary drone, post-disarm z
  reported 1.62 m while drone was on the floor, and a flight_marker.py run
  triggered the position-jump watchdog (1.9 m / 0.5 s) because baro drift
  fought vision in the EKF. Switching to HGT_REF=3 with vision z variance
  0.09 m^2 makes vision the primary altitude source; baro remains as a
  secondary fusion input for coast.

Baseline EKF2 vision params (gate-owned, set once at startup with retry):
  EKF2_EV_CTRL   = 15     (hpos+vpos+vel+yaw -- full vision fusion, never toggled)
  EKF2_HGT_REF   = 3      (external vision is primary altitude reference)
  EKF2_EVP_NOISE = 0.15   (XY position noise)
  EKF2_EVA_NOISE = 0.05   (yaw noise)
  EKF2_EV_DELAY  = 150.0  (ms)

  Architectural rule: PX4 vision params apply only through vpe_fix.py, never
  set_params.py. The retry-on-fail + force_pull cycle below handles the case
  where MAVROS has not yet cached the PX4 param list when we first set.

Staleness:
  VPE is only published while the ArUco pose is fresh (< POSE_TIMEOUT seconds
  old) AND the gate publish flag is True. Stale poses are NOT republished
  during armed flight.
"""

import rclpy
from rclpy.node import Node
from rclpy.qos import QoSProfile, ReliabilityPolicy, DurabilityPolicy
from geometry_msgs.msg import PoseWithCovarianceStamped
from mavros_msgs.msg import State
from mavros_msgs.srv import ParamSetV2, ParamPull
from rcl_interfaces.msg import ParameterValue, ParameterType
from aruco_pose.msg import MarkerArray
from std_msgs.msg import Int32, Bool


_POS_VARIANCE   = 0.30 ** 2   # 0.0900 m^2  XY
_POS_Z_VARIANCE = 0.30 ** 2   # 0.0900 m^2  Z (vision is primary altitude ref)
_YAW_VARIANCE   = 0.05 ** 2   # 0.0025 rad^2

_POSE_TIMEOUT   = 0.5          # seconds before stale pose stops being published

# Vision-quality-gate thresholds (matched to aruco_detect's publishing cadence).
_QUALITY_MULTI_TIMEOUT  = 1.0   # s — last seen ≥2 markers
_QUALITY_SINGLE_TIMEOUT = 0.5   # s — last seen ≥1 marker AFTER yaw lock

_EV_CTRL_FULL    = 15  # hpos + vpos + velocity + yaw -- set once at startup


class VpeFix(Node):
    def __init__(self):
        super().__init__('vpe_fix')

        self.vpe_pub = self.create_publisher(
            PoseWithCovarianceStamped, '/mavros/mavros/pose_cov', 1)

        self.param_client = self.create_client(ParamSetV2, '/mavros/mavros/set')
        self.pull_client = self.create_client(ParamPull, '/mavros/mavros/pull')

        # Retry bookkeeping for the generic param setter. Maps param_id ->
        # (target value, confirmed bool, retry count).
        self._param_target = {}
        self._param_confirmed = {}
        self._param_retries = {}

        self.last_pose = None
        self.last_cov = None
        self.last_pose_time = None
        self.visible_ids = []
        self.published = 0
        self.vpe_active = False
        self.armed = False
        self.in_offboard = False

        # ArUco quality signals: how many markers were used in the last frame
        # and whether yaw_world is locked. Updated by aruco_detect at frame rate.
        self.markers_used = 0
        self.markers_used_time = None      # rclpy.time.Time of last update
        self.markers_used_multi_time = None  # last time markers_used >= 2
        self.yaw_locked = False

        state_qos = QoSProfile(
            depth=1,
            reliability=ReliabilityPolicy.RELIABLE,
            durability=DurabilityPolicy.TRANSIENT_LOCAL,
        )
        self.create_subscription(State, '/mavros/state', self.state_callback, state_qos)
        self.create_subscription(
            PoseWithCovarianceStamped, '/aruco_map/pose',
            self.aruco_map_callback, 1)
        self.create_subscription(
            MarkerArray, '/aruco_detect/markers',
            self.markers_callback, 1)
        self.create_subscription(
            Int32, '/aruco_detect/markers_used',
            self.markers_used_callback, 10)
        self.create_subscription(
            Bool, '/aruco_detect/yaw_locked',
            self.yaw_locked_callback, 10)
        self.create_timer(1.0 / 30.0, self.publish_timer)
        # Re-evaluate gate at 1 Hz. The gate now only flips an in-process
        # boolean (vpe_active); no MAVLink traffic is generated by the gate
        # in flight. 1 Hz keeps log noise low and reacts fast enough to
        # OFFBOARD/manual-mode transitions.
        self.create_timer(1.0, self._gate_tick)

        # Kick off the initial force_pull after a short delay so MAVROS has
        # time to come up. The pull completion callback then queues the
        # baseline EKF2 vision params.
        self._pull_timer = self.create_timer(5.0, self._initial_pull)

        self.get_logger().info(
            'vpe_fix ready: gate=DISARMED|(OFFBOARD&vision_ok), timeout=%.1fs'
            % _POSE_TIMEOUT)

    # ------------------------------------------------------------------
    # Generic, retry-on-fail param setter
    # ------------------------------------------------------------------
    def _initial_pull(self):
        """One-shot force_pull of the PX4 param list, then queue baseline params."""
        self._pull_timer.cancel()
        if not self.pull_client.service_is_ready():
            self.get_logger().warn(
                'vpe_fix: pull service not ready, skipping initial pull')
            # Still try to push baseline -- _do_set_param will trigger a
            # pull-and-retry if the set fails.
            self._queue_baseline_params()
            return
        req = ParamPull.Request()
        req.force_pull = True
        fut = self.pull_client.call_async(req)
        fut.add_done_callback(self._initial_pull_done)

    def _initial_pull_done(self, f):
        try:
            res = f.result()
            cnt = res.param_received if (res and res.success) else 0
            self.get_logger().info(
                'vpe_fix: initial pull OK (%d params)' % cnt)
        except Exception as e:
            self.get_logger().warn('vpe_fix: initial pull failed: %s' % e)
        self._queue_baseline_params()

    def _queue_baseline_params(self):
        """Set EKF2 vision baseline params owned by the gate.

        EKF2_EV_CTRL=15 is set ONCE here and never modified in flight --
        toggling it mid-flight caused IMU-only dead-reckoning runaway
        (incident 2026-05-13). See module docstring.
        """
        self._set_param('EKF2_EV_CTRL',   15,    ParameterType.PARAMETER_INTEGER)
        self._set_param('EKF2_HGT_REF',   3,     ParameterType.PARAMETER_INTEGER)
        self._set_param('EKF2_EVP_NOISE', 0.15,  ParameterType.PARAMETER_DOUBLE)
        self._set_param('EKF2_EVA_NOISE', 0.05,  ParameterType.PARAMETER_DOUBLE)
        self._set_param('EKF2_EV_DELAY',  150.0, ParameterType.PARAMETER_DOUBLE)

    def _set_param(self, name, value, ptype):
        """Entry point: record target and fire first attempt."""
        self._param_target[name] = value
        self._param_confirmed[name] = False
        self._param_retries[name] = 0
        self._do_set_param(name, value, ptype)

    def _do_set_param(self, name, value, ptype):
        """Issue one ParamSetV2 call (no retry bookkeeping mutation here)."""
        if not self.param_client.service_is_ready():
            self._trigger_pull_and_retry(name, value, ptype)
            return
        pval = ParameterValue()
        pval.type = ptype
        if ptype == ParameterType.PARAMETER_INTEGER:
            pval.integer_value = int(value)
        else:
            pval.double_value = float(value)
        req = ParamSetV2.Request()
        req.param_id = name
        req.value = pval
        fut = self.param_client.call_async(req)
        fut.add_done_callback(
            lambda f, n=name, v=value, t=ptype: self._param_done_cb(f, n, v, t))

    def _param_done_cb(self, f, name, value, ptype):
        try:
            res = f.result()
            if res and res.success:
                self._param_confirmed[name] = True
                self.get_logger().info('vpe_fix: %s=%s OK' % (name, value))
                return
        except Exception as e:
            self.get_logger().warn('vpe_fix: %s exception: %s' % (name, e))
        self._param_retries[name] = self._param_retries.get(name, 0) + 1
        self.get_logger().warn(
            'vpe_fix: %s=%s FAIL (attempt %d)' % (
                name, value, self._param_retries[name]))
        if self._param_retries[name] <= 2:
            self._trigger_pull_and_retry(name, value, ptype)
        else:
            self.get_logger().error(
                'vpe_fix: %s=%s gave up after %d attempts' % (
                    name, value, self._param_retries[name]))

    def _trigger_pull_and_retry(self, name, value, ptype):
        """Force-pull the MAVROS param cache, then re-issue the set."""
        if not self.pull_client.service_is_ready():
            # Defer retry by 3s if pull service isn't up yet.
            t_holder = {}
            def _fire():
                self._retry_param_once(name, value, ptype, t_holder['t'])
            t_holder['t'] = self.create_timer(3.0, _fire)
            return
        req = ParamPull.Request()
        req.force_pull = True
        fut = self.pull_client.call_async(req)
        fut.add_done_callback(
            lambda f, n=name, v=value, t=ptype: self._pull_done_then_set(f, n, v, t))

    def _pull_done_then_set(self, f, name, value, ptype):
        try:
            res = f.result()
            if res and res.success:
                self.get_logger().info(
                    'vpe_fix: param pull OK (%d params)' % res.param_received)
        except Exception:
            pass
        if (self._param_target.get(name) == value
                and not self._param_confirmed.get(name, False)):
            self._do_set_param(name, value, ptype)

    def _retry_param_once(self, name, value, ptype, timer):
        timer.cancel()
        if (self._param_target.get(name) == value
                and not self._param_confirmed.get(name, False)):
            self._do_set_param(name, value, ptype)

    def _set_ev_ctrl(self, value):
        """DEPRECATED. EKF2_EV_CTRL is set once in _queue_baseline_params and
        must NEVER be toggled in flight. Method retained only to flag any
        accidental re-introduction of mid-flight toggling.
        """
        self.get_logger().error(
            'vpe_fix: _set_ev_ctrl(%s) called -- IGNORED. '
            'EKF2_EV_CTRL must not be toggled in flight.' % value)

    # ------------------------------------------------------------------
    # Vision quality helpers
    # ------------------------------------------------------------------
    def _multi_marker_fresh(self):
        if self.markers_used_multi_time is None:
            return False
        age = (self.get_clock().now() - self.markers_used_multi_time).nanoseconds / 1e9
        return age <= _QUALITY_MULTI_TIMEOUT

    def _single_marker_fresh(self):
        if self.markers_used_time is None or not self.yaw_locked or self.markers_used < 1:
            return False
        age = (self.get_clock().now() - self.markers_used_time).nanoseconds / 1e9
        return age <= _QUALITY_SINGLE_TIMEOUT

    def _vision_quality_ok(self):
        """Any vision fresh enough to use (single or multi). Used by publish_timer."""
        return self._multi_marker_fresh() or self._single_marker_fresh()

    def _evaluate_gate(self):
        """Decide whether to publish vision_pose. EV_CTRL stays 15 always --
        toggling it mid-flight caused IMU-only dead-reckoning runaways
        (incident 2026-05-13). Vision flow is gated solely by this publish
        flag: when False, publish_timer stops emitting pose so PX4 EKF
        coasts on baro+IMU until vision returns.
        """
        if not self.armed:
            return True, 'disarmed (warm-up)'
        if not self.in_offboard:
            return False, 'armed in manual (no publish)'
        if self._multi_marker_fresh() or self._single_marker_fresh():
            return True, 'OFFBOARD + vision_ok'
        return False, 'OFFBOARD + vision_bad (publish suspended)'

    def _apply_gate(self, force=False):
        publish, reason = self._evaluate_gate()
        if publish != self.vpe_active or force:
            self.vpe_active = publish
            self.get_logger().info(
                'vpe_fix: %s -> publish=%s' % (reason, publish))

    def state_callback(self, msg):
        """Track arm state and flight mode. Gate is re-evaluated by the 1 Hz timer
        so we don't react instantly to vision flicker (would flood MAVLink)."""
        was_armed = self.armed
        self.armed = bool(msg.armed)
        self.in_offboard = (msg.mode == 'OFFBOARD')
        # On arm-state edge, apply gate immediately so warm-up→flight transition
        # is fast. Vision-quality flicker still goes through the 1 Hz timer.
        if self.armed != was_armed:
            self._apply_gate()

    def aruco_map_callback(self, msg):
        self.last_pose = msg.pose.pose
        self.last_pose_time = self.get_clock().now()
        if any(msg.pose.covariance):
            self.last_cov = list(msg.pose.covariance)
        else:
            self.last_cov = None

    def markers_callback(self, msg):
        self.visible_ids = [m.id for m in msg.markers]

    def markers_used_callback(self, msg):
        self.markers_used = int(msg.data)
        self.markers_used_time = self.get_clock().now()
        if self.markers_used >= 2:
            self.markers_used_multi_time = self.markers_used_time
        # Gate re-eval happens in the 1 Hz timer to throttle PARAM_SET load.

    def yaw_locked_callback(self, msg):
        self.yaw_locked = bool(msg.data)
        # Gate re-eval happens in the 1 Hz timer.

    def _gate_tick(self):
        """Periodic gate re-evaluation. Bounded PARAM_SET rate."""
        self._apply_gate()

    def publish_timer(self):
        # vpe_active perfectly reflects the publish decision from _apply_gate;
        # when False, EKF coasts on baro+IMU (EV_CTRL stays 15 throughout).
        if self.last_pose is None or not self.vpe_active:
            return
        age = (self.get_clock().now() - self.last_pose_time).nanoseconds / 1e9
        if age > _POSE_TIMEOUT:
            return

        out = PoseWithCovarianceStamped()
        out.header.stamp = self.get_clock().now().to_msg()
        out.header.frame_id = 'map'
        out.pose.pose = self.last_pose

        if self.last_cov is not None:
            out.pose.covariance = self.last_cov
        else:
            cov = [0.0] * 36
            cov[0]  = _POS_VARIANCE
            cov[7]  = _POS_VARIANCE
            cov[14] = _POS_Z_VARIANCE
            cov[21] = 1e6
            cov[28] = 1e6
            cov[35] = _YAW_VARIANCE
            out.pose.covariance = cov

        self.vpe_pub.publish(out)
        self.published += 1
        if self.published % 90 == 1:
            self.get_logger().info(
                'vpe_fix: published %d | z=%.3f | markers=%s' % (
                    self.published, out.pose.pose.position.z, self.visible_ids))


def main():
    rclpy.init()
    node = VpeFix()
    rclpy.spin(node)
    node.destroy_node()
    rclpy.shutdown()


if __name__ == '__main__':
    main()
