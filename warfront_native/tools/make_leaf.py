"""Draw a single broad leaf with alpha for the tree generator (python3 make_leaf.py out.png)."""
import sys, math, random
from PIL import Image, ImageDraw, ImageFilter
S = 256
im = Image.new('RGBA', (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
pts = []
for i in range(64):
    t = i / 63 * math.pi
    r = math.sin(t) ** 0.8 * (1 + 0.04 * math.sin(t * 18))     # slightly serrated ovate blade
    pts.append((S / 2 + r * S * 0.36, S * 0.06 + (1 - math.cos(t)) / 2 * S * 0.86))
pts += [(S - x, y) for x, y in reversed(pts)]
d.polygon(pts, fill=(70, 104, 42, 255))
# shading and veins
for y in range(S):
    for x in range(S):
        r, g, b, a = im.getpixel((x, y))
        if a:
            k = 0.82 + 0.3 * (1 - y / S) + random.uniform(-.05, .05) - 0.12 * abs(x - S / 2) / (S / 2)
            im.putpixel((x, y), (int(r * k), int(g * k), int(b * k), a))
d.line([(S / 2, S * 0.08), (S / 2, S * 0.93)], fill=(96, 130, 60, 255), width=3)
for k in range(1, 7):
    y = S * (0.15 + k * 0.11)
    d.line([(S / 2, y), (S / 2 + S * 0.22, y - S * 0.08)], fill=(88, 120, 55, 255), width=2)
    d.line([(S / 2, y), (S / 2 - S * 0.22, y - S * 0.08)], fill=(88, 120, 55, 255), width=2)
d.line([(S / 2, S * 0.93), (S / 2, S)], fill=(80, 70, 40, 255), width=4)
im.filter(ImageFilter.SMOOTH).save(sys.argv[1])
