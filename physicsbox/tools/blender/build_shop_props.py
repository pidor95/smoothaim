"""Models the supermarket props in Blender and exports assets/props/shop.glb.

Run:  blender -b --python tools/blender/build_shop_props.py

Objects (origin at the bottom centre unless noted; game axes after export:
X width, Y up, Z depth):
  gondola     double-sided shelf unit 2.0 x 1.7 x 0.9, shelf boards at
              0.15 / 0.55 / 0.95 / 1.35 m on both sides of a centre panel
  wall_shelf  single-sided unit against a wall, 2.0 x 2.0 x 0.5
  checkout    counter with belt, register and card reader, 1.8 x 0.95 x 0.6
  freezer     upright glass-door cooler, 1.25 x 2.0 x 0.7
  cart        shopping cart, 0.55 x 1.0 x 0.9 (origin at the floor)
  lamp        ceiling light panel 1.2 x 0.3 (origin at its centre)
  prod_box, prod_can, prod_bottle, prod_carton, prod_bag, prod_jar
              products (origin at the bottom centre); material 0 is the
              package colour the game tints per item
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "props", "shop.glb")
_x = 0.0


def mat(name, color, rough=0.6, metal=0.0, emit=0.0, alpha=1.0):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit > 0:
        b.inputs["Emission Color"].default_value = (*color, 1)
        b.inputs["Emission Strength"].default_value = emit
    if alpha < 1:
        b.inputs["Alpha"].default_value = alpha
        m.blend_method = "BLEND"
    return m


def cube(size, loc, material, bevel=0.0):
    """Box: size/loc in GAME axes (x, y up, z depth) -> Blender (x, -z, y)."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(loc[0], -loc[2], loc[1]))
    o = bpy.context.active_object
    o.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        mod = o.modifiers.new("bev", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(material)
    return o


def cyl(radius, depth, loc, material, axis="y", verts=16):
    rot = {"y": (0, 0, 0), "x": (0, math.radians(90), 0), "z": (math.radians(90), 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth,
                                        location=(loc[0], -loc[2], loc[1]), rotation=rot)
    o = bpy.context.active_object
    o.data.materials.append(material)
    return o


def tube(a, b, radius, material):
    a = Vector((a[0], -a[2], a[1]))
    b = Vector((b[0], -b[2], b[1]))
    bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=radius, depth=(b - a).length, location=(a + b) / 2)
    o = bpy.context.active_object
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = (b - a).to_track_quat("Z", "Y")
    o.data.materials.append(material)
    return o


def combine(parts, name):
    global _x
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    o.name = name
    o.data.name = name
    o.location.x += _x  # keep them apart in the file; the game reads meshes only
    _x += 3.0
    return o


def gondola():
    steel = mat("ShelfSteel", (0.82, 0.83, 0.85), 0.35, 0.6)
    base = mat("ShelfBase", (0.25, 0.27, 0.3), 0.5)
    tag = mat("PriceTag", (0.95, 0.85, 0.2), 0.5)
    p = [cube((2.0, 0.15, 0.9), (0, 0.075, 0), base, 0.01),
         cube((2.0, 1.55, 0.05), (0, 0.925, 0), steel),
         cube((0.05, 1.7, 0.9), (-0.975, 0.85, 0), steel),
         cube((0.05, 1.7, 0.9), (0.975, 0.85, 0), steel)]
    for y in (0.55, 0.95, 1.35):
        for side in (-1, 1):
            p.append(cube((1.9, 0.03, 0.42), (0, y, side * 0.235), steel))
            p.append(cube((1.9, 0.05, 0.01), (0, y - 0.01, side * 0.45), tag))
    p.append(cube((2.0, 0.04, 0.9), (0, 1.7, 0), steel))
    return combine(p, "gondola")


def wall_shelf():
    wood = mat("WallShelfWood", (0.55, 0.4, 0.27), 0.7)
    steel = bpy.data.materials["ShelfSteel"]
    p = [cube((2.0, 0.15, 0.5), (0, 0.075, 0), wood),
         cube((2.0, 2.0, 0.04), (0, 1.0, 0.23), steel)]
    for y in (0.55, 0.95, 1.35, 1.75):
        p.append(cube((1.95, 0.03, 0.45), (0, y, 0), wood))
    for x in (-0.98, 0.98):
        p.append(cube((0.04, 2.0, 0.5), (x, 1.0, 0), steel))
    return combine(p, "wall_shelf")


def checkout():
    body = mat("CheckoutBody", (0.85, 0.85, 0.82), 0.5)
    belt = mat("Belt", (0.05, 0.05, 0.06), 0.8)
    dark = mat("RegisterDark", (0.08, 0.08, 0.09), 0.4)
    screen = mat("RegisterScreen", (0.2, 0.6, 0.9), 0.2, emit=1.5)
    p = [cube((1.8, 0.85, 0.6), (0, 0.425, 0), body, 0.02),
         cube((1.3, 0.04, 0.45), (-0.2, 0.87, 0), belt),
         cube((0.4, 0.12, 0.35), (0.65, 0.91, 0.0), dark, 0.01),
         cube((0.3, 0.2, 0.03), (0.65, 1.1, -0.1), dark),
         cube((0.26, 0.16, 0.01), (0.65, 1.1, -0.116), screen),
         cube((0.08, 0.12, 0.06), (0.4, 0.93, 0.18), dark)]
    return combine(p, "checkout")


def freezer():
    frame = mat("FreezerFrame", (0.9, 0.9, 0.92), 0.4, 0.3)
    inside = mat("FreezerInside", (0.75, 0.85, 0.95), 0.3, emit=0.4)
    glass = mat("FreezerGlass", (0.7, 0.85, 0.95), 0.05, alpha=0.25)
    p = [cube((1.25, 2.0, 0.05), (0, 1.0, 0.33), frame),
         cube((0.05, 2.0, 0.7), (-0.6, 1.0, 0), frame),
         cube((0.05, 2.0, 0.7), (0.6, 1.0, 0), frame),
         cube((1.25, 0.12, 0.7), (0, 0.06, 0), frame),
         cube((1.25, 0.18, 0.7), (0, 1.91, 0), frame),
         cube((1.15, 1.7, 0.02), (0, 0.97, 0.3), inside)]
    for y in (0.5, 0.9, 1.3):
        p.append(cube((1.15, 0.02, 0.55), (0, y, 0.03), inside))
    for x in (-0.3, 0.3):
        p.append(cube((0.58, 1.68, 0.015), (x, 0.97, -0.34), glass))
        p.append(cube((0.03, 0.4, 0.03), (x + 0.24, 1.0, -0.37), frame))
    return combine(p, "freezer")


def cart():
    wire = mat("CartWire", (0.75, 0.77, 0.8), 0.3, 0.8)
    red = mat("CartRed", (0.75, 0.08, 0.06), 0.4)
    black = mat("CartWheel", (0.05, 0.05, 0.05), 0.6)
    p = []
    # basket: bottom grid and side bars (slightly tapered towards the front)
    for i in range(6):
        z = -0.4 + i * 0.16
        p.append(tube((-0.25, 0.42, z), (0.25, 0.42, z), 0.006, wire))
    for i in range(5):
        x = -0.25 + i * 0.125
        p.append(tube((x, 0.42, -0.4), (x, 0.42, 0.4), 0.006, wire))
    for h in (0.42, 0.6, 0.78):
        p.append(tube((-0.27, h, -0.42), (-0.27, h, 0.42), 0.007, wire))
        p.append(tube((0.27, h, -0.42), (0.27, h, 0.42), 0.007, wire))
        p.append(tube((-0.27, h, -0.42), (0.27, h, -0.42), 0.007, wire))
        p.append(tube((-0.27, h, 0.42), (0.27, h, 0.42), 0.007, wire))
    for x in (-0.27, 0.27):
        for z in (-0.42, 0.42):
            p.append(tube((x, 0.12, z), (x, 0.78, z), 0.01, wire))
    p.append(tube((-0.27, 0.95, 0.55), (0.27, 0.95, 0.55), 0.016, red))
    for x in (-0.27, 0.27):
        p.append(tube((x, 0.78, 0.42), (x, 0.95, 0.55), 0.01, wire))
    p.append(cube((0.5, 0.03, 0.85), (0, 0.13, 0), wire))
    for x in (-0.22, 0.22):
        for z in (-0.38, 0.38):
            p.append(cyl(0.05, 0.03, (x, 0.05, z), black, "x", 12))
    return combine(p, "cart")


def lamp():
    housing = mat("LampHousing", (0.85, 0.85, 0.85), 0.5)
    glow = mat("LampGlow", (1.0, 0.98, 0.92), 0.3, emit=4.0)
    p = [cube((1.2, 0.05, 0.3), (0, 0.0, 0), housing), cube((1.12, 0.01, 0.24), (0, -0.03, 0), glow)]
    return combine(p, "lamp")


def products():
    pack = mat("Package", (1.0, 1.0, 1.0), 0.55)  # tinted per item by the game
    label = mat("Label", (0.95, 0.95, 0.92), 0.6)
    metal = mat("CanMetal", (0.8, 0.8, 0.82), 0.25, 0.9)
    glass = mat("BottleGlass", (0.35, 0.55, 0.35), 0.05)
    cap = mat("Cap", (0.9, 0.2, 0.1), 0.4)

    p = [cube((0.2, 0.3, 0.07), (0, 0.15, 0), pack), cube((0.14, 0.12, 0.002), (0, 0.18, -0.036), label)]
    combine(p, "prod_box")
    p = [cyl(0.034, 0.12, (0, 0.06, 0), pack, verts=14), cyl(0.031, 0.006, (0, 0.123, 0), metal, verts=14)]
    combine(p, "prod_can")
    p = [cyl(0.038, 0.2, (0, 0.1, 0), pack, verts=14), cyl(0.034, 0.07, (0, 0.11, 0), label, verts=14)]
    bpy.ops.mesh.primitive_cone_add(vertices=14, radius1=0.038, radius2=0.014, depth=0.06, location=(0, 0, 0.23))
    neck = bpy.context.active_object
    neck.data.materials.append(pack)
    p += [neck, cyl(0.015, 0.025, (0, 0.27, 0), cap, verts=10)]
    combine(p, "prod_bottle")
    p = [cube((0.07, 0.18, 0.07), (0, 0.09, 0), pack)]
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=0.05, radius2=0.0, depth=0.04, location=(0, 0, 0.2),
                                    rotation=(0, 0, math.radians(45)))
    roof = bpy.context.active_object
    roof.data.materials.append(pack)
    p += [roof, cube((0.05, 0.08, 0.002), (0, 0.1, -0.036), label)]
    combine(p, "prod_carton")
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12, ring_count=8, radius=0.1, location=(0, 0, 0.12))
    bag = bpy.context.active_object
    bag.scale = (1.0, 0.45, 1.25)
    bpy.ops.object.transform_apply(scale=True)
    bag.data.materials.append(pack)
    combine([bag, cube((0.16, 0.03, 0.04), (0, 0.255, 0), pack)], "prod_bag")
    p = [cyl(0.045, 0.1, (0, 0.05, 0), glass, verts=14), cyl(0.047, 0.025, (0, 0.112, 0), pack, verts=14),
         cyl(0.046, 0.05, (0, 0.05, 0), label, verts=14)]
    combine(p, "prod_jar")


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    gondola()
    wall_shelf()
    checkout()
    freezer()
    cart()
    lamp()
    products()
    for o in bpy.context.scene.objects:
        if o.type == "MESH":
            for poly in o.data.polygons:
                poly.use_smooth = False
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_apply=True,
                              export_cameras=False, export_lights=False, export_animations=False)
    print("EXPORTED", OUT, os.path.getsize(OUT))


main()
