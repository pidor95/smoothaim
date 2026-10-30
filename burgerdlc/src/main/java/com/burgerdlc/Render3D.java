package com.burgerdlc;

import net.fabricmc.fabric.api.client.rendering.v1.world.WorldRenderContext;
import net.minecraft.client.render.RenderLayers;
import net.minecraft.client.render.VertexConsumer;
import net.minecraft.client.render.VertexConsumerProvider;
import net.minecraft.util.math.Vec3d;
import org.joml.Matrix4f;

/** Простые полупрозрачные примитивы в мире. Координаты мировые, сдвиг на камеру — внутри. */
final class Render3D {
    private final Matrix4f matrix;
    private final VertexConsumerProvider consumers;
    private final Vec3d cam;

    Render3D(WorldRenderContext ctx) {
        matrix = ctx.matrices().peek().getPositionMatrix();
        consumers = ctx.consumers();
        cam = ctx.worldState().cameraRenderState.pos;
    }

    private void v(VertexConsumer vc, double x, double y, double z, int argb) {
        vc.vertex(matrix, (float) (x - cam.x), (float) (y - cam.y), (float) (z - cam.z)).color(argb);
    }

    /** Четырёхугольник с цветом на каждой вершине; рисуется с двух сторон. */
    void quad(boolean additive, Vec3d a, int ca, Vec3d b, int cb, Vec3d c, int cc, Vec3d d, int cd) {
        // Буфер берём на каждый вызов: Immediate держит открытым только один слой за раз.
        VertexConsumer vc = consumers.getBuffer(additive ? RenderLayers.lightning() : RenderLayers.debugQuads());
        v(vc, a.x, a.y, a.z, ca);
        v(vc, b.x, b.y, b.z, cb);
        v(vc, c.x, c.y, c.z, cc);
        v(vc, d.x, d.y, d.z, cd);
        v(vc, d.x, d.y, d.z, cd);
        v(vc, c.x, c.y, c.z, cc);
        v(vc, b.x, b.y, b.z, cb);
        v(vc, a.x, a.y, a.z, ca);
    }

    /** Горизонтальное кольцо: внутренний и внешний радиус, цвета по кругу из colorAt(phase). */
    void ring(boolean additive, Vec3d center, double inner, double outer, int segments,
              java.util.function.DoubleFunction<Integer> colorAt, int innerAlpha) {
        for (int i = 0; i < segments; i++) {
            double a0 = Math.PI * 2 * i / segments, a1 = Math.PI * 2 * (i + 1) / segments;
            int c0 = colorAt.apply(i / (double) segments), c1 = colorAt.apply((i + 1) / (double) segments);
            quad(additive,
                    center.add(Math.cos(a0) * inner, 0, Math.sin(a0) * inner), withAlpha(c0, innerAlpha),
                    center.add(Math.cos(a0) * outer, 0, Math.sin(a0) * outer), c0,
                    center.add(Math.cos(a1) * outer, 0, Math.sin(a1) * outer), c1,
                    center.add(Math.cos(a1) * inner, 0, Math.sin(a1) * inner), withAlpha(c1, innerAlpha));
        }
    }

    static int withAlpha(int argb, int alpha) {
        return (Math.max(0, Math.min(255, alpha)) << 24) | (argb & 0xFFFFFF);
    }

    static int alpha(int argb) {
        return argb >>> 24;
    }
}
