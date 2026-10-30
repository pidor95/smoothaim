package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.text.Style;
import net.minecraft.text.StyleSpriteSource;
import net.minecraft.text.Text;
import net.minecraft.util.Identifier;

/** Текст обычным шрифтом (Inter) вместо пиксельного шрифта Minecraft. */
final class UI {
    private static final Style STYLE = Style.EMPTY.withFont(
            new StyleSpriteSource.Font(Identifier.of("burgerdlc", "ui")));

    private UI() {
    }

    static Text text(String s) {
        return Text.literal(s).setStyle(STYLE);
    }

    static void draw(DrawContext ctx, String s, int x, int y, int color) {
        ctx.drawText(MinecraftClient.getInstance().textRenderer, text(s), x, y, color, false);
    }

    static int width(String s) {
        return MinecraftClient.getInstance().textRenderer.getWidth(text(s));
    }

    /** Обрезает строку с «…», чтобы она влезла в maxWidth. */
    static String trim(String s, int maxWidth) {
        if (width(s) <= maxWidth) return s;
        int ell = width("…");
        int end = s.length();
        while (end > 0 && width(s.substring(0, end)) + ell > maxWidth) end--;
        return s.substring(0, end) + "…";
    }
}
