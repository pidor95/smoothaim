package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.particle.ParticleTypes;
import net.minecraft.util.math.Vec3d;

public class FireFlies extends Module {
    final Setting.Num amount = add(new Setting.Num("Количество", 3, 1, 10, 1));
    final Setting.Num radius = add(new Setting.Num("Радиус", 8, 3, 16, 1));

    public FireFlies() {
        super("FireFlies", "Светлячки вокруг тебя", Category.VISUALS, false);
    }

    @Override
    public void onTick(MinecraftClient mc) {
        if (mc.player == null || mc.world == null) return;
        Vec3d p = mc.player.getEntityPos();
        double r = radius.value;
        for (int i = 0; i < (int) amount.value; i++) {
            mc.particleManager.addParticle(ParticleTypes.FIREFLY,
                    p.x + (Math.random() * 2 - 1) * r, p.y + Math.random() * 3, p.z + (Math.random() * 2 - 1) * r,
                    0, 0.01, 0);
        }
    }
}
