package com.burgerdlc;

import net.fabricmc.fabric.api.client.rendering.v1.world.WorldRenderContext;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.option.Perspective;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.util.math.Vec3d;

public class ChinaHat extends Module {
    final Setting.Mode color = Colors.setting(this);
    final Setting.Num radius = add(new Setting.Num("Радиус", 0.65, 0.3, 1.2, 0.05));
    final Setting.Num height = add(new Setting.Num("Высота", 0.3, 0.1, 0.8, 0.05));
    final Setting.Num alpha = add(new Setting.Num("Прозрачность", 150, 30, 255, 5));
    final Setting.Bool others = add(new Setting.Bool("На других игроках", false));
    final Setting.Bool glow = add(new Setting.Bool("Свечение", true));

    public ChinaHat() {
        super("China Hat", "Шляпа-конус над головой", Category.VISUALS, false);
    }

    @Override
    public void onWorld(WorldRenderContext ctx, MinecraftClient mc, float td) {
        Render3D r = new Render3D(ctx);
        for (PlayerEntity p : mc.world.getPlayers()) {
            boolean self = p == mc.player;
            if (!self && !others.value || p.isInvisible()) continue;
            // От первого лица шляпа закрывала бы обзор.
            if (self && mc.options.getPerspective() == Perspective.FIRST_PERSON) continue;
            Vec3d base = p.getLerpedPos(td).add(0, p.getHeight() + (p.isSneaking() ? -0.05 : 0.08), 0);
            draw(r, base, p.getYaw(td));
        }
    }

    private void draw(Render3D r, Vec3d base, float yaw) {
        int seg = 36, a = (int) alpha.value;
        Vec3d tip = base.add(0, height.value, 0);
        double spin = Math.toRadians(-yaw);
        for (int i = 0; i < seg; i++) {
            double a0 = spin + Math.PI * 2 * i / seg, a1 = spin + Math.PI * 2 * (i + 1) / seg;
            int c0 = Colors.get(color, i / (double) seg, a), c1 = Colors.get(color, (i + 1) / (double) seg, a);
            Vec3d p0 = base.add(Math.cos(a0) * radius.value, 0, Math.sin(a0) * radius.value);
            Vec3d p1 = base.add(Math.cos(a1) * radius.value, 0, Math.sin(a1) * radius.value);
            int tipColor = Colors.get(color, 0.5, Math.min(255, a + 60));
            r.quad(false, tip, tipColor, p0, c0, p1, c1, tip, tipColor);
            if (glow.value) {
                // Мягкое свечение по краю полями.
                Vec3d o0 = base.add(Math.cos(a0) * (radius.value + 0.12), -0.03, Math.sin(a0) * (radius.value + 0.12));
                Vec3d o1 = base.add(Math.cos(a1) * (radius.value + 0.12), -0.03, Math.sin(a1) * (radius.value + 0.12));
                r.quad(true, p0, Render3D.withAlpha(c0, 120), o0, Render3D.withAlpha(c0, 0),
                        o1, Render3D.withAlpha(c1, 0), p1, Render3D.withAlpha(c1, 120));
            }
        }
    }
}
