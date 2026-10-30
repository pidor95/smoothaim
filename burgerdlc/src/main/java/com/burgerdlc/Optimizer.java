package com.burgerdlc;

import net.minecraft.block.entity.BlockEntity;
import net.minecraft.block.entity.SignBlockEntity;
import net.minecraft.block.entity.HangingSignBlockEntity;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.option.CloudRenderMode;
import net.minecraft.client.option.GameOptions;
import net.minecraft.entity.Entity;
import net.minecraft.entity.ItemEntity;
import net.minecraft.entity.decoration.ArmorStandEntity;
import net.minecraft.entity.decoration.ItemFrameEntity;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.particle.ParticlesMode;
import net.minecraft.util.math.Vec3d;

import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

/** Оптимизатор: FPS, частицы, сущности, блок-энтити и лёгкие настройки графики. */
public class Optimizer extends Module {
    public static Optimizer INSTANCE;

    final Setting.Header fpsHeader = add(new Setting.Header("FPS"));
    final Setting.Bool backgroundFps = add(new Setting.Bool("FPS в фоне", true));
    final Setting.Num backgroundLimit = add(new Setting.Num("Лимит FPS в фоне", 15, 1, 60, 1));
    final Setting.Bool menuFps = add(new Setting.Bool("Динамический FPS в меню", false));
    final Setting.Num menuLimit = add(new Setting.Num("Лимит FPS в меню", 60, 10, 144, 5));

    final Setting.Header particlesHeader = add(new Setting.Header("Частицы"));
    final Setting.Num particlePercent = add(new Setting.Num("Оставить частиц, %", 60, 0, 100, 5));
    final Setting.Num particleDistance = add(new Setting.Num("Дистанция частиц", 32, 4, 64, 2));

    final Setting.Header entitiesHeader = add(new Setting.Header("Сущности"));
    final Setting.Num entityDistance = add(new Setting.Num("Скрытие сущностей дальше", 64, 16, 160, 8));
    final Setting.Bool hidePlayers = add(new Setting.Bool("Скрывать игроков тоже", false));
    final Setting.Bool occlusion = add(new Setting.Bool("Скрытие за стенами", true));
    final Setting.Num itemDistance = add(new Setting.Num("Дистанция предметов", 24, 4, 64, 2));
    final Setting.Num itemLimit = add(new Setting.Num("Лимит предметов", 80, 10, 300, 10));
    final Setting.Bool armorStands = add(new Setting.Bool("Скрыть стойки для брони", false));

    final Setting.Header framesHeader = add(new Setting.Header("Рамки и таблички"));
    final Setting.Num frameDistance = add(new Setting.Num("Дистанция рамок", 24, 4, 64, 2));
    final Setting.Num signDistance = add(new Setting.Num("Таблички вблизи", 16, 4, 64, 2));
    final Setting.Num blockEntityDistance = add(new Setting.Num("Дистанция блок-энтити", 48, 8, 64, 4));

    final Setting.Header graphicsHeader = add(new Setting.Header("Настройки Minecraft"));
    final Setting.Bool clouds = add(new Setting.Bool("Без облаков", true));
    final Setting.Bool shadows = add(new Setting.Bool("Без теней сущностей", true));
    final Setting.Bool fewerParticles = add(new Setting.Bool("Частицы: меньше", true));
    final Setting.Bool noAo = add(new Setting.Bool("Без мягкого освещения", false));
    final Setting.Bool biomeBlend = add(new Setting.Bool("Без смешивания биомов", false));
    final Setting.Bool toasts = add(new Setting.Bool("Скрыть тосты", true));

    private final Map<Integer, Long> visibleUntil = new HashMap<>();
    private final Map<Integer, Boolean> visible = new HashMap<>();
    private int itemsThisFrame;
    private long tick;

    // Прежние настройки игры, чтобы вернуть их при выключении.
    private CloudRenderMode oldClouds;
    private Boolean oldShadows, oldAo;
    private ParticlesMode oldParticles;
    private Integer oldBlend;

    public Optimizer() {
        super("Оптимизатор", "FPS, частицы, сущности, графика", Category.OPTIMIZATION, false);
        INSTANCE = this;
    }

    static boolean active() {
        return INSTANCE != null && INSTANCE.isEnabled();
    }

    @Override
    public void onFrame(MinecraftClient mc, double dt) {
        itemsThisFrame = 0;
    }

    @Override
    public void onTick(MinecraftClient mc) {
        tick++;
        if (tick % 200 == 0) {
            visible.clear();
            visibleUntil.clear();
        }
        GameOptions o = mc.options;
        if (clouds.value && o.getCloudRenderMode().getValue() != CloudRenderMode.OFF) {
            if (oldClouds == null) oldClouds = o.getCloudRenderMode().getValue();
            o.getCloudRenderMode().setValue(CloudRenderMode.OFF);
        }
        if (shadows.value && o.getEntityShadows().getValue()) {
            if (oldShadows == null) oldShadows = true;
            o.getEntityShadows().setValue(false);
        }
        if (fewerParticles.value && o.getParticles().getValue() == ParticlesMode.ALL) {
            if (oldParticles == null) oldParticles = ParticlesMode.ALL;
            o.getParticles().setValue(ParticlesMode.DECREASED);
        }
        if (noAo.value && o.getAo().getValue()) {
            if (oldAo == null) oldAo = true;
            o.getAo().setValue(false);
            mc.worldRenderer.reload();
        }
        if (biomeBlend.value && o.getBiomeBlendRadius().getValue() != 0) {
            if (oldBlend == null) oldBlend = o.getBiomeBlendRadius().getValue();
            o.getBiomeBlendRadius().setValue(0);
            mc.worldRenderer.reload();
        }
    }

    @Override
    protected void onDisable() {
        MinecraftClient mc = MinecraftClient.getInstance();
        GameOptions o = mc.options;
        boolean reload = oldAo != null || oldBlend != null;
        if (oldClouds != null) o.getCloudRenderMode().setValue(oldClouds);
        if (oldShadows != null) o.getEntityShadows().setValue(oldShadows);
        if (oldParticles != null) o.getParticles().setValue(oldParticles);
        if (oldAo != null) o.getAo().setValue(oldAo);
        if (oldBlend != null) o.getBiomeBlendRadius().setValue(oldBlend);
        if (reload && mc.worldRenderer != null) mc.worldRenderer.reload();
        oldClouds = null;
        oldShadows = oldAo = null;
        oldParticles = null;
        oldBlend = null;
    }

    /** Лимит кадров: в фоне и (по желанию) в меню. */
    public static int fpsLimit(int vanilla) {
        if (!active()) return vanilla;
        MinecraftClient mc = MinecraftClient.getInstance();
        if (INSTANCE.backgroundFps.value && !mc.isWindowFocused()) return Math.min(vanilla, (int) INSTANCE.backgroundLimit.value);
        if (INSTANCE.menuFps.value && mc.currentScreen != null && !(mc.currentScreen instanceof ClickGui)) {
            return Math.min(vanilla, (int) INSTANCE.menuLimit.value);
        }
        return vanilla;
    }

    /** Не создавать частицу: часть отбрасывается, дальние — всегда. */
    public static boolean dropParticle(double x, double y, double z) {
        if (!active()) return false;
        if (ThreadLocalRandom.current().nextDouble(100) >= INSTANCE.particlePercent.value) return true;
        Vec3d cam = MinecraftClient.getInstance().gameRenderer.getCamera().getCameraPos();
        double d = INSTANCE.particleDistance.value;
        return cam.squaredDistanceTo(x, y, z) > d * d;
    }

    public static boolean hideEntity(Entity e) {
        if (!active()) return false;
        MinecraftClient mc = MinecraftClient.getInstance();
        if (mc.player == null || e == mc.player || e == mc.getCameraEntity()) return false;
        Optimizer o = INSTANCE;
        boolean player = e instanceof PlayerEntity;
        if (player && !o.hidePlayers.value) return false;
        if (e instanceof ArmorStandEntity && o.armorStands.value) return true;
        double dist = mc.player.squaredDistanceTo(e);
        double max = e instanceof ItemEntity ? o.itemDistance.value
                : e instanceof ItemFrameEntity ? o.frameDistance.value : o.entityDistance.value;
        if (dist > max * max) return true;
        if (e instanceof ItemEntity && ++o.itemsThisFrame > o.itemLimit.value) return true;
        return o.occlusion.value && dist > 12 * 12 && !o.seen(mc, e);
    }

    /** Видна ли сущность игроку; луч проверяется не чаще раза в 10 тиков. */
    private boolean seen(MinecraftClient mc, Entity e) {
        int id = e.getId();
        Long until = visibleUntil.get(id);
        if (until == null || until < tick) {
            visible.put(id, mc.player.canSee(e));
            visibleUntil.put(id, tick + 10 + (id % 5));
        }
        return visible.get(id);
    }

    public static boolean hideBlockEntity(BlockEntity be) {
        if (!active()) return false;
        Vec3d cam = MinecraftClient.getInstance().gameRenderer.getCamera().getCameraPos();
        double d = be instanceof SignBlockEntity || be instanceof HangingSignBlockEntity
                ? INSTANCE.signDistance.value : INSTANCE.blockEntityDistance.value;
        return be.getPos().toCenterPos().squaredDistanceTo(cam) > d * d;
    }

    public static boolean hideToasts() {
        return active() && INSTANCE.toasts.value;
    }
}
