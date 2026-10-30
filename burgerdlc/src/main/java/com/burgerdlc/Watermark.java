package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.font.TextRenderer;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.network.PlayerListEntry;

public class Watermark extends Module {
    public Watermark() {
        super("Watermark", "Плашка сверху: ник, FPS, пинг", Category.DISPLAY, true);
    }

    @Override
    public void onHud(DrawContext ctx, MinecraftClient mc) {
        if (mc.player == null || mc.options.hudHidden) return;
        PlayerListEntry entry = mc.getNetworkHandler() == null ? null
                : mc.getNetworkHandler().getPlayerListEntry(mc.player.getUuid());
        String[] parts = {
                "Burger DLC",
                mc.getSession().getUsername(),
                mc.getCurrentFps() + " fps",
                (entry == null ? 0 : entry.getLatency()) + " ms"};

        TextRenderer tr = mc.textRenderer;
        int gap = 12, width = 0;
        for (String s : parts) width += UI.width(s);
        width += gap * (parts.length - 1) + 16;

        int x = (ctx.getScaledWindowWidth() - width) / 2, y = 4;
        Render2D.round(ctx, x, y, width, 15, 5, ClickGui.PANEL);
        int tx = x + 8;
        for (int i = 0; i < parts.length; i++) {
            UI.draw(ctx, parts[i], tx, y + 4, i == 0 ? ClickGui.ACCENT : ClickGui.TEXT);
            tx += UI.width(parts[i]);
            if (i < parts.length - 1) {
                ctx.fill(tx + gap / 2, y + 4, tx + gap / 2 + 1, y + 11, ClickGui.LINE);
                tx += gap;
            }
        }
    }
}
