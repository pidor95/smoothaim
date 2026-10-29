"""Builds the pistol the armed mannequins carry from the same textured Colt
M1911 model as the player's gun (assets/m1911/m1911.fbx) and exports it as
assets/npc/npc_pistol.glb.

Run:  blender -b --python tools/blender/build_npc_pistol.py

Model frame (Godot axes): origin in the middle of the grip, barrel along -Z,
top of the slide +Y, muzzle at (0, 0.056, -0.195). The glb carries no image:
the game puts the shared m1911_albedo.jpg on it, so it is not packed twice.
"""
import math
import os

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "npc", "npc_pistol.glb")
SCALE = 0.0626  # model is 3.45 units long; a real M1911 is 0.216 m
# middle of the grip in the scaled model (Blender axes, +Y = barrel); the
# muzzle then sits 0.195 m ahead of it and 0.056 m up (Npc.GUN_MUZZLE)
HAND = Vector((0.0, -0.045, -0.026))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT, "assets", "m1911", "m1911.fbx"))
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    mat = bpy.data.materials.new("M1911")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Metallic"].default_value = 0.3
    bsdf.inputs["Roughness"].default_value = 0.5
    to_gun = Matrix.Translation(-HAND) @ Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Scale(SCALE, 4)
    for o in parts:
        o.matrix_world = to_gun @ o.matrix_world
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        o.select_set(False)
        o.data.materials.clear()
        o.data.materials.append(mat)
        while len(o.data.uv_layers) > 1:
            o.data.uv_layers.remove(o.data.uv_layers[-1])
    for o in [o for o in bpy.context.scene.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    gun = bpy.context.active_object
    gun.name = "NpcPistol"
    pts = [gun.matrix_world @ v.co for v in gun.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    print("bounds (blender, from the grip):", [round(v, 3) for v in lo], [round(v, 3) for v in hi])
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_cameras=False,
                              export_lights=False, export_animations=False, export_image_format="NONE")
    print("EXPORTED", OUT, os.path.getsize(OUT))


main()
