"""Builds the interior door in Blender and pre-fractures it, exporting
assets/props/door.glb.

Run:  blender -b --python tools/blender/build_door.py

Objects:
  door        the leaf: 0.84 x 2.11 x 0.05 m, two recessed panels per side,
              lever handles on both sides; origin at the leaf centre
  frag_0..N   the same leaf cut into splintered chunks by random planes;
              each origin sits at the chunk centre, so its position is its
              offset inside the leaf (material 1 = raw wood on the cuts)
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "props", "door.glb")
W, H, T = 0.84, 2.11, 0.05
random.seed(3)


def mat(name, color, rough):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    return m


PAINT = None
RAW = None
METAL = None


def leaf_bmesh():
    """Door slab (Blender: X width, Z height, Y thickness) with recessed panels."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector((W, T, H)), verts=bm.verts)
    bm.faces.ensure_lookup_table()
    for side in (-1, 1):
        face = next(f for f in bm.faces if f.normal.y * side > 0.9)
        # inset twice: the stile/rail border, then the recessed panel
        # (a cross rail added later splits it into an upper and lower panel)
        bmesh.ops.inset_individual(bm, faces=[face], thickness=0.09, depth=0.0)
        bmesh.ops.inset_individual(bm, faces=[face], thickness=0.025, depth=-0.008)
    return bm


def build_leaf():
    bm = leaf_bmesh()
    me = bpy.data.meshes.new("door")
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new("door", me)
    bpy.context.scene.collection.objects.link(o)
    me.materials.append(PAINT)
    me.materials.append(RAW)
    me.materials.append(METAL)
    # a cross rail splitting the panel into two
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0.05))
    rail = bpy.context.active_object
    rail.scale = (W - 0.2, T + 0.004, 0.09)
    bpy.ops.object.transform_apply(scale=True)
    rail.data.materials.append(PAINT)
    # lever handles on both faces
    parts = [rail]
    for side in (-1, 1):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(W / 2 - 0.08, side * (T / 2 + 0.004), 0.0))
        plate = bpy.context.active_object
        plate.scale = (0.04, 0.006, 0.18)
        bpy.ops.object.transform_apply(scale=True)
        bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.009, depth=0.12,
                                            location=(W / 2 - 0.13, side * (T / 2 + 0.04), 0.03))
        lever = bpy.context.active_object
        lever.rotation_euler = (0, math.radians(90), 0)
        bpy.ops.mesh.primitive_cylinder_add(vertices=10, radius=0.011, depth=0.035,
                                            location=(W / 2 - 0.08, side * (T / 2 + 0.02), 0.03))
        neck = bpy.context.active_object
        neck.rotation_euler = (math.radians(90), 0, 0)
        for p in (plate, lever, neck):
            p.data.materials.append(METAL)
            parts.append(p)
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = "door"
    return o


def cut(bm, co, no):
    """Keeps the positive side of a plane and caps the cut with raw wood."""
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=co, plane_no=no, clear_inner=True)
    edges = [e for e in res["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    if edges:
        fill = bmesh.ops.holes_fill(bm, edges=edges, sides=0)
        for f in fill["faces"]:
            f.material_index = 1


def fragments():
    """Recursive random plane cuts of a plain slab -> splintered chunks."""
    base = bmesh.new()
    bmesh.ops.create_cube(base, size=1.0)
    bmesh.ops.scale(base, vec=Vector((W, T, H)), verts=base.verts)
    pieces = [base]
    target = 12
    while len(pieces) < target:
        pieces.sort(key=lambda b: -sum(f.calc_area() for f in b.faces))
        bm = pieces.pop(0)
        c = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
        ext = Vector((max(v.co.x for v in bm.verts) - min(v.co.x for v in bm.verts),
                      0, max(v.co.z for v in bm.verts) - min(v.co.z for v in bm.verts)))
        # mostly split across the long side, slanted like splintered wood
        if ext.z > ext.x:
            no = Vector((random.uniform(-0.6, 0.6), random.uniform(-0.15, 0.15), 1.0)).normalized()
        else:
            no = Vector((1.0, random.uniform(-0.15, 0.15), random.uniform(-0.8, 0.8))).normalized()
        co = c + Vector((random.uniform(-0.1, 0.1), 0, random.uniform(-0.15, 0.15)))
        a = bm.copy()
        b = bm.copy()
        bm.free()
        cut(a, co, no)
        cut(b, co, -no)
        for piece in (a, b):
            if len(piece.verts) >= 4:
                pieces.append(piece)
    out = []
    for i, bm in enumerate(pieces):
        # jag the long edges a little so the breaks look splintered
        for v in bm.verts:
            v.co.x += random.uniform(-0.006, 0.006)
            v.co.z += random.uniform(-0.01, 0.01)
        c = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
        for v in bm.verts:
            v.co -= c
        me = bpy.data.meshes.new("frag_%d" % i)
        bm.to_mesh(me)
        bm.free()
        me.materials.append(PAINT)
        me.materials.append(RAW)
        o = bpy.data.objects.new("frag_%d" % i, me)
        o.location = c
        bpy.context.scene.collection.objects.link(o)
        out.append(o)
    return out


def main():
    global PAINT, RAW, METAL
    bpy.ops.wm.read_factory_settings(use_empty=True)
    PAINT = mat("DoorPaint", (0.78, 0.62, 0.42), 0.55)
    RAW = mat("DoorRaw", (0.88, 0.74, 0.52), 0.9)
    METAL = mat("DoorMetal", (0.75, 0.75, 0.78), 0.3)
    METAL.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.9
    build_leaf()
    fragments()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True,
                              export_cameras=False, export_lights=False, export_animations=False)
    print("EXPORTED", OUT, os.path.getsize(OUT))


main()
