"""Bake a glTF 2.0 model (embedded buffers/images, as exported by Blockbench) into the same compact JS format as obj2js_tex.py.

Usage: python3 gltf2js.py in.gltf out.js VARNAME scale axes skip_materials
  axes e.g. "x,y,z" or "-x,y,-z" (game: +Z forward, +Y up); skip_materials e.g. "5" (comma separated, may be empty)
Node transforms are baked into the vertices; one draw group per material; textures are kept as embedded PNG data URIs.
"""
import sys, json, struct, base64, math

src, dst, var, scale, axes = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), sys.argv[5].split(',')
skip = {int(x) for x in sys.argv[6].split(',') if x} if len(sys.argv) > 6 else set()
G = json.load(open(src))
buf = base64.b64decode(G['buffers'][0]['uri'].split(',', 1)[1])
CT = {5126: ('f', 4), 5123: ('H', 2), 5125: ('I', 4), 5121: ('B', 1)}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4}


def acc(i):
    a = G['accessors'][i]
    bv = G['bufferViews'][a['bufferView']]
    f, sz = CT[a['componentType']]
    n = NC[a['type']]
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', sz * n)
    return [struct.unpack_from('<%d%s' % (n, f), buf, off + k * stride) for k in range(a['count'])]


def mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def trs(n):
    if 'matrix' in n:
        m = n['matrix']
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    tx, ty, tz = n.get('translation', [0, 0, 0])
    qx, qy, qz, qw = n.get('rotation', [0, 0, 0, 1])
    sx, sy, sz = n.get('scale', [1, 1, 1])
    R = [[1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw)],
         [2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw)],
         [2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)]]
    return [[R[0][0] * sx, R[0][1] * sy, R[0][2] * sz, tx], [R[1][0] * sx, R[1][1] * sy, R[1][2] * sz, ty],
            [R[2][0] * sx, R[2][1] * sy, R[2][2] * sz, tz], [0, 0, 0, 1]]


tris = {}  # material -> list of (pos, uv) triangles
P, UV = [], []


def walk(ni, M):
    n = G['nodes'][ni]
    W = mul(M, trs(n))
    if 'mesh' in n:
        for pr in G['meshes'][n['mesh']]['primitives']:
            mi = pr.get('material', 0)
            if mi in skip:
                continue
            pos, uv, ix = acc(pr['attributes']['POSITION']), acc(pr['attributes']['TEXCOORD_0']), [i[0] for i in acc(pr['indices'])]
            base = len(P)
            for p, t in zip(pos, uv):
                x = W[0][0] * p[0] + W[0][1] * p[1] + W[0][2] * p[2] + W[0][3]
                y = W[1][0] * p[0] + W[1][1] * p[1] + W[1][2] * p[2] + W[1][3]
                z = W[2][0] * p[0] + W[2][1] * p[1] + W[2][2] * p[2] + W[2][3]
                v = {'x': x, 'y': y, 'z': z}
                P.append([(-1 if a[0] == '-' else 1) * v[a[-1]] * scale for a in axes])
                UV.append(t)
            tris.setdefault(mi, []).extend(base + i for i in ix)
    for c in n.get('children', []):
        walk(c, W)


I4 = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
for r in G['scenes'][G.get('scene', 0)]['nodes']:
    walk(r, I4)
mn = [min(p[k] for p in P) for k in range(3)]
mx = [max(p[k] for p in P) for k in range(3)]
cen = [(mn[k] + mx[k]) / 2 for k in range(3)]
P = [[p[k] - cen[k] for k in range(3)] for p in P]
mn = [mn[k] - cen[k] for k in range(3)]
mx = [mx[k] - cen[k] for k in range(3)]
umn = [min(u[k] for u in UV) for k in range(2)]
umx = [max(u[k] for u in UV) for k in range(2)]
q = lambda v, a, b: int(round((v - a) / ((b - a) or 1) * 65534 - 32767))
qu = lambda v, a, b: int(round((v - a) / ((b - a) or 1) * 65535))
assert len(P) < 65536
pos = b''.join(struct.pack('<3h', *(q(p[k], mn[k], mx[k]) for k in range(3))) for p in P)
uvb = b''.join(struct.pack('<2H', *(qu(u[k], umn[k], umx[k]) for k in range(2))) for u in UV)
order, groups = [], []
for mi in sorted(tris):
    groups.append({'name': 'mat%d' % mi, 'tex': 't%d' % mi, 'start': len(order), 'count': len(tris[mi])})
    order += tris[mi]
tex = {}
for mi in tris:
    img = G['textures'][G['materials'][mi]['pbrMetallicRoughness']['baseColorTexture']['index']]['source']
    tex['t%d' % mi] = G['images'][img]['uri']
b64 = lambda b: base64.b64encode(b).decode()
data = {'min': mn, 'max': mx, 'umin': umn, 'umax': umx, 'groups': groups, 'pos': b64(pos), 'uv': b64(uvb),
        'idx': b64(struct.pack('<%dH' % len(order), *order)), 'tex': tex, 'pixel': True, 'flipY': False}
open(dst, 'w').write('window.%s=%s;\n' % (var, json.dumps(data, separators=(',', ':'))))
print(var, 'verts', len(P), 'tris', len(order) // 3, 'size', [round(mx[k] - mn[k], 2) for k in range(3)], 'groups', [(g['name'], g['count'] // 3) for g in groups])
