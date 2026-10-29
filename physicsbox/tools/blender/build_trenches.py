"""Builds the war map: two trench lines facing each other across a cratered
no-man's land, exported as assets/maps/trenches.glb.

Run:  blender -b --python tools/blender/build_trenches.py

Everything is laid out in the game's frame (Godot axes: +Y up; the allied
line is at +Z, the enemy at -Z). Objects in the glb:
  Terrain           heightfield with the trenches, craters and exits cut in
                    (vertex colours darken the trench floors and craters)
  Planks, Posts     plank revetments lining the trench walls
  Backing           earth walls (bare stretches and the earth behind planks)
  Duckboards, Steps walkway boards and exit steps
  Logs, Mounds      roofed dugout stretches
  Sandbags, Wire    sandbag rows, barbed wire fences
  Tree*             dead trees (linked copies of a few variants)
  C_Walls, C_Roofs  collision-only meshes (the game makes them static bodies)
  SpawnA_*, SpawnB_*, PostA_*, PostB_*   empties: reinforcement points and
                    firing positions of each side; Player = player start
"""
import math
import os
import random

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "maps", "trenches.glb")
random.seed(1916)
rng = np.random.default_rng(1916)

C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Godot -> Blender axes
X0, X1, Z0, Z1 = -46.0, 46.0, -52.0, 52.0
STEP = 0.5
WALL = 0.92        # half width of the trench floor (inner face of the walls)
WALL_T = 0.8       # wall thickness (hides the terrain slope behind it)
FLAT = WALL + 0.3  # the floor stays flat this far out (under the wall), so it is level wall to wall
FRONT_D = 1.3      # fighting trench depth: eyes just over the edge
DEEP_D = 2.1       # communication / rear trenches: over the head


def gv(x, y, z):
    return C @ Vector((x, y, z))


# ---------------------------------------------------------------- layout

def mirror(points, dx=0.0):
    return [(x + dx, -z) for x, z in points]


FRONT_A = [(-44, 27), (-32, 24), (-21, 29), (-10, 25), (0, 30), (10, 25.5), (20, 29.5), (31, 24), (44, 27)]
REAR_A = [(-40, 44), (-24, 41.5), (-8, 45), (8, 42), (24, 45), (42, 43)]
COMMS_A = [
    [(-32, 24), (-31, 33), (-24, 41.5)],
    [(0, 30), (2, 37), (-8, 45)],
    [(31, 24), (30, 34), (24, 45)],
]
TRENCHES = []  # [points, depths]
for side, (front, rear, comms) in enumerate([
        (FRONT_A, REAR_A, COMMS_A),
        (mirror(FRONT_A, 3.0), mirror(REAR_A, -2.0), [mirror(c, 3.0 if i < 1 else 0.0) for i, c in enumerate(COMMS_A)])]):
    TRENCHES.append([front, [FRONT_D] * len(front)])
    TRENCHES.append([rear, [DEEP_D] * len(rear)])
    for c in comms:
        TRENCHES.append([c, [FRONT_D] + [DEEP_D] * (len(c) - 1)])
# the enemy comm trenches must start on the enemy front line: re-anchor them
ef = TRENCHES[5][0]
for k, t in enumerate(TRENCHES[7:10]):
    p = t[0]
    p[0] = min(ef, key=lambda q: (q[0] - p[0][0]) ** 2 + (q[1] - p[0][1]) ** 2)
    p[-1] = min(TRENCHES[6][0], key=lambda q: (q[0] - p[-1][0]) ** 2 + (q[1] - p[-1][1]) ** 2)

# exits: from the front trench up into no-man's land (towards the enemy)
EXITS = []
for side, front in ((0, TRENCHES[0][0]), (1, TRENCHES[5][0])):
    toward = -1.0 if side == 0 else 1.0
    for k in (1, 3, 5, 7):
        a, b = front[k], front[k + 1]
        m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        EXITS.append([m, (m[0], m[1] + toward * 4.4), FRONT_D])

# roofed dugout stretches: [trench index, segment, t0, t1]
ROOFS = [[1, 1, 0.3, 0.6], [1, 3, 0.4, 0.7], [6, 2, 0.3, 0.6], [6, 4, 0.2, 0.5]]


# ---------------------------------------------------------------- geometry maths

def seg_dist(px, pz, a, b):
    """Distance from points to segment ab, and the parameter along it."""
    ax, az = a
    bx, bz = b
    dx, dz = bx - ax, bz - az
    L2 = dx * dx + dz * dz
    t = np.clip(((px - ax) * dx + (pz - az) * dz) / L2, 0.0, 1.0)
    cx, cz = ax + t * dx, az + t * dz
    return np.hypot(px - cx, pz - cz), t


def trench_field(px, pz):
    """Nearest-trench distance and the trench depth there."""
    best = np.full(np.shape(px), 1e9)
    depth = np.zeros(np.shape(px))
    for pts, dep in TRENCHES:
        for i in range(len(pts) - 1):
            d, t = seg_dist(px, pz, pts[i], pts[i + 1])
            dd = dep[i] + (dep[i + 1] - dep[i]) * t
            closer = d < best
            best = np.where(closer, d, best)
            depth = np.where(closer, dd, depth)
    return best, depth


CRATERS = []
while len(CRATERS) < 34:
    x, z = random.uniform(-42, 42), random.uniform(-20, 20)
    if all(math.hypot(x - c[0], z - c[1]) > 4.5 for c in CRATERS):
        CRATERS.append((x, z, random.uniform(1.4, 3.4), random.uniform(0.5, 1.3)))
for _ in range(10):  # shell holes behind the lines too
    x, z = random.uniform(-42, 42), random.choice([random.uniform(33, 40), random.uniform(-40, -33)])
    CRATERS.append((x, z, random.uniform(1.2, 2.4), random.uniform(0.4, 0.9)))


def base_height(px, pz):
    h = (0.18 * np.sin(px * 0.21 + 1.3) * np.cos(pz * 0.17) + 0.12 * np.sin(px * 0.53 + pz * 0.41)
         + 0.06 * np.sin(px * 1.3 - pz * 0.9))
    for cx, cz, r, d in CRATERS:
        rr = np.hypot(px - cx, pz - cz)
        bowl = np.where(rr < r, -d * (1 - (rr / r) ** 2), 0.0)
        rim = 0.22 * d * np.exp(-((rr - r) / 0.7) ** 2)
        h = h + bowl + rim
    # spoil heaps behind each front line (the parados)
    for pts, toward in ((TRENCHES[0][0], -1.0), (TRENCHES[5][0], 1.0)):
        for i in range(len(pts) - 1):
            d, t = seg_dist(px, pz, pts[i], pts[i + 1])
            behind = (pz - (pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)) * -toward > 0
            h = h + np.where(behind, 0.35 * np.exp(-((d - 2.3) / 0.8) ** 2), 0.0)
    return h


def height(px, pz):
    h = base_height(px, pz)
    d, dep = trench_field(px, pz)
    cut = np.where(d < FLAT, -dep, -dep + (h + dep) * np.clip((d - FLAT) / (WALL + WALL_T - FLAT - 0.05), 0, 1))
    h = np.where(d < WALL + WALL_T, np.minimum(h, cut), h)
    for a, b, dep in EXITS:
        dd, t = seg_dist(px, pz, a, b)
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        # level with the trench floor up to the wall line, then a steady climb
        u = np.clip((t * L - (FLAT - 0.15)) / (L - FLAT + 0.15), 0, 1)
        ramp = -dep + (dep + base_height(np.array(b[0]), np.array(b[1]))) * u
        edge = np.clip((dd - FLAT) / 0.6, 0, 1)
        h = np.where(dd < FLAT + 0.6, np.minimum(h, ramp + (h - ramp) * edge), h)
    return h


# ---------------------------------------------------------------- mesh helpers

class MeshBuilder:
    def __init__(self, name, material):
        self.name = name
        self.material = material
        self.bm = bmesh.new()

    def box(self, center, size, yaw=0.0, pitch=0.0):
        """Box in Godot coordinates, turned by yaw (about Y) then pitch."""
        m = Matrix.Translation(gv(*center)) @ (C @ (Matrix.Rotation(yaw, 3, "Y") @ Matrix.Rotation(pitch, 3, "X")) @ C.transposed()).to_4x4()
        m = m @ Matrix.Diagonal((size[0], size[2], size[1], 1.0))
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)

    def hull(self, points):
        """Convex solid through Godot-space points (wall pieces with a sloped top)."""
        vs = [self.bm.verts.new(gv(*p)) for p in points]
        bmesh.ops.convex_hull(self.bm, input=vs)

    def cyl(self, a, b, r, segs=6):
        a, b = gv(*a), gv(*b)
        d = b - a
        m = Matrix.Translation((a + b) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=d.length,
                              matrix=m)

    def finish(self, smooth=False):
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(self.material)
        for p in me.polygons:
            p.use_smooth = smooth
        return ob


def material(name, color):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*color, 1)
    return m


# ---------------------------------------------------------------- terrain

def build_terrain(mat):
    xs = np.arange(X0, X1 + 1e-6, STEP)
    zs = np.arange(Z0, Z1 + 1e-6, STEP)
    gx, gz = np.meshgrid(xs, zs)
    h = height(gx, gz)
    d, dep = trench_field(gx, gz)
    nx, nz = len(xs), len(zs)
    me = bpy.data.meshes.new("Terrain")
    verts = [tuple(gv(gx[j, i], h[j, i], gz[j, i])) for j in range(nz) for i in range(nx)]
    faces = []
    for j in range(nz - 1):
        for i in range(nx - 1):
            a = j * nx + i
            faces.append((a, a + nx, a + nx + 1, a + 1))  # counter-clockwise from above
    me.from_pydata(verts, [], faces)
    me.materials.append(mat)
    # darker, wetter low ground (trench floors, crater bottoms)
    col = me.color_attributes.new("Col", "BYTE_COLOR", "POINT")
    low = np.clip(-h.ravel() / 1.2, 0, 1)
    dry = 0.5 + 0.5 * np.clip(0.6 + 0.25 * np.sin(gx * 0.31) * np.cos(gz * 0.23), 0, 1).ravel()
    for k, c in enumerate(col.data):
        v = (0.95 - 0.35 * low[k]) * (0.85 + 0.15 * dry[k])
        c.color = (v, v * (0.97 + 0.03 * dry[k]), v * 0.95, 1.0)
    ob = bpy.data.objects.new("Terrain", me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    return ob


# ---------------------------------------------------------------- trench furniture

def in_corridor(x, z, skip=None, margin=1.1):
    """Inside another trench (junction) or an exit: no wall there."""
    for ti, (pts, _) in enumerate(TRENCHES):
        for i in range(len(pts) - 1):
            if (ti, i) == skip:
                continue
            d, _t = seg_dist(np.array(x), np.array(z), pts[i], pts[i + 1])
            if d < margin:
                return True
    for a, b, _d in EXITS:
        d, t = seg_dist(np.array(x), np.array(z), a, b)
        if d < WALL + 0.7 and 0.05 < t:
            return True
    return False


def build_walls(m_planks, m_backing, m_post, m_wire):
    planks = MeshBuilder("Planks", m_planks)
    backing = MeshBuilder("Backing", m_backing)
    posts = MeshBuilder("Posts", m_post)
    col = MeshBuilder("C_Walls", m_backing)
    boards = MeshBuilder("Duckboards", m_planks)
    for ti, (pts, dep) in enumerate(TRENCHES):
        for i in range(len(pts) - 1):
            ax, az = pts[i]
            bx, bz = pts[i + 1]
            L = math.hypot(bx - ax, bz - az)
            ux, uz = (bx - ax) / L, (bz - az) / L
            yaw = math.atan2(-uz, ux)  # box X axis along the segment
            plank_run = random.random() < 0.65
            n = max(1, int(math.ceil((L + 0.6) / 1.0)))
            piece = (L + 0.6) / n
            for side in (-1, 1):
                nx_, nz_ = -uz * side, ux * side  # outward normal
                for k in range(n):
                    s = -0.3 + (k + 0.5) * piece
                    cx = ax + ux * s + nx_ * (WALL + WALL_T / 2)
                    cz = az + uz * s + nz_ * (WALL + WALL_T / 2)
                    # no wall where another trench (or an exit) runs: check its corners too
                    pts4 = [(ax + ux * e + nx_ * o, az + uz * e + nz_ * o)
                            for e in (s - piece / 2, s + piece / 2) for o in (WALL, WALL + WALL_T)]
                    if in_corridor(cx, cz, skip=(ti, i)) or any(
                            in_corridor(x, z, skip=(ti, i), margin=WALL + 0.1) for x, z in pts4):
                        continue
                    t = min(max(s / L, 0.0), 1.0)
                    D = dep[i] + (dep[i + 1] - dep[i]) * t
                    top = float(base_height(np.array(cx), np.array(cz))) + 0.04
                    # the piece's top follows the ground at its corners
                    corners = []
                    for e in (s - piece / 2 - 0.01, s + piece / 2 + 0.01):
                        for o in (WALL, WALL + WALL_T):
                            x, z = ax + ux * e + nx_ * o, az + uz * e + nz_ * o
                            y = float(base_height(np.array(x), np.array(z))) + (0.03 if o == WALL else -0.02)
                            corners += [(x, y, z), (x, -D - 0.05, z)]
                    col.hull(corners)
                    backing.hull(corners)
                    if not plank_run:
                        continue
                    fx = ax + ux * s + nx_ * (WALL + 0.015)
                    fz = az + uz * s + nz_ * (WALL + 0.015)
                    y = -D + 0.1
                    while y < top - 0.08:
                        if random.random() > 0.05:  # the odd board missing
                            sag = random.uniform(-0.015, 0.015)
                            planks.box((fx, y + sag, fz), (piece - 0.03, 0.17, 0.03), yaw, random.uniform(-0.02, 0.02))
                        y += 0.2
                    px = ax + ux * (s - piece / 2) + nx_ * (WALL + 0.05)
                    pz = az + uz * (s - piece / 2) + nz_ * (WALL + 0.05)
                    posts.cyl((px, -D - 0.1, pz), (px, top + 0.12, pz), 0.06)
            # duckboards along the floor
            s = 0.2
            while s < L - 0.1:
                cx, cz = ax + ux * s, az + uz * s
                y = -(dep[i] + (dep[i + 1] - dep[i]) * s / L) + 0.035
                boards.box((cx, y, cz), (0.13, 0.03, 1.15), yaw)
                s += 0.2
            for off in (-0.42, 0.42):
                cx, cz = ax + ux * L / 2 - uz * off, az + uz * L / 2 + ux * off
                y = -(dep[i] + dep[i + 1]) / 2 + 0.01
                boards.box((cx, y, cz), (L - 0.2, 0.04, 0.07), yaw)
    return planks.finish(), backing.finish(), posts.finish(), col.finish(), boards.finish()


def build_exits(m_planks):
    steps = MeshBuilder("Steps", m_planks)
    for a, b, dep in EXITS:
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        ux, uz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        yaw = math.atan2(-uz, ux)
        s = WALL + 0.15
        while s < L - 0.2:
            x, z = a[0] + ux * s, a[1] + uz * s
            y = float(height(np.array(x), np.array(z))) + 0.04
            steps.box((x, y, z), (0.24, 0.05, 1.2), yaw)
            s += 0.38
    return steps.finish()


def build_roofs(m_logs, m_mud):
    logs = MeshBuilder("Logs", m_logs)
    mounds = MeshBuilder("Mounds", m_mud)
    col = MeshBuilder("C_Roofs", m_mud)
    for ti, seg, t0, t1 in ROOFS:
        pts = TRENCHES[ti][0]
        a, b = pts[seg], pts[seg + 1]
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        ux, uz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        yaw = math.atan2(-uz, ux)
        s = t0 * L
        while s < t1 * L:
            cx, cz = a[0] + ux * s, a[1] + uz * s
            top = float(base_height(np.array(cx), np.array(cz))) + 0.14
            r = random.uniform(0.1, 0.13)
            w = WALL + 0.6
            logs.cyl((cx + uz * w, top, cz - ux * w), (cx - uz * w, top + random.uniform(-0.03, 0.03), cz + ux * w), r, 8)
            s += 0.25
        mid = (t0 + t1) / 2 * L
        cx, cz = a[0] + ux * mid, a[1] + uz * mid
        top = float(base_height(np.array(cx), np.array(cz))) + 0.14
        span = (t1 - t0) * L
        mounds.box((cx, top + 0.2, cz), (span, 0.3, 2.6), yaw)
        mounds.box((cx, top + 0.38, cz), (span - 0.4, 0.2, 1.9), yaw)
        col.box((cx, top + 0.14, cz), (span, 0.5, 3.2), yaw)
    return logs.finish(), mounds.finish(True), col.finish()


def build_sandbags(m_bag):
    bags = MeshBuilder("Sandbags", m_bag)
    for pts, toward in ((TRENCHES[0][0], -1.0), (TRENCHES[5][0], 1.0)):
        for i in range(1, len(pts) - 1, 2):
            a, b = pts[i], pts[i + 1]
            L = math.hypot(b[0] - a[0], b[1] - a[1])
            ux, uz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
            nx_, nz_ = -uz, ux
            if nz_ * toward < 0:
                nx_, nz_ = -nx_, -nz_
            yaw = math.atan2(-uz, ux)
            for row in range(2):
                s = L * 0.3 + row * 0.25
                while s < L * 0.7:
                    x = a[0] + ux * s + nx_ * (WALL + 0.45)
                    z = a[1] + uz * s + nz_ * (WALL + 0.45)
                    y = float(base_height(np.array(x), np.array(z))) + 0.09 + row * 0.16
                    bags.box((x, y, z), (0.48, 0.16, 0.3), yaw + random.uniform(-0.08, 0.08))
                    s += 0.5
    ob = bags.finish()
    mod = ob.modifiers.new("bevel", "BEVEL")
    mod.width = 0.05
    mod.segments = 2
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="bevel")
    return ob


def build_wire(m_post, m_wire):
    stakes = MeshBuilder("WireStakes", m_post)
    wire = MeshBuilder("Wire", m_wire)
    for z0 in (-13.0, 13.0):
        x = -42.0
        prev = None
        while x < 42.0:
            z = z0 + random.uniform(-1.0, 1.0)
            if any(math.hypot(x - c[0], z - c[1]) < c[2] for c in CRATERS) or random.random() < 0.12:
                x += random.uniform(2.5, 4.0)
                prev = None
                continue
            y = float(height(np.array(x), np.array(z)))
            lean = random.uniform(-0.15, 0.15)
            top = (x + lean, y + 1.05, z)
            stakes.cyl((x, y - 0.2, z), top, 0.035)
            if prev:
                for k in range(3):
                    f = 0.3 + k * 0.33
                    pa = (prev[0][0], prev[1] + (prev[0][1] - prev[1]) * f, prev[0][2])
                    pb = (top[0], y + (top[1] - y) * f, top[2])
                    wire.cyl(pa, pb, 0.007, 4)
                pa = prev[0]
                wire.cyl(pa, (x, y + 0.2, z), 0.007, 4)
            prev = (top, y)
            x += random.uniform(2.5, 3.5)
    return stakes.finish(), wire.finish()


def make_tree(name, m_bark, seed):
    rnd = random.Random(seed)
    tb = MeshBuilder(name, m_bark)

    def branch(p, d, length, r, level):
        end = p + d * length
        tb.cyl(tuple(p), tuple(end), r, 6 if level < 2 else 4)
        if level >= 3 or r < 0.012:
            return
        for _ in range(rnd.randint(2, 4) if level > 0 else rnd.randint(3, 5)):
            f = rnd.uniform(0.45, 0.95)
            q = p + d * length * f
            nd = (d + Vector((rnd.uniform(-1, 1), rnd.uniform(-0.1, 0.8), rnd.uniform(-1, 1))) * 0.9).normalized()
            branch(q, nd, length * rnd.uniform(0.35, 0.6), r * 0.45, level + 1)

    h = rnd.uniform(5.5, 9.0)
    branch(Vector((0, -0.3, 0)), Vector((rnd.uniform(-0.08, 0.08), 1, rnd.uniform(-0.08, 0.08))).normalized(),
           h, rnd.uniform(0.12, 0.2), 0)
    ob = tb.finish()
    return ob


def place_trees(variants):
    placed = []
    tries = 0
    while len(placed) < 70 and tries < 4000:
        tries += 1
        x, z = random.uniform(-44, 44), random.uniform(-50, 50)
        d, _ = trench_field(np.array(x), np.array(z))
        if float(d) < 3.2 or any(math.hypot(x - c[0], z - c[1]) < c[2] + 0.5 for c in CRATERS):
            continue
        if abs(z) < 22 and random.random() < 0.6:  # no-man's land: fewer, shattered
            continue
        if any(math.hypot(x - p[0], z - p[1]) < 3.0 for p in placed):
            continue
        y = float(height(np.array(x), np.array(z)))
        src = random.choice(variants)
        ob = bpy.data.objects.new("Tree%d" % len(placed), src.data)
        bpy.context.scene.collection.objects.link(ob)
        s = random.uniform(0.8, 1.25) * (0.6 if abs(z) < 22 else 1.0)
        ob.matrix_world = Matrix.Translation(gv(x, y, z)) @ Matrix.Rotation(random.uniform(0, 6.28), 4, "Z") \
            @ Matrix.Scale(s, 4)
        placed.append((x, z))
    for v in variants:
        bpy.data.objects.remove(v)


def empties():
    def empty(name, x, z, yaw=0.0):
        ob = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(ob)
        y = float(height(np.array(x), np.array(z)))
        ob.matrix_world = Matrix.Translation(gv(x, y + 0.05, z)) @ Matrix.Rotation(yaw, 4, "Z")
    for side, (front, rear) in enumerate(((TRENCHES[0][0], TRENCHES[1][0]), (TRENCHES[5][0], TRENCHES[6][0]))):
        tag = "AB"[side]
        k = 0
        for pts in (rear,):
            for i in range(len(pts) - 1):
                for t in (0.3, 0.7):
                    x = pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t
                    z = pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t
                    empty("Spawn%s_%d" % (tag, k), x, z)
                    k += 1
        k = 0
        for i in range(len(front) - 1):
            for t in (0.25, 0.5, 0.75):
                x = front[i][0] + (front[i + 1][0] - front[i][0]) * t
                z = front[i][1] + (front[i + 1][1] - front[i][1]) * t
                empty("Post%s_%d" % (tag, k), x, z)
                k += 1
    a, b = TRENCHES[0][0][4], TRENCHES[0][0][5]
    empty("Player", a[0] + (b[0] - a[0]) * 0.45, a[1] + (b[1] - a[1]) * 0.45)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    m_mud = material("Mud", (0.3, 0.24, 0.18))
    m_planks = material("Planks", (0.42, 0.32, 0.22))
    m_post = material("Posts", (0.28, 0.21, 0.15))
    m_logs = material("Logs", (0.3, 0.25, 0.2))
    m_bark = material("Bark", (0.25, 0.22, 0.19))
    m_bag = material("Sandbag", (0.48, 0.42, 0.3))
    m_wire = material("Wire", (0.2, 0.19, 0.18))
    build_terrain(m_mud)
    build_walls(m_planks, m_mud, m_post, m_wire)
    build_exits(m_planks)
    build_roofs(m_logs, m_mud)
    build_sandbags(m_bag)
    build_wire(m_post, m_wire)
    place_trees([make_tree("TreeSrc%d" % i, m_bark, 50 + i) for i in range(4)])
    empties()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_cameras=False,
                              export_lights=False, export_animations=False, export_vertex_color="ACTIVE",
                              export_extras=False)
    tris = sum(len(o.data.polygons) for o in bpy.context.scene.objects if o.type == "MESH" and not o.name.startswith("Tree"))
    print("EXPORTED", OUT, os.path.getsize(OUT), "faces (no trees)", tris)


main()
