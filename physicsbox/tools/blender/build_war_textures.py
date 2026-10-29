"""Paints the textures of the war map and its effects inside Blender
(numpy noise written out through Blender images) into assets/textures/.

Run:  blender -b --python tools/blender/build_war_textures.py

  mud.png          - trench mud / churned earth (tileable)
  bark.png         - dead tree bark and logs (tileable, vertical grain)
  camo_green.png   - allied uniform (green digital-ish flecktarn)
  camo_tan.png     - enemy uniform (tan / khaki blotches)
  smoke.png        - soft smoke puff (alpha)
  fire.png         - fireball puff (alpha)
  scorch.png       - blast scorch mark decal (alpha)
"""
import os

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures")
rng = np.random.default_rng(1945)


def tile_noise(n, cells, octaves=4, persistence=0.5):
    """Tileable value noise in 0..1 (bicubic-ish via smoothstep, wraps)."""
    out = np.zeros((n, n))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        c = cells * 2 ** o
        g = rng.uniform(0, 1, (c, c))
        t = np.arange(n) / n * c
        i0 = np.floor(t).astype(int)
        f = t - i0
        f = f * f * (3 - 2 * f)
        i1 = (i0 + 1) % c
        i0 %= c
        a = g[np.ix_(i0, i0)] * (1 - f)[None, :] + g[np.ix_(i0, i1)] * f[None, :]
        b = g[np.ix_(i1, i0)] * (1 - f)[None, :] + g[np.ix_(i1, i1)] * f[None, :]
        out += amp * (a * (1 - f)[:, None] + b * f[:, None])
        total += amp
        amp *= persistence
    return out / total


def save(name, rgb, alpha=None):
    n_y, n_x = rgb.shape[:2]
    a = np.ones((n_y, n_x)) if alpha is None else alpha
    px = np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)])[::-1]  # Blender rows go bottom-up
    img = bpy.data.images.new(name, n_x, n_y, alpha=True)
    img.pixels.foreach_set(px.astype(np.float32).ravel())
    img.filepath_raw = os.path.join(OUT, name + ".png")
    img.file_format = "PNG"
    img.save()
    print("wrote", name)


def mix(a, b, t):
    return a[None, None, :] * (1 - t[..., None]) + b[None, None, :] * t[..., None]


def mud(n=512):
    base = tile_noise(n, 4, 5)
    clumps = tile_noise(n, 16, 3)
    fine = tile_noise(n, 64, 2)
    rgb = mix(np.array([0.33, 0.26, 0.19]), np.array([0.2, 0.15, 0.11]), base)
    rgb *= (0.8 + 0.4 * clumps)[..., None]
    rgb *= (0.88 + 0.24 * fine)[..., None]
    # pebbles and dry flecks
    stones = tile_noise(n, 96, 1)
    rgb = np.where((stones > 0.82)[..., None], rgb * 0.6 + 0.18, rgb)
    wet = np.clip((tile_noise(n, 6, 3) - 0.6) * 4, 0, 1)
    rgb *= (1 - 0.35 * wet)[..., None]
    save("mud", rgb)


def bark(n=256):
    y, x = np.mgrid[0:n, 0:n] / n
    streak = tile_noise(n, 8, 3)
    grain = np.sin((x * 40 + streak * 6) * np.pi * 2) * 0.5 + 0.5
    v = 0.55 + 0.25 * grain + 0.2 * tile_noise(n, 32, 2)
    rgb = mix(np.array([0.12, 0.1, 0.08]), np.array([0.36, 0.31, 0.26]), np.clip(v - 0.3, 0, 1))
    save("bark", rgb)


def camo(name, colors, cells, n=256):
    """Blotches: each layer cuts the noise at a threshold over the base colour."""
    rgb = np.ones((n, n, 3)) * np.array(colors[0])[None, None, :]
    for i, col in enumerate(colors[1:]):
        nz = tile_noise(n, cells * (1 + i % 2), 3, 0.55)
        rgb = np.where((nz > 0.55 + 0.02 * i)[..., None], np.array(col)[None, None, :], rgb)
    rgb *= (0.92 + 0.16 * tile_noise(n, 64, 1))[..., None]
    save(name, rgb)


def radial(n):
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    return np.sqrt(x * x + y * y)


def smoke(n=128):
    r = radial(n)
    nz = tile_noise(n, 4, 4)
    a = np.clip(1 - r * (1.1 + 0.6 * (nz - 0.5)), 0, 1) ** 1.6
    rgb = np.ones((n, n, 3)) * (0.6 + 0.4 * nz)[..., None]
    save("smoke", rgb, a * 0.9)


def fire(n=128):
    r = radial(n)
    nz = tile_noise(n, 5, 4)
    a = np.clip(1 - r * (1.0 + 0.8 * (nz - 0.5)), 0, 1) ** 1.3
    heat = np.clip(1.2 - r * 1.1 + 0.3 * (nz - 0.5), 0, 1)
    rgb = mix(np.array([0.9, 0.25, 0.02]), np.array([1.0, 0.9, 0.55]), heat)
    save("fire", rgb, a)


def scorch(n=256):
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    ang = np.arctan2(y, x)
    r = np.sqrt(x * x + y * y)
    rays = 0.15 * np.sin(ang * 9 + 1.3) + 0.1 * np.sin(ang * 23)
    nz = tile_noise(n, 8, 3)
    a = np.clip(1 - r * (1.15 + rays + 0.5 * (nz - 0.5)), 0, 1) ** 0.7
    rgb = np.ones((n, n, 3)) * (0.04 + 0.06 * nz)[..., None]
    save("scorch", rgb, a * 0.92)


def main():
    os.makedirs(OUT, exist_ok=True)
    mud()
    bark()
    camo("camo_green", [(0.29, 0.31, 0.21), (0.2, 0.23, 0.15), (0.38, 0.36, 0.25), (0.12, 0.13, 0.1)], 6)
    camo("camo_tan", [(0.55, 0.48, 0.36), (0.42, 0.36, 0.26), (0.66, 0.6, 0.47), (0.3, 0.27, 0.2)], 5)
    smoke()
    fire()
    scorch()


main()
