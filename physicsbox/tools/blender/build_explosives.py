"""Builds the explosives in Blender:
  assets/weapons/grenade.glb    - RGD-5 hand grenade (egg body, UZRGM fuse,
                                  spoon, ring); origin at the body's centre
  assets/weapons/fpv_drone.glb  - 7-inch FPV kamikaze drone: carbon X frame,
                                  motors, camera, battery, antennas and a PG-7
                                  warhead taped under it. Props are separate
                                  objects Prop0..Prop3 (spun by the game).

Run:  blender -b --python tools/blender/build_explosives.py

Godot axes as everywhere: +Y up, -Z forward.
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

    def sphere(self, c, r, scale=(1, 1, 1), segs=16):
        m = Matrix.Translation(gv(*c)) @ Matrix.Diagonal((scale[0], scale[2], scale[1], 1))
        bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=segs // 2 + 2, radius=r, matrix=m)

    def torus(self, c, r_major, r_minor, axis_pitch=0.0):
        """Ring in the XZ plane (Godot), tipped about X."""
        m = Matrix.Translation(gv(*c)) @ (C @ Matrix.Rotation(axis_pitch, 3, "X") @ C.transposed()).to_4x4()
        n = 16
        for i in range(n):
            a0, a1 = i / n * math.tau, (i + 1) / n * math.tau
            p0 = Vector((math.cos(a0) * r_major, 0, math.sin(a0) * r_major))
            p1 = Vector((math.cos(a1) * r_major, 0, math.sin(a1) * r_major))
            d = p1 - p0
            mm = m @ Matrix.Translation(C @ ((p0 + p1) / 2)) @ (C @ d).to_track_quat("Z", "Y").to_matrix().to_4x4()
            bmesh.ops.create_cone(self.bm, cap_ends=False, segments=6, radius1=r_minor, radius2=r_minor,
                                  depth=d.length * 1.05, matrix=mm)

    def finish(self, smooth=False, bevel=0.0):
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
    for o in objects:
        bpy.data.objects.remove(o)


def grenade():
    olive = material("GrenadeBody", (0.24, 0.27, 0.17), 0.3, 0.55)
    steel = material("GrenadeFuse", (0.35, 0.35, 0.33), 0.8, 0.35)
    body = Part("GrenadeBody", olive)
    body.sphere((0, 0, 0), 0.029, (1, 1.12, 1), 18)
    body.cyl((0, 0.028, 0), (0, 0.036, 0), 0.013)  # fuse well collar
    fuse = Part("GrenadeFuse", steel)
    fuse.cyl((0, 0.036, 0), (0, 0.062, 0), 0.0085)
    fuse.box((0.0, 0.065, 0.0), (0.02, 0.008, 0.02))
    # spoon: runs from the fuse head down the side of the body
    fuse.box((0.0, 0.062, -0.012), (0.012, 0.004, 0.022))
    fuse.box((0.0, 0.035, -0.031), (0.012, 0.05, 0.004), pitch=0.12)
    fuse.box((0.0, 0.005, -0.034), (0.011, 0.03, 0.004), pitch=-0.05)
    fuse.torus((0.017, 0.05, 0.0), 0.011, 0.0015, 1.4)  # pull ring
    export(os.path.join(ROOT, "assets", "weapons", "grenade.glb"), [body.finish(True), fuse.finish(True)])


def drone():
    carbon = material("Carbon", (0.03, 0.03, 0.035), 0.2, 0.45)
    motor = material("Motor", (0.25, 0.05, 0.05), 0.7, 0.35)
    prop_m = material("Prop", (0.05, 0.05, 0.05), 0.0, 0.5)
    batt = material("Battery", (0.1, 0.14, 0.3), 0.1, 0.5)
    warhead_m = material("Warhead", (0.27, 0.3, 0.19), 0.3, 0.55)
    tape = material("Tape", (0.04, 0.04, 0.04), 0.0, 0.35)
    lens = material("Lens", (0.02, 0.02, 0.03), 0.6, 0.1)
    frame = Part("Frame", carbon)
    # X frame: two arms, bottom + top plates, standoffs
    span = 0.145  # centre to motor
    for sx, sz in ((1, 1), (1, -1)):
        a = Vector((sx * span, 0, sz * span))
        frame.box((0, 0, 0), (0.024, 0.005, 2 * span * math.sqrt(2) + 0.03),
                  yaw=math.atan2(a.x, a.z))
    frame.box((0, 0.0, 0.0), (0.06, 0.004, 0.14))
    frame.box((0, 0.032, 0.0), (0.05, 0.003, 0.12))
    for sx in (-1, 1):
        for sz in (-1, 1):
            frame.cyl((sx * 0.02, 0.0, sz * 0.05), (sx * 0.02, 0.032, sz * 0.05), 0.003, segs=6)
    # FPV camera between the plates, tilted up 25 degrees, and its antenna
    frame.box((0, 0.016, -0.06), (0.03, 0.026, 0.006))
    cam = Part("Camera", lens)
    cam.cyl((0, 0.017, -0.064), (0, 0.017 + 0.009 * math.sin(0.44), -0.064 - 0.02), 0.009, segs=10)
    frame.cyl((0, 0.034, 0.055), (0, 0.075, 0.09), 0.003, segs=6)  # VTX antenna
    frame.sphere((0, 0.077, 0.092), 0.008, (1, 1, 1), 8)
    for sx in (-1, 1):  # receiver antennas
        frame.cyl((sx * 0.02, 0.034, 0.06), (sx * 0.05, 0.034, 0.1), 0.0012, segs=4)
    mot = Part("Motors", motor)
    for sx in (-1, 1):
        for sz in (-1, 1):
            mot.cyl((sx * span, 0.003, sz * span), (sx * span, 0.03, sz * span), 0.017, segs=14)
            mot.cyl((sx * span, 0.03, sz * span), (sx * span, 0.038, sz * span), 0.004, segs=8)
    bat = Part("Battery", batt)
    bat.box((0, 0.055, 0.0), (0.042, 0.038, 0.11))
    frame.box((0, 0.055, 0.0), (0.046, 0.04, 0.012))  # strap
    # PG-7 warhead strapped under the frame, nose forward
    wh = Part("Warhead", warhead_m)
    wh.cyl((0, -0.045, 0.06), (0, -0.045, -0.06), 0.042, segs=16)
    wh.cyl((0, -0.045, -0.06), (0, -0.045, -0.14), 0.042, 0.02, segs=16)
    wh.cyl((0, -0.045, -0.14), (0, -0.045, -0.175), 0.02, 0.006, segs=12)
    wh.cyl((0, -0.045, 0.06), (0, -0.045, 0.1), 0.042, 0.018, segs=16)
    wh.cyl((0, -0.045, 0.1), (0, -0.045, 0.17), 0.016, segs=10)
    tp = Part("Tape", tape)
    for z in (-0.02, 0.04):
        tp.cyl((0, -0.045, z - 0.01), (0, -0.045, z + 0.01), 0.0435, segs=16)
        tp.box((0, -0.005, z), (0.03, 0.04, 0.02))
    objs = [frame.finish(), cam.finish(), mot.finish(True), bat.finish(bevel=0.004), wh.finish(True), tp.finish()]
    # props: 3 blades each, own objects at the motors so the game can spin them
    for k, (sx, sz) in enumerate(((1, -1), (-1, -1), (1, 1), (-1, 1))):
        pr = Part("Prop%d" % k, prop_m)
        for b in range(3):
            ang = b * math.tau / 3
            pr.box((math.sin(ang) * 0.045, 0.0, math.cos(ang) * 0.045), (0.018, 0.0025, 0.09), yaw=ang, roll=0.25)
        pr.sphere((0, 0, 0), 0.007, (1, 0.8, 1), 8)
        ob = pr.finish()
        ob.location = gv(sx * span, 0.041, sz * span)
        objs.append(ob)
    export(os.path.join(ROOT, "assets", "weapons", "fpv_drone.glb"), objs)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    grenade()
    drone()


main()
