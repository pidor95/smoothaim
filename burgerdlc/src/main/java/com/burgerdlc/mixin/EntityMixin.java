package com.burgerdlc.mixin;

import com.burgerdlc.ESP;
import net.minecraft.entity.Entity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(Entity.class)
public class EntityMixin {
    /** Цвет контура свечения берётся из цвета команды — для ESP подменяем на свой. */
    @Inject(method = "getTeamColorValue", at = @At("HEAD"), cancellable = true)
    private void burger$glowColor(CallbackInfoReturnable<Integer> cir) {
        Entity self = (Entity) (Object) this;
        if (self.getEntityWorld().isClient() && ESP.glows(self)) cir.setReturnValue(ESP.glowColor(self));
    }
}
