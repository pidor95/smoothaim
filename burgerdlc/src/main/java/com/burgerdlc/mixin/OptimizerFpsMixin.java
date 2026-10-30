package com.burgerdlc.mixin;

import com.burgerdlc.Optimizer;
import net.minecraft.client.option.InactivityFpsLimiter;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(InactivityFpsLimiter.class)
public class OptimizerFpsMixin {
    @Inject(method = "update", at = @At("RETURN"), cancellable = true)
    private void burger$limit(CallbackInfoReturnable<Integer> cir) {
        cir.setReturnValue(Optimizer.fpsLimit(cir.getReturnValue()));
    }
}
