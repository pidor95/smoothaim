package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.particle.ParticleEffect;
import net.minecraft.particle.ParticleTypes;
import net.minecraft.util.math.Vec3d;

public class HitParticles extends Module {
    final Setting.Mode type = add(new Setting.Mode("Частицы", "Сердечки", "Звёзды", "Огонь", "Магия", "Ноты", "Облака"));
    final Setting.Num count = add(new Setting.Num("Количество", 8, 1, 30, 1));
    final Setting.Num spread = add(new Setting.Num("Разлёт", 0.3, 0.05, 1, 0.05));

    public HitParticles() {
        super("Hit Particles", "Частицы при ударе по цели", Category.VISUALS, false);
    }

    @Override
    public void onAttack(MinecraftClient mc, Entity target) {
        ParticleEffect effect = switch (type.get()) {
            case "Звёзды" -> ParticleTypes.ENCHANTED_HIT;
            case "Огонь" -> ParticleTypes.FLAME;
            case "Магия" -> ParticleTypes.WITCH;
            case "Ноты" -> ParticleTypes.NOTE;
            case "Облака" -> ParticleTypes.CLOUD;
            default -> ParticleTypes.HEART;
        };
        Vec3d c = target.getBoundingBox().getCenter();
        double s = spread.value;
        for (int i = 0; i < (int) count.value; i++) {
            mc.particleManager.addParticle(effect,
                    c.x + (Math.random() - 0.5) * target.getWidth(), c.y + (Math.random() - 0.3) * target.getHeight() * 0.6,
                    c.z + (Math.random() - 0.5) * target.getWidth(),
                    (Math.random() - 0.5) * s, Math.random() * s * 0.6, (Math.random() - 0.5) * s);
        }
    }
}
