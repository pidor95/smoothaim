"""Second batch of vehicle models: new Su-57 (PBR textured), new Mi-24 (textured) and the Pantsir-S1.
Every model also gets ambient occlusion baked into its vertex colours so it reads as a solid volume in the game.

Run: blender -b -P blender_models2.py -- SRC_DIR OUT_DIR
SRC_DIR layout:
  su57/base.obj + su57/texture_diffuse.png, texture_normal.png
  mi24/mi24.glb (the ASCII FBX converted with Godot) + mi24/helicopter_mi-24.png, helicopter_mi-24_norm.png
  pantsir/pantsir_s1.obj + pantsir/pantsir_s1.png
Conventions as in blender_vehicles.py: engine forward is Blender +Y, Z up, metres; aircraft origin at the middle
of the bounding box, ground vehicles at ground contact. Named nodes: "Rotor", "TailRotor", "Nozzle_L/R", "Turret", "Gun".
"""
import bpy, bmesh, sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aolib import bake_ao
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index('--') + 1:]
SRC, OUT = argv[0], argv[1]
ONLY = argv[2] if len(argv) > 2 else ''
os.makedirs(OUT, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def bake_world():
    """Put mesh transforms into the vertices so every later step works in world space."""
    bpy.context.view_layer.update()
    for o in meshes():
        if o.parent is None:
            o.data.transform(o.matrix_world)
            o.matrix_world = Matrix.Identity(4)


def bounds(objs):
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    return (Vector([min(p[k] for p in pts) for k in range(3)]), Vector([max(p[k] for p in pts) for k in range(3)]))


def transform(M):
    for o in meshes():
        if o.parent is None:
            o.data.transform(M)


def tex_mat(name, color, normal=None, rough=0.55, metal=0.2):
    m = bpy.data.materials.new(name); m.use_nodes = True
    nt = m.node_tree; b = nt.nodes['Principled BSDF']
    t = nt.nodes.new('ShaderNodeTexImage'); t.image = bpy.data.images.load(color)
    nt.links.new(t.outputs['Color'], b.inputs['Base Color'])
    if normal:
        n = nt.nodes.new('ShaderNodeTexImage'); n.image = bpy.data.images.load(normal); n.image.colorspace_settings.name = 'Non-Color'
        nm = nt.nodes.new('ShaderNodeNormalMap'); nt.links.new(n.outputs['Color'], nm.inputs['Color']); nt.links.new(nm.outputs['Normal'], b.inputs['Normal'])
    b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal
    return m


def split_faces(obj, pred, name):
    """Move faces for which pred(face_center, verts) is true into a new object (keeps UVs and materials)."""
    bm = bmesh.new(); bm.from_mesh(obj.data)
    sel = [f for f in bm.faces if pred(f)]
    if not sel:
        bm.free(); return None
    new_bm = bm.copy()
    keep = {f.index for f in sel}
    bmesh.ops.delete(new_bm, geom=[f for f in new_bm.faces if f.index not in keep], context='FACES')
    bmesh.ops.delete(bm, geom=sel, context='FACES')
    bm.to_mesh(obj.data); bm.free()
    me = bpy.data.meshes.new(name); new_bm.to_mesh(me); new_bm.free()
    for m in obj.data.materials: me.materials.append(m)
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    return o


def islands(bm):
    bm.faces.ensure_lookup_table(); seen = set(); out = []
    for f in bm.faces:
        if f.index in seen: continue
        stack = [f]; seen.add(f.index); comp = []
        while stack:
            g = stack.pop(); comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h.index not in seen: seen.add(h.index); stack.append(h)
        out.append(comp)
    return out


def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None); bpy.context.scene.collection.objects.link(e)
    e.location = loc
    if parent:
        bpy.context.view_layer.update()
        e.parent = parent; e.matrix_parent_inverse = parent.matrix_world.inverted()
    return e


def attach(o, parent):
    bpy.context.view_layer.update()
    wm = o.matrix_world.copy(); o.parent = parent; o.matrix_world = wm


def smooth(o, angle=40):
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active = o
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
    except Exception:
        bpy.ops.object.shade_smooth()


def decimate(o, ratio):
    md = o.modifiers.new('dec', 'DECIMATE'); md.ratio = ratio
    bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active = o
    bpy.ops.object.modifier_apply(modifier=md.name)


def export(name):
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + '.glb'), export_format='GLB', export_image_format='JPEG',
                              export_jpeg_quality=90, export_vertex_color='MATERIAL')
    mn, mx = bounds(meshes())
    print('VEHICLE', name, 'size', [round(v, 2) for v in (mx - mn)])


def centre_aircraft():
    mn, mx = bounds(meshes())
    c = (mn + mx) / 2
    transform(Matrix.Translation(-c))
    return mn - c, mx - c


# ---------------------------------------------------------------- Su-57
if ONLY in ('', 'su57'):
    reset()
    bpy.ops.wm.obj_import(filepath=os.path.join(SRC, 'su57/base.obj'))
    bake_world()
    o = meshes()[0]; o.name = 'Body'
    # landing gear hangs below the belly: cut it off (the jet is always airborne in the game)
    bm = bmesh.new(); bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if any(v.co.z < -0.14 for v in f.verts)], context='FACES')
    bm.to_mesh(o.data); bm.free()
    # nose is -Y in the file; the engine wants it at +Y. Real length 20.1 m
    mn, mx = bounds([o])
    transform(Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Scale(20.1 / (mx.y - mn.y), 4))
    decimate(o, 0.45)
    o.data.materials.clear()
    o.data.materials.append(tex_mat('su57_skin', os.path.join(SRC, 'su57/texture_diffuse.png'), os.path.join(SRC, 'su57/texture_normal.png'), 0.42, 0.35))
    smooth(o, 50)
    mn, mx = centre_aircraft()
    # nozzles: the two clusters of vertices at the very back
    back = [v.co for v in o.data.vertices if v.co.y < mn.y + 0.6 and abs(v.co.x) < 2.0 and abs(v.co.z) < 1.0]
    for s, nm in ((-1, 'Nozzle_L'), (1, 'Nozzle_R')):
        side = [p for p in back if p.x * s > 0.2] or [Vector((s * 1.2, mn.y, 0))]
        c = sum(side, Vector()) / len(side)
        empty(nm, Vector((c.x, mn.y + 0.3, c.z)))
    bake_ao(32)
    export('su57')

# ---------------------------------------------------------------- Mi-24
if ONLY in ('', 'mi24'):
    reset()
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, 'mi24/mi24.glb'))
    bake_world()
    for e in [x for x in bpy.context.scene.objects if x.type != 'MESH']:
        for ch in list(e.children):
            attach(ch, None)
        bpy.data.objects.remove(e)
    bake_world()
    o = meshes()[0]; o.name = 'Body'
    # file: nose +X, ~0.18 units long including rotors (real overall length 21.3 m)
    mn, mx = bounds([o])
    transform(Matrix.Rotation(math.pi / 2, 4, 'Z') @ Matrix.Scale(21.3 / (mx.x - mn.x), 4))
    o.data.materials.clear()
    o.data.materials.append(tex_mat('mi24_skin', os.path.join(SRC, 'mi24/helicopter_mi-24.png'), os.path.join(SRC, 'mi24/helicopter_mi-24_norm.png'), 0.6, 0.15))
    # main rotor: thin wide islands up top; tail rotor: small islands at the tail, beside the fin
    def classify(obj):
        bmx = bmesh.new(); bmx.from_mesh(obj.data)
        comps = islands(bmx)
        big = max(comps, key=len)
        cx = sum(v.co.x for f in big for v in f.verts) / sum(len(f.verts) for f in big)
        lo, hi = bounds([obj])
        rot, tail = set(), set()
        for comp in comps:
            vs = {v for f in comp for v in f.verts}
            q0 = Vector([min(v.co[k] for v in vs) for k in range(3)]); q1 = Vector([max(v.co[k] for v in vs) for k in range(3)])
            ext = max(q1.x - q0.x, q1.y - q0.y)
            ccx = (q0.x + q1.x) / 2 - cx
            if q1.z - q0.z < 0.6 and ext > 1.0 and q0.y > lo.y + 4.0 and q0.z > lo.z + 4.2:
                rot |= {f.index for f in comp}
            elif q1.y < lo.y + 3.5 and q0.z > lo.z + 2.5 and abs(ccx) > 0.3 and ext < 4.5:
                tail |= {f.index for f in comp}
        bmx.free()
        return rot, tail, cx

    rot_faces, _, cx = classify(o)
    rm = split_faces(o, lambda f: f.index in rot_faces, 'RotorMesh')
    _, tail_faces, _ = classify(o)
    tm = split_faces(o, lambda f: f.index in tail_faces, 'TailRotorMesh')
    print('ROTOR faces', len(rot_faces), 'TAIL faces', len(tail_faces), 'centreline', round(cx, 2))
    transform(Matrix.Translation(Vector((-cx, 0, 0))))
    smooth(o, 45)
    mn, mx = centre_aircraft()
    # rotor hubs: the blades are evenly spaced, so the vertex centroid is the axis
    def centroid(obj):
        return sum((v.co for v in obj.data.vertices), Vector()) / len(obj.data.vertices)
    if rm:
        r = empty('Rotor', centroid(rm))
        attach(rm, r)
    if tm:
        t = empty('TailRotor', centroid(tm))
        attach(tm, t)
    bake_ao(48)
    export('mi24')

# ---------------------------------------------------------------- Pantsir-S1
if ONLY in ('', 'pantsir'):
    reset()
    bpy.ops.wm.obj_import(filepath=os.path.join(SRC, 'pantsir/pantsir_s1.obj'))
    bake_world()
    pal = bpy.data.images.load(os.path.join(SRC, 'pantsir/pantsir_s1.png'))
    m = bpy.data.materials.new('pantsir'); m.use_nodes = True
    t = m.node_tree.nodes.new('ShaderNodeTexImage'); t.image = pal; t.interpolation = 'Closest'
    b = m.node_tree.nodes['Principled BSDF']; m.node_tree.links.new(t.outputs['Color'], b.inputs['Base Color'])
    b.inputs['Roughness'].default_value = 0.75; b.inputs['Metallic'].default_value = 0.1
    groups = {}
    for o in meshes():
        o.data.materials.clear(); o.data.materials.append(m)
        base = o.name.split('.')[0]
        groups.setdefault('tower' if base == 'tower' else 'body', []).append(o)

    def join(objs, name):
        bpy.ops.object.select_all(action='DESELECT')
        for x in objs: x.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join(); objs[0].name = name; return objs[0]

    body = join(groups['body'], 'Body')
    tower = join(groups['tower'], 'TurretMesh')
    # truck faces the end away from the turret; real width 2.6 m
    mn, mx = bounds([body, tower])
    tmn, tmx = bounds([tower])
    rot = 0.0 if (tmn.y + tmx.y) / 2 < (mn.y + mx.y) / 2 else math.pi
    s = 2.6 / (mx.x - mn.x)
    transform(Matrix.Rotation(rot, 4, 'Z') @ Matrix.Scale(s, 4))
    mn, mx = bounds([body, tower])
    transform(Matrix.Translation(Vector((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))))
    tmn, tmx = bounds([tower])
    turret = empty('Turret', Vector(((tmn.x + tmx.x) / 2, (tmn.y + tmx.y) / 2, tmn.z)))
    attach(tower, turret)
    # missiles and guns sit on the turret sides; the "Gun" node marks where they point from
    empty('Gun', Vector(((tmn.x + tmx.x) / 2, tmx.y, (tmn.z + tmx.z) / 2)), turret)
    bake_ao(24, 0.5)
    export('pantsir')
