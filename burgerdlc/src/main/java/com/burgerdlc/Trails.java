package com.burgerdlc;

import net.fabricmc.fabric.api.client.rendering.v1.world.WorldRenderContext;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.option.Perspective;
import net.minecraft.util.math.Vec3d;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Iterator;

public class Trails extends Module {
    final Setting.Mode color = Colors.setting(this);
    final Setting.Num length = add(new Setting.Num("Длина, сек", 0.8, 0.2, 3, 0.1));
    final Setting.Num height = add(new Setting.Num("Высота", 0.9, 0.1, 2, 0.05));
    final Setting.Bool firstPerson = add(new Setting.Bool("От первого лица", false));

    private record Point(Vec3d pos, long time) {
    }

    private final Deque<Point> points = new ArrayDeque<>();

    public Trails() {
        super("Trails", "Светящийся шлейф за игроком", Category.VISUALS, false);
    }

    @Override
    protected void onDisable() {
        points.clear();
    }

    @Override
    public void onWorld(WorldRenderContext ctx, MinecraftClient mc, float td) {
        long now = System.currentTimeMillis(), max = (long) (length.value * 1000);
        Vec3d pos = mc.player.getLerpedPos(td);
        if (points.isEmpty() || points.peekLast().pos.squaredDistanceTo(pos) > 0.0025) points.add(new Point(pos, now));
        while (!points.isEmpty() && now - points.peekFirst().time > max) points.removeFirst();
        if (points.size() < 2 || !firstPerson.value && mc.options.getPerspective() == Perspective.FIRST_PERSON) return;

        Render3D r = new Render3D(ctx);
        Iterator<Point> it = points.iterator();
        Point prev = it.next();
        int i = 0, n = points.size();
        while (it.hasNext()) {
            Point cur = it.next();
            double f0 = i / (double) n, f1 = (i + 1) / (double) n;
            int c0 = Colors.get(color, f0, (int) (200 * f0)), c1 = Colors.get(color, f1, (int) (200 * f1));
            r.quad(true, prev.pos, c0, prev.pos.add(0, height.value, 0), Render3D.withAlpha(c0, 0),
                    cur.pos.add(0, height.value, 0), Render3D.withAlpha(c1, 0), cur.pos, c1);
            prev = cur;
            i++;
        }
    }
}
