"""Renders the icons for the weapon menu and the hotbar in Blender from the
exported models: assets/ui/icon_<id>.png (transparent, 512x256, side view)
for the guns (viewmodels), the AK's two sights, the grenade, the FPV drone,
the suppressor and the first aid (medkit, bandage, promedol).

Run (after build_weapons.py / build_sketchfab_kit.py):
  blender -b --python tools/blender/build_icons.py [-- id ...]
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WEAPONS = {"ak74": 3.0, "svd": 2.5, "asval": 3.0}  # id -> yaw the viewmodel was built with
PROPS = {"grenade": "grenade.glb", "fpv": "fpv_drone.glb", "suppressor": "suppressor.glb",
         "medkit": "../props/medkit.glb", "bandage": "../props/bandage.glb", "promedol": "../props/promedol.glb"}
# the AK's sights on their own (ak74_fp.glb): icon id -> mesh name prefixes kept
SIGHTS = {"kobra": ("Kobra",), "collimator": ("Aimpoint",)}
# small first aid things are seen from above at an angle, not from the side
TILTED = ("medkit", "bandage", "promedol")
# per icon: meshes left out (the AK icon shows it with the collimator)
DROP = {"ak74": ("Kobra",)}
ONLY = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []  # icon ids to render (all by default)
SKIP = ("Hand", "Arm", "Thumb", "Shell", "MagNew", "Clip", "Round", "RedDot")


def render_icon(wid, yaw, path=None, keep=None, src=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path or os.path.join(ROOT, "assets", "weapons", (src or wid) + "_fp.glb"))
    meshes = []
    for o in list(bpy.context.scene.objects):
        # the importer adds a bone display shape (unparented); hands are not part of the icon
        if o.type == "MESH" and (o.name.startswith(SKIP) or (path is None and o.parent_type != "BONE")
                                 or o.name.startswith(DROP.get(wid, ("-",))) or (keep and not o.name.startswith(keep))):
            bpy.data.objects.remove(o)
        elif o.type == "MESH":
            meshes.append(o)
    for o in bpy.context.scene.objects:
        if o.type == "ARMATURE":
            o.animation_data_clear()
            for pb in o.pose.bones:
                pb.location = (0, 0, 0)
                pb.rotation_quaternion = (1, 0, 0, 0)
                pb.rotation_euler = (0, 0, 0)
                pb.scale = (1, 1, 1)
    bpy.context.view_layer.update()
    # undo the viewmodel yaw so the gun lies flat along +Y
    unyaw = Matrix.Rotation(math.radians(-yaw), 4, "Z")
    pts = [unyaw @ (o.matrix_world @ Vector(c)) for o in meshes for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center = unyaw.inverted() @ ((mn + mx) / 2)
    size = mx - mn

    scene = bpy.context.scene
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(size.y, size.z * 2.0, size.x * (1.0 if keep or path is None else 2.0)) * 1.12
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    # look along -X at the right side of the gun, muzzle to the right
    look = Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(90), 4, "Z") @ Matrix.Rotation(math.radians(90), 4, "X")
    cam.matrix_world = Matrix.Translation(center + unyaw.inverted().to_3x3() @ Vector((2.0, 0, 0))) @ look
    if wid in TILTED:
        cam_data.ortho_scale = size.length * 1.7
        tilt = Matrix.Rotation(math.radians(-25), 4, "Z") @ Matrix.Rotation(math.radians(-48), 4, "Y")
        cam.matrix_world = Matrix.Translation(center) @ tilt @ Matrix.Translation(-center) @ cam.matrix_world
    scene.camera = cam
    for rot, energy in (((50, 10, 60), 4.0), ((-30, -20, -120), 1.5)):
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
        sun.data.energy = energy
        sun.rotation_euler = [math.radians(a) for a in rot]
        scene.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.5, 0.52, 1)
    scene.world = world
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.device = "CPU"
    scene.render.film_transparent = True
    scene.render.resolution_x = 512
    scene.render.resolution_y = 256
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    out = os.path.join(ROOT, "assets", "ui", "icon_%s.png" % wid)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    scene.render.filepath = out
    bpy.ops.render.render(write_still=True)
    print("ICON", out)


for wid, yaw in WEAPONS.items():
    if not ONLY or wid in ONLY:
        render_icon(wid, yaw)
for wid, keep in SIGHTS.items():
    if not ONLY or wid in ONLY:
        render_icon(wid, 3.0, keep=keep, src="ak74")
for wid, f in PROPS.items():
    if not ONLY or wid in ONLY:
        render_icon(wid, 0.0, os.path.join(ROOT, "assets", "weapons", f))
