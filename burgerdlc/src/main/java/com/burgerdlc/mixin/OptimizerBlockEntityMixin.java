package com.burgerdlc.mixin;

import com.burgerdlc.Optimizer;
import net.minecraft.block.entity.BlockEntity;
import net.minecraft.client.render.block.entity.BlockEntityRenderManager;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

@Mixin(BlockEntityRenderManager.class)
public class OptimizerBlockEntityMixin {
    /** null — то же, что ваниль возвращает для блок-энтити вне дистанции отрисовки. */
    @Inject(method = "getRenderState", at = @At("HEAD"), cancellable = true)
    private void burger$cull(BlockEntity blockEntity, float tickProgress,
                             net.minecraft.client.render.command.ModelCommandRenderer.CrumblingOverlayCommand crumbling,
                             CallbackInfoReturnable<Object> cir) {
        if (Optimizer.hideBlockEntity(blockEntity)) cir.setReturnValue(null);
    }
}
