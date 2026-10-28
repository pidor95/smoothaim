"""Builds the first-person weapon viewmodels (gun + gloved hands) and their
animations in Blender, exported as glTF for Godot.

Run:
  blender -b --python tools/blender/build_weapons.py -- <m500.usdz> [preview_dir]

Outputs assets/weapons/m1911_fp.glb and assets/weapons/m500_fp.glb.

Coordinates are camera space (Blender axes): +Y forward, +Z up, +X right; the
exporter converts them to Godot's -Z forward / +Y up. Each viewmodel is an
armature "VM" whose bones carry rigid meshes:
  gun      - the weapon (recoil, tilt)          slide / pump / mag - moving parts
  hand_l   - support hand (reloads, pump)        shell / mag_new   - held items
  muzzle, eject, sight - marker bones read by the game
Animations: idle, fire, (fire_last), reload, (reload_empty), draw.
"""
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
USDZ = ARGS[0] if ARGS else ""
PREVIEW = ARGS[1] if len(ARGS) > 1 else ""
OUT_DIR = os.path.join(ROOT, "assets", "weapons")
FPS = 30


# ---------------------------------------------------------------- helpers

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS


def material(name, color, metallic=0.0, roughness=0.8, image=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if image:
        tex = m.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(image)
        m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def apply_all(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def join(objs, name):
    objs = [o for o in objs if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    return o


def capsule(name, radius, length, mat, segments=12):
    """Capsule along local Y centred at origin."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=8, radius=radius)
    o = bpy.context.active_object
    o.name = name
    half = max(length / 2 - radius, 0.0)
    for v in o.data.vertices:
        # sphere is built around Z; stretch along Z then rotate to Y
        v.co.z += half if v.co.z > 0 else -half
    o.rotation_euler = (math.radians(-90), 0, 0)
    apply_all(o)
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def limb_between(name, a, b, radius, mat):
    a, b = Vector(a), Vector(b)
    o = capsule(name, radius, (b - a).length + radius * 2, mat)
    d = (b - a).normalized()
    o.matrix_world = Matrix.Translation((a + b) / 2) @ d.to_track_quat("Y", "Z").to_matrix().to_4x4()
    apply_all(o)
    return o


def fist(name, pos, mat, rot=(0, 0, 0), scale=(1.0, 1.25, 1.0)):
    o = capsule(name, 0.026, 0.085, mat)
    o.rotation_euler = Euler([math.radians(a) for a in rot])
    o.scale = scale
    o.location = pos
    apply_all(o)
    return o


def make_armature(bones):
    """bones: list of (name, head, parent). Every bone points along +Y with
    zero roll, so pose-space axes equal armature axes."""
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = bpy.context.active_object
    arm.name = "VM"
    arm.data.name = "VM"
    eb = arm.data.edit_bones
    eb.remove(eb[0])
    for name, head, parent in bones:
        b = eb.new(name)
        b.head = Vector(head)
        b.tail = Vector(head) + Vector((0, 0.05, 0))
        b.roll = 0.0
        if parent:
            b.parent = eb[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
    return arm


def bind(obj, arm, bone):
    mw = obj.matrix_world.copy()
    obj.parent = arm
    obj.parent_type = "BONE"
    obj.parent_bone = bone
    obj.matrix_world = mw


class Clip:
    """Keyframes pose-bone channels into a named action pushed to the NLA."""

    def __init__(self, arm, name):
        self.arm = arm
        self.action = bpy.data.actions.new(name)
        self.action.use_fake_user = True
        arm.animation_data_create()
        arm.animation_data.action = self.action
        for pb in arm.pose.bones:
            pb.location = (0, 0, 0)
            pb.rotation_euler = (0, 0, 0)
            pb.scale = (1, 1, 1)
        self.end = 0

    def key(self, bone, frame, loc=None, rot=None, scale=None):
        pb = self.arm.pose.bones[bone]
        if loc is not None:
            pb.location = loc
            pb.keyframe_insert("location", frame=frame)
        if rot is not None:
            pb.rotation_euler = [math.radians(a) for a in rot]
            pb.keyframe_insert("rotation_euler", frame=frame)
        if scale is not None:
            pb.scale = (scale, scale, scale)
            pb.keyframe_insert("scale", frame=frame)
        self.end = max(self.end, frame)

    def hold_all(self, frames):
        """Key every bone's current value (rest unless keyed) on given frames."""
        for pb in self.arm.pose.bones:
            for f in frames:
                pb.keyframe_insert("location", frame=f)
                pb.keyframe_insert("rotation_euler", frame=f)
                pb.keyframe_insert("scale", frame=f)

    def step(self, bone, frame, **kw):
        """Constant (stepped) key, e.g. visibility via scale."""
        self.key(bone, frame, **kw)
        for fc in self.action.fcurves:
            if fc.data_path == 'pose.bones["%s"].scale' % bone:
                for kp in fc.keyframe_points:
                    if int(kp.co.x) == frame:
                        kp.interpolation = "CONSTANT"

    def finish(self):
        track = self.arm.animation_data.nla_tracks.new()
        track.name = self.action.name
        track.strips.new(self.action.name, 0, self.action)
        self.arm.animation_data.action = None


def export(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", export_apply=True, export_yup=True,
        export_animations=True, export_animation_mode="ACTIONS", export_force_sampling=True,
        export_image_format="JPEG", export_cameras=False, export_lights=False)
    print("EXPORTED", path, os.path.getsize(path))


def preview(name, frames_by_action):
    """Renders camera-view stills (Godot-like 75 deg vertical FOV)."""
    if not PREVIEW:
        return
    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(75)
    cam_data.clip_start = 0.02
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    cam.rotation_euler = (math.radians(90), 0, 0)
    scene.camera = cam
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 4
    sun.rotation_euler = (math.radians(40), math.radians(20), math.radians(30))
    scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.65, 0.8, 1)
    scene.world = world
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 12
    scene.cycles.device = "CPU"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 360
    arm = bpy.data.objects["VM"]
    for action_name, frame in frames_by_action:
        arm.animation_data.action = bpy.data.actions[action_name]
        for t in arm.animation_data.nla_tracks:
            t.mute = True
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(PREVIEW, "%s_%s_%d.png" % (name, action_name, frame))
        bpy.ops.render.render(write_still=True)
    arm.animation_data.action = None
    for t in arm.animation_data.nla_tracks:
        t.mute = False
    bpy.data.objects.remove(cam)
    bpy.data.objects.remove(sun)


def gloves():
    return (material("Glove", (0.03, 0.03, 0.035), roughness=0.85),
            material("Sleeve", (0.045, 0.045, 0.05), roughness=0.95))


# ---------------------------------------------------------------- M1911

def build_m1911():
    reset()
    bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT, "assets", "m1911", "m1911.fbx"))
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    s = 0.0626  # model is 3.45 units long; a real M1911 is 0.216 m
    tex = material("M1911", (1, 1, 1), metallic=0.3, roughness=0.5,
                   image=os.path.join(ROOT, "assets", "m1911", "m1911_albedo.jpg"))
    grip = Vector((0.15, 0.36, -0.165))  # camera-space hip position of the gun origin
    yaw = math.radians(4)
    to_cam = Matrix.Translation(grip) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Scale(s, 4)
    for o in parts:
        o.matrix_world = to_cam @ o.matrix_world
        apply_all(o)
        o.data.materials.clear()
        o.data.materials.append(tex)
        # keep only the first UV map (the albedo atlas)
        while len(o.data.uv_layers) > 1:
            o.data.uv_layers.remove(o.data.uv_layers[-1])

    def g(v):  # gun-local (unrotated, metres) -> camera space
        return grip + Matrix.Rotation(yaw, 3, "Z") @ Vector(v)

    slide_names = ("Plane.007", "Plane.010", "Plane.012", "Cylinder.001", "Plane.011")
    mag_names = ("Circle", "Plane.002")
    slide_objs = [o for o in parts if o.name in slide_names]
    mag_objs = [o for o in parts if o.name in mag_names]
    body_objs = [o for o in parts if o.name not in slide_names + mag_names]
    slide = join(slide_objs, "Slide")
    mag = join(mag_objs, "Mag")
    body = join(body_objs, "Frame")

    glove, sleeve = gloves()
    hand_r = fist("HandR", g((0.0, -0.04, -0.038)), glove, rot=(-18, 0, 0), scale=(1.05, 1.0, 1.35))
    thumb = capsule("ThumbR", 0.009, 0.05, glove)
    thumb.matrix_world = Matrix.Translation(g((-0.016, -0.012, -0.008))) @ Matrix.Rotation(math.radians(10), 4, "X")
    apply_all(thumb)
    arm_r = limb_between("ArmR", g((0.0, -0.075, -0.06)), (0.27, -0.12, -0.42), 0.042, sleeve)
    hand_l = fist("HandL", g((-0.035, -0.03, -0.075)), glove, rot=(-10, 0, 25))
    arm_l = limb_between("ArmL", g((-0.035, -0.06, -0.09)), (-0.2, -0.1, -0.45), 0.042, sleeve)
    mag_new = mag.copy()
    mag_new.data = mag.data.copy()
    mag_new.name = "MagNew"
    bpy.context.scene.collection.objects.link(mag_new)

    arm = make_armature([
        ("gun", grip, None),
        ("slide", grip, "gun"),
        ("mag", grip, "gun"),
        ("hand_l", g((-0.035, -0.03, -0.075)), "gun"),
        ("mag_new", g((-0.035, -0.03, -0.075)), "hand_l"),
        ("muzzle", g((0.0, 0.15, 0.030)), "gun"),
        ("eject", g((0.012, 0.03, 0.05)), "gun"),
        ("sight", g((0.0, 0.02, 0.063)), "gun"),
    ])
    for o, b in [(body, "gun"), (hand_r, "gun"), (thumb, "gun"), (arm_r, "gun"), (slide, "slide"),
                 (mag, "mag"), (hand_l, "hand_l"), (arm_l, "hand_l"), (mag_new, "mag_new")]:
        bind(o, arm, b)

    SLIDE = (0, -0.047, 0)
    AWAY = (-0.12, -0.25, -0.35)  # support hand parked off screen

    def base(c, frames):
        c.key("hand_l", frames[0], loc=AWAY, scale=0.0)
        c.key("mag_new", frames[0], scale=0.0)

    c = Clip(arm, "idle")
    base(c, [0])
    c.hold_all([0, 1])
    c.finish()

    for name, keep_back in (("fire", False), ("fire_last", True)):
        c = Clip(arm, name)
        base(c, [0])
        c.hold_all([0])
        c.key("slide", 0, loc=(0, 0, 0))
        c.key("slide", 1, loc=SLIDE)
        c.key("slide", 3, loc=SLIDE if keep_back else (0, 0, 0))
        c.key("slide", 8, loc=SLIDE if keep_back else (0, 0, 0))
        c.key("gun", 0, loc=(0, 0, 0), rot=(0, 0, 0))
        c.key("gun", 1, loc=(0, -0.035, 0.012), rot=(16, 0, -2))
        c.key("gun", 4, loc=(0, -0.012, 0.004), rot=(5, 0, -1))
        c.key("gun", 8, loc=(0, 0, 0), rot=(0, 0, 0))
        c.finish()

    for name, empty in (("reload", False), ("reload_empty", True)):
        c = Clip(arm, name)
        c.hold_all([0])
        tilt = dict(loc=(-0.05, 0.0, 0.035), rot=(14, -24, 6))
        c.key("gun", 0, loc=(0, 0, 0), rot=(0, 0, 0))
        c.key("gun", 7, **tilt)
        c.key("gun", 34, **tilt)
        c.key("gun", 40, loc=(-0.02, 0.0, 0.02), rot=(8, -10, 2))
        c.key("gun", 45, loc=(0, 0, 0), rot=(0, 0, 0))
        c.key("slide", 0, loc=SLIDE if empty else (0, 0, 0))
        c.key("slide", 36, loc=SLIDE if empty else (0, 0, 0))
        c.key("slide", 38, loc=(0, 0, 0))
        # old magazine drops out
        c.key("mag", 0, loc=(0, 0, 0), scale=1.0)
        c.key("mag", 8, loc=(0, 0, 0))
        c.key("mag", 14, loc=(0, -0.01, -0.28))
        c.step("mag", 14, scale=0.0)
        c.step("mag", 28, scale=1.0)
        c.key("mag", 28, loc=(0, 0, 0))
        # support hand brings the new one
        c.step("hand_l", 0, loc=AWAY, scale=0.0)
        c.step("hand_l", 10, loc=AWAY, scale=1.0)
        c.key("hand_l", 22, loc=(0.0, 0.0, -0.09))
        c.key("hand_l", 27, loc=(0.0, 0.0, -0.01))
        c.key("hand_l", 29, loc=(0.0, 0.0, -0.005))
        c.key("hand_l", 38, loc=(-0.04, -0.03, -0.06))
        c.key("hand_l", 44, loc=AWAY)
        c.step("hand_l", 45, scale=0.0)
        c.step("mag_new", 0, scale=1.0)
        c.step("mag_new", 28, scale=0.0)
        c.finish()

    c = Clip(arm, "draw")
    base(c, [0])
    c.hold_all([0])
    c.key("gun", 0, loc=(0, -0.05, -0.2), rot=(-55, 0, 20))
    c.key("gun", 12, loc=(0, 0, 0), rot=(0, 0, 0))
    c.finish()

    preview("m1911", [("idle", 0), ("fire", 1), ("reload", 20), ("reload", 28)])
    export(os.path.join(OUT_DIR, "m1911_fp.glb"))


# ---------------------------------------------------------------- M500

PUMP_PARTS = ("Cylinder_007", "Cylinder_026", "Cylinder_009", "Cylinder_008", "Cylinder_027")


def build_m500():
    reset()
    bpy.ops.wm.usd_import(filepath=USDZ)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in [o for o in bpy.context.scene.objects if o.type == "EMPTY"]:
        bpy.data.objects.remove(o)

    # model units -> metres, origin at the grip (behind the trigger)
    s = 0.00255
    grip_model = Vector((0.0, -80.0, 48.0))
    grip = Vector((0.12, 0.25, -0.215))
    yaw = math.radians(3.5)
    rot = Matrix.Rotation(yaw, 4, "Z")
    to_cam = Matrix.Translation(grip) @ rot @ Matrix.Scale(s, 4) @ Matrix.Translation(-grip_model)
    for o in meshes:
        o.matrix_world = to_cam @ o.matrix_world
        apply_all(o)
        n = len(o.data.vertices)
        if n > 3000:
            mod = o.modifiers.new("dec", "DECIMATE")
            mod.ratio = max(3000.0 / n, 0.22)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=mod.name)
        for p in o.data.polygons:
            p.use_smooth = True

    def g(model_v):  # model units -> camera space
        return grip + rot.to_3x3() @ ((Vector(model_v) - grip_model) * s)

    for img in bpy.data.images:
        if img.size[0] > 1024:
            img.scale(1024, 1024)

    pump = join([o for o in meshes if o.name.split("_Barrel")[0] in PUMP_PARTS], "Pump")
    body = join([o for o in bpy.context.scene.objects if o.type == "MESH" and o is not pump], "Shotgun")

    glove, sleeve = gloves()
    shell_mat = material("ShellHull", (0.6, 0.05, 0.04), roughness=0.4)
    brass = material("Brass", (0.85, 0.62, 0.25), metallic=1.0, roughness=0.3)

    pump_grip = g((0.0, 70.0, 44.0))
    hand_r = fist("HandR", g((0.0, -82.0, 40.0)), glove, rot=(-25, 0, 0), scale=(1.1, 1.0, 1.3))
    arm_r = limb_between("ArmR", g((0.0, -95.0, 30.0)), (0.3, -0.05, -0.45), 0.045, sleeve)
    hand_l = fist("HandL", pump_grip + Vector((-0.005, 0, -0.012)), glove, rot=(0, 0, 0), scale=(1.15, 1.6, 1.1))
    arm_l = limb_between("ArmL", pump_grip + Vector((-0.01, -0.03, -0.03)), (-0.22, 0.02, -0.45), 0.045, sleeve)
    shell = capsule("Shell", 0.0105, 0.068, shell_mat, segments=10)
    base_cap = capsule("ShellBase", 0.0112, 0.02, brass, segments=10)
    base_cap.location = (0, -0.026, 0)
    apply_all(base_cap)
    shell = join([shell, base_cap], "Shell")
    shell.matrix_world = Matrix.Translation(pump_grip + Vector((0, 0.0, -0.035)))
    apply_all(shell)

    arm = make_armature([
        ("gun", grip, None),
        ("pump", grip, "gun"),
        ("hand_l", pump_grip, "gun"),
        ("shell", pump_grip, "hand_l"),
        ("muzzle", g((0.0, 293.0, 71.5)), "gun"),
        ("eject", g((7.0, -20.0, 68.0)), "gun"),
        ("sight", g((0.0, -40.0, 79.5)), "gun"),
    ])
    for o, b in [(body, "gun"), (hand_r, "gun"), (arm_r, "gun"), (pump, "pump"),
                 (hand_l, "hand_l"), (arm_l, "hand_l"), (shell, "shell")]:
        bind(o, arm, b)

    PUMP_BACK = (0, -0.085, 0)
    PORT = (g((0.0, -30.0, 52.0)) - pump_grip)  # loading port, relative to the hand's rest

    c = Clip(arm, "idle")
    c.key("shell", 0, scale=0.0)
    c.hold_all([0, 1])
    c.finish()

    # fire + pump cycle (shell is ejected by the game at 0.6 s)
    c = Clip(arm, "fire")
    c.key("shell", 0, scale=0.0)
    c.hold_all([0])
    c.key("gun", 0, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key("gun", 2, loc=(0, -0.07, 0.015), rot=(12, 0, -3))
    c.key("gun", 7, loc=(0, -0.02, 0.004), rot=(4, 0, -1))
    c.key("gun", 12, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key("gun", 15, loc=(0, -0.01, 0), rot=(-2, 4, -6))
    c.key("gun", 25, loc=(0, -0.005, 0), rot=(-1, 2, -3))
    c.key("gun", 29, loc=(0, 0, 0), rot=(0, 0, 0))
    for b in ("pump", "hand_l"):
        c.key(b, 12, loc=(0, 0, 0))
        c.key(b, 17, loc=PUMP_BACK)
        c.key(b, 20, loc=PUMP_BACK)
        c.key(b, 25, loc=(0, 0, 0))
    c.finish()

    # reload: tilt, two shells pushed into the loading port, rack the pump
    c = Clip(arm, "reload")
    c.hold_all([0])
    tilt = dict(loc=(-0.05, 0.02, 0.05), rot=(10, 28, 4))
    c.key("gun", 0, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key("gun", 6, **tilt)
    c.key("gun", 36, **tilt)
    c.key("gun", 42, loc=(0, 0, 0), rot=(0, 0, 0))
    c.step("shell", 0, scale=0.0)
    c.key("hand_l", 0, loc=(0, 0, 0), rot=(0, 0, 0))
    below = PORT + Vector((0.0, -0.06, -0.12))
    t = 4
    for _ in range(2):
        c.key("hand_l", t + 3, loc=tuple(below), rot=(30, 0, 40))
        c.step("shell", t + 3, scale=1.0)
        c.key("hand_l", t + 9, loc=tuple(PORT + Vector((0, -0.03, -0.01))), rot=(10, 0, 30))
        c.key("hand_l", t + 12, loc=tuple(PORT + Vector((0, 0.03, 0.0))), rot=(10, 0, 30))
        c.step("shell", t + 13, scale=0.0)
        t += 14
    c.key("hand_l", 38, loc=(0, 0, 0), rot=(0, 0, 0))
    c.key("pump", 38, loc=(0, 0, 0))
    for b in ("pump", "hand_l"):
        c.key(b, 42, loc=(0, 0, 0))
        c.key(b, 45, loc=PUMP_BACK)
        c.key(b, 48, loc=(0, 0, 0))
    c.key("hand_l", 51, loc=(0, 0, 0))
    c.finish()

    c = Clip(arm, "draw")
    c.key("shell", 0, scale=0.0)
    c.hold_all([0])
    c.key("gun", 0, loc=(0, -0.1, -0.25), rot=(-50, 0, 25))
    c.key("gun", 14, loc=(0, 0, 0), rot=(0, 0, 0))
    c.finish()

    preview("m500", [("idle", 0), ("fire", 2), ("fire", 18), ("reload", 12)])
    export(os.path.join(OUT_DIR, "m500_fp.glb"))


if __name__ == "__main__":
    build_m1911()
    if USDZ:
        build_m500()
