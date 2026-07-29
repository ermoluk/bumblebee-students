#!/bin/bash
# setup_env.sh — one-shot environment setup for the sim VM.
#
# After running this, every NEW shell on the VM auto-loads:
#   - ROS 2 Jazzy
#   - bumblebee + bumblebee_sim workspace
#   - CycloneDDS (works around Fast-DDS MAVROS conflict)
#   - PYTHONPATH for drone_sim shim + production drone.py
#   - cd alias to examples/ directory
#   - sim-run helper that auto-imports drone_sim before running a script
#
# Run once on the VM:
#   bash ~/ros2_ws/install/bumblebee_sim/share/bumblebee_sim/scripts/setup_env.sh
set -euo pipefail

WS_DIR="${WS_DIR:-$HOME/ros2_ws}"
SIM_SHARE="$(ros2 pkg prefix bumblebee_sim 2>/dev/null || true)/share/bumblebee_sim"
EXAMPLES="$WS_DIR/src/bumblebee/examples"

MARKER="# >>> bumblebee_sim env >>>"
END_MARKER="# <<< bumblebee_sim env <<<"

# Strip any previous block.
if grep -q "$MARKER" "$HOME/.bashrc"; then
    sed -i "/$MARKER/,/$END_MARKER/d" "$HOME/.bashrc"
fi

cat >> "$HOME/.bashrc" <<EOF
$MARKER
# Auto-source ROS 2 + bumblebee workspace, set CycloneDDS.
source /opt/ros/jazzy/setup.bash
[ -f $WS_DIR/install/setup.bash ] && source $WS_DIR/install/setup.bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
# drone_sim shim (auto-patches drone.py I2C calls to no-ops in sim).
export PYTHONPATH="\$PYTHONPATH:$SIM_SHARE/python:$EXAMPLES"
# 'bb' jumps into examples/, ready to run any flight script.
alias bb='cd $EXAMPLES'
# 'sim-run <script>' = like running on the real drone, but I2C is stubbed.
sim-run() {
    if [ \$# -eq 0 ]; then
        echo "usage: sim-run <script.py> [args...]" >&2
        return 1
    fi
    local script="\$1"; shift
    python3 -c "import drone_sim, runpy; runpy.run_path('\$script', run_name='__main__')" "\$@"
}
$END_MARKER
EOF

echo "Updated $HOME/.bashrc"
echo "Reload with: source ~/.bashrc"
echo ""
echo "After reload:"
echo "  bb                                              # cd to examples/"
echo "  sim-run flight_marker.py                        # run script with drone_sim shim"
echo "  python3 -c 'import drone_sim, drone; print(drone.get_telemetry().mode)'"
