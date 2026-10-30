package com.burgerdlc;

import net.fabricmc.fabric.api.client.rendering.v1.world.WorldRenderContext;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.util.math.Vec3d;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class JumpCircles extends Module {
    final Setting.Mode color = Colors.setting(this);
    final Setting.Num radius = add(new Setting.Num("Радиус", 1.2, 0.4, 3, 0.1));
    final Setting.Num life = add(new Setting.Num("Время, сек", 1.2, 0.3, 3, 0.1));
    final Setting.Num width = add(new Setting.Num("Толщина", 0.12, 0.03, 0.4, 0.01));
    final Setting.Bool others = add(new Setting.Bool("У других игроков", false));

    private record Circle(Vec3d pos, long born) {
    }

    private final List<Circle> circles = new ArrayList<>();
    private final Map<PlayerEntity, Boolean> wasOnGround = new HashMap<>();

    public JumpCircles() {
        super("Jump Circles", "Круги под ногами при прыжке", Category.VISUALS, false);
    }

    @Override
    public void onTick(MinecraftClient mc) {
        if (mc.world == null) {
            circles.clear();
            wasOnGround.clear();
            return;
        }
        for (PlayerEntity p : mc.world.getPlayers()) {
            if (p != mc.player && !others.value) continue;
            boolean ground = p.isOnGround();
            if (Boolean.TRUE.equals(wasOnGround.get(p)) && !ground && p.getVelocity().y > 0.1) {
                circles.add(new Circle(p.getEntityPos().add(0, 0.02, 0), System.currentTimeMillis()));
            }
            wasOnGround.put(p, ground);
        }
        wasOnGround.keySet().removeIf(p -> p.isRemoved());
    }

    @Override
    public void onWorld(WorldRenderContext ctx, MinecraftClient mc, float td) {
        long now = System.currentTimeMillis();
        long lifeMs = (long) (life.value * 1000);
        circles.removeIf(c -> now - c.born > lifeMs);
        if (circles.isEmpty()) return;
        Render3D r = new Render3D(ctx);
        for (Circle c : circles) {
            double t = (now - c.born) / (double) lifeMs;
            double ease = 1 - Math.pow(1 - t, 3);
            double outer = radius.value * ease, inner = Math.max(0, outer - width.value);
            int a = (int) (255 * (1 - t));
            r.ring(true, c.pos, inner, outer, 48, ph -> Colors.get(color, ph, a), 0);
            r.ring(false, c.pos, Math.max(0, inner - 0.02), outer, 48, ph -> Colors.get(color, ph, a / 2), a / 4);
        }
    }
}
