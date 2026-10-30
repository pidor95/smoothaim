"""First aid in Blender:
  assets/props/medkit.glb    the IFAK pouch lying on the map (Sketchfab
                             "Tactical FIRST AID KIT" by ruskoschey, CC-BY-4.0,
                             https://sketchfab.com/3d-models/tactical-first-aid-kit-011c33c121284bc88bb765a85511dae1):
                             on its back, the red cross patch up, origin on
                             the ground under its middle; also on the
                             medics' chests
  assets/props/bandage.glb   a field dressing: a rolled bandage with its
                             loose end and the torn wrapper (icon)
  assets/props/promedol.glb  the promedol syringe-tube: soft tube, needle
                             cap, label band (icon)

Run (the IFAK source fetched by tools/fetch_sketchfab.py ifak):
  blender -b --python tools/blender/build_medical.py
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import build_weapons as bw  # noqa: E402
import build_sketchfab_kit as kit  # noqa: E402

ROOT = bw.ROOT
OUT = os.path.join(ROOT, "assets", "props")
IFAK_SCALE = 0.058  # the model is 3.45 units tall; the pouch is 20 cm


def build_medkit():
    bw.reset()
    meshes = kit.import_gltf("ifak")
    kit.shrink_images(512)
    pouch = bw.join(meshes, "Medkit")
    c, s = kit.centre(pouch)
    # straps (+Y) down on the ground, the patch side (-Y) up
    kit.transform([pouch], Matrix.Rotation(-math.pi / 2, 4, "X") @ Matrix.Scale(IFAK_SCALE, 4) @ Matrix.Translation(-c))
    c, s = kit.centre(pouch)
    kit.transform([pouch], Matrix.Translation((-c.x, -c.y, -(c.z - s.z / 2))))
    kit.decimate(pouch, 2500)
    for p in pouch.data.polygons:
        p.use_smooth = True
    os.makedirs(OUT, exist_ok=True)
    bw.export(os.path.join(OUT, "medkit.glb"))


def build_bandage():
    bw.reset()
    gauze = bw.material("Gauze", (0.93, 0.92, 0.88), roughness=0.95)
    wrap = bw.material("Wrapper", (0.42, 0.45, 0.3), roughness=0.7)
    bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.03, depth=0.07, location=(0, 0, 0.03))
    roll = bpy.context.active_object
    roll.rotation_euler = (0, math.radians(90), 0)
    bw.apply_all(roll)
    roll.data.materials.append(gauze)
    # the loose end trailing out, slightly wavy
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, 0, 0))
    tail = bpy.context.active_object
    tail.scale = (0.068, 0.12, 1)
    bw.apply_all(tail)
    mod = tail.modifiers.new("sub", "SUBSURF")
    mod.levels = 3
    mod.subdivision_type = "SIMPLE"
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for v in tail.data.vertices:
        y = v.co.y + 0.06
        v.co.y = y + 0.025
        v.co.z = 0.001 + 0.004 * math.sin(y * 70) + (0.03 if y < 0.0 else 0.0)
    tail.data.materials.append(gauze)
    # the opened wrapper under it
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, -0.02, 0.0005))
    pack = bpy.context.active_object
    pack.scale = (0.1, 0.14, 1)
    pack.rotation_euler = (0, 0, math.radians(14))
    bw.apply_all(pack)
    pack.data.materials.append(wrap)
    bw.join([roll, tail, pack], "Bandage")
    bw.export(os.path.join(OUT, "bandage.glb"))


def build_promedol():
    bw.reset()
    tube_mat = bw.material("Tube", (0.82, 0.84, 0.86), metallic=0.6, roughness=0.35)
    cap_mat = bw.material("Cap", (0.92, 0.92, 0.9), roughness=0.5)
    label = bw.material("Label", (0.75, 0.12, 0.1), roughness=0.6)
    # the soft tube: flattened, squeezed towards the back
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.009, depth=0.05, location=(0, 0, 0))
    tube = bpy.context.active_object
    tube.rotation_euler = (math.radians(90), 0, 0)
    bw.apply_all(tube)
    for v in tube.data.vertices:
        squeeze = 1.0 if v.co.y > 0 else 0.35
        v.co.z *= squeeze
        v.co.x *= 1.0 + (1.0 - squeeze) * 0.4
    tube.data.materials.append(tube_mat)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=0.0094, depth=0.016, location=(0, 0.012, 0))
    band = bpy.context.active_object
    band.rotation_euler = (math.radians(90), 0, 0)
    bw.apply_all(band)
    band.data.materials.append(label)
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.0035, depth=0.032, location=(0, 0.041, 0))
    cap = bpy.context.active_object
    cap.rotation_euler = (math.radians(-90), 0, 0)
    bw.apply_all(cap)
    cap.data.materials.append(cap_mat)
    o = bw.join([tube, band, cap], "Promedol")
    for p in o.data.polygons:
        p.use_smooth = True
    bw.export(os.path.join(OUT, "promedol.glb"))


if __name__ == "__main__":
    build_medkit()
    build_bandage()
    build_promedol()
