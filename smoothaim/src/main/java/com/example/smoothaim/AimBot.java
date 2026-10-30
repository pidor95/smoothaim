package com.example.smoothaim;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.ClientPlayerEntity;
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
    final Setting.Num maxSpeed = add(new Setting.Num("Макс. град/сек", 420, 60, 1080, 10));
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
    final TargetFilter filter = new TargetFilter(this);

    Entity target;
    private double velYaw, velPitch, restYaw, restPitch;
    private Vec3d offset = Vec3d.ZERO;
    private long offsetUntil;

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

    @Override
    public void onFrame(MinecraftClient mc, double dt) {
        ClientPlayerEntity p = mc.player;
        if (p == null || mc.world == null || mc.currentScreen != null
                || activation.is("Зажат ЛКМ") && !mc.options.attackKey.isPressed()
                || weaponOnly.value && !TargetFilter.holdingWeapon(p)) {
            reset();
            return;
        }

        Entity t = pickTarget(mc, p);
        if (t != target) offsetUntil = 0;
        target = t;
        if (t == null) {
            velYaw = velPitch = 0;
            return;
        }

        Vec3d eye = p.getEyePos();
        Vec3d aim = aimPoint(p, t, eye);
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
        double sy = step[0], sp = step[1];
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

    /** Точное решение критически задемпфированной пружины за dt — устойчиво при любом FPS. */
    private double spring(double error, boolean yawAxis, double omega, double dt) {
        double x0 = -error, v0 = yawAxis ? velYaw : velPitch;
        double e = Math.exp(-omega * dt);
        double c = v0 + omega * x0;
        double x1 = (x0 + c * dt) * e;
        double v1 = (v0 - omega * c * dt) * e;
        double step = x1 - x0;
        if (Math.signum(step) == Math.signum(error) && Math.abs(step) > Math.abs(error)) {
            step = error;
            v1 = 0;
        }
        if (yawAxis) velYaw = v1;
        else velPitch = v1;
        return step;
    }

    /** Точка наводки или null, если прицел уже на цели и двигать не нужно. */
    private Vec3d aimPoint(ClientPlayerEntity p, Entity t, Vec3d eye) {
        Box box = t.getBoundingBox();
        Vec3d c = box.getCenter();
        long now = System.currentTimeMillis();
        if (now > offsetUntil) {
            // Точка наводки немного «гуляет» внутри хитбокса.
            offset = new Vec3d((Math.random() - 0.5) * box.getLengthX() * 0.6,
                    (Math.random() - 0.5) * box.getLengthY() * 0.4,
                    (Math.random() - 0.5) * box.getLengthZ() * 0.6).multiply(jitter.value);
            offsetUntil = now + 250 + (long) (Math.random() * 300);
        }
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
        return filter.test(p, e)
                && p.distanceTo(e) <= range.value
                && (walls.value || p.canSee(e))
                && angleTo(p, e) <= maxAngle / 2;
    }

    private static double angleTo(ClientPlayerEntity p, Entity e) {
        Vec3d d = e.getBoundingBox().getCenter().subtract(p.getEyePos()).normalize();
        double dot = MathHelper.clamp(d.dotProduct(p.getRotationVec(1f)), -1, 1);
        return Math.toDegrees(Math.acos(dot));
    }
}
