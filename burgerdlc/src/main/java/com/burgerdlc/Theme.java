package com.burgerdlc;

/** Цвета клиента: акцент меню и палитра «Тема» во всех визуалах. */
public class Theme extends Module {
    public static Theme INSTANCE;

    private static final String[] PRESETS = {"Бургер", "Неон", "Лёд", "Закат", "Мята", "Кровь", "Своя"};
    private static final int[][] COLORS = {
            {0xFF9A1F, 0xFFD65A}, {0xB44CFF, 0x3CE6FF}, {0x7FD7FF, 0xFFFFFF},
            {0xFF4D6D, 0xFFB347}, {0x3CFFB0, 0x2E8BFF}, {0xFF2E2E, 0x7A0000}};

    final Setting.Mode preset = add(new Setting.Mode("Пресет", PRESETS));
    final Setting.Color first = add(new Setting.Color("Цвет 1", COLORS[0][0]));
    final Setting.Color second = add(new Setting.Color("Цвет 2", COLORS[0][1]));
    final Setting.Num speed = add(new Setting.Num("Скорость перелива", 1, 0, 4, 0.1));

    private int lastPreset = 0;
    private int lastRgb1 = COLORS[0][0], lastRgb2 = COLORS[0][1];

    public Theme() {
        super("Тема", "Цвета меню и визуалов", Category.DISPLAY, true);
        INSTANCE = this;
    }

    /** Применяет пресет или переключает на «Свою», если цвет поменяли пипеткой. Каждый кадр. */
    void sync() {
        if (preset.index != lastPreset) {
            lastPreset = preset.index;
            if (preset.index < COLORS.length) {
                first.set(COLORS[preset.index][0]);
                second.set(COLORS[preset.index][1]);
            }
        } else if (first.rgb() != lastRgb1 || second.rgb() != lastRgb2) {
            // Цвет поменяли пипеткой — это уже своя тема.
            preset.index = lastPreset = PRESETS.length - 1;
        }
        lastRgb1 = first.rgb();
        lastRgb2 = second.rgb();
    }

    static int color1() {
        return INSTANCE == null ? COLORS[0][0] : INSTANCE.first.rgb();
    }

    static int color2() {
        return INSTANCE == null ? COLORS[0][1] : INSTANCE.second.rgb();
    }

    static double speed() {
        return INSTANCE == null || !INSTANCE.isEnabled() ? 0 : INSTANCE.speed.value;
    }
}
