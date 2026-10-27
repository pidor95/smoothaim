"""Convert a textured OBJ (triangles, v index == vt index) into a compact JS model file with embedded textures.

Usage: python3 obj2js_tex.py config.json
Config keys:
  obj      path to the .obj
  out      output .js path
  var      global variable name
  axes     how to build game coordinates from OBJ ones, e.g. ["-z","y","x"] means x'=-z, y'=y, z'=x
           (game convention: +Z forward, +Y up)
  scale    multiplier applied after re-orienting
  center   [x,y,z] subtracted (in game coords, after scaling)
  groups   {obj_group_name: texture_key}; groups not listed are dropped
  textures {texture_key: [path, max_size]}
  parts    optional list of {"name", "groups": [...]} or {"name", "when": "python expr on x,y,z"} (unscaled game coords,
           true for every vertex of a face) plus optional "pivot" [x,y,z] (unscaled game coords; default: part bbox centre).
           Faces not claimed by any part belong to part "body".
Positions are quantized to int16 in the bounding box, UVs to uint16 in their own range.
"""
import sys, json, struct, base64, io
from PIL import Image

cfg = json.load(open(sys.argv[1]))
V, T, faces = [], [], []
g = None
for line in open(cfg['obj'], errors='ignore'):
    if line.startswith('v '):
        V.append(tuple(map(float, line.split()[1:4])))
    elif line.startswith('vt '):
        T.append(tuple(map(float, line.split()[1:3])))
    elif line.startswith('g '):
        g = line.split(None, 1)[1].strip()
    elif line.startswith('f '):
        if g not in cfg['groups']:
            continue
        idx = [int(p.split('/')[0]) - 1 for p in line.split()[1:]]
        for i in range(1, len(idx) - 1):
            faces.append((g, idx[0], idx[i], idx[i + 1]))


def axis(v, a):
    s = -1 if a[0] == '-' else 1
    return s * v['xyz'.index(a[-1])]


sc, ce = cfg['scale'], cfg['center']
G0 = lambda i: [axis(V[i], a) for a in cfg['axes']]
parts = cfg.get('parts', [])


def part_of(f):
    for pt in parts:
        if 'groups' in pt and f[0] in pt['groups']:
            return pt['name']
        if 'when' in pt and all(eval(pt['when'], {}, dict(zip('xyz', G0(i)))) for i in f[1:]):
            return pt['name']
    return 'body'


used = sorted({i for f in faces for i in f[1:]})
remap = {o: n for n, o in enumerate(used)}
P = [[axis(V[i], a) * sc - ce[k] for k, a in enumerate(cfg['axes'])] for i in used]
UV = [T[i] if i < len(T) else (0, 0) for i in used]
mn = [min(p[k] for p in P) for k in range(3)]
mx = [max(p[k] for p in P) for k in range(3)]
umn = [min(u[k] for u in UV) for k in range(2)]
umx = [max(u[k] for u in UV) for k in range(2)]
q = lambda v, a, b: int(round((v - a) / ((b - a) or 1) * 65534 - 32767))
qu = lambda v, a, b: int(round((v - a) / ((b - a) or 1) * 65535))
pos = b''.join(struct.pack('<3h', *(q(p[k], mn[k], mx[k]) for k in range(3))) for p in P)
uvb = b''.join(struct.pack('<2H', *(qu(u[k], umn[k], umx[k]) for k in range(2))) for u in UV)
order, groups, pivots = [], [], {}
fp = [(f, part_of(f)) for f in faces]
for pname in ['body'] + [pt['name'] for pt in parts]:
    for name in cfg['groups']:
        fs = [f for f, pn in fp if f[0] == name and pn == pname]
        if not fs:
            continue
        groups.append({'name': name, 'part': pname, 'tex': cfg['groups'][name], 'start': len(order), 'count': len(fs) * 3})
        for f in fs:
            order += [remap[i] for i in f[1:]]
for pt in parts:
    vs = {i for f, pn in fp if pn == pt['name'] for i in f[1:]}
    if not vs:
        continue
    if 'pivot' in pt:
        pv = pt['pivot']
    else:
        pts = [G0(i) for i in vs]
        pv = [(min(p[k] for p in pts) + max(p[k] for p in pts)) / 2 for k in range(3)]
    pivots[pt['name']] = [pv[k] * sc - ce[k] for k in range(3)]
assert len(P) < 65536
idx = struct.pack('<%dH' % len(order), *order)
tex = {}
for key, (path, size) in cfg['textures'].items():
    im = Image.open(path).convert('RGB')
    im.thumbnail((size, size))
    buf = io.BytesIO()
    im.save(buf, 'JPEG', quality=84)
    tex[key] = 'data:image/jpeg;base64,' + base64.b64encode(buf.getvalue()).decode()
b64 = lambda b: base64.b64encode(b).decode()
data = {'min': mn, 'max': mx, 'umin': umn, 'umax': umx, 'groups': groups, 'pivots': pivots, 'pos': b64(pos), 'uv': b64(uvb), 'idx': b64(idx), 'tex': tex}
open(cfg['out'], 'w').write('window.%s=%s;\n' % (cfg['var'], json.dumps(data, separators=(',', ':'))))
print(cfg['var'], 'verts', len(P), 'tris', len(order) // 3, 'bbox', [round(x, 2) for x in mn], [round(x, 2) for x in mx],
      'groups', [(x['part'], x['name'], x['count'] // 3) for x in groups], 'pivots', {k: [round(c, 2) for c in v] for k, v in pivots.items()})
