package com.burgerdlc.mixin;

import com.burgerdlc.BurgerDLC;
import net.minecraft.client.render.GameRenderer;
import net.minecraft.client.render.RenderTickCounter;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(GameRenderer.class)
public class GameRendererMixin {
    /** Ротации считаются перед отрисовкой кадра, независимо от HUD и F1. */
    @Inject(method = "render", at = @At("HEAD"))
    private void burger$frame(RenderTickCounter tickCounter, boolean tick, CallbackInfo ci) {
        BurgerDLC.onFrame();
    }
}
