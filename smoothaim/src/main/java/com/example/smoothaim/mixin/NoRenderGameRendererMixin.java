package com.example.smoothaim.mixin;

import com.example.smoothaim.NoRender;
import net.minecraft.client.render.GameRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(GameRenderer.class)
public class NoRenderGameRendererMixin {
    @Inject(method = "tiltViewWhenHurt", at = @At("HEAD"), cancellable = true)
    private void smoothaim$hurtCam(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.hurtCam)) ci.cancel();
    }

    @Inject(method = "showFloatingItem", at = @At("HEAD"), cancellable = true)
    private void smoothaim$totem(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.totem)) ci.cancel();
    }
}
