"""Infantry soldier built from separate body parts, so the game can animate and ragdoll it joint by joint.

Run: blender -b -P blender_soldier.py -- OUT_DIR
Each part has its origin at the joint it hangs from and extends along +Z (engine +Y) to the next joint;
the front of the body faces +Y (engine -Z). Parts: Torso (pelvis->neck), Pelvis, Head (from the neck),
UpperArm, LowerArm, Hand, Thigh, Shin, Foot (origin at the ankle). Colours are vertex colours
(woodland camouflage, olive vest and helmet, black boots, skin).
"""
import bpy, bmesh, sys, os, math
from mathutils import Vector, Matrix

OUT = sys.argv[sys.argv.index('--') + 1]
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)

mat = bpy.data.materials.new('soldier'); mat.use_nodes = True
nt = mat.node_tree; bsdf = nt.nodes['Principled BSDF']
vc = nt.nodes.new('ShaderNodeVertexColor'); vc.layer_name = 'Col'
nt.links.new(vc.outputs['Color'], bsdf.inputs['Base Color'])
bsdf.inputs['Roughness'].default_value = 0.85

GREEN, BROWN, BLACK, KHAKI = (.30, .33, .20), (.38, .31, .21), (.13, .13, .11), (.47, .44, .32)
OLIVE, POUCH, BOOT, SKIN, GLOVE, METAL = (.27, .29, .19), (.22, .24, .16), (.07, .07, .07), (.72, .52, .40), (.12, .12, .1), (.2, .2, .2)


def hsh(a, b, c=0.0):
    h = math.sin(a * 127.1 + b * 311.7 + c * 74.7) * 43758.5453
    return h - math.floor(h)


def camo(p):
    v = math.sin(p.x * 9 + p.z * 4) + math.sin(p.y * 11 - p.z * 7 + 1.3) * .8 + math.sin(p.z * 13 + p.x * 5) * .6 + hsh(round(p.x * 12), round(p.y * 12), round(p.z * 12)) * .5
    return BLACK if v > 1.25 else BROWN if v > .4 else GREEN if v > -.7 else KHAKI


def ring_loft(bm, rings, seg=14, cap=True):
    """rings: (z, half_width_x, half_depth_y, centre_y, squareness)"""
    rs = []
    for z, w, d, cy, sq in rings:
        e = 2.0 / (2.0 + 6.0 * sq)
        rs.append([bm.verts.new((w * math.copysign(abs(math.cos(a)) ** e, math.cos(a)), cy + d * math.copysign(abs(math.sin(a)) ** e, math.sin(a)), z))
                   for a in (2 * math.pi * k / seg for k in range(seg))])
    for r0, r1 in zip(rs, rs[1:]):
        for k in range(seg):
            bm.faces.new((r0[k], r0[(k + 1) % seg], r1[(k + 1) % seg], r1[k]))
    if cap:
        bm.faces.new(rs[0][::-1]); bm.faces.new(rs[-1])
    return [v for r in rs for v in r]


def ellipsoid(bm, c, r, top_only=False, seg=16, rings=10):
    verts = []
    m = bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    vs = m['verts']
    if top_only:
        bmesh.ops.delete(bm, geom=[v for v in vs if v.co.z < -0.05], context='VERTS')
        vs = [v for v in vs if v.is_valid]
    for v in vs:
        v.co = Vector((c[0] + v.co.x * r[0], c[1] + v.co.y * r[1], c[2] + v.co.z * r[2]))
    return vs


def box(bm, c, h):
    m = bmesh.ops.create_cube(bm, size=2.0)
    for v in m['verts']:
        v.co = Vector((c[0] + v.co.x * h[0], c[1] + v.co.y * h[1], c[2] + v.co.z * h[2]))
    return m['verts']


def limb(bm, length, r0, r1, seg=10):
    return ring_loft(bm, [(0.0, r0, r0, 0, 0), (length * 0.5, (r0 + r1) / 2 * 1.04, (r0 + r1) / 2 * 1.04, 0, 0), (length, r1, r1, 0, 0)], seg)


def part(name, build):
    """build(bm) returns a list of (verts, colour or callable) groups."""
    bm = bmesh.new()
    groups = build(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.verts.index_update()
    me = bpy.data.meshes.new(name); bm.to_mesh(me)
    col = me.color_attributes.new('Col', 'FLOAT_COLOR', 'POINT')
    index_col = {}
    for vs, c in groups:
        for v in vs:
            if v.is_valid:
                index_col[v.index] = c
    for v in me.vertices:
        c = index_col.get(v.index, GREEN)
        if callable(c):
            c = c(v.co)
        g = 0.92 + hsh(v.co.x * 50, v.co.y * 50, v.co.z * 50) * 0.12
        col.data[v.index].color = (c[0] * g, c[1] * g, c[2] * g, 1)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    return o


def torso(bm):
    body = ring_loft(bm, [(0.0, .155, .105, 0, .3), (.12, .15, .105, 0, .3), (.30, .175, .12, 0, .35), (.42, .195, .12, 0, .35), (.47, .14, .095, 0, .3), (.52, .055, .055, 0, 0)], 16)
    vest = ring_loft(bm, [(.13, .17, .13, .005, .6), (.25, .185, .145, .005, .6), (.43, .19, .14, .005, .6)], 16)
    pouches = []
    for x in (-.09, 0, .09):
        pouches += box(bm, (x, .155, .21), (.04, .025, .06))
    radio = box(bm, (.07, -.16, .32), (.05, .03, .08))
    return [(body, camo), (vest, OLIVE), (pouches, POUCH), (radio, BLACK)]


def pelvis(bm):
    hips = ring_loft(bm, [(.02, .155, .105, 0, .3), (-.06, .165, .11, 0, .3), (-.15, .13, .1, 0, .2)], 16)
    belt = ring_loft(bm, [(.0, .162, .112, 0, .3), (-.035, .165, .114, 0, .3)], 16)
    return [(hips, camo), (belt, BLACK)]


def head(bm):
    neck = limb(bm, .08, .05, .05, 10)
    face = ellipsoid(bm, (0, .01, .16), (.083, .095, .108))
    helmet = ellipsoid(bm, (0, -.005, .19), (.118, .132, .105), top_only=True, seg=18, rings=10)
    rim = ring_loft(bm, [(.18, .122, .136, -.005, 0), (.195, .12, .134, -.005, 0)], 18)
    goggles = box(bm, (0, .1, .23), (.07, .02, .018))
    return [(neck, SKIN), (face, SKIN), (helmet, OLIVE), (rim, POUCH), (goggles, BLACK)]


def upper_arm(bm):
    a = limb(bm, .29, .057, .046)
    cap = ellipsoid(bm, (0, 0, .015), (.065, .065, .06))
    patch = box(bm, (.0, 0, .08), (.062, .03, .025))
    return [(a, camo), (cap, camo), (patch, OLIVE)]


def lower_arm(bm):
    return [(limb(bm, .27, .046, .036), camo)]


def hand(bm):
    return [(box(bm, (0, .005, .045), (.028, .042, .048)), GLOVE)]


def thigh(bm):
    t = limb(bm, .44, .082, .062)
    pocket = box(bm, (.07, 0, .2), (.02, .05, .07))
    return [(t, camo), (pocket, camo)]


def shin(bm):
    s = limb(bm, .43, .06, .047)
    pad = ellipsoid(bm, (0, .045, .015), (.055, .035, .06))
    boot = ring_loft(bm, [(.30, .056, .056, 0, .2), (.43, .058, .058, 0, .2)], 10)
    return [(s, camo), (pad, BLACK), (boot, BOOT)]


def foot(bm):
    return [(box(bm, (0, .06, -.045), (.052, .13, .05)), BOOT)]


for name, fn in (('Torso', torso), ('Pelvis', pelvis), ('Head', head), ('UpperArm', upper_arm), ('LowerArm', lower_arm),
                 ('Hand', hand), ('Thigh', thigh), ('Shin', shin), ('Foot', foot)):
    part(name, fn)

bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, 'soldier.glb'), export_format='GLB', export_vertex_color='MATERIAL')
print('SOLDIER exported')
