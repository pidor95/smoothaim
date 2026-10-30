package com.burgerdlc.mixin;

import com.burgerdlc.ESP;
import com.burgerdlc.NoRender;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.Entity;
import net.minecraft.entity.player.PlayerEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(MinecraftClient.class)
public class NoRenderMiscMixin {
    @Inject(method = "hasOutline", at = @At("HEAD"), cancellable = true)
    private void burger$glow(Entity entity, CallbackInfoReturnable<Boolean> cir) {
        if (ESP.glows(entity)) cir.setReturnValue(true);
        else if (entity instanceof PlayerEntity && NoRender.on(NoRender.INSTANCE.glow)) cir.setReturnValue(false);
    }
}
