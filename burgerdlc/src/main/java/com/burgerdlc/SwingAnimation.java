package com.burgerdlc;

public class SwingAnimation extends Module {
    public static SwingAnimation INSTANCE;

    final Setting.Num speed = add(new Setting.Num("Длительность взмаха", 1.6, 0.5, 4, 0.1));

    public SwingAnimation() {
        super("Swing Animation", "Медленный плавный взмах рукой", Category.VISUALS, false);
        INSTANCE = this;
    }

    /** Ваниль — 6 тиков на взмах; модуль растягивает или ускоряет его. */
    public static int duration(int vanilla) {
        if (INSTANCE == null || !INSTANCE.isEnabled()) return vanilla;
        return Math.max(1, Math.round(vanilla * (float) INSTANCE.speed.value));
    }
}
