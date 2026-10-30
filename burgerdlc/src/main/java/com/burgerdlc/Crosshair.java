package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.option.Perspective;

public class Crosshair extends Module {
    public static Crosshair INSTANCE;

    final Setting.Mode color = Colors.setting(this);
    final Setting.Num size = add(new Setting.Num("Длина", 4, 1, 10, 1));
    final Setting.Num gap = add(new Setting.Num("Зазор", 2, 0, 8, 1));
    final Setting.Num thick = add(new Setting.Num("Толщина", 1, 1, 3, 1));
    final Setting.Bool dot = add(new Setting.Bool("Точка", true));
    final Setting.Bool dynamic = add(new Setting.Bool("Расходится от кулдауна", true));

    public Crosshair() {
        super("Crosshair", "Свой прицел вместо ванильного", Category.VISUALS, false);
        INSTANCE = this;
    }

    @Override
    public void onHud(DrawContext ctx, MinecraftClient mc) {
        if (mc.player == null || mc.options.hudHidden || mc.options.getPerspective() != Perspective.FIRST_PERSON) return;
        int cx = ctx.getScaledWindowWidth() / 2, cy = ctx.getScaledWindowHeight() / 2;
        int t = (int) thick.value, len = (int) size.value;
        int g = (int) gap.value + (dynamic.value ? Math.round((1 - mc.player.getAttackCooldownProgress(0)) * 4) : 0);
        int col = Colors.get(color, 0, 255), shadow = 0x90000000;
        int h = t / 2;
        int[][] bars = {
                {cx - g - len, cy - h, cx - g, cy - h + t}, {cx + g + 1, cy - h, cx + g + 1 + len, cy - h + t},
                {cx - h, cy - g - len, cx - h + t, cy - g}, {cx - h, cy + g + 1, cx - h + t, cy + g + 1 + len}};
        for (int[] b : bars) ctx.fill(b[0] - 1, b[1] - 1, b[2] + 1, b[3] + 1, shadow);
        for (int[] b : bars) ctx.fill(b[0], b[1], b[2], b[3], col);
        if (dot.value) {
            ctx.fill(cx - h - 1, cy - h - 1, cx - h + t + 1, cy - h + t + 1, shadow);
            ctx.fill(cx - h, cy - h, cx - h + t, cy - h + t, col);
        }
    }

    public static boolean active() {
        return INSTANCE != null && INSTANCE.isEnabled();
    }
}
