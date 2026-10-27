// How to drive AircraftPhysics from an engine script (ITsMagic or any other Java engine).
// The engine calls below are written as comments: replace them with your engine's own API
// (the names differ between engines and versions). Everything else stays as is.

public class FlyScript /* extends the engine's script/component class */ {

    AircraftPhysics plane = new AircraftPhysics();   // or AircraftPhysics.mig29()

    // called once when the object appears
    public void start() {
        // 1. Starting point and speed:
        plane.pos = new AircraftPhysics.V3(0, 500, 0);
        plane.vel = new AircraftPhysics.V3(0, 0, 200);   // 200 m/s along +Z
    }

    // called every frame
    public void repeat() {
        double dt = 1.0 / 60;   // take the real frame time from the engine if it has one, capped at 0.05

        // 2. Inputs:
        //    plane.aim = camera forward direction (x, y, z) in world space
        //    plane.throttle = slider value 0..1
        //    plane.superManeuver = state of the "СВЕРХМАНЁВР" button (Su-57)

        // physics runs in small steps so it stays stable at low FPS
        int steps = (int) Math.ceil(dt / 0.01);
        for (int i = 0; i < steps; i++) plane.update(dt / steps);

        // 3. Outputs, copy to the 3D object:
        //    object position  = (plane.pos.x, plane.pos.y, plane.pos.z)
        //    object rotation  = quaternion (plane.rot.x, plane.rot.y, plane.rot.z, plane.rot.w)
        //    HUD: plane.speed * 3.6 km/h, plane.gLoad G, plane.mach, Math.toDegrees(plane.aoa) degrees
        //
        // If the engine uses a different axis convention (for example -Z forward), flip the sign of z
        // when copying position and use the matching quaternion conversion.

        // 4. Crash: if plane.pos.y is below the ground height at (pos.x, pos.z) the plane is destroyed.
    }
}
