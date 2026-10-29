"""Builds the AK's / SVD's suppressor from a Sketchfab model (CC-BY-4.0, see README):
  PBS-1 silencer   by 3dYaroslav       https://sketchfab.com/3d-models/pbs-1-silencer-for-ak-74-545x39-cb95b1e5f55842beb9a80587c6ff3f19

Output:
  assets/weapons/suppressor.glb   the PBS-1 along Godot -Z, origin on the
                                  rear face (it screws onto the muzzle),
                                  1 m long: the game scales it per rifle

Run (source fetched by tools/fetch_sketchfab.py pbs1):
  blender -b --python tools/blender/build_suppressor.py
"""
import math
import os
import sys

import bpy
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(__file__))
import build_weapons as bw  # noqa: E402
from build_sketchfab_kit import centre, decimate, import_gltf, shrink_images, transform  # noqa: E402

ROOT = bw.ROOT
OUT = os.path.join(ROOT, "assets", "weapons")


def build_suppressor():
    bw.reset()
    (src,) = import_gltf("pbs1")
    shrink_images(512)
    decimate(src, 900)
    # the model lies along X, the threaded collar end at -X (2.33), 4.69 long:
    # rear face to the origin, front along +Y (Godot -Z), 1 unit long
    length = 4.694
    transform([src], Matrix.Scale(1.0 / length, 4) @ Matrix.Rotation(math.pi / 2, 4, "Z") @ Matrix.Translation((2.33, 0, 0)))
    src.name = "Suppressor"
    c, s = centre(src)
    print("SUPPRESSOR centre", c, "size", s)
    bw.export(os.path.join(OUT, "suppressor.glb"))


if __name__ == "__main__":
    build_suppressor()
