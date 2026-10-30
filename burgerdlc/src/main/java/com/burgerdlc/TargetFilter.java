package com.burgerdlc;

import net.minecraft.entity.Entity;
import net.minecraft.entity.LivingEntity;
import net.minecraft.entity.decoration.ArmorStandEntity;
import net.minecraft.entity.mob.Monster;
import net.minecraft.entity.passive.AnimalEntity;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.item.AxeItem;
import net.minecraft.item.ItemStack;
import net.minecraft.item.Items;
import net.minecraft.registry.tag.ItemTags;

/** Общие настройки «по кому работать» для боевых модулей. */
final class TargetFilter {
    final Setting.Bool players, mobs, animals, invisibles, teams;

    TargetFilter(Module m) {
        players = m.add(new Setting.Bool("Игроки", true));
        mobs = m.add(new Setting.Bool("Мобы", false));
        animals = m.add(new Setting.Bool("Животные", false));
        invisibles = m.add(new Setting.Bool("Невидимые", true));
        // По умолчанию выкл.: на серверах плагины таба кладут всех игроков в скорборд-команды,
        // и ванильная проверка «в одной команде» отсеивает вообще всех.
        teams = m.add(new Setting.Bool("Не бить свою команду", false));
    }

    boolean test(PlayerEntity self, Entity e) {
        return reject(self, e) == null;
    }

    /** Почему сущность не подходит, или null, если подходит. Для отладки показывается на экране. */
    String reject(PlayerEntity self, Entity e) {
        if (e == self || !(e instanceof LivingEntity living) || e instanceof ArmorStandEntity) return "не цель";
        // Античиты часто прячут HP чужих игроков (присылают 0), и клиент тогда сам считает их мёртвыми
        // (isAlive, deathTime). Поэтому игрок мёртв, только когда сервер убрал его из мира.
        if (living.isRemoved()) return "мёртв";
        if (!(e instanceof PlayerEntity) && !living.isAlive()) return "мёртв";
        if (e.isInvisible() && !invisibles.value) return "невидимый";
        if (teams.value && self.isTeammate(e)) return "твоя команда";
        if (e instanceof PlayerEntity pl) {
            if (!players.value) return "игроки выключены";
            if (pl.isSpectator()) return "наблюдатель";
            if (pl.isCreative()) return "креатив";
            return null;
        }
        if (e instanceof Monster) return mobs.value ? null : "мобы выключены";
        if (e instanceof AnimalEntity) return animals.value ? null : "животные выключены";
        return "не цель";
    }

    static boolean holdingWeapon(PlayerEntity p) {
        ItemStack stack = p.getMainHandStack();
        return stack.isIn(ItemTags.SWORDS) || stack.getItem() instanceof AxeItem || stack.isOf(Items.MACE);
    }
}
