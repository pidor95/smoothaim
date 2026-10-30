package com.burgerdlc;

import net.fabricmc.fabric.api.client.rendering.v1.world.WorldRenderContext;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.font.TextRenderer;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.entity.Entity;
import net.minecraft.entity.ItemEntity;
import net.minecraft.entity.LivingEntity;
import net.minecraft.entity.decoration.ArmorStandEntity;
import net.minecraft.entity.mob.Monster;
import net.minecraft.entity.passive.AnimalEntity;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.util.math.Box;
import net.minecraft.util.math.MathHelper;
import net.minecraft.util.math.Vec3d;

public class ESP extends Module {
    public static ESP INSTANCE;

    final Setting.Bool players = add(new Setting.Bool("Игроки", true));
    final Setting.Bool mobs = add(new Setting.Bool("Мобы", false));
    final Setting.Bool animals = add(new Setting.Bool("Животные", false));
    final Setting.Bool items = add(new Setting.Bool("Предметы", false));
    final Setting.Mode box = add(new Setting.Mode("Коробка", "2D", "3D", "Нет"));
    final Setting.Bool glow = add(new Setting.Bool("Свечение", false));
    final Setting.Bool health = add(new Setting.Bool("Полоска HP", true));
    final Setting.Bool tags = add(new Setting.Bool("Ники (HP, дистанция)", true));
    final Setting.Bool tracers = add(new Setting.Bool("Трейсеры", false));
    final Setting.Mode color = add(new Setting.Mode("Цвет", "Тема", "Радуга", "Белый", "По здоровью"));
    final Setting.Num range = add(new Setting.Num("Дистанция", 96, 16, 256, 8));

    public ESP() {
        super("ESP", "Видеть игроков: коробки, ники, свечение", Category.VISUALS, false);
        INSTANCE = this;
    }

    boolean matches(MinecraftClient mc, Entity e) {
        // Игроков с HP, спрятанным античитом, всё равно показываем: мёртв — только если убран из мира.
        if (e == mc.player || mc.player == null || e.isRemoved() || e instanceof ArmorStandEntity) return false;
        if (!(e instanceof PlayerEntity) && !e.isAlive()) return false;
        if (mc.player.squaredDistanceTo(e) > range.value * range.value) return false;
        if (e instanceof PlayerEntity p) return players.value && !p.isSpectator();
        if (e instanceof Monster) return mobs.value;
        if (e instanceof AnimalEntity) return animals.value;
        if (e instanceof ItemEntity) return items.value;
        return false;
    }

    int colorOf(Entity e, int alpha) {
        if (color.is("По здоровью") && e instanceof LivingEntity l) {
            float f = MathHelper.clamp(l.getHealth() / l.getMaxHealth(), 0, 1);
            return (alpha << 24) | Colors.lerp(0xFF3B3B, 0x4CFF6A, f);
        }
        Setting.Mode m = color.is("По здоровью") ? null : color;
        return m == null ? (alpha << 24) | 0xFFFFFF : Colors.get(m, e.getId() * 0.13, alpha);
    }

    /** Для mixin'ов свечения: подсвечивать ли сущность и каким цветом. */
    public static boolean glows(Entity e) {
        MinecraftClient mc = MinecraftClient.getInstance();
        return INSTANCE != null && INSTANCE.isEnabled() && INSTANCE.glow.value && INSTANCE.matches(mc, e);
    }

    public static int glowColor(Entity e) {
        return INSTANCE.colorOf(e, 255) & 0xFFFFFF;
    }

    @Override
    public void onWorld(WorldRenderContext ctx, MinecraftClient mc, float td) {
        boolean box3d = box.is("3D");
        if (!box3d && !tracers.value) return;
        Render3D r = new Render3D(ctx);
        Vec3d eye = mc.gameRenderer.getCamera().getCameraPos();
        Vec3d start = eye.add(Vec3d.fromPolar(mc.gameRenderer.getCamera().getPitch(), mc.gameRenderer.getCamera().getYaw()).multiply(1.5));
        for (Entity e : mc.world.getEntities()) {
            if (!matches(mc, e)) continue;
            Box b = lerpedBox(e, td);
            int c = colorOf(e, 255);
            if (box3d) {
                r.box(b, Render3D.withAlpha(c, 40));
                r.boxEdges(b, c, 0.025);
            }
            if (tracers.value) r.line(start, b.getCenter(), c, 0.015);
        }
    }

    @Override
    public void onHud(DrawContext ctx, MinecraftClient mc) {
        if (mc.world == null || mc.options.hudHidden) return;
        boolean box2d = box.is("2D");
        if (!box2d && !health.value && !tags.value) return;
        float td = mc.getRenderTickCounter().getTickProgress(true);
        Projection.update(mc, td);
        TextRenderer tr = mc.textRenderer;
        for (Entity e : mc.world.getEntities()) {
            if (!matches(mc, e)) continue;
            double[] rect = screenRect(lerpedBox(e, td));
            if (rect == null) continue;
            int x1 = (int) rect[0], y1 = (int) rect[1], x2 = (int) rect[2], y2 = (int) rect[3];
            int c = colorOf(e, 255);

            if (box2d) {
                ctx.drawStrokedRectangle(x1 - 1, y1 - 1, x2 - x1 + 3, y2 - y1 + 3, 0xA0000000);
                ctx.drawStrokedRectangle(x1, y1, x2 - x1 + 1, y2 - y1 + 1, c);
                ctx.drawStrokedRectangle(x1 + 1, y1 + 1, x2 - x1 - 1, y2 - y1 - 1, 0xA0000000);
            }
            if (health.value && e instanceof LivingEntity l) {
                float f = MathHelper.clamp((l.getHealth() + l.getAbsorptionAmount()) / l.getMaxHealth(), 0, 1);
                int hx = x1 - 5, top = y2 - Math.round((y2 - y1) * Math.min(f, 1));
                ctx.fill(hx - 1, y1 - 1, hx + 2, y2 + 2, 0xA0000000);
                ctx.fill(hx, top, hx + 1, y2 + 1, 0xFF000000 | Colors.lerp(0xFF3B3B, 0x4CFF6A, f));
            }
            if (tags.value) {
                String name = e.getName().getString();
                String info = String.format("%.0fm", mc.player.distanceTo(e));
                if (e instanceof LivingEntity l) info = String.format("%.1f❤ ", l.getHealth() + l.getAbsorptionAmount()) + info;
                String text = name + "  " + info;
                int tw = tr.getWidth(text), cx = (x1 + x2) / 2, ty = y1 - 13;
                Render2D.round(ctx, cx - tw / 2 - 4, ty - 2, tw + 8, 12, 3, 0xB0101018);
                ctx.drawText(tr, name, cx - tw / 2, ty, 0xFFFFFFFF, false);
                ctx.drawText(tr, info, cx - tw / 2 + tr.getWidth(name + "  "), ty, c, false);
            }
        }
    }

    private static Box lerpedBox(Entity e, float td) {
        Vec3d off = e.getLerpedPos(td).subtract(e.getEntityPos());
        return e.getBoundingBox().offset(off);
    }

    /** Прямоугольник на экране вокруг хитбокса: {x1, y1, x2, y2} или null. */
    private static double[] screenRect(Box b) {
        double x1 = Double.MAX_VALUE, y1 = Double.MAX_VALUE, x2 = -Double.MAX_VALUE, y2 = -Double.MAX_VALUE;
        for (int i = 0; i < 8; i++) {
            Vec3d p = new Vec3d((i & 1) == 0 ? b.minX : b.maxX, (i & 2) == 0 ? b.minY : b.maxY, (i & 4) == 0 ? b.minZ : b.maxZ);
            double[] s = Projection.toScreen(p);
            if (s == null) return null;
            x1 = Math.min(x1, s[0]);
            y1 = Math.min(y1, s[1]);
            x2 = Math.max(x2, s[0]);
            y2 = Math.max(y2, s[1]);
        }
        return new double[]{x1, y1, x2, y2};
    }
}
