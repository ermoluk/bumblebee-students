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

# load_real_params.sh — push real-drone flight params into PX4 SITL.
#
# Reads $PARAMS_FILE (default: install/bumblebee_sim/share/bumblebee_sim/params/imb_real.txt)
# and sends each `param set NAME VALUE` line into pxh prompt via tmux send-keys.
# Ends with `param save` so settings persist across SITL restarts.
#
# Intended to be called by sim_prearm.sh BEFORE its sim-specific overrides
# (EKF2_EV_CTRL=15, EKF2_MAG_CHECK=0, etc.), so the overrides win.
#
# Usage:
#   ~/ros2_ws/install/bumblebee_sim/share/bumblebee_sim/scripts/load_real_params.sh
#   PARAMS_FILE=/path/to/other.txt ~/.../load_real_params.sh
#
# Requires tmux session 'bumblebee_sim' with px4 pane (started by run_sim.sh).
set -eo pipefail

SESSION="${TMUX_SESSION:-bumblebee_sim}"
PANE="${SIM_PANE:-bumblebee_sim:px4.0}"

# Resolve params file: env override, then install path, then src fallback.
if [ -z "${PARAMS_FILE:-}" ]; then
    for cand in \
        "$HOME/ros2_ws/install/bumblebee_sim/share/bumblebee_sim/params/imb_real.txt" \
        "$HOME/ros2_ws/src/bumblebee_sim/params/imb_real.txt"; do
        if [ -f "$cand" ]; then PARAMS_FILE="$cand"; break; fi
    done
fi

if [ ! -f "${PARAMS_FILE:-}" ]; then
    echo "params file not found (tried install + src). Set PARAMS_FILE explicitly." >&2
    exit 1
fi

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "tmux session '$SESSION' not running; start sim first via run_sim.sh" >&2
    exit 1
fi

# PX4 nsh in SITL is single-threaded and can starve on rapid input;
# at 50ms/cmd × 448 cmds, EKF logging blocks command echo and the stream
# silently freezes. Throttle to 120ms/cmd (~54s for 448 params) and pause
# 1s every 30 commands so the param subsystem flushes.
echo "Loading real-drone params from: $PARAMS_FILE"
count=0
while IFS= read -r line; do
    case "$line" in
        ""|"#"*) continue ;;
    esac
    tmux send-keys -t "$PANE" "$line" Enter
    count=$((count + 1))
    if [ $((count % 30)) -eq 0 ]; then
        sleep 1
    else
        sleep 0.12
    fi
done < "$PARAMS_FILE"

# Give PX4 time to drain the final batch before sim_prearm proceeds.
sleep 2
echo "Loaded $count param set lines."
