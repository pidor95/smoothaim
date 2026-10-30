package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.entity.EntityType;
import net.minecraft.entity.LightningEntity;
import net.minecraft.entity.LivingEntity;
import net.minecraft.particle.ParticleTypes;
import net.minecraft.sound.SoundCategory;
import net.minecraft.sound.SoundEvents;
import net.minecraft.util.math.Vec3d;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

public class KillEffect extends Module {
    final Setting.Mode mode = add(new Setting.Mode("Эффект", "Молния", "Тотем", "Молния + тотем"));
    final Setting.Bool sound = add(new Setting.Bool("Звук", true));

    /** Кого били за последние секунды → когда. */
    private final Map<LivingEntity, Long> hit = new HashMap<>();

    public KillEffect() {
        super("Kill Effect", "Эффект, когда убиваешь цель", Category.VISUALS, false);
    }

    @Override
    public void onAttack(MinecraftClient mc, Entity e) {
        if (e instanceof LivingEntity l) hit.put(l, System.currentTimeMillis());
    }

    @Override
    public void onTick(MinecraftClient mc) {
        if (mc.world == null) {
            hit.clear();
            return;
        }
        long now = System.currentTimeMillis();
        for (Iterator<Map.Entry<LivingEntity, Long>> it = hit.entrySet().iterator(); it.hasNext(); ) {
            Map.Entry<LivingEntity, Long> en = it.next();
            LivingEntity l = en.getKey();
            if (l.isDead() || l.getHealth() <= 0) {
                play(mc, l.getEntityPos());
                it.remove();
            } else if (now - en.getValue() > 4000 || l.isRemoved()) {
                it.remove();
            }
        }
    }

    private void play(MinecraftClient mc, Vec3d pos) {
        if (!mode.is("Тотем")) {
            // Молния только у нас на клиенте: урона и огня нет.
            LightningEntity bolt = new LightningEntity(EntityType.LIGHTNING_BOLT, mc.world);
            bolt.setId(-1 - (int) (Math.random() * 1_000_000));
            bolt.refreshPositionAfterTeleport(pos);
            bolt.setCosmetic(true);
            mc.world.addEntity(bolt);
        }
        if (!mode.is("Молния")) {
            for (int i = 0; i < 40; i++) {
                mc.particleManager.addParticle(ParticleTypes.TOTEM_OF_UNDYING, pos.x, pos.y + 1, pos.z,
                        (Math.random() - 0.5) * 0.8, Math.random() * 0.8, (Math.random() - 0.5) * 0.8);
            }
        }
        if (sound.value) {
            mc.world.playSoundClient(pos.x, pos.y, pos.z, SoundEvents.ENTITY_LIGHTNING_BOLT_THUNDER,
                    SoundCategory.PLAYERS, 0.4f, 1.4f, false);
        }
    }
}
