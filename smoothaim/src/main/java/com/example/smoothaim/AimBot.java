package com.example.smoothaim;

import net.minecraft.client.MinecraftClient;
import net.minecraft.client.network.ClientPlayerEntity;
import net.minecraft.entity.Entity;
import net.minecraft.util.math.Box;
import net.minecraft.util.math.MathHelper;
import net.minecraft.util.math.Vec3d;

public class AimBot extends Module {
    final Setting.Mode activation = add(new Setting.Mode("Активация", "Зажат ЛКМ", "Всегда"));
    final Setting.Mode point = add(new Setting.Mode("Точка", "Ближайшая", "Центр", "Голова"));
    final Setting.Num speed = add(new Setting.Num("Плавность", 6, 1, 20, 0.5));
    final Setting.Num maxSpeed = add(new Setting.Num("Макс. град/сек", 300, 60, 900, 10));
    final Setting.Num fov = add(new Setting.Num("FOV", 60, 10, 180, 1));
    final Setting.Num range = add(new Setting.Num("Дистанция", 4.2, 2, 6, 0.1));
    final Setting.Bool walls = add(new Setting.Bool("Сквозь стены", false));
    final Setting.Bool lock = add(new Setting.Bool("Держать цель", true));
    final Setting.Bool weaponOnly = add(new Setting.Bool("Только с оружием", false));
    final Setting.Bool gcd = add(new Setting.Bool("Под сенсу мыши", true));
    final TargetFilter filter = new TargetFilter(this);

    private Entity target;
    private double restYaw, restPitch;

    public AimBot() {
        super("AimBot", "Плавно доводит прицел до цели", Category.COMBAT, true);
    }

    @Override
    protected void onDisable() {
        target = null;
    }

    @Override
    public void onFrame(MinecraftClient mc, double dt) {
        ClientPlayerEntity p = mc.player;
        if (p == null || mc.world == null || mc.currentScreen != null) return;
        if (activation.is("Зажат ЛКМ") && !mc.options.attackKey.isPressed()
                || weaponOnly.value && !TargetFilter.holdingWeapon(p)) {
            target = null;
            return;
        }

        target = pickTarget(mc, p);
        if (target == null) return;

        Vec3d eye = p.getEyePos();
        Box box = target.getBoundingBox();
        Vec3d aim;
        if (point.is("Ближайшая")) {
            // Прицел уже на хитбоксе — не дёргаем камеру.
            Vec3d look = p.getRotationVec(1f);
            if (box.raycast(eye, eye.add(look.multiply(range.value + 1))).isPresent()) return;
            aim = closestOnBox(box.contract(0.1), eye, look);
        } else if (point.is("Голова")) {
            aim = new Vec3d(box.getCenter().x, target.getEyeY() - 0.1, box.getCenter().z);
        } else {
            aim = box.getCenter();
        }

        Vec3d d = aim.subtract(eye);
        float yaw = (float) (Math.toDegrees(Math.atan2(d.z, d.x)) - 90.0);
        float pitch = (float) -Math.toDegrees(Math.atan2(d.y, Math.hypot(d.x, d.z)));

        // Экспоненциальное сглаживание: быстро издалека, мягко у цели, не зависит от FPS.
        double k = 1.0 - Math.exp(-speed.value * dt);
        double dy = MathHelper.wrapDegrees(yaw - p.getYaw()) * k;
        double dp = (pitch - p.getPitch()) * k;
        double limit = maxSpeed.value * dt, len = Math.hypot(dy, dp);
        if (len > limit) {
            dy *= limit / len;
            dp *= limit / len;
        }

        if (gcd.value) {
            // Поворачиваем только на величины, кратные шагу мыши при текущей чувствительности.
            double f = mc.options.getMouseSensitivity().getValue() * 0.6 + 0.2;
            double step = f * f * f * 8.0 * 0.15;
            dy += restYaw;
            dp += restPitch;
            double qy = Math.round(dy / step) * step, qp = Math.round(dp / step) * step;
            restYaw = dy - qy;
            restPitch = dp - qp;
            dy = qy;
            dp = qp;
        }

        // Как движение мыши: changeLookDirection сам обновит prevYaw и ограничит pitch.
        p.changeLookDirection(dy / 0.15, dp / 0.15);
    }

    private Entity pickTarget(MinecraftClient mc, ClientPlayerEntity p) {
        if (lock.value && target != null && valid(p, target, fov.value * 1.5)) return target;
        Entity best = null;
        double bestAngle = Double.MAX_VALUE;
        for (Entity e : mc.world.getEntities()) {
            if (!valid(p, e, fov.value)) continue;
            double a = angleTo(p, e);
            if (a < bestAngle) {
                bestAngle = a;
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

    private static Vec3d closestOnBox(Box box, Vec3d eye, Vec3d look) {
        Vec3d onRay = eye.add(look.multiply(eye.distanceTo(box.getCenter())));
        return new Vec3d(
                MathHelper.clamp(onRay.x, box.minX, box.maxX),
                MathHelper.clamp(onRay.y, box.minY, box.maxY),
                MathHelper.clamp(onRay.z, box.minZ, box.maxZ));
    }
}
