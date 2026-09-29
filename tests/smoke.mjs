// Behaviour checks on the real game in headless Chromium (logic only,
// no rendering, except where stated). Run: node tests/smoke.mjs
import { open } from './serve.mjs';

const { page, logs, close } = await open(process.env.SEED ? '&seed=' + process.env.SEED : '');
let failures = 0, checks = 0;
const check = (ok, label, extra = '') => { checks++; if (!ok) failures++; console.log(`  ${ok ? 'PASS' : 'FAIL'} ${label}${extra ? '  (' + extra + ')' : ''}`); };
const E = (fn, arg) => page.evaluate(fn, arg);

// Helpers inside the page.
await E(() => {
  const g = window.__game, T = g.THREE;
  window.T = {
    place(x, y, z, fx, fz, nx = 0, ny = 1, nz = 0) {
      g.game.inRefuge = false; g.game.refugeVeil(false);
      g.walker.place(new T.Vector3(x, y, z), new T.Vector3(nx, ny, nz), new T.Vector3(fx, 0, fz).normalize());
      g.follow.heading.copy(g.walker.f); g.follow.lastN.copy(g.walker.n); g.follow.smoothPos = null;
    },
    hold(code, on) { if (on) g.game.input.keys.add(code); else g.game.input.keys.delete(code); },
    press(a) { g.game.input.pressed.add(a); g.sim(1); },
    w() { const w = g.walker; return { x: +w.pos.x.toFixed(3), y: +w.pos.y.toFixed(3), z: +w.pos.z.toFixed(3), nx: +w.n.x.toFixed(2), ny: +w.n.y.toFixed(2), nz: +w.n.z.toFixed(2), grounded: w.grounded }; },
  };
});

console.log('-- chargement');
check(logs.filter((l) => l.includes('PAGEERROR') || l.startsWith('error')).length === 0, 'aucune erreur au chargement', logs.join(' | '));

console.log('-- locomotion');
let r = await E(() => { T.place(1.0, 0, 1.2, 0, -1); T.hold('KeyW', true); __game.sim(60 * 14); T.hold('KeyW', false); return T.w(); });
check(r.y > 0.85 && r.ny > 0.8 && r.z < 0.65, 'marcher vers les meubles : grimpe la plinthe, la façade, arrive sur le plan de travail', JSON.stringify(r));
r = await E(() => { T.place(2.05, 0.76, 2.3, 0, 1); T.hold('KeyW', true); __game.sim(60 * 6); T.hold('KeyW', false); return T.w(); });
check(r.grounded && (r.ny < 0.5 || r.y < 0.05), 'sortir du bord de la table : passe sur la tranche ou descend', JSON.stringify(r));
r = await E(() => { T.place(0.0, 1.2, 1.0, 0, 1, 1, 0, 0); __game.sim(5); const on = T.w(); T.press('letgo'); __game.sim(120); return [on, T.w()]; });
check(Math.abs(r[0].nx - 1) < 0.05 && r[1].grounded && r[1].y < 0.08 && r[1].ny > 0.9, 'sur un mur, se lâcher : tombe (au sol ou sur la plinthe)', JSON.stringify(r));
r = await E(() => { T.place(2.0, 2.6, 1.0, 1, 0, 0, -1, 0); T.hold('KeyW', true); __game.sim(60); T.hold('KeyW', false); return T.w(); });
check(r.grounded && r.ny < -0.9 && r.y > 2.5, 'marcher au plafond', JSON.stringify(r));

console.log('-- besoins et interactions');
r = await E(() => {
  const g = __game.game;
  const drop = g.kitchen.items.find((i) => i.kind === 'water' && i.position.y < 0.01);
  T.place(drop.position.x + 0.02, 0, drop.position.z, -1, 0);
  __game.sim(2);
  const before = g.water; T.press('interact'); return [before, g.water, g.prompt && g.prompt.text];
});
check(r[1] > r[0] + 0.3, 'boire une goutte', JSON.stringify(r));
r = await E(() => {
  const g = __game.game;
  const c = g.kitchen.items.find((i) => i.kind === 'food' && !i.gone && i.position.y < 0.02);
  T.place(c.position.x + 0.02, 0, c.position.z, -1, 0); __game.sim(2);
  T.press('grab');
  const carrying = !!g.carrying;
  const r0 = g.kitchen.refuge;
  T.place(0.05, 0, r0.z, -1, 0); __game.sim(2);
  const near = g.nearRefuge;
  T.press('interact');
  return [carrying, near, g.inRefuge, g.stock];
});
check(r[0] && r[1] && r[2] && r[3] === 1, 'ramasser une miette, la rapporter au refuge : réserve 1', JSON.stringify(r));
r = await E(() => { const g = __game.game; g.food = 0.3; T.press('interact'); return [g.food, g.stock]; });
check(r[0] > 0.6 && r[1] === 0, 'au refuge, manger la réserve', JSON.stringify(r));

console.log("-- humain : visite, lumière, perception, frappe");
r = await E(() => {
  const g = __game.game, h = g.human;
  T.place(1.2, 0, 0.3, 1, 0);           // hidden under the cabinets
  h.timer = 0; __game.sim(2);
  let lightSeen = false, maxT = 0;
  for (let i = 0; i < 60 * 40; i++) { __game.sim(1); if (g.kitchen.ceilingLight.intensity > 0) lightSeen = true; if (h.state === 'away' && i > 60) break; maxT = i; }
  return [lightSeen, h.state, g.kitchen.ceilingLight.intensity, (maxT / 60).toFixed(1), h.task];
});
check(r[0] && r[1] === 'away' && r[2] === 0, "visite : l'humain entre, allume, fait sa tâche, repart et éteint", JSON.stringify(r));
// The human by the table, facing west; the cockroach in the open, lit,
// half a metre in front of them.
await E(() => {
  window.T.stage = (move) => {
    const g = __game.game, h = g.human;
    document.querySelector('.death')?.remove();
    if (g.dead) g.reset();
    h._startVisit();
    h.strike = null; h.ring.visible = false;
    h.task = 'table'; h.state = 'task'; h.timer = 60; h.taskTime = 0;
    h.pos.set(3.4, 1.75); h.yaw = -Math.PI / 2;           // facing west, toward the table
    h.suspicion = 0; h.cooldown = 0;
    g.kitchen.setCeiling(true);
    T.place(2.85, 0, 1.75, 0, 1);
    let announced = null;
    if (move) T.hold('KeyD', true);
    for (let i = 0; i < 60 * 15; i++) {
      __game.sim(1);
      if (h.strike && !announced) announced = { at: (i / 60).toFixed(2), sus: 1 };
      if (g.dead || (announced && !h.strike)) break;
    }
    T.hold('KeyD', false);
    return [!!announced, g.dead, g.stats.dodges, announced && announced.at];
  };
});
r = await E(() => T.stage(true));
check(r[0], 'repéré en bougeant à découvert sous la lumière : attaque annoncée', JSON.stringify(r));
check(!r[1] && r[2] === 1, "continuer à bouger pendant l'annonce : esquivé", JSON.stringify(r));
r = await E(() => T.stage(false));
check(r[0] && r[1], 'immobile : repéré plus lentement, puis écrasé', JSON.stringify(r));
r = await E(() => {
  const g = __game.game;
  document.querySelector('.death')?.remove(); g.reset();
  const h = g.human;
  // Under the cabinets (behind the plinth): covered.
  T.place(1.2, 0, 0.3, 1, 0);
  h.timer = 0; __game.sim(1);
  h.suspicion = 1; __game.sim(1);
  let hit = false;
  for (let i = 0; i < 60 * 4; i++) { __game.sim(1); if (g.dead) { hit = true; break; } }
  return [hit, g.stats.dodges];
});
check(!r[0], 'sous les meubles : la frappe ne passe pas', JSON.stringify(r));

console.log('-- enregistrement');
r = await E(async () => { const { Recorder } = await import('./src/recorder.js'); return Recorder.mime(); });
check(!!r, 'format vidéo disponible dans ce navigateur', r);

console.log(`RESULT: ${checks - failures}/${checks}`);
console.log(logs.slice(0, 20).join('\n'));
await close();
process.exit(failures ? 1 : 0);
