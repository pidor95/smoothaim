package com.example.smoothaim;

import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keybinding.v1.KeyBindingHelper;
import net.fabricmc.fabric.api.client.rendering.v1.hud.HudElementRegistry;
import net.fabricmc.loader.api.FabricLoader;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.option.KeyBinding;
import net.minecraft.client.util.InputUtil;
import net.minecraft.util.Identifier;
import org.lwjgl.glfw.GLFW;

import java.io.Reader;
import java.io.Writer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Properties;

public class SmoothAim implements ClientModInitializer {
    static final List<Module> MODULES = List.of(
            new AimBot(), new TriggerBot(), new InvMove(), new Watermark());

    static final KeyBinding.Category CATEGORY = KeyBinding.Category.create(Identifier.of("smoothaim", "main"));

    static KeyBinding openGui;
    private static long last = System.nanoTime();

    @Override
    public void onInitializeClient() {
        openGui = KeyBindingHelper.registerKeyBinding(new KeyBinding(
                "key.smoothaim.gui", InputUtil.Type.KEYSYM,
                GLFW.GLFW_KEY_RIGHT_SHIFT, CATEGORY));
        loadConfig();

        ClientTickEvents.START_CLIENT_TICK.register(c -> {
            for (Module m : MODULES) {
                if (m.isEnabled()) m.onTick(c);
            }
        });
        ClientTickEvents.END_CLIENT_TICK.register(c -> {
            while (openGui.wasPressed()) {
                if (c.currentScreen == null) c.setScreen(new ClickGui());
            }
        });

        HudElementRegistry.addLast(Identifier.of("smoothaim", "hud"), (ctx, tickCounter) -> {
            MinecraftClient mc = MinecraftClient.getInstance();
            for (Module m : MODULES) {
                if (m.isEnabled()) m.onHud(ctx, mc);
            }
        });
    }

    /** Вызывается из GameRendererMixin в начале каждого кадра. */
    public static void onFrame() {
        long now = System.nanoTime();
        double dt = Math.min((now - last) / 1e9, 0.05);
        last = now;
        MinecraftClient mc = MinecraftClient.getInstance();
        for (Module m : MODULES) {
            if (m.isEnabled()) m.onFrame(mc, dt);
        }
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
            m.bind = parseInt(p.getProperty(m.name + ".bind"), m.bind);
            for (Setting s : m.settings) {
                String v = p.getProperty(m.name + "." + s.name);
                if (v != null) s.load(v);
            }
        }
        ClickGui.posX = parseInt(p.getProperty("gui.x"), ClickGui.posX);
        ClickGui.posY = parseInt(p.getProperty("gui.y"), ClickGui.posY);
    }

    static void saveConfig() {
        Properties p = new Properties();
        for (Module m : MODULES) {
            p.setProperty(m.name + ".enabled", Boolean.toString(m.isEnabled()));
            p.setProperty(m.name + ".bind", Integer.toString(m.bind));
            for (Setting s : m.settings) p.setProperty(m.name + "." + s.name, s.save());
        }
        p.setProperty("gui.x", Integer.toString(ClickGui.posX));
        p.setProperty("gui.y", Integer.toString(ClickGui.posY));
        try (Writer w = Files.newBufferedWriter(configPath(), StandardCharsets.UTF_8)) {
            p.store(w, "SmoothAim");
        } catch (Exception ignored) {
        }
    }

    private static int parseInt(String s, int def) {
        try {
            return s == null ? def : Integer.parseInt(s);
        } catch (NumberFormatException e) {
            return def;
        }
    }
}
