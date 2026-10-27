"""Build the real buildings of the map from OpenStreetMap footprints and export them as glTF.

Run: blender -b -P blender_buildings.py -- MAP_DIR TEX_DIR OUT.glb
MAP_DIR has vectors.json and height.bin from process_map.py. Game axes: X east, Y up, Z south.
Blender works Z-up, and the glTF exporter maps Blender (x, y, z) to glTF (x, z, -y), so a game point (x, h, z)
is created in Blender at (x, -z, h).
Houses get walls with windows and a pitched roof; large or irregular footprints get flat roofs.
Buildings are merged into 8x8 chunks so the engine can cull them.
"""
import bpy, bmesh, sys, os, json, math, random
import numpy as np

argv = sys.argv[sys.argv.index('--') + 1:]
MAP, TEX, OUT = argv
V = json.load(open(os.path.join(MAP, 'vectors.json')))
N = 513
HM = np.fromfile(os.path.join(MAP, 'height.bin'), '<f4').reshape(N, N)
SIZE = 10400.0
HALF = SIZE / 2
random.seed(42)


def ground(x, z):
    fx = (x + HALF) / SIZE * (N - 1); fz = (z + HALF) / SIZE * (N - 1)
    fx = min(max(fx, 0), N - 1.001); fz = min(max(fz, 0), N - 1.001)
    i, j = int(fx), int(fz); u, v = fx - i, fz - j
    return float(HM[j, i] * (1 - u) * (1 - v) + HM[j, i + 1] * u * (1 - v) + HM[j + 1, i] * (1 - u) * v + HM[j + 1, i + 1] * u * v)


bpy.ops.wm.read_factory_settings(use_empty=True)
MATS = {}


def mat(name):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name); m.use_nodes = True
    bsdf = m.node_tree.nodes['Principled BSDF']
    tex = m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image = bpy.data.images.load(os.path.join(TEX, name + '.jpg'))
    m.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    bsdf.inputs['Roughness'].default_value = 0.55 if 'metal' in name else 0.9
    bsdf.inputs['Metallic'].default_value = 0.3 if 'metal' in name else 0.0
    MATS[name] = m
    return m


WALLS_HOUSE = ['wall_plaster', 'wall_plaster2', 'wall_brick', 'wall_brick_white', 'wall_wood']
ROOFS_HOUSE = ['roof_metal_green', 'roof_metal_red', 'roof_metal_grey', 'roof_slate', 'roof_slate', 'roof_tiles']


def clean(p):
    pts = [tuple(q) for q in p]
    if len(pts) > 2 and pts[0] == pts[-1]:
        pts = pts[:-1]
    out = []
    for q in pts:
        if not out or math.dist(q, out[-1]) > 0.3:
            out.append(q)
    # drop nearly collinear points
    k = 0
    while len(out) > 3 and k < len(out):
        a, b, c = out[k - 1], out[k], out[(k + 1) % len(out)]
        cr = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if abs(cr) < 0.05 * math.dist(a, b) * math.dist(b, c) + 1e-6:
            out.pop(k)
        else:
            k += 1
    return out


def area(p):
    return sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p))) / 2


def rect_axes(p):
    # long axis of a 4-corner footprint
    e = [(p[(i + 1) % 4][0] - p[i][0], p[(i + 1) % 4][1] - p[i][1]) for i in range(4)]
    L = [math.hypot(*v) for v in e]
    return (0 if L[0] + L[2] >= L[1] + L[3] else 1), L


CH = 8
chunks = {}


def chunk(x, z):
    key = (min(CH - 1, int((x + HALF) / SIZE * CH)), min(CH - 1, int((z + HALF) / SIZE * CH)))
    if key not in chunks:
        me = bpy.data.meshes.new('bld_%d_%d' % key)
        bm = bmesh.new()
        chunks[key] = (me, bm, [], bm.loops.layers.uv.new('UVMap'))
    return chunks[key]


def matidx(c, name):
    names = c[2]
    if name not in names:
        names.append(name)
    return names.index(name)


CEN = [0, 0, 0]


def orient(f):
    # walls face away from the building centre, roofs face up
    f.normal_update()
    fc = f.calc_center_median()
    out = (fc.x - CEN[0], fc.y - CEN[1], (fc.z - CEN[2]) * 0.2)
    if f.normal.x * out[0] + f.normal.y * out[1] + f.normal.z * out[2] < 0:
        f.normal_flip()


def quad(c, pts, uvs, mname):
    me, bm, names, uvl = c
    vs = [bm.verts.new((x, -z, y)) for x, y, z in pts]
    f = bm.faces.new(vs)
    f.material_index = matidx(c, mname)
    for loop, uv in zip(f.loops, uvs):
        loop[uvl].uv = uv
    orient(f)
    return f


count = 0
for b in V['buildings']:
    p = clean(b['p'])
    if len(p) < 3:
        continue
    a = area(p)
    if a < 0:
        p = p[::-1]; a = -a
    if a < 10:
        continue
    cx = sum(q[0] for q in p) / len(p); cz = sum(q[1] for q in p) / len(p)
    gs = [ground(x, z) for x, z in p]
    base = min(gs) - 0.6
    top0 = max(gs)
    kind = b.get('k', 'yes')
    if kind in ('apartments',) or (b.get('h') and b['h'] > 8):
        H = b.get('h') or 15.0; wall = 'wall_panel'; roof = 'roof_flat'; pitched = False
    elif kind in ('industrial', 'warehouse', 'transportation', 'supermarket', 'retail', 'roof') or a > 450:
        H = b.get('h') or random.uniform(5.5, 8); wall = 'wall_industrial'; roof = random.choice(['roof_flat', 'roof_metal_grey']); pitched = False
    else:
        storeys = 2 if a > 160 and random.random() < .5 else 1
        H = b.get('h') or storeys * 3.0 - 0.2; wall = random.choice(WALLS_HOUSE); roof = random.choice(ROOFS_HOUSE); pitched = len(p) == 4
    c = chunk(cx, cz)
    top = top0 + H
    CEN[:] = [cx, -cz, base]
    # walls
    for i in range(len(p)):
        x0, z0 = p[i]; x1, z1 = p[(i + 1) % len(p)]
        L = math.dist(p[i], p[(i + 1) % len(p)])
        u1 = max(1, round(L / 4)) if wall != 'wall_industrial' else L / 4
        v0 = (base - top0) / 3; v1 = H / 3
        quad(c, [(x0, base, z0), (x1, base, z1), (x1, top, z1), (x0, top, z0)], [(0, v0), (u1, v0), (u1, v1), (0, v1)], wall)
    if pitched:
        ax, L = rect_axes(p)
        # ridge along the long sides 0-1 / 2-3 (ax 0) or 1-2 / 3-0 (ax 1)
        q = p[ax:] + p[:ax]
        short = L[(ax + 1) % 4]
        rh = min(0.55 * short, 4.5)
        o = 0.45  # eaves overhang
        m0 = ((q[3][0] + q[0][0]) / 2, (q[3][1] + q[0][1]) / 2); m1 = ((q[1][0] + q[2][0]) / 2, (q[1][1] + q[2][1]) / 2)
        def ext(pt, ref, d):
            vx, vz = pt[0] - ref[0], pt[1] - ref[1]; n = math.hypot(vx, vz) or 1
            return (pt[0] + vx / n * d, pt[1] + vz / n * d)
        Q = [ext(q[0], (cx, cz), o), ext(q[1], (cx, cz), o), ext(q[2], (cx, cz), o), ext(q[3], (cx, cz), o)]
        rd = top + rh
        Lr = math.dist(Q[0], Q[1]) / 4; Wr = math.hypot(math.dist(Q[1], Q[2]) / 2, rh) / 4
        quad(c, [(Q[0][0], top - .2, Q[0][1]), (Q[1][0], top - .2, Q[1][1]), (m1[0], rd, m1[1]), (m0[0], rd, m0[1])], [(0, 0), (Lr, 0), (Lr, Wr), (0, Wr)], roof)
        quad(c, [(Q[2][0], top - .2, Q[2][1]), (Q[3][0], top - .2, Q[3][1]), (m0[0], rd, m0[1]), (m1[0], rd, m1[1])], [(0, 0), (Lr, 0), (Lr, Wr), (0, Wr)], roof)
        # gable triangles in the wall material
        for g0, g1, mm in ((q[1], q[2], m1), (q[3], q[0], m0)):
            me, bm, names, uvl = c
            vs = [bm.verts.new((g0[0], -g0[1], top)), bm.verts.new((g1[0], -g1[1], top)), bm.verts.new((mm[0], -mm[1], rd))]
            f = bm.faces.new(vs); f.material_index = matidx(c, wall)
            for loop, uv in zip(f.loops, [(0, H / 3), (1, H / 3), (.5, (H + rh) / 3)]):
                loop[uvl].uv = uv
            orient(f)
    else:
        me, bm, names, uvl = c
        vs = [bm.verts.new((x, -z, top)) for x, z in p]
        try:
            f = bm.faces.new(vs)
        except ValueError:
            continue
        f.material_index = matidx(c, roof)
        f.normal_update()
        if f.normal.z < 0: f.normal_flip()
        for loop in f.loops:
            co = loop.vert.co; loop[uvl].uv = (co.x / 4, co.y / 4)
        if len(p) > 4:
            bmesh.ops.triangulate(bm, faces=[f])
    count += 1

for key, (me, bm, names, uvl) in chunks.items():
    bm.to_mesh(me); bm.free()
    for n in names:
        me.materials.append(mat(n))
    ob = bpy.data.objects.new(me.name, me)
    bpy.context.scene.collection.objects.link(ob)
bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_image_format='JPEG', export_jpeg_quality=85, export_apply=True)
print('BUILDINGS', count, 'chunks', len(chunks))
