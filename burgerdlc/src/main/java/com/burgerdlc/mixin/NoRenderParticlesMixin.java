package com.burgerdlc.mixin;

import com.burgerdlc.NoRender;
import com.burgerdlc.Optimizer;
import net.minecraft.client.particle.Particle;
import net.minecraft.particle.ParticleEffect;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;
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
    private void burger$hit(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.particles)) ci.cancel();
    }

    @Inject(method = "addEmitter(Lnet/minecraft/entity/Entity;Lnet/minecraft/particle/ParticleEffect;I)V",
            at = @At("HEAD"), cancellable = true)
    private void burger$hitCount(CallbackInfo ci) {
        if (NoRender.on(NoRender.INSTANCE.particles)) ci.cancel();
    }

    /** Оптимизатор: часть частиц и все дальние не создаём вовсе. */
    @Inject(method = "addParticle(Lnet/minecraft/particle/ParticleEffect;DDDDDD)Lnet/minecraft/client/particle/Particle;",
            at = @At("HEAD"), cancellable = true)
    private void burger$limit(ParticleEffect effect, double x, double y, double z, double vx, double vy, double vz,
                              CallbackInfoReturnable<Particle> cir) {
        if (Optimizer.dropParticle(x, y, z)) cir.setReturnValue(null);
    }
}
