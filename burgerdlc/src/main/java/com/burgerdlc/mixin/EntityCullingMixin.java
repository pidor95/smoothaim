package com.burgerdlc.mixin;

import com.burgerdlc.EntityCulling;
import net.minecraft.client.render.Frustum;
import net.minecraft.client.render.entity.EntityRenderManager;
import net.minecraft.entity.Entity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(EntityRenderManager.class)
public class EntityCullingMixin {
    @Inject(method = "shouldRender", at = @At("HEAD"), cancellable = true)
    private <E extends Entity> void burger$cull(E entity, Frustum frustum, double x, double y, double z,
                                                CallbackInfoReturnable<Boolean> cir) {
        if (EntityCulling.hide(entity)) cir.setReturnValue(false);
    }
}
