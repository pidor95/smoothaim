"""Renders the bullet-wound atlas in Blender: assets/textures/wound_atlas.png
(512x512, 2x2 cells, RGBA). Each cell is what a hit leaves on a soldier's
uniform: the hole, wet torn flesh round it, a ring of frayed fabric with
loose threads, and the blood soaking into the cloth around. The game glues
them to the body parts (scripts/blood.gd, wound_decal.gdshader).

Run:  blender -b --python tools/blender/build_wound_atlas.py

Cells: 0-1 bullet entry holes, 2 exit wound (bigger, flaps torn outwards),
3 fragment rip (long jagged tear with scorched edges).
"""
import math
import os

import bpy
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "wound_atlas.png")
CELL = 256
rng = np.random.default_rng(545)


def value_noise(shape, scale, seed):
    """Smooth 2D noise in 0..1 (bilinear over a random grid)."""
    r = np.random.default_rng(seed)
    gh, gw = int(shape[0] / scale) + 3, int(shape[1] / scale) + 3
    g = r.random((gh, gw))
    y = np.arange(shape[0]) / scale
    x = np.arange(shape[1]) / scale
    y0, x0 = np.floor(y).astype(int), np.floor(x).astype(int)
    fy, fx = y - y0, x - x0
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0]
    b = g[y0][:, x0 + 1]
    c = g[y0 + 1][:, x0]
    d = g[y0 + 1][:, x0 + 1]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def fbm(shape, scale, seed, octaves=4):
    out = np.zeros(shape)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        out += value_noise(shape, scale / (2 ** o), seed + o * 17) * amp
        total += amp
        amp *= 0.5
    return out / total


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def angular(ang, seed, lobes):
    """Noise round the circle (0..1): how far the tear reaches each way."""
    r = np.random.default_rng(seed)
    k = np.arange(1, lobes + 1)
    amp = r.random(lobes) / k
    ph = r.random(lobes) * math.tau
    v = sum(amp[i] * np.sin(ang * k[i] + ph[i]) for i in range(lobes))
    return (v - v.min()) / (v.max() - v.min())


def cell(kind, seed):
    n = CELL
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2.0 - 1.0  # -1..1
    stretch = {"entry": 1.0, "exit": 1.15, "rip": 2.3}[kind]
    rr = np.hypot(x / stretch, y)
    ang = np.arctan2(y, x * 1.0)
    warp = fbm((n, n), 40, seed) - 0.5
    fine = fbm((n, n), 9, seed + 5) - 0.5
    r = rr + warp * 0.12 + fine * 0.05
    hole_r = {"entry": 0.12, "exit": 0.2, "rip": 0.13}[kind]
    flesh_r = hole_r * {"entry": 1.7, "exit": 1.9, "rip": 1.8}[kind]
    flesh_r = flesh_r * (0.75 + 0.5 * angular(ang, seed + 1, 7))
    # the cloth is torn back unevenly: long flaps one way, almost nothing the other
    reach = angular(ang, seed + 2, 9) ** 1.6
    torn_r = flesh_r + 0.03 + reach * {"entry": 0.22, "exit": 0.32, "rip": 0.24}[kind]
    soak_r = {"entry": 0.72, "exit": 0.85, "rip": 0.72}[kind] * (0.75 + 0.45 * angular(ang, seed + 3, 6))
    # a few loose threads past the torn edge, of different lengths
    rays = (np.sin(ang * rng.integers(13, 19) + fbm((n, n), 25, seed + 9) * 6.0) * 0.5 + 0.5) ** 14
    thread_len = torn_r + 0.03 + 0.1 * angular(ang, seed + 8, 11)
    threads = rays * smooth(thread_len, thread_len - 0.04, r) * smooth(torn_r - 0.02, torn_r + 0.01, r) * 0.7

    rgb = np.zeros((n, n, 3))
    # blood soaking into the cloth: dark, patchy, fading out
    soak = smooth(soak_r, soak_r * 0.45, r) * (0.45 + 0.55 * fbm((n, n), 12, seed + 4))
    rgb[:] = np.array([0.3, 0.025, 0.02])  # fresh blood in the cloth
    a = soak * 0.9
    # frayed fabric flaps: pale torn fibres, stained with blood near the hole
    torn = smooth(torn_r, torn_r - 0.03, r) * smooth(flesh_r - 0.015, flesh_r + 0.015, r)
    torn *= smooth(0.25, 0.55, fbm((n, n), 7, seed + 6) + reach * 0.4)  # holes in the flaps
    fabric = np.array([0.42, 0.39, 0.3]) * (0.7 + 0.5 * fbm((n, n), 4, seed + 7))[..., None]
    stain = smooth(torn_r, flesh_r, r)[..., None] * 0.7
    fabric = fabric * (1 - stain) + np.array([0.25, 0.04, 0.03]) * stain
    if kind == "rip":  # scorched by the hot fragment
        fabric = fabric * 0.3 + np.array([0.035, 0.028, 0.02])
    fab = np.clip(torn + threads, 0.0, 1.0)
    rgb = rgb * (1 - fab[..., None]) + fabric * fab[..., None]
    a = np.maximum(a, fab)
    # wet torn flesh, then the dark hole
    flesh = smooth(flesh_r, flesh_r - 0.03, r)
    meat = np.array([0.45, 0.035, 0.045]) * (0.6 + 0.7 * fbm((n, n), 4, seed + 11))[..., None]
    rgb = rgb * (1 - flesh[..., None]) + meat * flesh[..., None]
    a = np.maximum(a, flesh)
    hole = smooth(hole_r, hole_r * 0.5, r)
    rgb = rgb * (1 - hole[..., None]) + np.array([0.035, 0.0, 0.0]) * hole[..., None]
    # nothing past the cell's edge
    a *= smooth(1.0, 0.88, np.maximum(np.abs(x), np.abs(y)))
    return np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)])


def main():
    atlas = np.zeros((CELL * 2, CELL * 2, 4))
    for i, (kind, seed) in enumerate([("entry", 1), ("entry", 2), ("exit", 3), ("rip", 4)]):
        cx, cy = i % 2, i // 2
        atlas[cy * CELL:(cy + 1) * CELL, cx * CELL:(cx + 1) * CELL] = cell(kind, seed * 31)
    img = bpy.data.images.new("wound_atlas", CELL * 2, CELL * 2, alpha=True)
    img.pixels = np.flipud(atlas).ravel().astype(np.float32)  # Blender images start at the bottom row
    img.filepath_raw = OUT
    img.file_format = "PNG"
    img.save()
    print("WOUND ATLAS", OUT)


main()
