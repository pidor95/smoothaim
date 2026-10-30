package com.burgerdlc.mixin;

import com.burgerdlc.NoRender;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.world.World;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(World.class)
public class NoRenderWorldMixin {
    /** Без дождя и грозы на клиенте: ни осадков, ни затемнения неба. */
    @Inject(method = {"getRainGradient", "getThunderGradient"}, at = @At("HEAD"), cancellable = true)
    private void burger$weather(float delta, CallbackInfoReturnable<Float> cir) {
        if ((Object) this instanceof ClientWorld && NoRender.on(NoRender.INSTANCE.weather)) cir.setReturnValue(0f);
    }
}
