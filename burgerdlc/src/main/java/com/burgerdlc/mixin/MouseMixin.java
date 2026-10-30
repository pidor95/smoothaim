package com.burgerdlc.mixin;

import com.burgerdlc.Binds;
import net.minecraft.client.Mouse;
import net.minecraft.client.input.MouseInput;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Mouse.class)
public class MouseMixin {
    @Inject(method = "onMouseButton", at = @At("HEAD"))
    private void burger$onMouseButton(long window, MouseInput input, int action, CallbackInfo ci) {
        Binds.onMouse(input.button(), action);
    }
}
