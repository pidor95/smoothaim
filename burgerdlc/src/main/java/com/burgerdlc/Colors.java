package com.burgerdlc;

import net.minecraft.util.math.MathHelper;

/** Палитры визуалов. phase — 0..1, сдвиг по градиенту (по кругу, по длине следа и т.п.). */
final class Colors {
    static final String[] MODES = {"Тема", "Радуга", "Белый"};

    private Colors() {
    }

    static Setting.Mode setting(Module m) {
        return m.add(new Setting.Mode("Цвет", MODES));
    }

    /** Цвет темы (перелив между «Цвет 1» и «Цвет 2»). */
    static int theme(double phase, int alpha) {
        double t = time() * Theme.speed() + phase;
        return argb(alpha, lerp(Theme.color1(), Theme.color2(), wave(t)));
    }

    static int get(Setting.Mode mode, double phase, int alpha) {
        return switch (mode.get()) {
            case "Радуга" -> argb(alpha, java.awt.Color.HSBtoRGB((float) ((time() + phase) % 1.0), 0.65f, 1f));
            case "Белый" -> argb(alpha, 0xFFFFFF);
            default -> theme(phase, alpha);
        };
    }

    private static double time() {
        return (System.currentTimeMillis() % 400000) / 4000.0;
    }

    private static int argb(int alpha, int rgb) {
        return (MathHelper.clamp(alpha, 0, 255) << 24) | (rgb & 0xFFFFFF);
    }

    private static double wave(double t) {
        return 0.5 + 0.5 * Math.sin(t * Math.PI * 2);
    }

    static int lerp(int a, int b, double t) {
        int r = (int) (((a >> 16) & 255) + (((b >> 16) & 255) - ((a >> 16) & 255)) * t);
        int g = (int) (((a >> 8) & 255) + (((b >> 8) & 255) - ((a >> 8) & 255)) * t);
        int bl = (int) ((a & 255) + ((b & 255) - (a & 255)) * t);
        return (r << 16) | (g << 8) | bl;
    }
}
