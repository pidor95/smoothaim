package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;

public class KeyBindsHud extends Module {
    final Setting.Bool onlyEnabled = add(new Setting.Bool("Только включённые", false));

    public KeyBindsHud() {
        super("KeyBinds", "Список биндов на экране", Category.DISPLAY, false);
    }

    @Override
    public void onHud(DrawContext ctx, MinecraftClient mc) {
        if (mc.options.hudHidden) return;
        int x = 6, y = 26, w = 110, row = 12;
        int count = 0;
        for (Module m : BurgerDLC.MODULES) {
            if (m.bind != Binds.NONE && (!onlyEnabled.value || m.isEnabled())) count++;
        }
        Render2D.round(ctx, x, y, w, 16 + Math.max(1, count) * row + 4, 5, ClickGui.PANEL);
        UI.draw(ctx, "Бинды", x + 6, y + 4, ClickGui.ACCENT);
        int ry = y + 17;
        if (count == 0) UI.draw(ctx, "нет биндов", x + 6, ry, ClickGui.DIM);
        for (Module m : BurgerDLC.MODULES) {
            if (m.bind == Binds.NONE || onlyEnabled.value && !m.isEnabled()) continue;
            String key = "[" + Binds.name(m.bind) + "]";
            UI.draw(ctx, UI.trim(m.name, w - 18 - UI.width(key)), x + 6, ry, m.isEnabled() ? ClickGui.TEXT : ClickGui.DIM);
            UI.draw(ctx, key, x + w - 6 - UI.width(key), ry, m.isEnabled() ? ClickGui.ACCENT : ClickGui.DIM);
            ry += row;
        }
    }
}
