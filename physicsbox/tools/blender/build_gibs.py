"""Builds gore meshes in Blender and exports assets/npc/gibs.glb.

Run:  blender -b --python tools/blender/build_gibs.py

Objects (names are looked up by the game, scripts/gore.gd):
  skull_0..3   curved skull fragments: material 0 = skin (recoloured per NPC),
               1 = bone inside, 2 = bloody rim
  brain_0..2   brain lumps          eye           eyeball
  heart, lung, liver, stomach, kidney             organs
  chunk_0..2   blocky flesh chunks (like voxel gore)
  stump        torn neck stump shown when the head is gone
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "npc", "gibs.glb")
random.seed(7)


def mat(name, color, roughness=0.5, metallic=0.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = roughness
    b.inputs["Metallic"].default_value = metallic
    return m


def finish(o, name, x):
    o.name = name
    o.data.name = name
    o.location = (x, 0, 0)  # spread out so they do not overlap in the file
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def apply_mods(o):
    bpy.context.view_layer.objects.active = o
    for m in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def lumpy(name, x, size, scale, color, rough=0.35, seed=0, bumps=0.25, subdiv=2):
    """Organic blob: icosphere scaled and pushed around by noise."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=size)
    o = bpy.context.active_object
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    for v in o.data.vertices:
        n = noise.noise(v.co * (4.0 / size) + off)
        v.co += v.co.normalized() * n * size * bumps
    o.data.materials.append(mat(name + "_mat", color, rough))
    return finish(o, name, x)


def skull_fragment(i, x):
    r = 0.118
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=3, radius=r)
    o = bpy.context.active_object
    o.scale = (1.0, 1.0, 1.15)
    bpy.ops.object.transform_apply(scale=True)
    center = Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-0.2, 1))).normalized()
    reach = random.uniform(0.55, 0.85)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    kill = []
    for f in bm.faces:
        d = f.calc_center_median().normalized()
        jag = noise.noise(f.calc_center_median() * 40.0 + Vector((i, i, i))) * 0.25
        if d.dot(center) < math.cos(reach) + jag:
            kill.append(f)
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    # recentre on the fragment
    c = sum((v.co for v in bm.verts), Vector()) / max(len(bm.verts), 1)
    for v in bm.verts:
        v.co -= c
        v.co += Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))) * 0.003
    bm.to_mesh(o.data)
    bm.free()
    o.data.materials.append(mat("Skin", (0.9, 0.85, 0.8), 0.6))
    o.data.materials.append(mat("BoneInner", (0.86, 0.72, 0.62), 0.6))
    o.data.materials.append(mat("BloodRim", (0.45, 0.02, 0.03), 0.25))
    sol = o.modifiers.new("solid", "SOLIDIFY")
    sol.thickness = 0.014
    sol.offset = -1
    sol.material_offset = 1
    sol.material_offset_rim = 2
    apply_mods(o)
    return finish(o, "skull_%d" % i, x)


def chunk(i, x):
    """Blocky flesh chunk, like the voxel gore in the reference video."""
    s = random.uniform(0.035, 0.06)
    bpy.ops.mesh.primitive_cube_add(size=s)
    o = bpy.context.active_object
    o.scale = (random.uniform(0.7, 1.3), random.uniform(0.7, 1.3), random.uniform(0.6, 1.1))
    bpy.ops.object.transform_apply(scale=True)
    for v in o.data.vertices:
        v.co += Vector((random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1))) * s * 0.12
    o.data.materials.append(mat("Chunk%d" % i, [(0.45, 0.03, 0.04), (0.62, 0.12, 0.12), (0.3, 0.02, 0.03)][i], 0.4))
    o = finish(o, "chunk_%d" % i, x)
    for p in o.data.polygons:
        p.use_smooth = False
    return o


def eye(x):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.013)
    o = bpy.context.active_object
    o.data.materials.append(mat("EyeWhite", (0.95, 0.93, 0.9), 0.2))
    o.data.materials.append(mat("Pupil", (0.03, 0.03, 0.03), 0.1))
    for p in o.data.polygons:
        if p.center.y < -0.009:
            p.material_index = 1
    return finish(o, "eye", x)


def stump(x):
    """Ragged neck stump: a short bloody cylinder with a torn top."""
    bpy.ops.mesh.primitive_cylinder_add(vertices=14, radius=0.052, depth=0.05)
    o = bpy.context.active_object
    for v in o.data.vertices:
        if v.co.z > 0:
            v.co.z += random.uniform(-0.012, 0.022)
            v.co.x *= random.uniform(0.85, 1.1)
            v.co.y *= random.uniform(0.85, 1.1)
    o.data.materials.append(mat("StumpFlesh", (0.5, 0.04, 0.05), 0.25))
    o.data.materials.append(mat("StumpBone", (0.85, 0.78, 0.7), 0.5))
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=0.012, depth=0.07, location=(0, 0.01, 0.01))
    spine = bpy.context.active_object
    spine.data.materials.append(bpy.data.materials["StumpBone"])
    bpy.ops.object.select_all(action="DESELECT")
    spine.select_set(True)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.join()
    o = bpy.context.active_object
    o = finish(o, "stump", x)
    for p in o.data.polygons:
        p.use_smooth = False
    return o


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    x = 0.0
    for i in range(4):
        skull_fragment(i, x)
        x += 0.3
    for i in range(3):
        lumpy("brain_%d" % i, x, 0.035, (1.0, random.uniform(0.6, 0.9), random.uniform(0.5, 0.8)),
              (0.86, 0.6, 0.62), 0.3, seed=i, bumps=0.45, subdiv=3)
        x += 0.3
    eye(x)
    x += 0.3
    lumpy("heart", x, 0.055, (0.85, 0.8, 1.15), (0.5, 0.05, 0.07), 0.3, seed=11, bumps=0.2)
    x += 0.3
    lumpy("lung", x, 0.07, (0.6, 0.55, 1.3), (0.78, 0.38, 0.42), 0.4, seed=12, bumps=0.25)
    x += 0.3
    lumpy("liver", x, 0.08, (1.3, 0.75, 0.38), (0.38, 0.07, 0.06), 0.25, seed=13, bumps=0.2)
    x += 0.3
    lumpy("stomach", x, 0.06, (1.25, 0.8, 0.75), (0.8, 0.55, 0.5), 0.35, seed=14, bumps=0.15)
    x += 0.3
    lumpy("kidney", x, 0.035, (0.7, 0.5, 1.2), (0.45, 0.1, 0.1), 0.3, seed=15, bumps=0.15)
    x += 0.3
    for i in range(3):
        chunk(i, x)
        x += 0.3
    stump(x)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True,
                              export_cameras=False, export_lights=False, export_animations=False)
    print("EXPORTED", OUT, os.path.getsize(OUT))


main()
