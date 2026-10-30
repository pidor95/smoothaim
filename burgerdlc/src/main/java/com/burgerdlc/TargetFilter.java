package com.burgerdlc;

import net.minecraft.entity.Entity;
import net.minecraft.entity.LivingEntity;
import net.minecraft.entity.decoration.ArmorStandEntity;
import net.minecraft.entity.mob.Monster;
import net.minecraft.entity.passive.AnimalEntity;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.item.AxeItem;
import net.minecraft.item.ItemStack;
import net.minecraft.registry.tag.ItemTags;

/** Общие настройки «по кому работать» для боевых модулей. */
final class TargetFilter {
    final Setting.Bool players, mobs, animals, invisibles, teams;

    TargetFilter(Module m) {
        players = m.add(new Setting.Bool("Игроки", true));
        mobs = m.add(new Setting.Bool("Мобы", false));
        animals = m.add(new Setting.Bool("Животные", false));
        invisibles = m.add(new Setting.Bool("Невидимые", true));
        teams = m.add(new Setting.Bool("Не бить своих", true));
    }

    boolean test(PlayerEntity self, Entity e) {
        if (e == self || !(e instanceof LivingEntity living)) return false;
        if (!living.isAlive() || living.getHealth() <= 0 || e instanceof ArmorStandEntity) return false;
        if (e.isInvisible() && !invisibles.value) return false;
        if (teams.value && self.isTeammate(e)) return false;
        if (e instanceof PlayerEntity pl) return players.value && !pl.isSpectator() && !pl.isCreative();
        if (e instanceof Monster) return mobs.value;
        if (e instanceof AnimalEntity) return animals.value;
        return false;
    }

    static boolean holdingWeapon(PlayerEntity p) {
        ItemStack stack = p.getMainHandStack();
        return stack.isIn(ItemTags.SWORDS) || stack.getItem() instanceof AxeItem;
    }
}
