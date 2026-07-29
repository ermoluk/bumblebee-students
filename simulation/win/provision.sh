#!/bin/bash
# provision.sh — разворачивает полный SITL-стек Bumblebee внутри WSL2 Ubuntu 24.04.
#
# Ставит: ROS 2 Jazzy + Gazebo Harmonic + MAVROS + rosbridge + PX4 SITL (пин на тег),
# распаковывает seed-архив исходников в ~/ros2_ws, собирает workspace и включает
# то же окружение, что на сим-VM (setup_env.sh).
#
# Запускается install.ps1 автоматически, но можно и руками изнутри Ubuntu:
#   bash provision.sh /mnt/c/path/to/bumblebee_src.tar.gz
#
# Идемпотентен: повторный запуск доустанавливает недостающее.
#
# Env overrides:
#   PX4_TAG=v1.16.0    # тег PX4-Autopilot (нужна модель gz_x500_mono_cam_down)
#   WS_DIR=~/ros2_ws
set -euo pipefail

SEED="${1:-}"
PX4_TAG="${PX4_TAG:-v1.16.0}"
WS_DIR="${WS_DIR:-$HOME/ros2_ws}"
PX4_DIR="${PX4_DIR:-$HOME/PX4-Autopilot}"

log() { echo -e "\n\033[1;33m[provision] $*\033[0m"; }

# ── 0. Проверки окружения ────────────────────────────────────────────────────
if [ "$(id -u)" = "0" ]; then
    echo "provision.sh нужно запускать от обычного пользователя (не root):" >&2
    echo "он настраивает ~/.bashrc и ~/ros2_ws этого пользователя." >&2
    exit 1
fi

. /etc/os-release
if [ "${VERSION_ID:-}" != "24.04" ]; then
    echo "Ожидается Ubuntu 24.04 (Jazzy), найдено: ${PRETTY_NAME:-unknown}." >&2
    echo "Продолжаю через 5 с (Ctrl+C для отмены)…" >&2
    sleep 5
fi

if [ -n "$SEED" ] && [ ! -f "$SEED" ]; then
    echo "Seed-архив не найден: $SEED" >&2
    exit 1
fi

sudo -v   # спросить пароль один раз в начале

# ── 1. Apt-репозитории: ROS 2 + OSRF (Gazebo) ────────────────────────────────
log "Базовые пакеты и репозитории"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl gnupg lsb-release ca-certificates software-properties-common

if ! dpkg -s ros2-apt-source >/dev/null 2>&1; then
    log "Подключаю apt-репозиторий ROS 2"
    ROS_APT_VER="$(curl -fsSL https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
        | grep -F '"tag_name"' | awk -F'"' '{print $4}')"
    curl -fsSL -o /tmp/ros2-apt-source.deb \
        "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_VER}/ros2-apt-source_${ROS_APT_VER}.$(lsb_release -cs)_all.deb"
    sudo apt-get install -y /tmp/ros2-apt-source.deb
fi

if [ ! -f /etc/apt/sources.list.d/gazebo-stable.list ]; then
    log "Подключаю apt-репозиторий Gazebo (packages.osrfoundation.org)"
    sudo curl -fsSL https://packages.osrfoundation.org/gazebo.gpg \
        -o /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" \
        | sudo tee /etc/apt/sources.list.d/gazebo-stable.list >/dev/null
fi

# ── 2. ROS 2 Jazzy + Gazebo Harmonic + зависимости стека ─────────────────────
log "Ставлю ROS 2 Jazzy, Gazebo Harmonic, MAVROS, rosbridge (долго, один раз)"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ros-jazzy-desktop \
    ros-jazzy-ros-gz \
    gz-harmonic \
    ros-jazzy-mavros ros-jazzy-mavros-extras ros-jazzy-mavros-msgs \
    ros-jazzy-rosbridge-server \
    ros-jazzy-rmw-cyclonedds-cpp \
    ros-jazzy-cv-bridge ros-jazzy-image-proc ros-jazzy-image-geometry \
    python3-colcon-common-extensions python3-rosdep python3-vcstool \
    python3-opencv python3-lxml python3-pip \
    tmux git build-essential cmake ccache

log "pymavlink via pip (no apt package python3-pymavlink on noble)"
sudo pip3 install --break-system-packages --no-input pymavlink

log "Датасеты GeographicLib для MAVROS"
sudo bash /opt/ros/jazzy/lib/mavros/install_geographiclib_datasets.sh

# tf2_web_republisher: в apt есть не для всех дистро — fallback на сборку из исходников.
mkdir -p "$WS_DIR/src"
if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ros-jazzy-tf2-web-republisher 2>/dev/null; then
    if [ ! -d "$WS_DIR/src/tf2_web_republisher" ]; then
        log "tf2_web_republisher нет в apt — клонирую в workspace"
        git clone --depth 1 -b ros2 https://github.com/RobotWebTools/tf2_web_republisher.git \
            "$WS_DIR/src/tf2_web_republisher"
    fi
fi

# ── 3. PX4-Autopilot SITL (пин на тег) ───────────────────────────────────────
if [ ! -d "$PX4_DIR" ]; then
    log "Клонирую PX4-Autopilot $PX4_TAG"
    git clone --recursive --branch "$PX4_TAG" --depth 1 --shallow-submodules \
        https://github.com/PX4/PX4-Autopilot.git "$PX4_DIR"
fi

# Модель с нижней камерой обязана существовать в этом теге — иначе стек не полетит.
if ! ls "$PX4_DIR"/ROMFS/px4fmu_common/init.d-posix/airframes/ | grep -q "gz_x500_mono_cam_down"; then
    echo "В PX4 $PX4_TAG нет airframe gz_x500_mono_cam_down — возьмите тег новее (PX4_TAG=...)" >&2
    exit 1
fi

log "Зависимости PX4 (Tools/setup/ubuntu.sh)"
bash "$PX4_DIR/Tools/setup/ubuntu.sh" --no-nuttx

# PX4 --shallow-submodules leaves the NuttX submodule без тегов; генератор
# версии (px_update_git_header.py) падает с IndexError даже для SITL. Чиним.
NX_DIR="$PX4_DIR/platforms/nuttx/NuttX/nuttx"
if [ -e "$NX_DIR/.git" ] && [ "$(git -C "$NX_DIR" tag | wc -l)" -eq 0 ]; then
    log "Дотягиваю NuttX-теги сабмодуля (иначе падает генерация версии PX4)"
    git -C "$NX_DIR" fetch --tags --depth 1 origin || true
fi

log "Прекомпиляция PX4 SITL (10–20 мин; в золотом образе студенты этого не ждут)"
make -C "$PX4_DIR" px4_sitl

# ── 4. Workspace: seed → ~/ros2_ws, сборка ───────────────────────────────────
if [ -n "$SEED" ]; then
    log "Распаковываю исходники в $WS_DIR"
    tar -xzf "$SEED" -C "$WS_DIR"
elif [ ! -d "$WS_DIR/src/bumblebee_sim" ]; then
    echo "Seed-архив не передан, а $WS_DIR/src/bumblebee_sim не существует." >&2
    echo "Запустите: bash provision.sh /путь/к/bumblebee_src.tar.gz" >&2
    exit 1
fi

# Камера: в PX4 v1.16 модель x500_mono_cam_down называет сенсор камеры "imager",
# а launch-мост по умолчанию подписан на .../sensor/camera/image (пусто) — кадры
# не доходят до /main_camera/image_raw. Публикующий кадры сенсор — "imager".
_LF="$WS_DIR/src/bumblebee_sim/launch/bumblebee_sim.launch.py"
if [ -f "$_LF" ] && grep -q '/sensor/camera/' "$_LF"; then
    log "Правлю топик камеры в launch на сенсор 'imager' (PX4 v1.16)"
    sed -i 's#/sensor/camera/#/sensor/imager/#g' "$_LF"
fi

set +u; source /opt/ros/jazzy/setup.bash; set -u

log "rosdep (зависимости workspace)"
[ -f /etc/ros/rosdep/sources.list.d/20-default.list ] || sudo rosdep init
rosdep update || true
# skip: gazebo_* — Gazebo Classic из описания реального дрона, в симе не нужен;
#       smbus2 — I2C реального борта, в симе застаблен drone_sim'ом.
rosdep install --from-paths "$WS_DIR/src" --ignore-src -y \
    --skip-keys "gazebo_ros gazebo_plugins python3-smbus2" \
    || log "rosdep закончился с предупреждениями — продолжаю, colcon покажет реальные проблемы"

log "colcon build (aruco_pose + bumblebee + bumblebee_sim и их зависимости)"
cd "$WS_DIR"
# tf2_web_republisher попадает в сборку только если его пришлось клонировать
# (иначе он стоит из apt и в src/ его нет).
EXTRA_PKGS=""
[ -d "$WS_DIR/src/tf2_web_republisher" ] && EXTRA_PKGS="tf2_web_republisher"
# aruco_pose обязателен: drone.py и vpe_fix.py делают `from aruco_pose.msg import ...`,
# но bumblebee не объявляет его зависимостью, поэтому без явного указания
# --packages-up-to его пропускает и полёт падает с ModuleNotFoundError.
# bumblebee_description — пакет ROS 1 (catkin) и на Jazzy не собирается; не трогаем.
colcon build --symlink-install --packages-up-to aruco_pose bumblebee bumblebee_sim $EXTRA_PKGS \
    --cmake-args -DCMAKE_BUILD_TYPE=RelWithDebInfo

# PX4's gz_env.sh безусловно перезаписывает PX4_GZ_WORLDS на свою папку
# Tools/simulation/gz/worlds, поэтому env-переопределение мира невозможно —
# кладём симлинк нашего мира прямо туда.
log "Симлинк мира aruco_bumblebee в папку миров PX4"
ln -sf "$WS_DIR/install/bumblebee_sim/share/bumblebee_sim/worlds/aruco_bumblebee.sdf" \
       "$PX4_DIR/Tools/simulation/gz/worlds/aruco_bumblebee.sdf"

# ── 5. Окружение пользователя: тот же setup_env.sh, что на сим-VM ────────────
log "Настраиваю ~/.bashrc (setup_env.sh)"
set +u; source "$WS_DIR/install/setup.bash"; set -u
bash "$WS_DIR/install/bumblebee_sim/share/bumblebee_sim/scripts/setup_env.sh"

# colcon --symlink-install делает install/<pkg>/lib/<pkg>/<exe> симлинком на
# исходник. Исходники приезжают из seed-архива (собран на macOS) без бита +x,
# и ros2 launch не находит python-ноды ("executable '<x>.py' not found on the
# libexec directory") — весь launch падает. Восстанавливаем бит исполняемости.
log "Восстанавливаю бит исполняемости у установленных нод/скриптов"
for _d in "$WS_DIR"/install/*/lib/*; do
    [ -d "$_d" ] || continue
    for _f in "$_d"/*; do
        _t="$(readlink -f "$_f" 2>/dev/null || echo "$_f")"
        [ -f "$_t" ] && [ ! -x "$_t" ] && chmod +x "$_t"
    done
done
chmod +x "$WS_DIR"/install/*/share/*/scripts/* 2>/dev/null || true

# sim-run доступен как команда и из не-интерактивных шеллов.
sudo ln -sf "$WS_DIR/install/bumblebee_sim/share/bumblebee_sim/scripts/sim-run" /usr/local/bin/sim-run

# ── 6. /etc/wsl.conf — дефолтный пользователь переживает export/import ───────
if ! grep -q "^\[user\]" /etc/wsl.conf 2>/dev/null; then
    log "Прописываю default-пользователя в /etc/wsl.conf (для золотого образа)"
    printf '[user]\ndefault=%s\n' "$USER" | sudo tee -a /etc/wsl.conf >/dev/null
fi

log "Готово!"
echo "Дальше:"
echo "  1) Запуск симулятора: из Windows двойной клик по win\\run-sim.bat"
echo "     (или изнутри WSL: HEADLESS=0 $WS_DIR/install/bumblebee_sim/share/bumblebee_sim/scripts/run_sim.sh)"
echo "  2) Проверка: bash $(cd "$(dirname "$0")" && pwd)/selftest.sh"
echo "  3) Раскатка на класс: win\\export-golden.ps1 → студентам install.ps1 -Image bumblebee-sim.tar"
