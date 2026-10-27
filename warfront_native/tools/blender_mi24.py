"""Procedural Mi-24 (Hind) helicopter: lofted fuselage, tandem canopies, stub wings with rocket pods,
5-blade main rotor, 3-blade tail rotor, camouflage in vertex colours. Faces -Z in the engine.

Run: blender -b -P blender_mi24.py -- OUT_DIR
Named nodes: "Rotor", "TailRotor" (spinning), origin at the middle of the bounding box like the other aircraft.
"""
import bpy, bmesh, sys, os, math
from mathutils import Vector, Matrix

OUT = sys.argv[sys.argv.index('--') + 1]
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)


def mat(name, col, rough=.55, metal=.15, vcol=False):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes['Principled BSDF']
    b.inputs['Base Color'].default_value = (*col, 1); b.inputs['Roughness'].default_value = rough; b.inputs['Metallic'].default_value = metal
    if vcol:
        vc = m.node_tree.nodes.new('ShaderNodeVertexColor'); vc.layer_name = 'Col'
        m.node_tree.links.new(vc.outputs['Color'], b.inputs['Base Color'])
    return m


SKIN = mat('mi24_skin', (.4, .42, .3), vcol=True)
GLASS = mat('mi24_glass', (.08, .12, .14), .05, .9)
DARK = mat('mi24_dark', (.07, .07, .07), .6, .4)
BLADE = mat('mi24_blade', (.12, .13, .12), .7, .1)


def obj(name, bm, m):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    me.materials.append(m)
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    return o


def loft(name, sections, m, seg=20):
    """sections: (y, z_center, half_width, half_height, squareness) along the body; Blender Y is forward."""
    bm = bmesh.new(); rings = []
    for y, zc, w, h, sq in sections:
        ring = []
        for k in range(seg):
            a = 2 * math.pi * k / seg
            c, s = math.cos(a), math.sin(a)
            # superellipse: squareness 0 = ellipse, towards 1 = box-like sides
            e = 2.0 / (2.0 + 6.0 * sq)
            x = w * math.copysign(abs(c) ** e, c); z = h * math.copysign(abs(s) ** e, s)
            ring.append(bm.verts.new((x, y, zc + z)))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(seg):
            bm.faces.new((r0[k], r0[(k + 1) % seg], r1[(k + 1) % seg], r1[k]))
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj(name, bm, m)


def prim(name, kind, m, loc, scale, rot=(0, 0, 0), **kw):
    bm = bmesh.new()
    if kind == 'cyl':
        # axis along Y (Blender forward); radius2 is the +Y end
        bmesh.ops.create_cone(bm, cap_ends=True, segments=kw.get('seg', 16), radius1=1, radius2=kw.get('r2', 1), depth=2)
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(-math.pi / 2, 3, 'X'))
    elif kind == 'sph':
        bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1)
    else:
        bmesh.ops.create_cube(bm, size=2)
    M = Matrix.Translation(loc) @ Matrix.Rotation(rot[2], 4, 'Z') @ Matrix.Rotation(rot[1], 4, 'Y') @ Matrix.Rotation(rot[0], 4, 'X') @ Matrix.Diagonal((*scale, 1))
    bmesh.ops.transform(bm, matrix=M, verts=bm.verts)
    o = obj(name, bm, m)
    if kind == 'box':
        for p in o.data.polygons: p.use_smooth = False
    return o


parts = []
# fuselage: nose (+Y) to tail boom (-Y); y, z centre, half width, half height, squareness
parts.append(loft('Fuselage', [
    (8.6, .35, .05, .05, 0), (8.2, .35, .55, .6, .1), (7.0, .45, .8, .95, .2), (5.6, .7, .95, 1.15, .3),
    (4.0, .8, 1.05, 1.3, .45), (1.5, .85, 1.12, 1.4, .5), (-1.0, .85, 1.1, 1.35, .5), (-2.6, 1.0, .9, 1.05, .35),
    (-4.0, 1.25, .5, .6, .2), (-7.5, 1.45, .32, .38, .1), (-9.6, 1.6, .25, .3, .1), (-10.4, 2.0, .2, .2, 0)], SKIN))
# tandem canopies: gunner in the nose, pilot raised behind
parts.append(prim('CanopyGunner', 'sph', GLASS, Vector((0, 6.75, 1.05)), (.62, 1.1, .62)))
parts.append(prim('CanopyPilot', 'sph', GLASS, Vector((0, 5.0, 1.55)), (.66, 1.05, .7)))
# engine nacelles and rotor mast fairing on the roof
for s in (-1, 1):
    parts.append(prim('Engine', 'cyl', SKIN, Vector((s * .62, 1.6, 2.3)), (.48, 2.3, .48), r2=.8))
    parts.append(prim('Intake', 'cyl', DARK, Vector((s * .62, 3.95, 2.3)), (.42, .1, .42)))
    parts.append(prim('Exhaust', 'cyl', DARK, Vector((s * .95, -.9, 2.25)), (.36, .5, .36), (0, 0, s * .5)))
parts.append(loft('Hump', [(3.6, 2.2, .1, .1, 0), (3.0, 2.3, .55, .45, .3), (-.5, 2.45, .65, .55, .4), (-2.4, 2.2, .45, .35, .3), (-3.4, 1.9, .1, .1, 0)], SKIN, 14))
parts.append(prim('Mast', 'cyl', DARK, Vector((0, .4, 3.05)), (.22, .3, .22), (math.pi / 2, 0, 0)))
# stub wings with anhedral, pylons with rocket pods and missile rails
for s in (-1, 1):
    w = prim('Wing', 'box', SKIN, Vector((s * 2.45, .2, .55)), (1.5, .75, .07), (0, -s * .12, 0))
    parts.append(w)
    parts.append(prim('Endplate', 'box', SKIN, Vector((s * 3.95, .2, .2)), (.08, .55, .45)))
    for k, xo in enumerate((1.5, 2.9)):
        parts.append(prim('Pod', 'cyl', DARK, Vector((s * xo, .45, .05 - .1 * k)), (.28, 1.0, .28), r2=.24))
    parts.append(prim('Rail', 'cyl', DARK, Vector((s * 3.95, .4, -.35)), (.09, .9, .09)))
# tail: fin and horizontal stabiliser
parts.append(prim('Fin', 'box', SKIN, Vector((0, -9.7, 2.8)), (.07, .7, 1.2), (-.35, 0, 0)))
parts.append(prim('Stab', 'box', SKIN, Vector((0, -8.4, 1.55)), (1.3, .35, .05)))
# landing gear
for p in (Vector((-1.1, -1.2, -.85)), Vector((1.1, -1.2, -.85)), Vector((0, 6.8, -.4))):
    parts.append(prim('Wheel', 'cyl', DARK, p, (.35, .14, .35), (0, 0, math.pi / 2)))
    parts.append(prim('Strut', 'cyl', DARK, p + Vector((0, 0, .45)), (.07, .4, .07), (math.pi / 2, 0, 0)))
# chin gun turret
parts.append(prim('ChinGun', 'sph', DARK, Vector((0, 7.4, -.15)), (.35, .35, .3)))
parts.append(prim('Barrel', 'cyl', DARK, Vector((0, 8.1, -.2)), (.05, .6, .05)))

# camouflage: two-tone green/sand pattern with a light-blue belly, written per vertex
GREEN, SAND, BROWN, BELLY = (.33, .37, .23), (.55, .5, .36), (.36, .29, .2), (.52, .6, .64)


def hsh(a, b):
    h = math.sin(a * 127.1 + b * 311.7) * 43758.5453
    return h - math.floor(h)


for o in parts:
    if o.data.materials[0] != SKIN: continue
    col = o.data.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    for v in o.data.vertices:
        p = o.matrix_world @ v.co
        n = v.normal
        val = math.sin(p.y * .45 + p.z * .7) + math.sin(p.y * .9 - p.x * .6 + 1.7) * .6 + hsh(math.floor(p.y / 1.2), math.floor(p.z / 1.2)) * .5
        c = GREEN if val > .3 else SAND if val > -.6 else BROWN
        if n.z < -.45 and p.z < .6: c = BELLY
        g = .94 + hsh(math.floor(p.x * 3), math.floor(p.y * 3)) * .1
        col.data[v.index].color = (c[0] * g, c[1] * g, c[2] * g, 1)

# rotors
hub = Vector((0, .4, 3.35))
rotor = bpy.data.objects.new('Rotor', None); bpy.context.scene.collection.objects.link(rotor); rotor.location = hub
blades = []
for k in range(5):
    a = 2 * math.pi * k / 5
    b = prim('Blade', 'box', BLADE, Vector((0, 0, 0)), (4.3, .27, .03))
    b.data.transform(Matrix.Rotation(a, 4, 'Z') @ Matrix.Translation((4.4, 0, 0)))
    blades.append(b)
blades.append(prim('Hub', 'cyl', DARK, Vector((0, 0, 0)), (.35, .15, .35), (math.pi / 2, 0, 0)))
tail_hub = Vector((-.32, -10.1, 2.4))
trotor = bpy.data.objects.new('TailRotor', None); bpy.context.scene.collection.objects.link(trotor); trotor.location = tail_hub
tblades = []
for k in range(3):
    a = 2 * math.pi * k / 3
    b = prim('TBlade', 'box', BLADE, Vector((0, 0, 0)), (.03, .12, 1.0))
    b.data.transform(Matrix.Rotation(a, 4, 'X') @ Matrix.Translation((0, 0, 1.0)))
    tblades.append(b)


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join(); objs[0].name = name; return objs[0]


body = join(parts, 'Body')
rm = join(blades, 'RotorMesh'); rm.parent = rotor
tm = join(tblades, 'TailRotorMesh'); tm.parent = trotor

# Blender +Y forward -> engine -Z after the glTF Y-up conversion; centre the bounding box on the origin
bpy.context.view_layer.update()
pts = [o.matrix_world @ v.co for o in (body, rm, tm) for v in o.data.vertices]
mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
c = (mn + mx) / 2
body.data.transform(Matrix.Translation(-c))
rotor.location -= c; trotor.location -= c
print('VEHICLE mi24 size', [round(v, 2) for v in (mx - mn)])
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, 'mi24.glb'), export_format='GLB')
