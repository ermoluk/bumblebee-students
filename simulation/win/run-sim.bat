@echo off
rem run-sim.bat - launch the Bumblebee simulator (PX4 SITL + Gazebo + ROS 2) in WSL
rem and open the Gazebo 3D window rendered on the NVIDIA RTX 4090.
rem
rem Why the NVIDIA pin: WSLg defaults to the llvmpipe SOFTWARE OpenGL renderer, on
rem which the Gazebo 3D viewport stays BLANK. Forcing the Intel Arc iGPU renders but
rem HANGS Windows. The discrete NVIDIA RTX 4090 renders the world AND stays stable,
rem so the GUI is pinned to it (MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA).
rem run_sim.sh is installed without the +x bit, so it is launched via `bash`.
setlocal

set "DISTRO=BumblebeeSim"
wsl -d %DISTRO% -e true >nul 2>nul
if errorlevel 1 set "DISTRO=Ubuntu-24.04"
wsl -d %DISTRO% -e true >nul 2>nul
if errorlevel 1 (
    echo.
    echo No Bumblebee WSL distro found ^(looked for BumblebeeSim and Ubuntu-24.04^).
    echo Run the installer first:  powershell -ExecutionPolicy Bypass -File Install-BumblebeeSim.ps1
    echo.
    pause
    exit /b 1
)

echo Starting Bumblebee sim in %DISTRO% ...
echo The Gazebo 3D window (NVIDIA RTX 4090) opens in ~40-60s. Dashboard: http://localhost:8000/gcs.html

rem 1) Start the stack headless (PX4 server + ROS 2 + flight shell) in a tmux session.
rem    PX4_GZ_WORLD=clover_aruco -> the full world (grass field, cable towers,
rem    landing pad, ArUco markers). Use aruco_bumblebee for the bare marker world.
wsl -d %DISTRO% -- bash -c "source /opt/ros/jazzy/setup.bash && source $HOME/ros2_ws/install/setup.bash && HEADLESS=1 PX4_GZ_WORLD=clover_aruco bash $HOME/ros2_ws/install/bumblebee_sim/share/bumblebee_sim/scripts/run_sim.sh"

rem 2) Open the Gazebo 3D world window on the NVIDIA RTX 4090 (waits for the server).
rem    GZ_SIM_RESOURCE_PATH: the GUI process resolves model:// meshes ITSELF, so it
rem    needs the same resource path as the server. Without it the window shows only
rem    the sky (procedural, no assets) and silently drops every model of the world.
rem    DO NOT source ROS here: /opt/ros/jazzy puts its VENDORED (older) gz libs on
rem    LD_LIBRARY_PATH (gz_sim_vendor 8.11, gz_rendering_vendor 8.2.3 vs system
rem    8.14) - that mix breaks the 3D view ("[WARN:COPY MODE]" + blank viewport).
rem    The GUI needs only the system gz + this resource path.
start "Gazebo Sim" wsl -d %DISTRO% -- bash -lc "export GZ_SIM_RESOURCE_PATH=$HOME/ros2_ws/install/bumblebee_sim/share/bumblebee_sim/models:$HOME/ros2_ws/install/bumblebee_sim/share/bumblebee_sim/worlds:$HOME/PX4-Autopilot/Tools/simulation/gz/models:$HOME/PX4-Autopilot/Tools/simulation/gz/worlds; export GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA QSG_RENDER_LOOP=basic; n=0; until pgrep -f 'gz sim.* -s' >/dev/null 2>&1 || [ $n -ge 40 ]; do sleep 1; n=$((n+1)); done; sleep 3; exec gz sim -g"

rem 3) Attach the terminal so you see the PX4 / ROS / flight tmux panes.
wsl -d %DISTRO% -- bash -c "exec tmux attach -t bumblebee_sim"

endlocal
