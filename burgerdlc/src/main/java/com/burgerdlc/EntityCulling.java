package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.entity.ItemEntity;
import net.minecraft.entity.decoration.ArmorStandEntity;
import net.minecraft.entity.decoration.ItemFrameEntity;
import net.minecraft.entity.player.PlayerEntity;

/** Не рисовать дальние и бесполезные сущности — главный источник лагов на ивентах и спавне. */
public class EntityCulling extends Module {
    public static EntityCulling INSTANCE;

    final Setting.Num distance = add(new Setting.Num("Дистанция сущностей", 64, 16, 160, 8));
    final Setting.Num itemDistance = add(new Setting.Num("Дистанция предметов", 24, 4, 64, 2));
    final Setting.Bool armorStands = add(new Setting.Bool("Скрыть стойки для брони", false));
    final Setting.Bool itemFrames = add(new Setting.Bool("Скрыть рамки", false));
    final Setting.Bool keepPlayers = add(new Setting.Bool("Игроков не скрывать", true));

    public EntityCulling() {
        super("Entity Culling", "Не рисует дальние сущности", Category.OPTIMIZATION, false);
        INSTANCE = this;
    }

    public static boolean hide(Entity e) {
        if (INSTANCE == null || !INSTANCE.isEnabled()) return false;
        MinecraftClient mc = MinecraftClient.getInstance();
        if (mc.player == null || e == mc.player || e == mc.getCameraEntity()) return false;
        EntityCulling c = INSTANCE;
        if (e instanceof PlayerEntity && c.keepPlayers.value) return false;
        if (e instanceof ArmorStandEntity && c.armorStands.value) return true;
        if (e instanceof ItemFrameEntity && c.itemFrames.value) return true;
        double max = e instanceof ItemEntity ? c.itemDistance.value : c.distance.value;
        return mc.player.squaredDistanceTo(e) > max * max;
    }
}
