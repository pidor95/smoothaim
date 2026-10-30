package com.burgerdlc;

import net.fabricmc.fabric.api.client.rendering.v1.world.WorldRenderContext;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.entity.LivingEntity;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.util.math.Vec3d;

public class TargetESP extends Module {
    final Setting.Mode mode = add(new Setting.Mode("Вид", "Кольцо", "Призраки", "Ромб"));
    final Setting.Mode color = Colors.setting(this);
    final Setting.Num speed = add(new Setting.Num("Скорость", 1, 0.3, 3, 0.1));
    final Setting.Num hold = add(new Setting.Num("Держать, сек", 3, 0.5, 10, 0.5));

    private Entity target;
    private long lastHit;

    public TargetESP() {
        super("Target ESP", "Метка на цели, которую бьёшь", Category.VISUALS, false);
    }

    @Override
    public void onAttack(MinecraftClient mc, Entity e) {
        if (e instanceof LivingEntity) {
            target = e;
            lastHit = System.currentTimeMillis();
        }
    }

    @Override
    public void onWorld(WorldRenderContext ctx, MinecraftClient mc, float td) {
        if (target == null || target.isRemoved() || !(target instanceof PlayerEntity) && !target.isAlive()
                || System.currentTimeMillis() - lastHit > hold.value * 1000) {
            target = null;
            return;
        }
        Render3D r = new Render3D(ctx);
        double t = System.currentTimeMillis() / 1000.0 * speed.value;
        Vec3d pos = target.getLerpedPos(td);
        double h = target.getHeight(), w = target.getWidth() * 0.75 + 0.1;

        switch (mode.get()) {
            case "Призраки" -> {
                // Три светящихся «души», кружащих вокруг цели по спиралям.
                for (int k = 0; k < 3; k++) {
                    for (int i = 0; i < 14; i++) {
                        double tt = t * 2.2 - i * 0.06 + k * Math.PI * 2 / 3;
                        double y = h * (0.5 + 0.4 * Math.sin(tt * 0.8 + k));
                        Vec3d c = pos.add(Math.cos(tt) * w, y, Math.sin(tt) * w);
                        double s = 0.09 * (1 - i / 14.0) + 0.02;
                        int col = Colors.get(color, k / 3.0 + i * 0.02, (int) (230 * (1 - i / 14.0)));
                        billboard(r, mc, c, s, col);
                    }
                }
            }
            case "Ромб" -> {
                Vec3d top = pos.add(0, h + 0.45 + Math.sin(t * 3) * 0.08, 0);
                double rot = t * 2, s = 0.18;
                Vec3d up = top.add(0, s * 1.4, 0), down = top.add(0, -s * 1.4, 0);
                for (int i = 0; i < 4; i++) {
                    double a0 = rot + Math.PI / 2 * i, a1 = rot + Math.PI / 2 * (i + 1);
                    Vec3d p0 = top.add(Math.cos(a0) * s, 0, Math.sin(a0) * s);
                    Vec3d p1 = top.add(Math.cos(a1) * s, 0, Math.sin(a1) * s);
                    int c0 = Colors.get(color, i / 4.0, 220), c1 = Colors.get(color, (i + 1) / 4.0, 220);
                    r.quad(false, up, c0, p0, c0, p1, c1, up, c1);
                    r.quad(false, down, c1, p0, c0, p1, c1, down, c1);
                }
            }
            default -> {
                // Кольцо, которое плавно ходит вверх-вниз по телу, со светящимся «хвостом».
                double y = h * (0.5 + 0.5 * Math.sin(t * 2.5));
                double prev = h * (0.5 + 0.5 * Math.sin(t * 2.5 - 0.35));
                Vec3d c = pos.add(0, y, 0);
                r.ring(true, c, w, w + 0.04, 48, ph -> Colors.get(color, ph, 255), 255);
                int seg = 48;
                for (int i = 0; i < seg; i++) {
                    double a0 = Math.PI * 2 * i / seg, a1 = Math.PI * 2 * (i + 1) / seg;
                    int c0 = Colors.get(color, i / (double) seg, 150), c1 = Colors.get(color, (i + 1) / (double) seg, 150);
                    r.quad(true,
                            pos.add(Math.cos(a0) * w, y, Math.sin(a0) * w), c0,
                            pos.add(Math.cos(a0) * w, prev, Math.sin(a0) * w), Render3D.withAlpha(c0, 0),
                            pos.add(Math.cos(a1) * w, prev, Math.sin(a1) * w), Render3D.withAlpha(c1, 0),
                            pos.add(Math.cos(a1) * w, y, Math.sin(a1) * w), c1);
                }
            }
        }
    }

    /** Квадрат, всегда повёрнутый к камере. */
    private static void billboard(Render3D r, MinecraftClient mc, Vec3d c, double s, int col) {
        float yaw = (float) Math.toRadians(mc.gameRenderer.getCamera().getYaw());
        float pitch = (float) Math.toRadians(mc.gameRenderer.getCamera().getPitch());
        Vec3d right = new Vec3d(Math.cos(yaw), 0, Math.sin(yaw)).multiply(s);
        Vec3d up = new Vec3d(-Math.sin(yaw) * Math.sin(pitch), Math.cos(pitch), Math.cos(yaw) * Math.sin(pitch)).multiply(s);
        int edge = Render3D.withAlpha(col, 0);
        r.quad(true, c.subtract(right).subtract(up), edge, c.add(right).subtract(up), edge,
                c.add(right).add(up), edge, c.subtract(right).add(up), edge);
        r.quad(true, c, col, c.add(right), edge, c.add(up), edge, c, col);
        r.quad(true, c, col, c.add(up), edge, c.subtract(right), edge, c, col);
        r.quad(true, c, col, c.subtract(right), edge, c.subtract(up), edge, c, col);
        r.quad(true, c, col, c.subtract(up), edge, c.add(right), edge, c, col);
    }
}
