package com.burgerdlc;

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

public class BurgerClientGameTest implements FabricClientGameTest {
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
            double before = ctx.computeOnClient(BurgerClientGameTest::angleToZombie);
            for (int i = 0; i < 6; i++) {
                ctx.waitTicks(5);
                System.out.println("[burgerdlc-test] " + ctx.computeOnClient(mc -> String.format(
                        "угол=%.1f target=%s screen=%s yaw=%.1f pitch=%.1f",
                        angleToZombie(mc), aim.target, mc.currentScreen, mc.player.getYaw(), mc.player.getPitch())));
            }
            ctx.takeScreenshot("burger-aim-debug");
            ctx.waitFor(mc -> mc.crosshairTarget instanceof EntityHitResult h && h.getEntity() instanceof ZombieEntity, 60);
            double after = ctx.computeOnClient(BurgerClientGameTest::angleToZombie);
            ctx.takeScreenshot("burger-aim");
            System.out.printf("[burgerdlc-test] AimBot: угол до зомби %.1f° -> %.1f°%n", before, after);

            // AimBot по игроку как на сервере: оба в одной скорборд-команде (плагин таба), HP спрятано.
            srv.runCommand("kill @e[type=minecraft:zombie]");
            srv.runCommand("execute as @a at @s run tp @s ~ ~ ~ 0 0");
            ctx.waitTicks(5);
            ctx.runOnClient(mc -> {
                aim.filter.mobs.value = false;
                var enemy = new net.minecraft.client.network.OtherClientPlayerEntity(mc.world,
                        new com.mojang.authlib.GameProfile(java.util.UUID.randomUUID(), "Enemy"));
                enemy.setId(424242);
                Vec3d pos = mc.player.getEntityPos().add(-1.6, 0, 2.6);
                enemy.refreshPositionAndAngles(pos.x, pos.y, pos.z, 180, 0);
                enemy.setHealth(0); // античит прячет HP
                mc.world.addEntity(enemy);
                var sb = mc.world.getScoreboard();
                var team = sb.addTeam("tab_prefix");
                sb.addScoreHolderToTeam(mc.player.getNameForScoreboard(), team);
                sb.addScoreHolderToTeam("Enemy", team);
                aim.debug.value = true;
            });
            ctx.waitTicks(20);
            ctx.takeScreenshot("burger-aim-player-debug");
            System.out.println("[burger-test] player debug: " + ctx.computeOnClient(mc -> {
                var e = mc.world.getEntityById(424242);
                return "entity=" + e + " target=" + aim.target + " crosshair=" + mc.crosshairTarget.getType()
                        + (e == null ? "" : " reject=" + aim.filter.reject(mc.player, e) + " canSee=" + mc.player.canSee(e)
                        + " dist=" + mc.player.distanceTo(e));
            }));
            ctx.waitFor(mc -> mc.crosshairTarget instanceof EntityHitResult h
                    && h.getEntity() instanceof net.minecraft.entity.player.PlayerEntity, 60);
            ctx.takeScreenshot("burger-aim-player");
            System.out.println("[burger-test] AimBot по игроку (одна команда, HP скрыто): навёлся");
            ctx.runOnClient(mc -> {
                mc.world.removeEntity(424242, net.minecraft.entity.Entity.RemovalReason.DISCARDED);
                aim.filter.mobs.value = true;
                aim.debug.value = false;
            });
            srv.runCommand("execute at @a run summon minecraft:zombie ~1.2 ~ ~2.8 {NoAI:1b,PersistenceRequired:1b,Silent:1b}");
            ctx.waitFor(mc -> zombie(mc) != null);
            srv.runCommand("execute as @a at @s run tp @s ~ ~ ~ 0 0");
            ctx.waitFor(mc -> mc.crosshairTarget instanceof EntityHitResult h && h.getEntity() instanceof ZombieEntity, 60);

            // TriggerBot: прицел на зомби — должен ударить сам.
            ctx.runOnClient(mc -> trigger.setEnabled(true));
            ctx.waitFor(mc -> zombie(mc) == null || zombie(mc).getHealth() < zombie(mc).getMaxHealth(), 60);
            System.out.println("[burgerdlc-test] TriggerBot: зомби получил урон");
            ctx.runOnClient(mc -> trigger.setEnabled(false));

            // Бинд: R переключает AimBot.
            boolean was = ctx.computeOnClient(mc -> aim.isEnabled());
            ctx.getInput().pressKey(GLFW.GLFW_KEY_R);
            ctx.waitTick();
            boolean now = ctx.computeOnClient(mc -> aim.isEnabled());
            if (was == now) throw new AssertionError("Бинд R не переключил AimBot");
            System.out.println("[burgerdlc-test] Бинд R: AimBot " + was + " -> " + now);
            ctx.getInput().pressKey(GLFW.GLFW_KEY_R);
            ctx.waitTick();

            // InvMove: в открытом инвентаре W двигает игрока.
            Vec3d start = ctx.computeOnClient(mc -> mc.player.getEntityPos());
            ctx.setScreen(() -> new InventoryScreen(MinecraftClient.getInstance().player));
            ctx.getInput().holdKeyFor(GLFW.GLFW_KEY_W, 20);
            double moved = ctx.computeOnClient(mc -> mc.player.getEntityPos().distanceTo(start));
            if (moved < 1) throw new AssertionError("InvMove: игрок не сдвинулся (" + moved + ")");
            System.out.printf("[burgerdlc-test] InvMove: прошёл %.2f блока в инвентаре%n", moved);
            ctx.setScreen(() -> null);

            // NoRender: все пункты, гроза и огонь — игра не должна упасть, небо без дождя.
            ctx.runOnClient(mc -> {
                NoRender.INSTANCE.setEnabled(true);
                for (Setting st : NoRender.INSTANCE.settings) ((Setting.Bool) st).value = true;
            });
            srv.runCommand("weather thunder");
            srv.runCommand("gamemode creative @a");
            srv.runCommand("execute at @a run setblock ~ ~ ~ minecraft:fire");
            ctx.waitTicks(40);
            float rain = ctx.computeOnClient(mc -> mc.world.getRainGradient(1f));
            if (rain != 0f) throw new AssertionError("NoRender: погода не убрана, rain=" + rain);
            ctx.takeScreenshot("burger-norender");
            System.out.println("[burgerdlc-test] NoRender: гроза и огонь скрыты, rain=" + rain);
            srv.runCommand("execute at @a run setblock ~ ~ ~ minecraft:air");

            // Визуалы: от третьего лица, шляпа, след, круги от прыжка, метка и частицы на зомби.
            ctx.runOnClient(mc -> {
                NoRender.INSTANCE.setEnabled(false);
                for (Module m : BurgerDLC.MODULES) {
                    if (m.category == Category.VISUALS && !(m instanceof Crosshair) && !(m instanceof TimeChanger)) m.setEnabled(true);
                }
                module(TargetESP.class).hold.value = 30;
                mc.options.setPerspective(net.minecraft.client.option.Perspective.THIRD_PERSON_BACK);
            });
            srv.runCommand("weather clear");
            srv.runCommand("gamemode survival @a");
            srv.runCommand("kill @e[type=minecraft:zombie]");
            srv.runCommand("execute as @a at @s run tp @s ~ ~ ~ 0 0");
            srv.runCommand("execute at @a run summon minecraft:zombie ~ ~ ~2.5 {NoAI:1b,PersistenceRequired:1b,Silent:1b,Health:500f,Attributes:[{id:\"minecraft:max_health\",base:500}]}");
            ctx.waitFor(mc -> zombie(mc) != null);
            ctx.waitTicks(5);
            ctx.runOnClient(mc -> mc.interactionManager.attackEntity(mc.player, zombie(mc)));
            ctx.getInput().holdKeyFor(GLFW.GLFW_KEY_D, 12);
            ctx.getInput().pressKey(GLFW.GLFW_KEY_SPACE);
            ctx.waitTicks(6);
            ctx.takeScreenshot("burger-visuals");
            System.out.println("[burger-test] Визуалы: отрисованы без ошибок");

            // ESP: зомби впереди — 2D коробка, HP, ник, свечение, трейсер. Плюс вся оптимизация.
            ctx.runOnClient(mc -> {
                for (Module m : BurgerDLC.MODULES) {
                    if (m.category == Category.VISUALS && !(m instanceof ESP)) m.setEnabled(false);
                    if (m instanceof Optimizer) m.setEnabled(true);
                }
                ESP esp = module(ESP.class);
                esp.setEnabled(true);
                esp.mobs.value = true;
                esp.glow.value = true;
                esp.tracers.value = true;
                mc.options.setPerspective(net.minecraft.client.option.Perspective.FIRST_PERSON);
            });
            srv.runCommand("execute as @a at @s run tp @s ~ ~ ~ 0 0");
            srv.runCommand("tp @e[type=minecraft:zombie] @p");
            srv.runCommand("execute as @e[type=minecraft:zombie] at @s run tp @s ~1.5 ~ ~6");
            srv.runCommand("execute at @a run summon minecraft:zombie ~-2 ~ ~9 {NoAI:1b,PersistenceRequired:1b,Silent:1b}");
            ctx.waitTicks(20);
            ctx.takeScreenshot("burger-esp-2d");
            ctx.runOnClient(mc -> module(ESP.class).box.index = 1);
            ctx.waitTicks(5);
            ctx.takeScreenshot("burger-esp-3d");
            boolean cloudsOff = ctx.computeOnClient(mc -> mc.options.getCloudRenderMode().getValue() == net.minecraft.client.option.CloudRenderMode.OFF);
            if (!cloudsOff) throw new AssertionError("Fast Settings не выключил облака");
            System.out.println("[burger-test] ESP и оптимизация: без ошибок, облака выключены");
            ctx.runOnClient(mc -> {
                for (Module m : BurgerDLC.MODULES) {
                    if (m instanceof Optimizer || m instanceof ESP) m.setEnabled(false);
                }
            });

            // Булава: падаем на зомби с высоты — TriggerBot должен ударить ещё в воздухе.
            srv.runCommand("kill @e[type=minecraft:zombie]");
            srv.runCommand("item replace entity @a weapon.mainhand with minecraft:mace");
            srv.runCommand("execute as @a at @s run tp @s ~ ~ ~ 0 90");
            ctx.runOnClient(mc -> {
                module(TriggerBot.class).setEnabled(false);
                module(AimBot.class).setEnabled(false);
            });
            ctx.waitTicks(40); // булава заряжается ~1.7 с
            srv.runCommand("execute as @a at @s run tp @s ~ ~8 ~ 0 90");
            srv.runCommand("execute at @a run summon minecraft:husk ~ ~-8 ~ {NoAI:1b,PersistenceRequired:1b,Silent:1b}");
            ctx.waitFor(mc -> !mc.player.isOnGround() && zombie(mc) != null);
            ctx.runOnClient(mc -> module(TriggerBot.class).setEnabled(true));
            boolean[] hitInAir = {false};
            for (int i = 0; i < 60 && !hitInAir[0]; i++) {
                ctx.waitTick();
                String st = ctx.computeOnClient(mc -> {
                    ZombieEntity z = zombie(mc);
                    // Удар сбрасывает заряд; если это случилось в воздухе — ранний удар сработал.
                    if (!mc.player.isOnGround() && mc.player.getAttackCooldownProgress(0.5f) < 0.5f) hitInAir[0] = true;
                    return String.format("ground=%s fall=%.2f vy=%.2f cd=%.2f hit=%s hp=%s item=%s",
                            mc.player.isOnGround(), mc.player.fallDistance, mc.player.getVelocity().y,
                            mc.player.getAttackCooldownProgress(0.5f), mc.crosshairTarget == null ? null : mc.crosshairTarget.getType(),
                            z == null ? "-" : z.getHealth(), mc.player.getMainHandStack().getItem());
                });
                if (i % 3 == 0 || hitInAir[0]) System.out.println("[burger-test] mace " + i + ": " + st);
            }
            System.out.println("[burger-test] Булава: удар в воздухе = " + hitInAir[0]);
            if (!hitInAir[0]) throw new AssertionError("Ранний удар булавой не сработал в воздухе");
            ctx.runOnClient(mc -> module(TriggerBot.class).setEnabled(false));
            srv.runCommand("item replace entity @a weapon.mainhand with minecraft:diamond_sword");

            // Kill Effect + HUD-панели: убиваем слабого зомби.
            srv.runCommand("kill @e[type=minecraft:zombie]");
            srv.runCommand("effect give @a minecraft:speed 120 1");
            srv.runCommand("item replace entity @a armor.chest with minecraft:diamond_chestplate");
            srv.runCommand("execute as @a at @s run tp @s ~ ~ ~ 0 0");
            srv.runCommand("execute at @a run summon minecraft:zombie ~ ~ ~2.5 {NoAI:1b,PersistenceRequired:1b,Silent:1b,Health:3f}");
            ctx.waitFor(mc -> zombie(mc) != null);
            ctx.runOnClient(mc -> {
                for (Module m : BurgerDLC.MODULES) {
                    if (m instanceof KillEffect || m instanceof TargetHud || m instanceof KeyBindsHud
                            || m instanceof ArmorHud || m instanceof PotionsHud) m.setEnabled(true);
                }
            });
            ctx.waitTicks(3);
            ctx.runOnClient(mc -> mc.interactionManager.attackEntity(mc.player, zombie(mc)));
            ctx.waitTicks(3);
            ctx.takeScreenshot("burger-kill-hud");
            System.out.println("[burger-test] Kill Effect и HUD: без ошибок");

            // FullBright + Time Changer «Ночь».
            ctx.runOnClient(mc -> {
                TimeChanger.INSTANCE.setEnabled(true);
                TimeChanger.INSTANCE.time.index = 2;
                mc.options.setPerspective(net.minecraft.client.option.Perspective.FIRST_PERSON);
                Crosshair.INSTANCE.setEnabled(true);
            });
            ctx.waitTicks(10);
            ctx.takeScreenshot("burger-night-fullbright");
            ctx.runOnClient(mc -> FullBright.INSTANCE.setEnabled(false));
            ctx.waitTicks(10);
            ctx.takeScreenshot("burger-night-dark");
            ctx.runOnClient(mc -> TimeChanger.INSTANCE.setEnabled(false));

            // Меню: открыть, раскрыть AimBot кликом, сделать скриншоты.
            ctx.setScreen(ClickGui::new);
            ctx.waitTicks(10);
            ctx.takeScreenshot("burger-gui");
            double[] card = ctx.computeOnClient(mc -> {
                int w = mc.getWindow().getScaledWidth(), h = mc.getWindow().getScaledHeight();
                int size = Math.min(360, Math.min(w, h) - 16);
                int px = (w - size) / 2, py = (h - size) / 2;
                double scale = mc.getWindow().getScaleFactor();
                return new double[]{(px + 84 + 8 + 40) * scale, (py + 28 + 8 + 15) * scale};
            });
            ctx.getInput().setCursorPos(card[0], card[1]);
            ctx.getInput().pressMouse(GLFW.GLFW_MOUSE_BUTTON_RIGHT);
            ctx.waitTicks(10);
            ctx.takeScreenshot("burger-gui-aimbot");
            double[] visuals = ctx.computeOnClient(mc -> {
                int w = mc.getWindow().getScaledWidth(), h = mc.getWindow().getScaledHeight();
                int size = Math.min(360, Math.min(w, h) - 16);
                int px = (w - size) / 2, py = (h - size) / 2;
                double scale = mc.getWindow().getScaleFactor();
                return new double[]{(px + 30) * scale, (py + 28 + 22 + 2 * 20 + 8) * scale};
            });
            ctx.getInput().setCursorPos(visuals[0], visuals[1]);
            ctx.getInput().pressMouse(GLFW.GLFW_MOUSE_BUTTON_LEFT);
            ctx.waitTicks(10);
            ctx.takeScreenshot("burger-gui-visuals");
            // Тема: открыть пипетку «Цвет 1».
            ctx.runOnClient(mc -> {
                Theme.INSTANCE.first.open = true;
            });
            ctx.setScreen(() -> null);
            ctx.runOnClient(mc -> {
                ClickGui.current = Category.DISPLAY;
                ClickGui.expanded.add(Theme.INSTANCE);
                mc.setScreen(new ClickGui());
            });
            ctx.waitTicks(10);
            ctx.takeScreenshot("burger-gui-theme");
            ctx.runOnClient(mc -> {
                ClickGui.current = Category.MOVEMENT;
                ClickGui.expanded.add(Optimizer.INSTANCE);
                mc.setScreen(new ClickGui());
            });
            ctx.waitTicks(10);
            ctx.takeScreenshot("burger-gui-optimizer");
            ctx.setScreen(() -> null);
        }
    }

    @SuppressWarnings("unchecked")
    private static <T extends Module> T module(Class<T> type) {
        for (Module m : BurgerDLC.MODULES) {
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
