# Bumblebee Sim — Windows 11

PX4 drone simulator (Gazebo + ROS 2) in WSL2. Students use the same `drone.py`
API as on the real drone.

## Install

Open **PowerShell** in this folder:

```powershell
powershell -ExecutionPolicy Bypass -File Install-BumblebeeSim.ps1
```

It finds `bumblebee-sim.tar` next to the script and installs in minutes.
If WSL was never installed on this PC, run the first time **as Administrator**
(it enables WSL and asks for a reboot; after the reboot run it again, no admin).

Build from source instead (30–60 min, needs `bumblebee_src.tar.gz`):

```powershell
powershell -ExecutionPolicy Bypass -File Install-BumblebeeSim.ps1 -Build
```

## Start the simulator

Double-click **`run-sim.bat`**. Wait ~60 s — the Gazebo window opens:
grass field, landing pad, ArUco markers, drone with nav LEDs on the pad.

- Dashboard (drone camera, telemetry): http://localhost:8000/gcs.html
- If the Gazebo window is missing or frozen: run **`show-gazebo.bat`**.

## Fly

Open a terminal, enter the sim:

```powershell
wsl -d BumblebeeSim
```

then:

```bash
sim-run flight.py        # full flight: takeoff 1.5 m -> hover -> precision land
```

or one line without a file:

```bash
python3 -c "import drone_sim, drone; drone.takeoff(1.0); drone.safe_land()"
```

More examples: `~/ros2_ws/src/bumblebee/examples/flight/`.

**Note:** the very first flight after starting the sim may fail with a service
timeout — just run it again.

## LED

LED colors show up directly on the 3D drone model. Nav lights (green front,
red rear, cyan sides) turn on automatically at startup.

```bash
sim-run led_strip.py     # demo: running fire + police blinker (30 s)
```

From your own script:

```python
import drone_sim, drone                                # drone_sim first!

drone.set_led(drone.STRIP_ALL, drone.LED_ALL, 255, 0, 0)   # all strips red
drone.set_led(drone.LED_3, 5, 0, 0, 100)                   # strip 3 blue
drone.led_off()                                            # all off
```

`set_led(strip, pixel, r, g, b)`: strip is `LED_1`..`LED_6` or `STRIP_ALL`;
pixel is 0–10 or `LED_ALL` (ignored in sim — one color per strip); r,g,b 0–255.

**Always launch scripts with `sim-run`** (it loads the sim bridge). Plain
`python3` works only if the script does `import drone_sim` before `import drone`.

## Troubleshooting

- **Sim extremely slow, flights time out** — check GPU memory on Windows:
  `nvidia-smi`. Local LLMs (Ollama, LM Studio) eat all VRAM and break the sim
  renderer. Unload them, then `wsl --shutdown` and start `run-sim.bat` again.
- **"No Bumblebee WSL distro found"** — run the installer first.
- **Gazebo window empty, invisible, or shows only sky** — `wsl --shutdown`,
  then `run-sim.bat`.
- **Flight aborts with "EKF z below ground" / crazy altitude** — restart the
  sim (`run-sim.bat`): fresh estimator state.
- **Rebuild after editing sources:**

```bash
wsl -d BumblebeeSim -- bash -lc "cd ~/ros2_ws && colcon build --symlink-install --packages-up-to aruco_pose bumblebee bumblebee_sim"
```

## Files

| File | Purpose |
|------|---------|
| `Install-BumblebeeSim.ps1` | installer (image **or** `-Build` from source) |
| `bumblebee-sim.tar` | golden WSL image (all fixes included) |
| `bumblebee_src.tar.gz` | workspace sources (for `-Build`) |
| `run-sim.bat` | start the simulator (double-click) |
| `show-gazebo.bat` | reopen the Gazebo window |
| `selftest.sh` | stack check (`--fly` = test flight) |
| `export-golden.ps1` | export a new golden image after changes |

> In this git folder only the scripts are kept. `bumblebee-sim.tar` and `bumblebee_src.tar.gz` come with the [download bundle](https://futurelab-uae.technology/s/fz3gBzbM4ENPH59).
