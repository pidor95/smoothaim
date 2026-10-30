package com.burgerdlc;

import java.util.concurrent.ThreadLocalRandom;

public class ParticleLimit extends Module {
    public static ParticleLimit INSTANCE;

    final Setting.Num percent = add(new Setting.Num("Оставить частиц, %", 40, 0, 100, 5));

    public ParticleLimit() {
        super("Particle Limit", "Меньше частиц — больше FPS", Category.OPTIMIZATION, false);
        INSTANCE = this;
    }

    public static boolean drop() {
        return INSTANCE != null && INSTANCE.isEnabled()
                && ThreadLocalRandom.current().nextDouble(100) >= INSTANCE.percent.value;
    }
}
