package com.example.smoothaim;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;

import java.util.ArrayList;
import java.util.List;

public abstract class Module {
    public final String name;
    public final String description;
    public final Category category;
    public final List<Setting> settings = new ArrayList<>();
    private boolean enabled;
    /** Код клавиши GLFW, кнопка мыши как Binds.mouse(n), или Binds.NONE. */
    public int bind = Binds.NONE;

    protected Module(String name, String description, Category category, boolean enabled) {
        this(name, description, category, enabled, Binds.NONE);
    }

    protected Module(String name, String description, Category category, boolean enabled, int bind) {
        this.name = name;
        this.description = description;
        this.category = category;
        this.enabled = enabled;
        this.bind = bind;
    }

    protected <T extends Setting> T add(T setting) {
        settings.add(setting);
        return setting;
    }

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean value) {
        if (enabled == value) return;
        enabled = value;
        if (value) onEnable();
        else onDisable();
    }

    public void toggle() {
        setEnabled(!enabled);
    }

    protected void onEnable() {
    }

    protected void onDisable() {
    }

    /** Вызывается в начале каждого тика, пока модуль включён. */
    public void onTick(MinecraftClient mc) {
    }

    /** Вызывается каждый кадр, пока модуль включён. dt в секундах. */
    public void onFrame(MinecraftClient mc, double dt) {
    }

    public void onHud(DrawContext ctx, MinecraftClient mc) {
    }
}
