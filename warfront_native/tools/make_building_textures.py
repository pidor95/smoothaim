"""Compose wall and roof textures for village buildings from CC0 photo textures (ambientCG).

python3 make_building_textures.py ASSETS_DIR OUT_DIR
Walls: one tile = 4 m wide x 3 m high (one storey with one window), so UVs are u = metres/4, v = metres/3.
Roofs: one tile = 4 m x 4 m.
"""
import sys, os, glob, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

A, OUT = sys.argv[1], sys.argv[2]
os.makedirs(OUT, exist_ok=True)
W, H = 512, 384
random.seed(3)


def src(asset, size, tint=None, bright=1.0):
    im = Image.open(glob.glob(os.path.join(A, asset, '*_Color.jpg'))[0]).convert('RGB').resize(size, Image.LANCZOS)
    if tint:
        arr = np.asarray(im, np.float32) * np.array(tint, np.float32) / 255
        im = Image.fromarray(np.clip(arr * bright, 0, 255).astype(np.uint8))
    elif bright != 1.0:
        im = ImageEnhance.Brightness(im).enhance(bright)
    return im


def window(im, x0, y0, w, h, frame=(235, 235, 228), shutters=None):
    d = ImageDraw.Draw(im)
    if shutters:
        sw = w // 2
        d.rectangle([x0 - sw - 4, y0, x0 - 4, y0 + h], fill=shutters)
        d.rectangle([x0 + w + 4, y0, x0 + w + sw + 4, y0 + h], fill=shutters)
    d.rectangle([x0 - 6, y0 - 6, x0 + w + 6, y0 + h + 8], fill=frame)        # frame and sill
    d.rectangle([x0 - 10, y0 + h + 4, x0 + w + 10, y0 + h + 12], fill=tuple(int(c * .8) for c in frame))
    for yy in range(h):                                                       # glass: sky reflection fading to dark interior
        t = yy / h
        c = (int(70 + 90 * (1 - t)), int(90 + 95 * (1 - t)), int(105 + 100 * (1 - t)))
        d.line([(x0, y0 + yy), (x0 + w, y0 + yy)], fill=c)
    d.rectangle([x0 + w // 2 - 3, y0, x0 + w // 2 + 3, y0 + h], fill=frame)      # mullions
    d.rectangle([x0, y0 + h // 3 - 3, x0 + w, y0 + h // 3 + 3], fill=frame)


def wall(name, base, frame, shutters=None, plinth=(95, 90, 85)):
    im = base.copy()
    d = ImageDraw.Draw(im)
    d.rectangle([0, H - 40, W, H], fill=plinth)                               # plinth at the bottom 0.3 m
    d.rectangle([0, 0, W, 10], fill=tuple(int(c * .8) for c in base.getpixel((5, 20))))  # eaves shadow line
    window(im, W // 2 - 90, 110, 180, 170, frame, shutters)
    # dirt streaks under the window and at the plinth
    arr = np.asarray(im, np.float32)
    y = np.linspace(0, 1, H)[:, None]
    arr *= (0.92 + 0.08 * (1 - y))[..., None]
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(os.path.join(OUT, name + '.jpg'), quality=88)


wall('wall_plaster', src('PaintedPlaster017', (W, H), (236, 226, 196)), (240, 240, 235), shutters=(70, 110, 140))
wall('wall_plaster2', src('Plaster001', (W, H), (214, 222, 205)), (245, 245, 240))
wall('wall_brick', src('Bricks059', (W, H)), (238, 236, 230))
wall('wall_brick_white', src('Bricks066', (W, H), (240, 236, 226), 1.15), (90, 70, 55))
wall('wall_wood', src('WoodSiding008', (W, H), None, 1.35), (228, 228, 220), shutters=(60, 100, 70))
# five-storey panel block: one storey per tile, wider window with balcony slab
pan = src('Concrete034', (W, H), (226, 222, 214))
d = ImageDraw.Draw(pan)
for x in range(0, W, 128): d.line([(x, 0), (x, H)], fill=(150, 148, 140), width=3)
d.line([(0, H - 2), (W, H - 2)], fill=(150, 148, 140), width=4)
window(pan, W // 2 - 110, 90, 220, 180, (232, 232, 226))
pan.save(os.path.join(OUT, 'wall_panel.jpg'), quality=88)
ind = src('Concrete034', (W, H), (200, 198, 190))
d = ImageDraw.Draw(ind)
for x in range(0, W, 64): d.line([(x, 0), (x, H)], fill=(160, 158, 150), width=2)
d.rectangle([60, 40, W - 60, 90], fill=(70, 85, 95))                          # ribbon window
ind.save(os.path.join(OUT, 'wall_industrial.jpg'), quality=88)


def corrugated(name, color, wave=16, slate=False):
    S = 512
    base = src('Metal032' if not slate else 'Concrete034', (S, S), color)
    arr = np.asarray(base, np.float32)
    x = np.arange(S)[None, :]
    shade = 0.82 + 0.18 * np.sin(x / wave * 2 * np.pi)
    arr *= shade[..., None]
    if slate:
        for yy in range(0, S, 128): arr[yy:yy + 3] *= 0.7                     # overlap lines of slate sheets
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).filter(ImageFilter.SMOOTH).save(os.path.join(OUT, name + '.jpg'), quality=88)


corrugated('roof_metal_green', (90, 128, 98))
corrugated('roof_metal_red', (150, 72, 58))
corrugated('roof_metal_grey', (170, 175, 178))
corrugated('roof_slate', (170, 170, 162), wave=22, slate=True)
src('RoofingTiles006', (512, 512)).save(os.path.join(OUT, 'roof_tiles.jpg'), quality=88)
src('Concrete034', (512, 512), (120, 118, 112)).save(os.path.join(OUT, 'roof_flat.jpg'), quality=88)
print('ok', sorted(os.listdir(OUT)))
