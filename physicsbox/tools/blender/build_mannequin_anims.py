"""Builds the mannequin armature and its animation library in Blender and
exports it as assets/npc/mannequin_anims.glb.

Run:  blender -b --python tools/blender/build_mannequin_anims.py

The bones match the rigid body parts used by scripts/npc.gd (same pivots), so
the game samples these clips and places each physics part from its bone.

Poses are written in the game's NPC frame (Godot axes: +Y up, -Z forward)
with these conventions (degrees):
  thigh +X leg forward, shin -X knee bends back, uarm +X arm forward,
  uarm Z raises the arm sideways (left -, right +), farm +X elbow bends,
  chest -X leans forward, head +X tilts back, pelvis rotates the whole body.
Clips:
  idle, walk, panic_run                      - loops
  stagger_back/fwd/left/right, stagger_head,  - balance recoveries after a hit,
  limp_l/r, spin_l/r, knee_fall_l/r            full body, with root motion
  getup_back, getup_front                    - standing up from the floor
"""
import math
import os

import bpy
from mathutils import Euler, Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "npc", "mannequin_anims.glb")
FPS = 30

# name: (head, tail, parent) in Godot coordinates
BONES = [
    ("pelvis", (0, 0.93, 0), (0, 1.08, 0), None),
    ("chest", (0, 1.08, 0), (0, 1.55, 0), "pelvis"),
    ("head", (0, 1.55, 0), (0, 1.85, 0), "chest"),
    ("uarm_l", (-0.265, 1.47, 0), (-0.265, 1.19, 0), "chest"),
    ("farm_l", (-0.265, 1.19, 0), (-0.265, 0.86, 0), "uarm_l"),
    ("uarm_r", (0.265, 1.47, 0), (0.265, 1.19, 0), "chest"),
    ("farm_r", (0.265, 1.19, 0), (0.265, 0.86, 0), "uarm_r"),
    ("thigh_l", (-0.1, 0.93, 0), (-0.1, 0.5, 0), "pelvis"),
    ("shin_l", (-0.1, 0.5, 0), (-0.1, 0.08, 0), "thigh_l"),
    ("thigh_r", (0.1, 0.93, 0), (0.1, 0.5, 0), "pelvis"),
    ("shin_r", (0.1, 0.5, 0), (0.1, 0.08, 0), "thigh_r"),
]
NAMES = [b[0] for b in BONES]
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Godot -> Blender axes


def gv(v):
    return C @ Vector(v)


def build_armature():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.ops.object.armature_add(enter_editmode=True)
    arm = bpy.context.active_object
    arm.name = "Mannequin"
    arm.data.name = "Mannequin"
    eb = arm.data.edit_bones
    eb.remove(eb[0])
    for name, head, tail, parent in BONES:
        b = eb.new(name)
        b.head = gv(head)
        b.tail = gv(tail)
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    # a tiny skinned mesh so the exporter writes a proper skin / Skeleton3D
    bpy.ops.mesh.primitive_cube_add(size=0.02)
    cube = bpy.context.active_object
    cube.name = "SkinAnchor"
    vg = cube.vertex_groups.new(name="pelvis")
    vg.add([v.index for v in cube.data.vertices], 1.0, "REPLACE")
    cube.parent = arm
    mod = cube.modifiers.new("arm", "ARMATURE")
    mod.object = arm
    return arm


def godot_rot(deg):
    """Euler in Godot order (YXZ) -> rotation matrix in Blender axes."""
    x, y, z = (math.radians(a) for a in deg)
    r = Euler((x, y, z), "ZXY").to_matrix()  # Ry * Rx * Rz
    return C @ r @ C.transposed()


class Clip:
    def __init__(self, arm, name):
        self.arm = arm
        self.action = bpy.data.actions.new(name)
        self.action.use_fake_user = True
        arm.animation_data_create()
        arm.animation_data.action = self.action

    def pose(self, frame, rots=None, pelvis_loc=(0, 0, 0)):
        """Keys a full pose. rots: {bone: (x, y, z) degrees in the NPC frame}."""
        rots = rots or {}
        for pb in self.arm.pose.bones:
            b = pb.bone.matrix_local.to_3x3()
            r = godot_rot(rots.get(pb.name, (0, 0, 0)))
            local = b.inverted() @ r @ b
            pb.rotation_quaternion = local.to_quaternion()
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            if pb.name == "pelvis":
                pb.location = b.inverted() @ gv(pelvis_loc)
            else:
                pb.location = (0, 0, 0)
            pb.keyframe_insert("location", frame=frame)

    def finish(self):
        track = self.arm.animation_data.nla_tracks.new()
        track.name = self.action.name
        track.strips.new(self.action.name, 0, self.action)
        self.arm.animation_data.action = None


def mirror(rots):
    """Left/right mirror of a pose dict."""
    out = {}
    for k, (x, y, z) in rots.items():
        if k.endswith("_l"):
            k = k[:-2] + "_r"
        elif k.endswith("_r"):
            k = k[:-2] + "_l"
        out[k] = (x, -y, -z)
    return out


# ---------------------------------------------------------------- loops

def idle(arm):
    c = Clip(arm, "idle")
    a = {"chest": (1.5, 0, 0), "uarm_l": (0, 0, -4), "uarm_r": (0, 0, 4), "farm_l": (10, 0, 0), "farm_r": (10, 0, 0),
         "thigh_l": (0, 0, -2), "thigh_r": (0, 0, 2)}
    b = {"chest": (-1.5, 2, 0), "head": (3, 5, 0), "uarm_l": (2, 0, -6), "uarm_r": (-1, 0, 5), "farm_l": (14, 0, 0),
         "farm_r": (8, 0, 0), "thigh_l": (0, 0, -2), "thigh_r": (0, 0, 2)}
    c.pose(0, a)
    c.pose(45, b, (0, -0.006, 0))
    c.pose(90, a)
    c.finish()


def cycle(arm, name, frames, stride, knee, arm_swing, lean, bob, arms_up=0.0, keys=12):
    c = Clip(arm, name)
    for i in range(keys + 1):
        t = i / keys
        ph = t * 2 * math.pi
        s = math.sin(ph)
        k_l = -max(0.0, math.sin(ph + 1.6)) * knee
        k_r = -max(0.0, math.sin(ph + 1.6 + math.pi)) * knee
        swing = -s * arm_swing
        flail = math.sin(ph * 2) * 18 * arms_up
        raise_ = 150 * arms_up + 5
        elbow = 15 + 10 * abs(s) + 25 * arms_up
        rots = {
            "pelvis": (0, s * 5, 0),
            "chest": (-lean, -s * 8, 0),
            "head": (lean * 0.5 + 8 * arms_up, s * 4, 0),
            "thigh_l": (s * stride, 0, 0), "thigh_r": (-s * stride, 0, 0),
            "shin_l": (k_l, 0, 0), "shin_r": (k_r, 0, 0),
            "uarm_l": (swing * (1 - arms_up) + flail, 0, -raise_),
            "uarm_r": (-swing * (1 - arms_up) - flail, 0, raise_),
            "farm_l": (elbow, 0, 0), "farm_r": (elbow, 0, 0),
        }
        c.pose(round(t * frames), rots, (0, -abs(s) * bob, 0))
    c.finish()


# ---------------------------------------------------------------- reactions

def reaction(arm, name, keys, mirror_to=None):
    """keys: [(frame, rots, pelvis_loc)]; first and last should be rest."""
    for nm, flip in ((name, False), (mirror_to, True)):
        if nm is None:
            continue
        c = Clip(arm, nm)
        for frame, rots, loc in keys:
            r = mirror(rots) if flip else rots
            l = (-loc[0], loc[1], loc[2]) if flip else loc
            c.pose(frame, r, l)
        c.finish()


REST = ({}, (0, 0, 0))


def staggers(arm):
    """Full-body balance recoveries. The pelvis location carries root motion:
    the game moves the NPC by its horizontal travel so the steps are real."""
    # shot in the chest from the front: thrown back, three stumbling steps
    # backwards with windmilling arms, leans forward and catches himself
    reaction(arm, "stagger_back", [
        (0, *REST),
        (3, {"chest": (24, 0, 0), "head": (26, 0, 0), "uarm_l": (45, 0, -20), "uarm_r": (40, 0, 22),
             "farm_l": (25, 0, 0), "farm_r": (25, 0, 0), "thigh_r": (-14, 0, 0), "thigh_l": (8, 0, 0)}, (0, -0.02, 0.06)),
        (8, {"chest": (20, -6, 0), "head": (14, 0, 0), "uarm_l": (85, 0, -40), "uarm_r": (-20, 0, 65),
             "farm_l": (30, 0, 0), "farm_r": (45, 0, 0), "thigh_r": (-32, 0, 0), "shin_r": (-45, 0, 0),
             "thigh_l": (16, 0, 0), "shin_l": (-6, 0, 0)}, (0, -0.03, 0.17)),
        (13, {"chest": (15, 0, 0), "head": (8, 0, 0), "uarm_l": (30, 0, -85), "uarm_r": (65, 0, 40),
              "farm_l": (40, 0, 0), "farm_r": (20, 0, 0), "thigh_r": (-18, 0, 0), "shin_r": (-6, 0, 0),
              "thigh_l": (24, 0, 0), "shin_l": (-12, 0, 0)}, (0, -0.02, 0.31)),
        (18, {"chest": (12, 6, 0), "head": (5, 0, 0), "uarm_l": (-30, 0, -65), "uarm_r": (100, 0, 30),
              "farm_l": (50, 0, 0), "farm_r": (30, 0, 0), "thigh_l": (-32, 0, 0), "shin_l": (-48, 0, 0),
              "thigh_r": (12, 0, 0), "shin_r": (-14, 0, 0)}, (0, -0.04, 0.46)),
        (23, {"chest": (5, 0, 0), "uarm_l": (55, 0, -50), "uarm_r": (20, 0, 75), "farm_l": (30, 0, 0),
              "farm_r": (40, 0, 0), "thigh_l": (-16, 0, 0), "shin_l": (-5, 0, 0), "thigh_r": (20, 0, 0),
              "shin_r": (-10, 0, 0)}, (0, -0.03, 0.6)),
        (28, {"chest": (-6, 0, 0), "head": (-4, 0, 0), "uarm_l": (20, 0, -55), "uarm_r": (25, 0, 55),
              "farm_l": (35, 0, 0), "farm_r": (35, 0, 0), "thigh_r": (-22, 0, 0), "shin_r": (-32, 0, 0),
              "thigh_l": (8, 0, 0), "shin_l": (-8, 0, 0)}, (0, -0.05, 0.7)),
        (33, {"chest": (-14, 0, 0), "head": (-10, 0, 0), "uarm_l": (10, 0, -35), "uarm_r": (10, 0, 35),
              "farm_l": (35, 0, 0), "farm_r": (35, 0, 0), "thigh_r": (-8, 0, 0), "thigh_l": (6, 0, 0),
              "shin_l": (-14, 0, 0), "shin_r": (-14, 0, 0)}, (0, -0.07, 0.76)),
        (41, {"chest": (-6, 0, 0), "uarm_l": (5, 0, -15), "uarm_r": (5, 0, 15), "farm_l": (20, 0, 0),
              "farm_r": (20, 0, 0)}, (0, -0.025, 0.79)),
        (50, {}, (0, 0, 0.8)),
    ])
    # shot in the back: stumbles forward, almost falls on his face
    reaction(arm, "stagger_fwd", [
        (0, *REST),
        (3, {"chest": (-28, 0, 0), "head": (-20, 0, 0), "uarm_l": (-35, 0, -30), "uarm_r": (-35, 0, 30),
             "farm_l": (20, 0, 0), "farm_r": (20, 0, 0), "thigh_l": (14, 0, 0)}, (0, -0.03, -0.06)),
        (8, {"chest": (-32, 0, 0), "head": (-12, 0, 0), "uarm_l": (60, 0, -50), "uarm_r": (-20, 0, 55),
             "farm_l": (30, 0, 0), "farm_r": (50, 0, 0), "thigh_l": (45, 0, 0), "shin_l": (-55, 0, 0),
             "thigh_r": (-12, 0, 0)}, (0, -0.06, -0.2)),
        (13, {"chest": (-24, 0, 0), "uarm_l": (20, 0, -75), "uarm_r": (70, 0, 45), "thigh_l": (25, 0, 0),
              "shin_l": (-10, 0, 0), "thigh_r": (-22, 0, 0), "shin_r": (-15, 0, 0)}, (0, -0.07, -0.36)),
        (18, {"chest": (-20, 0, 0), "uarm_l": (90, 0, -30), "uarm_r": (10, 0, 70), "thigh_r": (45, 0, 0),
              "shin_r": (-55, 0, 0), "thigh_l": (-12, 0, 0), "shin_l": (-12, 0, 0)}, (0, -0.08, -0.52)),
        (23, {"chest": (-10, 0, 0), "uarm_l": (40, 0, -45), "uarm_r": (40, 0, 45), "thigh_r": (25, 0, 0),
              "shin_r": (-12, 0, 0), "thigh_l": (-15, 0, 0)}, (0, -0.06, -0.66)),
        (30, {"chest": (4, 0, 0), "head": (6, 0, 0), "uarm_l": (15, 0, -25), "uarm_r": (15, 0, 25),
              "thigh_r": (10, 0, 0), "thigh_l": (-6, 0, 0)}, (0, -0.03, -0.72)),
        (40, {}, (0, 0, -0.74)),
    ])
    # pushed to his right: cross-over side steps, torso leaning against the fall
    reaction(arm, "stagger_right", [
        (0, *REST),
        (3, {"chest": (0, 15, -22), "head": (0, 12, -18), "uarm_l": (10, 0, -60), "uarm_r": (-15, 0, 40),
             "farm_l": (40, 0, 0), "thigh_r": (0, 0, 14), "thigh_l": (0, 0, 8)}, (0.07, -0.02, 0)),
        (9, {"chest": (0, 8, -14), "uarm_l": (40, 0, -85), "uarm_r": (-10, 0, 60), "farm_l": (30, 0, 0),
             "thigh_r": (8, 0, 28), "shin_r": (-35, 0, 0), "thigh_l": (0, 0, -6)}, (0.22, -0.04, 0)),
        (15, {"chest": (0, 2, -6), "uarm_l": (10, 0, -60), "uarm_r": (20, 0, 80), "thigh_r": (0, 0, 10),
              "thigh_l": (12, 0, 22), "shin_l": (-35, 0, 0)}, (0.38, -0.05, 0)),
        (21, {"chest": (0, -4, 6), "uarm_l": (20, 0, -45), "uarm_r": (10, 0, 55), "thigh_r": (6, 0, 20),
              "shin_r": (-25, 0, 0), "thigh_l": (0, 0, 4)}, (0.52, -0.04, 0)),
        (28, {"chest": (0, -2, 8), "head": (0, 0, 6), "uarm_l": (5, 0, -25), "uarm_r": (5, 0, 25),
              "thigh_r": (0, 0, 6)}, (0.6, -0.02, 0)),
        (38, {}, (0.62, 0, 0)),
    ], mirror_to="stagger_left")
    # head (non-lethal: neck / graze): reels back clutching his face
    reaction(arm, "stagger_head", [
        (0, *REST),
        (2, {"chest": (16, 0, 0), "head": (42, 18, 12), "uarm_l": (-15, 0, -25), "uarm_r": (-15, 0, 25)}, (0, -0.02, 0.06)),
        (9, {"chest": (6, 0, 0), "head": (-12, 8, 0), "uarm_l": (75, 0, -22), "uarm_r": (70, 0, 22),
             "farm_l": (115, 0, 0), "farm_r": (115, 0, 0), "thigh_r": (-28, 0, 0), "shin_r": (-40, 0, 0),
             "thigh_l": (12, 0, 0)}, (0, -0.05, 0.2)),
        (16, {"chest": (-8, 0, 6), "head": (-18, 0, 0), "uarm_l": (65, 0, -20), "uarm_r": (60, 0, 20),
              "farm_l": (110, 0, 0), "farm_r": (110, 0, 0), "thigh_r": (-10, 0, 0), "thigh_l": (-25, 0, 0),
              "shin_l": (-40, 0, 0)}, (0, -0.07, 0.36)),
        (26, {"chest": (-12, 0, -6), "head": (-15, 0, 0), "uarm_l": (60, 0, -18), "uarm_r": (55, 0, 18),
              "farm_l": (105, 0, 0), "farm_r": (105, 0, 0), "thigh_l": (-6, 0, 0), "shin_l": (-10, 0, 0),
              "thigh_r": (8, 0, 0), "shin_r": (-12, 0, 0)}, (0, -0.08, 0.44)),
        (40, {"chest": (-5, 0, 0), "uarm_l": (20, 0, -10), "uarm_r": (20, 0, 10), "farm_l": (40, 0, 0),
              "farm_r": (40, 0, 0)}, (0, -0.02, 0.46)),
        (52, {}, (0, 0, 0.46)),
    ])
    # thigh hit: the leg gives, he limps a step on the good leg and straightens
    reaction(arm, "limp_l", [
        (0, *REST),
        (3, {"thigh_l": (22, 0, 0), "shin_l": (-60, 0, 0), "thigh_r": (-6, 0, 0), "shin_r": (-18, 0, 0),
             "chest": (-16, 0, 12), "uarm_l": (20, 0, -55), "uarm_r": (-10, 0, 45), "farm_l": (45, 0, 0)}, (0, -0.17, 0.04)),
        (10, {"thigh_l": (10, 0, 0), "shin_l": (-35, 0, 0), "thigh_r": (-25, 0, 0), "shin_r": (-35, 0, 0),
              "chest": (-10, 0, 9), "uarm_l": (40, 0, -40), "uarm_r": (10, 0, 50), "farm_l": (70, 0, 0)}, (0, -0.12, 0.12)),
        (17, {"thigh_l": (14, 0, 0), "shin_l": (-30, 0, 0), "thigh_r": (-8, 0, 0), "shin_r": (-8, 0, 0),
              "chest": (-8, 0, 6), "uarm_l": (35, 0, -25), "uarm_r": (5, 0, 30), "farm_l": (80, 0, 0)}, (0, -0.08, 0.2)),
        (30, {"thigh_l": (4, 0, 0), "shin_l": (-12, 0, 0), "chest": (-4, 0, 3), "uarm_l": (25, 0, -12),
              "farm_l": (60, 0, 0)}, (0, -0.03, 0.22)),
        (40, {}, (0, 0, 0.22)),
    ], mirror_to="limp_r")
    # knee hit: the knee folds, he drops onto it, tries to hold himself up and
    # topples (the game turns him into a ragdoll when the clip ends)
    reaction(arm, "knee_fall_l", [
        (0, *REST),
        (3, {"thigh_l": (12, 0, 0), "shin_l": (-75, 0, 0), "chest": (-14, 0, 12), "uarm_l": (25, 0, -60),
             "uarm_r": (-10, 0, 55), "farm_l": (30, 0, 0)}, (0, -0.22, 0.02)),
        (9, {"thigh_l": (0, 0, 0), "shin_l": (-92, 0, 0), "thigh_r": (65, 0, 0), "shin_r": (-75, 0, 0),
             "chest": (-22, 0, 14), "head": (-10, 0, 0), "uarm_l": (35, 0, -20), "farm_l": (10, 0, 0),
             "uarm_r": (10, 0, 65), "farm_r": (30, 0, 0)}, (0, -0.44, 0.05)),
        (15, {"thigh_l": (-4, 0, 0), "shin_l": (-92, 0, 0), "thigh_r": (70, 0, 0), "shin_r": (-80, 0, 0),
              "chest": (-30, 0, 20), "head": (-15, 0, 0), "uarm_l": (50, 0, -15), "farm_l": (5, 0, 0),
              "uarm_r": (30, 0, 50), "farm_r": (20, 0, 0)}, (0, -0.47, 0.05)),
        (20, {"thigh_l": (-8, 0, 0), "shin_l": (-90, 0, 0), "thigh_r": (55, 0, 0), "shin_r": (-70, 0, 0),
              "chest": (-42, 0, 26), "head": (-20, 0, 0), "uarm_l": (70, 0, -20), "uarm_r": (60, 0, 35),
              "farm_l": (10, 0, 0), "farm_r": (10, 0, 0)}, (0, -0.5, 0.0)),
    ], mirror_to="knee_fall_r")
    # arm hit: the shoulder is knocked back, the body twists and he steps to catch it
    reaction(arm, "spin_l", [
        (0, *REST),
        (3, {"pelvis": (0, 12, 0), "chest": (6, 28, 6), "head": (0, -12, 0), "uarm_l": (-60, 0, -40),
             "farm_l": (5, 0, 0), "uarm_r": (30, 0, 30)}, (-0.03, -0.02, 0.04)),
        (10, {"pelvis": (0, 22, 0), "chest": (0, 22, 4), "uarm_l": (-20, 0, -70), "farm_l": (60, 0, 0),
              "uarm_r": (50, 0, 40), "thigh_l": (-25, 0, 0), "shin_l": (-35, 0, 0), "thigh_r": (10, 0, 0)},
         (-0.08, -0.04, 0.14)),
        (17, {"pelvis": (0, 14, 0), "chest": (-4, 8, 0), "uarm_l": (30, 0, -30), "farm_l": (90, 0, 0),
              "uarm_r": (15, 0, 25), "thigh_l": (-10, 0, 0), "thigh_r": (6, 0, 0)}, (-0.1, -0.03, 0.2)),
        (30, {"pelvis": (0, 4, 0), "uarm_l": (35, 0, -15), "farm_l": (80, 0, 0)}, (-0.1, 0, 0.22)),
        (40, {}, (-0.1, 0, 0.22)),
    ], mirror_to="spin_r")


# ---------------------------------------------------------------- get up

def getups(arm):
    c = Clip(arm, "getup_back")  # lying face up, head towards +Z
    c.pose(0, {"pelvis": (90, 0, 0), "uarm_l": (0, 0, -10), "uarm_r": (0, 0, 10)}, (0, -0.8, 0))
    c.pose(12, {"pelvis": (35, 0, 0), "chest": (-30, 0, 0), "head": (-15, 0, 0), "thigh_l": (55, 0, 0),
                "thigh_r": (55, 0, 0), "uarm_l": (-45, 0, -15), "uarm_r": (-45, 0, 15), "farm_l": (20, 0, 0),
                "farm_r": (20, 0, 0)}, (0, -0.8, 0))
    c.pose(24, {"chest": (-25, 0, 0), "thigh_l": (115, 0, 0), "thigh_r": (95, 0, 0), "shin_l": (-125, 0, 0),
                "shin_r": (-60, 0, 0), "uarm_l": (-35, 0, -20), "uarm_r": (40, 0, 15), "farm_r": (30, 0, 0)},
           (0, -0.66, -0.05))
    c.pose(38, {"chest": (-45, 0, 0), "head": (-10, 0, 0), "thigh_l": (110, 0, 0), "thigh_r": (100, 0, 0),
                "shin_l": (-125, 0, 0), "shin_r": (-115, 0, 0), "uarm_l": (40, 0, -10), "uarm_r": (45, 0, 10),
                "farm_l": (40, 0, 0), "farm_r": (40, 0, 0)}, (0, -0.5, -0.12))
    c.pose(50, {"chest": (-20, 0, 0), "thigh_l": (45, 0, 0), "thigh_r": (40, 0, 0), "shin_l": (-55, 0, 0),
                "shin_r": (-50, 0, 0), "uarm_l": (15, 0, -10), "uarm_r": (15, 0, 10), "farm_l": (25, 0, 0),
                "farm_r": (25, 0, 0)}, (0, -0.16, -0.04))
    c.pose(64, {})
    c.finish()

    c = Clip(arm, "getup_front")  # lying face down, head towards -Z
    c.pose(0, {"pelvis": (-90, 0, 0), "uarm_l": (0, 0, -15), "uarm_r": (0, 0, 15)}, (0, -0.8, 0))
    c.pose(10, {"pelvis": (-80, 0, 0), "chest": (25, 0, 0), "head": (20, 0, 0), "uarm_l": (85, 0, -20),
                "uarm_r": (85, 0, 20), "farm_l": (60, 0, 0), "farm_r": (60, 0, 0)}, (0, -0.72, 0))
    c.pose(22, {"pelvis": (-55, 0, 0), "chest": (10, 0, 0), "head": (15, 0, 0), "thigh_l": (75, 0, 0),
                "thigh_r": (70, 0, 0), "shin_l": (-110, 0, 0), "shin_r": (-110, 0, 0), "uarm_l": (75, 0, -12),
                "uarm_r": (75, 0, 12), "farm_l": (5, 0, 0), "farm_r": (5, 0, 0)}, (0, -0.55, 0.12))
    c.pose(36, {"pelvis": (-15, 0, 0), "chest": (-30, 0, 0), "thigh_l": (115, 0, 0), "thigh_r": (100, 0, 0),
                "shin_l": (-125, 0, 0), "shin_r": (-120, 0, 0), "uarm_l": (50, 0, -10), "uarm_r": (50, 0, 10),
                "farm_l": (30, 0, 0), "farm_r": (30, 0, 0)}, (0, -0.5, 0.04))
    c.pose(50, {"chest": (-20, 0, 0), "thigh_l": (45, 0, 0), "thigh_r": (40, 0, 0), "shin_l": (-55, 0, 0),
                "shin_r": (-50, 0, 0), "uarm_l": (15, 0, -10), "uarm_r": (15, 0, 10)}, (0, -0.16, 0))
    c.pose(64, {})
    c.finish()


def main():
    arm = build_armature()
    idle(arm)
    cycle(arm, "walk", 30, stride=30, knee=50, arm_swing=24, lean=2, bob=0.035)
    cycle(arm, "panic_run", 20, stride=42, knee=85, arm_swing=0, lean=12, bob=0.05, arms_up=1.0)
    staggers(arm)
    getups(arm)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True, export_def_bones=False,
                              export_cameras=False, export_lights=False)
    print("EXPORTED", OUT, os.path.getsize(OUT))


main()
