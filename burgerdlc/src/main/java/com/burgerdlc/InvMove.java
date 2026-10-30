package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.ChatScreen;
import net.minecraft.client.gui.screen.Screen;
import net.minecraft.client.gui.screen.ingame.AbstractSignEditScreen;
import net.minecraft.client.gui.screen.ingame.AnvilScreen;
import net.minecraft.client.gui.screen.ingame.BookEditScreen;
import net.minecraft.client.gui.screen.ingame.HandledScreen;
import net.minecraft.client.option.KeyBinding;
import net.minecraft.client.util.InputUtil;

public class InvMove extends Module {
    final Setting.Bool inventories = add(new Setting.Bool("В инвентаре/сундуках", true));
    final Setting.Bool clickGui = add(new Setting.Bool("В меню Burger DLC", true));
    final Setting.Bool sneak = add(new Setting.Bool("Присед", false));

    public InvMove() {
        super("InvMove", "Ходить с открытым инвентарём и меню", Category.MOVEMENT, true);
    }

    @Override
    public void onTick(MinecraftClient mc) {
        Screen s = mc.currentScreen;
        if (s == null || mc.player == null || !allowed(s)) return;
        KeyBinding[] keys = {mc.options.forwardKey, mc.options.backKey, mc.options.leftKey,
                mc.options.rightKey, mc.options.jumpKey, mc.options.sprintKey};
        for (KeyBinding k : keys) update(k);
        if (sneak.value) update(mc.options.sneakKey);
    }

    private boolean allowed(Screen s) {
        if (s instanceof ClickGui) return clickGui.value;
        // Там, где печатают текст, клавиши должны идти в поле ввода.
        if (s instanceof ChatScreen || s instanceof AbstractSignEditScreen || s instanceof AnvilScreen
                || s instanceof BookEditScreen) return false;
        return inventories.value && s instanceof HandledScreen;
    }

    private static void update(KeyBinding k) {
        InputUtil.Key key = InputUtil.fromTranslationKey(k.getBoundKeyTranslationKey());
        if (key.getCategory() != InputUtil.Type.KEYSYM) return;
        k.setPressed(Binds.keyDown(key.getCode()));
    }
}
