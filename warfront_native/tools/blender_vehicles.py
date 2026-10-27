"""Convert the vehicle models into game-ready glTF files with named moving parts.

Run: blender -b -P blender_vehicles.py -- SRC_DIR OUT_DIR
SRC_DIR layout: abrams/ (OBJ + textures/), apache/ (OBJ + textures/), mig/source/model.gltf, su57.obj
Every model faces -Z in the engine (Blender +Y before export), Y up, real-world size in metres.
Ground vehicles have their origin at ground contact, aircraft at the middle of their bounding box.
Named nodes the game looks for: Abrams "Turret" > "Gun"; Apache "Rotor", "TailRotor"; aircraft "Nozzle_L", "Nozzle_R".
"""
import bpy, bmesh, sys, os, glob, math
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index('--') + 1:]
SRC, OUT = argv
os.makedirs(OUT, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def image_mat(name, path, rough=0.6, metal=0.2):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    t = m.node_tree.nodes.new('ShaderNodeTexImage'); t.image = bpy.data.images.load(path)
    m.node_tree.links.new(t.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal
    return m


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def bounds(objs):
    # computed from vertices: bound_box is cached and goes stale after mesh.transform()
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    return Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))), Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))


def transform_all(M):
    for o in meshes():
        o.data.transform(M @ o.matrix_world); o.matrix_world = Matrix.Identity(4)


def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    if parent:
        bpy.context.view_layer.update()
        e.parent = parent
        e.location = loc - parent.matrix_world.translation
    else:
        e.location = loc
    bpy.context.view_layer.update()
    return e


def attach(objs, parent):
    bpy.context.view_layer.update()
    for o in objs:
        wm = o.matrix_world.copy(); o.parent = parent; o.matrix_world = wm
    bpy.context.view_layer.update()


def join(objs, name):
    if not objs: return None
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1: bpy.ops.object.join()
    objs[0].name = name; return objs[0]


def split_by(obj, pred, name):
    """Move faces whose vertices all satisfy pred(co) into a new object."""
    bm = bmesh.new(); bm.from_mesh(obj.data)
    sel = [f for f in bm.faces if all(pred(obj.matrix_world @ v.co) for v in f.verts)]
    if not sel: bm.free(); return None
    new = bpy.data.meshes.new(name); nb = bmesh.new()
    uv_src = bm.loops.layers.uv.active; uv_dst = nb.loops.layers.uv.new('UVMap') if uv_src else None
    vmap = {}
    for f in sel:
        vs = []
        for v in f.verts:
            if v not in vmap: vmap[v] = nb.verts.new(v.co)
            vs.append(vmap[v])
        try:
            nf = nb.faces.new(vs)
        except ValueError:
            continue
        nf.material_index = f.material_index
        if uv_src:
            for a, b in zip(f.loops, nf.loops): b[uv_dst].uv = a[uv_src].uv
    bmesh.ops.delete(bm, geom=sel, context='FACES')
    bm.to_mesh(obj.data); bm.free(); nb.to_mesh(new); nb.free()
    for m in obj.data.materials: new.materials.append(m)
    o = bpy.data.objects.new(name, new); o.matrix_world = obj.matrix_world.copy()
    bpy.context.scene.collection.objects.link(o)
    return o


def export(name):
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + '.glb'), export_format='GLB', export_image_format='JPEG', export_jpeg_quality=88)
    mn, mx = bounds(meshes())
    print('VEHICLE', name, 'size', [round(v, 2) for v in (mx - mn)])


# ---------------- M1A2 Abrams: OBJ is Y-up, nose +Z, centimetres
reset()
d = os.path.join(SRC, 'abrams')
bpy.ops.wm.obj_import(filepath=glob.glob(os.path.join(d, '*.obj'))[0], use_split_groups=True, use_split_objects=True)
T = {'Main': image_mat('abrams_main', os.path.join(d, 'textures/Main_Defuse.jpg'), .75, .3),
     'Track': image_mat('abrams_track', os.path.join(d, 'textures/Track_Def.jpg'), .9, .1),
     'Minigun': image_mat('abrams_minigun', os.path.join(d, 'textures/Minigun_Defuse.jpg'), .5, .6),
     'Ministand': image_mat('abrams_stand', os.path.join(d, 'textures/Ministand_Defuse.jpg'), .6, .4)}
groups = {}
for o in meshes():
    g = next((k for k in ['Main_Body', 'Main_Stuff', 'Main_Turret', 'Main_Barrel', 'Main_Rotor', 'Main_Wheels', 'Track', 'Minigun', 'Ministand'] if k in o.name), None)
    o.data.materials.clear(); o.data.materials.append(T['Track'] if g == 'Track' else T['Minigun'] if g == 'Minigun' else T['Ministand'] if g == 'Ministand' else T['Main'])
    groups.setdefault(g, []).append(o)
# importer made it Z-up with nose at -Y; turn nose to +Y, scale to real size (hull 7.9 m)
transform_all(Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Scale(0.01367, 4))
mn, mx = bounds(meshes())
transform_all(Matrix.Translation((-(mn.x + mx.x) / 2, 0, -mn.z)))
turret = empty('Turret', Vector((0, -0.41, 1.51)))
gun = empty('Gun', Vector((0, 1.23, 1.85)), turret)   # trunnion in front of the turret ring
attach(groups.get('Main_Turret', []) + groups.get('Main_Stuff', []) + groups.get('Minigun', []) + groups.get('Ministand', []), turret)
attach(groups.get('Main_Barrel', []), gun)
export('abrams')

# ---------------- AH-64D Apache: OBJ is Y-up, nose +X, normalised units
reset()
d = os.path.join(SRC, 'apache')
bpy.ops.wm.obj_import(filepath=glob.glob(os.path.join(d, '*.obj'))[0], use_split_groups=True)
for o in meshes():
    key = next((k for k in ['Main_Body_1', 'Main_Body_2', 'Glass', 'Missile_1', 'Decal', 'Alpha'] if k in o.name), 'Main_Body_2')
    o.data.materials.clear()
    o.data.materials.append(image_mat('apache_' + key, os.path.join(d, 'textures', key + '.jpg'), .1 if key == 'Glass' else .7, .6 if key == 'Glass' else .25))
transform_all(Matrix.Rotation(math.pi / 2, 4, 'Z') @ Matrix.Scale(7.0, 4))     # nose +X -> +Y
body = join(meshes(), 'Body')
mn, mx = bounds([body])
transform_all(Matrix.Translation((-(mn.x + mx.x) / 2, 0, -mn.z)))
mn, mx = bounds([body])
# main rotor: everything above the blade root plane except the tail; tail rotor: small disc on the right of the fin
hub_z = mn.z + (0.095 + 0.3416) * 7.0
rotor = split_by(body, lambda c: c.z > hub_z and c.y > mn.y + 2.4, 'RotorMesh')
tail = split_by(body, lambda c: c.y < mn.y + 2.1 and c.z > mn.z + 2.6 and abs(c.x) > 0.52, 'TailRotorMesh')
rmn, rmx = bounds([rotor]); r = empty('Rotor', Vector(((rmn.x + rmx.x) / 2, (rmn.y + rmx.y) / 2, hub_z)))
attach([rotor], r)
if tail:
    tmn, tmx = bounds([tail]); t = empty('TailRotor', (tmn + tmx) / 2); attach([tail], t)
export('apache')

# ---------------- MiG-29 (Blockbench glTF): already nose -Z in glTF, 3.76 units long
reset()
bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, 'mig/source/model.gltf'))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.parent_clear(type='CLEAR_KEEP_TRANSFORM')
for o in list(meshes()):
    imgs = [n.image.name for m in o.data.materials if m and m.node_tree for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image]
    if any(i in ('Image_4', 'Image_5') for i in imgs):   # missiles and landing gear textures
        bpy.data.objects.remove(o)
print('MIG IMAGES', sorted({n.image.name for m in bpy.data.materials if m.node_tree for n in m.node_tree.nodes if n.type == 'TEX_IMAGE' and n.image}))
for o in meshes():
    for m in o.data.materials:
        if m and m.node_tree:
            for n in m.node_tree.nodes:
                if n.type == 'TEX_IMAGE': n.interpolation = 'Closest'
transform_all(Matrix.Scale(4.6, 4))
mn, mx = bounds(meshes())
transform_all(Matrix.Translation(-(mn + mx) / 2))
mn, mx = bounds(meshes())
for s, nm in ((-1, 'Nozzle_L'), (1, 'Nozzle_R')): empty(nm, Vector((s * 0.8, mn.y + 0.3, -0.15)))
for o in list(bpy.context.scene.objects):
    if o.type == 'EMPTY' and not o.name.startswith('Nozzle'):
        bpy.data.objects.remove(o)
export('mig29')

# ---------------- Su-57 (Roblox OBJ, no materials): Y-up, nose -X; grey digital camouflage in vertex colours
reset()
bpy.ops.wm.obj_import(filepath=os.path.join(SRC, 'su57.obj'), use_split_groups=True)
for o in list(meshes()):
    if any(k in o.name for k in ('Object621', 'Object51', 'Object21', 'Object821')):
        bpy.data.objects.remove(o)
transform_all(Matrix.Rotation(-math.pi / 2, 4, 'Z') @ Matrix.Scale(20.1 / 86.45, 4))
mn, mx = bounds(meshes())
transform_all(Matrix.Translation(-(mn + mx) / 2))
body = mat_glass = None
glass = bpy.data.materials.new('su57_canopy'); glass.use_nodes = True
gb = glass.node_tree.nodes['Principled BSDF']; gb.inputs['Base Color'].default_value = (.55, .42, .14, 1); gb.inputs['Metallic'].default_value = 1; gb.inputs['Roughness'].default_value = .08
skin = bpy.data.materials.new('su57_skin'); skin.use_nodes = True
sb = skin.node_tree.nodes['Principled BSDF']; vc = skin.node_tree.nodes.new('ShaderNodeVertexColor'); vc.layer_name = 'Col'
skin.node_tree.links.new(vc.outputs['Color'], sb.inputs['Base Color']); sb.inputs['Roughness'].default_value = .45; sb.inputs['Metallic'].default_value = .3


def hsh(a, b):
    h = math.sin(a * 127.1 + b * 311.7) * 43758.5453
    return h - math.floor(h)


LIGHT, MID, DARK, METAL = (.74, .77, .80), (.50, .56, .62), (.30, .35, .41), (.22, .21, .22)
for o in meshes():
    o.data.materials.clear()
    o.data.materials.append(glass if 'Object11' in o.name else skin)
    if 'Object11' in o.name: continue
    col = o.data.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    for v in o.data.vertices:
        x, fwd, z = v.co.x, v.co.y, v.co.z
        n = v.normal
        if fwd < -8.6: c = METAL
        else:
            big = math.sin(abs(x) * .55 + 1.3) * math.cos(fwd * .42) + math.sin(fwd * .9 + abs(x) * .3) * .6
            val = big + hsh(math.floor(abs(x) / .75), math.floor(fwd / .75)) * .9 - .45
            c = DARK if val > .55 else MID if val > -.1 else LIGHT
            if n.z < -.35 and val < .9: c = LIGHT
            if fwd > 8.8: c = MID
        g = .92 + hsh(math.floor(x * 3), math.floor(fwd * 3)) * .12
        col.data[v.index].color = (c[0] * g, c[1] * g, c[2] * g, 1)
mn, mx = bounds(meshes())
for s, nm in ((-1, 'Nozzle_L'), (1, 'Nozzle_R')): empty(nm, Vector((s * 1.35, mn.y + 0.3, -0.25)))
export('su57')
