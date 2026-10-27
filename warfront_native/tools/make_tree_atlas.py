"""Stack the per-species tree renders (from blender_trees.py) into one atlas, one row per species, and bleed
the colours into transparent pixels so mipmaps don't get dark fringes.

Run: python3 make_tree_atlas.py RENDER_DIR OUT_DIR [view_px]
"""
import sys, os, json
import numpy as np
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
V = int(sys.argv[3]) if len(sys.argv) > 3 else 1024
ORDER = ['birch', 'aspen', 'maple', 'oak', 'poplar']
rows, meta = [], []
for n in ORDER:
    im = Image.open(os.path.join(src, n + '.png')).convert('RGBA').resize((2 * V, V), Image.LANCZOS)
    rows.append(np.asarray(im).astype(np.float32))
    m = json.load(open(os.path.join(src, n + '.json'))); m['name'] = n; meta.append(m)
a = np.concatenate(rows, 0)
rgb, solid = a[..., :3], a[..., 3] > 8
filled, col = solid.copy(), rgb * solid[..., None]
for _ in range(96):
    if filled.all():
        break
    acc = np.zeros_like(col); cnt = np.zeros(solid.shape, np.float32)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)):
        f = np.roll(filled, (dy, dx), (0, 1)); acc += np.roll(col, (dy, dx), (0, 1)) * f[..., None]; cnt += f
    new = (~filled) & (cnt > 0)
    col[new] = acc[new] / cnt[new][:, None]; filled |= new
col[~filled] = rgb[solid].mean(0)
a[..., :3] = np.where(solid[..., None], rgb, col)
Image.fromarray(a.clip(0, 255).astype(np.uint8)).save(os.path.join(out, 'trees_atlas.png'))
json.dump(meta, open(os.path.join(out, 'trees.json'), 'w'))
print('atlas', a.shape)
