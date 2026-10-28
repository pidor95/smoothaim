"""Attack aircraft: Su-25M, Su-24M (with Storm Shadow under the belly) and Su-27.
Unlike the other jets these keep their landing gear as a separate "Gear" node: the game shows it while the
aircraft rolls out of the hangar and takes off, then hides it. Ammo-carrying stores get "Store_L"/"Store_R" nodes.

Run: blender -b -P blender_attack.py -- SRC_DIR OUT_DIR [su25|su24|su27]
SRC_DIR layout:
  su25.glb                    low_poly_ukrainian_su-25m.glb (Sketchfab), nose -X, Z up, metres
  su24/source/*.fbx           + su24/textures/mat0_c.jpeg ... mat5_c.jpeg, nose -Y
  su27.obj                    Roblox export without textures, nose -Y after import, gear down
Conventions as in blender_models2.py: engine forward is Blender +Y, Z up, metres, origin at the middle of the airframe.
"""
import bpy, bmesh, sys, os, math, glob
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


def flatten():
    """Drop the imported hierarchy: every mesh becomes a root object with its transform baked into the vertices."""
    bpy.context.view_layer.update()
    for o in meshes():
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(mw)
        o.matrix_world = Matrix.Identity(4)
    for e in [x for x in bpy.context.scene.objects if x.type != 'MESH']:
        bpy.data.objects.remove(e)


def bounds(objs):
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    return (Vector([min(p[k] for p in pts) for k in range(3)]), Vector([max(p[k] for p in pts) for k in range(3)]))


def transform(M):
    for o in meshes():
        if o.parent is None:
            o.data.transform(M)


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
    bpy.ops.object.select_all(action='DESELECT')
    for x in objs:
        x.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


def split_faces(obj, pred, name):
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
    for m in obj.data.materials:
        me.materials.append(m)
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    return o


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


def paint(name, col, rough=0.55, metal=0.25):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*col, 1.0)
    b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal
    return m


def finish(name, body, gear, length, nozzles=(0.3, 1.5, 0.0), stores=()):
    """Scale to the real length, centre on the airframe, add gear/nozzle/store nodes, bake AO and export."""
    mn, mx = bounds([body])
    transform(Matrix.Scale(length / (mx.y - mn.y), 4))
    mn, mx = bounds([body])
    c = (mn + mx) / 2
    transform(Matrix.Translation(-c))
    mn, mx = mn - c, mx - c
    if gear:
        gmn, _ = bounds([gear])
        g = empty('Gear', Vector((0, 0, 0)))
        attach(gear, g)
        # height of the origin above the runway when standing on the wheels (goes into data.gd as gear_h)
        print('GEAR', name, 'gear_h', round(-gmn.z, 2))
    if isinstance(nozzles[0], float):
        # nozzles = (min |x|, max |x|, max z) window where the engine exhausts are; take the rearmost ring on each side
        x0, x1, z1 = nozzles
        found = []
        for s in (-1, 1):
            vs = [v.co for v in body.data.vertices if x0 < v.co.x * s < x1 and v.co.z < z1 and v.co.y < mn.y + length * 0.25]
            y0 = min(p.y for p in vs)
            ring = [p for p in vs if p.y < y0 + 0.25]
            q = sum(ring, Vector()) / len(ring)
            found.append(Vector((q.x, y0 + 0.3, q.z)))
        nozzles = found
    else:
        # separate nozzle meshes: their centres, then they go back into the body
        found = []
        for o in nozzles:
            q = sum((v.co for v in o.data.vertices), Vector()) / len(o.data.vertices)
            lo, _ = bounds([o])
            found.append(Vector((q.x, lo.y + 0.3, q.z)))
        join([body] + list(nozzles), body.name)
        nozzles = found
    for nm, q in zip(('Nozzle_L', 'Nozzle_R'), nozzles):
        empty(nm, q)
        print('NOZZLE', name, nm, [round(v, 2) for v in q])
    for st in stores:
        if st:
            smn, smx = bounds([st])
            node = empty(st.name.replace('Mesh', ''), (smn + smx) / 2)
            attach(st, node)
    bake_ao(32)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + '.glb'), export_format='GLB', export_image_format='JPEG',
                              export_jpeg_quality=88, export_vertex_color='MATERIAL')
    mn, mx = bounds([body])
    print('VEHICLE', name, 'size', [round(v, 2) for v in (mx - mn)])


def shrink_images(px=1024):
    for im in bpy.data.images:
        if im.size[0] > px:
            im.scale(px, px * im.size[1] // im.size[0])
            im.pack()


# ---------------------------------------------------------------- Su-25M
if ONLY in ('', 'su25'):
    reset()
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, 'su25.glb'))
    flatten()
    junk = ('Ladder', 'LadderExtract', 'Step')
    gear_parts = ('Gear', 'Wheel', 'Strut', 'Fender', 'NoseStrut', 'Lever')
    body, gear, noz = [], [], {}
    for o in meshes():
        base = o.name.split('_')[0]
        if base in ('EngineNozzleLeft', 'EngineNozzleRight'):
            noz[base] = o
        elif base in junk:
            bpy.data.objects.remove(o)
        elif base.startswith(gear_parts):
            gear.append(o)
        else:
            body.append(o)
    glass = [o for o in body if any(m and m.name == 'Glass' for m in o.data.materials)]
    body = join(body, 'Body')
    gear = join(gear, 'GearMesh')
    decimate(body, 0.6)
    smooth(body, 45)
    # nose -X in the file: turn it to +Y
    transform(Matrix.Rotation(-math.pi / 2, 4, 'Z'))
    shrink_images(2048)
    finish('su25', body, gear, 15.36, nozzles=(noz['EngineNozzleLeft'], noz['EngineNozzleRight']))

# ---------------------------------------------------------------- Su-24M
if ONLY in ('', 'su24'):
    reset()
    fbx = glob.glob(os.path.join(SRC, 'su24/source/*.fbx'))[0]
    bpy.ops.import_scene.fbx(filepath=fbx)
    flatten()
    # the FBX points at the author's folders: relink the colour maps by file name
    tex = os.path.join(SRC, 'su24/textures')
    for im in bpy.data.images:
        base = os.path.splitext(os.path.basename(im.filepath))[0]
        p = os.path.join(tex, base + '.jpeg')
        if os.path.exists(p):
            im.filepath = p; im.reload()
    for m in bpy.data.materials:
        if m.use_nodes and 'Principled BSDF' in m.node_tree.nodes:
            b = m.node_tree.nodes['Principled BSDF']
            b.inputs['Roughness'].default_value = 0.5 if m.name.startswith('planer') else 0.6
            b.inputs['Metallic'].default_value = 0.25
    body, gear, ss = [], [], []
    for o in meshes():
        mats = [m.name for m in o.data.materials if m]
        if any(n.startswith('Chassis') for n in mats):
            gear.append(o)
        elif any(n.startswith('ss_misile') for n in mats):
            ss.append(o)
        else:
            body.append(o)
    body = join(body, 'Body')
    gear = join(gear, 'GearMesh')
    ssm = join(ss, 'StoreMesh')
    decimate(gear, 0.35)
    smooth(body, 40)
    transform(Matrix.Rotation(math.pi, 4, 'Z'))
    # two Storm Shadows side by side under the belly: one node each so they disappear as they are launched
    st_l = split_faces(ssm, lambda f: f.calc_center_median().x < 0.0, 'Store_LMesh')
    ssm.name = 'Store_RMesh'
    shrink_images(1024)
    finish('su24', body, gear, 22.67, nozzles=(0.25, 1.2, -0.2), stores=(st_l, ssm))

# ---------------------------------------------------------------- Su-27
if ONLY in ('', 'su27'):
    reset()
    bpy.ops.wm.obj_import(filepath=os.path.join(SRC, 'su27.obj'), use_split_groups=True)
    flatten()
    skin = paint('su27_skin', (0.56, 0.63, 0.7), 0.5, 0.3)
    glass = paint('su27_glass', (0.08, 0.1, 0.12), 0.1, 0.6)
    body, gear = [], []
    for o in meshes():
        n = o.name.split('.')[0]
        o.data.materials.clear()
        if n == 'Meshpart10':
            o.data.materials.append(glass); body.append(o)
        elif n == 'Meshpart8':
            o.data.materials.append(skin); body.append(o)
        else:
            # struts, wheels and open gear doors hang below the fuselage
            o.data.materials.append(skin); gear.append(o)
    body = join(body, 'Body')
    gear = join(gear, 'GearMesh')
    smooth(body, 40)
    smooth(gear, 40)
    # nose -Y; centre the fuselage on X
    mn, mx = bounds([body])
    transform(Matrix.Rotation(math.pi, 4, 'Z') @ Matrix.Translation(Vector((-(mn.x + mx.x) / 2, 0, 0))))
    finish('su27', body, gear, 21.9, nozzles=(0.7, 2.2, -0.4))
