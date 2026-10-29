"""Builds the war map: a front several hundred metres long - two trench
systems facing each other across a cratered no-man's land, a town sector on
the east flank with two five-storey panel blocks (like in the user's video)
on either side of the line, abandoned villages behind both lines and ruins
in no-man's land. Exported as assets/maps/trenches.glb.

Run (after build_buildings.py):  blender -b --python tools/blender/build_trenches.py

Everything is laid out in the game's frame (Godot axes: +Y up; the allied
line is at +Z, the enemy at -Z). Objects in the glb:
  Terrain_<i>_<j>   heightfield chunks with the trenches, craters, exits,
                    building pads and tracks (vertex colours darken trench
                    floors, craters and roads); finer where there is detail,
                    with skirts hiding the seams
  Planks_*, Posts_* plank revetments lining the trench walls (by map cell)
  Backing_*         earth walls (bare stretches and the earth behind planks)
  Duckboards_*, Steps_*   walkway boards and exit steps
  Logs_*, Mounds_*  roofed dugout stretches
  Sandbags_*, Wire_*, WireStakes_*
  Tree*             dead trees (linked copies of a few variants)
  C_*               collision-only meshes (the game makes them static bodies)
  B_<Proto>_<side>_<k>    empties: where buildings.glb prototypes stand
                    (side A / B / N: whose positions their windows are)
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
X0, X1, Z0, Z1 = -150.0, 150.0, -170.0, 170.0
CHX, CHZ = 30.0, 34.0  # terrain chunk size
CELL = 60.0  # furniture meshes are split into cells this big (culling)
WALL = 0.92        # half width of the trench floor (inner face of the walls)
WALL_T = 0.8       # wall thickness (hides the terrain slope behind it)
FLAT = WALL + 0.3  # the floor stays flat this far out (under the wall), so it is level wall to wall
FRONT_D = 1.3      # fighting trench depth: eyes just over the edge
DEEP_D = 2.1       # communication / rear trenches: over the head


def gv(x, y, z):
    return C @ Vector((x, y, z))


# ---------------------------------------------------------------- layout

def zigzag(xa, xb, step, z, amp):
    pts = []
    x = xa
    k = 0
    while x < xb + 0.1:
        pts.append((round(x, 2), round(z + (amp if k % 2 else -amp) * random.uniform(0.5, 1.0), 2)))
        x += step * random.uniform(0.85, 1.15)
        k += 1
    pts[-1] = (xb, pts[-1][1])
    return pts


def nearest(pts, x):
    return min(pts, key=lambda q: abs(q[0] - x))


TRENCHES = []  # [points, depths]
FRONTS = []
REARS = []
for side, sgn in ((0, 1.0), (1, -1.0)):
    front = zigzag(-142.0, 42.0, 11.0, sgn * 29.0, 2.6)
    rear = zigzag(-138.0, 38.0, 17.0, sgn * 50.0, 2.0)
    FRONTS.append(len(TRENCHES))
    TRENCHES.append([front, [FRONT_D] * len(front)])
    REARS.append(len(TRENCHES))
    TRENCHES.append([rear, [DEEP_D] * len(rear)])
    for x in (-118.0, -74.0, -31.0, 14.0):
        f = nearest(front, x)
        r = nearest(rear, x + random.uniform(-6, 6))
        mid = ((f[0] + r[0]) / 2 + random.uniform(-4, 4), (f[1] + r[1]) / 2)
        TRENCHES.append([[f, mid, r], [FRONT_D, DEEP_D, DEEP_D]])

# exits: from the front trench up into no-man's land (towards the enemy)
EXITS = []
for side in (0, 1):
    front = TRENCHES[FRONTS[side]][0]
    toward = -1.0 if side == 0 else 1.0
    for k in range(1, len(front) - 1, 2):
        a, b = front[k], front[k + 1]
        m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        EXITS.append([m, (m[0], m[1] + toward * 4.4), FRONT_D])

# roofed dugout stretches: [trench index, segment, t0, t1]
ROOFS = []
for side in (0, 1):
    n = len(TRENCHES[REARS[side]][0])
    for seg in range(1, n - 1, 3):
        ROOFS.append([REARS[side], seg, 0.3, 0.6])

# buildings (prototypes from buildings.glb): name, x, z, yaw, half extents
# (x, z-front, z-back in local axes) for the ground pad
EXTENT = {"Panel5": (19.0, -2.5, 13.0), "HouseBrick": (4.8, -5.2, 4.6), "HouseWood": (4.2, -5.5, 3.8),
          "Ruin2": (7.8, -6.5, 5.2), "Garages": (10.8, -4.5, 3.6), "CarWreck": (1.2, -2.4, 2.4)}
BUILDINGS = [
    ("Panel5", 97.0, 16.0, 0.0), ("Panel5", 97.0, -16.0, math.pi),
    ("Garages", 61.0, 0.0, math.pi / 2), ("Ruin2", 133.0, 1.0, -math.pi / 2),
    ("HouseBrick", 68.0, -47.0, math.pi), ("HouseBrick", 126.0, 47.0, 0.1),
    ("CarWreck", 88.0, 5.0, 0.4), ("CarWreck", 108.0, -4.0, 2.1), ("CarWreck", 77.0, -9.0, 1.2),
    ("Ruin2", -55.0, 2.0, 0.15), ("HouseBrick", -6.0, -3.0, math.pi), ("HouseWood", -101.0, 4.0, 0.5),
    ("HouseWood", -122.0, 86.0, 0.3), ("HouseBrick", -95.0, 97.0, -0.2), ("HouseWood", -62.0, 82.0, 0.1),
    ("Ruin2", -22.0, 102.0, 0.0), ("HouseBrick", 24.0, 86.0, 0.4), ("Garages", 62.0, 96.0, 0.0),
    ("HouseWood", 98.0, 92.0, -0.3), ("CarWreck", 40.0, 70.0, 0.9),
    ("HouseWood", -116.0, -90.0, math.pi + 0.2), ("HouseBrick", -71.0, -86.0, math.pi), ("Ruin2", -26.0, -104.0, math.pi),
    ("HouseWood", 19.0, -91.0, math.pi - 0.3), ("HouseBrick", 58.0, -96.0, math.pi + 0.2),
    ("Garages", 100.0, -94.0, math.pi), ("CarWreck", -40.0, -70.0, 2.5),
]
TOWN = (52.0, 146.0, -62.0, 62.0)  # flat ground of the town sector
ROADS = [[(-148.0, 64.0), (148.0, 64.0)], [(-148.0, -64.0), (148.0, -64.0)],
         [(97.0, 64.0), (97.0, 30.0)], [(97.0, -64.0), (97.0, -30.0)], [(55.0, 0.0), (140.0, 0.0)]]


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


def pad_local(px, pz, b):
    """Point in a building's local axes."""
    _n, bx, bz, yaw = b
    dx, dz = px - bx, pz - bz
    c, s_ = math.cos(yaw), math.sin(yaw)
    # Godot yaw about +Y: local x = dx cos - dz sin ... (inverse rotation)
    return dx * c - dz * s_, dx * s_ + dz * c


def in_pad(x, z, margin=1.5):
    for b in BUILDINGS:
        lx, lz = pad_local(x, z, b)
        ex, ez0, ez1 = EXTENT[b[0]]
        if abs(lx) < ex + margin and ez0 - margin < lz < ez1 + margin:
            return True
    return False


def in_town(x, z, margin=0.0):
    return TOWN[0] - margin < x < TOWN[1] + margin and TOWN[2] - margin < z < TOWN[3] + margin


CRATERS = []
while len(CRATERS) < 170:
    x, z = random.uniform(-146, 50), random.uniform(-22, 22)
    if all(math.hypot(x - c[0], z - c[1]) > 4.0 for c in CRATERS) and not in_pad(x, z, 3.0):
        CRATERS.append((x, z, random.uniform(1.4, 3.4), random.uniform(0.5, 1.3)))
while len(CRATERS) < 260:  # shell holes behind the lines and in the town too
    x, z = random.uniform(-146, 146), random.uniform(-160, 160)
    if abs(z) < 22 and x < 50:
        continue
    if in_pad(x, z, 3.0) or any(math.hypot(x - c[0], z - c[1]) < 4.0 for c in CRATERS):
        continue
    CRATERS.append((x, z, random.uniform(1.2, 2.6), random.uniform(0.4, 0.9)))


def town_mask(px, pz):
    """1 inside the flat town ground, fading out over 12 m."""
    dx = np.maximum(np.maximum(TOWN[0] - px, px - TOWN[1]), 0.0)
    dz = np.maximum(np.maximum(TOWN[2] - pz, pz - TOWN[3]), 0.0)
    return np.clip(1.0 - np.hypot(dx, dz) / 12.0, 0.0, 1.0)


def base_height(px, pz, pads=True):
    px = np.asarray(px, dtype=float)
    pz = np.asarray(pz, dtype=float)
    h = (0.18 * np.sin(px * 0.21 + 1.3) * np.cos(pz * 0.17) + 0.12 * np.sin(px * 0.53 + pz * 0.41)
         + 0.06 * np.sin(px * 1.3 - pz * 0.9))
    # broad rolling ground away from the trench lines and the town
    h = h + (1.1 * np.sin(px * 0.021 + 0.4) * np.cos(pz * 0.018 - 0.3) + 0.6 * np.sin(px * 0.047 - pz * 0.033)) \
        * np.clip((np.abs(pz) - 60.0) / 30.0, 0.0, 1.0)
    h = h * (1.0 - town_mask(px, pz) * 0.85)
    for cx, cz, r, d in CRATERS:
        if np.ndim(px) and (np.min(np.abs(px - cx)) > r + 2.5 or np.min(np.abs(pz - cz)) > r + 2.5):
            continue
        rr = np.hypot(px - cx, pz - cz)
        bowl = np.where(rr < r, -d * (1 - (rr / r) ** 2), 0.0)
        rim = 0.22 * d * np.exp(-((rr - r) / 0.7) ** 2)
        h = h + bowl + rim
    # spoil heaps behind each front line (the parados)
    for pts, toward in ((TRENCHES[FRONTS[0]][0], -1.0), (TRENCHES[FRONTS[1]][0], 1.0)):
        for i in range(len(pts) - 1):
            d, t = seg_dist(px, pz, pts[i], pts[i + 1])
            behind = (pz - (pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t)) * -toward > 0
            h = h + np.where(behind, 0.35 * np.exp(-((d - 2.3) / 0.8) ** 2), 0.0)
    # level pads under the buildings
    for b in (BUILDINGS if pads else ()):
        ex, ez0, ez1 = EXTENT[b[0]]
        _n, bx, bz, yaw = b
        if np.ndim(px) and (np.min(np.abs(px - bx)) > ex + ez1 + 8 or np.min(np.abs(pz - bz)) > ex + ez1 + 8):
            continue
        c, s_ = math.cos(yaw), math.sin(yaw)
        lx = (px - bx) * c - (pz - bz) * s_
        lz = (px - bx) * s_ + (pz - bz) * c
        ox = np.maximum(np.abs(lx) - ex, 0.0)
        oz = np.maximum(np.maximum(ez0 - lz, lz - ez1), 0.0)
        w = np.clip(1.0 - np.hypot(ox, oz) / 4.0, 0.0, 1.0)
        h = h * (1.0 - w) + PAD_Y.get(b, 0.0) * w
    return h


PAD_Y = {}
for _b in BUILDINGS:
    PAD_Y[_b] = float(base_height(np.array(_b[1]), np.array(_b[2]), pads=False))


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

class Cells:
    """Several MeshBuilders of one kind, one per map cell (so the game can
    cull what is out of view): name_<i>_<j>."""

    def __init__(self, name, material):
        self.name = name
        self.material = material
        self.cells = {}

    def at(self, x, z):
        key = (int((x - X0) // CELL), int((z - Z0) // CELL))
        if key not in self.cells:
            self.cells[key] = MeshBuilder("%s_%d_%d" % (self.name, key[0], key[1]), self.material)
        return self.cells[key]

    def finish(self, smooth=False):
        return [mb.finish(smooth) for mb in self.cells.values()]


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

def near_trench(x0, x1, z0, z1, pad):
    for pts, _d in TRENCHES:
        for i in range(len(pts) - 1):
            (ax, az), (bx, bz) = pts[i], pts[i + 1]
            if max(ax, bx) + pad > x0 and min(ax, bx) - pad < x1 and max(az, bz) + pad > z0 and min(az, bz) - pad < z1:
                # closer check: distance from the segment to the chunk centre
                cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
                d, _t = seg_dist(np.array(cx), np.array(cz), (ax, az), (bx, bz))
                if float(d) < math.hypot(x1 - x0, z1 - z0) / 2 + pad:
                    return True
    return False


def chunk_step(x0, x1, z0, z1):
    if near_trench(x0, x1, z0, z1, 3.0):
        return 0.5
    for b in BUILDINGS:
        if x0 - 20 < b[1] < x1 + 20 and z0 - 20 < b[2] < z1 + 20:
            return 1.0
    if any(x0 - 4 < c[0] < x1 + 4 and z0 - 4 < c[1] < z1 + 4 for c in CRATERS):
        return 1.0
    return 2.0


def road_dist(px, pz):
    best = np.full(np.shape(px), 1e9)
    for a, b in ROADS:
        d, _t = seg_dist(px, pz, a, b)
        best = np.minimum(best, d)
    return best


def build_terrain(mat):
    """Terrain in chunks; each chunk's grid step depends on what is in it.
    A skirt hangs from every edge so the seams between steps never open."""
    nx = int(round((X1 - X0) / CHX))
    nz = int(round((Z1 - Z0) / CHZ))
    total = 0
    for i in range(nx):
        for j in range(nz):
            x0, z0 = X0 + i * CHX, Z0 + j * CHZ
            x1, z1 = x0 + CHX, z0 + CHZ
            step = chunk_step(x0, x1, z0, z1)
            xs = np.linspace(x0, x1, int(round(CHX / step)) + 1)
            zs = np.linspace(z0, z1, int(round(CHZ / step)) + 1)
            gx, gz = np.meshgrid(xs, zs)
            h = height(gx, gz)
            cnx, cnz = len(xs), len(zs)
            verts = [tuple(gv(gx[q, k], h[q, k], gz[q, k])) for q in range(cnz) for k in range(cnx)]
            faces = []
            for q in range(cnz - 1):
                for k in range(cnx - 1):
                    a = q * cnx + k
                    faces.append((a, a + cnx, a + cnx + 1, a + 1))
            # skirts: the border loop again, 0.8 m lower, faced outwards
            border = [(0, k) for k in range(cnx)] + [(q, cnx - 1) for q in range(1, cnz)] \
                + [(cnz - 1, k) for k in range(cnx - 2, -1, -1)] + [(q, 0) for q in range(cnz - 2, 0, -1)]
            base = len(verts)
            for q, k in border:
                verts.append(tuple(gv(gx[q, k], h[q, k] - 0.8, gz[q, k])))
            nb = len(border)
            for m in range(nb):
                q0, k0 = border[m]
                q1, k1 = border[(m + 1) % nb]
                faces.append((q0 * cnx + k0, q1 * cnx + k1, base + (m + 1) % nb, base + m))
            me = bpy.data.meshes.new("Terrain_%d_%d" % (i, j))
            me.from_pydata(verts, [], faces)
            me.materials.append(mat)
            col = me.color_attributes.new("Col", "BYTE_COLOR", "POINT")
            hh = np.concatenate([h.ravel(), np.array([h[q, k] for q, k in border])])
            gxx = np.concatenate([gx.ravel(), np.array([gx[q, k] for q, k in border])])
            gzz = np.concatenate([gz.ravel(), np.array([gz[q, k] for q, k in border])])
            low = np.clip(-hh / 1.2, 0, 1)
            dry = 0.5 + 0.5 * np.clip(0.6 + 0.25 * np.sin(gxx * 0.31) * np.cos(gzz * 0.23), 0, 1)
            road = np.clip(1.0 - (road_dist(gxx, gzz) - 1.6) / 1.4, 0, 1)
            town = town_mask(gxx, gzz)
            for k, c in enumerate(col.data):
                v = (0.95 - 0.35 * low[k]) * (0.85 + 0.15 * dry[k]) * (1.0 - 0.3 * road[k]) * (1.0 - 0.12 * town[k])
                c.color = (v, v * (0.97 + 0.03 * dry[k]), v * (0.95 + 0.04 * town[k]), 1.0)
            ob = bpy.data.objects.new(me.name, me)
            bpy.context.scene.collection.objects.link(ob)
            # (the game smooths the normals itself on import)
            for poly in me.polygons:
                poly.use_smooth = True
            total += len(verts)
    print("terrain verts", total)


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
    planks = Cells("Planks", m_planks)
    backing = Cells("Backing", m_backing)
    posts = Cells("Posts", m_post)
    col = Cells("C_Walls", m_backing)
    boards = Cells("Duckboards", m_planks)
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
                    col.at(cx, cz).hull(corners)
                    backing.at(cx, cz).hull(corners)
                    if not plank_run:
                        continue
                    fx = ax + ux * s + nx_ * (WALL + 0.015)
                    fz = az + uz * s + nz_ * (WALL + 0.015)
                    y = -D + 0.1
                    while y < top - 0.08:
                        if random.random() > 0.05:  # the odd board missing
                            sag = random.uniform(-0.015, 0.015)
                            planks.at(fx, fz).box((fx, y + sag, fz), (piece - 0.03, 0.17, 0.03), yaw, random.uniform(-0.02, 0.02))
                        y += 0.2
                    px = ax + ux * (s - piece / 2) + nx_ * (WALL + 0.05)
                    pz = az + uz * (s - piece / 2) + nz_ * (WALL + 0.05)
                    posts.at(px, pz).cyl((px, -D - 0.1, pz), (px, top + 0.12, pz), 0.06)
            # duckboards along the floor
            s = 0.2
            while s < L - 0.1:
                cx, cz = ax + ux * s, az + uz * s
                y = -(dep[i] + (dep[i + 1] - dep[i]) * s / L) + 0.035
                boards.at(cx, cz).box((cx, y, cz), (0.13, 0.03, 1.15), yaw)
                s += 0.2
            for off in (-0.42, 0.42):
                cx, cz = ax + ux * L / 2 - uz * off, az + uz * L / 2 + ux * off
                y = -(dep[i] + dep[i + 1]) / 2 + 0.01
                boards.at(cx, cz).box((cx, y, cz), (L - 0.2, 0.04, 0.07), yaw)
    planks.finish(), backing.finish(), posts.finish(), col.finish(), boards.finish()


def build_exits(m_planks):
    steps = Cells("Steps", m_planks)
    for a, b, dep in EXITS:
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        ux, uz = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        yaw = math.atan2(-uz, ux)
        s = WALL + 0.15
        while s < L - 0.2:
            x, z = a[0] + ux * s, a[1] + uz * s
            y = float(height(np.array(x), np.array(z))) + 0.04
            steps.at(x, z).box((x, y, z), (0.24, 0.05, 1.2), yaw)
            s += 0.38
    return steps.finish()


def build_roofs(m_logs, m_mud):
    logs = Cells("Logs", m_logs)
    mounds = Cells("Mounds", m_mud)
    col = Cells("C_Roofs", m_mud)
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
            logs.at(cx, cz).cyl((cx + uz * w, top, cz - ux * w), (cx - uz * w, top + random.uniform(-0.03, 0.03), cz + ux * w), r, 8)
            s += 0.25
        mid = (t0 + t1) / 2 * L
        cx, cz = a[0] + ux * mid, a[1] + uz * mid
        top = float(base_height(np.array(cx), np.array(cz))) + 0.14
        span = (t1 - t0) * L
        mounds.at(cx, cz).box((cx, top + 0.2, cz), (span, 0.3, 2.6), yaw)
        mounds.at(cx, cz).box((cx, top + 0.38, cz), (span - 0.4, 0.2, 1.9), yaw)
        col.at(cx, cz).box((cx, top + 0.14, cz), (span, 0.5, 3.2), yaw)
    logs.finish(), mounds.finish(True), col.finish()


def build_sandbags(m_bag):
    bags = Cells("Sandbags", m_bag)
    for pts, toward in ((TRENCHES[FRONTS[0]][0], -1.0), (TRENCHES[FRONTS[1]][0], 1.0)):
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
                    bags.at(x, z).box((x, y, z), (0.48, 0.16, 0.3), yaw + random.uniform(-0.08, 0.08))
                    s += 0.5
    for ob in bags.finish():
        mod = ob.modifiers.new("bevel", "BEVEL")
        mod.width = 0.05
        mod.segments = 2
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier="bevel")


def build_wire(m_post, m_wire):
    stakes = Cells("WireStakes", m_post)
    wire = Cells("Wire", m_wire)
    for z0 in (-14.0, 14.0):
        x = -146.0
        prev = None
        while x < 48.0:
            z = z0 + random.uniform(-1.0, 1.0)
            if any(math.hypot(x - c[0], z - c[1]) < c[2] for c in CRATERS) or random.random() < 0.12 or in_pad(x, z):
                x += random.uniform(2.5, 4.0)
                prev = None
                continue
            y = float(height(np.array(x), np.array(z)))
            lean = random.uniform(-0.15, 0.15)
            top = (x + lean, y + 1.05, z)
            stakes.at(x, z).cyl((x, y - 0.2, z), top, 0.035)
            if prev:
                for k in range(3):
                    f = 0.3 + k * 0.33
                    pa = (prev[0][0], prev[1] + (prev[0][1] - prev[1]) * f, prev[0][2])
                    pb = (top[0], y + (top[1] - y) * f, top[2])
                    wire.at(x, z).cyl(pa, pb, 0.007, 4)
                pa = prev[0]
                wire.at(x, z).cyl(pa, (x, y + 0.2, z), 0.007, 4)
            prev = (top, y)
            x += random.uniform(2.5, 3.5)
    stakes.finish(), wire.finish()


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
    while len(placed) < 300 and tries < 20000:
        tries += 1
        x, z = random.uniform(X0 + 3, X1 - 3), random.uniform(Z0 + 3, Z1 - 3)
        d, _ = trench_field(np.array(x), np.array(z))
        if float(d) < 3.2 or any(math.hypot(x - c[0], z - c[1]) < c[2] + 0.5 for c in CRATERS):
            continue
        if in_pad(x, z, 2.5) or float(road_dist(np.array(x), np.array(z))) < 3.0:
            continue
        if abs(z) < 22 and random.random() < 0.6:  # no-man's land: fewer, shattered
            continue
        if in_town(x, z) and random.random() < 0.7:
            continue
        if any(math.hypot(x - p[0], z - p[1]) < 3.0 for p in placed):
            continue
        y = float(height(np.array(x), np.array(z)))
        src = random.choice(variants)
        ob = bpy.data.objects.new("Tree%d" % len(placed), src.data)
        bpy.context.scene.collection.objects.link(ob)
        sc = random.uniform(0.8, 1.25) * (0.6 if abs(z) < 22 else 1.0)
        ob.matrix_world = Matrix.Translation(gv(x, y, z)) @ Matrix.Rotation(random.uniform(0, 6.28), 4, "Z") \
            @ Matrix.Scale(sc, 4)
        placed.append((x, z))
    for v in variants:
        bpy.data.objects.remove(v)
    print("trees", len(placed))


def empty(name, x, z, yaw=0.0, y=None):
    ob = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(ob)
    if y is None:
        y = float(height(np.array(x), np.array(z))) + 0.05
    ob.matrix_world = Matrix.Translation(gv(x, y, z)) @ (C @ Matrix.Rotation(yaw, 3, "Y") @ C.transposed()).to_4x4()


def empties():
    for side in (0, 1):
        front, rear = TRENCHES[FRONTS[side]][0], TRENCHES[REARS[side]][0]
        tag = "AB"[side]
        k = 0
        for i in range(len(rear) - 1):
            for t in (0.3, 0.7):
                x = rear[i][0] + (rear[i + 1][0] - rear[i][0]) * t
                z = rear[i][1] + (rear[i + 1][1] - rear[i][1]) * t
                empty("Spawn%s_%d" % (tag, k), x, z)
                k += 1
        # the town sector: behind each block, out of the enemy's sight
        sgn = 1.0 if side == 0 else -1.0
        for x in (72.0, 84.0, 97.0, 110.0, 122.0):
            empty("Spawn%s_%d" % (tag, k), x, sgn * 42.0)
            k += 1
        k = 0
        for i in range(len(front) - 1):
            for t in (0.25, 0.5, 0.75):
                x = front[i][0] + (front[i + 1][0] - front[i][0]) * t
                z = front[i][1] + (front[i + 1][1] - front[i][1]) * t
                empty("Post%s_%d" % (tag, k), x, z)
                k += 1
    for k, b in enumerate(BUILDINGS):
        name, x, z, yaw = b
        side = "N" if abs(z) < 10 else ("A" if z > 0 else "B")
        empty("B_%s_%s_%d" % (name, side, k), x, z, yaw, PAD_Y[b])
    f = TRENCHES[FRONTS[0]][0]
    a = nearest(f, -8.0)
    b = f[f.index(a) + 1]
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
