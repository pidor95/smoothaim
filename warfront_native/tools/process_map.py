"""Turn downloaded real-world data into game map data (run from the folder holding dem/, sat/, osm.json, area.json).

Inputs:  dem/13_x_y.png   AWS Terrain Tiles (terrarium encoding)
         sat/15_x_y.jpg   Sentinel-2 cloudless 2020 by EOX (CC BY-NC-SA 4.0)
         osm.json         OpenStreetMap extract from Overpass (ODbL)
Outputs (in OUT): height.bin (float32, N*N, row 0 = north), satellite.jpg, splat.png, vectors.json, map.json

Game axes: X = east, Y = up, Z = south (so -Z is north). Origin = map centre.
"""
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else 'out'
os.makedirs(OUT, exist_ok=True)
A = json.load(open('area.json'))
LAT, LON, HALF = A['lat'], A['lon'], A['half']
MLAT = 111132.92 - 559.82 * math.cos(2 * math.radians(LAT))
MLON = 111412.84 * math.cos(math.radians(LAT))
N = 513            # heightmap vertices per side
SAT = 4096         # satellite texture size
SPLAT = 2048       # mask texture size


def to_latlon(x, z):
    return LAT - z / MLAT, LON + x / MLON


def to_local(lat, lon):
    return (lon - LON) * MLON, -(lat - LAT) * MLAT


def merc_px(lat, lon, z):
    n = 2 ** z * 256
    lat = np.radians(lat)
    return (lon + 180) / 360 * n, (1 - np.log(np.tan(lat) + 1 / np.cos(lat)) / math.pi) / 2 * n


def mosaic(folder, z, ext):
    tiles = {}
    for f in os.listdir(folder):
        zz, x, y = f.split('.')[0].split('_')
        if int(zz) == z:
            tiles[(int(x), int(y))] = os.path.join(folder, f)
    xs = sorted({k[0] for k in tiles}); ys = sorted({k[1] for k in tiles})
    W, H = len(xs) * 256, len(ys) * 256
    img = np.zeros((H, W, 3), np.float32)
    for (x, y), p in tiles.items():
        im = np.asarray(Image.open(p).convert('RGB'), np.float32)
        if im.shape[0] != 256:
            im = np.asarray(Image.open(p).convert('RGB').resize((256, 256)), np.float32)
        img[(y - ys[0]) * 256:(y - ys[0] + 1) * 256, (x - xs[0]) * 256:(x - xs[0] + 1) * 256] = im
    return img, xs[0] * 256, ys[0] * 256


def bilinear(img, px, py):
    h, w = img.shape[:2]
    px = np.clip(px, 0, w - 1.001); py = np.clip(py, 0, h - 1.001)
    x0 = px.astype(int); y0 = py.astype(int); fx = (px - x0)[..., None]; fy = (py - y0)[..., None]
    return (img[y0, x0] * (1 - fx) * (1 - fy) + img[y0, x0 + 1] * fx * (1 - fy) + img[y0 + 1, x0] * (1 - fx) * fy + img[y0 + 1, x0 + 1] * fx * fy)


def grid(n):
    c = (np.arange(n) + (0.5 if n != N else 0)) / (n if n != N else n - 1) * 2 * HALF - HALF
    X, Z = np.meshgrid(c, c)
    return X, Z


# ---- heightmap
dem, ox, oy = mosaic('dem', 13, 'png')
X, Z = grid(N)
la, lo = to_latlon(X, Z)
px, py = merc_px(la, lo, 13)
rgb = bilinear(dem, px - ox, py - oy)
H = rgb[..., 0] * 256 + rgb[..., 1] + rgb[..., 2] / 256 - 32768
Hp = np.pad(H, 1, mode='edge')  # 3x3 smoothing softens the 1 m stair steps of the source data
H = sum(Hp[1 + dy:1 + dy + N, 1 + dx:1 + dx + N] * w for dy, dx, w in
        [(0, 0, .25), (-1, 0, .125), (1, 0, .125), (0, -1, .125), (0, 1, .125), (-1, -1, .0625), (-1, 1, .0625), (1, -1, .0625), (1, 1, .0625)]).astype(np.float32)
base = float(np.percentile(H, 2))
H = H - base                      # lowest ground at about 0 m
H.astype('<f4').tofile(os.path.join(OUT, 'height.bin'))
print('height range', H.min(), H.max(), 'original base', base)

# ---- satellite texture
sat, ox, oy = mosaic('sat', 15, 'jpg')
X, Z = grid(SAT)
la, lo = to_latlon(X, Z)
px, py = merc_px(la, lo, 15)
S = bilinear(sat, px - ox, py - oy)
# gentle grade: Sentinel mosaics are hazy, give them some contrast and lift the greens
S = np.clip(255 * (S / 255) ** 0.88 * 1.1 - 8, 0, 255)
Image.fromarray(S.astype(np.uint8)).save(os.path.join(OUT, 'satellite.jpg'), quality=88)

# ---- OSM vectors
osm = json.load(open('osm.json'))['elements']
nodes = {e['id']: (e['lat'], e['lon']) for e in osm if e['type'] == 'node'}
ways = {e['id']: e for e in osm if e['type'] == 'way'}


def pts(way):
    out = []
    for nid in way.get('nodes', []):
        if nid in nodes:
            x, z = to_local(*nodes[nid])
            out.append([round(x, 1), round(z, 1)])
    return out


V = {'buildings': [], 'forests': [], 'water': [], 'roads': [], 'rail': [], 'rivers': [], 'residential': []}
ROADW = {'motorway': 14, 'trunk': 12, 'primary': 10, 'secondary': 9, 'tertiary': 7, 'unclassified': 6, 'residential': 6,
         'service': 4, 'track': 4, 'road': 5, 'living_street': 5, 'pedestrian': 4}
for w in ways.values():
    t = w.get('tags', {})
    p = pts(w)
    if len(p) < 2:
        continue
    if 'building' in t:
        lv = t.get('building:levels')
        h = float(t['height']) if 'height' in t and t['height'].replace('.', '').isdigit() else (float(lv) * 3 + 1 if lv and lv.isdigit() else None)
        V['buildings'].append({'p': p, 'h': h, 'k': t['building']})
    elif t.get('landuse') == 'forest' or t.get('natural') in ('wood', 'scrub'):
        V['forests'].append(p)
    elif t.get('natural') == 'water' or t.get('landuse') == 'reservoir':
        V['water'].append(p)
    elif t.get('landuse') in ('residential', 'farmyard'):
        V['residential'].append(p)
    elif 'highway' in t and t['highway'] in ROADW:
        V['roads'].append({'p': p, 'w': ROADW[t['highway']], 'k': t['highway'], 'paved': t.get('surface', 'asphalt' if t['highway'] in ('primary', 'secondary', 'tertiary', 'residential', 'trunk') else 'unpaved')})
    elif t.get('railway') == 'rail':
        V['rail'].append(p)
    elif 'waterway' in t:
        V['rivers'].append({'p': p, 'k': t['waterway']})
for r in (e for e in osm if e['type'] == 'relation'):
    t = r.get('tags', {})
    for m in r.get('members', []):
        if m['type'] == 'way' and m.get('role') == 'outer' and m['ref'] in ways:
            p = pts(ways[m['ref']])
            if len(p) > 2:
                (V['forests'] if t.get('landuse') == 'forest' or t.get('natural') == 'wood' else V['water'] if t.get('natural') == 'water' else []).append(p)
json.dump(V, open(os.path.join(OUT, 'vectors.json'), 'w'), separators=(',', ':'))
print({k: len(v) for k, v in V.items()})

# ---- splat mask: R asphalt, G dirt, B forest floor, A built-up area (painted at 2x then downsampled)
SS = SPLAT * 2
k = SS / (2 * HALF)
P = lambda p: [((x + HALF) * k, (z + HALF) * k) for x, z in p]
layers = {c: Image.new('L', (SS, SS), 0) for c in 'RGBA'}
d = {c: ImageDraw.Draw(layers[c]) for c in 'RGBA'}
for p in V['forests']:
    if len(p) > 2: d['B'].polygon(P(p), fill=255)
for p in V['residential']:
    if len(p) > 2: d['A'].polygon(P(p), fill=200)
for b in V['buildings']:
    if len(b['p']) > 2: d['A'].polygon(P(b['p']), fill=255)
for r in V['roads']:
    c = 'R' if r['paved'] in ('asphalt', 'paved', 'concrete') else 'G'
    d[c].line(P(r['p']), fill=255, width=max(2, int(r['w'] * k)), joint='curve')
for p in V['rail']:
    d['G'].line(P(p), fill=200, width=max(2, int(8 * k)))
mask = Image.merge('RGBA', [layers[c].resize((SPLAT, SPLAT), Image.LANCZOS) for c in 'RGBA'])
mask.save(os.path.join(OUT, 'splat.png'))
# ---- tree placement from OSM forests plus the satellite image: narrow dark-green strips are windbreaks,
# dark-green patches on ravine slopes are groves; big flat dark-green areas are crop fields and stay empty
G = 1024
Sg = np.asarray(Image.fromarray(S.astype(np.uint8)).resize((G, G), Image.BILINEAR), np.float32)
L = Sg.mean(2); green = Sg[..., 1] - Sg[..., 0]
fmask = Image.new('L', (G, G), 0); fd = ImageDraw.Draw(fmask); kk = G / (2 * HALF)
for p in V['forests']:
    if len(p) > 2: fd.polygon([((x + HALF) * kk, (z + HALF) * kk) for x, z in p], fill=255)
for b in V['buildings']:
    if len(b['p']) > 2: fd.polygon([((x + HALF) * kk, (z + HALF) * kk) for x, z in b['p']], fill=0)
osmf = np.asarray(fmask, np.float32) / 255
thr = np.percentile(L[osmf > .5], 75) if (osmf > .5).any() else 25
dark = ((L < thr) & (green > 6)).astype(np.float32)
def box(a, r):
    c = np.pad(a, r, mode='edge').cumsum(0).cumsum(1); c = np.pad(c, ((1, 0), (1, 0)))
    n = 2 * r + 1
    return (c[n:, n:] - c[:-n, n:] - c[n:, :-n] + c[:-n, :-n]) / (n * n)
frac = box(dark, 4)
Hg = np.asarray(Image.fromarray(H).resize((G, G), Image.BILINEAR), np.float32)
gy, gx = np.gradient(Hg, 2 * HALF / G)
slope = np.hypot(gx, gy)
low = Hg - box(Hg, 12)
strip = dark * (frac < .5)
ravine = dark * ((slope > .045) | (low < -2.5))
built = np.asarray(layers['A'].resize((G, G)), np.float32) / 255
roadm = np.maximum(np.asarray(layers['R'].resize((G, G)), np.float32), np.asarray(layers['G'].resize((G, G)), np.float32)) / 255
dens = np.clip(np.maximum.reduce([osmf, strip * .9, ravine * .8]) - built * .8 - roadm, 0, 1)
rng = np.random.default_rng(7)
cell = 2 * HALF / G
trees = []
for j, i in zip(*np.nonzero(dens > .05)):
    for _ in range(rng.poisson(dens[j, i] * 0.55)):
        x = (i + rng.random()) * cell - HALF; z = (j + rng.random()) * cell - HALF
        kind = rng.choice(4, p=[.36, .36, .2, .08])
        trees.append((x, z, kind, .75 + rng.random() * .55))
np.array(trees, '<f4').tofile(os.path.join(OUT, 'trees.bin'))
print('trees', len(trees))
json.dump({'lat': LAT, 'lon': LON, 'size': 2 * HALF, 'n': N, 'base_elevation': base,
           'credits': 'Elevation: AWS Terrain Tiles (SRTM and others). Imagery: Sentinel-2 cloudless 2020 by EOX IT Services GmbH '
                      '(contains modified Copernicus Sentinel data), CC BY-NC-SA 4.0. Map data: (c) OpenStreetMap contributors, ODbL.'},
          open(os.path.join(OUT, 'map.json'), 'w'), indent=1)
print('done')
