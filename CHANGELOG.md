# Changelog

All notable changes to the Bumblebee student platform are documented here.
Versioning follows [SemVer](https://semver.org/); each release has a tag `vX.Y.Z`,
a release page in the [wiki](https://github.com/futureLabKezad/bumblebee-students/wiki)
and downloadable builds.

## v1.0.0 — 2026-07-29

First official release.

### Added
- `drone/` — complete on-board source code extracted from the official SD image `030726`
  (ROS 2 Jazzy workspace: `bumblebee`, `aruco_pose`, `bumblebee_bridge`,
  `bumblebee_description`; systemd units and system scripts).
- `examples/` — `drone.py` flight API and flight/LED/misc example scripts.
- `simulation/` — `bumblebee_sim` ROS 2 package with the `clover_aruco` Gazebo world
  (grass field, cable towers, landing pad, ArUco markers) and Windows installer scripts.
- `gcs/` — Ground Control Station sources for macOS (SwiftUI) and Windows (WinUI 3),
  including the SimDrone localhost mock.
- `lectures/` — three lecture decks and the Lecture 1 Python notebook.
- Wiki: setup guides for Gazebo on Windows/macOS, Ground Control Station,
  SD Card Image; Downloads section with hosted builds.
- Apache License 2.0 (`LICENSE`, `NOTICE`).

### Builds
- Gazebo simulator for Windows, GCS for Windows/macOS, drone SD-card image —
  links and SHA-256 checksums on the release page in the wiki.
