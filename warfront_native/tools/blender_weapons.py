"""Infantry weapons: AK-47 and M500 shotgun (USDZ) and the FIM-92 Stinger (FBX), scaled to real size,
muzzle pointing forward (Blender +Y = engine -Z), origin at the pistol grip.

Run: blender -b -P blender_weapons.py -- SRC_DIR OUT_DIR
SRC_DIR: ak.usdz, m500.usdz, stinger/stinger.fbx + stinger/<material>_Base_color.png, _Normal.png
Writes <name>.glb and weapons.json with the muzzle and fore-grip positions in engine coordinates.
"""
import bpy, bmesh, sys, os, math, json
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index('--') + 1:]
SRC, OUT = argv[0], argv[1]
os.makedirs(OUT, exist_ok=True)
info = {}


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def flatten():
    """Bake all transforms into the meshes and drop empties."""
    bpy.context.view_layer.update()
    for o in meshes():
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    for o in [o for o in bpy.context.scene.objects if o.type != 'MESH']:
        bpy.data.objects.remove(o)


def bounds(objs):
    pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    return Vector([min(p[k] for p in pts) for k in range(3)]), Vector([max(p[k] for p in pts) for k in range(3)])


def centre(objs):
    a, b = bounds(objs)
    return (a + b) / 2


def join_all(name):
    ms = meshes()
    bpy.ops.object.select_all(action='DESELECT')
    for o in ms: o.select_set(True)
    bpy.context.view_layer.objects.active = ms[0]
    if len(ms) > 1: bpy.ops.object.join()
    ms[0].name = name
    return ms[0]


def finish(name, length, muzzle_objs, grip_frac, fore_frac, decimate=1.0):
    """Orient the long axis with the muzzle at +Y, scale to `length`, put the origin at the grip."""
    flatten()
    allm = meshes()
    mn, mx = bounds(allm)
    ext = mx - mn
    ax = max(range(3), key=lambda k: ext[k])
    mc = centre(muzzle_objs) if muzzle_objs else mx
    c = (mn + mx) / 2
    sign = 1 if mc[ax] > c[ax] else -1
    # rotation taking the muzzle axis to +Y
    d = Vector((0, 0, 0)); d[ax] = sign
    R = d.rotation_difference(Vector((0, 1, 0))).to_matrix().to_4x4()
    o = join_all(name)
    o.data.transform(R)
    mn, mx = bounds([o])
    s = length / (mx.y - mn.y)
    o.data.transform(Matrix.Scale(s, 4))
    mn, mx = bounds([o])
    gy = mn.y + (mx.y - mn.y) * grip_frac
    gz = (mn.z + mx.z) / 2
    o.data.transform(Matrix.Translation(Vector((-(mn.x + mx.x) / 2, -gy, -gz))))
    mn, mx = bounds([o])
    if decimate < 1.0:
        md = o.modifiers.new('d', 'DECIMATE'); md.ratio = decimate
        bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier='d')
    fy = mn.y + (mx.y - mn.y) * fore_frac
    # engine coordinates: (x, z, -y)
    info[name] = {"muzzle": [0.0, 0.0, -mx.y], "fore": [0.0, -0.02, -fy], "length": length, "faces": len(o.data.polygons)}
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + '.glb'), export_format='GLB', export_image_format='JPEG', export_jpeg_quality=88)
    print('WEAPON', name, 'faces', len(o.data.polygons), 'size', [round(v, 3) for v in (mx - mn)])


# AK-47 (real length 0.88 m)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=os.path.join(SRC, 'ak.usdz'))
bpy.context.view_layer.update()
finish('ak47', 0.88, [o for o in meshes() if 'barrel' in o.name.lower()], 0.32, 0.6)

# Mossberg M500 with silencer (~1.15 m)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=os.path.join(SRC, 'm500.usdz'))
bpy.context.view_layer.update()
finish('m500', 1.15, [o for o in meshes() if 'silencer' in o.name.lower()], 0.3, 0.55, decimate=0.08)

# FIM-92 Stinger (1.52 m)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=os.path.join(SRC, 'stinger/stinger.fbx'))
# the file also shows the missile lying beside the launcher: keep only the launch tube and gripstock
for o in [o for o in meshes() if o.data.materials and o.data.materials[0].name.split('.')[0] in ('blinn1', 'blinn2', 'blinn3', 'blinn4', 'lambert1')]:
    bpy.data.objects.remove(o)
for m in bpy.data.materials:
    base = os.path.join(SRC, 'stinger', m.name + '_Base_color.png')
    if not os.path.exists(base) or not m.use_nodes:
        continue
    nt = m.node_tree
    b = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if b is None:
        continue
    t = nt.nodes.new('ShaderNodeTexImage'); t.image = bpy.data.images.load(base)
    nt.links.new(t.outputs['Color'], b.inputs['Base Color'])
    nrm = os.path.join(SRC, 'stinger', m.name + '_Normal.png')
    if os.path.exists(nrm):
        n = nt.nodes.new('ShaderNodeTexImage'); n.image = bpy.data.images.load(nrm); n.image.colorspace_settings.name = 'Non-Color'
        nm = nt.nodes.new('ShaderNodeNormalMap'); nt.links.new(n.outputs['Color'], nm.inputs['Color']); nt.links.new(nm.outputs['Normal'], b.inputs['Normal'])
    b.inputs['Roughness'].default_value = 0.6
bpy.context.view_layer.update()
# the gripstock (lambert3) sits towards the front of the tube
finish('stinger', 1.52, [o for o in meshes() if o.data.materials and o.data.materials[0].name.startswith('lambert3')], 0.72, 0.9)

json.dump(info, open(os.path.join(OUT, 'weapons.json'), 'w'), indent=1)
print('WEAPONS', info)
