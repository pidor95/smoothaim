package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.entity.Entity;
import net.minecraft.entity.effect.StatusEffects;
import net.minecraft.item.Items;
import net.minecraft.util.Hand;
import net.minecraft.util.hit.EntityHitResult;

public class TriggerBot extends Module {
    final Setting.Num delayMin = add(new Setting.Num("Задержка от, мс", 0, 0, 250, 5));
    final Setting.Num delayMax = add(new Setting.Num("Задержка до, мс", 30, 0, 300, 5));
    final Setting.Num charge = add(new Setting.Num("Заряд удара", 0.95, 0.5, 1.0, 0.01));
    final Setting.Mode crits = add(new Setting.Mode("Криты", "Умные", "Выкл"));
    final Setting.Bool earlyMace = add(new Setting.Bool("Ранний удар булавой", true));
    final Setting.Num maceFall = add(new Setting.Num("Булава: падение от, блоков", 1.5, 1.5, 6, 0.5));
    final Setting.Bool weaponOnly = add(new Setting.Bool("Только с оружием", true));
    final TargetFilter filter = new TargetFilter(this);

    private Entity seen;
    private long seenAt, delay;

    public TriggerBot() {
        super("TriggerBot", "Бьёт, когда прицел на цели", Category.COMBAT, false);
    }

    @Override
    public void onFrame(MinecraftClient mc, double dt) {
        ClientPlayerEntity p = mc.player;
        if (p == null || mc.world == null || mc.interactionManager == null || mc.currentScreen != null
                || p.isUsingItem() || weaponOnly.value && !TargetFilter.holdingWeapon(p)) {
            seen = null;
            return;
        }
        // crosshairTarget пересчитывается каждый кадр, поэтому реакция не ждёт тика.
        if (!(mc.crosshairTarget instanceof EntityHitResult hit) || !filter.test(p, hit.getEntity())) {
            seen = null;
            return;
        }

        // Булава: урон растёт с высотой падения, поэтому бьём сразу, как цель под прицелом,
        // не дожидаясь задержки реакции — иначе можно приземлиться и потерять урон.
        if (earlyMace.value && p.getMainHandStack().isOf(Items.MACE) && !p.isOnGround()
                && p.fallDistance >= maceFall.value && p.getVelocity().y < 0
                && p.getAttackCooldownProgress(0.5f) >= 0.9f) {
            mc.interactionManager.attackEntity(p, hit.getEntity());
            p.swingHand(Hand.MAIN_HAND);
            seen = null;
            return;
        }

        long now = System.currentTimeMillis();
        if (seen != hit.getEntity()) {
            seen = hit.getEntity();
            seenAt = now;
            double lo = Math.min(delayMin.value, delayMax.value), hi = Math.max(delayMin.value, delayMax.value);
            delay = Math.round(lo + Math.random() * (hi - lo));
        }
        if (now - seenAt < delay) return;
        if (p.getAttackCooldownProgress(0.5f) < charge.value) return;
        if (crits.is("Умные") && !critReady(mc, p)) return;

        mc.interactionManager.attackEntity(p, seen);
        p.swingHand(Hand.MAIN_HAND);
    }

    /** В прыжке ждём падения, чтобы удар был критом; на земле бьём сразу. */
    private static boolean critReady(MinecraftClient mc, ClientPlayerEntity p) {
        boolean canCrit = !p.isClimbing() && !p.isTouchingWater() && !p.hasVehicle()
                && !p.hasStatusEffect(StatusEffects.BLINDNESS) && !p.getAbilities().flying;
        if (!canCrit) return true;
        if (p.isOnGround()) return !mc.options.jumpKey.isPressed();
        return p.fallDistance > 0 && p.getVelocity().y < 0;
    }
}
