package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.gui.PlayerSkinDrawer;
import net.minecraft.client.network.AbstractClientPlayerEntity;
import net.minecraft.entity.Entity;
import net.minecraft.entity.LivingEntity;
import net.minecraft.util.hit.EntityHitResult;
import net.minecraft.util.math.MathHelper;

public class TargetHud extends Module {
    final Setting.Num offsetY = add(new Setting.Num("Сдвиг от прицела", 40, 10, 150, 5));
    final Setting.Num hold = add(new Setting.Num("Показывать, сек", 4, 1, 10, 0.5));

    private LivingEntity target;
    private long lastSeen;
    private float shownHealth = -1;

    public TargetHud() {
        super("Target HUD", "Панель цели: голова, HP, броня", Category.DISPLAY, false);
    }

    @Override
    public void onAttack(MinecraftClient mc, Entity e) {
        remember(e);
    }

    private void remember(Entity e) {
        if (e instanceof LivingEntity l) {
            if (l != target) shownHealth = -1;
            target = l;
            lastSeen = System.currentTimeMillis();
        }
    }

    @Override
    public void onHud(DrawContext ctx, MinecraftClient mc) {
        if (mc.player == null || mc.options.hudHidden) return;
        if (mc.crosshairTarget instanceof EntityHitResult hit) remember(hit.getEntity());
        if (target == null || target.isRemoved() || System.currentTimeMillis() - lastSeen > hold.value * 1000) {
            target = null;
            return;
        }

        int w = 128, h = 40;
        int x = ctx.getScaledWindowWidth() / 2 - w / 2, y = ctx.getScaledWindowHeight() / 2 + (int) offsetY.value;
        Render2D.round(ctx, x, y, w, h, 6, ClickGui.PANEL);

        int tx = x + 6;
        if (target instanceof AbstractClientPlayerEntity pl) {
            PlayerSkinDrawer.draw(ctx, pl.getSkin(), x + 6, y + 6, 28);
            tx = x + 40;
        }
        float hp = target.getHealth() + target.getAbsorptionAmount();
        float max = target.getMaxHealth();
        if (shownHealth < 0) shownHealth = hp;
        shownHealth += (hp - shownHealth) * 0.15f;

        UI.draw(ctx, UI.trim(target.getName().getString(), x + w - tx - 6), tx, y + 6, ClickGui.TEXT);
        String hpText = String.format("%.1f HP  ·  %.1fm", hp, mc.player.distanceTo(target));
        UI.draw(ctx, hpText, tx, y + 17, ClickGui.DIM);

        int bw = x + w - 6 - tx, by = y + h - 9;
        Render2D.round(ctx, tx, by, bw, 4, 2, ClickGui.OFF);
        float f = MathHelper.clamp(shownHealth / max, 0, 1);
        Render2D.round(ctx, tx, by, Math.max(4, Math.round(bw * f)), 4, 2, Colors.theme(0, 255));
        if (target.getAbsorptionAmount() > 0) {
            float a = MathHelper.clamp(target.getAbsorptionAmount() / max, 0, 1);
            Render2D.round(ctx, tx, by, Math.max(4, Math.round(bw * a)), 4, 2, 0xFFFFD34A);
        }
    }
}
