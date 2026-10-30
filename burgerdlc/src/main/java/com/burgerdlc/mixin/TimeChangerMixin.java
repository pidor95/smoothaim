package com.burgerdlc.mixin;

import com.burgerdlc.TimeChanger;
import net.minecraft.client.world.ClientWorld;
import net.minecraft.world.World;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(World.class)
public class TimeChangerMixin {
    @Inject(method = "getTimeOfDay", at = @At("HEAD"), cancellable = true)
    private void burger$time(CallbackInfoReturnable<Long> cir) {
        long t = TimeChanger.override();
        if (t >= 0 && (Object) this instanceof ClientWorld) cir.setReturnValue(t);
    }
}
