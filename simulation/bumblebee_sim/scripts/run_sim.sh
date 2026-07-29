#!/bin/bash
# run_sim.sh — convenience launcher for PX4 SITL + ROS 2 sim stack.
#
# Spawns three tmux panes:
#   1. PX4 SITL + Gazebo Harmonic (gz_x500_mono_cam_down + clover_aruco.sdf)
#   2. ros2 launch bumblebee_sim bumblebee_sim.launch.py gz_world:=$WORLD
#   3. shell ready for `python3 -c "import drone_sim, drone; ..."`
#
# Usage:
#   ~/ros2_ws/install/bumblebee_sim/share/bumblebee_sim/scripts/run_sim.sh
#
# Env overrides:
#   HEADLESS=1               # don't open Gazebo GUI
#   PX4_GZ_WORLD=other_world # replace clover_aruco
#   ROS_DOMAIN_ID=N
set -euo pipefail

PX4_DIR="${PX4_DIR:-$HOME/PX4-Autopilot}"
WS_DIR="${WS_DIR:-$HOME/ros2_ws}"
WORLD="${PX4_GZ_WORLD:-clover_aruco}"
SPAWN="${PX4_GZ_MODEL_POSE:-0,0,0.15,0,0,0}"
HEADLESS="${HEADLESS:-1}"
TMUX_SESSION="${TMUX_SESSION:-bumblebee_sim}"
# One DDS for the whole stack: clients (sim-run/.bashrc) force cyclonedds, so
# the stack must run it too - mixed RMW = every service call times out.
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"

if ! command -v tmux >/dev/null; then
    echo "tmux is required: sudo apt install -y tmux" >&2
    exit 1
fi

if [ ! -d "$PX4_DIR" ]; then
    echo "PX4-Autopilot not found at $PX4_DIR" >&2
    exit 1
fi

# Resource path for our world + ArUco models.
SIM_SHARE="$(ros2 pkg prefix bumblebee_sim 2>/dev/null || echo /opt/ros/jazzy)/share/bumblebee_sim"
export GZ_SIM_RESOURCE_PATH="${GZ_SIM_RESOURCE_PATH:+$GZ_SIM_RESOURCE_PATH:}$SIM_SHARE/models:$SIM_SHARE/worlds"

# PX4's px4-rc.gzsim opens the gz GUI only when HEADLESS is UNSET (it tests
# [ -z "$HEADLESS" ]), so HEADLESS=0 must not reach PX4 at all.
HEADLESS_ENV=""
[ "$HEADLESS" = "1" ] && HEADLESS_ENV="HEADLESS=1"

PX4_CMD="cd $PX4_DIR && \
    GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA \
    GZ_SIM_RESOURCE_PATH='$GZ_SIM_RESOURCE_PATH' \
    PX4_GZ_WORLD=$WORLD \
    PX4_GZ_MODEL_POSE='$SPAWN' \
    $HEADLESS_ENV \
    make px4_sitl gz_x500_mono_cam_down"

ROS_CMD="source /opt/ros/jazzy/setup.bash && \
    source $WS_DIR/install/setup.bash && \
    ros2 launch bumblebee_sim bumblebee_sim.launch.py gz_world:=$WORLD"

FLIGHT_CMD="source /opt/ros/jazzy/setup.bash && \
    source $WS_DIR/install/setup.bash && \
    export PYTHONPATH=\$PYTHONPATH:$SIM_SHARE/python && \
    cd $WS_DIR/src/bumblebee/examples && \
    echo 'Try: python3 -c \"import drone_sim, drone; drone.takeoff(1.0); drone.safe_land()\"'"

tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TMUX_SESSION" -n px4 "bash -c '$PX4_CMD; exec bash'"
tmux split-window -t "$TMUX_SESSION:px4" -h "bash -c 'sleep 8; $ROS_CMD; exec bash'"
tmux split-window -t "$TMUX_SESSION:px4" -v "bash -c 'sleep 16; $FLIGHT_CMD; exec bash'"
tmux select-layout -t "$TMUX_SESSION:px4" tiled
tmux new-window -d -t "$TMUX_SESSION" -n prearm "bash -c 'sleep 28; SKIP_REAL_PARAMS=1 bash $SIM_SHARE/scripts/sim_prearm.sh >/tmp/prearm.log 2>&1'"
tmux new-window -d -t "$TMUX_SESSION" -n vpe "bash -c 'sleep 20; while true; do python3 $SIM_SHARE/python/vpe_groundtruth.py >>/tmp/vpe_gt.log 2>&1; sleep 2; done'"
tmux new-window -d -t "$TMUX_SESSION" -n leds "bash -c 'sleep 35; python3 $SIM_SHARE/python/led_static.py >/tmp/led_static.log 2>&1'"

echo "tmux session '$TMUX_SESSION' started. Attach: tmux attach -t $TMUX_SESSION"
