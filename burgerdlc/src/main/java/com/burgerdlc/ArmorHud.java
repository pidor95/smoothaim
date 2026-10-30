package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.entity.EquipmentSlot;
import net.minecraft.item.ItemStack;

public class ArmorHud extends Module {
    final Setting.Bool percent = add(new Setting.Bool("Прочность в %", true));

    private static final EquipmentSlot[] SLOTS = {
            EquipmentSlot.HEAD, EquipmentSlot.CHEST, EquipmentSlot.LEGS, EquipmentSlot.FEET};

    public ArmorHud() {
        super("Armor HUD", "Броня и прочность над хотбаром", Category.DISPLAY, false);
    }

    @Override
    public void onHud(DrawContext ctx, MinecraftClient mc) {
        if (mc.player == null || mc.options.hudHidden) return;
        // Справа от хотбара, чтобы не пересекаться с Target HUD и полосками здоровья.
        int x = ctx.getScaledWindowWidth() / 2 + 98, y = ctx.getScaledWindowHeight() - 19;
        for (EquipmentSlot slot : SLOTS) {
            ItemStack s = mc.player.getEquippedStack(slot);
            if (s.isEmpty()) continue;
            ctx.drawItem(s, x, y);
            if (s.isDamageable()) {
                float f = (s.getMaxDamage() - s.getDamage()) / (float) s.getMaxDamage();
                String t = percent.value ? Math.round(f * 100) + "%" : Integer.toString(s.getMaxDamage() - s.getDamage());
                int color = 0xFF000000 | Colors.lerp(0xFF4040, 0x5CFF7A, f);
                UI.draw(ctx, t, x + 8 - UI.width(t) / 2, y - 10, color);
            }
            x += 20;
        }
    }
}
