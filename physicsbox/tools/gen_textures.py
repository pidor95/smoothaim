"""Generates the game's effect textures into assets/textures/*.png.

Run: python3 tools/gen_textures.py  (needs numpy + Pillow)
"""
import os

import numpy as np
from PIL import Image, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "textures")
rng = np.random.default_rng(42)


def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    return x / (n - 1) * 2 - 1, y / (n - 1) * 2 - 1


def value_noise(n, cells):
    g = rng.uniform(0, 1, (cells + 1, cells + 1))
    img = Image.fromarray((g * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
    return np.asarray(img, dtype=np.float64) / 255.0


def save_rgba(name, rgb, alpha):
    a = np.clip(alpha, 0, 1)
    out = np.dstack([np.clip(rgb, 0, 1), a])
    Image.fromarray((out * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"))
    print("wrote", name)


def blood_rgb(n, alpha):
    shade = 0.75 + 0.25 * value_noise(n, 6)
    core = np.clip(alpha * 1.4, 0, 1)
    r = (0.52 + 0.2 * core) * shade
    g = 0.015 + 0.012 * shade
    b = 0.025 + 0.015 * shade
    return np.dstack([r, np.full_like(r, 1) * g, np.full_like(r, 1) * b])


def splat(n, streak):
    x, y = grid(n)
    field = np.zeros((n, n))
    ang = rng.uniform(0, np.pi * 2)
    d = np.array([np.cos(ang), np.sin(ang)])
    # main blob made of several overlapping soft circles
    for _ in range(rng.integers(4, 8)):
        c = rng.normal(0, 0.12, 2)
        r = rng.uniform(0.18, 0.32)
        field += np.clip(1 - np.hypot(x - c[0], y - c[1]) / r, 0, 1) * 1.6
    # satellite droplets, flung along the streak direction
    for _ in range(rng.integers(14, 30)):
        dist = rng.uniform(0.3, 0.9)
        if streak:
            a2 = ang + rng.normal(0, 0.35)
        else:
            a2 = rng.uniform(0, np.pi * 2)
        c = np.array([np.cos(a2), np.sin(a2)]) * dist
        r = rng.uniform(0.015, 0.07) * (1.2 - dist * 0.6)
        field += np.clip(1 - np.hypot(x - c[0], y - c[1]) / r, 0, 1) * 2.0
    if streak:
        # elongated tails
        for _ in range(rng.integers(3, 7)):
            a2 = ang + rng.normal(0, 0.25)
            dd = np.array([np.cos(a2), np.sin(a2)])
            along = x * dd[0] + y * dd[1]
            across = -x * dd[1] + y * dd[0]
            width = rng.uniform(0.02, 0.05)
            length = rng.uniform(0.45, 0.85)
            tail = np.clip(1 - np.abs(across) / (width * np.clip(1 - along / length, 0, 1) + 1e-4), 0, 1)
            tail *= (along > 0) & (along < length)
            field += tail * 1.5
    field *= 0.75 + 0.5 * value_noise(n, 10)
    alpha = np.clip((field - 0.35) * 3.0, 0, 1)
    edge = np.clip(1 - np.hypot(x, y), 0, 1) ** 0.25  # keep off the texture border
    alpha *= edge
    return alpha


def pool(n):
    x, y = grid(n)
    field = np.zeros((n, n))
    for _ in range(9):
        c = rng.normal(0, 0.18, 2)
        r = rng.uniform(0.3, 0.5)
        field += np.clip(1 - np.hypot(x - c[0], y - c[1]) / r, 0, 1)
    field *= 0.85 + 0.3 * value_noise(n, 8)
    alpha = np.clip((field - 0.25) * 4.0, 0, 1) * np.clip(1 - np.hypot(x, y), 0, 1) ** 0.2
    return alpha


def bullet_hole(n):
    x, y = grid(n)
    r = np.hypot(x, y)
    noise = value_noise(n, 12)
    hole = np.clip(1 - r / 0.22, 0, 1)
    ring = np.clip(1 - np.abs(r - 0.3) / 0.25, 0, 1) * (0.4 + 0.6 * noise)
    alpha = np.clip(hole * 4, 0, 1) + ring * 0.8
    alpha = np.clip(alpha * (r < 0.85), 0, 1)
    shade = np.clip(0.05 + r * 0.35 * noise, 0, 1)
    return np.dstack([shade, shade, shade]), alpha


def muzzle_flash(n):
    x, y = grid(n)
    r = np.hypot(x, y)
    ang = np.arctan2(y, x)
    spikes = 0.55 + 0.45 * np.abs(np.cos(ang * 3.5 + 0.3)) ** 6
    spikes += 0.25 * np.abs(np.cos(ang * 7 + 1.0)) ** 10
    alpha = np.clip(1 - r / spikes, 0, 1) ** 1.3
    core = np.clip(1 - r / 0.35, 0, 1)
    rgb = np.dstack([np.ones_like(r), 0.55 + 0.45 * core, 0.15 + 0.85 * core ** 2])
    return rgb, alpha


def flash_side(n):
    # side view of a muzzle blast cone (u = along barrel)
    x, y = grid(n)
    u = (x + 1) / 2
    width = 0.12 + 0.5 * u * (1 - u) * 2
    alpha = np.clip(1 - np.abs(y) / width, 0, 1) * np.clip(1 - u, 0, 1) ** 0.6 * np.clip(u * 8, 0, 1)
    alpha *= 0.7 + 0.3 * value_noise(n, 8)
    core = np.clip(1 - np.abs(y) / (width * 0.4), 0, 1)
    rgb = np.dstack([np.ones_like(u), 0.55 + 0.45 * core, 0.2 + 0.7 * core])
    return rgb, alpha


def menu_grid(n, cells):
    x, y = np.mgrid[0:n, 0:n].astype(np.float64)
    cell = n / cells
    gx = np.abs(((x + cell / 2) % cell) - cell / 2)
    gy = np.abs(((y + cell / 2) % cell) - cell / 2)
    line = np.clip(1 - np.minimum(gx, gy) / 2.5, 0, 1)
    rgb = np.dstack([line * 1.0, line * 0.12, line * 0.05])
    return rgb


def concrete(n):
    v = 0.55 * value_noise(n, 8) + 0.3 * value_noise(n, 32) + 0.15 * rng.uniform(0, 1, (n, n))
    v = 0.9 + (v - 0.5) * 0.09
    return np.dstack([v, v, v * 0.98])


def wood(n):
    x, y = np.mgrid[0:n, 0:n].astype(np.float64) / n
    warp = value_noise(n, 6) * 0.6
    rings = 0.5 + 0.5 * np.sin((y * 14 + warp * 4) * np.pi * 2)
    planks = ((x * 6).astype(int) % 2) * 0.05
    gap = (np.abs(((x * 6) % 1) - 0.0) < 0.012)
    v = 0.84 + rings * 0.05 + planks + value_noise(n, 24) * 0.06 - gap * 0.3
    return np.dstack([v, v * 0.97, v * 0.95])


def tiles(n):
    x, y = np.mgrid[0:n, 0:n].astype(np.float64) / n
    gx = np.abs(((x * 4) % 1) - 0.5) > 0.485
    gy = np.abs(((y * 4) % 1) - 0.5) > 0.485
    v = 0.95 - (gx | gy) * 0.3 + value_noise(n, 16) * 0.05
    return np.dstack([v, v, v])


def clouds(w, h):
    crng = np.random.default_rng(7)

    def vn(cw, ch):
        g = crng.uniform(0, 1, (ch + 1, cw + 1))
        g[:, -1] = g[:, 0]  # wrap horizontally
        return np.asarray(Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), dtype=float) / 255

    n = 0.5 * vn(8, 4) + 0.25 * vn(16, 8) + 0.15 * vn(32, 16) + 0.1 * vn(64, 32)
    y = np.linspace(0, 1, h)[:, None]
    elev = (0.5 - y) * 2  # 1 at zenith, 0 at horizon
    mask = np.clip(elev * 6, 0, 1) * np.clip(1 - elev * 0.6, 0, 1)
    alpha = np.clip((n - 0.5) * 3.2, 0, 1) * mask
    shade = 0.85 + 0.15 * np.clip((n - 0.5) * 2, 0, 1)
    return np.dstack([shade, shade, shade * 1.02]), alpha


def save_rgb(name, rgb):
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, name + ".png"))
    print("wrote", name)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for i in range(6):
        a = splat(128, streak=i >= 3)
        save_rgba(f"splat_{i}", blood_rgb(128, a), a)
    a = pool(128)
    save_rgba("pool", blood_rgb(128, a), a)
    rgb, a = bullet_hole(64)
    save_rgba("bullet_hole", rgb, a)
    rgb, a = muzzle_flash(128)
    save_rgba("muzzle_flash", rgb, a)
    rgb, a = flash_side(128)
    save_rgba("muzzle_flash_side", rgb, a)
    save_rgb("menu_grid", menu_grid(256, 4))
    save_rgb("concrete", concrete(256))
    save_rgb("wood", wood(256))
    save_rgb("tiles", tiles(256))
    rgb, a = clouds(1024, 512)
    save_rgba("clouds", rgb, a)
