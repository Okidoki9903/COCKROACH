// All sounds are synthesised with Web Audio (no audio file). Positional
// sounds go through an HRTF panner relative to the camera.
export class Audio {
  constructor() {
    this.ctx = null;
    this.master = null;
    this.volume = 0.8;
  }

  // Must be called from a user gesture (browser autoplay rules).
  start() {
    if (this.ctx) { this.ctx.resume(); return; }
    const ctx = (this.ctx = new (window.AudioContext || window.webkitAudioContext)());
    this.master = ctx.createGain();
    this.master.gain.value = this.volume;
    const comp = ctx.createDynamicsCompressor();
    comp.threshold.value = -12;
    this.master.connect(comp).connect(ctx.destination);
    // Stream for the video recorder.
    this.recordDest = ctx.createMediaStreamDestination();
    comp.connect(this.recordDest);
    this.noise = this._noiseBuffer(2);
    this._roomTone();
  }

  setVolume(v) {
    this.volume = v;
    if (this.master) this.master.gain.value = v;
  }

  // Listener = camera.
  setListener(pos, forward, up) {
    if (!this.ctx) return;
    const l = this.ctx.listener;
    const t = this.ctx.currentTime;
    if (l.positionX) {
      l.positionX.setValueAtTime(pos.x, t); l.positionY.setValueAtTime(pos.y, t); l.positionZ.setValueAtTime(pos.z, t);
      l.forwardX.setValueAtTime(forward.x, t); l.forwardY.setValueAtTime(forward.y, t); l.forwardZ.setValueAtTime(forward.z, t);
      l.upX.setValueAtTime(up.x, t); l.upY.setValueAtTime(up.y, t); l.upZ.setValueAtTime(up.z, t);
    } else {
      l.setPosition(pos.x, pos.y, pos.z);
      l.setOrientation(forward.x, forward.y, forward.z, up.x, up.y, up.z);
    }
  }

  _noiseBuffer(sec) {
    const b = this.ctx.createBuffer(1, this.ctx.sampleRate * sec, this.ctx.sampleRate);
    const d = b.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    return b;
  }

  _panner(pos, ref = 0.5) {
    const p = this.ctx.createPanner();
    p.panningModel = 'HRTF';
    p.distanceModel = 'inverse';
    p.refDistance = ref;
    p.rolloffFactor = 1.2;
    p.positionX.value = pos.x; p.positionY.value = pos.y; p.positionZ.value = pos.z;
    p.connect(this.master);
    return p;
  }

  _roomTone() {
    const ctx = this.ctx;
    const hum = ctx.createOscillator();
    hum.frequency.value = 50;
    const hum2 = ctx.createOscillator();
    hum2.frequency.value = 100;
    const g = ctx.createGain();
    g.gain.value = 0.012;
    const g2 = ctx.createGain();
    g2.gain.value = 0.006;
    const air = ctx.createBufferSource();
    air.buffer = this.noise;
    air.loop = true;
    const lp = ctx.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 400;
    const ga = ctx.createGain();
    ga.gain.value = 0.02;
    const fridge = this._panner({ x: 3.5, y: 0.1, z: 0.2 }, 0.6);
    hum.connect(g).connect(fridge);
    hum2.connect(g2).connect(fridge);
    air.connect(lp).connect(ga).connect(this.master);
    hum.start(); hum2.start(); air.start();
  }

  // Heavy footstep heard from the floor: low thud + heel click.
  footstep(pos, near) {
    if (!this.ctx) return;
    const ctx = this.ctx, t = ctx.currentTime;
    const out = this._panner(pos, 0.8);
    const o = ctx.createOscillator();
    o.frequency.setValueAtTime(95, t);
    o.frequency.exponentialRampToValueAtTime(45, t + 0.12);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.9, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.22);
    o.connect(g).connect(out);
    o.start(t); o.stop(t + 0.25);
    const n = ctx.createBufferSource();
    n.buffer = this.noise;
    const bp = ctx.createBiquadFilter();
    bp.type = 'bandpass'; bp.frequency.value = 800; bp.Q.value = 0.8;
    const gn = ctx.createGain();
    gn.gain.setValueAtTime(0.35 + near * 0.3, t);
    gn.gain.exponentialRampToValueAtTime(0.001, t + 0.05);
    n.connect(bp).connect(gn).connect(out);
    n.start(t, Math.random()); n.stop(t + 0.06);
  }

  // Tiny ticks of the cockroach's legs (only when moving; very quiet).
  scuttle(rate) {
    if (!this.ctx || rate <= 0) return;
    this._scuttleAcc = (this._scuttleAcc || 0) + rate;
    if (this._scuttleAcc < 1) return;
    this._scuttleAcc = 0;
    const ctx = this.ctx, t = ctx.currentTime;
    const n = ctx.createBufferSource();
    n.buffer = this.noise;
    const hp = ctx.createBiquadFilter();
    hp.type = 'highpass'; hp.frequency.value = 5000;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.03 + Math.random() * 0.02, t);
    g.gain.exponentialRampToValueAtTime(0.0005, t + 0.015);
    n.connect(hp).connect(g).connect(this.master);
    n.start(t, Math.random()); n.stop(t + 0.02);
  }

  // Warning whoosh when a strike is announced.
  announce(pos) {
    if (!this.ctx) return;
    const ctx = this.ctx, t = ctx.currentTime;
    const n = ctx.createBufferSource();
    n.buffer = this.noise;
    const bp = ctx.createBiquadFilter();
    bp.type = 'bandpass'; bp.Q.value = 2;
    bp.frequency.setValueAtTime(300, t);
    bp.frequency.exponentialRampToValueAtTime(2000, t + 0.6);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.25, t);
    g.gain.linearRampToValueAtTime(0.7, t + 0.6);
    g.gain.linearRampToValueAtTime(0, t + 0.7);
    n.connect(bp).connect(g).connect(this._panner(pos, 0.5));
    n.start(t); n.stop(t + 0.72);
  }

  impact(pos, hand) {
    if (!this.ctx) return;
    const ctx = this.ctx, t = ctx.currentTime;
    const out = this._panner(pos, 0.5);
    const o = ctx.createOscillator();
    o.frequency.setValueAtTime(hand ? 200 : 120, t);
    o.frequency.exponentialRampToValueAtTime(40, t + 0.2);
    const g = ctx.createGain();
    g.gain.setValueAtTime(1.2, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.35);
    o.connect(g).connect(out);
    o.start(t); o.stop(t + 0.4);
    const n = ctx.createBufferSource();
    n.buffer = this.noise;
    const lp = ctx.createBiquadFilter();
    lp.type = 'lowpass'; lp.frequency.value = hand ? 3000 : 1200;
    const gn = ctx.createGain();
    gn.gain.setValueAtTime(0.9, t);
    gn.gain.exponentialRampToValueAtTime(0.001, t + 0.12);
    n.connect(lp).connect(gn).connect(out);
    n.start(t); n.stop(t + 0.15);
  }

  fridge(open, pos) {
    if (!this.ctx) return;
    const ctx = this.ctx, t = ctx.currentTime;
    const n = ctx.createBufferSource();
    n.buffer = this.noise;
    const bp = ctx.createBiquadFilter();
    bp.type = 'lowpass'; bp.frequency.value = open ? 900 : 500;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.4, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + (open ? 0.3 : 0.12));
    n.connect(bp).connect(g).connect(this._panner(pos, 0.6));
    n.start(t, Math.random()); n.stop(t + 0.35);
  }

  switchClick(pos) {
    if (!this.ctx) return;
    const ctx = this.ctx, t = ctx.currentTime;
    const o = ctx.createOscillator();
    o.type = 'square';
    o.frequency.value = 1800;
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.15, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.03);
    o.connect(g).connect(this._panner(pos, 0.5));
    o.start(t); o.stop(t + 0.04);
  }

  // UI: soft confirmation (eat, drink, deposit).
  blip(high) {
    if (!this.ctx) return;
    const ctx = this.ctx, t = ctx.currentTime;
    const o = ctx.createOscillator();
    o.type = 'sine';
    o.frequency.setValueAtTime(high ? 880 : 520, t);
    o.frequency.exponentialRampToValueAtTime(high ? 1320 : 700, t + 0.08);
    const g = ctx.createGain();
    g.gain.setValueAtTime(0.08, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + 0.18);
    o.connect(g).connect(this.master);
    o.start(t); o.stop(t + 0.2);
  }
}
