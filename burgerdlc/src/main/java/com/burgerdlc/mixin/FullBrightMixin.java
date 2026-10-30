package com.burgerdlc.mixin;

import com.burgerdlc.FullBright;
import com.llamalad7.mixinextras.injector.ModifyExpressionValue;
import net.minecraft.client.render.LightmapTextureManager;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;

@Mixin(LightmapTextureManager.class)
public class FullBrightMixin {
    /** Третий getValue() в update — это options.getGamma().getValue(). */
    @ModifyExpressionValue(method = "update", at = @At(value = "INVOKE",
            target = "Lnet/minecraft/client/option/SimpleOption;getValue()Ljava/lang/Object;", ordinal = 2))
    private Object burger$gamma(Object original) {
        return FullBright.gammaOr((Double) original);
    }
}
