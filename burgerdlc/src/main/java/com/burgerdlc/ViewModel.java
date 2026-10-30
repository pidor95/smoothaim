package com.burgerdlc;

import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.util.Hand;

public class ViewModel extends Module {
    public static ViewModel INSTANCE;

    final Setting.Num x = add(new Setting.Num("Сдвиг X", 0, -1, 1, 0.05));
    final Setting.Num y = add(new Setting.Num("Сдвиг Y", 0, -1, 1, 0.05));
    final Setting.Num z = add(new Setting.Num("Сдвиг Z", 0, -1, 1, 0.05));
    final Setting.Num scale = add(new Setting.Num("Размер", 1, 0.3, 2, 0.05));

    public ViewModel() {
        super("ViewModel", "Положение и размер рук", Category.VISUALS, false);
        INSTANCE = this;
    }

    public static void apply(MatrixStack m, Hand hand) {
        if (INSTANCE == null || !INSTANCE.isEnabled()) return;
        // Для левой руки зеркалим X, чтобы обе руки двигались симметрично.
        double side = hand == Hand.MAIN_HAND ? 1 : -1;
        m.translate(INSTANCE.x.value * side, INSTANCE.y.value, INSTANCE.z.value);
        float s = (float) INSTANCE.scale.value;
        m.scale(s, s, s);
    }
}
