package com.burgerdlc;

import com.burgerdlc.mixin.GameRendererAccessor;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.render.Camera;
import net.minecraft.util.math.Vec3d;
import org.joml.Matrix4f;
import org.joml.Quaternionf;
import org.joml.Vector4f;

/** Перевод точек мира в координаты HUD. Обновляется раз за кадр перед отрисовкой HUD. */
final class Projection {
    private static final Matrix4f matrix = new Matrix4f();
    private static Vec3d cam = Vec3d.ZERO;
    private static int width, height;

    private Projection() {
    }

    static void update(MinecraftClient mc, float td) {
        Camera camera = mc.gameRenderer.getCamera();
        float fov = ((GameRendererAccessor) mc.gameRenderer).burger$getFov(camera, td, true);
        Matrix4f proj = mc.gameRenderer.getBasicProjectionMatrix(fov);
        Quaternionf view = camera.getRotation().conjugate(new Quaternionf());
        matrix.set(proj).rotate(view);
        cam = camera.getCameraPos();
        width = mc.getWindow().getScaledWidth();
        height = mc.getWindow().getScaledHeight();
    }

    /** {x, y} на экране или null, если точка за камерой. */
    static double[] toScreen(Vec3d p) {
        Vector4f v = new Vector4f((float) (p.x - cam.x), (float) (p.y - cam.y), (float) (p.z - cam.z), 1f);
        matrix.transform(v);
        if (v.w <= 0.05f) return null;
        return new double[]{(v.x / v.w + 1) / 2 * width, (1 - v.y / v.w) / 2 * height};
    }
}
