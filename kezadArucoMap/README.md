# ArUco Marker Map — KEZAD Polygon

This repository contains the ArUco marker map for the **KEZAD indoor flight polygon**, used for autonomous navigation with the [Bumblebee](https://github.com/ermoluk/bumblebee-students) drone platform.

---

## Map

The map consists of **7 markers** placed across the polygon floor. All positions are measured from **marker ID 0**, located at the takeoff origin.

```
# id    length    x       y      z    rot_z   rot_y   rot_x
0       0.19      0       0      0    1.571    0       0
1       0.29      0       1.88   0    1.571    0       0
2       0.29      0       3.64   0    1.571    0       0
3       0.29      0       5.40   0    1.571    0       0
11      0.29     -1.95    1.88   0    1.571    0       0
12      0.29     -1.95    3.64   0    1.571    0       0
13      0.29     -1.95    5.40   0    1.571    0       0
```

All markers lie flat on the floor (`z = 0`) and are rotated 90° around the Z axis (`rot_z = 1.571 rad`) to match the expected orientation of the `aruco_pose` package.

Marker **ID 0** (origin) is printed at **0.19 m**, all others at **0.29 m**.

---

## Usage

Reference this map in your `aruco.launch`:

```xml
<param name="map" value="$(find your_package)/maps/map.txt"/>
```

This map can also be used as a **template** for configuring ArUco maps in other indoor environments — simply replace the coordinates with measurements from your own space.

---

## Related

- [Bumblebee Students Repository](https://github.com/ermoluk/bumblebee-students)
- For flashing instructions:
👉 **[Bumblebee Students Wiki](https://github.com/ermoluk/bumblebee-students/wiki)**
