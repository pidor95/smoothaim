package com.burgerdlc.mixin;

import com.burgerdlc.ViewModel;
import net.minecraft.client.network.AbstractClientPlayerEntity;
import net.minecraft.client.render.command.OrderedRenderCommandQueue;
import net.minecraft.client.render.item.HeldItemRenderer;
import net.minecraft.client.util.math.MatrixStack;
import net.minecraft.item.ItemStack;
import net.minecraft.util.Hand;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(HeldItemRenderer.class)
public class ViewModelMixin {
    @Inject(method = "renderFirstPersonItem", at = @At("HEAD"))
    private void burger$push(AbstractClientPlayerEntity player, float tickProgress, float pitch, Hand hand,
                                float swing, ItemStack item, float equip, MatrixStack matrices,
                                OrderedRenderCommandQueue queue, int light, CallbackInfo ci) {
        matrices.push();
        ViewModel.apply(matrices, hand);
    }

    @Inject(method = "renderFirstPersonItem", at = @At("RETURN"))
    private void burger$pop(AbstractClientPlayerEntity player, float tickProgress, float pitch, Hand hand,
                               float swing, ItemStack item, float equip, MatrixStack matrices,
                               OrderedRenderCommandQueue queue, int light, CallbackInfo ci) {
        matrices.pop();
    }
}
