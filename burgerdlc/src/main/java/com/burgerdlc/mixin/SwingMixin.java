package com.burgerdlc.mixin;

import com.burgerdlc.SwingAnimation;
import net.minecraft.client.MinecraftClient;
import net.minecraft.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(LivingEntity.class)
public class SwingMixin {
    @Inject(method = "getHandSwingDuration", at = @At("RETURN"), cancellable = true)
    private void burger$swing(CallbackInfoReturnable<Integer> cir) {
        if ((Object) this == MinecraftClient.getInstance().player) {
            cir.setReturnValue(SwingAnimation.duration(cir.getReturnValue()));
        }
    }
}
