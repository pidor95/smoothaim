package com.burgerdlc;

/** Отключает мешающие эффекты; сами хуки — в mixin/NoRender*Mixin. */
public class NoRender extends Module {
    public static NoRender INSTANCE;

    public final Setting.Bool fire = add(new Setting.Bool("Огонь на экране", true));
    public final Setting.Bool hurtCam = add(new Setting.Bool("Тряска от урона", true));
    public final Setting.Bool totem = add(new Setting.Bool("Анимация тотема", false));
    public final Setting.Bool liquid = add(new Setting.Bool("Вода/блок в глазах", true));
    public final Setting.Bool vignette = add(new Setting.Bool("Затемнение (виньетка)", true));
    public final Setting.Bool nausea = add(new Setting.Bool("Тошнота и портал", true));
    public final Setting.Bool bossBar = add(new Setting.Bool("Боссбар", false));
    public final Setting.Bool scoreboard = add(new Setting.Bool("Скорборд", false));
    public final Setting.Bool effects = add(new Setting.Bool("Зелья в углу", false));
    public final Setting.Bool air = add(new Setting.Bool("Пузырьки воздуха", false));
    public final Setting.Bool weather = add(new Setting.Bool("Погода", false));
    public final Setting.Bool glow = add(new Setting.Bool("Свечение игроков", false));
    public final Setting.Bool particles = add(new Setting.Bool("Частицы ударов", false));

    public NoRender() {
        super("NoRender", "Убирает огонь, тряску, оверлеи", Category.DISPLAY, false);
        INSTANCE = this;
    }

    /** Включён модуль и пункт. */
    public static boolean on(Setting.Bool option) {
        return INSTANCE != null && INSTANCE.isEnabled() && option.value;
    }
}
