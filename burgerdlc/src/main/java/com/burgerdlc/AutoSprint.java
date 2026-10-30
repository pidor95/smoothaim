package com.burgerdlc;

import net.minecraft.client.MinecraftClient;

public class AutoSprint extends Module {
    public AutoSprint() {
        super("Auto Sprint", "Бег без зажатия Ctrl", Category.MOVEMENT, false);
    }

    @Override
    public void onTick(MinecraftClient mc) {
        if (mc.player == null) return;
        if (mc.options.forwardKey.isPressed() && !mc.player.isSneaking() && !mc.player.horizontalCollision
                && mc.player.getHungerManager().getFoodLevel() > 6) {
            mc.player.setSprinting(true);
        }
    }
}
