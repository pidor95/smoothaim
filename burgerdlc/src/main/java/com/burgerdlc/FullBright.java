package com.burgerdlc;

public class FullBright extends Module {
    public static FullBright INSTANCE;

    final Setting.Num gamma = add(new Setting.Num("Яркость", 10, 1, 16, 0.5));

    public FullBright() {
        super("FullBright", "Видно в темноте и пещерах", Category.VISUALS, false);
        INSTANCE = this;
    }

    public static double gammaOr(double vanilla) {
        return INSTANCE != null && INSTANCE.isEnabled() ? INSTANCE.gamma.value : vanilla;
    }
}
