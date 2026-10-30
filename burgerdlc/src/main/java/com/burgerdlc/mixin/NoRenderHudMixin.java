package com.burgerdlc.mixin;

import com.burgerdlc.NoRender;
import net.minecraft.client.gui.hud.InGameHud;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(InGameHud.class)
public class NoRenderHudMixin {
    @Inject(method = "renderBossBarHud", at = @At("HEAD"), cancellable = true)
    private void burger$bossBar(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.bossBar)) ci.cancel();
    }

    @Inject(method = "renderScoreboardSidebar(Lnet/minecraft/client/gui/DrawContext;Lnet/minecraft/client/render/RenderTickCounter;)V",
            at = @At("HEAD"), cancellable = true)
    private void burger$scoreboard(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.scoreboard)) ci.cancel();
    }

    @Inject(method = "renderStatusEffectOverlay", at = @At("HEAD"), cancellable = true)
    private void burger$effects(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.effects)) ci.cancel();
    }

    @Inject(method = "renderAirBubbles", at = @At("HEAD"), cancellable = true)
    private void burger$air(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.air)) ci.cancel();
    }

    @Inject(method = "renderVignetteOverlay", at = @At("HEAD"), cancellable = true)
    private void burger$vignette(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.vignette)) ci.cancel();
    }

    @Inject(method = {"renderNauseaOverlay", "renderPortalOverlay"}, at = @At("HEAD"), cancellable = true)
    private void burger$nausea(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.nausea)) ci.cancel();
    }
}
