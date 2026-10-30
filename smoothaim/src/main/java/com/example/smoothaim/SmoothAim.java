package com.example.smoothaim;

import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keybinding.v1.KeyBindingHelper;
import net.fabricmc.fabric.api.client.rendering.v1.HudRenderCallback;
import net.fabricmc.loader.api.FabricLoader;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.option.KeyBinding;
import net.minecraft.client.util.InputUtil;
import org.lwjgl.glfw.GLFW;

import java.io.Reader;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Properties;

public class SmoothAim implements ClientModInitializer {
    static final AimBot AIM_BOT = new AimBot();
    static final TriggerBot TRIGGER_BOT = new TriggerBot();
    static final List<Module> MODULES = List.of(AIM_BOT, TRIGGER_BOT, new Watermark());

    static KeyBinding toggleAim;
    static KeyBinding toggleTrigger;
    static KeyBinding openGui;
    static long last = System.nanoTime();

    @Override
    public void onInitializeClient() {
        toggleAim = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.smoothaim.toggle", InputUtil.Type.KEYSYM,
                GLFW.GLFW_KEY_R, "category.smoothaim"));
        toggleTrigger = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.smoothaim.trigger", InputUtil.Type.KEYSYM,
                GLFW.GLFW_KEY_UNKNOWN, "category.smoothaim"));
        openGui = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.smoothaim.gui", InputUtil.Type.KEYSYM,
                GLFW.GLFW_KEY_RIGHT_SHIFT, "category.smoothaim"));
        loadConfig();

        ClientTickEvents.END_CLIENT_TICK.register(c -> {
            boolean changed = false;
            while (toggleAim.wasPressed()) {
                AIM_BOT.toggle();
                changed = true;
            }
            while (toggleTrigger.wasPressed()) {
                TRIGGER_BOT.toggle();
                changed = true;
            }
            if (changed) saveConfig();
            while (openGui.wasPressed()) {
                if (c.currentScreen == null) c.setScreen(new ClickGui());
            }
        });

        HudRenderCallback.EVENT.register((ctx, tickCounter) -> {
            long now = System.nanoTime();
            double dt = Math.min((now - last) / 1e9, 0.05);
            last = now;
            MinecraftClient mc = MinecraftClient.getInstance();
            for (Module m : MODULES) {
                if (!m.isEnabled()) continue;
                m.onFrame(mc, dt);
                m.onHud(ctx, mc);
            }
        });
    }

    private static Path configPath() {
        return FabricLoader.getInstance().getConfigDir().resolve("smoothaim.properties");
    }

    static void loadConfig() {
        Path path = configPath();
        if (!Files.exists(path)) return;
        Properties p = new Properties();
        try (Reader r = Files.newBufferedReader(path, StandardCharsets.UTF_8)) {
            p.load(r);
        } catch (Exception e) {
            return;
        }
        for (Module m : MODULES) {
            String on = p.getProperty(m.name + ".enabled");
            if (on != null) m.setEnabled(Boolean.parseBoolean(on));
            for (Setting s : m.settings) {
                String v = p.getProperty(m.name + "." + s.name);
                if (v != null) s.load(v);
            }
        }
    }

    static void saveConfig() {
        Properties p = new Properties();
        for (Module m : MODULES) {
            p.setProperty(m.name + ".enabled", Boolean.toString(m.isEnabled()));
            for (Setting s : m.settings) p.setProperty(m.name + "." + s.name, s.save());
        }
        try (Writer w = Files.newBufferedWriter(configPath(), StandardCharsets.UTF_8)) {
            p.store(w, "SmoothAim");
        } catch (Exception ignored) {
        }
    }
}
