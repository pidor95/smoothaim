package com.example.smoothaim.mixin;

import com.example.smoothaim.Binds;
import net.minecraft.client.Keyboard;
import net.minecraft.client.input.KeyInput;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Keyboard.class)
public class KeyboardMixin {
    @Inject(method = "onKey", at = @At("HEAD"))
    private void smoothaim$onKey(long window, int action, KeyInput input, CallbackInfo ci) {
        Binds.onKey(input.key(), action);
    }
}
