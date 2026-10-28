"""Builds the pistol the armed mannequins carry (a low-poly 1911 seen from
third person) and exports it as assets/npc/npc_pistol.glb.

Run:  blender -b --python tools/blender/build_npc_pistol.py

Model frame (Godot axes): origin in the middle of the grip where the hand
holds it, barrel along -Z, top of the slide +Y. The muzzle is at
(0, 0.035, -0.12), which scripts/npc.gd relies on.
"""
import math
import os

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "npc", "npc_pistol.glb")
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Godot -> Blender axes


def gv(v):
    return C @ Vector(v)


def material(name, color, metallic, roughness):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return m


def box(name, center, size, mat, tilt_x=0.0, bevel=0.003):
    """Box in Godot coordinates; tilt_x turns it about the gun's X axis (deg)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0], size[2], size[1])  # Godot (x, y, z) sizes -> Blender (x, z, y)
    o.rotation_euler = (math.radians(tilt_x), 0, 0)
    o.location = gv(center)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel > 0:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier="bevel")
    o.data.materials.append(mat)
    return o


def cylinder(name, center, radius, depth, mat):
    """Cylinder along the barrel axis."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=depth)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler = (math.radians(90), 0, 0)  # Blender Z -> Y (= Godot -Z)
    o.location = gv(center)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
    o.data.materials.append(mat)
    return o


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    steel = material("Steel", (0.055, 0.057, 0.062), 0.85, 0.32)
    dark = material("Bore", (0.01, 0.01, 0.01), 0.2, 0.8)
    wood = material("Grip", (0.17, 0.08, 0.04), 0.0, 0.55)

    parts = [
        box("slide", (0, 0.035, -0.025), (0.028, 0.03, 0.195), steel),
        box("frame", (0, 0.012, -0.03), (0.026, 0.016, 0.15), steel),
        box("dust_cover", (0, 0.012, -0.095), (0.024, 0.018, 0.05), steel),
        box("grip", (0, -0.032, 0.022), (0.031, 0.105, 0.047), wood, tilt_x=-16.0),
        box("backstrap", (0, -0.03, 0.045), (0.027, 0.1, 0.012), steel, tilt_x=-16.0),
        box("guard_front", (0, -0.012, -0.045), (0.008, 0.032, 0.008), steel, bevel=0.0015),
        box("guard_bottom", (0, -0.026, -0.022), (0.008, 0.007, 0.05), steel, bevel=0.0015),
        box("trigger", (0, -0.004, -0.017), (0.006, 0.02, 0.006), steel, bevel=0.001),
        box("hammer", (0, 0.04, 0.075), (0.008, 0.016, 0.012), steel, bevel=0.0015),
        box("sight_front", (0, 0.053, -0.112), (0.004, 0.006, 0.008), steel, bevel=0.0),
        box("sight_rear", (0, 0.053, 0.06), (0.018, 0.006, 0.008), steel, bevel=0.0),
        box("mag_base", (0, -0.087, 0.037), (0.028, 0.008, 0.042), steel, tilt_x=-16.0, bevel=0.0015),
        cylinder("bore", (0, 0.035, -0.121), 0.0055, 0.004, dark),
    ]
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    gun = bpy.context.active_object
    gun.name = "NpcPistol"
    bpy.ops.object.shade_flat()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_cameras=False,
                              export_lights=False, export_animations=False)
    print("EXPORTED", OUT, os.path.getsize(OUT))


main()
