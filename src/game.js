// Gameplay: needs, food and water, the refuge and its reserve, the human's
// visits, instinct senses, exposure to light, objectives, death, pause,
// recording.
import * as THREE from 'three';
import { Human } from './human.js';
import { Hud } from './hud.js';
import { Audio } from './audio.js';
import { Recorder } from './recorder.js';

const WALK = 0.13, SPRINT = 0.36, CARRY = 0.1;
const OBJECTIVES = [
  { text: "Sortir du refuge et trouver de l'eau", done: (g) => g.stats.drinks > 0 },
  { text: 'Trouver de la nourriture et manger', done: (g) => g.stats.meals > 0 },
  { text: 'Rapporter une miette au refuge', done: (g) => g.stats.deposits > 0 },
  { text: 'Grimper sur le plan de travail', done: (g) => g.walker.pos.y > 0.9 && g.walker.pos.z < 0.65 && g.walker.n.y > 0.8 },
  { text: "Survivre à une visite de l'humain", done: (g) => g.stats.visitsSurvived > 0 },
  { text: 'Constituer une réserve de 3 miettes', done: (g) => g.stock >= 3 },
  { text: 'Explorer : passer sous le frigo (il y fait chaud)', done: (g) => g.senses.chaleur && g.walker.pos.z < 0.6 && g.walker.pos.x > 3.15 },
  { text: 'Tenir la réserve à 5 miettes', done: (g) => g.stock >= 5 },
];

export class Game {
  constructor(ctx) {
    Object.assign(this, ctx);
    this.sprinting = false;
    this.fps = 0;
    this.playing = false;
    this.paused = false;
    this.hud = new Hud(document.getElementById('hud'));
    this.audio = new Audio();
    this.recorder = new Recorder(ctx.canvas, this.audio);
    this.shake = 0;
    this.settings = { sensitivity: 1, invertY: false, quality: 'high', volume: 0.8 };
    try { Object.assign(this.settings, JSON.parse(localStorage.getItem('cockroach.settings') || '{}')); } catch { /* private mode */ }
    this.best = Number(localStorage.getItem('cockroach.best') || 0);
  }

  start() {
    this.reset();
    document.getElementById('play').onclick = () => this.begin(true);
    document.addEventListener('pointerlockchange', () => {
      if (document.pointerLockElement !== this.canvas && this.playing && !this.dead) this.pause(true);
    });
    this.canvas.addEventListener('click', () => {
      if (this.playing && !this.paused && !this.dead && document.pointerLockElement !== this.canvas) this.canvas.requestPointerLock();
    });
  }

  reset() {
    const k = this.kitchen;
    this.food = 0.7;
    this.water = 0.45;
    this.health = 1;
    this.stock = 0;
    this.carrying = null;
    this.inRefuge = true;
    this.dead = false;
    this.time = 0;
    this.objective = 0;
    this.stats = { drinks: 0, meals: 0, deposits: 0, visitsSurvived: 0, dodges: 0 };
    this.senses = {};
    this.vibration = 0;
    this.senseTime = 0;
    this.senseCooldown = 0;
    this.known = new Set();
    for (const it of k.items) {
      if (!it.baseMat) it.baseMat = it.mesh.material;
      it.mesh.material = it.baseMat;
      if (it.home) { it.position.copy(it.home); it.mesh.position.copy(it.home); } else it.home = it.position.clone();
      if (it.mesh.parent !== k.decor) k.decor.add(it.mesh);
      it.mesh.scale.setScalar(1);
      it.mesh.visible = true;
      it.gone = false;
      it.uses = it.kind === 'water' ? 3 : 1;
    }
    this.walker.place(k.refuge.clone().setX(0.02), new THREE.Vector3(0, 1, 0), new THREE.Vector3(1, 0, -0.2).normalize());
    this.follow.heading.copy(this.walker.f);
    this.follow.smoothPos = null;
    if (this.human) { this.scene.remove(this.human.model.root); this.scene.remove(this.human.ring); }
    this.human = new Human(this.scene, k, this.walker, {
      footstep: (p) => this._footstep(p),
      light: (on) => { this.audio.switchClick(new THREE.Vector3(4.15, 1.2, 2.2)); if (on && !this.inRefuge) this.hud.toast('La lumière s\'allume…'); },
      task: (task) => { if (task === 'fridge') this.audio.fridge(true, new THREE.Vector3(3.5, 1, 0.7)); },
      announce: (s) => this.audio.announce(s.target),
      strike: (pos, hit, hand) => this._strike(pos, hit, hand),
    });
    this.wasPresent = false;
    this.hud.objective(OBJECTIVES[0].text);
    this.refugeVeil(true);
    k.setCeiling(false);
    k.setFridgeOpen(0);
    this._carryMesh?.removeFromParent();
    this._carryMesh = null;
  }

  begin(lock) {
    document.getElementById('title').hidden = true;
    document.getElementById('hud').hidden = false;
    this.playing = true;
    this.audio.start();
    this.audio.setVolume(this.settings.volume);
    if (lock) this.canvas.requestPointerLock();
    this.hud.toast('Tu es dans ton refuge. [E] pour sortir.', 4000);
  }

  // --- frame --------------------------------------------------------------------------

  update(dt) {
    const inp = this.input.poll(dt);
    if (this.input.was('pause') && this.playing && !this.dead) this.pause(!this.paused);
    if (this.input.was('record') && this.playing) {
      const on = this.recorder.toggle();
      this.hud.toast(on ? 'Enregistrement vidéo…' : (this.recorder.active ? '' : 'Vidéo enregistrée (téléchargement)'));
    }
    if (this.input.was('photo') && this.playing) this.wantPhoto = true;
    const { look, zoom } = this.input.consume();
    if (!this.playing || this.paused || this.dead) {
      this._hud();
      return;
    }
    this.time += dt;
    const s = this.settings.sensitivity;
    this.follow.look(look.x * s, look.y * s * (this.settings.invertY ? -1 : 1));
    if (zoom !== 1) this.follow.zoom(zoom);

    if (this.inRefuge) this._refuge(inp);
    else this._move(dt, inp);
    this._needs(dt);
    const exposure = this.inRefuge ? 0 : this._exposure();
    this.exposure = exposure;
    this.human.update(dt, exposure, this.walker.travelled > 0.0005, this.inRefuge);
    this._visits();
    this._senses(dt);
    this._items();
    this._objectives();
    this.shake = Math.max(0, this.shake - dt * 3);
    if (this.shake > 0) this.camera.position.x += (Math.random() - 0.5) * this.shake * 0.01;
    this.audio.setListener(this.camera.position, this.camera.getWorldDirection(new THREE.Vector3()), this.camera.up);
    this.audio.scuttle(this.walker.travelled * 900);
    this._hud();
  }

  // Called by main right after rendering (the WebGL image is valid).
  afterRender() {
    this.recorder.capture(OBJECTIVES[this.objective % OBJECTIVES.length].text);
    if (this.wantPhoto) {
      this.wantPhoto = false;
      Recorder.photo(this.canvas);
      this.hud.toast('Photo enregistrée');
    }
  }

  _move(dt, inp) {
    const { fwd, right } = this.follow.axes();
    const move = fwd.multiplyScalar(inp.move.y).addScaledVector(right, inp.move.x);
    this.sprinting = inp.sprint && !this.carrying && this.food > 0.05;
    const speed = this.carrying ? CARRY : this.sprinting ? SPRINT : WALK;
    if (this.input.was('letgo')) this.walker.letGo();
    this.walker.update(dt, move, speed);
    // Out of the world (fell through a gap): back to the refuge.
    const p = this.walker.pos;
    if (p.y < -0.3 || p.x < -0.5 || p.x > 6.5 || p.z < -0.5 || p.z > 4.2) this._enterRefuge(true);
    if (this.input.was('interact')) this._interact();
    if (this.input.was('grab')) this._grab();
    if (this.input.was('sense')) this._sense();
    // Near the crack: enter.
    this.nearRefuge = this.walker.pos.distanceTo(this.kitchen.refuge) < 0.07;
  }

  _needs(dt) {
    const moving = this.walker.travelled > 0.0005;
    const rate = this.inRefuge ? 0.35 : this.sprinting ? 3 : moving ? 1.6 : 1;
    this.food = Math.max(0, this.food - dt / 260 * rate);
    this.water = Math.max(0, this.water - dt / 210 * (this.inRefuge ? 0.5 : 1));
    if (this.food <= 0 || this.water <= 0) {
      this.health -= dt / 25;
      if (this.health <= 0) this._die('Épuisé', this.food <= 0 ? 'Tu es mort de faim.' : 'Tu es mort de soif.');
    } else this.health = Math.min(1, this.health + dt / 30);
    // Regrowing things: the leak refills its drops, crumbs appear after meals.
    for (const it of this.kitchen.items) {
      if (it.kind === 'water' && it.uses < 3) {
        it.refill = (it.refill || 0) + dt;
        if (it.refill > 35) { it.uses++; it.refill = 0; it.mesh.visible = true; it.gone = false; }
      }
    }
  }

  // Light reaching the cockroach (0..1), a gameplay estimate: each light
  // counts only if nothing blocks the line from the body to it.
  _exposure() {
    const w = this.walker, k = this.kitchen;
    const from = w.pos.clone().addScaledVector(w.n, 0.006);
    let L = 0;
    const add = (pos, intensity, maxDist) => {
      const to = pos.clone().sub(from);
      const d = to.length();
      if (d > maxDist || intensity <= 0) return;
      if (w.cast(from, to.divideScalar(d), d - 0.05)) return;
      L += intensity / Math.max(0.05, d * d);
    };
    add(k.ceilingLight.position, k.ceilingLight.intensity, 8);
    add(k.fridgeLight.position, k.fridgeLight.intensity, 3);
    add(new THREE.Vector3(0.05, 0.3, 0.8), 3.5, 2.2);
    // Hallway spot: only inside its cone.
    const hall = k.lights.hall;
    const dir = hall.target.position.clone().sub(hall.position).normalize();
    const toRoach = from.clone().sub(hall.position).normalize();
    if (toRoach.dot(dir) > Math.cos(hall.angle)) add(hall.position, hall.intensity * 0.5, 8);
    // Moonlight through the window.
    const moonDir = k.lights.moon.position.clone().sub(k.lights.moon.target.position).normalize();
    if (!w.cast(from, moonDir, 6)) L += 0.6;
    return THREE.MathUtils.clamp(L / (L + 2.5), 0, 1);
  }

  // --- interactions --------------------------------------------------------------------

  _nearest(maxD) {
    let best = null, bd = maxD;
    for (const it of this.kitchen.items) {
      if (it.gone) continue;
      const d = it.position.distanceTo(this.walker.pos);
      if (d < bd) { bd = d; best = it; }
    }
    return best;
  }

  _interact() {
    if (this.nearRefuge) { this._enterRefuge(); return; }
    const it = this._nearest(0.04);
    if (!it) return;
    if (it.kind === 'water') {
      this.water = Math.min(1, this.water + 0.45);
      this.stats.drinks++;
      it.uses--;
      if (it.uses <= 0) { it.gone = true; it.mesh.visible = false; it.refill = 0; }
      this.audio.blip(true);
      this.hud.toast('Tu as bu.');
    } else {
      this.food = Math.min(1, this.food + 0.35);
      this.stats.meals++;
      this._consume(it);
      this.audio.blip(false);
      this.hud.toast('Miam.');
    }
  }

  _grab() {
    if (this.carrying) {
      // Put it down here.
      const it = this.carrying;
      it.position.copy(this.walker.pos).addScaledVector(this.walker.f, 0.02);
      this.kitchen.decor.add(it.mesh);
      it.mesh.position.copy(it.position);
      it.mesh.scale.setScalar(1);
      it.gone = false;
      this.carrying = null;
      return;
    }
    const it = this._nearest(0.04);
    if (!it || it.kind !== 'food') return;
    it.gone = true;
    this.carrying = it;
    // Held in the mandibles, in front of the head.
    it.mesh.removeFromParent();
    this.roach.root.add(it.mesh);
    it.mesh.position.set(0, 0.004, 0.022);
    it.mesh.scale.setScalar(0.8);
    this.audio.blip(false);
  }

  _consume(it) {
    it.gone = true;
    it.mesh.visible = false;
    this.known.delete(it);
  }

  _enterRefuge(forced) {
    this.inRefuge = true;
    this.refugeVeil(true);
    this.walker.place(this.kitchen.refuge.clone().setX(0.02), new THREE.Vector3(0, 1, 0), new THREE.Vector3(1, 0, 0));
    if (this.carrying) {
      this.stock++;
      this.stats.deposits++;
      const it = this.carrying;
      it.mesh.removeFromParent();
      it.mesh.visible = false;
      this.carrying = null;
      this.audio.blip(true);
      this.hud.toast('Miette ajoutée à la réserve');
    } else if (!forced) this.hud.toast('Au refuge. Personne ne peut te voir ici.');
  }

  _refuge(inp) {
    this.nearRefuge = false;
    if (this.input.was('interact')) {
      if (this.stock > 0 && this.food < 0.75) {
        this.stock--;
        this.food = Math.min(1, this.food + 0.35);
        this.stats.meals++;
        this.audio.blip(false);
        this.hud.toast('Tu manges une miette de ta réserve');
      } else this._leaveRefuge();
    }
    if (this.input.was('letgo') || Math.abs(inp.move.y) + Math.abs(inp.move.x) > 0.5) this._leaveRefuge();
  }

  _leaveRefuge() {
    this.inRefuge = false;
    this.refugeVeil(false);
    this.walker.place(new THREE.Vector3(0.04, 0, 3.0175), new THREE.Vector3(0, 1, 0), new THREE.Vector3(1, 0, 0));
  }

  refugeVeil(on) {
    let v = document.querySelector('.refuge-veil');
    if (!v) { v = document.createElement('div'); v.className = 'refuge-veil'; document.body.appendChild(v); }
    v.hidden = !on;
  }

  // Instinct, active sense (F / X): food and water within 2.5 m glow for a
  // few seconds and are marked on the map. Cooldown 12 s.
  _sense() {
    if (this.senseCooldown > 0) return;
    this.senseTime = 6;
    this.senseCooldown = 12;
    for (const it of this.kitchen.items) {
      if (!it.gone && it.position.distanceTo(this.walker.pos) < 2.5) this.known.add(it);
    }
  }

  _senses(dt) {
    const w = this.walker, h = this.human;
    this.vibration = Math.max(0, this.vibration - dt);
    this.senseTime = Math.max(0, this.senseTime - dt);
    this.senseCooldown = Math.max(0, this.senseCooldown - dt);
    const near = (kind, r) => this.kitchen.items.some((it) => !it.gone && it.kind === kind && it.position.distanceTo(w.pos) < r);
    const hp = new THREE.Vector3(h.pos.x, 0, h.pos.y);
    const hd = h.present ? hp.distanceTo(new THREE.Vector3(w.pos.x, 0, w.pos.z)) : 99;
    this.senses = {
      vibrations: this.vibration > 0,
      humidite: near('water', 0.6),
      odeur: near('food', 0.9),
      mouvement: h.present && hd < 4,
      chaleur: w.pos.distanceTo(this.kitchen.heat) < 0.7 || (w.pos.x > 3.1 && w.pos.z < 0.7 && w.pos.y < 0.05),
      humain: hd < 1.5,
    };
    // Discover what is close.
    for (const it of this.kitchen.items) if (!it.gone && it.position.distanceTo(w.pos) < 0.8) this.known.add(it);
    for (const it of this.kitchen.items) {
      if (it.gone) continue;
      const glow = this.senseTime > 0 && this.known.has(it);
      it.mesh.material = glow ? (it.kind === 'water' ? GLOW_WATER : GLOW_FOOD) : it.baseMat;
    }
  }

  _items() {
    if (this.inRefuge) { this.prompt = { pos: this.kitchen.refuge, text: this.stock > 0 && this.food < 0.75 ? 'Manger une miette de la réserve' : 'Sortir' }; return; }
    if (this.nearRefuge) { this.prompt = { pos: this.kitchen.refuge, text: this.carrying ? 'Déposer au refuge' : 'Entrer au refuge' }; return; }
    const it = this._nearest(0.04);
    if (!it) { this.prompt = null; return; }
    this.prompt = { pos: it.position, text: it.kind === 'water' ? 'Boire' : this.carrying ? 'Manger' : 'Manger  ·  [G] Ramasser' };
  }

  _footstep(p) {
    const d = p.distanceTo(new THREE.Vector3(this.walker.pos.x, 0, this.walker.pos.z));
    if (d < 2.5) this.vibration = 0.7;
    this.audio.footstep(p.clone().setY(0.02), Math.max(0, 1 - d / 2.5));
    if (d < 1.2) this.shake = Math.max(this.shake, (1.2 - d) * 0.4);
  }

  _strike(pos, hit, hand) {
    this.audio.impact(pos, hand);
    this.shake = 1;
    if (hit) this._die('Écrasé', hand ? "La main de l'humain t'a eu." : "Le pied de l'humain t'a eu.");
    else {
      this.stats.dodges++;
      this.hud.toast('Esquivé !');
    }
  }

  _visits() {
    const present = this.human.present;
    if (this.wasPresent && !present && !this.dead) {
      this.stats.visitsSurvived++;
      if (!this.inRefuge) this.hud.toast("L'humain est reparti.");
    }
    if (!this.wasPresent && present && !this.inRefuge) this.hud.toast("Des pas dans le couloir…");
    this.wasPresent = present;
    // After a snack, crumbs fall where the human ate.
    if (this.human.state === 'walk' && this.human.leaving && !this.human.dropped && (this.human.task === 'table' || this.human.task === 'counter')) {
      this.human.dropped = true;
      const spot = this.human.task === 'table' ? [2.72, 0.0, 2.35, 0.18] : [2.55, 0.92, 0.4, 0.12];
      for (let i = 0; i < 2; i++) this._spawnCrumb(spot[0] + (Math.random() - 0.5) * spot[3], spot[1], spot[2] + (Math.random() - 0.5) * spot[3]);
    }
  }

  _spawnCrumb(x, y, z) {
    const free = this.kitchen.items.find((it) => it.kind === 'food' && it.gone && it !== this.carrying);
    if (!free) return;
    free.position.set(x, y + 0.003, z);
    this.kitchen.decor.add(free.mesh);
    free.mesh.position.copy(free.position);
    free.mesh.scale.setScalar(1);
    free.mesh.visible = true;
    free.gone = false;
  }

  _objectives() {
    const o = OBJECTIVES[this.objective % OBJECTIVES.length];
    if (o.done(this)) {
      this.hud.toast('✔ ' + o.text, 3000);
      this.objective++;
      this.hud.objective(OBJECTIVES[this.objective % OBJECTIVES.length].text);
    }
  }

  _die(title, why) {
    if (this.dead) return;
    this.dead = true;
    this.recorderNote = null;
    const survived = Math.floor(this.time);
    if (survived > this.best) { this.best = survived; try { localStorage.setItem('cockroach.best', survived); } catch { /* ignore */ } }
    document.exitPointerLock?.();
    const d = document.createElement('div');
    d.className = 'overlay death';
    d.innerHTML = `<div class="menu"><h2>${title.toUpperCase()}</h2><p>${why}</p>
      <p>Survécu ${Math.floor(survived / 60)} min ${survived % 60} s · réserve ${this.stock} · esquives ${this.stats.dodges} · visites ${this.stats.visitsSurvived}</p>
      <p>Record : ${Math.floor(this.best / 60)} min ${this.best % 60} s</p><button id="again">Rejouer</button></div>`;
    document.body.appendChild(d);
    d.querySelector('#again').onclick = () => { d.remove(); this.reset(); this.canvas.requestPointerLock(); };
    d.querySelector('#again').focus();
  }

  // --- pause and settings -----------------------------------------------------------------

  pause(on) {
    if (this.paused === on) return;
    this.paused = on;
    let m = document.getElementById('pause');
    if (on) {
      document.exitPointerLock?.();
      const s = this.settings;
      m = document.createElement('div');
      m.id = 'pause';
      m.className = 'overlay';
      m.innerHTML = `<div class="menu"><h2>PAUSE</h2>
        <button data-a="resume">Reprendre</button>
        <label>Qualité <select data-s="quality"><option value="high">Haute</option><option value="low">Basse (PC modeste)</option></select></label>
        <label>Sensibilité <input type="range" min="0.3" max="2.5" step="0.1" data-s="sensitivity"></label>
        <label>Volume <input type="range" min="0" max="1" step="0.05" data-s="volume"></label>
        <label>Inverser l'axe vertical <input type="checkbox" data-s="invertY"></label>
        <button data-a="restart">Recommencer</button>
        <div class="keys">ZQSD/WASD bouger · Maj sprint · souris regarder · molette zoom<br>E manger/boire/refuge · G ramasser/poser · Espace sauter/se lâcher<br>F instinct · R enregistrer une vidéo · C photo · Échap pause<br>Manette : stick gauche/droit, A action, X ramasser, Y instinct, B sauter,<br>RB/RT sprint, LB/LT zoom, Back vidéo, clic stick droit photo, Start pause</div></div>`;
      document.body.appendChild(m);
      for (const el of m.querySelectorAll('[data-s]')) {
        const key = el.dataset.s;
        if (el.type === 'checkbox') el.checked = !!s[key]; else el.value = s[key];
        el.oninput = el.onchange = () => {
          s[key] = el.type === 'checkbox' ? el.checked : el.type === 'range' ? Number(el.value) : el.value;
          if (key === 'volume') this.audio.setVolume(s.volume);
          if (key === 'quality') this.onQuality?.(s.quality);
          try { localStorage.setItem('cockroach.settings', JSON.stringify(s)); } catch { /* ignore */ }
        };
      }
      m.querySelector('[data-a=resume]').onclick = () => this.pause(false);
      m.querySelector('[data-a=restart]').onclick = () => { this.pause(false); this.reset(); };
      m.querySelector('[data-a=resume]').focus();
    } else {
      m?.remove();
      if (this.playing) this.canvas.requestPointerLock?.();
    }
  }

  _hud() {
    const h = this.human, w = this.walker;
    this.hud.update({
      suspicion: h ? h.suspicion : 0,
      senses: this.senses || {},
      food: this.food, water: this.water,
      safety: this.inRefuge ? 1 : (1 - (this.exposure || 0) * 0.6) * (1 - (h ? h.suspicion : 0)),
      stock: this.stock,
      carrying: !!this.carrying,
      prompt: this.playing && !this.paused && !this.dead ? this.prompt : null,
      camera: this.camera,
      strike: h && h.strike && !h.strike.done ? h.strike : null,
      recording: this.recorder.active ? this.recorder.elapsed || 0.001 : 0,
      known: [...this.known].filter((it) => !it.gone),
      human: h ? h.pos : new THREE.Vector2(),
      humanVisibleOnMap: h && h.present,
      player: w.pos, heading: w.f,
      pad: this.input.usingPad,
    });
  }
}

const GLOW_FOOD = new THREE.MeshStandardMaterial({ color: 0xffe0a0, emissive: 0x9cff6a, emissiveIntensity: 2.5 });
const GLOW_WATER = new THREE.MeshStandardMaterial({ color: 0xcfe8ff, emissive: 0x4ab0ff, emissiveIntensity: 2.5, transparent: true, opacity: 0.9 });
