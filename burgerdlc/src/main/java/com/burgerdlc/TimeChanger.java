package com.burgerdlc;

public class TimeChanger extends Module {
    public static TimeChanger INSTANCE;

    final Setting.Mode time = add(new Setting.Mode("Время", "День", "Закат", "Ночь", "Рассвет", "Полдень"));

    public TimeChanger() {
        super("Time Changer", "Своё время суток (только у тебя)", Category.VISUALS, false);
        INSTANCE = this;
    }

    /** Время суток для клиента или -1, если модуль выключен. */
    public static long override() {
        if (INSTANCE == null || !INSTANCE.isEnabled()) return -1;
        return switch (INSTANCE.time.get()) {
            case "Закат" -> 12500;
            case "Ночь" -> 18000;
            case "Рассвет" -> 23200;
            case "Полдень" -> 6000;
            default -> 1000;
        };
    }
}
