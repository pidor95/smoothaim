"""Builds the weapons made from Sketchfab models (CC-BY-4.0, see README):
  AK-74M      by SeveN          https://sketchfab.com/3d-models/ak-74m-84bb0a58a18047069706047639b82899
  RGD-5       by _Alexandr      https://sketchfab.com/3d-models/grenade-rgd-5-886637c9482b4cc4960d0112684baac6
  FPV drone   by Kvasovich      https://sketchfab.com/3d-models/fpv-kamikaze-drone-low-poly-87f5bbb5b08641b782bc084ddd4082a7

Outputs:
  assets/weapons/ak74_fp.glb     first-person AK-74M with gloved hands: idle,
                                 fire, reload, reload_empty, draw
  assets/weapons/grenade_fp.glb  first-person grenade throw: right hand with
                                 an RGD-5, left hand pulls the ring ("throw")
  assets/npc/npc_rifle.glb       the soldiers' AK (rifle frame of npc.gd)
  assets/weapons/grenade.glb     the thrown RGD-5 (origin at the body centre)
  assets/weapons/fpv_drone.glb   the FPV drone, props split off as Prop0..3

Run (sources fetched by tools/fetch_sketchfab.py into tools/model_sources/):
  blender -b --python tools/blender/build_sketchfab_kit.py [-- preview_dir]
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import build_weapons as bw  # noqa: E402  (helpers: capsule, fist, Clip, export...)

ROOT = bw.ROOT
SRC = os.path.join(ROOT, "tools", "model_sources")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
bw.PREVIEW = ARGS[0] if ARGS else ""

AK_SCALE = 0.1007  # model is 9.37 units long; an AK-74M is 0.943 m
RGD_SCALE = 0.023
RGD_CENTER = Vector((0.0, 0.0, 0.45))  # middle of the egg in model units


# ---------------------------------------------------------------- import helpers

def import_gltf(name):
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name, "scene.gltf"))
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in [o for o in bpy.context.scene.objects if o.type == "EMPTY"]:
        bpy.data.objects.remove(o)
    for o in meshes:
        bw.apply_all(o)
    return meshes


def shrink_images(size):
    for img in bpy.data.images:
        if img.size[0] > size:
            img.scale(size, size)


def decimate(o, faces):
    n = len(o.data.polygons)
    if n > faces:
        mod = o.modifiers.new("dec", "DECIMATE")
        mod.ratio = faces / n
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)


def transform(objs, m):
    for o in objs:
        o.matrix_world = m @ o.matrix_world
        bw.apply_all(o)


def separate_loose(o):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.mesh.separate(type="LOOSE")
    return [x for x in bpy.context.selected_objects]


def centre(o):
    vs = [o.matrix_world @ v.co for v in o.data.vertices]
    lo = Vector([min(v[i] for v in vs) for i in range(3)])
    hi = Vector([max(v[i] for v in vs) for i in range(3)])
    return (lo + hi) / 2, hi - lo


# ---------------------------------------------------------------- AK-74M

def ak_parts():
    """Imports the AK in model units: barrel +Y, top +Z, right +X.
    Returns (body, mag, bolt) objects and the grip point."""
    meshes = import_gltf("ak74m")
    by = {}
    for o in meshes:
        by[o.name] = o
    names = {o.name: o for o in meshes}
    # Sketchfab node names were Stock_low_0 -> Object_4 etc.; find parts by extent
    mag = bolt = grip_obj = None
    for o in meshes:
        c, s = centre(o)
        if s.z > 1.8 and c.z < 0.0:
            mag = o  # the only part hanging that far down
        elif 1.0 < s.y < 1.7 and c.z > 0.9 and c.x > 0.1:
            bolt = o  # charging handle on the right side
        elif 0.7 < s.y < 0.85 and s.z > 1.0 and c.z < 0.2 and abs(c.y + 1.86) < 0.3:
            grip_obj = o
    assert mag and bolt and grip_obj, (mag, bolt, grip_obj, list(names))
    vs = [grip_obj.matrix_world @ v.co for v in grip_obj.data.vertices]
    mid = [v for v in vs if -0.35 < v.z < 0.2]
    grip = sum(mid, Vector()) / len(mid)
    grip.x = 0.0
    body = bw.join([o for o in meshes if o not in (mag, bolt)], "AK")
    mag.name = "Mag"
    bolt.name = "Bolt"
    return body, mag, bolt, grip


def build_ak_fp():
    bw.reset()
    body, mag, bolt, grip_m = ak_parts()
    shrink_images(2048)
    s = AK_SCALE
    grip = Vector((0.13, 0.27, -0.23))  # camera-space hip position of the grip
    yaw = math.radians(3.0)
    rot = Matrix.Rotation(yaw, 4, "Z")
    to_cam = Matrix.Translation(grip) @ rot @ Matrix.Scale(s, 4) @ Matrix.Translation(-grip_m)
    transform([body, mag, bolt], to_cam)
    for o in (body, mag, bolt):
        for p in o.data.polygons:
            p.use_smooth = True

    def g(model_v):  # model units -> camera space
        return grip + rot.to_3x3() @ ((Vector(model_v) - grip_m) * s)

    glove, _ = bw.gloves()
    sleeve = bw.material("SleeveCamo", (0.075, 0.085, 0.055), roughness=0.95)
    guard = g((0.0, 1.0, 0.42))  # under the handguard
    hand_r = bw.fist("HandR", g((0.0, grip_m.y, grip_m.z + 0.15)), glove, rot=(-22, 0, 0), scale=(1.1, 1.0, 1.35))
    arm_r = bw.limb_between("ArmR", g((0.0, grip_m.y - 0.6, grip_m.z - 0.2)), (0.32, -0.08, -0.5), 0.046, sleeve)
    hand_l = bw.fist("HandL", guard, glove, rot=(0, 0, 0), scale=(1.2, 1.55, 1.1))
    arm_l = bw.limb_between("ArmL", guard + Vector((-0.01, -0.035, -0.035)), (-0.24, 0.0, -0.48), 0.046, sleeve)
    mag_pos = g((0.0, -0.4, 0.2))  # where the old magazine sits, top of the well
    mag_new = mag.copy()
    mag_new.data = mag.data.copy()
    mag_new.name = "MagNew"
    bpy.context.scene.collection.objects.link(mag_new)
    # the new magazine is carried by the support hand: it sits in the well
    # when the hand is at INSERT (relative to the hand's rest on the handguard)
    INSERT = mag_pos - guard + Vector((0.0, -0.02, -0.07))
    mag_new.matrix_world = Matrix.Translation(-INSERT) @ mag_new.matrix_world
    bw.apply_all(mag_new)

    arm = bw.make_armature([
        ("gun", grip, None),
        ("bolt", g((0.25, -0.3, 1.05)), "gun"),
        ("mag", mag_pos, "gun"),
        ("hand_l", guard, "gun"),
        ("mag_new", guard, "hand_l"),
        ("muzzle", g((0.0, 4.72, 0.99)), "gun"),
        ("eject", g((0.22, -0.55, 0.98)), "gun"),
        ("sight", g((0.0, 0.18, 1.30)), "gun"),
    ])
    for o, b in [(body, "gun"), (hand_r, "gun"), (arm_r, "gun"), (bolt, "bolt"), (mag, "mag"),
                 (hand_l, "hand_l"), (arm_l, "hand_l"), (mag_new, "mag_new")]:
        bw.bind(o, arm, b)

    MAG_AT = tuple(mag_pos - guard + Vector((0.0, 0.01, -0.05)))  # hand on the old magazine
    BOLT_AT = tuple(g((0.3, -0.3, 1.0)) - guard)
    AWAY = (-0.15, -0.3, -0.35)

    c = bw.Clip(arm, "idle")
    c.key("mag_new", 0, scale=0.0)
    c.hold_all([0, 1])
    c.finish()

    c = bw.Clip(arm, "fire")
    c.key("mag_new", 0, scale=0.0)
    c.hold_all([0])
    c.key("gun", 0, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key("gun", 1, loc=(0.002, -0.022, 0.006), rot=(3.0, 0, -0.8))
    c.key("gun", 3, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key("bolt", 0, loc=(0, 0, 0))
    c.key("bolt", 1, loc=(0, -0.075, 0))
    c.key("bolt", 2, loc=(0, 0, 0))
    c.finish()

    for name, empty in (("reload", False), ("reload_empty", True)):
        c = bw.Clip(arm, name)
        c.hold_all([0])
        tilt = dict(loc=(-0.05, 0.03, 0.04), rot=(10, -6, -28))
        end = 56 if not empty else 72
        c.key("gun", 0, loc=(0, 0, 0), rot=(0, 0, 0))
        c.key("gun", 7, **tilt)
        c.key("gun", end - 10, **tilt)
        c.key("gun", end, loc=(0, 0, 0), rot=(0, 0, 0))
        # support hand grabs the old magazine and rocks it out
        c.step("mag_new", 0, scale=0.0)
        c.key("hand_l", 0, loc=(0, 0, 0), rot=(0, 0, 0))
        c.key("hand_l", 9, loc=MAG_AT, rot=(-10, 0, 0))
        c.key("mag", 0, loc=(0, 0, 0), rot=(0, 0, 0), scale=1.0)
        c.key("mag", 10, loc=(0, 0, 0), rot=(0, 0, 0))
        c.key("hand_l", 15, loc=tuple(Vector(MAG_AT) + Vector((0, 0.05, -0.12))), rot=(-25, 0, 0))
        c.key("mag", 15, loc=(0, 0.05, -0.12), rot=(-25, 0, 0))
        c.key("hand_l", 21, loc=AWAY, rot=(-40, 0, 0))
        c.key("mag", 21, loc=tuple(Vector(AWAY) - Vector(MAG_AT)), rot=(-40, 0, 0))
        c.step("mag", 21, scale=0.0)
        # ...and comes back with a fresh one
        c.step("mag_new", 22, scale=1.0)
        c.key("hand_l", 31, loc=tuple(INSERT + Vector((0, 0.05, -0.1))), rot=(-22, 0, 0))
        c.key("hand_l", 36, loc=tuple(INSERT + Vector((0, 0.01, -0.01))), rot=(-6, 0, 0))
        c.key("hand_l", 39, loc=tuple(INSERT), rot=(0, 0, 0))
        c.step("mag", 39, loc=(0, 0, 0), rot=(0, 0, 0), scale=1.0)
        c.step("mag_new", 39, scale=0.0)
        c.key("hand_l", 41, loc=tuple(INSERT), rot=(0, 0, 0))
        if empty:
            # over the top to the charging handle, rack it
            c.key("hand_l", 50, loc=tuple(Vector(BOLT_AT) + Vector((0.02, 0.06, 0.05))), rot=(0, 0, 0))
            c.key("hand_l", 53, loc=BOLT_AT, rot=(0, 0, 0))
            c.key("bolt", 53, loc=(0, 0, 0))
            c.key("hand_l", 56, loc=tuple(Vector(BOLT_AT) + Vector((0, -0.08, 0))), rot=(0, 0, 0))
            c.key("bolt", 56, loc=(0, -0.08, 0))
            c.key("bolt", 58, loc=(0, 0, 0))
            c.key("hand_l", 58, loc=tuple(Vector(BOLT_AT) + Vector((0.03, -0.1, 0.04))), rot=(0, 0, 0))
        c.key("hand_l", end - 3, loc=(0, 0, 0), rot=(0, 0, 0))
        c.key("hand_l", end, loc=(0, 0, 0), rot=(0, 0, 0))
        c.finish()

    c = bw.Clip(arm, "draw")
    c.key("mag_new", 0, scale=0.0)
    c.hold_all([0])
    c.key("gun", 0, loc=(0, -0.12, -0.28), rot=(-45, 0, 30))
    c.key("gun", 13, loc=(0, 0, 0), rot=(0, 0, 0))
    c.finish()

    bw.preview("ak74", [("idle", 0), ("fire", 1), ("reload", 15), ("reload", 36), ("reload_empty", 56)])
    bw.export(os.path.join(bw.OUT_DIR, "ak74_fp.glb"))


def build_npc_rifle():
    """The soldiers' AK in the rifle frame of npc.gd: origin in the middle of
    the pistol grip, barrel along Godot -Z (Blender +Y), top up."""
    bw.reset()
    body, mag, bolt, grip_m = ak_parts()
    shrink_images(512)
    ak = bw.join([body, mag, bolt], "AK")
    transform([ak], Matrix.Scale(AK_SCALE, 4) @ Matrix.Translation(-grip_m))
    decimate(ak, 4000)
    for p in ak.data.polygons:
        p.use_smooth = True
    for m in ak.data.materials:  # no normal map at this size
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        for link in list(bsdf.inputs["Normal"].links):
            m.node_tree.links.remove(link)
    muzzle = (Vector((0.0, 4.72, 0.99)) - grip_m) * AK_SCALE
    print("NPC RIFLE muzzle (Godot) = (0, %.3f, %.3f)" % (muzzle.z, -muzzle.y))
    bw.export(os.path.join(ROOT, "assets", "npc", "npc_rifle.glb"))


# ---------------------------------------------------------------- RGD-5

def rgd_parts():
    """The standing RGD-5 (the model has a second one lying down), scaled
    to metres around the middle of its body; returns (body, ring)."""
    meshes = import_gltf("rgd5")
    keep = None
    for o in meshes:
        c, s = centre(o)
        if s.z > 5.0:
            keep = o
        else:
            bpy.data.objects.remove(o)
    ring_parts = []
    rest = []
    for p in separate_loose(keep):
        c, s = centre(p)
        (ring_parts if c.x < -0.3 and c.y > 0.3 and c.z > 2.4 else rest).append(p)
    body = bw.join(rest, "Grenade")
    ring = bw.join(ring_parts, "Ring")
    transform([body, ring], Matrix.Scale(RGD_SCALE, 4) @ Matrix.Translation(-RGD_CENTER))
    for o in (body, ring):
        for p in o.data.polygons:
            p.use_smooth = True
    return body, ring


def build_grenade():
    bw.reset()
    body, ring = rgd_parts()
    shrink_images(512)
    bw.join([body, ring], "Grenade")
    bw.export(os.path.join(ROOT, "assets", "weapons", "grenade.glb"))


# throw clip: the physical grenade is let go at this frame (weapon.gd THROW_RELEASE)
RELEASE = 25


def build_grenade_fp():
    bw.reset()
    body, ring = rgd_parts()
    shrink_images(1024)
    glove, _ = bw.gloves()
    sleeve = bw.material("SleeveCamo", (0.075, 0.085, 0.055), roughness=0.95)
    hold = Vector((0.16, 0.42, -0.2))  # the grenade in front, held low on the right
    transform([body, ring], Matrix.Translation(hold))
    hand_r = bw.fist("HandR", hold + Vector((0.012, -0.012, -0.03)), glove, rot=(-60, 0, 10), scale=(1.25, 1.1, 1.3))
    arm_r = bw.limb_between("ArmR", hold + Vector((0.02, -0.05, -0.06)), (0.3, -0.1, -0.55), 0.046, sleeve)
    ring_at = hold + Vector((-0.014, 0.014, 0.054))  # the ring, in camera space
    hand_l = bw.fist("HandL", ring_at + Vector((-0.02, -0.01, 0.0)), glove, rot=(0, 0, -70), scale=(1.1, 1.2, 1.1))
    arm_l = bw.limb_between("ArmL", ring_at + Vector((-0.04, -0.04, -0.03)), (-0.28, -0.05, -0.5), 0.046, sleeve)
    ring_l = ring.copy()  # the ring once it is pulled, in the left hand
    ring_l.data = ring.data.copy()
    ring_l.name = "RingPulled"
    bpy.context.scene.collection.objects.link(ring_l)

    arm = bw.make_armature([
        ("hand_r", hold, None),
        ("grenade", hold, "hand_r"),
        ("ring", ring_at, "grenade"),
        ("hand_l", ring_at, None),
        ("ring_l", ring_at, "hand_l"),
    ])
    for o, b in [(hand_r, "hand_r"), (arm_r, "hand_r"), (body, "grenade"), (ring, "ring"),
                 (hand_l, "hand_l"), (arm_l, "hand_l"), (ring_l, "ring_l")]:
        bw.bind(o, arm, b)

    LOW = (0.05, -0.15, -0.3)
    c = bw.Clip(arm, "throw")
    c.hold_all([0])
    # up into view, the left hand comes to the ring
    c.key("hand_r", 0, loc=LOW, rot=(-30, 0, 0))
    c.key("hand_r", 7, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key("hand_l", 0, loc=(-0.15, -0.15, -0.3), rot=(0, 0, 0))
    c.key("hand_l", 7, loc=(-0.04, -0.03, -0.03), rot=(0, 0, 0))
    c.key("hand_l", 10, loc=(0, 0, 0), rot=(0, 0, 0))
    c.step("ring_l", 0, scale=0.0)
    c.step("ring", 0, scale=1.0)
    c.step("grenade", 0, scale=1.0)
    c.step("ring_l", 13, scale=1.0)
    c.step("ring", 13, scale=0.0)
    # pull the ring out and away
    c.key("hand_l", 12, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key("hand_l", 16, loc=(-0.1, -0.02, 0.03), rot=(0, 0, 25))
    c.key("hand_l", 22, loc=(-0.25, -0.12, -0.3), rot=(0, 0, 40))
    # wind up: the arm goes back over the shoulder
    c.key("hand_r", 12, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key("hand_r", 20, loc=(0.06, -0.3, 0.2), rot=(40, 0, -10))
    c.key("hand_r", 22, loc=(0.06, -0.33, 0.22), rot=(45, 0, -10))
    # ...and the swing over, let go
    c.key("hand_r", RELEASE, loc=(-0.02, 0.05, 0.16), rot=(-20, 0, 5))
    c.step("grenade", RELEASE, scale=0.0)
    c.key("hand_r", 29, loc=(-0.06, 0.12, -0.12), rot=(-70, 0, 10))
    c.key("hand_r", 34, loc=LOW, rot=(-80, 0, 0))
    c.finish()
    bw.preview("grenade", [("throw", 8), ("throw", 16), ("throw", 22), ("throw", 26)])
    bw.export(os.path.join(bw.OUT_DIR, "grenade_fp.glb"))


# ---------------------------------------------------------------- FPV drone

HUBS = [Vector((-0.089, 0.088)), Vector((-0.089, -0.090)), Vector((0.090, 0.088)), Vector((0.090, -0.090))]


def build_drone():
    bw.reset()
    (src,) = import_gltf("fpv")
    shrink_images(1024)
    props = [[] for _ in HUBS]
    frame = []
    for p in separate_loose(src):
        c, s = centre(p)
        hub = None
        for k, h in enumerate(HUBS):
            d = (c.xy - h).length
            if 0.02 < d < 0.05 and 0.005 < c.z < 0.016 and max(s.x, s.y) > 0.012:
                hub = k
        (props[hub] if hub is not None else frame).append(p)
    body = bw.join(frame, "Frame")
    # nose (warhead tip) was along -Y: turn it to +Y (Godot -Z, forward)
    turn = Matrix.Rotation(math.pi, 4, "Z")
    transform([body], turn)
    decimate(body, 9000)
    objs = [body]
    for k, parts in enumerate(props):
        pr = bw.join(parts, "Prop%d" % k)
        transform([pr], turn)
        h = turn @ Vector((HUBS[k].x, HUBS[k].y, 0.011))
        # origin on the motor axis so the game can spin it in place
        pr.data.transform(Matrix.Translation(-h))
        pr.location = h
        objs.append(pr)
    for o in objs:
        for p in o.data.polygons:
            p.use_smooth = True
    print("DRONE props:", [len(p) for p in props])
    bw.export(os.path.join(ROOT, "assets", "weapons", "fpv_drone.glb"))


if __name__ == "__main__":
    build_ak_fp()
    build_grenade_fp()
    build_npc_rifle()
    build_grenade()
    build_drone()
