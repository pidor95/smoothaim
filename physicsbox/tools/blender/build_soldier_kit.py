"""Builds the soldiers' kit in Blender:
  assets/npc/npc_rifle.glb    - AK-74M with a red dot (the NPC rifle)
  assets/npc/soldier_gear.glb - helmet ("Helmet", head space) and plate
                                carrier with pouches ("Vest", chest space)

Run:  blender -b --python tools/blender/build_soldier_kit.py

Rifle frame (Godot axes): origin in the middle of the pistol grip, barrel
along -Z, top +Y. Points the game and the pose solver use (npc.gd RIFLE_*,
build_mannequin_anims.py RIFLE_*):
  muzzle     (0, 0.085, -0.69)
  handguard  (0, 0.07, -0.33)    where the support hand holds it
  butt       (0, 0.03, 0.31)     butt plate centre, goes into the shoulder
Gear is modelled around the part centres of npc.gd: head (radius 0.115,
eyes towards -Z) and chest (capsule r 0.17 scaled 1.2 x 0.78).
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Godot -> Blender axes


def gv(x, y, z):
    return C @ Vector((x, y, z))


def material(name, color, metallic=0.0, roughness=0.6):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Metallic"].default_value = metallic
    b.inputs["Roughness"].default_value = roughness
    return m


class Part:
    """One mesh object being assembled from primitives (Godot coordinates)."""

    def __init__(self, name, mat):
        self.bm = bmesh.new()
        self.name = name
        self.mat = mat

    def box(self, c, s, pitch=0.0, yaw=0.0, roll=0.0):
        r = Matrix.Rotation(yaw, 3, "Y") @ Matrix.Rotation(pitch, 3, "X") @ Matrix.Rotation(roll, 3, "Z")
        m = Matrix.Translation(gv(*c)) @ (C @ r @ C.transposed()).to_4x4() @ Matrix.Diagonal((s[0], s[2], s[1], 1))
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)

    def cyl(self, a, b, r1, r2=None, segs=12):
        a, b = gv(*a), gv(*b)
        d = b - a
        m = Matrix.Translation((a + b) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=r1, radius2=r1 if r2 is None else r2,
                              depth=d.length, matrix=m)

    def hull(self, points):
        vs = [self.bm.verts.new(gv(*p)) for p in points]
        bmesh.ops.convex_hull(self.bm, input=vs)

    def finish(self, bevel=0.0, smooth=False):
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(self.mat)
        if bevel > 0:
            mod = ob.modifiers.new("bevel", "BEVEL")
            mod.width = bevel
            mod.segments = 2
            mod.limit_method = "ANGLE"
            bpy.context.view_layer.objects.active = ob
            bpy.ops.object.modifier_apply(modifier="bevel")
        for p in me.polygons:
            p.use_smooth = smooth
        return ob


def export(path, objects):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, use_selection=True,
                              export_cameras=False, export_lights=False, export_animations=False)
    print("EXPORTED", path, os.path.getsize(path))


# ---------------------------------------------------------------- AK-74M

def rifle():
    steel = material("RifleSteel", (0.05, 0.05, 0.055), 0.8, 0.4)
    poly = material("RiflePolymer", (0.07, 0.065, 0.06), 0.0, 0.55)
    glass = material("RedDotLens", (0.6, 0.08, 0.05), 0.2, 0.1)
    m = Part("RifleMetal", steel)
    p = Part("RiflePolymer", poly)
    # receiver with a rounded dust cover, trunnion and rear sight block
    m.box((0, 0.072, -0.07), (0.048, 0.06, 0.25))
    m.cyl((0, 0.1, 0.05), (0, 0.1, -0.17), 0.022, segs=10)
    m.box((0, 0.085, -0.205), (0.05, 0.06, 0.03))
    m.box((0, 0.112, -0.185), (0.03, 0.03, 0.05))
    # barrel, muzzle brake, gas block and tube, front sight
    m.cyl((0, 0.085, -0.21), (0, 0.085, -0.6), 0.011)
    m.cyl((0, 0.085, -0.6), (0, 0.085, -0.69), 0.016)
    m.box((0, 0.105, -0.46), (0.03, 0.05, 0.04))
    m.cyl((0, 0.118, -0.22), (0, 0.118, -0.45), 0.012)
    m.box((0, 0.112, -0.56), (0.018, 0.06, 0.02))
    m.box((0, 0.145, -0.56), (0.004, 0.025, 0.004))
    # handguards (polymer)
    p.hull([(sx * 0.03, y, z) for sx in (-1, 1) for y in (0.045, 0.098) for z in (-0.215, -0.42)])
    p.cyl((0, 0.12, -0.225), (0, 0.12, -0.4), 0.021)
    # magazine: curved, built from segments bending forward
    ang = 0.32
    pos = Vector((0, 0.035, -0.105))
    for k in range(6):
        d = Vector((0, -math.cos(ang), -math.sin(ang)))
        c = pos + d * 0.022
        p.box(tuple(c), (0.026, 0.05, 0.075 - k * 0.002), pitch=ang)
        pos = pos + d * 0.044
        ang += 0.085
    # pistol grip, trigger guard, trigger
    p.box((0, -0.005, 0.012), (0.03, 0.105, 0.042), pitch=-0.3)
    m.box((0, 0.028, -0.045), (0.008, 0.006, 0.07))
    m.box((0, 0.033, -0.022), (0.006, 0.02, 0.006), pitch=0.3)
    # polymer stock: tapering, sloping butt
    p.hull([(sx * 0.022, y, z) for sx in (-1, 1) for y, z in ((0.1, 0.06), (0.05, 0.06), (0.098, 0.3), (-0.06, 0.3))])
    p.box((0, 0.02, 0.315), (0.048, 0.17, 0.03))
    # side rail + red dot
    m.box((0.028, 0.085, -0.06), (0.01, 0.04, 0.12))
    m.box((0.012, 0.135, -0.06), (0.03, 0.02, 0.05))
    m.cyl((0, 0.165, -0.1), (0, 0.165, -0.02), 0.02, segs=14)
    lens = Part("RifleLens", glass)
    lens.cyl((0, 0.165, -0.1), (0, 0.165, -0.098), 0.017, segs=14)
    objs = [m.finish(0.003), p.finish(0.004), lens.finish()]
    export(os.path.join(ROOT, "assets", "npc", "npc_rifle.glb"), objs)
    for o in objs:
        bpy.data.objects.remove(o)


# ---------------------------------------------------------------- helmet and vest

def gear():
    shell = material("Helmet", (0.3, 0.32, 0.22), 0.0, 0.8)
    cloth = material("Vest", (0.22, 0.24, 0.16), 0.0, 0.9)
    strap = material("Strap", (0.1, 0.1, 0.08), 0.0, 0.9)
    # helmet: a dome over the head down to the brow, with ear cut-outs and a rim
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.142)
    for v in bm.verts:
        g = C.transposed() @ v.co  # back to Godot axes
        g.y *= 0.9
        v.co = C @ g
    cut = [v for v in bm.verts if (C.transposed() @ v.co).y < -0.0]
    bmesh.ops.delete(bm, geom=cut, context="VERTS")
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.012)
    # lower at the back and sides than at the brow
    for v in bm.verts:
        g = C.transposed() @ v.co
        if g.y < 0.04:
            g.y -= max(0.0, g.z) * 0.35 + abs(g.x) * 0.1
            v.co = C @ g
    for v in bm.verts:
        v.co += gv(0, 0.035, 0.008)
    me = bpy.data.meshes.new("Helmet")
    bm.to_mesh(me)
    bm.free()
    helmet = bpy.data.objects.new("Helmet", me)
    bpy.context.scene.collection.objects.link(helmet)
    me.materials.append(shell)
    for p in me.polygons:
        p.use_smooth = True
    chin = Part("ChinStrap", strap)
    for sx in (-1, 1):
        chin.box((sx * 0.112, -0.06, 0.0), (0.008, 0.13, 0.016), roll=sx * 0.12)
    chin.box((0, -0.125, -0.045), (0.16, 0.012, 0.02))

    vest = Part("Vest", cloth)
    for z, sgn in ((-0.13, -1), (0.13, 1)):
        vest.hull([(sx * 0.17, y, z + sgn * dz) for sx in (-1, 1) for y in (-0.17, 0.17) for dz in (0.0, 0.045)])
    for sx in (-1, 1):  # cummerbund sides and shoulder straps
        vest.box((sx * 0.2, -0.1, 0.0), (0.035, 0.12, 0.27))
        vest.box((sx * 0.12, 0.2, 0.0), (0.06, 0.03, 0.27))
    for k in range(3):  # magazine pouches on the front
        vest.box(((k - 1) * 0.085, -0.09, -0.195), (0.075, 0.13, 0.05))
        vest.box(((k - 1) * 0.085, -0.02, -0.2), (0.077, 0.03, 0.055))
    vest.box((0.1, 0.09, -0.185), (0.08, 0.07, 0.04))  # admin pouch
    vest.box((-0.11, 0.1, -0.18), (0.05, 0.09, 0.03))  # radio
    objs = [helmet, chin.finish(), vest.finish(0.008)]
    export(os.path.join(ROOT, "assets", "npc", "soldier_gear.glb"), objs)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    rifle()
    gear()


main()
