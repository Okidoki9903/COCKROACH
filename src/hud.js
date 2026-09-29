// HUD in the style of the concept art: objective (top left), human
// suspicion and instinct senses (right), minimap (bottom left), needs
// (bottom right), a prompt anchored to the object in the world, the strike
// warning, messages, recording indicator. Plain DOM over the canvas.
import * as THREE from 'three';

const ICONS = {
  vibrations: '<svg viewBox="0 0 24 24"><path d="M2 14c2-4 3 4 5 0s3 4 5 0 3 4 5 0 3 4 5 0" fill="none" stroke="currentColor" stroke-width="2"/><path d="M2 9c2-4 3 4 5 0s3 4 5 0 3 4 5 0 3 4 5 0" fill="none" stroke="currentColor" stroke-width="2" opacity=".6"/></svg>',
  humidite: '<svg viewBox="0 0 24 24"><path d="M12 2C8 8 5 11 5 15a7 7 0 0 0 14 0c0-4-3-7-7-13z" fill="currentColor"/></svg>',
  odeur: '<svg viewBox="0 0 24 24"><path d="M6 21c-2-4 2-6 0-10s2-6 0-9M12 21c-2-4 2-6 0-10s2-6 0-9M18 21c-2-4 2-6 0-10s2-6 0-9" fill="none" stroke="currentColor" stroke-width="2"/></svg>',
  mouvement: '<svg viewBox="0 0 24 24"><circle cx="15" cy="4" r="2" fill="currentColor"/><path d="M9 21l3-6 3 3v5M7 12l3-4 5 1 3 4M12 15l1-6" fill="none" stroke="currentColor" stroke-width="2"/></svg>',
  chaleur: '<svg viewBox="0 0 24 24"><path d="M10 3a2 2 0 0 1 4 0v10a4 4 0 1 1-4 0z" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="17" r="2" fill="currentColor"/></svg>',
  humain: '<svg viewBox="0 0 24 24"><circle cx="12" cy="4" r="3" fill="currentColor"/><path d="M8 9h8l-1 7h-2v6h-2v-6H9z" fill="currentColor"/></svg>',
};
const SENSES = [
  ['vibrations', 'Vibrations'], ['humidite', 'Humidité'], ['odeur', 'Odeur de nourriture'],
  ['mouvement', 'Mouvement'], ['chaleur', 'Chaleur'], ['humain', 'Proximité humaine'],
];

export class Hud {
  constructor(root) {
    this.root = root;
    root.innerHTML = `
      <div class="panel objective"><span class="diamond">◆</span><div><div class="h">OBJECTIF</div><div class="obj-text"></div></div></div>
      <div class="panel suspicion"><div class="h"><span class="eye">👁</span> SUSPICION HUMAINE</div><div class="bar"><i></i></div><span class="pct">0%</span></div>
      <div class="instinct"><div class="h">INSTINCT <kbd class="sense-key">F</kbd></div>${SENSES.map(([k, l]) => `<div class="sense" data-k="${k}">${ICONS[k]}<span>${l}</span></div>`).join('')}</div>
      <div class="panel minimap"><div class="h">CUISINE — RDC</div><canvas width="220" height="190"></canvas>
        <div class="legend"><span class="you">➤ Vous</span><span>⌂ Refuge</span><span class="lf">● Nourriture</span><span class="lw">● Eau</span><span class="ld">● Danger</span></div></div>
      <div class="panel needs">
        <div class="need"><span>🍞</span><div><div class="h">NOURRITURE</div><div class="bar food"><i></i></div></div></div>
        <div class="need"><span>💧</span><div><div class="h">EAU</div><div class="bar water"><i></i></div></div></div>
        <div class="need"><span>🛡</span><div><div class="h">SÉCURITÉ</div><div class="bar safety"><i></i></div></div></div>
        <div class="stock">Réserve au refuge : <b>0</b></div>
      </div>
      <div class="prompt" hidden><kbd>E</kbd><span></span></div>
      <div class="warning" hidden><div class="t">⚠ ATTAQUE — BOUGE !</div><div class="bar"><i></i></div></div>
      <div class="toast"></div>
      <div class="rec" hidden><i></i> REC <span>00:00</span></div>
      <div class="carry" hidden>Tu portes une miette — rapporte-la au refuge</div>
    `;
    this.$ = (s) => root.querySelector(s);
    this.objText = this.$('.obj-text');
    this.susBar = this.$('.suspicion .bar i');
    this.susPct = this.$('.suspicion .pct');
    this.senses = Object.fromEntries([...root.querySelectorAll('.sense')].map((e) => [e.dataset.k, e]));
    this.map = this.$('.minimap canvas').getContext('2d');
    this.food = this.$('.bar.food i');
    this.water = this.$('.bar.water i');
    this.safety = this.$('.bar.safety i');
    this.stock = this.$('.stock b');
    this.prompt = this.$('.prompt');
    this.warning = this.$('.warning');
    this.warnBar = this.$('.warning .bar i');
    this.toastEl = this.$('.toast');
    this.recEl = this.$('.rec');
    this.carryEl = this.$('.carry');
    this.v = new THREE.Vector3();
  }

  objective(text) { this.objText.textContent = text; }

  toast(text, ms = 2600) {
    const d = document.createElement('div');
    d.textContent = text;
    this.toastEl.appendChild(d);
    setTimeout(() => d.classList.add('out'), ms);
    setTimeout(() => d.remove(), ms + 600);
  }

  update(s) {
    const pct = Math.round(s.suspicion * 100);
    this.susBar.style.width = pct + '%';
    this.susPct.textContent = pct + '%';
    for (const k in this.senses) this.senses[k].classList.toggle('on', !!s.senses[k]);
    this.food.style.width = s.food * 100 + '%';
    this.water.style.width = s.water * 100 + '%';
    this.safety.style.width = s.safety * 100 + '%';
    this.stock.textContent = s.stock;
    this.carryEl.hidden = !s.carrying;
    this.$('.sense-key').textContent = s.pad ? 'X' : 'F';
    this.prompt.querySelector('kbd').textContent = s.pad ? 'A' : 'E';
    // Prompt anchored in the world.
    if (s.prompt) {
      this.v.copy(s.prompt.pos).project(s.camera);
      const visible = this.v.z < 1 && Math.abs(this.v.x) < 1.1 && Math.abs(this.v.y) < 1.1;
      this.prompt.hidden = !visible;
      if (visible) {
        this.prompt.style.left = ((this.v.x * 0.5 + 0.5) * innerWidth + 28) + 'px';
        this.prompt.style.top = ((-this.v.y * 0.5 + 0.5) * innerHeight - 14) + 'px';
        this.prompt.querySelector('span').textContent = s.prompt.text;
      }
    } else this.prompt.hidden = true;
    // Strike warning.
    this.warning.hidden = !s.strike;
    if (s.strike) this.warnBar.style.width = Math.max(0, 1 - s.strike.t / s.strike.dur) * 100 + '%';
    this.recEl.hidden = !s.recording;
    if (s.recording) {
      const t = Math.floor(s.recording);
      this.recEl.querySelector('span').textContent = String(Math.floor(t / 60)).padStart(2, '0') + ':' + String(t % 60).padStart(2, '0');
    }
    this._minimap(s);
  }

  // Top-down plan of the kitchen: 4.2 x 3.6 m (+ the doorway).
  _minimap(s) {
    const c = this.map, W = 220, H = 190, sc = 44, ox = 12, oy = 16;
    const X = (x) => ox + x * sc, Y = (z) => oy + z * sc;
    c.clearRect(0, 0, W, H);
    c.fillStyle = 'rgba(40,40,40,0.9)';
    c.fillRect(X(0), Y(0), 4.2 * sc, 3.6 * sc);
    c.fillStyle = 'rgba(15,15,15,0.95)';
    c.fillRect(X(0), Y(0), 3.0 * sc, 0.6 * sc);          // cabinets
    c.fillRect(X(3.15), Y(0), 0.7 * sc, 0.7 * sc);       // fridge
    c.fillRect(X(1.5), Y(1.9), 1.1 * sc, 0.8 * sc);      // table
    c.strokeStyle = 'rgba(200,200,200,0.5)';
    c.lineWidth = 1.5;
    c.strokeRect(X(0), Y(0), 4.2 * sc, 3.6 * sc);
    c.clearRect(X(4.2) - 2, Y(2.3), 4, 0.9 * sc);        // door gap
    const dot = (x, z, col, r = 4) => { c.fillStyle = col; c.beginPath(); c.arc(X(x), Y(z), r, 0, Math.PI * 2); c.fill(); };
    for (const it of s.known) dot(it.position.x, it.position.z, it.kind === 'water' ? '#3aa0ff' : '#3ccf5a', 3.5);
    c.fillStyle = '#fff';
    c.font = '14px sans-serif';
    c.fillText('⌂', X(0.03), Y(3.08));
    if (s.humanVisibleOnMap) dot(s.human.x, s.human.y, '#ff3b30', 5);
    // Player arrow.
    c.save();
    c.translate(X(s.player.x), Y(s.player.z));
    c.rotate(Math.atan2(s.heading.x, -s.heading.z));
    c.fillStyle = '#ffd23c';
    c.beginPath(); c.moveTo(0, -7); c.lineTo(5, 6); c.lineTo(0, 3); c.lineTo(-5, 6); c.closePath(); c.fill();
    c.restore();
  }
}
