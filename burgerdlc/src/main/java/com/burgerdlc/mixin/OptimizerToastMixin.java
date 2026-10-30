package com.burgerdlc.mixin;

import com.burgerdlc.Optimizer;
import net.minecraft.client.toast.ToastManager;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ToastManager.class)
public class OptimizerToastMixin {
    @Inject(method = "add", at = @At("HEAD"), cancellable = true)
    private void burger$toast(CallbackInfo ci) {
        if (Optimizer.hideToasts()) ci.cancel();
    }
}
