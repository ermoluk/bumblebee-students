#!/bin/bash
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

# sim_prearm.sh — apply PX4 SITL params for headless arming on macOS sim.
#
# Without these, PX4 preflight blocks arming with:
#   - "Strong magnetic interference" (sim mag too noisy)
#   - "no heading reference"        (mag fix doesn't settle)
#   - "No connection to the GCS"    (mavros heartbeat not classified as GCS)
#
# Usage:
#   ~/ros2_ws/install/bumblebee_sim/share/bumblebee_sim/scripts/sim_prearm.sh
# Requires:
#   - tmux session 'bumblebee_sim' with px4 pane 0 (started by run_sim.sh)
set -eo pipefail

SESSION="${TMUX_SESSION:-bumblebee_sim}"
PANE="${SIM_PANE:-bumblebee_sim:px4.0}"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "tmux session '$SESSION' not running; start sim first via run_sim.sh" >&2
    exit 1
fi

# Phase 1: Load real-drone params (control gains, EKF2 tuning, commander).
# Done FIRST so our sim-specific overrides below win for the few params we
# need to differ in sim (EKF2_EV_CTRL, EKF2_HGT_REF, MAG/GPS checks).
# Skipped via SKIP_REAL_PARAMS=1 for clean A/B testing against PX4 defaults.
if [ "${SKIP_REAL_PARAMS:-0}" != "1" ]; then
    LOADER="$(dirname "$0")/load_real_params.sh"
    if [ -x "$LOADER" ]; then
        "$LOADER" || echo "warning: load_real_params.sh failed, continuing with sim overrides" >&2
    else
        echo "warning: $LOADER not executable, skipping real-drone params" >&2
    fi
fi

# Phase 2: sim-specific overrides — applied AFTER real params so we win.
# Each line is sent as a pxh> command. Order matters.
PX4_CMDS=(
    "param set EKF2_MAG_TYPE 1"          # use sim magnetometer
    "param set EKF2_MAG_CHECK 0"         # ignore mag-field-strength preflight
    "param set EKF2_GPS_CHECK 0"         # don't block on strict GPS pre-arm
    "param set COM_ARM_WO_GPS 1"         # allow arming without strict GPS
    "param set COM_RC_IN_MODE 4"         # disable RC requirement
    "param set NAV_DLL_ACT 0"            # no GCS heartbeat required
    "param set NAV_RCL_ACT 0"            # no RC link required
    "param set COM_RCL_EXCEPT 4"         # OFFBOARD ignores RC loss
    # External vision fusion — vpe_groundtruth.py feeds VPE so EKF can hold
    # XY position during OFFBOARD. Without these PX4 ignores VPE input
    # and horizontal flight drifts (GPS/IMU only is too noisy).
    # EV_CTRL=15 enables full vision fusion. Empirically this works in sim
    # even when only sending VISION_POSITION_ESTIMATE (no separate VISION_SPEED).
    "param set EKF2_EV_CTRL 15"          # full external vision fusion
    "param set EKF2_HGT_REF 3"           # use vision z as primary altitude
    "param save"
)

for cmd in "${PX4_CMDS[@]}"; do
    tmux send-keys -t "$PANE" "$cmd" Enter
    sleep 0.4
done

echo "Applied. Within ~5s PX4 should report: 'INFO [commander] Ready for takeoff!'"
