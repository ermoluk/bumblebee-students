#!/bin/bash
# make_seed.sh — собирает seed-архив исходников для Windows-порта (запускать на Mac).
#
# Кладёт в bumblebee_src.tar.gz:
#   src/aruco_pose            ┐
#   src/bumblebee             │ из /Users/iermoliuk/bumblebee/ros2_ws/src
#   src/bumblebee_bridge      │ (bumblebee/examples/drone.py едет внутри пакета)
#   src/bumblebee_description ┘
#   src/bumblebee_sim         — из /Users/iermoliuk/bumblebee_sim/bumblebee_sim
#
# Архив переносится на Windows-машину преподавателя вместе с папкой win/
# (USB/облако) и распаковывается provision.sh в ~/ros2_ws внутри WSL.
#
# Usage:
#   bash make_seed.sh [выходной .tar.gz]   # default: win/bumblebee_src.tar.gz
set -euo pipefail

BB_DIR="${BB_DIR:-$HOME/bumblebee}"
SIM_DIR="${SIM_DIR:-$HOME/bumblebee_sim}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HERE/bumblebee_src.tar.gz}"

for d in "$BB_DIR/ros2_ws/src" "$SIM_DIR/bumblebee_sim"; do
    [ -d "$d" ] || { echo "make_seed: не найдено: $d" >&2; exit 1; }
done

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/src"

for pkg in aruco_pose bumblebee bumblebee_bridge bumblebee_description; do
    [ -d "$BB_DIR/ros2_ws/src/$pkg" ] || { echo "make_seed: нет пакета $pkg" >&2; exit 1; }
    cp -R "$BB_DIR/ros2_ws/src/$pkg" "$STAGE/src/"
done
cp -R "$SIM_DIR/bumblebee_sim" "$STAGE/src/bumblebee_sim"

# Чистим мусор, которому нечего делать в образе.
find "$STAGE" \( -name '__pycache__' -o -name '.DS_Store' -o -name '*.pyc' \
    -o -name '.git' -o -name 'COLCON_IGNORE' \) -prune -exec rm -rf {} + 2>/dev/null || true

tar -czf "$OUT" -C "$STAGE" src

# Самопроверка: все 5 package.xml и production drone.py на месте.
for want in \
    src/aruco_pose/package.xml \
    src/bumblebee/package.xml \
    src/bumblebee_bridge/package.xml \
    src/bumblebee_description/package.xml \
    src/bumblebee_sim/package.xml \
    src/bumblebee/examples/drone.py \
    src/bumblebee_sim/worlds/aruco_bumblebee.sdf; do
    tar -tzf "$OUT" "$want" >/dev/null 2>&1 \
        || { echo "make_seed: в архиве нет $want" >&2; exit 1; }
done

echo "OK: $OUT ($(du -h "$OUT" | cut -f1))"
