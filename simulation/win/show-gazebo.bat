@echo off
rem show-gazebo.bat - open the Gazebo 3D world window (GPU-accelerated).
rem Run AFTER run-sim.bat (the sim/server must already be up).
rem
rem ============================  READ FIRST  ============================
rem The 3D viewport needs the GPU. On WSLg the software renderer (llvmpipe)
rem leaves it BLANK, so this script forces the GPU (GALLIUM_DRIVER=d3d12).
rem
rem If your Intel graphics driver is old, GPU rendering here can HANG Windows
rem (hard freeze -> you must reboot). BEFORE using this, update the driver:
rem   1. Install "Intel Driver & Support Assistant" from intel.com/dsa
rem   2. Let it update the Intel Arc / graphics driver to the latest, reboot.
rem Recent Intel drivers have stable WSL (WSLg) GPU support.
rem
rem If it still freezes after updating: your GPU + WSL combo is unstable for
rem Gazebo's 3D window - use the browser dashboard (run-sim.bat) instead.
rem =====================================================================
setlocal

set "DISTRO=BumblebeeSim"
wsl -d %DISTRO% -e true >nul 2>nul
if errorlevel 1 set "DISTRO=Ubuntu-24.04"
wsl -d %DISTRO% -e true >nul 2>nul
if errorlevel 1 ( echo Run run-sim.bat first. & pause & exit /b 1 )

echo Opening the Gazebo 3D window on the NVIDIA RTX 4090 GPU...
echo (Rendering is pinned to the NVIDIA card, not the Intel Arc iGPU.)
echo If Windows still freezes, close this, reboot, and use the dashboard instead.
echo.
rem Pin GL rendering to the NVIDIA RTX 4090 (dGPU) via Mesa's d3d12 backend.
rem The Intel Arc iGPU path (GALLIUM_DRIVER=d3d12 alone) is what hung Windows.
rem GZ_SIM_RESOURCE_PATH: the GUI resolves model:// meshes itself; without this
rem export the window shows only sky and silently drops all world models.
rem DO NOT source ROS here: its vendored older gz libs (gz_*_vendor) break the
rem 3D view ("[WARN:COPY MODE]" + blank). System gz + resource path is enough.
wsl -d %DISTRO% -- bash -lc "export GZ_SIM_RESOURCE_PATH=$HOME/ros2_ws/install/bumblebee_sim/share/bumblebee_sim/models:$HOME/ros2_ws/install/bumblebee_sim/share/bumblebee_sim/worlds:$HOME/PX4-Autopilot/Tools/simulation/gz/models:$HOME/PX4-Autopilot/Tools/simulation/gz/worlds; export GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA QSG_RENDER_LOOP=basic; n=0; until pgrep -f 'gz sim.* -s' >/dev/null 2>&1 || [ $n -ge 30 ]; do sleep 1; n=$((n+1)); done; exec gz sim -g"

endlocal
