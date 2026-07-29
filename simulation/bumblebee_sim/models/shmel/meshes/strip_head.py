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
Strip the protruding bumblebee head/abdomen from shmel.obj.

The shmel mesh's main body extends to mesh-y ~0.10. Above that sits a thin
neck (y 0.12-0.16) topped by a head bulb (y 0.17-0.21). After SDF scale 0.6
and roll-pi/2 rotation, those map to z 0.07-0.13 in base_link, which is what
sticks up above the drone in Gazebo. Filtering vertices with y > Y_CUT and
dropping any face that references one gives a flat-topped body.

Reads shmel.obj.bak (untouched original) and overwrites shmel.obj.
"""
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE / "shmel.obj.bak"
DST = HERE / "shmel.obj"
Y_CUT = 0.180  # drop vertices with y > Y_CUT (mesh frame).
# Mesh layout (per histogram of Body1.2019 verts) and groups:
#   y ≤ 0.09  body + top cap (49k-vert spike at the cap)
#   0.092-0.102  Body1.001-005 = propeller blades (must be preserved —
#                x500_base rotor_N visuals are transparency=1.0, so the
#                static props in shmel.obj are the only visible blades)
#   0.10-0.15  servo / neck cylinder
#   0.17-0.21  head bulb / top sensor
# Cutting at 0.103 keeps cap + props and drops servo/bulb (the things
# the user sees as "torchat" on top of the drone).


def main() -> None:
    # Pass 1: classify vertices, build old->new index remap.
    keep: list[bool] = [False]  # 1-indexed; sentinel at 0
    with SRC.open() as f:
        for line in f:
            if line.startswith("v "):
                y = float(line.split(maxsplit=3)[2])
                keep.append(y <= Y_CUT)
    n_vertices = len(keep) - 1
    remap = [0] * len(keep)
    new_idx = 0
    for i in range(1, len(keep)):
        if keep[i]:
            new_idx += 1
            remap[i] = new_idx
    n_kept = new_idx

    # Pass 2: rewrite. Keep vt/vn/o/g/usemtl/mtllib verbatim; drop dead v's
    # and any face that references one.
    dropped_faces = 0
    kept_faces = 0
    with SRC.open() as fin, DST.open("w") as fout:
        for line in fin:
            if line.startswith("v "):
                y = float(line.split(maxsplit=3)[2])
                if y <= Y_CUT:
                    fout.write(line)
            elif line.startswith("f "):
                tokens = line.split()
                out_tokens = ["f"]
                ok = True
                for t in tokens[1:]:
                    parts = t.split("/")
                    v = int(parts[0])
                    if not keep[v]:
                        ok = False
                        break
                    parts[0] = str(remap[v])
                    out_tokens.append("/".join(parts))
                if ok and len(out_tokens) >= 4:  # need >= 3 verts
                    fout.write(" ".join(out_tokens) + "\n")
                    kept_faces += 1
                else:
                    dropped_faces += 1
            else:
                fout.write(line)

    print(f"vertices: kept {n_kept} of {n_vertices}")
    print(f"faces:    kept {kept_faces}, dropped {dropped_faces}")
    print(f"wrote: {DST}")


if __name__ == "__main__":
    main()
