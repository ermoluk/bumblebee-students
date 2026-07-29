#!/usr/bin/env python3
# Copyright 2026 FutureLab
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
generate_aruco_models.py — generate ArUco PNG textures + Gazebo SDF models.

Produces, for every id in IDS:

    models/aruco_<id>/model.config
    models/aruco_<id>/model.sdf
    models/aruco_<id>/materials/textures/marker_<id>.png

The marker is a flat 0.19 m square plane with the ArUco texture on +Z.
DICT_4X4_50 matches drone.py defaults (DICT_4X4_100 also works for ids 0-49).

Usage:
    python3 generate_aruco_models.py [--dst /path/to/models] [--size 0.19]
"""
import argparse
import os
import sys

import cv2
import numpy as np

DEFAULT_IDS = [0, 1, 2, 3, 11, 12, 13]
DEFAULT_DICT = cv2.aruco.DICT_4X4_50
DEFAULT_SIZE = 0.19
TEXTURE_PIXELS = 800


MODEL_CONFIG = """\
<?xml version="1.0"?>
<model>
  <name>aruco_{id}</name>
  <version>1.0</version>
  <sdf version="1.10">model.sdf</sdf>
  <author>
    <name>bumblebee_sim</name>
  </author>
  <description>ArUco DICT_4X4_50 marker {id}</description>
</model>
"""

MODEL_SDF = """\
<?xml version="1.0"?>
<sdf version="1.10">
  <model name="aruco_{id}">
    <static>true</static>
    <link name="link">
      <visual name="visual">
        <geometry>
          <plane>
            <normal>0 0 1</normal>
            <size>{size} {size}</size>
          </plane>
        </geometry>
        <material>
          <diffuse>1 1 1 1</diffuse>
          <specular>0 0 0 1</specular>
          <pbr>
            <metal>
              <albedo_map>model://aruco_{id}/materials/textures/marker_{id}.png</albedo_map>
              <metalness>0</metalness>
              <roughness>1</roughness>
            </metal>
          </pbr>
        </material>
      </visual>
      <collision name="collision">
        <geometry>
          <plane>
            <normal>0 0 1</normal>
            <size>{size} {size}</size>
          </plane>
        </geometry>
      </collision>
    </link>
  </model>
</sdf>
"""


def render_marker_png(marker_id: int, dictionary: int, dst: str) -> None:
    aruco_dict = cv2.aruco.getPredefinedDictionary(dictionary)
    # 4.7+ renamed drawMarker -> generateImageMarker.
    if hasattr(cv2.aruco, 'generateImageMarker'):
        img = cv2.aruco.generateImageMarker(aruco_dict, marker_id, TEXTURE_PIXELS)
    else:
        img = cv2.aruco.drawMarker(aruco_dict, marker_id, TEXTURE_PIXELS)
    # Add a 10% white border so detection is robust against texture seams.
    border = TEXTURE_PIXELS // 10
    bordered = np.full(
        (TEXTURE_PIXELS + 2 * border, TEXTURE_PIXELS + 2 * border),
        255,
        dtype=np.uint8,
    )
    bordered[border:border + TEXTURE_PIXELS,
             border:border + TEXTURE_PIXELS] = img
    cv2.imwrite(dst, bordered)


def write_model(model_dir: str, marker_id: int, size: float, dictionary: int) -> None:
    tex_dir = os.path.join(model_dir, 'materials', 'textures')
    os.makedirs(tex_dir, exist_ok=True)
    render_marker_png(
        marker_id, dictionary,
        os.path.join(tex_dir, f'marker_{marker_id}.png'),
    )
    with open(os.path.join(model_dir, 'model.config'), 'w') as fh:
        fh.write(MODEL_CONFIG.format(id=marker_id))
    with open(os.path.join(model_dir, 'model.sdf'), 'w') as fh:
        fh.write(MODEL_SDF.format(id=marker_id, size=size))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--dst', default=os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'models'))
    ap.add_argument('--size', type=float, default=DEFAULT_SIZE)
    ap.add_argument('--ids', type=int, nargs='+', default=DEFAULT_IDS)
    ap.add_argument('--dictionary', type=int, default=DEFAULT_DICT)
    opts = ap.parse_args()

    os.makedirs(opts.dst, exist_ok=True)
    for marker_id in opts.ids:
        model_dir = os.path.join(opts.dst, f'aruco_{marker_id}')
        write_model(model_dir, marker_id, opts.size, opts.dictionary)
        print(f'wrote {model_dir}')
    print(f'done: {len(opts.ids)} markers in {opts.dst}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
