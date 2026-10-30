package com.burgerdlc;

import net.minecraft.client.gui.DrawContext;

final class Render2D {
    private Render2D() {
    }

    /** Прямоугольник со скруглёнными углами, построчно — без шейдеров. */
    static void round(DrawContext ctx, int x, int y, int w, int h, int r, int color) {
        r = Math.min(r, Math.min(w, h) / 2);
        if (r <= 0) {
            ctx.fill(x, y, x + w, y + h, color);
            return;
        }
        ctx.fill(x, y + r, x + w, y + h - r, color);
        for (int i = 0; i < r; i++) {
            double dy = r - i - 0.5;
            int inset = (int) Math.round(r - Math.sqrt(r * r - dy * dy));
            ctx.fill(x + inset, y + i, x + w - inset, y + i + 1, color);
            ctx.fill(x + inset, y + h - 1 - i, x + w - inset, y + h - i, color);
        }
    }

    static int mix(int a, int b, float t) {
        t = Math.max(0, Math.min(1, t));
        int r = 0;
        for (int shift = 0; shift < 32; shift += 8) {
            int ca = (a >>> shift) & 0xFF, cb = (b >>> shift) & 0xFF;
            r |= Math.round(ca + (cb - ca) * t) << shift;
        }
        return r;
    }
}
