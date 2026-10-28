"""Renders the blood splatter atlas in Blender: assets/textures/blood_atlas.png
(1024x512, 4x2 cells, white with alpha = blood coverage). The game's decal
shader colours it, derives thickness/gloss from blurred alpha and dries it.

Run:  blender -b --python tools/blender/build_blood_atlas.py

Cells: 0-1 drop splats with crowns, 2-3 directional splashes with streaks,
4 fine spray, 5 smear with drips, 6-7 puddles (used for growing pools).
Shapes are metaballs, so drops merge into each other like real liquid.
"""
import math
import os
import random

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "blood_atlas.png")
random.seed(12)


def cell_center(i):
    return Vector((i % 4 + 0.5, -(i // 4 + 0.5), 0))


def blob(mb, c, r, sx=1.0, sy=1.0, rot=0.0):
    e = mb.elements.new()
    e.type = "ELLIPSOID"
    e.co = c
    e.radius = r
    e.size_x = sx
    e.size_y = sy
    e.size_z = 1.0
    e.rotation = (math.cos(rot / 2), 0, 0, math.sin(rot / 2))  # quaternion (w, x, y, z) about Z
    return e


def drop_splat(mb, c, size):
    blob(mb, c, size)
    for _ in range(5):
        o = Vector((random.uniform(-1, 1), random.uniform(-1, 1), 0)) * size * 0.45
        blob(mb, c + o, size * random.uniform(0.45, 0.7))
    n = random.randint(10, 16)
    for k in range(n):  # crown spikes
        a = k / n * math.tau + random.uniform(-0.15, 0.15)
        d = Vector((math.cos(a), math.sin(a), 0))
        length = size * random.uniform(1.05, 1.5)
        blob(mb, c + d * length * 0.75, size * 0.14, 2.2, 0.8, a)
        if random.random() < 0.6:
            blob(mb, c + d * length * random.uniform(1.15, 1.6), size * random.uniform(0.06, 0.12))
    for _ in range(14):  # satellites
        a = random.uniform(0, math.tau)
        r = size * random.uniform(1.6, 3.2)
        blob(mb, c + Vector((math.cos(a), math.sin(a), 0)) * r, size * random.uniform(0.03, 0.08))


def splash(mb, c, size, angle):
    d = Vector((math.cos(angle), math.sin(angle), 0))
    side = Vector((-d.y, d.x, 0))
    blob(mb, c - d * size * 0.6, size * 0.8, 1.6, 1.0, angle)
    for _ in range(6):  # streak tails
        off = side * random.uniform(-0.6, 0.6) * size
        dir2 = (d + side * random.uniform(-0.25, 0.25)).normalized()
        steps = random.randint(5, 9)
        for s in range(steps):
            t = s / steps
            blob(mb, c + off * (1 - t) + dir2 * size * (0.2 + 2.6 * t), size * 0.16 * (1 - t * 0.75), 1.8, 0.9,
                 math.atan2(dir2.y, dir2.x))
        blob(mb, c + off * 0.2 + dir2 * size * random.uniform(2.9, 3.6), size * random.uniform(0.06, 0.12))
    for _ in range(18):
        p = c + d * size * random.uniform(0.5, 3.8) + side * size * random.uniform(-1.4, 1.4)
        blob(mb, p, size * random.uniform(0.03, 0.09))


def spray(mb, c, size):
    for _ in range(70):
        a = random.uniform(0, math.tau)
        r = size * math.sqrt(random.random()) * 3.4
        blob(mb, c + Vector((math.cos(a), math.sin(a), 0)) * r, size * random.uniform(0.04, 0.14))
    for _ in range(6):
        a = random.uniform(0, math.tau)
        blob(mb, c + Vector((math.cos(a), math.sin(a), 0)) * size * random.uniform(0, 1.5), size * random.uniform(0.2, 0.35))


def smear(mb, c, size):
    for s in range(14):
        t = s / 13
        blob(mb, c + Vector((t - 0.5, (t - 0.5) * 0.2, 0)) * size * 5.0, size * (0.55 - 0.25 * abs(t - 0.4)), 1.6, 0.8, 0.2)
    for k in range(5):  # drips running down
        x = random.uniform(-1.8, 1.6) * size
        for s in range(6):
            blob(mb, c + Vector((x, -size * (0.3 + s * 0.3), 0)), size * (0.24 - s * 0.015))
        blob(mb, c + Vector((x, -size * 2.6, 0)), size * 0.2)


def puddle(mb, c, size):
    for _ in range(14):
        o = Vector((random.uniform(-1, 1), random.uniform(-1, 1), 0)) * size * 0.75
        blob(mb, c + o, size * random.uniform(0.35, 0.6), random.uniform(0.8, 1.4), random.uniform(0.8, 1.4),
             random.uniform(0, math.tau))
    for _ in range(10):
        a = random.uniform(0, math.tau)
        blob(mb, c + Vector((math.cos(a), math.sin(a), 0)) * size * random.uniform(1.1, 1.5), size * random.uniform(0.06, 0.15))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    mbd = bpy.data.metaballs.new("blood")
    mbd.resolution = 0.006
    mbd.render_resolution = 0.004
    mbd.threshold = 0.25
    ob = bpy.data.objects.new("blood", mbd)
    scene.collection.objects.link(ob)
    drop_splat(mbd, cell_center(0), 0.13)
    drop_splat(mbd, cell_center(1), 0.11)
    splash(mbd, cell_center(2) - Vector((0.3, 0, 0)), 0.11, 0.0)
    splash(mbd, cell_center(3) - Vector((0.25, 0.12, 0)), 0.1, 0.5)
    spray(mbd, cell_center(4), 0.1)
    smear(mbd, cell_center(5) + Vector((0, 0.17, 0)), 0.075)
    puddle(mbd, cell_center(6), 0.24)
    puddle(mbd, cell_center(7), 0.22)

    m = bpy.data.materials.new("white")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs[0])
    mbd.materials.append(m)

    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 4.0
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = (2.0, -1.0, 5.0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 16
    scene.cycles.device = "CPU"
    scene.render.film_transparent = True
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 512
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.render.filepath = OUT
    bpy.ops.render.render(write_still=True)
    print("RENDERED", OUT)


main()
