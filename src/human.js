// The human: lives in the flat, comes to the kitchen only with a reason
// (fridge, sink, a snack at the table), switches the light on, stays a
// while, leaves. The kitchen is empty most of the time. If they notice the
// cockroach long enough, they strike: announced, avoidable, blocked by
// anything low overhead.
import * as THREE from 'three';
import * as T from './textures.js';

const HEIGHT = 1.74;

export function buildHumanModel() {
  const root = new THREE.Group();
  const pj = T.plaid([3, 3]);
  const trousers = new THREE.MeshStandardMaterial({ ...pj, roughness: 1 });
  const sweater = new THREE.MeshStandardMaterial({ color: 0x8c8a86, roughness: 0.95 });
  const skin = new THREE.MeshStandardMaterial({ color: 0xc58f6c, roughness: 0.7 });
  const slipper = new THREE.MeshStandardMaterial({ color: 0x2b2b30, roughness: 0.9 });
  const sole = new THREE.MeshStandardMaterial({ color: 0x151515, roughness: 0.8 });

  const limb = (r0, r1, len, mat) => {
    const g = new THREE.CapsuleGeometry((r0 + r1) / 2, len, 6, 16);
    g.translate(0, -len / 2, 0);
    const m = new THREE.Mesh(g, mat);
    m.castShadow = true;
    return m;
  };

  const hips = new THREE.Group();
  hips.position.y = 0.92;
  root.add(hips);
  const legs = [];
  for (const side of [-1, 1]) {
    const thigh = new THREE.Group();
    thigh.position.set(side * 0.1, 0, 0);
    thigh.add(limb(0.075, 0.06, 0.4, trousers));
    const knee = new THREE.Group();
    knee.position.y = -0.44;
    knee.add(limb(0.06, 0.05, 0.38, trousers));
    const ankle = new THREE.Group();
    ankle.position.y = -0.43;
    const foot = new THREE.Mesh(new THREE.CapsuleGeometry(0.048, 0.17, 6, 16), slipper);
    foot.rotation.x = Math.PI / 2;
    foot.position.set(0, -0.035, 0.05);
    foot.scale.set(1.05, 1, 0.62);
    foot.castShadow = true;
    const footSole = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.012, 0.27), sole);
    footSole.position.set(0, -0.066, 0.05);
    ankle.add(foot, footSole);
    knee.add(ankle);
    thigh.add(knee);
    hips.add(thigh);
    legs.push({ thigh, knee, ankle, side });
  }
  const torso = new THREE.Mesh(new THREE.CapsuleGeometry(0.17, 0.42, 6, 16), sweater);
  torso.scale.set(1, 1, 0.65);
  torso.position.y = 0.32;
  torso.castShadow = true;
  hips.add(torso);
  const arms = [];
  for (const side of [-1, 1]) {
    const shoulder = new THREE.Group();
    shoulder.position.set(side * 0.22, 0.56, 0);
    shoulder.add(limb(0.05, 0.045, 0.3, sweater));
    const elbow = new THREE.Group();
    elbow.position.y = -0.33;
    elbow.add(limb(0.045, 0.04, 0.26, sweater));
    const hand = new THREE.Mesh(new THREE.SphereGeometry(0.045, 16, 12), skin);
    hand.position.y = -0.3;
    hand.scale.set(0.8, 1.2, 0.5);
    elbow.add(hand);
    shoulder.add(elbow);
    hips.add(shoulder);
    arms.push({ shoulder, elbow, hand, side });
  }
  const head = new THREE.Mesh(new THREE.SphereGeometry(0.105, 24, 16), skin);
  head.scale.set(0.9, 1.1, 1);
  head.position.y = 0.8;
  head.castShadow = true;
  hips.add(head);
  return { root, hips, legs, arms, head };
}

// Waypoints (x, z). The door is in the hallway; paths avoid the table.
const P = {
  hall: new THREE.Vector2(5.2, 2.75),
  door: new THREE.Vector2(4.5, 2.75),
  inside: new THREE.Vector2(3.6, 2.55),
  mid: new THREE.Vector2(3.0, 1.35),
  fridge: new THREE.Vector2(3.5, 1.2),
  sink: new THREE.Vector2(1.8, 1.0),
  table: new THREE.Vector2(2.95, 2.35),
  counter: new THREE.Vector2(2.6, 1.0),
};
const ROUTES = {
  fridge: ['door', 'inside', 'fridge'],
  sink: ['door', 'inside', 'mid', 'sink'],
  table: ['door', 'inside', 'table'],
  counter: ['door', 'inside', 'mid', 'counter'],
};

export class Human {
  constructor(scene, kitchen, walker, hooks) {
    this.k = kitchen;
    this.walker = walker;
    this.hooks = hooks;            // { footstep(pos), strike(pos, hit), noticed() ... }
    this.model = buildHumanModel();
    this.model.root.visible = false;
    scene.add(this.model.root);
    this.pos = P.hall.clone();
    this.yaw = -Math.PI / 2;
    this.state = 'away';
    this.timer = 28 + Math.random() * 10;   // first visit after ~30 s
    this.path = [];
    this.task = null;
    this.walkPhase = 0;
    this.stride = 0;
    this.suspicion = 0;            // 0..1, what the player sees on the HUD
    this.seeing = false;
    this.strike = null;            // { target, t, dur, hand }
    this.cooldown = 0;
    this.moving = false;
    this.eyes = new THREE.Vector3();
    this.ray = new THREE.Raycaster();
    // Strike announce on the surface: the shadow of the foot or hand
    // darkening, and a thin red circle marking the 4.5 cm danger zone.
    const ring = new THREE.Group();
    const c = document.createElement('canvas');
    c.width = c.height = 128;
    const x = c.getContext('2d');
    const grad = x.createRadialGradient(64, 64, 0, 64, 64, 64);
    grad.addColorStop(0, 'rgba(0,0,0,1)'); grad.addColorStop(0.6, 'rgba(0,0,0,0.8)'); grad.addColorStop(1, 'rgba(0,0,0,0)');
    x.fillStyle = grad; x.fillRect(0, 0, 128, 128);
    this.shadowMat = new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(c), transparent: true, opacity: 0, depthWrite: false });
    const shadow = new THREE.Mesh(new THREE.PlaneGeometry(0.16, 0.16), this.shadowMat);
    const circle = new THREE.Mesh(new THREE.RingGeometry(0.0435, 0.045, 64), new THREE.MeshBasicMaterial({ color: 0xff3a24, transparent: true, opacity: 0.55, depthWrite: false }));
    ring.add(shadow, circle);
    ring.visible = false;
    scene.add(ring);
    this.ring = ring;
  }

  get present() { return this.state !== 'away'; }

  update(dt, exposure, roachMoving, roachHidden) {
    this.cooldown = Math.max(0, this.cooldown - dt);
    switch (this.state) {
      case 'away':
        this.timer -= dt;
        if (this.timer <= 0) this._startVisit();
        break;
      case 'walk':
        this._walkPath(dt);
        break;
      case 'task':
        this.timer -= dt;
        this._doTask(dt);
        if (this.timer <= 0) this._leave();
        break;
      case 'strike':
        this._updateStrike(dt);
        break;
    }
    this._perceive(dt, exposure, roachMoving, roachHidden);
    this._animate(dt);
  }

  _startVisit() {
    const tasks = ['fridge', 'fridge', 'sink', 'table', 'counter'];
    this.task = tasks[Math.floor(Math.random() * tasks.length)];
    this.path = ROUTES[this.task].map((k) => P[k].clone());
    this.pos.copy(P.hall);
    this.state = 'walk';
    this.leaving = false;
    this.dropped = false;
    this.model.root.visible = true;
    this.lightOn = false;
  }

  _leave() {
    this.k.setFridgeOpen(0);
    this.path = ROUTES[this.task].slice(0, -1).reverse().map((k) => P[k].clone());
    this.path.push(P.hall.clone());
    this.state = 'walk';
    this.leaving = true;
  }

  _walkPath(dt) {
    const target = this.path[0];
    if (!target) {
      if (this.leaving) {
        this.state = 'away';
        this.model.root.visible = false;
        this.timer = 35 + Math.random() * 70;     // often empty for a minute or more
        this.k.setCeiling(false);
      } else {
        this.state = 'task';
        this.timer = { fridge: 6, sink: 7, table: 12, counter: 8 }[this.task] + Math.random() * 5;
        this.taskTime = 0;
        this.hooks.task?.(this.task, true);
      }
      return;
    }
    const to = new THREE.Vector2().subVectors(target, this.pos);
    const d = to.length();
    const speed = 1.05;
    // Switch the light on when passing the door, off when leaving.
    if (!this.leaving && !this.lightOn && this.pos.x < 4.25) {
      this.lightOn = true;
      this.k.setCeiling(true);
      this.hooks.light?.(true);
    }
    if (this.leaving && this.lightOn && this.pos.x > 4.15) {
      this.lightOn = false;
      this.k.setCeiling(false);
      this.hooks.light?.(false);
    }
    if (d < 0.05) {
      this.path.shift();
      return;
    }
    const step = Math.min(d, speed * dt);
    this.pos.addScaledVector(to.normalize(), step);
    this._turnTo(Math.atan2(to.x, to.y), dt * 6);
    this.moving = true;
    this._footsteps(step);
  }

  _doTask(dt) {
    this.moving = false;
    this.taskTime += dt;
    const face = { fridge: Math.PI, sink: Math.PI, table: -Math.PI / 2, counter: Math.PI }[this.task];
    this._turnTo(face, dt * 4);
    if (this.task === 'fridge') {
      const t = this.taskTime;
      const open = t < 0.8 ? t / 0.8 : this.timer < 0.8 ? Math.max(0, this.timer / 0.8) : 1;
      this.k.setFridgeOpen(open);
    }
  }

  _turnTo(yaw, k) {
    let d = yaw - this.yaw;
    d = Math.atan2(Math.sin(d), Math.cos(d));
    this.yaw += d * Math.min(1, k);
  }

  _footsteps(step) {
    this.stride += step;
    if (this.stride > 0.62) {
      this.stride = 0;
      const side = (this.stepSide = -(this.stepSide || 1));
      const p = new THREE.Vector3(this.pos.x + Math.cos(this.yaw) * 0.1 * side, 0, this.pos.y - Math.sin(this.yaw) * 0.1 * side);
      this.hooks.footstep?.(p);
    }
  }

  // --- perception ----------------------------------------------------------------

  _perceive(dt, exposure, roachMoving, roachHidden) {
    this.seeing = false;
    if (this.state === 'away' || this.state === 'strike' || roachHidden) {
      this.suspicion = Math.max(0, this.suspicion - dt * (this.state === 'away' ? 0.3 : 0.08));
      return;
    }
    const w = this.walker;
    this.eyes.set(this.pos.x + Math.sin(this.yaw) * 0.08, 1.62, this.pos.y + Math.cos(this.yaw) * 0.08);
    const to = new THREE.Vector3().subVectors(w.pos, this.eyes);
    const dist = to.length();
    const flat = new THREE.Vector2(to.x, to.z).normalize();
    const facing = new THREE.Vector2(Math.sin(this.yaw), Math.cos(this.yaw));
    const inCone = flat.dot(facing) > Math.cos(THREE.MathUtils.degToRad(60));
    if (dist < 4.5 && inCone) {
      this.ray.set(this.eyes, to.clone().divideScalar(dist));
      this.ray.far = dist - 0.01;
      const blocked = this.ray.intersectObjects(this.k.solids.children, true).length > 0;
      if (!blocked) {
        // A 3 cm insect: noticed mostly when lit, moving, and close.
        const vis = (0.08 + exposure * 0.9) * (roachMoving ? 1 : 0.35) * THREE.MathUtils.clamp(2.2 / dist, 0.3, 1.6);
        this.seeing = vis > 0.05;
        this.suspicion = Math.min(1, this.suspicion + vis * dt * 0.55);
      }
    }
    if (!this.seeing) this.suspicion = Math.max(0, this.suspicion - dt * 0.05);
    if (this.suspicion >= 1 && this.cooldown <= 0) this._beginStrike();
  }

  // --- strike --------------------------------------------------------------------------

  _beginStrike() {
    const w = this.walker;
    const target = w.pos.clone();
    const high = target.y > 0.2;
    if (target.y > 1.95) { this.cooldown = 2; return; }       // out of reach
    this.prevState = this.state;
    this.state = 'strike';
    this.strike = { target, t: 0, dur: 0.75, hand: high, normal: w.n.clone() };
    this.ring.visible = true;
    this.ring.position.copy(target).addScaledVector(w.n, 0.002);
    this.ring.quaternion.setFromUnitVectors(new THREE.Vector3(0, 0, 1), w.n);
    this.hooks.announce?.(this.strike);
  }

  _updateStrike(dt) {
    const s = this.strike;
    s.t += dt;
    // Step toward the target during the windup (reach 0.55 m).
    const flat = new THREE.Vector2(s.target.x, s.target.z);
    const to = new THREE.Vector2().subVectors(flat, this.pos);
    const want = s.hand ? 0.45 : 0.18;
    if (to.length() > want) {
      const step = Math.min(to.length() - want, 1.6 * dt);
      this.pos.addScaledVector(to.clone().normalize(), step);
      this.moving = true;
    }
    this._turnTo(Math.atan2(to.x, to.y), dt * 10);
    const k = Math.min(1, s.t / s.dur);
    this.shadowMat.opacity = 0.15 + k * 0.6;
    this.ring.children[0].scale.setScalar(1.6 - k * 0.6);
    if (s.t >= s.dur && !s.done) {
      s.done = true;
      const hit = this._resolve(s);
      this.hooks.strike?.(s.target, hit, s.hand);
      this.ring.visible = false;
      this.suspicion = hit ? 0 : 0.6;
      this.cooldown = 1.5;
    }
    if (s.t >= s.dur + 0.6) {
      this.state = this.prevState === 'task' ? 'task' : 'walk';
      this.strike = null;
    }
  }

  // The blow lands where the target was: the cockroach must have left a
  // 4.5 cm radius, or be under something low (a foot or a hand cannot fit).
  _resolve(s) {
    const w = this.walker;
    if (!w.grounded && w.pos.distanceTo(s.target) > 0.02) return false;
    if (w.pos.distanceTo(s.target) > 0.045) return false;
    this.ray.set(w.pos.clone().addScaledVector(w.n, 0.004), w.n);
    this.ray.far = 0.25;
    const covered = this.ray.intersectObjects(this.k.solids.children, true).length > 0;
    return !covered;
  }

  // --- animation ---------------------------------------------------------------------

  _animate(dt) {
    const m = this.model;
    m.root.position.set(this.pos.x, 0, this.pos.y);
    m.root.rotation.y = this.yaw;
    if (this.moving) this.walkPhase += dt * 7.5;
    const a = this.moving ? Math.sin(this.walkPhase) : 0;
    m.legs.forEach((L, i) => {
      const s = i === 0 ? a : -a;
      L.thigh.rotation.x = s * 0.45;
      L.knee.rotation.x = Math.max(0, -Math.cos(this.walkPhase + (i ? Math.PI : 0))) * (this.moving ? 0.7 : 0);
      L.ankle.rotation.x = -L.thigh.rotation.x * 0.4;
    });
    m.arms.forEach((A, i) => {
      A.shoulder.rotation.x = (i === 0 ? -a : a) * 0.35;
      A.elbow.rotation.x = -0.2;
    });
    m.hips.position.y = 0.92 + (this.moving ? Math.abs(Math.cos(this.walkPhase)) * 0.02 : 0);
    // Strike: stomp (lift the foot then slam) or slap with the right hand.
    if (this.state === 'strike' && this.strike) {
      const s = this.strike;
      const k = Math.min(1, s.t / s.dur);
      if (!s.hand) {
        const L = m.legs[1];
        const up = k < 0.8 ? k / 0.8 : Math.max(0, 1 - (k - 0.8) / 0.2);
        L.thigh.rotation.x = -up * 0.9;
        L.knee.rotation.x = up * 1.1;
      } else {
        const A = m.arms[1];
        const up = k < 0.8 ? k / 0.8 : Math.max(0, 1 - (k - 0.8) / 0.2);
        A.shoulder.rotation.x = -1.2 - up * 0.9;
        m.hips.rotation.x = 0.35;
      }
    } else {
      m.hips.rotation.x = 0;
    }
    this.moving = false;
  }
}

export { HEIGHT };
