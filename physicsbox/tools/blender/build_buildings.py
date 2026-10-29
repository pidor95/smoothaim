"""Builds the buildings of the front in Blender, exported as
assets/maps/buildings.glb. Each building is a prototype: an empty "P_<Name>"
at the origin with its meshes, collision and markers as children; the map
(build_trenches.py) only places them, the game instances them
(trench_level.gd).

Run:  blender -b --python tools/blender/build_buildings.py

Prototypes (Godot axes: +Y up, the front faces -Z, centred on the origin
along X; local ground at y = 0):
  Panel5     five-storey panel block ("khrushchevka", like in the user's
             video): three entrances with canopies, a stairwell in each
             (flights and landings you can climb, windows between floors,
             green-painted walls), two flats per landing plus a room behind
             it, windows with frames and radiators, balconies at the back,
             the yellow gas pipe along the front, flat roof with a parapet
  HouseBrick one-storey brick house: broken roof, rubble, gaping windows
  HouseWood  wooden village house: plank walls, sagging roof with a hole
  Ruin2      two-storey brick ruin, one corner collapsed, stairs inside
  Garages    a row of brick garages, some doors hanging open
  CarWreck   a burnt-out car
Children of a prototype:
  <Mat>__<Name>       visible meshes; <Mat> picks the game's material
  C__<Name>           collision only (static, walkable: slabs, ramps on
                      stairs, walls, furniture)
  Glass__<Name>_<k>   empties: window panes (scale x = width, y = height)
  Door__<Name>_<k>    empties: hinged door leaves (scale x/y = size,
                      hinge on the -X edge)
  Post__<Name>_<k>    empties: firing positions (soldiers stand here)
"""
import math
import os
import random

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "maps", "buildings.glb")
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))  # Godot -> Blender axes
random.seed(1961)

COLORS = {
    "Panel": (0.62, 0.62, 0.6), "Plinth": (0.42, 0.41, 0.4), "Plaster": (0.62, 0.72, 0.66),
    "Paint": (0.16, 0.42, 0.38), "Whitewash": (0.85, 0.85, 0.82), "Lino": (0.55, 0.32, 0.18),
    "Concrete": (0.55, 0.55, 0.54), "Frame": (0.86, 0.86, 0.84), "Metal": (0.22, 0.23, 0.24),
    "Pipe": (0.9, 0.72, 0.1), "Roof": (0.2, 0.2, 0.21), "Brick": (0.55, 0.27, 0.19),
    "Planks": (0.45, 0.35, 0.25), "Slate": (0.42, 0.46, 0.44), "Rubble": (0.5, 0.42, 0.38),
    "Rust": (0.3, 0.17, 0.1), "Wood": (0.4, 0.26, 0.16), "Fabric": (0.3, 0.32, 0.38),
}


def gv(x, y, z):
    return C @ Vector((x, y, z))


def rot_y(yaw):
    return (C @ Matrix.Rotation(yaw, 3, "Y") @ C.transposed()).to_4x4()


class MB:
    """bmesh being assembled from primitives in Godot coordinates."""

    def __init__(self):
        self.bm = bmesh.new()

    def box(self, c, s, yaw=0.0, pitch=0.0, roll=0.0):
        r = Matrix.Rotation(yaw, 3, "Y") @ Matrix.Rotation(pitch, 3, "X") @ Matrix.Rotation(roll, 3, "Z")
        m = Matrix.Translation(gv(*c)) @ (C @ r @ C.transposed()).to_4x4() @ Matrix.Diagonal((s[0], s[2], s[1], 1))
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)

    def span(self, a, b, y0, y1, t):
        """Wall between floor points a, b (x, z) from y0 to y1, thickness t."""
        dx, dz = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dz)
        self.box(((a[0] + b[0]) / 2, (y0 + y1) / 2, (a[1] + b[1]) / 2), (L, y1 - y0, t), math.atan2(-dz, dx))

    def hull(self, pts):
        vs = [self.bm.verts.new(gv(*p)) for p in pts]
        bmesh.ops.convex_hull(self.bm, input=vs)

    def cyl(self, a, b, r, segs=8):
        a, b = gv(*a), gv(*b)
        d = b - a
        m = Matrix.Translation((a + b) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        bmesh.ops.create_cone(self.bm, cap_ends=True, segments=segs, radius1=r, radius2=r, depth=d.length, matrix=m)


class Proto:
    """One building: meshes by material, a collision mesh and markers."""

    def __init__(self, name):
        self.name = name
        self.parts = {}
        self.col = MB()
        self.markers = []  # [kind, pos, yaw, (sx, sy)]

    def mb(self, mat):
        if mat not in self.parts:
            self.parts[mat] = MB()
        return self.parts[mat]

    def solid(self, mat, c, s, yaw=0.0):
        """Visible and collidable box."""
        self.mb(mat).box(c, s, yaw)
        self.col.box(c, s, yaw)

    def deco(self, mat, c, s, yaw=0.0, pitch=0.0, roll=0.0):
        self.mb(mat).box(c, s, yaw, pitch, roll)

    def marker(self, kind, pos, yaw=0.0, size=(1.0, 1.0)):
        self.markers.append([kind, pos, yaw, size])

    # -------------------------------------------------- walls with openings

    def wall(self, axis, fixed, a, b, y0, y1, t, mat, openings=(), inner_mat=None):
        """Axis-aligned wall: along X (axis "x", at z = fixed) or along Z.
        openings: (from, to, bottom, top, kind) along the wall, kind
        "window" / "door" / "hole" / "glass" (window with a pane) /
        "doorleaf" (door with a hinged leaf)."""
        def seg(s, e, lo, hi):
            if e - s < 0.01 or hi - lo < 0.01:
                return
            c = ((s + e) / 2, (lo + hi) / 2, fixed) if axis == "x" else (fixed, (lo + hi) / 2, (s + e) / 2)
            size = (e - s, hi - lo, t) if axis == "x" else (t, hi - lo, e - s)
            self.solid(mat, c, size)
        # openings stacked in the same column (windows floor above floor)
        # share one gap in the wall, filled between them
        cols = {}
        for o in openings:
            cols.setdefault((o[0], o[1]), []).append(o[2:])
        cur = a
        for (s, e) in sorted(cols):
            seg(cur, s, y0, y1)
            lo_prev = y0
            for lo, hi, kind in sorted(cols[(s, e)]):
                seg(s, e, lo_prev, lo)
                lo_prev = hi
                mid = (s + e) / 2
                if kind in ("window", "glass"):
                    self.window_frame(axis, fixed, s, e, lo, hi, t)
                    if kind == "glass":
                        pos = (mid, (lo + hi) / 2, fixed) if axis == "x" else (fixed, (lo + hi) / 2, mid)
                        self.marker("Glass", pos, 0.0 if axis == "x" else math.pi / 2, (e - s - 0.12, hi - lo - 0.12))
                elif kind == "doorleaf":
                    pos = (mid, (lo + hi) / 2, fixed) if axis == "x" else (fixed, (lo + hi) / 2, mid)
                    self.marker("Door", pos, 0.0 if axis == "x" else math.pi / 2, (e - s - 0.06, hi - lo - 0.04))
            seg(s, e, lo_prev, y1)
            cur = e
        seg(cur, b, y0, y1)

    def window_frame(self, axis, fixed, s, e, lo, hi, t):
        w = 0.06
        mid = (s + e) / 2
        for c, size in (((mid, lo + w / 2), (e - s, w)), ((mid, hi - w / 2), (e - s, w)),
                        ((s + w / 2, (lo + hi) / 2), (w, hi - lo)), ((e - w / 2, (lo + hi) / 2), (w, hi - lo)),
                        ((mid, (lo + hi) / 2), (w * 0.8, hi - lo))):
            p = (c[0], c[1], fixed) if axis == "x" else (fixed, c[1], c[0])
            sz = (size[0], size[1], 0.08) if axis == "x" else (0.08, size[1], size[0])
            self.deco("Frame", p, sz)

    # -------------------------------------------------- stairs

    def flight(self, x0, x1, z0, y0, z1, y1, mat="Concrete"):
        """Straight flight in a lane x0..x1 from (z0, y0) to (z1, y1): steps
        to look at, a smooth ramp to walk on."""
        n = max(int(round(abs(y1 - y0) / 0.17)), 1)
        dz = (z1 - z0) / n
        dy = (y1 - y0) / n
        for k in range(n):
            top = y0 + dy * (k + 1)
            zc = z0 + dz * (k + 0.5)
            self.deco(mat, ((x0 + x1) / 2, top - 0.09, zc), (x1 - x0, 0.18, abs(dz) + 0.01))
        # the underside slab
        self.deco(mat, ((x0 + x1) / 2, (y0 + y1) / 2 - 0.25, (z0 + z1) / 2), (x1 - x0, 0.12, math.hypot(z1 - z0, y1 - y0)),
                  pitch=math.atan2(y1 - y0, -(z1 - z0)) if z1 < z0 else -math.atan2(y1 - y0, z1 - z0))
        pts = []
        for x in (x0, x1):
            for z, y in ((z0, y0), (z1, y1)):
                pts += [(x, y + 0.01, z), (x, y - 0.12, z)]
        self.col.hull(pts)

    # -------------------------------------------------- export

    def finish(self, root_coll):
        parent = bpy.data.objects.new("P_" + self.name, None)
        root_coll.objects.link(parent)
        objs = []
        for mat, mb in self.parts.items():
            objs.append(self._mesh("%s__%s" % (mat, self.name), mb, mat, parent, root_coll))
        self._mesh("C__" + self.name, self.col, "Concrete", parent, root_coll)
        counts = {}
        for kind, pos, yaw, size in self.markers:
            k = counts.get(kind, 0)
            counts[kind] = k + 1
            e = bpy.data.objects.new("%s__%s_%d" % (kind, self.name, k), None)
            root_coll.objects.link(e)
            e.parent = parent
            e.matrix_world = Matrix.Translation(gv(*pos)) @ rot_y(yaw) @ Matrix.Diagonal((size[0], 1.0, size[1], 1.0))
        print("PROTO", self.name, "markers", counts, "faces",
              sum(len(o.data.polygons) for o in objs))
        return parent

    def _mesh(self, name, mb, mat, parent, coll):
        me = bpy.data.meshes.new(name)
        bmesh.ops.remove_doubles(mb.bm, verts=mb.bm.verts, dist=0.0005)
        mb.bm.to_mesh(me)
        mb.bm.free()
        ob = bpy.data.objects.new(name, me)
        coll.objects.link(ob)
        ob.parent = parent
        me.materials.append(material(mat))
        return ob


_mats = {}


def material(name):
    if name not in _mats:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*COLORS.get(name, (0.5, 0.5, 0.5)), 1)
        _mats[name] = m
    return _mats[name]


def rubble(p, cx, cz, r, h, n, y0=0.0, mat="Rubble"):
    """A heap of broken pieces (visible and collidable as a low mound)."""
    for _ in range(n):
        a = random.uniform(0, math.tau)
        d = random.uniform(0, r) ** 0.8
        x, z = cx + math.cos(a) * d, cz + math.sin(a) * d
        top = h * (1 - (d / r) ** 2)
        s = random.uniform(0.25, 0.7)
        p.deco(mat, (x, y0 + top * 0.6, z), (s, random.uniform(0.15, 0.4), s * random.uniform(0.5, 1.2)),
               random.uniform(0, 3), random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5))
    pts = []
    for k in range(10):
        a = k / 10 * math.tau
        pts.append((cx + math.cos(a) * r, y0, cz + math.sin(a) * r))
    pts.append((cx, y0 + h * 0.75, cz))
    p.col.hull(pts)


def furniture(p, x0, x1, z0, z1, y, wall_side):
    """A few pieces in a room: a wardrobe against a wall, a table, a bed."""
    r = random.random()
    if r < 0.35:
        p.solid("Wood", (x0 + 0.35, y + 0.95, (z0 + z1) / 2), (0.6, 1.9, 1.1))
    if random.random() < 0.5:
        x, z = random.uniform(x0 + 1.0, x1 - 1.0), random.uniform(z0 + 1.2, z1 - 1.2)
        p.solid("Wood", (x, y + 0.72, z), (1.1, 0.06, 0.7), random.uniform(0, 3))
        for sx in (-0.45, 0.45):
            for sz in (-0.28, 0.28):
                p.deco("Wood", (x + sx, y + 0.35, z + sz), (0.05, 0.7, 0.05))
    if random.random() < 0.35:
        p.solid("Fabric", (x1 - 0.5, y + 0.25, z1 - 1.1), (0.9, 0.5, 1.9))


# ================================================================ Panel5

SECTION = 12.0
DEPTH = 11.0
FLOOR0 = 0.9
FH = 2.8
FLOORS = 5
T_OUT = 0.3


def floor_y(f):
    return FLOOR0 + FH * f


def build_panel5():
    p = Proto("Panel5")
    xs = [(-1 + k) * SECTION for k in range(3)]  # section centres
    X0, X1 = -SECTION * 1.5, SECTION * 1.5
    top = floor_y(FLOORS)
    zf0, zf1 = 0.0, T_OUT  # front wall
    zb0, zb1 = DEPTH - T_OUT, DEPTH  # back wall

    # plinth (solid under the ground floor) with lobbies cut out, vents
    # slabs stop inside the outer walls (no faces flush with the facade)
    def cx(a, b):
        return max(a, X0 + 0.15), min(b, X1 - 0.15)
    zi0, zi1 = 0.15, DEPTH - 0.15
    for sx in xs:
        for a, b in ((sx - 6, sx - 1.3), (sx + 1.3, sx + 6)):
            a, b = cx(a, b)
            p.solid("Plinth", ((a + b) / 2, FLOOR0 / 2, (zi0 + zi1) / 2), (b - a, FLOOR0, zi1 - zi0))
        p.solid("Plinth", (sx, FLOOR0 / 2, (3.8 + zi1) / 2), (2.6, FLOOR0, zi1 - 3.8))
        p.solid("Concrete", (sx, -0.1, (zi0 + 3.8) / 2), (2.6, 0.2, 3.8 - zi0))  # lobby floor at the ground
        for vx in (sx - 3.6, sx + 3.6):
            p.deco("Metal", (vx, 0.45, -0.01), (0.5, 0.25, 0.04))
    # floors 1.. (slabs with the stairwell shafts open) and the roof
    for f in range(1, FLOORS + 1):
        y = floor_y(f)
        for sx in xs:
            for a, b in ((sx - 6, sx - 1.2), (sx + 1.2, sx + 6)):
                a, b = cx(a, b)
                p.solid("Concrete", ((a + b) / 2, y - 0.1, (zi0 + zi1) / 2), (b - a, 0.2, zi1 - zi0))
            p.solid("Concrete", (sx, y - 0.1, (3.8 + zi1) / 2), (2.4, 0.2, zi1 - 3.8))
            if f < FLOORS:
                # flats: linoleum on top
                for a, b in ((sx - 5.9, sx - 1.4), (sx + 1.4, sx + 5.9)):
                    p.deco("Lino", ((a + b) / 2, y + 0.005, DEPTH / 2), (b - a, 0.01, DEPTH - 0.7))
    for sx in xs:
        for a, b in ((sx - 5.9, sx - 1.4), (sx + 1.4, sx + 5.9)):
            p.deco("Lino", ((a + b) / 2, FLOOR0 + 0.005, DEPTH / 2), (b - a, 0.01, DEPTH - 0.7))
    p.solid("Concrete", (0, top - 0.1, (zi0 + 3.8) / 2), (X1 - X0 - 0.3, 0.2, 3.8 - zi0))  # roof over the stairwells
    p.solid("Roof", (0, top + 0.02, DEPTH / 2), (X1 - X0 + 0.2, 0.06, DEPTH + 0.2))
    for z in (-0.05, DEPTH + 0.05):
        p.solid("Panel", (0, top + 0.35, z), (X1 - X0 + 0.3, 0.7, 0.2))
    for x in (X0 - 0.05, X1 + 0.05):
        p.solid("Panel", (x, top + 0.35, DEPTH / 2), (0.2, 0.7, DEPTH + 0.3))
    for sx in xs:  # roof exits
        p.solid("Panel", (sx, top + 1.0, 4.5), (1.6, 2.0, 1.6))

    win_front = []
    for sx in xs:
        # ---------------- stairwell
        for f in range(FLOORS - 1):
            y = floor_y(f)
            mid = y + FH / 2
            p.solid("Concrete", (sx, mid - 0.075, 0.75), (2.4, 0.15, 0.9))  # mid landing
            p.flight(sx + 0.05, sx + 1.2, 3.8, y, 1.2, mid)
            p.flight(sx - 1.2, sx - 0.05, 1.2, mid, 3.8, y + FH)
            for k, (a, b) in enumerate(((sx + 0.05, sx + 1.2), (sx - 1.2, sx - 0.05))):
                # handrail between the flights
                z0, y0, z1, y1 = (3.8, y, 1.2, mid) if k == 0 else (1.2, mid, 3.8, y + FH)
                rx = sx + (0.08 if k == 0 else -0.08)
                p.mb("Metal").cyl((rx, y0 + 0.95, z0), (rx, y1 + 0.95, z1), 0.022, 6)
                for t in (0.15, 0.5, 0.85):
                    zz, yy = z0 + (z1 - z0) * t, y0 + (y1 - y0) * t
                    p.mb("Metal").cyl((rx, yy, zz), (rx, yy + 0.95, zz), 0.012, 4)
        p.flight(sx - 1.2, sx - 0.05, 1.2, 0.0, 3.8, FLOOR0)  # lobby up to the ground floor
        # stairwell side walls with the flat doors, back wall with the third
        for side in (-1, 1):
            x = sx + side * 1.3
            ops = [(4.15, 5.15, floor_y(f), floor_y(f) + 2.05, "doorleaf" if random.random() < 0.6 else "door")
                   for f in range(FLOORS)]
            p.wall("z", x, T_OUT, 5.5, 0.0, top, 0.15, "Whitewash", ops)
            # the green-painted lower half on the stairwell side
            for f in range(-1, FLOORS):
                y = floor_y(f) if f >= 0 else 0.0
                for z0, z1 in ((T_OUT, 4.15), (5.15, 5.43)):
                    p.deco("Paint", (x - side * 0.08, y + 0.75, (z0 + z1) / 2), (0.01, 1.5, z1 - z0))
        ops = [(sx - 0.5, sx + 0.5, floor_y(f), floor_y(f) + 2.05, "doorleaf" if random.random() < 0.5 else "door")
               for f in range(FLOORS)]
        p.wall("x", 5.5, sx - 1.225, sx + 1.225, FLOOR0, top, 0.15, "Whitewash", ops)
        # canopy over the entrance on two posts, a bench
        p.solid("Concrete", (sx, 2.62, -0.75), (2.6, 0.14, 1.5))
        for px in (sx - 1.15, sx + 1.15):
            p.mb("Metal").cyl((px, 0.0, -1.4), (px, 2.55, -1.4), 0.04, 6)
        if random.random() < 0.6:
            p.solid("Wood", (sx + 2.6, 0.42, -1.2), (1.6, 0.08, 0.4))
        # ---------------- flats: partitions, rooms, windows
        for side in (-1, 1):
            a, b = sorted((sx + side * 1.3, sx + side * 6.0))
            for f in range(FLOORS):
                y = floor_y(f)
                door_c = sx + side * 3.4
                p.wall("x", 5.5, a + 0.08, b - 0.1, y, y + FH - 0.2, 0.12, "Plaster",
                       [(door_c - 0.5, door_c + 0.5, y, y + 2.05, "hole")])
                p.deco("Whitewash", ((a + b) / 2, y + FH - 0.205, DEPTH / 2), (b - a, 0.01, DEPTH - 0.6))
                for z0, z1 in ((T_OUT, 5.44), (5.56, DEPTH - T_OUT)):
                    furniture(p, a + 0.15, b - 0.15, z0 + 0.1, z1 - 0.1, y, side)
                    # radiator under the window
                    zz = z0 + 0.12 if z0 < 1 else z1 - 0.12
                    p.deco("Whitewash", ((a + b) / 2, y + 0.45, zz), (1.0, 0.55, 0.08))
                if f < FLOORS - 1:
                    win_front.append(((a + b) / 2, y))
        # the room behind the stairwell opens into the right-hand flat
        for f in range(FLOORS):
            y = floor_y(f)
            p.wall("z", sx + 1.3, 5.6, DEPTH - T_OUT, y, y + FH - 0.2, 0.12, "Plaster",
                   [(8.0, 9.0, y, y + 2.05, "hole")])
            p.wall("z", sx - 1.3, 5.6, DEPTH - T_OUT, y, y + FH - 0.2, 0.12, "Plaster")
        # walls between the sections
        for x in (sx - 6.0, sx + 6.0):
            if X0 < x < X1:
                p.wall("z", x, T_OUT, DEPTH - T_OUT, FLOOR0, top, 0.2, "Plaster")

    # ---------------- facades
    def windows(sx, front):
        ops = []
        for f in range(FLOORS):
            y = floor_y(f)
            for c in (sx - 3.65, sx + 3.65):
                kind = "glass" if random.random() < 0.38 else "window"
                ops.append((c - 0.7, c + 0.7, y + 0.85, y + 2.3, kind))
            if not front:
                kind = "glass" if random.random() < 0.38 else "window"
                ops.append((sx - 0.55, sx + 0.55, y + 0.85, y + 2.3, kind))
        if front:
            ops.append((sx - 0.7, sx + 0.7, 0.0, 2.15, "doorleaf" if random.random() < 0.7 else "door"))
            for f in range(FLOORS - 1):
                y = floor_y(f) + FH / 2
                ops.append((sx - 0.7, sx + 0.7, y + 0.9, y + 2.1, "glass" if random.random() < 0.3 else "window"))
        return ops

    for sx in xs:
        a, b = sx - SECTION / 2, sx + SECTION / 2
        p.wall("x", T_OUT / 2, a, b, 0.0, top, T_OUT, "Panel", windows(sx, True))
        p.wall("x", DEPTH - T_OUT / 2, a, b, 0.0, top, T_OUT, "Panel", windows(sx, False))
        # panel seams
        for f in range(1, FLOORS):
            p.deco("Plinth", ((a + b) / 2, floor_y(f) - 0.1, -0.005), (SECTION, 0.04, 0.02))
        # balconies at the back
        for f in range(1, FLOORS):
            y = floor_y(f)
            for c in (sx - 3.65, sx + 3.65):
                if random.random() < 0.7:
                    p.solid("Concrete", (c, y - 0.08, DEPTH + 0.6), (2.6, 0.16, 1.2))
                    p.solid("Panel", (c, y + 0.5, DEPTH + 1.17), (2.6, 1.0, 0.06))
                    for x in (c - 1.28, c + 1.28):
                        p.solid("Panel", (x, y + 0.5, DEPTH + 0.6), (0.06, 1.0, 1.2))
    for x, t in ((X0 + T_OUT / 2, -1), (X1 - T_OUT / 2, 1)):
        ops = [(4.8, 6.2, floor_y(f) + 1.0, floor_y(f) + 2.0, "window") for f in range(FLOORS) if f % 2 == 1]
        p.wall("z", x, 0.0, DEPTH, 0.0, top, T_OUT, "Panel", ops)
    # the yellow gas pipe along the front, with drops to the ground
    py = floor_y(1) - 0.35
    p.mb("Pipe").cyl((X0 + 0.3, py, -0.14), (X1 - 0.3, py, -0.14), 0.045, 8)
    for x in (X0 + 0.3, X1 - 0.3, -SECTION / 2 + 2.0, SECTION / 2 - 2.0):
        p.mb("Pipe").cyl((x, 0.0, -0.14), (x, py, -0.14), 0.045, 8)
        p.mb("Pipe").cyl((x, py, -0.14), (x, py, 0.0), 0.045, 8)
    # firing positions: behind the front windows of the lower floors
    for x, y in win_front:
        p.marker("Post", (x, y + 0.05, 1.3))
    return p


# ================================================================ small houses

def house_brick():
    p = Proto("HouseBrick")
    W, D, H, Y0 = 8.0, 7.0, 3.0, 0.3
    hw, hd = W / 2, D / 2
    p.solid("Concrete", (0, Y0 / 2, 0), (W, Y0, D))
    p.solid("Concrete", (-2.1, 0.08, -hd - 0.4), (1.2, 0.16, 0.8))  # step
    t = 0.38
    p.wall("x", -hd + t / 2, -hw, hw, Y0, Y0 + H, t, "Brick",
           [(-2.6, -1.6, Y0, Y0 + 2.1, "hole"), (0.4, 1.8, Y0 + 0.9, Y0 + 2.2, "window"),
            (2.6, 3.4, Y0 + 0.9, Y0 + 2.2, "window")])
    # the back wall half fallen in: jagged top over a heap
    p.wall("x", hd - t / 2, -hw, 0.5, Y0, Y0 + H, t, "Brick", [(-3.0, -1.8, Y0 + 0.9, Y0 + 2.2, "window")])
    for k in range(7):
        x = 0.5 + k * 0.5
        p.solid("Brick", (x + 0.25, Y0 + (H - 0.3 - k * 0.32) / 2, hd - t / 2), (0.5, max(H - 0.3 - k * 0.32, 0.3), t))
    rubble(p, 2.2, hd - 0.4, 1.8, 1.0, 26, Y0)
    rubble(p, 2.6, hd + 1.2, 1.4, 0.6, 14, 0.0)
    for x, ops in ((-hw + t / 2, [(-1.0, 0.4, Y0 + 0.9, Y0 + 2.2, "window")]),
                   (hw - t / 2, [(-0.4, 1.0, Y0 + 0.9, Y0 + 2.2, "window")])):
        p.wall("z", x, -hd + t, hd - t, Y0, Y0 + H, t, "Brick", ops)
        # gables
        p.mb("Brick").hull([(x - t / 2, Y0 + H, -hd), (x + t / 2, Y0 + H, -hd), (x - t / 2, Y0 + H, hd),
                             (x + t / 2, Y0 + H, hd), (x - t / 2, Y0 + H + 1.7, 0), (x + t / 2, Y0 + H + 1.7, 0)])
    p.wall("z", 0.8, -hd + t, hd - t, Y0, Y0 + H, 0.15, "Whitewash", [(-0.5, 0.4, Y0, Y0 + 2.0, "hole")])
    # roof: the front slope whole, the back one mostly gone - bare rafters
    pitch = math.atan2(1.7, hd + 0.4)
    L = math.hypot(1.7, hd + 0.4)
    p.mb("Slate").box((0, Y0 + H + 0.85, -(hd + 0.4) / 2), (W + 0.6, 0.08, L), 0.0, -pitch)
    p.mb("Slate").box((-2.6, Y0 + H + 0.85, (hd + 0.4) / 2), (3.4, 0.08, L), 0.0, pitch)
    for k in range(9):
        x = -hw + 0.3 + k * 0.95
        p.mb("Wood").box((x, Y0 + H + 0.8, (hd + 0.4) / 2), (0.1, 0.12, L), 0.0, pitch)
    p.col.box((0, Y0 + H + 0.85, -(hd + 0.4) / 2), (W + 0.6, 0.08, L), 0.0, -pitch)
    p.col.box((-2.6, Y0 + H + 0.85, (hd + 0.4) / 2), (3.4, 0.08, L), 0.0, pitch)
    furniture(p, -hw + 0.5, 0.6, -hd + 0.5, hd - 0.5, Y0, 1)
    p.marker("Post", (1.1, Y0 + 0.05, -hd + 1.1))
    p.marker("Post", (3.0, Y0 + 0.05, -hd + 1.1))
    return p


def house_wood():
    p = Proto("HouseWood")
    W, D, H, Y0 = 7.0, 6.0, 2.7, 0.4
    hw, hd = W / 2, D / 2
    p.solid("Wood", (0, Y0 / 2, 0), (W, Y0, D))
    p.solid("Wood", (-1.8, Y0 / 2, -hd - 0.9), (2.4, Y0, 1.8))  # porch
    for x in (-2.9, -0.7):
        p.mb("Wood").cyl((x, Y0, -hd - 1.7), (x, Y0 + 2.3, -hd - 1.7), 0.07, 6)
    t = 0.2
    p.wall("x", -hd + t / 2, -hw, hw, Y0, Y0 + H, t, "Planks",
           [(-2.2, -1.3, Y0, Y0 + 2.0, "hole"), (0.6, 1.8, Y0 + 0.8, Y0 + 1.9, "window")])
    p.wall("x", hd - t / 2, -hw, hw, Y0, Y0 + H, t, "Planks",
           [(-2.0, -0.8, Y0 + 0.8, Y0 + 1.9, "window"), (1.2, 2.2, Y0 + 0.5, Y0 + 1.6, "hole")])
    for x in (-hw + t / 2, hw - t / 2):
        p.wall("z", x, -hd + t, hd - t, Y0, Y0 + H, t, "Planks", [(-0.6, 0.6, Y0 + 0.8, Y0 + 1.9, "window")])
        p.mb("Planks").hull([(x - t / 2, Y0 + H, -hd), (x + t / 2, Y0 + H, -hd), (x - t / 2, Y0 + H, hd),
                              (x + t / 2, Y0 + H, hd), (x - t / 2, Y0 + H + 1.6, 0), (x + t / 2, Y0 + H + 1.6, 0)])
    p.wall("x", 0.6, -hw + t, hw - t, Y0, Y0 + H, 0.12, "Planks", [(-0.6, 0.4, Y0, Y0 + 2.0, "hole")])
    pitch = math.atan2(1.6, hd + 0.5)
    L = math.hypot(1.6, hd + 0.5)
    for s in (-1, 1):
        # the roof sags, the back slope has a hole torn in it
        segs = [(-hw - 0.3, hw + 0.3)] if s < 0 else [(-hw - 0.3, -0.6), (1.4, hw + 0.3)]
        for a, b in segs:
            p.mb("Slate").box(((a + b) / 2, Y0 + H + 0.8, s * (hd + 0.5) / 2), (b - a, 0.06, L), 0.0, s * pitch,
                              random.uniform(-0.03, 0.03))
            p.col.box(((a + b) / 2, Y0 + H + 0.8, s * (hd + 0.5) / 2), (b - a, 0.06, L), 0.0, s * pitch)
    rubble(p, 0.4, 1.6, 1.0, 0.4, 10, Y0, "Planks")
    furniture(p, -hw + 0.4, -0.6, -hd + 0.4, 0.4, Y0, 1)
    p.marker("Post", (1.2, Y0 + 0.05, -hd + 0.9))
    return p


def ruin2():
    p = Proto("Ruin2")
    W, D, H, Y0 = 14.0, 9.0, 3.1, 0.1
    hw, hd = W / 2, D / 2
    t = 0.4
    p.solid("Concrete", (0, Y0 / 2, 0), (W, Y0, D))
    y1 = Y0 + H  # first floor level
    # upper floor slab with the collapsed corner (x > 3, z < 0) missing and the stair hole
    p.solid("Concrete", (-4.0, y1 - 0.1, 0), (6.0, 0.2, D))
    p.solid("Concrete", (0.0 + 0.0, y1 - 0.1, 2.6), (2.0, 0.2, 3.8))
    p.solid("Concrete", (2.0, y1 - 0.1, 0.0), (2.0, 0.2, D))
    p.solid("Concrete", (5.0, y1 - 0.1, 2.25), (4.0, 0.2, 4.5))
    # stairs along the inside of the front wall (x -1..1 lane, z -hd+t .. 0.7)
    p.flight(-0.98, 0.98, -hd + t + 0.1, Y0, 0.7, y1)
    lo_ops = [(-6.0, -4.6, Y0 + 0.9, Y0 + 2.2, "window"), (-3.4, -2.0, Y0 + 0.9, Y0 + 2.2, "window"),
              (1.6, 2.6, Y0, Y0 + 2.2, "hole"), (4.0, 5.4, Y0 + 0.9, Y0 + 2.2, "window")]
    up_ops = [(-6.0, -4.6, y1 + 0.9, y1 + 2.2, "window"), (-3.4, -2.0, y1 + 0.9, y1 + 2.2, "window"),
              (0.0, 1.4, y1 + 0.9, y1 + 2.2, "window")]
    p.wall("x", -hd + t / 2, -hw, 3.0, Y0, y1 + H, t, "Brick", [o for o in lo_ops + up_ops if o[1] <= 3.0])
    p.wall("x", -hd + t / 2, 3.0, hw, Y0, Y0 + 1.4, t, "Brick")
    for k in range(6):  # broken edge stepping down
        x = 3.0 + k * 0.4
        h = max(y1 + H - Y0 - (k + 1) * 0.95, 0.4)
        p.solid("Brick", (x + 0.2, Y0 + h / 2, -hd + t / 2), (0.4, h, t))
    p.wall("x", hd - t / 2, -hw, hw, Y0, y1 + H, t, "Brick",
           [(-5.0, -3.6, Y0 + 0.9, Y0 + 2.2, "window"), (2.0, 3.4, Y0 + 0.9, Y0 + 2.2, "window"),
            (-5.0, -3.6, y1 + 0.9, y1 + 2.2, "window"), (2.0, 3.4, y1 + 0.9, y1 + 2.2, "window")])
    p.wall("z", -hw + t / 2, -hd + t, hd - t, Y0, y1 + H, t, "Brick",
           [(-1.0, 0.5, Y0 + 0.9, Y0 + 2.2, "window"), (-1.0, 0.5, y1 + 0.9, y1 + 2.2, "window")])
    p.wall("z", hw - t / 2, 0.0, hd - t, Y0, y1 + H, t, "Brick", [(1.5, 2.8, y1 + 0.9, y1 + 2.2, "window")])
    p.wall("z", hw - t / 2, -hd + t, 0.0, Y0, Y0 + 1.2, t, "Brick")
    rubble(p, 5.0, -2.4, 3.0, 2.4, 50, Y0)
    rubble(p, 6.5, -5.5, 1.8, 0.8, 16, 0.0)
    p.wall("z", -1.0, 0.8, hd - t, Y0, y1, 0.2, "Whitewash", [(2.0, 3.0, Y0, Y0 + 2.1, "hole")])
    p.wall("z", -1.0, 0.8, hd - t, y1, y1 + H, 0.2, "Whitewash", [(2.0, 3.0, y1, y1 + 2.1, "hole")])
    for k in range(6):  # charred joists of the burnt roof
        x = -hw + 0.8 + k * 1.3
        p.mb("Wood").box((x, y1 + H + 0.1, 0), (0.14, 0.2, D - 0.4 - (k % 3) * 1.6), 0.0, 0.0, random.uniform(-0.08, 0.08))
    furniture(p, -hw + 0.6, -1.4, 0.8, hd - 0.6, Y0, 1)
    furniture(p, -hw + 0.6, -1.4, -hd + 0.6, 0.0, y1, 1)
    p.marker("Post", (-5.3, Y0 + 0.05, -hd + 1.1))
    p.marker("Post", (-2.7, Y0 + 0.05, -hd + 1.1))
    p.marker("Post", (-5.3, y1 + 0.05, -hd + 1.1))
    p.marker("Post", (-2.7, y1 + 0.05, -hd + 1.1))
    p.marker("Post", (4.6, Y0 + 0.05, -hd + 1.1))
    return p


def garages():
    p = Proto("Garages")
    n, w, D, H = 6, 3.4, 6.0, 2.6
    W = n * w
    t = 0.25
    x0 = -W / 2
    p.solid("Concrete", (0, -0.05, 0), (W, 0.1, D))
    p.solid("Concrete", (0, H + 0.1, 0.1), (W + 0.3, 0.2, D + 0.5))
    p.solid("Roof", (0, H + 0.22, 0.1), (W + 0.3, 0.04, D + 0.5))
    p.wall("x", D / 2 - t / 2, x0, -x0, 0.0, H, t, "Brick")
    for k in range(n + 1):
        p.wall("z", x0 + k * w, -D / 2, D / 2 - t, 0.0, H, t, "Brick")
    for k in range(n):
        cx = x0 + (k + 0.5) * w
        p.solid("Brick", (cx, H - 0.25, -D / 2 + t / 2), (w - t, 0.5, t))
        r = random.random()
        if r < 0.45:  # closed metal doors
            p.solid("Rust", (cx, (H - 0.5) / 2, -D / 2 + t / 2), (w - t - 0.1, H - 0.5, 0.06))
        elif r < 0.8:  # one leaf hanging open
            p.solid("Rust", (cx - (w - t) / 4, (H - 0.5) / 2, -D / 2 + t / 2), ((w - t) / 2 - 0.05, H - 0.5, 0.06))
            p.solid("Rust", (cx + (w - t) / 2 - 0.05, (H - 0.5) / 2, -D / 2 - 0.55), (0.06, H - 0.5, (w - t) / 2 - 0.1),
                    random.uniform(-0.3, 0.3))
        if random.random() < 0.4:
            rubble(p, cx, 0.5, 0.9, 0.5, 8, 0.0, "Rust")
    p.marker("Post", (x0 + 2.5 * w, 0.05, -D / 2 + 1.2))
    return p


def car_wreck():
    p = Proto("CarWreck")
    p.solid("Rust", (0, 0.55, 0), (1.75, 0.6, 4.2))
    p.solid("Rust", (0, 1.1, 0.25), (1.55, 0.55, 2.0))
    p.deco("Metal", (0, 1.4, 0.25), (1.5, 0.04, 1.9))
    for sx in (-0.85, 0.85):
        for sz in (-1.3, 1.35):
            p.mb("Metal").cyl((sx - 0.1, 0.32, sz), (sx + 0.1, 0.32, sz), 0.26, 10)
    return p


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    coll = bpy.context.scene.collection
    for build in (build_panel5, house_brick, house_wood, ruin2, garages, car_wreck):
        build().finish(coll)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_cameras=False,
                              export_lights=False, export_animations=False, export_extras=False)
    print("EXPORTED", OUT, os.path.getsize(OUT))


main()
