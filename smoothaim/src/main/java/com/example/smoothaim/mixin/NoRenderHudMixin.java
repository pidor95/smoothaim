package com.example.smoothaim.mixin;

import com.example.smoothaim.NoRender;
import net.minecraft.client.gui.hud.InGameHud;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(InGameHud.class)
public class NoRenderHudMixin {
    @Inject(method = "renderBossBarHud", at = @At("HEAD"), cancellable = true)
    private void smoothaim$bossBar(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.bossBar)) ci.cancel();
    }

    @Inject(method = "renderScoreboardSidebar(Lnet/minecraft/client/gui/DrawContext;Lnet/minecraft/client/render/RenderTickCounter;)V",
            at = @At("HEAD"), cancellable = true)
    private void smoothaim$scoreboard(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.scoreboard)) ci.cancel();
    }

    @Inject(method = "renderStatusEffectOverlay", at = @At("HEAD"), cancellable = true)
    private void smoothaim$effects(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.effects)) ci.cancel();
    }

    @Inject(method = "renderAirBubbles", at = @At("HEAD"), cancellable = true)
    private void smoothaim$air(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.air)) ci.cancel();
    }

    @Inject(method = "renderVignetteOverlay", at = @At("HEAD"), cancellable = true)
    private void smoothaim$vignette(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.vignette)) ci.cancel();
    }

    @Inject(method = {"renderNauseaOverlay", "renderPortalOverlay"}, at = @At("HEAD"), cancellable = true)
    private void smoothaim$nausea(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.nausea)) ci.cancel();
    }
}
