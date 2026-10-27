"""Generate forest-steppe trees with the Sapling Tree Gen add-on and bake them into billboard atlases.

Run: blender -b -P blender_trees.py -- OUT_DIR BARK_COLOR.jpg LEAF.png
Output per species: <name>.png (two 1024x1024 views side by side, RGBA) and <name>.json (quad size, base offset).
"""
import bpy, sys, os, json, math, ast, random
from mathutils import Vector

argv = sys.argv[sys.argv.index('--') + 1:]
OUT, BARK, LEAF = argv[0], argv[1], argv[2]
os.makedirs(OUT, exist_ok=True)
import addon_utils
addon_utils.enable('bl_ext.user_default.sapling_tree_gen', default_set=True)
import importlib
sap = importlib.import_module('bl_ext.user_default.sapling_tree_gen')
PDIR = os.path.join(os.path.dirname(sap.__file__), 'presets')


def preset(name):
    src = open(os.path.join(PDIR, name + '.py')).read()
    return ast.literal_eval(src[src.index('{'):])


# species: base preset + overrides; heights are in metres
SPECIES = {
    'birch': ('white_birch', {'scale': 17, 'leafScale': 0.32, 'leaves': 22}),
    'aspen': ('white_birch', {'scale': 20, 'shape': '4', 'leafScale': 0.3, 'leaves': 26, 'seed': 3}),
    'maple': ('small_maple', {'scale': 13, 'leafScale': 0.42, 'leaves': 26}),
    'oak': ('small_maple', {'scale': 16, 'scaleV': 3, 'shape': '1', 'leafScale': 0.45, 'leaves': 30, 'baseSize': 0.28,
                            'downAngle': (90.0, 75.0, 50.0, 45.0), 'seed': 11}),
    'poplar': ('small_maple', {'scale': 24, 'scaleV': 2, 'shape': '3', 'baseSize': 0.12, 'downAngle': (90.0, 22.0, 30.0, 45.0),
                               'downAngleV': (0.0, 6.0, 10.0, 10.0), 'leafScale': 0.36, 'leaves': 30, 'seed': 5}),
}
ONLY = argv[3].split(',') if len(argv) > 3 else None


def material(name, img_path, alpha):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; bsdf = nt.nodes['Principled BSDF']
    tex = nt.nodes.new('ShaderNodeTexImage'); tex.image = bpy.data.images.load(img_path)
    nt.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    if alpha:
        nt.links.new(tex.outputs['Alpha'], bsdf.inputs['Alpha'])
        bsdf.inputs['Roughness'].default_value = 0.7
        if 'Subsurface Weight' in bsdf.inputs: pass
    else:
        mapn = nt.nodes.new('ShaderNodeMapping'); tc = nt.nodes.new('ShaderNodeTexCoord')
        mapn.inputs['Scale'].default_value = (3, 1, 1)
        nt.links.new(tc.outputs['UV'], mapn.inputs['Vector']); nt.links.new(mapn.outputs['Vector'], tex.inputs['Vector'])
        bsdf.inputs['Roughness'].default_value = 0.9
    return m


R = 1024
for name, (base, over) in SPECIES.items():
    if ONLY and name not in ONLY:
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    addon_utils.enable('bl_ext.user_default.sapling_tree_gen', default_set=True)
    params = preset(base); params.update(over)
    params['showLeaves'] = True; params['makeMesh'] = False; params['bevel'] = True
    params['leafShape'] = 'rect'; params['useArm'] = False; params['armAnim'] = False; params['leafAnim'] = False
    params = {k: v for k, v in params.items() if k not in ('limitImport',)}
    bpy.ops.curve.tree_add(**params)
    scn = bpy.context.scene
    bark = material('bark', BARK, False); leaf = material('leaf', LEAF, True)
    for o in list(scn.objects):
        if o.type == 'CURVE':
            o.data.materials.append(bark)
        elif o.type == 'MESH':
            o.data.materials.append(leaf)
    objs = [o for o in scn.objects if o.type in ('MESH', 'CURVE')]
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    size = mx - mn; cx, cy = (mn.x + mx.x) / 2, (mn.y + mx.y) / 2
    height = size.z; width = max(size.x, size.y)
    scale = max(height, width) * 1.04
    scn.render.engine = 'CYCLES'; scn.cycles.samples = 40; scn.cycles.device = 'CPU'
    scn.cycles.transparent_max_bounces = 24
    scn.render.film_transparent = True
    scn.render.resolution_x = scn.render.resolution_y = R
    scn.render.image_settings.file_format = 'PNG'; scn.render.image_settings.color_mode = 'RGBA'
    scn.view_settings.view_transform = 'Standard'
    world = bpy.data.worlds.new('w'); scn.world = world; world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (0.78, 0.82, 0.86, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = 0.9
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN'))
    sun.data.energy = 2.5; sun.rotation_euler = (math.radians(40), 0, math.radians(25)); scn.collection.objects.link(sun)
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); cam.data.type = 'ORTHO'; cam.data.ortho_scale = scale
    scn.collection.objects.link(cam); scn.camera = cam
    shots = []
    for i, ang in enumerate([0, 90]):
        a = math.radians(ang); d = scale * 3
        cam.location = (cx + math.sin(a) * d, cy - math.cos(a) * d, mn.z + scale / 2)
        cam.rotation_euler = (math.radians(90), 0, a)
        f = os.path.join(OUT, '%s_%d.png' % (name, i)); scn.render.filepath = f
        bpy.ops.render.render(write_still=True); shots.append(f)
    imgs = [bpy.data.images.load(f) for f in shots]
    atlas = bpy.data.images.new(name, R * 2, R, alpha=True)
    import numpy as np
    buf = np.zeros((R, R * 2, 4), np.float32)
    for k, im in enumerate(imgs):
        a = np.empty(R * R * 4, np.float32); im.pixels.foreach_get(a)
        buf[:, k * R:(k + 1) * R] = a.reshape(R, R, 4)
    atlas.pixels.foreach_set(buf.ravel())
    atlas.filepath_raw = os.path.join(OUT, name + '.png'); atlas.file_format = 'PNG'; atlas.save()
    for f in shots: os.remove(f)
    json.dump({'size': scale, 'tree_height': height, 'crown_width': width, 'base_offset': 0.0}, open(os.path.join(OUT, name + '.json'), 'w'))
    print('TREE', name, 'height', round(height, 1), 'width', round(width, 1))
