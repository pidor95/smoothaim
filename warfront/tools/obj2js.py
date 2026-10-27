"""Convert an OBJ (triangles, v/vt/vn with equal indices) into a compact JS model file.

Usage: python3 obj2js.py in.obj out.js VARNAME [skip_group ...]
Positions are quantized to int16 inside the bounding box, normals to int8.
The model is re-oriented so the nose points to +Z (game convention): x' = z, y' = y, z' = -x.
"""
import sys, struct, base64, json

src, dst, var = sys.argv[1:4]
skip = set(sys.argv[4:])
V, N, groups, faces = [], [], [], []
g = None
for line in open(src):
    if line.startswith('v '):
        x, y, z = map(float, line.split()[1:4]); V.append((z, y, -x))
    elif line.startswith('vn '):
        x, y, z = map(float, line.split()[1:4]); N.append((z, y, -x))
    elif line.startswith('g '):
        g = line.split()[1]
    elif line.startswith('f '):
        if g in skip: continue
        idx = [int(p.split('/')[0]) - 1 for p in line.split()[1:]]
        for i in range(1, len(idx) - 1):
            faces.append((g, idx[0], idx[i], idx[i + 1]))

used = sorted({i for f in faces for i in f[1:]})
remap = {o: n for n, o in enumerate(used)}
P = [V[i] for i in used]; NN = [N[i] for i in used]
mn = [min(p[k] for p in P) for k in range(3)]; mx = [max(p[k] for p in P) for k in range(3)]
q = lambda v, k: int(round((v - mn[k]) / ((mx[k] - mn[k]) or 1) * 65534 - 32767))
pos = b''.join(struct.pack('<3h', *(q(p[k], k) for k in range(3))) for p in P)
nrm = b''.join(struct.pack('<3b', *(max(-127, min(127, int(round(c * 127)))) for c in n)) for n in NN)
order = []
for f in faces:
    if not groups or groups[-1]['name'] != f[0]:
        groups.append({'name': f[0], 'start': len(order), 'count': 0})
    order += [remap[i] for i in f[1:]]; groups[-1]['count'] += 3
assert len(P) < 65536
idx = struct.pack('<%dH' % len(order), *order)
b64 = lambda b: base64.b64encode(b).decode()
data = {'min': mn, 'max': mx, 'groups': groups, 'pos': b64(pos), 'nrm': b64(nrm), 'idx': b64(idx)}
open(dst, 'w').write('window.%s=%s;\n' % (var, json.dumps(data, separators=(',', ':'))))
print('verts', len(P), 'tris', len(order) // 3, 'bytes', len(pos) + len(nrm) + len(idx), 'groups', [(x['name'], x['count'] // 3) for x in groups])
