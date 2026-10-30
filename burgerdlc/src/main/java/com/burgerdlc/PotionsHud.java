package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.entity.effect.StatusEffectInstance;

import java.util.ArrayList;
import java.util.List;

public class PotionsHud extends Module {
    public PotionsHud() {
        super("Potions", "Эффекты и их время на экране", Category.DISPLAY, false);
    }

    @Override
    public void onHud(DrawContext ctx, MinecraftClient mc) {
        if (mc.player == null || mc.options.hudHidden) return;
        List<StatusEffectInstance> effects = new ArrayList<>(mc.player.getStatusEffects());
        if (effects.isEmpty()) return;
        int w = 130, row = 12, x = ctx.getScaledWindowWidth() - w - 6, y = 26;
        Render2D.round(ctx, x, y, w, 16 + effects.size() * row + 4, 5, ClickGui.PANEL);
        UI.draw(ctx, "Эффекты", x + 6, y + 4, ClickGui.ACCENT);
        int ry = y + 17;
        for (StatusEffectInstance e : effects) {
            String name = e.getEffectType().value().getName().getString();
            if (e.getAmplifier() > 0) name += " " + (e.getAmplifier() + 1);
            String time = e.isInfinite() ? "∞" : String.format("%d:%02d", e.getDuration() / 1200, e.getDuration() / 20 % 60);
            UI.draw(ctx, UI.trim(name, w - 18 - UI.width(time)), x + 6, ry, ClickGui.TEXT);
            UI.draw(ctx, time, x + w - 6 - UI.width(time), ry, e.getDuration() < 200 && !e.isInfinite() ? 0xFFFF5555 : ClickGui.DIM);
            ry += row;
        }
    }
}
