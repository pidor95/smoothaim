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
  idle, walk, panic_run (sprint)             - loops
  stagger_back/fwd/left/right, stagger_head,  - balance recoveries after a hit:
  limp_l/r, spin_l/r                           rocked on the spot, feet pattering
  knee_fall_l/r                              - knee shot, folds and topples
  clutch_*                                   - hand on the wound (single poses)
  choke_stand, choke_knees, choke_fall,      - neck shot: hands on the throat, gasping,
  choke_floor                                  then down on the floor rolling about
  hands_up, kneel_hands_head                 - obeying the player's orders
  suicide_r                                  - pistol to the temple (head + right arm)
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
        """Keys a full pose. rots: {bone: (x, y, z) degrees in the NPC frame,
        or a 3x3 rotation Matrix in the NPC frame (used for lying bodies)}."""
        rots = rots or {}
        for pb in self.arm.pose.bones:
            b = pb.bone.matrix_local.to_3x3()
            v = rots.get(pb.name, (0, 0, 0))
            r = C @ v @ C.transposed() if isinstance(v, Matrix) else godot_rot(v)
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


def cycle(arm, name, frames, stride, knee, arm_swing, lean, bob, arms_up=0.0, keys=12, elbow_bend=15):
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
        elbow = elbow_bend + 10 * abs(s) + 25 * arms_up
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


def _add(*poses):
    out = {}
    for rots in poses:
        for k, v in rots.items():
            a = out.get(k, (0, 0, 0))
            out[k] = (a[0] + v[0], a[1] + v[1], a[2] + v[2])
    return out


def _scale(rots, s):
    return {k: (v[0] * s, v[1] * s, v[2] * s) for k, v in rots.items()}


def _lift(side, amount):
    """One foot lifted for a quick step in place."""
    return {"thigh_" + side: (24 * amount, 0, 0), "shin_" + side: (-46 * amount, 0, 0)}


def shuffle(arm, name, jolt, offset, arms, steps=4, first="l", hold=None, mirror_to=None):
    """Balance recovery without walking away: the hit throws the body over
    (`jolt`), the arms go out (`arms`) and the feet patter on the spot,
    left-right-left, while the lean dies down. The pelvis only sways by a few
    centimetres and ends back where it started, so the NPC holds his ground.
    `hold` is a pose kept for the whole clip (hands to the face, a buckled leg)."""
    hold = hold or {}
    ox, oz = offset
    keys = [(0, *REST),
            (3, _add(jolt, arms, hold), (ox * 0.06, -0.035, oz * 0.06))]
    side = first
    f = 3
    for k in range(steps):
        d = 0.72 ** (k + 1)
        sway = 0.018 if side == "r" else -0.018
        f += 3
        keys.append((f, _add(_scale(jolt, d), _scale(arms, d), hold, _lift(side, 0.55 + 0.45 * d)),
                     (ox * 0.06 * d + sway, -0.015 - 0.02 * d, oz * 0.06 * d)))
        f += 3
        keys.append((f, _add(_scale(jolt, d * 0.85), _scale(arms, d * 0.9), hold),
                     (ox * 0.05 * d, -0.02 * d, oz * 0.05 * d)))
        side = "r" if side == "l" else "l"
    keys.append((f + 6, _add(_scale(jolt, -0.12), _scale(arms, 0.15), _scale(hold, 0.6)), (0, -0.008, 0)))
    keys.append((f + 14, {}, (0, 0, 0)))
    reaction(arm, name, keys, mirror_to=mirror_to)


ARMS_OUT = {"uarm_l": (30, 0, -55), "uarm_r": (25, 0, 55), "farm_l": (35, 0, 0), "farm_r": (35, 0, 0)}


def staggers(arm):
    """Balance recoveries after a hit. He does not step away from the shot:
    he is rocked by it and fights to stay upright, feet pattering in place."""
    # shot from the front: rocked back
    shuffle(arm, "stagger_back", {"chest": (22, 0, 0), "head": (24, 0, 0)}, (0, 1),
            {"uarm_l": (55, 0, -45), "uarm_r": (45, 0, 50), "farm_l": (30, 0, 0), "farm_r": (35, 0, 0)}, steps=4)
    # shot in the back: pitched forward
    shuffle(arm, "stagger_fwd", {"chest": (-26, 0, 0), "head": (-16, 0, 0)}, (0, -1),
            {"uarm_l": (-25, 0, -45), "uarm_r": (-25, 0, 45), "farm_l": (25, 0, 0), "farm_r": (25, 0, 0)}, steps=4, first="r")
    # pushed to his right
    shuffle(arm, "stagger_right", {"chest": (0, 14, -20), "head": (0, 12, -16), "pelvis": (0, 6, 0)}, (1, 0),
            {"uarm_l": (15, 0, -70), "uarm_r": (-10, 0, 45), "farm_l": (35, 0, 0)}, steps=4, first="r",
            mirror_to="stagger_left")
    # head (graze): reels, hands to the face, still on his feet
    shuffle(arm, "stagger_head", {"chest": (14, 0, 0), "head": (36, 16, 10)}, (0, 1), {},
            steps=5, hold={"uarm_l": (70, 0, -22), "uarm_r": (66, 0, 22), "farm_l": (112, 0, 0), "farm_r": (112, 0, 0)})
    # thigh: the leg buckles, he keeps the weight on the good one and steadies
    shuffle(arm, "limp_l", {"chest": (-14, 0, 11), "thigh_l": (14, 0, 0), "shin_l": (-40, 0, 0)}, (0, 0),
            ARMS_OUT, steps=3, first="r", hold={"shin_r": (-10, 0, 0)}, mirror_to="limp_r")
    # arm: the shoulder is knocked back and the body twists on the spot
    shuffle(arm, "spin_l", {"pelvis": (0, 14, 0), "chest": (6, 26, 6), "head": (0, -12, 0)}, (-0.4, 0.4),
            {"uarm_l": (-50, 0, -40), "uarm_r": (30, 0, 35), "farm_l": (10, 0, 0)}, steps=3, mirror_to="spin_r")
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


def clutches(arm):
    """Single poses: a hand (or both) pressed on the wound. The game blends
    them in after a hit (over whatever else he is doing) and lets go later."""
    # arm angles solved so the hand lands on the wound (FK search, see git history)
    poses = {
        "clutch_chest_l": ({"chest": (-10, 0, 0), "head": (-12, 0, 0), "uarm_r": (20, 45, -30), "farm_r": (90, 0, 0)}, (0, 0, 0)),
        "clutch_belly": ({"chest": (-25, 0, 0), "head": (-15, 0, 0), "uarm_l": (0, -30, 10), "farm_l": (80, 0, 0),
                          "uarm_r": (0, 30, -10), "farm_r": (80, 0, 0), "thigh_l": (12, 0, 0), "thigh_r": (12, 0, 0),
                          "shin_l": (-18, 0, 0), "shin_r": (-18, 0, 0)}, (0, -0.04, 0)),
        "clutch_arm_l": ({"chest": (-6, 18, 0), "head": (-10, 15, 0), "uarm_r": (20, 15, -60), "farm_r": (40, 0, 0),
                          "uarm_l": (6, 0, -4), "farm_l": (8, 0, 0)}, (0, 0, 0)),
        "clutch_thigh_l": ({"chest": (-35, 0, 8), "head": (-10, 0, 0), "uarm_l": (10, 45, 30), "farm_l": (2, 0, 0),
                            "uarm_r": (10, 0, 30), "thigh_l": (20, 0, 0), "shin_l": (-25, 0, 0), "thigh_r": (5, 0, 0)},
                           (0, -0.07, 0)),
        "clutch_neck": ({"chest": (-5, 0, 0), "head": (10, 0, 0), "uarm_l": (40, -60, 30), "farm_l": (130, 0, 0),
                         "uarm_r": (40, 60, -30), "farm_r": (130, 0, 0)}, (0, 0, 0)),
        "clutch_head": ({"chest": (-10, 0, 0), "head": (-20, 0, 0), "uarm_l": (70, -45, 30), "farm_l": (110, 0, 0),
                         "uarm_r": (70, 45, -30), "farm_r": (110, 0, 0)}, (0, 0, 0)),
    }
    mirrored = {"clutch_chest_l": "clutch_chest_r", "clutch_arm_l": "clutch_arm_r", "clutch_thigh_l": "clutch_thigh_r"}
    for name, (rots, loc) in poses.items():
        reaction(arm, name, [(0, rots, loc), (1, rots, loc)], mirror_to=mirrored.get(name))


# ---------------------------------------------------------------- neck wound

CLUTCH_NECK = {"uarm_l": (40, -60, 30), "farm_l": (130, 0, 0), "uarm_r": (40, 60, -30), "farm_r": (130, 0, 0)}
KNEEL = {"thigh_l": (-4, 0, 0), "thigh_r": (-4, 0, 0), "shin_l": (-92, 0, 0), "shin_r": (-92, 0, 0)}
KNEEL_DROP = -0.44


def chokes(arm):
    """Carotid opened by a neck shot. Both hands clamp the throat for as long
    as he lives; he gasps (chest heaving, head jerking) and keeps patting his
    feet to stay up, sinks to his knees, topples over and rolls about on the
    floor still holding on."""
    c = Clip(arm, "choke_stand")
    n = 12
    for i in range(n + 1):
        ph = i / n * 2 * math.pi
        gasp = max(0.0, math.sin(ph * 3)) ** 3
        rots = _add(CLUTCH_NECK, {
            "pelvis": (0, 5 * math.sin(ph), 0),
            "chest": (-20 - 9 * gasp + 3 * math.sin(ph * 2), 7 * math.sin(ph), 4 * math.sin(ph)),
            "head": (-6 + 16 * gasp, 9 * math.sin(ph * 2), -5 * math.sin(ph)),
            "thigh_l": (10, 0, -3), "thigh_r": (10, 0, 3), "shin_l": (-18, 0, 0), "shin_r": (-18, 0, 0)})
        step = i % 4
        if step == 1:
            rots = _add(rots, _lift("l", 0.6))
        elif step == 3:
            rots = _add(rots, _lift("r", 0.6))
        c.pose(round(i / n * 60), rots, (0.022 * math.sin(ph), -0.055 - 0.012 * gasp, 0.012 * math.sin(ph * 2)))
    c.finish()

    c = Clip(arm, "choke_knees")
    n = 12
    for i in range(n + 1):
        ph = i / n * 2 * math.pi
        gasp = max(0.0, math.sin(ph * 2)) ** 3
        rots = _add(CLUTCH_NECK, KNEEL, {
            "chest": (-32 - 8 * gasp + 4 * math.sin(ph), 6 * math.sin(ph), 9 * math.sin(ph)),
            "head": (-8 + 18 * gasp, 6 * math.sin(ph * 2), -6 * math.sin(ph))})
        c.pose(round(i / n * 72), rots, (0.03 * math.sin(ph), KNEEL_DROP - 0.015 * gasp, 0))
    c.finish()


    # from his knees he keels over sideways onto the floor
    c = Clip(arm, "choke_fall")
    c.pose(0, _add(CLUTCH_NECK, KNEEL, {"chest": (-32, 0, 0), "head": (-8, 0, 0)}), (0, KNEEL_DROP, 0))
    c.pose(6, _add(CLUTCH_NECK, KNEEL, {"pelvis": (0, 0, 14), "chest": (-38, 0, 16), "head": (-12, 0, 12)}),
           (0.03, KNEEL_DROP - 0.05, 0))
    c.pose(12, dict(_add(CLUTCH_NECK, {"chest": (-28, 0, 8), "head": (-6, 0, 10), "thigh_l": (75, 0, -6),
                                       "thigh_r": (70, 0, 6), "shin_l": (-110, 0, 0), "shin_r": (-105, 0, 0)}),
                    pelvis=lying(60, 45)), (-0.05, -0.68, 0.05))
    c.pose(17, dict(_add(CLUTCH_NECK, {"chest": (-12, 0, 0), "head": (14, 0, 0), "thigh_l": (62, 0, -8),
                                       "thigh_r": (55, 0, 8), "shin_l": (-95, 0, 0), "shin_r": (-90, 0, 0)}),
                    pelvis=lying(95)), (-0.1, -0.73, 0))
    floor = _floor_pose(0.0)
    c.pose(24, floor[0], floor[1])
    c.finish()

    # rolling about on the floor: onto one side, over the back onto the other,
    # knees drawn up and kicking, chest heaving, still clutching the throat
    c = Clip(arm, "choke_floor")
    n = 16
    for i in range(n + 1):
        rots, loc = _floor_pose(i / n * 2 * math.pi)
        c.pose(round(i / n * 120), rots, loc)
    c.finish()


def lying(roll, tilt=88):
    """Pelvis rotation of a body lying on its back (head towards +Z) and
    rolled by `roll` degrees about its own length (+ = onto the left side)."""
    return Matrix.Rotation(math.radians(roll), 3, "Z") @ grot((tilt, 0, 0))


def _floor_pose(ph):
    roll = 92 * math.cos(ph) + 14 * math.sin(2 * ph)
    gasp = max(0.0, math.sin(ph * 3)) ** 3
    k = math.sin(2 * ph)
    rots = _add(CLUTCH_NECK, {
        "chest": (-18 - 12 * gasp + 6 * math.sin(ph * 4), 10 * math.sin(ph), 0),
        "head": (-6 + 22 * gasp, 14 * math.sin(ph + 0.5), 0),
        "thigh_l": (58 + 28 * k, 0, -8), "shin_l": (-88 - 26 * math.sin(2 * ph + 0.8), 0, 0),
        "thigh_r": (58 - 28 * k, 0, 8), "shin_r": (-88 + 26 * math.sin(2 * ph + 0.8), 0, 0)})
    rots["pelvis"] = lying(roll)
    side = abs(math.sin(math.radians(roll)))
    return rots, (-0.1 * math.sin(math.radians(roll)), -0.8 + 0.075 * side, 0)


# ---------------------------------------------------------------- orders

def orders(arm):
    """Poses for the player's orders, as short loops with a scared tremble."""
    c = Clip(arm, "hands_up")
    n = 8
    for i in range(n + 1):
        ph = i / n * 2 * math.pi
        tr = math.sin(ph * 3)
        c.pose(round(i / n * 60), {
            "chest": (3 + 1.5 * math.sin(ph), 0, 0), "head": (-6, 0, 0),
            "uarm_l": (10 + 2 * tr, 0, -158 + 2 * math.sin(ph)), "uarm_r": (10 - 2 * tr, 0, 158 - 2 * math.sin(ph)),
            "farm_l": (24 + 3 * tr, 0, 0), "farm_r": (24 - 3 * tr, 0, 0),
            "thigh_l": (0, 0, -3), "thigh_r": (0, 0, 3)}, (0, -0.004 * (1 + math.sin(ph)), 0))
    c.finish()

    c = Clip(arm, "kneel_hands_head")
    for i in range(n + 1):
        ph = i / n * 2 * math.pi
        c.pose(round(i / n * 72), _add(KNEEL, {
            "chest": (-6 + 2 * math.sin(ph), 0, 0), "head": (-14 + 2 * math.sin(ph * 2), 0, 0),
            "uarm_l": (70, -45, 30), "farm_l": (112, 0, 0), "uarm_r": (70, 45, -30), "farm_r": (112, 0, 0)}),
            (0, KNEEL_DROP - 0.006 * (1 + math.sin(ph)), 0))
    c.finish()


# ---------------------------------------------------------------- suicide

HEADS = {b[0]: Vector(b[1]) for b in BONES}
PARENTS = {b[0]: b[3] for b in BONES}
# How the NPC holds the pistol (must match Npc.GUN_* in scripts/npc.gd): the
# grip sits in the right hand, the barrel runs on along the forearm tipped 20
# degrees forward (so a hanging arm carries it pointing at the floor ahead),
# the slide's top faces the thumb side.
HAND_R = Vector((0.265, 0.85, 0))
GUN_BARREL = Vector((0, -1, -0.364)).normalized()
GUN_TOP = Vector((0, 0.364, -1)).normalized()
GUN_MUZZLE = HAND_R + GUN_BARREL * 0.195 + GUN_TOP * 0.056


def grot(deg):
    """Rotation in the NPC frame for a pose angle triple (Godot YXZ)."""
    return Euler(tuple(math.radians(a) for a in deg), "ZXY").to_matrix()


def fk(rots, bone, point):
    """Forward kinematics in the NPC frame: each bone turns everything below
    it about its own head, parents last (same maths the game uses)."""
    p = Vector(point)
    while bone:
        h = HEADS[bone]
        p = h + grot(rots.get(bone, (0, 0, 0))) @ (p - h)
        bone = PARENTS[bone]
    return p


def fk_dir(rots, bone, d):
    v = Vector(d)
    while bone:
        v = grot(rots.get(bone, (0, 0, 0))) @ v
        bone = PARENTS[bone]
    return v


def solve_gun_to_temple(head_rot):
    """Searches the right arm angles that press the pistol's muzzle against
    the right temple, barrel pointing into the head."""
    import random
    random.seed(7)
    temple = fk({"head": head_rot}, "head", (0.122, 1.72, -0.01))
    into = -fk_dir({"head": head_rot}, "head", (1, 0, 0.12)).normalized()
    want = temple - into * 0.012
    lim = [(-40, 160), (-90, 90), (-20, 175), (0, 150), (-180, 180), (-90, 90)]

    def rots_of(x):
        return {"head": head_rot, "uarm_r": (x[0], x[1], x[2]), "farm_r": (x[3], x[4], x[5])}

    def cost(x):
        r = rots_of(x)
        m = fk(r, "farm_r", GUN_MUZZLE)
        bd = fk_dir(r, "farm_r", GUN_BARREL)
        up = fk_dir(r, "farm_r", GUN_TOP)
        elbow = fk(r, "uarm_r", (0.265, 1.19, 0))
        hand = fk(r, "farm_r", HAND_R)
        c = 400 * (m - want).length_squared + 6 * (1 - bd.dot(into))
        c += 1.0 * max(0.0, 0.3 - up.y)
        c += 8.0 * max(0.0, elbow.y - 1.7) ** 2
        c += 60 * max(0.0, 0.2 - elbow.x) ** 2
        c += 60 * max(0.0, 0.17 - (hand - HEADS["head"] - Vector((0, 0.14, 0))).length) ** 2
        return c

    best, best_c = None, 1e9
    for _ in range(12000):
        x = [random.uniform(a, b) for a, b in lim]
        cc = cost(x)
        if cc < best_c:
            best, best_c = x, cc
    step = 8.0
    while step > 0.05:
        moved = False
        for k in range(len(lim)):
            for sgn in (1, -1):
                y = list(best)
                y[k] = min(max(y[k] + sgn * step, lim[k][0]), lim[k][1])
                cc = cost(y)
                if cc < best_c:
                    best, best_c, moved = y, cc, True
        if not moved:
            step *= 0.5
    r = rots_of(best)
    print("suicide arm", [round(v, 1) for v in best], "muzzle error %.3f m" % (fk(r, "farm_r", GUN_MUZZLE) - want).length,
          "barrel dot %.2f" % fk_dir(r, "farm_r", GUN_BARREL).dot(into))
    return r


def suicide(arm):
    """Pistol to the right temple: a pose for the head and the right arm only,
    laid over whatever the body is doing (standing, kneeling, choking)."""
    head = (-8, 10, 12)
    r = solve_gun_to_temple(head)
    c = Clip(arm, "suicide_r")
    c.pose(0, r)
    c.pose(1, r)
    c.finish()


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
    # panic: just a flat-out sprint away, arms pumping
    cycle(arm, "panic_run", 18, stride=46, knee=95, arm_swing=50, lean=15, bob=0.06, elbow_bend=80)
    staggers(arm)
    clutches(arm)
    chokes(arm)
    orders(arm)
    suicide(arm)
    getups(arm)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_animations=True,
                              export_animation_mode="ACTIONS", export_force_sampling=True, export_def_bones=False,
                              export_cameras=False, export_lights=False)
    print("EXPORTED", OUT, os.path.getsize(OUT))


main()
