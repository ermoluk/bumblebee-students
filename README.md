# 🐝 Bumblebee - Drone Programming Learning Platform

Welcome! This repository is your starting point for learning how to program autonomous drones using the **Bumblebee** platform.

## What You'll Learn

- Working with ROS 2 (Robot Operating System) and MAVROS
- Writing flight scripts in Python
- Using the Gazebo simulator for safe testing
- Autonomous drone control - takeoff, navigation, landing
- Working with cameras, ArUco markers, and the Ground Control Station

## Before You Start

All tasks are completed **in the simulator first**, and only then on a real drone. This keeps things safe and lets you make mistakes without consequences.

## Downloads

| What | Download | Size | Guide |
| --- | --- | --- | --- |
| 🖥️ Gazebo simulator for **Windows** (WSL2, pre-built image) | [📥 Download](https://futurelab-uae.technology/s/fz3gBzbM4ENPH59) | ~3.7 GB | [Gazebo Setup (Windows)](https://github.com/futureLabKezad/bumblebee-students/wiki/Gazebo‐Setup‐(Windows)) |
| 🎛️ Ground Control Station for **Windows** | [📥 Download](https://futurelab-uae.technology/s/PNmQcA7yfLBAY3W) | ~291 MB | [Ground Control Station](https://github.com/futureLabKezad/bumblebee-students/wiki/Ground‐Control‐Station) |
| 🎛️ Ground Control Station for **macOS** | [📥 Download](https://futurelab-uae.technology/s/4gsYow9JBNACqcG) | ~201 MB | [Ground Control Station](https://github.com/futureLabKezad/bumblebee-students/wiki/Ground‐Control‐Station) |
| 💾 Drone SD card image (Raspberry Pi 5) | [📥 Download](https://futurelab-uae.technology/s/wXSZisHxTZE6zHg) | ~3.4 GB | [SD Card Image](https://github.com/futureLabKezad/bumblebee-students/wiki/SD‐Card‐Image) |

## Full Documentation

All the information you need — setup instructions, code examples, and assignments — can be found in our wiki:

👉 **[Open Bumblebee Students Wiki](https://github.com/futureLabKezad/bumblebee-students/wiki)**

## Repository Structure

```
bumblebee-students/
├── lectures/                        # Lecture slides and Python notebook
├── tasks/                           # Learning assignments
├── examples/                        # Example flight scripts + drone.py API
├── drone/                           # On-board source code (ROS 2 workspace + system files)
├── simulation/                      # Simulator source code and Windows installer scripts
├── gcs/                             # Ground Control Station source code (macOS + Windows)
├── system-images-for-bumblebee/     # Raspberry Pi SD card images for the drone
├── PX4_bin/                         # PX4 firmware binaries for the flight controller
├── PX4_parameters/                  # PX4 parameter snapshots
├── kezadArucoMap/                   # ArUco marker map of the KEZAD polygon
└── README.md                        # This file
```

## Need Help?

Check the wiki first - it covers the most common questions. If something isn't working, don't panic: ask your instructor or open an Issue in the repository.

Good luck and smooth landings! 🚁
