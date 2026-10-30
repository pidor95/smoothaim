package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.option.CloudRenderMode;
import net.minecraft.client.option.GameOptions;
import net.minecraft.particle.ParticlesMode;

/** Ставит лёгкие настройки графики, а при выключении возвращает прежние. */
public class FastSettings extends Module {
    final Setting.Bool clouds = add(new Setting.Bool("Без облаков", true));
    final Setting.Bool shadows = add(new Setting.Bool("Без теней сущностей", true));
    final Setting.Bool particles = add(new Setting.Bool("Частицы: меньше", true));
    final Setting.Bool biomeBlend = add(new Setting.Bool("Без смешивания биомов", false));

    private CloudRenderMode oldClouds;
    private Boolean oldShadows;
    private ParticlesMode oldParticles;
    private Integer oldBlend;

    public FastSettings() {
        super("Fast Settings", "Облака, тени, частицы — в минимум", Category.OPTIMIZATION, false);
    }

    @Override
    public void onTick(MinecraftClient mc) {
        GameOptions o = mc.options;
        if (clouds.value && o.getCloudRenderMode().getValue() != CloudRenderMode.OFF) {
            if (oldClouds == null) oldClouds = o.getCloudRenderMode().getValue();
            o.getCloudRenderMode().setValue(CloudRenderMode.OFF);
        }
        if (shadows.value && o.getEntityShadows().getValue()) {
            if (oldShadows == null) oldShadows = true;
            o.getEntityShadows().setValue(false);
        }
        if (particles.value && o.getParticles().getValue() == ParticlesMode.ALL) {
            if (oldParticles == null) oldParticles = ParticlesMode.ALL;
            o.getParticles().setValue(ParticlesMode.DECREASED);
        }
        if (biomeBlend.value && o.getBiomeBlendRadius().getValue() != 0) {
            if (oldBlend == null) oldBlend = o.getBiomeBlendRadius().getValue();
            o.getBiomeBlendRadius().setValue(0);
            mc.worldRenderer.reload();
        }
    }

    @Override
    protected void onDisable() {
        GameOptions o = MinecraftClient.getInstance().options;
        if (oldClouds != null) o.getCloudRenderMode().setValue(oldClouds);
        if (oldShadows != null) o.getEntityShadows().setValue(oldShadows);
        if (oldParticles != null) o.getParticles().setValue(oldParticles);
        if (oldBlend != null) {
            o.getBiomeBlendRadius().setValue(oldBlend);
            MinecraftClient.getInstance().worldRenderer.reload();
        }
        oldClouds = null;
        oldShadows = null;
        oldParticles = null;
        oldBlend = null;
    }
}
