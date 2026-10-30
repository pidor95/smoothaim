package com.burgerdlc.mixin;

import com.burgerdlc.BurgerDLC;
import net.minecraft.client.network.ClientPlayerInteractionManager;
import net.minecraft.entity.Entity;
import net.minecraft.entity.player.PlayerEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ClientPlayerInteractionManager.class)
public class AttackMixin {
    @Inject(method = "attackEntity", at = @At("HEAD"))
    private void burger$attack(PlayerEntity player, Entity target, CallbackInfo ci) {
        BurgerDLC.onAttack(target);
    }
}
