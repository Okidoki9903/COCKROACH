// Keyboard (physical positions: ZQSD on AZERTY = WASD on QWERTY), mouse
// (pointer lock) and gamepad (standard mapping: Xbox / 8BitDo X-input /
// PlayStation). The game reads one merged state per frame.
export class Input {
  constructor(canvas) {
    this.keys = new Set();
    this.pressed = new Set();        // actions pressed this frame
    this.look = { x: 0, y: 0 };      // radians requested this frame
    this.zoom = 1;
    this.mouseSensitivity = 0.0025;
    this.stickLookSpeed = 2.6;       // rad/s at full tilt
    this.usingPad = false;
    this.canvas = canvas;
    this._padPrev = [];
    this._wheel = 0;

    addEventListener('keydown', (e) => {
      if (e.repeat) return;
      this.keys.add(e.code);
      const a = KEYMAP[e.code];
      if (a) this.pressed.add(a);
      this.usingPad = false;
      if (['Space', 'Tab', 'F3'].includes(e.code)) e.preventDefault();
    });
    addEventListener('keyup', (e) => this.keys.delete(e.code));
    addEventListener('blur', () => this.keys.clear());
    addEventListener('mousemove', (e) => {
      if (document.pointerLockElement !== canvas) return;
      this.look.x += e.movementX * this.mouseSensitivity;
      this.look.y -= e.movementY * this.mouseSensitivity;
      if (Math.abs(e.movementX) + Math.abs(e.movementY) > 2) this.usingPad = false;
    });
    addEventListener('wheel', (e) => { this._wheel += Math.sign(e.deltaY); }, { passive: true });
  }

  // Call once per frame before reading.
  poll(dt) {
    let mx = 0, my = 0;
    const k = (c) => this.keys.has(c);
    if (k('KeyW') || k('ArrowUp')) my += 1;
    if (k('KeyS') || k('ArrowDown')) my -= 1;
    if (k('KeyA') || k('ArrowLeft')) mx -= 1;
    if (k('KeyD') || k('ArrowRight')) mx += 1;
    let sprint = k('ShiftLeft') || k('ShiftRight');
    let len = Math.hypot(mx, my);
    if (len > 1) { mx /= len; my /= len; }

    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    for (const p of pads) {
      if (!p || !p.connected) continue;
      const dz = (v, z) => (Math.abs(v) < z ? 0 : (v - Math.sign(v) * z) / (1 - z));
      const lx = dz(p.axes[0] || 0, 0.18), ly = dz(p.axes[1] || 0, 0.18);
      const rx = dz(p.axes[2] || 0, 0.15), ry = dz(p.axes[3] || 0, 0.15);
      const b = (i) => !!(p.buttons[i] && p.buttons[i].pressed);
      const dpad = [b(12) ? 1 : 0, b(13) ? 1 : 0, b(14) ? 1 : 0, b(15) ? 1 : 0];
      if (lx || ly || dpad.some(Boolean)) {
        mx += lx + dpad[3] - dpad[2];
        my += -ly + dpad[0] - dpad[1];
        this.usingPad = true;
      }
      if (rx || ry) {
        const mag = Math.hypot(rx, ry);
        this.look.x += rx * mag * this.stickLookSpeed * dt;
        this.look.y += -ry * mag * this.stickLookSpeed * dt;
        this.usingPad = true;
      }
      if (b(5) || b(10) || (p.buttons[7] && p.buttons[7].value > 0.3)) sprint = true;
      if (b(6)) this.zoom *= 1 + dt * 1.5;          // LT: zoom out
      if (b(4)) this.zoom *= 1 - dt * 1.5;          // LB: zoom in
      PADMAP.forEach((action, i) => {
        const now = b(i);
        if (now && !this._padPrev[i] && action) { this.pressed.add(action); this.usingPad = true; }
        this._padPrev[i] = now;
      });
    }
    len = Math.hypot(mx, my);
    if (len > 1) { mx /= len; my /= len; }
    if (this._wheel) {
      this.zoom *= Math.pow(1.12, this._wheel);
      this._wheel = 0;
    }
    return { move: { x: mx, y: my }, sprint };
  }

  // Look and zoom accumulated since the last call, then reset.
  consume() {
    const out = { look: { ...this.look }, zoom: this.zoom };
    this.look.x = this.look.y = 0;
    this.zoom = 1;
    return out;
  }

  endFrame() { this.pressed.clear(); }
  was(action) { return this.pressed.has(action); }
}

// Physical key -> action (pressed once).
const KEYMAP = {
  KeyE: 'interact', KeyG: 'grab', Space: 'letgo', Escape: 'pause', KeyP: 'pause', KeyR: 'record',
  KeyF: 'sense', Tab: 'sense', KeyC: 'photo',
};
// Standard gamepad button index -> action.
const PADMAP = [];
PADMAP[0] = 'interact';   // A
PADMAP[1] = 'letgo';      // B
PADMAP[2] = 'grab';       // X
PADMAP[3] = 'sense';      // Y
PADMAP[11] = 'photo';     // right stick click
PADMAP[9] = 'pause';      // Start
PADMAP[8] = 'record';     // Back / Select
