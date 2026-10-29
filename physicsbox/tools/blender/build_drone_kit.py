"""Builds the player's bomber drone and the AK's suppressor from Sketchfab
models (CC-BY-4.0, see README):
  DJI Mavic 2 Pro  by MattMaksymowicz  https://sketchfab.com/3d-models/dji-mavic-2-pro-3e5b8566dbe24f4ba65473179650abd1
  F-1 grenade      by notcplkerry      https://sketchfab.com/3d-models/low-poly-f-1-grenade-4ed44b77a00d4116928b15e8b30a5785
  PBS-1 silencer   by 3dYaroslav       https://sketchfab.com/3d-models/pbs-1-silencer-for-ak-74-545x39-cb95b1e5f55842beb9a80587c6ff3f19

Outputs:
  assets/weapons/bomb_drone.glb   the quadcopter that drops grenades: Frame,
                                  Prop0..3 (origin on the motor axis, the game
                                  spins them), Rig (the printed drop rig under
                                  the belly, like on the front's Mavics),
                                  Grenade0 / Grenade1 (F-1s in the rig's cups,
                                  origin in the middle) and the empty Cam
                                  (the gimbal camera)
  assets/weapons/f1.glb           the falling F-1 (origin in the middle)
  assets/weapons/suppressor.glb   the PBS-1 along Godot -Z, origin on the
                                  rear face (it screws onto the muzzle),
                                  1 m long: the game scales it per rifle

Run (sources fetched by tools/fetch_sketchfab.py mavic f1 pbs1):
  blender -b --python tools/blender/build_drone_kit.py
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import build_weapons as bw  # noqa: E402
from build_sketchfab_kit import centre, decimate, import_gltf, import_more, separate_loose, shrink_images, transform  # noqa: E402

ROOT = bw.ROOT
OUT = os.path.join(ROOT, "assets", "weapons")

MAVIC_SCALE = 0.075  # rear motors 4.1 units apart -> ~0.31 m, ~0.45 m across the props
# motor axes (model units, front is -Y) and the height band of each prop
MAVIC_HUBS = [(Vector((-1.53, 2.25)), 0.85, 1.15), (Vector((1.53, 2.25)), 0.85, 1.15),
              (Vector((-2.05, -0.79)), 1.4, 1.6), (Vector((2.05, -0.79)), 1.4, 1.6)]
MAVIC_MID = Vector((0.0, 0.7, 1.0))  # middle of the body
GIMBAL = Vector((0.0, -0.97, 0.83))


def to_game(v):
    """Mavic model units -> drone frame (Blender axes, nose along +Y)."""
    return Matrix.Rotation(math.pi, 3, "Z") @ ((Vector(v) - MAVIC_MID) * MAVIC_SCALE)


def add_empty(name, pos):
    ob = bpy.data.objects.new(name, None)
    ob.location = pos
    bpy.context.scene.collection.objects.link(ob)
    return ob


F1_MID = Vector((0.0, 0.0, 0.005))  # middle of the F-1's body (model units are metres)


def f1_grenade(name):
    """The F-1 "limonka" (fuse up, the ring in; the pulled-ring variant
    the model also has goes), origin in the middle of its body."""
    meshes = import_more("f1")
    for o in list(meshes):
        if min((o.matrix_world @ Vector(c)).x for c in o.bound_box) < -0.06:  # the pulled ring, off to the side
            meshes.remove(o)
            bpy.data.objects.remove(o)
    g = bw.join(meshes, name)
    for m in g.data.materials:
        if m.name.startswith("body"):
            m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.2, 0.23, 0.12, 1)
            m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.7
    g.data.transform(Matrix.Translation(-F1_MID))
    return g


def build_f1():
    bw.reset()
    f1_grenade("F1")
    bw.export(os.path.join(OUT, "f1.glb"))


def build_bomb_drone():
    bw.reset()
    (src,) = import_gltf("mavic")
    shrink_images(1024)
    for mat in src.data.materials:  # the baked normal map goes blotchy once the parts are split
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        for link in list(bsdf.inputs["Normal"].links):
            mat.node_tree.links.remove(link)
    props = [[] for _ in MAVIC_HUBS]
    frame = []
    for p in separate_loose(src):
        c, s = centre(p)
        hub = None
        for k, (h, z0, z1) in enumerate(MAVIC_HUBS):
            if (c.xy - h).length < 1.55 and z0 < c.z < z1 and s.z < 0.45 and not (abs(c.x) < 0.5 and c.y < 2.0):
                hub = k
        (props[hub] if hub is not None else frame).append(p)
    m = Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Scale(MAVIC_SCALE, 4) @ Matrix.Translation(-MAVIC_MID)
    body = bw.join(frame, "Frame")
    transform([body], m)
    objs = [body]
    for k, parts in enumerate(props):
        pr = bw.join(parts, "Prop%d" % k)
        transform([pr], m)
        h, z0, z1 = MAVIC_HUBS[k]
        at = to_game((h.x, h.y, (z0 + z1) / 2))
        pr.data.transform(Matrix.Translation(-at))
        pr.location = at
        objs.append(pr)
    # the drop rig, like the ones printed for the front: a white bracket
    # strapped under the belly, a servo in the middle, a cup either side
    # holding an F-1 on its side (fuse out, the ring on the servo's pin),
    # longer white legs so it can land with them
    white = bw.material("Printed", (0.85, 0.85, 0.82), roughness=0.55)
    blue = bw.material("Servo", (0.1, 0.25, 0.7), roughness=0.4)
    bottom = to_game((0.0, 0.62, 0.44)).z
    rig = []

    def box(loc, size, mat):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
        o = bpy.context.active_object
        o.scale = size
        bw.apply_all(o)
        o.data.materials.append(mat)
        rig.append(o)
        return o

    def rod(a, b, r, mat):
        a, b = Vector(a), Vector(b)
        d = b - a
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=r, depth=d.length, location=(a + b) / 2)
        o = bpy.context.active_object
        o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
        bw.apply_all(o)
        o.data.materials.append(mat)
        rig.append(o)
        return o

    box((0.0, 0.0, bottom - 0.006), (0.1, 0.07, 0.012), white)
    for strap_y in (-0.03, 0.03):
        box((0.0, strap_y, bottom + 0.02), (0.1, 0.008, 0.05), white)
    box((0.0, 0.012, bottom - 0.02), (0.026, 0.032, 0.016), blue)
    CUP_X = 0.066
    CUP_Z = bottom - 0.03
    for side in (-1.0, 1.0):
        # the cup: a half shell round the grenade's base, open to the outside
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, radius=0.034)
        cup = bpy.context.active_object
        bm = bmesh.new()
        bm.from_mesh(cup.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z > 0.004], context="VERTS")
        bm.to_mesh(cup.data)
        bm.free()
        mod = cup.modifiers.new("shell", "SOLIDIFY")
        mod.thickness = 0.003
        bpy.context.view_layer.objects.active = cup
        bpy.ops.object.modifier_apply(modifier=mod.name)
        tilt = side * math.radians(105)
        cup.matrix_world = Matrix.Translation((side * CUP_X, 0.0, CUP_Z)) @ Matrix.Rotation(tilt, 4, "Y")
        bw.apply_all(cup)
        cup.data.materials.append(white)
        rig.append(cup)
        box((side * 0.045, 0.0, bottom - 0.016), (0.03, 0.03, 0.012), white)  # arm out to the cup
        for leg_y in (-0.028, 0.028):
            rod((side * CUP_X, leg_y, CUP_Z - 0.02), (side * (CUP_X + 0.012), leg_y * 1.3, CUP_Z - 0.105), 0.0035, white)
        g = f1_grenade("Grenade%d" % (0 if side < 0 else 1))
        g.matrix_world = Matrix.Translation((side * CUP_X, 0.0, CUP_Z)) @ Matrix.Rotation(tilt, 4, "Y")
        objs.append(g)
    objs.append(bw.join(rig, "Rig"))
    add_empty("Cam", to_game(GIMBAL) + Vector((0.0, 0.02, -0.01)))
    print("BOMB DRONE props:", [len(p) for p in props], "faces", sum(len(o.data.polygons) for o in objs))
    bw.export(os.path.join(OUT, "bomb_drone.glb"))


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
    build_bomb_drone()
    build_f1()
    build_suppressor()
