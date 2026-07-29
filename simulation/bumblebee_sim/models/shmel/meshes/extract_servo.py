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

"""Split shmel.obj.bak into body (shmel.obj) and servo arm (servo_arm.obj).

The shmel mesh has a thin vertical neck/head bulb at the rear of the body
(mesh x∈[-0.04,+0.05], y∈[0.10,0.22], z∈[-0.36,-0.14]). On the real drone
this is the servo-driven probe. To animate it in Gazebo we need it as a
SEPARATE visual that drone_sim can rotate without spinning the whole body.

This script:
  • reads shmel.obj.bak (untouched original)
  • writes shmel.obj          ← body without the neck, head bulb cut at Y_CUT
  • writes servo_arm.obj      ← just the neck, translated so its BASE sits at
                                the mesh-frame origin (0,0,0). That way the
                                SDF visual that loads servo_arm.obj rotates
                                about its base when drone_sim updates the pose.

Face/vertex remapping mirrors strip_head.py: vt and vn lines are copied
verbatim into both files (assimp's OBJ loader tolerates unused entries);
faces are routed by which output their vertices live in. Faces that span
both buckets are dropped (there should be a clean cut at the neck base).
"""
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE / "shmel.obj.bak"
BODY_DST = HERE / "shmel.obj"
SERVO_DST = HERE / "servo_arm.obj"

Y_CUT = 0.180  # strip_head.py default — drop body verts above this y

# Bounding box for the neck/head in mesh frame (verified by histogram).
NECK_X = (-0.05, 0.05)
NECK_Y = (0.10, 0.22)
NECK_Z = (-0.36, -0.14)

# Translate the extracted neck so its BASE (lowest y, mid x/z) lands at the
# mesh origin. base mesh point ≈ (0, 0.10, -0.25); translation negates that.
SERVO_DY = -0.10
SERVO_DZ = +0.25


def in_neck(x, y, z):
    return (NECK_X[0] <= x <= NECK_X[1]
            and NECK_Y[0] <= y <= NECK_Y[1]
            and NECK_Z[0] <= z <= NECK_Z[1])


def main():
    # Pass 1: classify every vertex; build separate body/servo remaps.
    cats = [None]   # 1-indexed; cats[i] ∈ {'body', 'servo', 'drop'}
    body_remap = [0]
    servo_remap = [0]
    nb = ns = nd = 0
    with SRC.open() as f:
        for line in f:
            if not line.startswith("v "):
                continue
            parts = line.split()
            x = float(parts[1]); y = float(parts[2]); z = float(parts[3])
            if in_neck(x, y, z):
                ns += 1
                cats.append("servo"); body_remap.append(0); servo_remap.append(ns)
            elif y <= Y_CUT:
                nb += 1
                cats.append("body"); body_remap.append(nb); servo_remap.append(0)
            else:
                nd += 1
                cats.append("drop"); body_remap.append(0); servo_remap.append(0)

    # Pass 2: re-emit. v's and f's are filtered/remapped per output; vt, vn,
    # mtllib, comments, etc. are copied verbatim to both (their indices must
    # stay in sync with face references). `o ` directives are DEFERRED — we
    # only emit them once we know the block has content for that output.
    # That avoids leaving empty `o` blocks behind in servo_arm.obj, which
    # Ogre's OBJ loader rejects.
    body_faces = servo_faces = dropped = 0
    vi = 0
    pending_o_body = None
    pending_o_servo = None

    def flush_body_o(fb_):
        nonlocal pending_o_body
        if pending_o_body is not None:
            fb_.write(pending_o_body)
            pending_o_body = None

    def flush_servo_o(fs_):
        nonlocal pending_o_servo
        if pending_o_servo is not None:
            fs_.write(pending_o_servo)
            pending_o_servo = None

    with SRC.open() as fin, BODY_DST.open("w") as fb, SERVO_DST.open("w") as fs:
        for line in fin:
            if line.startswith("o "):
                # Defer until v/f content appears for that output. Replacing
                # any prior pending `o` silently drops empty blocks.
                pending_o_body = line
                pending_o_servo = line
            elif line.startswith("v "):
                vi += 1
                parts = line.split()
                x = float(parts[1]); y = float(parts[2]); z = float(parts[3])
                tail = (" " + " ".join(parts[4:])) if len(parts) > 4 else ""
                if cats[vi] == "servo":
                    flush_servo_o(fs)
                    fs.write(f"v {x:.6f} {y + SERVO_DY:.6f} {z + SERVO_DZ:.6f}{tail}\n")
                elif cats[vi] == "body":
                    flush_body_o(fb)
                    fb.write(line)
                # drop: write to neither
            elif line.startswith("f "):
                tokens = line.split()
                vs = [int(t.split("/")[0]) for t in tokens[1:]]
                face_cats = {cats[v] for v in vs}
                if face_cats == {"body"}:
                    flush_body_o(fb)
                    out = ["f"]
                    for t in tokens[1:]:
                        parts = t.split("/")
                        parts[0] = str(body_remap[int(parts[0])])
                        out.append("/".join(parts))
                    fb.write(" ".join(out) + "\n")
                    body_faces += 1
                elif face_cats == {"servo"}:
                    flush_servo_o(fs)
                    out = ["f"]
                    for t in tokens[1:]:
                        parts = t.split("/")
                        parts[0] = str(servo_remap[int(parts[0])])
                        out.append("/".join(parts))
                    fs.write(" ".join(out) + "\n")
                    servo_faces += 1
                else:
                    dropped += 1
            else:
                # vt / vn / usemtl / mtllib / g / comments — copy verbatim to
                # both files so vt/vn global indexing stays consistent. These
                # do NOT flush the pending `o` — only v/f content does.
                fb.write(line)
                fs.write(line)

    print(f"vertices: body={nb} servo={ns} dropped={nd}")
    print(f"faces:    body={body_faces} servo={servo_faces} dropped={dropped}")
    print(f"wrote: {BODY_DST}")
    print(f"wrote: {SERVO_DST}")


if __name__ == "__main__":
    main()
