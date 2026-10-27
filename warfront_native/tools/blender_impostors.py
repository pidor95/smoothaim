"""Render vegetation models into billboard atlases (run with: blender -b -P blender_impostors.py -- OUT_DIR model.gltf ...).

For each model: two orthographic views (front and side) with a transparent background are packed side by side
into one RGBA image <name>.png (each view 512x1024), and the real height/width go to <name>.json.
The game draws them as two crossed quads, which is how mobile games keep thousands of trees cheap.
"""
import bpy, sys, os, json, math
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
out_dir, models = argv[0], argv[1:]
os.makedirs(out_dir, exist_ok=True)
W, H = 512, 1024

for path in models:
    name = os.path.basename(path).replace('_1k.gltf', '').replace('.gltf', '').replace('.glb', '')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    size = mx - mn
    cx, cy = (mn.x + mx.x) / 2, (mn.y + mx.y) / 2
    height = size.z
    width = max(size.x, size.y, height * 0.25)
    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'
    scn.cycles.samples = 48
    scn.cycles.device = 'CPU'
    scn.render.film_transparent = True
    scn.render.resolution_x, scn.render.resolution_y = W, H
    scn.render.image_settings.file_format = 'PNG'
    scn.render.image_settings.color_mode = 'RGBA'
    scn.view_settings.view_transform = 'Standard'
    # neutral daylight: soft sky dome plus a weak sun from above, so in-game lighting can tint it
    world = bpy.data.worlds.new('w'); scn.world = world; world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (0.75, 0.8, 0.85, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = 1.1
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN'))
    sun.data.energy = 2.2; sun.rotation_euler = (math.radians(35), 0, math.radians(30)); scn.collection.objects.link(sun)
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = max(height, width * 2) * 1.02
    scn.collection.objects.link(cam); scn.camera = cam
    shots = []
    for i, ang in enumerate([0, 90]):
        a = math.radians(ang)
        d = max(size.x, size.y, height) * 3
        cam.location = (cx + math.sin(a) * d, cy - math.cos(a) * d, mn.z + height / 2)
        cam.rotation_euler = (math.radians(90), 0, a)
        # ortho_scale covers the larger render dimension (height); keep 1:2 aspect
        cam.data.ortho_scale = max(height, width * 2) * 1.02
        f = os.path.join(out_dir, '%s_%d.png' % (name, i))
        scn.render.filepath = f
        bpy.ops.render.render(write_still=True)
        shots.append(f)
    img = [bpy.data.images.load(f) for f in shots]
    atlas = bpy.data.images.new(name, W * 2, H, alpha=True)
    px = [0.0] * (W * 2 * H * 4)
    for k, im in enumerate(img):
        p = list(im.pixels)
        for y in range(H):
            row = p[y * W * 4:(y + 1) * W * 4]
            px[(y * W * 2 + k * W) * 4:(y * W * 2 + k * W + W) * 4] = row
    atlas.pixels = px
    atlas.filepath_raw = os.path.join(out_dir, name + '.png'); atlas.file_format = 'PNG'; atlas.save()
    scale = max(height, width * 2) * 1.02
    json.dump({'height': scale, 'width': scale / 2, 'tree_height': height, 'base_offset': height / 2 - scale / 2}, open(os.path.join(out_dir, name + '.json'), 'w'))
    for f in shots: os.remove(f)
    print('IMPOSTOR', name, 'height', round(height, 2), 'width', round(width, 2))
