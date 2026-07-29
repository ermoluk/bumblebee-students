#!/bin/bash
# selftest.sh — проверка, что портированный стек жив (запускать ВНУТРИ WSL,
# пока симулятор работает — т.е. после run-sim.bat).
#
#   bash selftest.sh          # проверки нод/топиков
#   bash selftest.sh --fly    # + короткий полёт: takeoff 1м → safe_land
set -uo pipefail

FLY=0
[ "${1:-}" = "--fly" ] && FLY=1

set +u
source /opt/ros/jazzy/setup.bash
[ -f "$HOME/ros2_ws/install/setup.bash" ] && source "$HOME/ros2_ws/install/setup.bash"
set -u
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"

PASS=0; FAIL=0
ok()   { echo "  [ OK ] $1"; PASS=$((PASS+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "== Ноды =="
NODES="$(timeout 10 ros2 node list 2>/dev/null || true)"
for n in mavros simple_offboard pose_to_tf aruco_detect; do
    echo "$NODES" | grep -q "$n" && ok "нода $n" || bad "нода $n не найдена (стек запущен? run-sim.bat)"
done

echo "== Топики =="
TOPICS="$(timeout 10 ros2 topic list 2>/dev/null || true)"
for t in /main_camera/image_raw /main_camera/camera_info /aruco_detect/markers /mavros/state /clock; do
    echo "$TOPICS" | grep -qx "$t" && ok "топик $t" || bad "топик $t отсутствует"
done

echo "== Данные в топиках =="
if timeout 15 ros2 topic echo --once /main_camera/image_raw >/dev/null 2>&1; then
    ok "камера публикует кадры"
else
    bad "нет кадров в /main_camera/image_raw за 15с (Gazebo-мост? sensors-плагин?)"
fi
if timeout 15 ros2 topic echo --once /mavros/state >/dev/null 2>&1; then
    ok "MAVROS публикует state (связь с PX4 есть)"
else
    bad "нет /mavros/state за 15с (PX4 SITL запущен? порт 14580?)"
fi

if [ "$FLY" = "1" ]; then
    echo "== Полёт: takeoff 1.0 → safe_land =="
    TMP="$(mktemp /tmp/selftest_flight_XXXX.py)"
    cat > "$TMP" <<'EOF'
import drone
drone.takeoff(1.0)
drone.safe_land()
print("FLIGHT_OK")
EOF
    # sim-run часто выходит с ненулевым кодом из-за шумного закрытия rclpy-потока
    # ("cannot schedule new futures after shutdown"), даже когда полёт прошёл.
    # Судим по маркеру FLIGHT_OK в выводе, а не по коду возврата (+ pipefail).
    sim-run "$TMP" > /tmp/selftest_flight.log 2>&1 || true
    if grep -q FLIGHT_OK /tmp/selftest_flight.log; then
        ok "полёт прошёл (лог: /tmp/selftest_flight.log)"
    else
        bad "полёт не удался — смотри /tmp/selftest_flight.log"
    fi
    rm -f "$TMP"
fi

echo
echo "Итого: $PASS OK, $FAIL FAIL"
[ "$FAIL" = "0" ]
