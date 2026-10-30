package com.example.smoothaim.mixin;

import com.example.smoothaim.NoRender;
import net.minecraft.client.gui.hud.InGameOverlayRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(InGameOverlayRenderer.class)
public class NoRenderOverlayMixin {
    @Inject(method = "renderFireOverlay", at = @At("HEAD"), cancellable = true)
    private static void smoothaim$fire(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.fire)) ci.cancel();
    }

    @Inject(method = {"renderUnderwaterOverlay", "renderInWallOverlay"}, at = @At("HEAD"), cancellable = true)
    private static void smoothaim$liquid(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.liquid)) ci.cancel();
    }
}
