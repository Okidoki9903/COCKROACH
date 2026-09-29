// Surface locomotion: the cockroach sticks to whatever it walks on.
// Floor, walls, cabinet sides, the underside of the table, the ceiling:
// a wall ahead is climbed, an edge walked over is wrapped around, and
// letting go (or walking off with nothing below) is a fall under gravity.
import * as THREE from 'three';

const ray = new THREE.Raycaster();
const tmp = new THREE.Vector3();
const tmp2 = new THREE.Vector3();

export class Walker {
  constructor(solids) {
    this.solids = solids;
    this.pos = new THREE.Vector3();
    this.n = new THREE.Vector3(0, 1, 0);      // surface normal (the roach's up)
    this.f = new THREE.Vector3(0, 0, 1);      // heading, tangent to the surface
    this.vel = new THREE.Vector3();
    this.grounded = true;
    this.travelled = 0;                        // metres moved in the last update
    this.airTime = 0;
  }

  place(p, n, f) {
    this.pos.copy(p);
    this.n.copy(n).normalize();
    this.f.copy(f);
    this._orthonormalise();
    this.grounded = true;
    this.vel.set(0, 0, 0);
  }

  // First solid hit along a ray, with its world-space face normal.
  cast(origin, dir, far) {
    ray.set(origin, dir);
    ray.far = far;
    const hits = ray.intersectObjects(this.solids.children, true);
    for (const h of hits) {
      if (!h.face) continue;
      const normal = h.face.normal.clone().transformDirection(h.object.matrixWorld);
      // Ignore back faces (inside of thin parts).
      if (normal.dot(dir) > 0) continue;
      return { point: h.point, normal, distance: h.distance };
    }
    return null;
  }

  // move: desired direction in world space (tangent or not), length 0..1.
  update(dt, move, speed) {
    const before = tmp2.copy(this.pos);
    if (this.grounded) this._walk(dt, move, speed);
    else this._fall(dt);
    this.travelled = before.distanceTo(this.pos);
  }

  letGo() {
    if (!this.grounded) return;
    this.grounded = false;
    this.airTime = 0;
    // On the floor it is a small hop; elsewhere it just drops off.
    const hop = this.n.y > 0.8 ? 0.55 : 0.05;
    this.vel.copy(this.n).multiplyScalar(hop).addScaledVector(this.f, 0.15);
  }

  _walk(dt, move, speed) {
    const n = this.n;
    const amount = Math.min(1, move.length());
    if (amount > 0.01) {
      const dir = tmp.copy(move).addScaledVector(n, -move.dot(n));
      if (dir.lengthSq() > 1e-8) {
        dir.normalize();
        // Turn the body toward the direction (fast but not instant).
        this.f.lerp(dir, Math.min(1, dt * 12)).normalize();
        this._orthonormalise();
        const step = speed * amount * dt;
        // A wall ahead (concave edge): climb onto it.
        const origin = this.pos.clone().addScaledVector(n, 0.004);
        const hit = this.cast(origin, dir, step + 0.012);
        if (hit && hit.normal.dot(n) < 0.6) {
          const oldN = n.clone();
          this.n.copy(hit.normal);
          this.pos.copy(hit.point);
          this.f.copy(oldN).addScaledVector(this.n, -oldN.dot(this.n));
          this._orthonormalise();
        } else {
          this.pos.addScaledVector(dir, step);
        }
      }
    }
    this._stick();
  }

  _stick() {
    const n = this.n;
    const hit = this.cast(this.pos.clone().addScaledVector(n, 0.008), n.clone().negate(), 0.022);
    if (hit) {
      this.pos.copy(hit.point);
      if (hit.normal.dot(n) < 0.999) {
        this.n.lerp(hit.normal, 0.5).normalize();
        if (hit.normal.dot(this.n) > 0.99) this.n.copy(hit.normal);
        this._orthonormalise();
      }
      return;
    }
    // Walked over a convex edge: wrap around to the face below the edge.
    const back = this.f.clone().negate();
    const edge = this.cast(this.pos.clone().addScaledVector(n, -0.006).addScaledVector(this.f, 0.006), back, 0.03);
    if (edge && edge.normal.dot(n) < 0.6) {
      const oldN = n.clone();
      this.n.copy(edge.normal);
      this.pos.copy(edge.point);
      this.f.copy(oldN).negate().addScaledVector(this.n, oldN.dot(this.n));
      this._orthonormalise();
      return;
    }
    // Nothing: fall.
    this.grounded = false;
    this.airTime = 0;
    this.vel.copy(this.f).multiplyScalar(0.08);
  }

  _fall(dt) {
    this.airTime += dt;
    this.vel.y -= 9.81 * dt;
    // Small bodies fall slowly (air drag): terminal speed about 1.2 m/s.
    const s = this.vel.length();
    if (s > 1.2) this.vel.multiplyScalar(1.2 / s);
    const stepLen = this.vel.length() * dt;
    const dir = this.vel.clone().normalize();
    const hit = stepLen > 0 ? this.cast(this.pos, dir, stepLen + 0.004) : null;
    if (hit) {
      this.grounded = true;
      this.n.copy(hit.normal);
      this.pos.copy(hit.point);
      const along = this.vel.clone().addScaledVector(this.n, -this.vel.dot(this.n));
      if (along.lengthSq() > 1e-6) this.f.copy(along.normalize());
      this._orthonormalise();
      this.vel.set(0, 0, 0);
      return;
    }
    this.pos.addScaledVector(this.vel, dt);
    // While airborne, the body rights itself toward world up.
    this.n.lerp(new THREE.Vector3(0, 1, 0), Math.min(1, dt * 4)).normalize();
    this._orthonormalise();
  }

  _orthonormalise() {
    this.f.addScaledVector(this.n, -this.f.dot(this.n));
    if (this.f.lengthSq() < 1e-8) {
      this.f.set(1, 0, 0).addScaledVector(this.n, -this.n.x);
      if (this.f.lengthSq() < 1e-8) this.f.set(0, 0, 1).addScaledVector(this.n, -this.n.z);
    }
    this.f.normalize();
  }

  // Rotation matrix for the model: X = left, Y = normal, Z = heading.
  basis(out) {
    const left = tmp.crossVectors(this.n, this.f).normalize();
    return out.makeBasis(left, this.n, this.f);
  }
}

// Third-person camera that follows the surface: its "up" is the surface
// normal (walls and ceiling turn the world around), it orbits with the
// mouse or the right stick, and never ends up behind a solid.
export class FollowCamera {
  constructor(camera, walker) {
    this.camera = camera;
    this.walker = walker;
    this.heading = new THREE.Vector3(0, 0, 1);  // tangent, where the camera looks
    this.pitch = 0.6;                           // radians above the surface
    this.distance = 0.11;
    this.minDistance = 0.06;
    this.maxDistance = 0.6;
    this.up = new THREE.Vector3(0, 1, 0);
    this.lastN = new THREE.Vector3(0, 1, 0);
    this.smoothPos = null;
    this.currentDistance = this.distance;
  }

  // yaw > 0 turns right; pitch > 0 looks up (camera goes lower).
  look(yaw, pitch) {
    this.heading.applyAxisAngle(this.walker.n, -yaw);
    this.pitch = THREE.MathUtils.clamp(this.pitch - pitch, -0.15, 1.35);
  }

  zoom(k) {
    this.distance = THREE.MathUtils.clamp(this.distance * k, this.minDistance, this.maxDistance);
  }

  // Forward and right on the surface, for movement input.
  axes() {
    const n = this.walker.n;
    const fwd = this.heading.clone().addScaledVector(n, -this.heading.dot(n)).normalize();
    const right = new THREE.Vector3().crossVectors(fwd, n).normalize();
    return { fwd, right };
  }

  update(dt) {
    const w = this.walker;
    // Parallel-transport the heading when the surface normal changes.
    if (w.n.dot(this.lastN) < 0.99999) {
      const q = new THREE.Quaternion().setFromUnitVectors(this.lastN, w.n);
      this.heading.applyQuaternion(q);
      this.lastN.copy(w.n);
    }
    const { fwd } = this.axes();
    this.heading.copy(fwd);
    this.up.lerp(w.n, Math.min(1, dt * 6)).normalize();
    const pivot = w.pos.clone().addScaledVector(w.n, 0.012);
    const back = fwd.clone().multiplyScalar(-Math.cos(this.pitch)).addScaledVector(w.n, Math.sin(this.pitch)).normalize();
    // Pull in in front of anything between the pivot and the camera.
    const hit = w.cast(pivot, back, this.distance + 0.01);
    const target = hit ? Math.max(0.02, hit.distance - 0.012) : this.distance;
    this.currentDistance = target < this.currentDistance ? target : THREE.MathUtils.lerp(this.currentDistance, target, Math.min(1, dt * 3));
    const want = pivot.clone().addScaledVector(back, this.currentDistance);
    if (!this.smoothPos) this.smoothPos = want.clone();
    this.smoothPos.lerp(want, Math.min(1, dt * 14));
    this.camera.position.copy(this.smoothPos);
    this.camera.up.copy(this.up);
    this.camera.lookAt(pivot.addScaledVector(fwd, 0.02));
  }
}
