package com.example.smoothaim.mixin;

import com.example.smoothaim.NoRender;
import net.minecraft.client.particle.ParticleManager;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ParticleManager.class)
public class NoRenderParticlesMixin {
    /** Эмиттеры — это частицы крита и острия при ударах. */
    @Inject(method = "addEmitter(Lnet/minecraft/entity/Entity;Lnet/minecraft/particle/ParticleEffect;)V",
            at = @At("HEAD"), cancellable = true)
    private void smoothaim$hit(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.particles)) ci.cancel();
    }

    @Inject(method = "addEmitter(Lnet/minecraft/entity/Entity;Lnet/minecraft/particle/ParticleEffect;I)V",
            at = @At("HEAD"), cancellable = true)
    private void smoothaim$hitCount(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.particles)) ci.cancel();
    }
}
