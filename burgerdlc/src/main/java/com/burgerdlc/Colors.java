package com.burgerdlc;

import net.minecraft.util.math.MathHelper;

/** Палитры визуалов. phase — 0..1, сдвиг по градиенту (по кругу, по длине следа и т.п.). */
final class Colors {
    static final String[] MODES = {"Бургер", "Радуга", "Неон", "Лёд", "Белый"};

    private Colors() {
    }

    static Setting.Mode setting(Module m) {
        return m.add(new Setting.Mode("Цвет", MODES));
    }

    static int get(Setting.Mode mode, double phase, int alpha) {
        double t = (System.currentTimeMillis() % 4000) / 4000.0 + phase;
        int rgb = switch (mode.get()) {
            case "Радуга" -> java.awt.Color.HSBtoRGB((float) (t % 1.0), 0.65f, 1f);
            case "Неон" -> lerp(0xB44CFF, 0x3CE6FF, wave(t));
            case "Лёд" -> lerp(0x7FD7FF, 0xFFFFFF, wave(t));
            case "Белый" -> 0xFFFFFF;
            default -> lerp(0xFF9A1F, 0xFFD65A, wave(t));
        };
        return (MathHelper.clamp(alpha, 0, 255) << 24) | (rgb & 0xFFFFFF);
    }

    private static double wave(double t) {
        return 0.5 + 0.5 * Math.sin(t * Math.PI * 2);
    }

    private static int lerp(int a, int b, double t) {
        int r = (int) (((a >> 16) & 255) + (((b >> 16) & 255) - ((a >> 16) & 255)) * t);
        int g = (int) (((a >> 8) & 255) + (((b >> 8) & 255) - ((a >> 8) & 255)) * t);
        int bl = (int) ((a & 255) + ((b & 255) - (a & 255)) * t);
        return (r << 16) | (g << 8) | bl;
    }
}
