// Flight model from Boevoy Front (index.html, updatePlane) ported to plain Java.
// No engine classes are used here, so it compiles in any Java environment, ITsMagic included.
// Each frame call update(dt), then copy pos and rot to the engine object (see FlyScript.java).
//
// Axes as in the game: +Z forward, +Y up, +X left. Units: metres, seconds, kilograms, newtons, radians.

public class AircraftPhysics {

    // ---------- tiny math ----------
    public static class V3 {
        public double x, y, z;
        public V3(double x, double y, double z) { this.x = x; this.y = y; this.z = z; }
        V3 add(V3 o, double k) { return new V3(x + o.x * k, y + o.y * k, z + o.z * k); }
        V3 mul(double k) { return new V3(x * k, y * k, z * k); }
        double dot(V3 o) { return x * o.x + y * o.y + z * o.z; }
        double len() { return Math.sqrt(dot(this)); }
        V3 norm() { double l = len(); return l < 1e-9 ? new V3(0, 0, 1) : mul(1 / l); }
    }

    public static class Quat {
        public double x, y, z, w;
        public Quat(double x, double y, double z, double w) { this.x = x; this.y = y; this.z = z; this.w = w; }
        V3 rotate(V3 v) {
            double ix = w * v.x + y * v.z - z * v.y, iy = w * v.y + z * v.x - x * v.z;
            double iz = w * v.z + x * v.y - y * v.x, iw = -x * v.x - y * v.y - z * v.z;
            return new V3(ix * w + iw * -x + iy * -z - iz * -y, iy * w + iw * -y + iz * -x - ix * -z, iz * w + iw * -z + ix * -y - iy * -x);
        }
        Quat inv() { return new Quat(-x, -y, -z, w); }
        Quat mul(Quat b) {
            return new Quat(x * b.w + w * b.x + y * b.z - z * b.y, y * b.w + w * b.y + z * b.x - x * b.z,
                    z * b.w + w * b.z + x * b.y - y * b.x, w * b.w - x * b.x - y * b.y - z * b.z);
        }
        Quat normalize() { double l = Math.sqrt(x * x + y * y + z * z + w * w); return new Quat(x / l, y / l, z / l, w / l); }
        // small body-axis rotation (rx, ry, rz radians), XYZ order
        static Quat euler(double rx, double ry, double rz) {
            double c1 = Math.cos(rx / 2), c2 = Math.cos(ry / 2), c3 = Math.cos(rz / 2), s1 = Math.sin(rx / 2), s2 = Math.sin(ry / 2), s3 = Math.sin(rz / 2);
            return new Quat(s1 * c2 * c3 + c1 * s2 * s3, c1 * s2 * c3 - s1 * c2 * s3, c1 * c2 * s3 + s1 * s2 * c3, c1 * c2 * c3 - s1 * s2 * s3);
        }
    }

    static double clamp(double v, double a, double b) { return v < a ? a : v > b ? b : v; }
    static double smooth(double a, double b, double x) { double t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); }

    // ---------- aircraft data (Su-57 by default) ----------
    public double mass = 25000, wingArea = 78.8, thrustMil = 176e3, thrustAB = 290e3;
    public double clAlpha = 3.6, stallAoA = 0.42, clMax = 1.5, cd0 = 0.021, kInduced = 0.11, gLimit = 9;
    public double maxPitchRate = 1.4, maxRollRate = 4.2, maxYawRate = 0.35;
    public boolean thrustVectoring = true;   // Su-57: true, MiG-29: false

    public static AircraftPhysics mig29() {
        AircraftPhysics a = new AircraftPhysics();
        a.mass = 16500; a.wingArea = 38; a.thrustMil = 100e3; a.thrustAB = 163e3; a.clAlpha = 3.5; a.stallAoA = 0.4; a.clMax = 1.4;
        a.cd0 = 0.022; a.kInduced = 0.12; a.maxPitchRate = 1.3; a.maxRollRate = 4.6; a.maxYawRate = 0.3; a.thrustVectoring = false;
        return a;
    }

    // ---------- state ----------
    public V3 pos = new V3(0, 500, 0), vel = new V3(0, 0, 200);
    public Quat rot = new Quat(0, 0, 0, 1);
    V3 w = new V3(0, 0, 0);                     // body angular rates
    public double speed, aoa, gLoad, mach;

    // ---------- inputs (set every frame) ----------
    public V3 aim = new V3(0, 0, 1);            // world direction the player looks (camera forward)
    public double throttle = 0.7;               // 0..1, above 0.85 is afterburner
    public boolean superManeuver = false;       // Su-57 thrust-vectoring mode

    static final double G = 9.8;

    static double cl(AircraftPhysics A, double a) {
        double x = Math.abs(a);
        if (x < A.stallAoA) return A.clAlpha * a;
        return Math.signum(a) * Math.max(Math.max(A.clMax * (1 - (x - A.stallAoA) * 1.4), 1.1 * Math.sin(2 * x)), 0);
    }

    public void update(double dt) {
        Quat qi = rot.inv();
        double spd = Math.max(vel.len(), 1);
        V3 vl = qi.rotate(vel);
        double alpha = Math.atan2(-vl.y, vl.z), beta = Math.atan2(vl.x, vl.z);
        double rho = 1.225 * Math.exp(-Math.max(pos.y, 0) / 8500), qd = 0.5 * rho * spd * spd, W = mass * G;
        boolean tvc = thrustVectoring && superManeuver;

        // instructor: roll the target above the canopy for big corrections, keep wings level for small ones, then pull
        V3 dl = qi.rotate(aim).norm();
        double off = Math.acos(clamp(dl.z, -1, 1));
        V3 ul = qi.rotate(new V3(0, 1, 0));
        double bank = Math.atan2(ul.x, ul.y);
        double phi = off > 0.35 ? Math.atan2(dl.x, dl.y) : (dl.y >= 0 ? 1 : -1) * Math.atan2(dl.x, Math.abs(dl.y) + 1e-4);
        double wg = smooth(0.02, 0.12, off), rollErr = phi * wg + bank * (1 - wg);
        double wdz = clamp(-rollErr * 5, -maxRollRate, maxRollRate);
        double pe = Math.atan2(dl.y, dl.z);
        if (off > 0.35 && dl.y < 0) pe = Math.max(pe, -0.1);
        double rollOk = off > 0.35 ? clamp(1.25 - Math.abs(phi) / 1.1, 0, 1) : 1;
        double wdx = -clamp(pe * 2.6 * rollOk, -0.5, maxPitchRate);
        double wdy = clamp(Math.atan2(dl.x, Math.max(dl.z, 0.2)) * 1.4, -maxYawRate, maxYawRate) + beta * 1.5;
        double auth = clamp(qd / 12000, 0.08, 1);
        if (tvc) auth = Math.max(auth, 0.9);
        // fly-by-wire: angle-of-attack / G limiter
        if (wdx < 0) {
            double aLim = tvc ? 1.7 : Math.min(stallAoA * 0.95, (gLimit * W / (qd * wingArea + 1)) / clAlpha);
            double vTurn = qd * wingArea * Math.abs(cl(this, alpha)) / (mass * spd);
            wdx = Math.max(wdx, -Math.max(0, (aLim - alpha) * 4 + vTurn));
        }
        if (wdx > 0 && alpha < -0.18) wdx = Math.min(wdx, Math.max(0, (alpha + 0.25) * 4));

        // rotational inertia
        w.x += (wdx * auth - w.x) * (1 - Math.exp(-dt / 0.22));
        w.y += (wdy * auth - w.y) * (1 - Math.exp(-dt / 0.4));
        w.z += (wdz * Math.max(auth, 0.3) - w.z) * (1 - Math.exp(-dt / 0.12));
        rot = rot.mul(Quat.euler(w.x * dt, w.y * dt, w.z * dt)).normalize();

        // forces: thrust along the nose, lift normal to the airflow, drag, side force, gravity
        V3 f = rot.rotate(new V3(0, 0, 1)), up = rot.rotate(new V3(0, 1, 0)), left = rot.rotate(new V3(1, 0, 0)), vd = vel.mul(1 / spd);
        double c = cl(this, alpha);
        double L = clamp(qd * wingArea * c, -3.5 * W, (gLimit + 1.5) * W);
        V3 ld = up.add(vd, -up.dot(vd)).norm();
        double M = spd / 340, sa = Math.sin(Math.min(Math.abs(alpha), 1.57));
        double cd = cd0 + kInduced * c * c + 1.4 * sa * sa + 0.028 * smooth(0.88, 1.15, M) + 0.012 * Math.max(0, M - 1.2);
        double T = (throttle <= 0.85 ? throttle / 0.85 * thrustMil : thrustMil + (throttle - 0.85) / 0.15 * (thrustAB - thrustMil)) * Math.pow(rho / 1.225, 0.7);
        V3 acc = f.mul(T).add(ld, L).add(vd, -qd * wingArea * cd).add(left, -qd * wingArea * 0.9 * beta).mul(1 / mass);
        acc.y -= G;
        vel = vel.add(acc, dt);
        pos = pos.add(vel, dt);
        speed = vel.len(); aoa = alpha; gLoad = L / W; mach = M;
    }
}
