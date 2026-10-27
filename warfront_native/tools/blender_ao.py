"""Re-export existing vehicle glTF files with baked ambient occlusion in their vertex colours.

Run: blender -b -P blender_ao.py -- IN.glb OUT.glb [samples]
"""
import bpy, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aolib import bake_ao

argv = sys.argv[sys.argv.index('--') + 1:]
src, dst = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
bake_ao(int(argv[2]) if len(argv) > 2 else 32)
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_image_format='JPEG', export_jpeg_quality=90, export_vertex_color='MATERIAL')
print('AO done', dst)
