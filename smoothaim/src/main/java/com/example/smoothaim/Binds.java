package com.example.smoothaim;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.util.InputUtil;
import org.lwjgl.glfw.GLFW;

/** Бинды модулей (клавиши и кнопки мыши) и состояние клавиш, которое видят модули. */
public final class Binds {
    static final int NONE = -1;
    private static final int MOUSE = -100;
    private static final boolean[] keys = new boolean[GLFW.GLFW_KEY_LAST + 1];

    private Binds() {
    }

    static int mouse(int button) {
        return MOUSE - button;
    }

    static String name(int bind) {
        if (bind == NONE) return "—";
        if (bind <= MOUSE) return "Mouse " + (MOUSE - bind + 1);
        String s = InputUtil.Type.KEYSYM.createFromCode(bind).getLocalizedText().getString();
        return s.length() > 10 ? s.substring(0, 10) : s;
    }

    /** Нажата ли клавиша сейчас — работает и при открытом экране. */
    static boolean keyDown(int key) {
        return key >= 0 && key < keys.length && keys[key];
    }

    /** Из KeyboardMixin: каждое событие клавиатуры. */
    public static void onKey(int key, int action) {
        if (key >= 0 && key < keys.length) keys[key] = action != GLFW.GLFW_RELEASE;
        if (action == GLFW.GLFW_PRESS) onPress(key);
    }

    /** Из MouseMixin: нажатие кнопки мыши. */
    public static void onMouse(int button, int action) {
        if (action == GLFW.GLFW_PRESS) onPress(mouse(button));
    }

    private static void onPress(int bind) {
        MinecraftClient mc = MinecraftClient.getInstance();
        if (mc.currentScreen != null || bind == NONE) return;
        boolean changed = false;
        for (Module m : SmoothAim.MODULES) {
            if (m.bind == bind) {
                m.toggle();
                changed = true;
            }
        }
        if (changed) SmoothAim.saveConfig();
    }
}
