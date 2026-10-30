package com.example.smoothaim;

import net.fabricmc.fabric.api.client.gametest.v1.FabricClientGameTest;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestSingleplayerContext;
import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.screen.ingame.InventoryScreen;
import net.minecraft.entity.mob.ZombieEntity;
import net.minecraft.util.hit.EntityHitResult;
import net.minecraft.util.math.MathHelper;
import net.minecraft.util.math.Vec3d;
import org.lwjgl.glfw.GLFW;

public class SmoothAimClientGameTest implements FabricClientGameTest {
    @Override
    public void runTest(ClientGameTestContext ctx) {
        try (TestSingleplayerContext sp = ctx.worldBuilder().create()) {
            sp.getClientWorld().waitForChunksRender();
            TestServerContext srv = sp.getServer();
            srv.runCommand("difficulty easy");
            srv.runCommand("gamemode survival @a");
            srv.runCommand("item replace entity @a weapon.mainhand with minecraft:diamond_sword");
            srv.runCommand("execute as @a at @s run tp @s ~ ~ ~ 0 0");
            ctx.waitTicks(5);

            AimBot aim = module(AimBot.class);
            TriggerBot trigger = module(TriggerBot.class);
            ctx.runOnClient(mc -> {
                aim.setEnabled(true);
                aim.activation.index = 1; // Всегда
                aim.filter.mobs.value = true;
                trigger.setEnabled(false);
                trigger.filter.mobs.value = true;
            });

            // AimBot: зомби сбоку, прицел должен довестись на него.
            srv.runCommand("execute at @a run summon minecraft:zombie ~1.2 ~ ~2.8 "
                    + "{NoAI:1b,PersistenceRequired:1b,Silent:1b}");
            ctx.waitFor(mc -> zombie(mc) != null);
            double before = ctx.computeOnClient(SmoothAimClientGameTest::angleToZombie);
            for (int i = 0; i < 6; i++) {
                ctx.waitTicks(5);
                System.out.println("[smoothaim-test] " + ctx.computeOnClient(mc -> String.format(
                        "угол=%.1f target=%s screen=%s yaw=%.1f pitch=%.1f",
                        angleToZombie(mc), aim.target, mc.currentScreen, mc.player.getYaw(), mc.player.getPitch())));
            }
            ctx.takeScreenshot("smoothaim-aim-debug");
            ctx.waitFor(mc -> mc.crosshairTarget instanceof EntityHitResult h && h.getEntity() instanceof ZombieEntity, 60);
            double after = ctx.computeOnClient(SmoothAimClientGameTest::angleToZombie);
            ctx.takeScreenshot("smoothaim-aim");
            System.out.printf("[smoothaim-test] AimBot: угол до зомби %.1f° -> %.1f°%n", before, after);

            // TriggerBot: прицел на зомби — должен ударить сам.
            ctx.runOnClient(mc -> trigger.setEnabled(true));
            ctx.waitFor(mc -> zombie(mc) == null || zombie(mc).getHealth() < zombie(mc).getMaxHealth(), 60);
            System.out.println("[smoothaim-test] TriggerBot: зомби получил урон");
            ctx.runOnClient(mc -> trigger.setEnabled(false));

            // Бинд: R переключает AimBot.
            boolean was = ctx.computeOnClient(mc -> aim.isEnabled());
            ctx.getInput().pressKey(GLFW.GLFW_KEY_R);
            ctx.waitTick();
            boolean now = ctx.computeOnClient(mc -> aim.isEnabled());
            if (was == now) throw new AssertionError("Бинд R не переключил AimBot");
            System.out.println("[smoothaim-test] Бинд R: AimBot " + was + " -> " + now);
            ctx.getInput().pressKey(GLFW.GLFW_KEY_R);
            ctx.waitTick();

            // InvMove: в открытом инвентаре W двигает игрока.
            Vec3d start = ctx.computeOnClient(mc -> mc.player.getEntityPos());
            ctx.setScreen(() -> new InventoryScreen(MinecraftClient.getInstance().player));
            ctx.getInput().holdKeyFor(GLFW.GLFW_KEY_W, 20);
            double moved = ctx.computeOnClient(mc -> mc.player.getEntityPos().distanceTo(start));
            if (moved < 1) throw new AssertionError("InvMove: игрок не сдвинулся (" + moved + ")");
            System.out.printf("[smoothaim-test] InvMove: прошёл %.2f блока в инвентаре%n", moved);
            ctx.setScreen(() -> null);

            // Меню: открыть, раскрыть AimBot кликом, сделать скриншоты.
            ctx.setScreen(ClickGui::new);
            ctx.waitTicks(10);
            ctx.takeScreenshot("smoothaim-gui");
            double[] card = ctx.computeOnClient(mc -> {
                int w = mc.getWindow().getScaledWidth(), h = mc.getWindow().getScaledHeight();
                int size = Math.min(360, Math.min(w, h) - 16);
                int px = (w - size) / 2, py = (h - size) / 2;
                double scale = mc.getWindow().getScaleFactor();
                return new double[]{(px + 84 + 8 + 40) * scale, (py + 28 + 8 + 15) * scale};
            });
            ctx.getInput().setCursorPos(card[0], card[1]);
            ctx.getInput().pressMouse(GLFW.GLFW_MOUSE_BUTTON_LEFT);
            ctx.waitTicks(10);
            ctx.takeScreenshot("smoothaim-gui-aimbot");
            ctx.setScreen(() -> null);
        }
    }

    @SuppressWarnings("unchecked")
    private static <T extends Module> T module(Class<T> type) {
        for (Module m : SmoothAim.MODULES) {
            if (type.isInstance(m)) return (T) m;
        }
        throw new AssertionError("Нет модуля " + type.getSimpleName());
    }

    private static ZombieEntity zombie(MinecraftClient mc) {
        for (var e : mc.world.getEntities()) {
            if (e instanceof ZombieEntity z && z.isAlive()) return z;
        }
        return null;
    }

    private static double angleToZombie(MinecraftClient mc) {
        Vec3d d = zombie(mc).getBoundingBox().getCenter().subtract(mc.player.getEyePos()).normalize();
        return Math.toDegrees(Math.acos(MathHelper.clamp(d.dotProduct(mc.player.getRotationVec(1f)), -1, 1)));
    }
}
