"""Shared Blender helper: bake ambient occlusion into vertex colours and multiply it into every material."""
import bpy


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == 'MESH']


def bake_ao(samples=48, dist=1.5):
    """Ambient occlusion per vertex, multiplied into the material colour (glTF COLOR_0 x base colour)."""
    scn = bpy.context.scene
    scn.render.engine = 'CYCLES'; scn.cycles.device = 'CPU'; scn.cycles.samples = samples
    w = bpy.data.worlds.new('ao') if not scn.world else scn.world; scn.world = w
    objs = [o for o in meshes() if len(o.data.vertices) > 0]
    for o in objs:
        me = o.data
        old = me.color_attributes.get('Col')
        ao = me.color_attributes.new('AO', 'FLOAT_COLOR', 'POINT')
        me.color_attributes.active_color = ao
        bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active = o
        scn.render.bake.target = 'VERTEX_COLORS'
        scn.render.bake.use_selected_to_active = False
        if dist > 0: w.light_settings.distance = dist
        bpy.ops.object.bake(type='AO')
        ao = me.color_attributes['AO']
        # soften: real ambient light is never fully blocked, and keep it a little warm
        for i, c in enumerate(ao.data):
            a = 0.45 + 0.55 * c.color[0]
            if old:
                oc = old.data[i].color
                ao.data[i].color = (oc[0] * a, oc[1] * a, oc[2] * a, 1)
            else:
                ao.data[i].color = (a, a, a, 1)
        if old:
            me.color_attributes.remove(old)
        ao = me.color_attributes['AO']; ao.name = 'Col'
        me.color_attributes.active_color = me.color_attributes['Col']
        me.color_attributes.render_color_index = 0
        for m in me.materials:
            if m is None or not m.use_nodes or m.get('ao_done'): continue
            nt = m.node_tree; b = nt.nodes.get('Principled BSDF')
            if b is None: continue
            vc = next((n for n in nt.nodes if n.type == 'VERTEX_COLOR'), None)
            if vc is None:
                vc = nt.nodes.new('ShaderNodeVertexColor')
            vc.layer_name = 'Col'
            src = b.inputs['Base Color'].links[0].from_socket if b.inputs['Base Color'].links else None
            if src is None:
                c = b.inputs['Base Color'].default_value
                mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'; mix.inputs['Factor'].default_value = 1
                mix.inputs['A'].default_value = c
                nt.links.new(vc.outputs['Color'], mix.inputs['B']); nt.links.new(mix.outputs['Result'], b.inputs['Base Color'])
            elif src.node != vc:
                mix = nt.nodes.new('ShaderNodeMix'); mix.data_type = 'RGBA'; mix.blend_type = 'MULTIPLY'; mix.inputs['Factor'].default_value = 1
                nt.links.new(src, mix.inputs['A']); nt.links.new(vc.outputs['Color'], mix.inputs['B']); nt.links.new(mix.outputs['Result'], b.inputs['Base Color'])
            m['ao_done'] = True
