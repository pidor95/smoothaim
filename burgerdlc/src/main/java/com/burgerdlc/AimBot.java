package com.burgerdlc;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.gui.DrawContext;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.entity.player.PlayerEntity;
import net.minecraft.entity.Entity;
import net.minecraft.entity.LivingEntity;
import net.minecraft.util.math.Box;
import net.minecraft.util.math.MathHelper;
import net.minecraft.util.math.Vec3d;
import org.lwjgl.glfw.GLFW;

public class AimBot extends Module {
    final Setting.Mode activation = add(new Setting.Mode("Активация", "Зажат ЛКМ", "Всегда"));
    final Setting.Mode rotation = add(new Setting.Mode("Ротация",
            "SpaceTime", "Плавная", "Человеческая", "Линейная", "Резкая"));
    final Setting.Num speed = add(new Setting.Num("Резкость", 7, 1, 20, 0.5));
    final Setting.Num maxSpeed = add(new Setting.Num("Макс. град/сек", 300, 60, 1080, 10));
    final Setting.Num jitter = add(new Setting.Num("Рандом точки", 0.2, 0, 1, 0.05));
    final Setting.Mode point = add(new Setting.Mode("Точка", "Ближайшая", "Голова", "Тело", "Центр"));
    final Setting.Mode priority = add(new Setting.Mode("Приоритет", "Угол", "Дистанция", "Здоровье"));
    final Setting.Num fov = add(new Setting.Num("FOV", 90, 10, 360, 5));
    final Setting.Num range = add(new Setting.Num("Дистанция", 4.5, 2, 8, 0.1));
    final Setting.Bool vertical = add(new Setting.Bool("Наводить по вертикали", true));
    final Setting.Bool walls = add(new Setting.Bool("Сквозь стены", false));
    final Setting.Bool lock = add(new Setting.Bool("Держать цель", true));
    final Setting.Bool weaponOnly = add(new Setting.Bool("Только с оружием", false));
    final Setting.Bool gcd = add(new Setting.Bool("Под сенсу мыши", true));

    final Setting.Header humanHeader = add(new Setting.Header("Естественность"));
    final Setting.Bool mouseOnly = add(new Setting.Bool("Только пока двигаешь мышью", true));
    final Setting.Num reactionMin = add(new Setting.Num("Реакция от, мс", 90, 0, 400, 10));
    final Setting.Num reactionMax = add(new Setting.Num("Реакция до, мс", 180, 0, 500, 10));
    final Setting.Num verticalPower = add(new Setting.Num("Сила по вертикали, %", 45, 0, 100, 5));
    final Setting.Num lag = add(new Setting.Num("Отставание от цели, сек", 0.08, 0, 0.3, 0.01));
    final Setting.Num speedVariance = add(new Setting.Num("Разброс скорости, %", 25, 0, 60, 5));
    final Setting.Bool debug = add(new Setting.Bool("Отладка (почему не наводит)", false));
    final TargetFilter filter = new TargetFilter(this);

    Entity target;
    private double velYaw, velPitch, restYaw, restPitch;
    private Vec3d offsetFrom = Vec3d.ZERO, offsetTo = Vec3d.ZERO;
    private long offsetStart, offsetUntil;

    // Естественность: реакция, движение мыши игрока, скорость цели.
    private long targetSince, reaction;
    private double expectedYaw = Double.NaN, expectedPitch = Double.NaN;
    private long lastUserMove;
    private double userSpeed;
    private Vec3d lastTargetPos;
    private Vec3d targetVel = Vec3d.ZERO;
    private final double noiseSeed = Math.random() * 1000;
    private double springOmegaMul = 1, springZeta = 0.9;

    public AimBot() {
        super("AimBot", "Наводка на цель, разные ротации", Category.COMBAT, true, GLFW.GLFW_KEY_R);
    }

    @Override
    protected void onDisable() {
        reset();
    }

    private void reset() {
        target = null;
        velYaw = velPitch = 0;
    }

    /** Двигал ли игрок мышь сам: камера ушла не туда, куда мы её поставили в прошлом кадре. */
    private void trackUserMouse(ClientPlayerEntity p, double dt) {
        if (!Double.isNaN(expectedYaw)) {
            double moved = Math.abs(MathHelper.wrapDegrees(p.getYaw() - expectedYaw)) + Math.abs(p.getPitch() - expectedPitch);
            if (moved > 0.01) {
                lastUserMove = System.currentTimeMillis();
                userSpeed = userSpeed * 0.7 + moved / Math.max(dt, 1e-3) * 0.3;
            }
        }
        expectedYaw = p.getYaw();
        expectedPitch = p.getPitch();
    }

    /** Сила наводки 0..1: без движения мыши — ноль, при быстром движении — полная. */
    private double mouseFactor() {
        if (!mouseOnly.value) return 1;
        if (System.currentTimeMillis() - lastUserMove > 150) return 0;
        return MathHelper.clamp(userSpeed / 40.0, 0.35, 1.0);
    }

    /** Плавный шум -1..1 из нескольких синусов: скорость «гуляет», а не дёргается. */
    private double noise(double t) {
        t += noiseSeed;
        return (Math.sin(t * 1.3) + Math.sin(t * 2.9 + 1.7) * 0.6 + Math.sin(t * 5.3 + 4.1) * 0.3) / 1.9;
    }

    @Override
    public void onFrame(MinecraftClient mc, double dt) {
        ClientPlayerEntity p = mc.player;
        if (p != null) trackUserMouse(p, dt);
        if (p == null || mc.world == null || mc.currentScreen != null
                || activation.is("Зажат ЛКМ") && !mc.options.attackKey.isPressed()
                || weaponOnly.value && !TargetFilter.holdingWeapon(p)) {
            reset();
            return;
        }

        Entity t = pickTarget(mc, p);
        if (t != target) {
            offsetUntil = 0;
            lastTargetPos = null;
            targetVel = Vec3d.ZERO;
            targetSince = System.currentTimeMillis();
            double lo = Math.min(reactionMin.value, reactionMax.value), hi = Math.max(reactionMin.value, reactionMax.value);
            reaction = Math.round(lo + Math.random() * (hi - lo));
            // Для SpaceTime: у каждой цели своя «рука» — скорость ±20%, демпфирование 0.72–0.98.
            springOmegaMul = 0.8 + Math.random() * 0.4;
            springZeta = 0.72 + Math.random() * 0.26;
        }
        target = t;
        if (t == null) {
            velYaw = velPitch = 0;
            return;
        }

        // Скорость цели (сглаженная) — чтобы целиться чуть «позади», как человек.
        Vec3d tp = t.getEntityPos();
        if (lastTargetPos != null && dt > 0) {
            targetVel = targetVel.multiply(0.8).add(tp.subtract(lastTargetPos).multiply(0.2 / dt));
        }
        lastTargetPos = tp;

        // Реакция: первые миллисекунды после появления цели ничего не делаем.
        if (System.currentTimeMillis() - targetSince < reaction) return;
        double strength = mouseFactor();
        if (strength <= 0) {
            velYaw = velPitch = 0;
            return;
        }

        Vec3d eye = p.getEyePos();
        Vec3d aim = aimPoint(p, t, eye);
        if (aim != null) aim = aim.subtract(targetVel.multiply(lag.value));
        if (aim == null) {
            // Прицел уже на хитбоксе — гасим скорость и не двигаем камеру.
            velYaw = velPitch = 0;
            return;
        }

        Vec3d d = aim.subtract(eye);
        double yaw = Math.toDegrees(Math.atan2(d.z, d.x)) - 90.0;
        double pitch = -Math.toDegrees(Math.atan2(d.y, Math.hypot(d.x, d.z)));
        double ey = MathHelper.wrapDegrees(yaw - p.getYaw());
        double ep = vertical.value ? pitch - p.getPitch() : 0;

        double[] step = step(ey, ep, dt);
        double variance = 1 + speedVariance.value / 100.0 * noise(System.nanoTime() / 1e9);
        double sy = step[0] * strength * variance;
        double sp = step[1] * strength * variance * verticalPower.value / 100.0;
        double limit = maxSpeed.value * dt, len = Math.hypot(sy, sp);
        if (len > limit) {
            sy *= limit / len;
            sp *= limit / len;
        }

        if (gcd.value) {
            // Поворачиваем только на величины, кратные шагу мыши при текущей чувствительности.
            double f = mc.options.getMouseSensitivity().getValue() * 0.6 + 0.2;
            double g = f * f * f * 8.0 * 0.15;
            sy += restYaw;
            sp += restPitch;
            double qy = Math.round(sy / g) * g, qp = Math.round(sp / g) * g;
            restYaw = sy - qy;
            restPitch = sp - qp;
            sy = qy;
            sp = qp;
        }

        // Как движение мыши: changeLookDirection сам обновит prevYaw и ограничит pitch.
        p.changeLookDirection(sy / 0.15, sp / 0.15);
        expectedYaw = p.getYaw();
        expectedPitch = p.getPitch();
    }

    /** Сколько градусов повернуть за этот кадр при ошибке (ey, ep). */
    private double[] step(double ey, double ep, double dt) {
        double dist = Math.hypot(ey, ep);
        double s = speed.value;
        switch (rotation.get()) {
            case "SpaceTime" -> {
                // Критически задемпфированная пружина: быстрый разгон, точная остановка без перелёта.
                return new double[]{spring(ey, true, s * 2.2, dt), spring(ep, false, s * 2.2, dt)};
            }
            case "Человеческая" -> {
                // Издалека быстро, у цели медленно, с лёгкой дугой как у руки.
                double v = (s * 6 + dist * s * 0.7) * dt;
                double f = dist <= v ? 1 : v / dist;
                double curve = Math.sin(System.nanoTime() / 2.5e8) * 0.12 * Math.min(dist, 20) * f;
                double nx = dist == 0 ? 0 : -ep / dist, ny = dist == 0 ? 0 : ey / dist;
                return new double[]{ey * f + nx * curve, ep * f + ny * curve};
            }
            case "Линейная" -> {
                double v = s * 40 * dt;
                double f = dist <= v ? 1 : v / dist;
                return new double[]{ey * f, ep * f};
            }
            case "Резкая" -> {
                return new double[]{ey, ep};
            }
            default -> {
                double k = 1.0 - Math.exp(-s * dt);
                return new double[]{ey * k, ep * k};
            }
        }
    }

    /**
     * Пружина SpaceTime. Жёсткость и демпфирование немного свои для каждой цели (как у руки:
     * то чуть резче, то мягче), при демпфировании меньше 1 — небольшой перелёт и докоррекция.
     * Считается мелкими подшагами, поэтому устойчива при любом FPS.
     */
    private double spring(double error, boolean yawAxis, double omega, double dt) {
        double w = omega * springOmegaMul;
        double zeta = yawAxis ? springZeta : Math.min(1.0, springZeta + 0.1);
        double x = -error, v = yawAxis ? velYaw : velPitch;
        int steps = Math.max(1, (int) Math.ceil(dt * 240));
        double h = dt / steps;
        for (int i = 0; i < steps; i++) {
            v += (-w * w * x - 2 * zeta * w * v) * h;
            x += v * h;
        }
        double step = x + error;
        // Не больше пятой части ошибки «за» цель за кадр — перелёт мягкий, а не рывок.
        if (Math.signum(step) == Math.signum(error) && Math.abs(step) > Math.abs(error) * 1.2) {
            step = error * 1.2;
            v *= 0.5;
        }
        if (yawAxis) velYaw = v;
        else velPitch = v;
        return step;
    }

    /** Точка наводки или null, если прицел уже на цели и двигать не нужно. */
    private Vec3d aimPoint(ClientPlayerEntity p, Entity t, Vec3d eye) {
        Box box = t.getBoundingBox();
        Vec3d c = box.getCenter();
        long now = System.currentTimeMillis();
        if (now > offsetUntil) {
            // Точка наводки плавно «гуляет» внутри хитбокса: от старой случайной точки к новой.
            offsetFrom = offsetTo;
            offsetTo = new Vec3d((Math.random() - 0.5) * box.getLengthX() * 0.6,
                    (Math.random() - 0.5) * box.getLengthY() * 0.4,
                    (Math.random() - 0.5) * box.getLengthZ() * 0.6).multiply(jitter.value);
            offsetStart = now;
            offsetUntil = now + 300 + (long) (Math.random() * 400);
        }
        double k = MathHelper.clamp((now - offsetStart) / (double) (offsetUntil - offsetStart), 0, 1);
        k = k * k * (3 - 2 * k);
        Vec3d offset = offsetFrom.add(offsetTo.subtract(offsetFrom).multiply(k));
        return switch (point.get()) {
            case "Голова" -> new Vec3d(c.x, t.getEyeY() - 0.1, c.z).add(offset.multiply(1, 0.3, 1));
            case "Тело" -> new Vec3d(c.x, box.minY + box.getLengthY() * 0.6, c.z).add(offset);
            case "Центр" -> c.add(offset);
            default -> {
                Vec3d look = p.getRotationVec(1f);
                Box inner = box.contract(0.1);
                if (inner.raycast(eye, eye.add(look.multiply(range.value + 2))).isPresent()) yield null;
                Vec3d onRay = eye.add(look.multiply(eye.distanceTo(c)));
                yield new Vec3d(
                        MathHelper.clamp(onRay.x, inner.minX, inner.maxX),
                        MathHelper.clamp(onRay.y, inner.minY, inner.maxY),
                        MathHelper.clamp(onRay.z, inner.minZ, inner.maxZ));
            }
        };
    }

    private Entity pickTarget(MinecraftClient mc, ClientPlayerEntity p) {
        if (lock.value && target != null && valid(p, target, Math.min(360, fov.value * 1.5))) return target;
        Entity best = null;
        double bestScore = Double.MAX_VALUE;
        for (Entity e : mc.world.getEntities()) {
            if (!valid(p, e, fov.value)) continue;
            double score = switch (priority.get()) {
                case "Дистанция" -> p.distanceTo(e);
                case "Здоровье" -> e instanceof LivingEntity l ? l.getHealth() + l.getAbsorptionAmount() : 100;
                default -> angleTo(p, e);
            };
            if (score < bestScore) {
                bestScore = score;
                best = e;
            }
        }
        return best;
    }

    private boolean valid(ClientPlayerEntity p, Entity e, double maxAngle) {
        return reject(p, e, maxAngle) == null;
    }

    private String reject(ClientPlayerEntity p, Entity e, double maxAngle) {
        String r = filter.reject(p, e);
        if (r != null) return r;
        if (p.distanceTo(e) > range.value) return String.format("далеко (%.1f > %.1f)", p.distanceTo(e), range.value);
        if (!walls.value && !p.canSee(e)) return "за стеной";
        if (angleTo(p, e) > maxAngle / 2) return String.format("вне FOV (%.0f° > %.0f°)", angleTo(p, e), maxAngle / 2);
        return null;
    }

    @Override
    public void onHud(DrawContext ctx, MinecraftClient mc) {
        if (!debug.value || mc.player == null || mc.world == null) return;
        String text;
        if (activation.is("Зажат ЛКМ") && !mc.options.attackKey.isPressed()) {
            text = "AimBot: ждёт зажатый ЛКМ";
        } else if (weaponOnly.value && !TargetFilter.holdingWeapon(mc.player)) {
            text = "AimBot: нет оружия в руке";
        } else if (target != null) {
            text = "AimBot: цель " + target.getName().getString() + (mouseFactor() <= 0 ? " (двигай мышью)" : "");
        } else {
            PlayerEntity near = null;
            for (PlayerEntity pl : mc.world.getPlayers()) {
                if (pl != mc.player && (near == null || mc.player.distanceTo(pl) < mc.player.distanceTo(near))) near = pl;
            }
            text = near == null ? "AimBot: рядом нет игроков"
                    : "AimBot: " + near.getName().getString() + " — " + reject(mc.player, near, fov.value);
        }
        int w = UI.width(text) + 10, x = (ctx.getScaledWindowWidth() - w) / 2, y = ctx.getScaledWindowHeight() / 2 + 14;
        Render2D.round(ctx, x, y, w, 13, 4, ClickGui.PANEL);
        UI.draw(ctx, text, x + 5, y + 3, ClickGui.TEXT);
    }

    private static double angleTo(ClientPlayerEntity p, Entity e) {
        Vec3d d = e.getBoundingBox().getCenter().subtract(p.getEyePos()).normalize();
        double dot = MathHelper.clamp(d.dotProduct(p.getRotationVec(1f)), -1, 1);
        return Math.toDegrees(Math.acos(dot));
    }
}
