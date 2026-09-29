// The kitchen at night, built in real metres. Everything the cockroach can
// walk on (floor, walls, cabinets, worktop, table, chairs, fridge...) is a
// "solid": a mesh the locomotion raycasts against.
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import * as T from './textures.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

export const ROOM = { w: 4.2, d: 3.6, h: 2.6 };

export function buildKitchen(scene) {
  const solids = new THREE.Group();
  solids.name = 'solids';
  const decor = new THREE.Group();
  scene.add(solids, decor);

  const mats = makeMaterials();

  // Adds a box; its min corner and size in metres. solid = walkable.
  function box(x0, y0, z0, sx, sy, sz, mat, solid = true, rounded = 0) {
    const g = rounded > 0 ? new RoundedBoxGeometry(sx, sy, sz, 2, rounded) : new THREE.BoxGeometry(sx, sy, sz);
    metricUV(g, x0 + sx / 2, y0 + sy / 2, z0 + sz / 2);
    const m = new THREE.Mesh(g, mat);
    m.position.set(x0 + sx / 2, y0 + sy / 2, z0 + sz / 2);
    m.castShadow = true;
    m.receiveShadow = true;
    (solid ? solids : decor).add(m);
    return m;
  }

  // --- shell -------------------------------------------------------------------
  const floor = new THREE.Mesh(new THREE.PlaneGeometry(ROOM.w, ROOM.d), mats.floor);
  floor.rotation.x = -Math.PI / 2;
  floor.position.set(ROOM.w / 2, 0, ROOM.d / 2);
  floor.receiveShadow = true;
  solids.add(floor);

  const ceiling = new THREE.Mesh(new THREE.PlaneGeometry(ROOM.w, ROOM.d), mats.ceiling);
  ceiling.rotation.x = Math.PI / 2;
  ceiling.position.set(ROOM.w / 2, ROOM.h, ROOM.d / 2);
  solids.add(ceiling);

  // Walls are thin boxes (they cast shadows: the window and door shapes).
  const t = 0.1;
  box(-t, 0, 0, ROOM.w + 2 * t, ROOM.h, -t, mats.wall);              // back (z = 0)
  box(-t, 0, ROOM.d, ROOM.w + 2 * t, ROOM.h, t, mats.wall);           // front
  // Left wall (x = 0) with the window opening z 1.3..2.3, y 1.0..2.1.
  box(-t, 0, 0, t, ROOM.h, 1.3, mats.wall);
  box(-t, 0, 2.3, t, ROOM.h, ROOM.d - 2.3, mats.wall);
  box(-t, 0, 1.3, t, 1.0, 1.0, mats.wall);
  box(-t, 2.1, 1.3, t, ROOM.h - 2.1, 1.0, mats.wall);
  // Right wall (x = w) with the door opening z 2.3..3.2, y 0..2.05.
  box(ROOM.w, 0, 0, t, ROOM.h, 2.3, mats.wall);
  box(ROOM.w, 0, 3.2, t, ROOM.h, ROOM.d - 3.2, mats.wall);
  box(ROOM.w, 2.05, 2.3, t, ROOM.h - 2.05, 0.9, mats.wall);

  // Window: sill, frame, mullions, glass, night outside.
  box(-0.02, 0.98, 1.28, 0.08, 0.03, 1.04, mats.whitePaint);
  for (const z of [1.3, 1.79, 2.28]) box(-0.03, 1.0, z, 0.03, 1.1, 0.02, mats.whitePaint, false);
  for (const y of [1.0, 1.55, 2.08]) box(-0.03, y, 1.3, 0.03, 0.02, 1.0, mats.whitePaint, false);
  const glass = new THREE.Mesh(new THREE.PlaneGeometry(1.0, 1.1), mats.glass);
  glass.rotation.y = Math.PI / 2;
  glass.position.set(-0.015, 1.55, 1.8);
  decor.add(glass);
  const sky = new THREE.Mesh(new THREE.PlaneGeometry(3, 2.5), mats.nightSky);
  sky.rotation.y = Math.PI / 2;
  sky.position.set(-1.2, 1.6, 1.8);
  decor.add(sky);

  // Door frame and the hallway beyond it.
  box(ROOM.w - 0.01, 0, 2.26, 0.12, 2.09, 0.04, mats.whitePaint);
  box(ROOM.w - 0.01, 0, 3.2, 0.12, 2.09, 0.04, mats.whitePaint);
  box(ROOM.w - 0.01, 2.05, 2.26, 0.12, 0.04, 0.98, mats.whitePaint);
  // Hallway walls (solid: the cockroach can explore it, not leave it).
  box(ROOM.w + 0.1, 0, 1.45, 2.0, 2.6, 0.1, mats.hallWalls);
  box(ROOM.w + 0.1, 0, 3.95, 2.0, 2.6, 0.1, mats.hallWalls);
  box(ROOM.w + 2.1, 0, 1.45, 0.1, 2.6, 2.6, mats.hallWalls);
  box(ROOM.w + 0.1, 2.6, 1.45, 2.1, 0.1, 2.6, mats.hallWalls);
  const hallFloor = new THREE.Mesh(new THREE.PlaneGeometry(2.0, 2.4), mats.woodFloor);
  hallFloor.rotation.x = -Math.PI / 2;
  hallFloor.position.set(ROOM.w + 1.1, 0.0005, 2.75);
  hallFloor.receiveShadow = true;
  solids.add(hallFloor);

  // Baseboards; the left one has the refuge crack at z 3.00..3.035.
  const bb = 0.07, bt = 0.012;
  box(0, 0, 0.6, bt, bb, 2.4, mats.whitePaint);
  box(0, 0, 3.035, bt, bb, ROOM.d - 3.035, mats.whitePaint);
  box(ROOM.w - bt, 0, 0.72, bt, bb, 1.58, mats.whitePaint);
  box(0, 0, ROOM.d - bt, ROOM.w, bb, bt, mats.whitePaint);
  // Behind the crack: a dark hole into the wall (the refuge).
  box(-0.06, 0, 3.0, 0.06, 0.014, 0.035, mats.dark);
  box(-0.06, 0.028, 3.0, 0.06, 0.02, 0.035, mats.dark, false);
  const refuge = new THREE.Vector3(-0.004, 0.008, 3.0175);   // the crack's mouth

  // --- base cabinets along the back wall ------------------------------------------
  // Recessed plinth with a broken piece (x 1.50..1.58) into the dark space
  // under the cabinets.
  box(0, 0, 0.5, 1.5, 0.1, 0.015, mats.plinth);
  box(1.58, 0, 0.5, 1.42, 0.1, 0.015, mats.plinth);
  box(0, 0.1, 0, 3.0, 0.78, 0.58, mats.walnut);
  // Door gaps and handles.
  for (let x = 0.6; x < 3.0; x += 0.6) box(x - 0.002, 0.11, 0.579, 0.004, 0.76, 0.003, mats.dark, false);
  for (let x = 0.3; x < 3.0; x += 0.6) box(x - 0.08, 0.78, 0.58, 0.16, 0.012, 0.02, mats.steelBar, false, 0.005);
  // Oven: dark glass front with a steel bar and a green clock.
  box(0.04, 0.14, 0.581, 0.52, 0.5, 0.004, mats.ovenGlass, false);
  box(0.12, 0.66, 0.583, 0.36, 0.012, 0.02, mats.steelBar, false, 0.005);
  const clock = box(0.25, 0.7, 0.582, 0.1, 0.03, 0.002, mats.clock, false);
  // Worktop around the sink hole (x 1.5..2.1, z 0.08..0.5).
  const ty = 0.88, tt = 0.04;
  box(0, ty, 0, 1.5, tt, 0.62, mats.granite);
  box(2.1, ty, 0, 0.95, tt, 0.62, mats.granite);
  box(1.5, ty, 0, 0.6, tt, 0.08, mats.granite);
  box(1.5, ty, 0.5, 0.6, tt, 0.12, mats.granite);
  // Sink basin.
  box(1.5, 0.72, 0.08, 0.6, 0.01, 0.42, mats.steel);
  box(1.5, 0.72, 0.08, 0.01, 0.2, 0.42, mats.steel);
  box(2.09, 0.72, 0.08, 0.01, 0.2, 0.42, mats.steel);
  box(1.5, 0.72, 0.08, 0.6, 0.2, 0.01, mats.steel);
  box(1.5, 0.72, 0.49, 0.6, 0.2, 0.01, mats.steel);
  // Faucet.
  const tap = new THREE.Group();
  const post = new THREE.Mesh(new THREE.CylinderGeometry(0.014, 0.018, 0.28, 24), mats.chrome);
  post.position.y = 0.14;
  const spout = new THREE.Mesh(new THREE.TorusGeometry(0.1, 0.011, 12, 32, Math.PI), mats.chrome);
  spout.rotation.y = Math.PI / 2;
  spout.position.set(0, 0.28, 0.1);
  tap.add(post, spout);
  tap.position.set(1.8, ty + tt, 0.05);
  tap.traverse((o) => { o.castShadow = true; });
  solids.add(tap);
  // Backsplash and upper cabinets with their warm LED strip.
  const splash = new THREE.Mesh(new THREE.PlaneGeometry(3.0, 0.53), mats.subway);
  splash.position.set(1.5, 0.92 + 0.265, 0.002);
  splash.receiveShadow = true;
  solids.add(splash);
  box(0, 1.45, 0, 2.4, 0.7, 0.35, mats.walnut);
  for (let x = 0.6; x < 2.4; x += 0.6) box(x - 0.002, 1.46, 0.349, 0.004, 0.68, 0.003, mats.dark, false);
  box(0.02, 1.445, 0.3, 2.36, 0.006, 0.012, mats.led, false);

  // --- fridge --------------------------------------------------------------------------
  box(3.15, 0.02, 0, 0.7, 1.83, 0.66, mats.steel);
  for (const x of [3.18, 3.8]) box(x, 0, 0.55, 0.02, 0.02, 0.02, mats.dark);
  const fridgeDoor = new THREE.Group();
  fridgeDoor.position.set(3.85, 0.02, 0.66);          // hinge on the right
  const doorMesh = new THREE.Mesh(new RoundedBoxGeometry(0.7, 1.83, 0.06, 2, 0.01), mats.steel);
  doorMesh.position.set(-0.35, 0.915, 0.03);
  doorMesh.castShadow = doorMesh.receiveShadow = true;
  const handle = new THREE.Mesh(new RoundedBoxGeometry(0.02, 0.5, 0.03, 2, 0.008), mats.chrome);
  handle.position.set(-0.64, 1.1, 0.08);
  fridgeDoor.add(doorMesh, handle);
  solids.add(fridgeDoor);
  const fridgeInside = new THREE.Mesh(new THREE.BoxGeometry(0.64, 1.7, 0.02), mats.fridgeInside);
  fridgeInside.position.set(3.5, 0.95, 0.58);
  decor.add(fridgeInside);
  const fridgeLight = new THREE.PointLight(0xdcecff, 0, 3, 2);
  fridgeLight.position.set(3.5, 1.3, 0.8);
  scene.add(fridgeLight);

  // --- table, chairs, rug, bin -------------------------------------------------------
  const rugGeo = new THREE.BoxGeometry(1.7, 0.006, 1.3);
  metricUV(rugGeo, 2.05, 0.003, 2.3);
  const rug = new THREE.Mesh(rugGeo, mats.rug);
  rug.position.set(2.05, 0.003, 2.3);
  rug.receiveShadow = true;
  solids.add(rug);
  box(1.5, 0.72, 1.9, 1.1, 0.04, 0.8, mats.tableWood, true, 0.008);
  for (const [x, z] of [[1.55, 1.95], [2.51, 1.95], [1.55, 2.61], [2.51, 2.61]]) box(x, 0, z, 0.04, 0.72, 0.04, mats.tableWood);
  chair(solids, mats, 2.05, 3.0, Math.PI);
  chair(solids, mats, 1.2, 2.3, Math.PI / 2);
  const bin = new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.14, 0.45, 32), mats.steel);
  bin.position.set(3.95, 0.225, 1.3);
  bin.castShadow = bin.receiveShadow = true;
  solids.add(bin);

  // Fruit bowl and a sugar jar (worktop).
  const bowl = new THREE.Mesh(new THREE.LatheGeometry([new THREE.Vector2(0.001, 0), new THREE.Vector2(0.06, 0.005), new THREE.Vector2(0.11, 0.06), new THREE.Vector2(0.105, 0.062)], 32), mats.ceramic);
  bowl.position.set(2.2, 0.76, 2.25);
  bowl.castShadow = true;
  decor.add(bowl);
  const fruitCols = [0xff8a1c, 0xc7261c, 0xffb13b];
  [[0, 0.05, 0], [0.05, 0.045, 0.03], [-0.045, 0.045, 0.03]].forEach((p, i) => {
    const f = new THREE.Mesh(new THREE.SphereGeometry(0.036, 24, 16), new THREE.MeshStandardMaterial({ color: fruitCols[i], roughness: 0.45 }));
    f.position.set(2.2 + p[0], 0.76 + p[1], 2.25 + p[2]);
    f.castShadow = true;
    decor.add(f);
  });
  const jar = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.14, 32), mats.glassJar);
  jar.position.set(2.5, ty + tt + 0.07, 0.25);
  decor.add(jar);
  props(solids, decor, mats, ty + tt);

  // --- lights ----------------------------------------------------------------------------
  const lights = {};
  scene.add(new THREE.HemisphereLight(0x33415f, 0x1e140c, 0.45));
  const moon = new THREE.DirectionalLight(0xa8bbff, 2.6);
  moon.position.set(-2.5, 3.2, 2.2);
  moon.target.position.set(1.6, 0, 1.6);
  moon.castShadow = true;
  moon.shadow.mapSize.set(2048, 2048);
  Object.assign(moon.shadow.camera, { left: -3, right: 3, top: 3, bottom: -3, near: 0.5, far: 9 });
  moon.shadow.bias = -0.0004;
  moon.shadow.normalBias = 0.01;
  moon.shadow.radius = 4;
  scene.add(moon, moon.target);
  lights.moon = moon;
  // Under-cabinet LEDs: warm pools on the worktop.
  for (const x of [0.4, 1.2, 2.0]) {
    const s = new THREE.SpotLight(0xffc27a, 6, 2.6, Math.PI / 3, 0.8, 2);
    s.position.set(x, 1.44, 0.28);
    s.target.position.set(x, 0, 0.45);
    scene.add(s, s.target);
  }
  // Hallway light spilling through the door.
  const hallLight = new THREE.SpotLight(0xffb870, 110, 8, Math.PI / 3.5, 0.6, 2);
  hallLight.position.set(ROOM.w + 1.5, 2.2, 2.75);
  hallLight.target.position.set(2.8, 0, 2.7);
  hallLight.castShadow = true;
  hallLight.shadow.mapSize.set(1024, 1024);
  hallLight.shadow.bias = -0.0005;
  hallLight.shadow.radius = 3;
  scene.add(hallLight, hallLight.target);
  lights.hall = hallLight;
  // Night light plugged low on the left wall: a warm pool at floor level.
  const nl = new THREE.Mesh(new THREE.SphereGeometry(0.025, 24, 12, 0, Math.PI * 2, 0, Math.PI / 2), mats.nightlight);
  nl.rotation.z = -Math.PI / 2;
  nl.position.set(0.0, 0.3, 0.8);
  decor.add(nl);
  const nightLight = new THREE.PointLight(0xffa04a, 3.5, 2.2, 2);
  nightLight.position.set(0.05, 0.3, 0.8);
  scene.add(nightLight);
  // Ceiling light: off until the human switches it on.
  const lamp = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 0.03, 48), mats.lampOff);
  lamp.position.set(2.1, ROOM.h - 0.015, 1.8);
  lamp.userData.dynamic = true;
  decor.add(lamp);
  // A wide spot pointing down: one shadow map instead of a point light's six.
  const ceilingLight = new THREE.SpotLight(0xfff0d8, 0, 8, 1.35, 0.7, 2);
  ceilingLight.position.set(2.1, ROOM.h - 0.08, 1.8);
  ceilingLight.target.position.set(2.1, 0, 1.8);
  ceilingLight.castShadow = true;
  ceilingLight.shadow.mapSize.set(1024, 1024);
  ceilingLight.shadow.bias = -0.0008;
  ceilingLight.shadow.radius = 3;
  scene.add(ceilingLight, ceilingLight.target);

  // --- things to find ----------------------------------------------------------------------
  const items = [];
  const crumbMat = mats.crumb;
  function crumb(x, y, z, s, amount) {
    const g = new THREE.IcosahedronGeometry(s, 1);
    const p = g.attributes.position;
    for (let i = 0; i < p.count; i++) p.setXYZ(i, p.getX(i) * (0.8 + Math.random() * 0.5), p.getY(i) * (0.5 + Math.random() * 0.3), p.getZ(i) * (0.8 + Math.random() * 0.5));
    g.computeVertexNormals();
    const m = new THREE.Mesh(g, crumbMat);
    m.position.set(x, y + s * 0.4, z);
    m.castShadow = true;
    m.userData.dynamic = true;
    decor.add(m);
    items.push({ kind: 'food', mesh: m, position: m.position.clone(), amount, label: 'miette' });
  }
  crumb(2.05, 0.006, 2.2, 0.006, 1);
  crumb(1.82, 0.006, 2.52, 0.005, 1);
  crumb(2.3, 0.006, 1.98, 0.007, 1);
  crumb(1.25, 0, 2.62, 0.005, 1);
  crumb(2.62, ty + tt, 0.36, 0.004, 1);    // sugar grains by the jar
  crumb(2.58, ty + tt, 0.33, 0.003, 1);
  crumb(2.2, 0.76, 2.1, 0.005, 1);         // on the table, near the fruit
  const drops = [];
  function drop(x, y, z, r) {
    const m = new THREE.Mesh(new THREE.SphereGeometry(r, 32, 16, 0, Math.PI * 2, 0, Math.PI / 2), mats.water);
    m.scale.y = 0.55;
    m.position.set(x, y, z);
    m.userData.dynamic = true;
    decor.add(m);
    drops.push(m);
    items.push({ kind: 'water', mesh: m, position: m.position.clone(), amount: 1, label: "goutte d'eau" });
  }
  drop(1.54, 0.0005, 0.62, 0.012);         // small leak under the sink, by the plinth gap
  drop(1.8, 0.7305, 0.3, 0.01);            // in the sink basin
  drop(2.3, 0.0005, 3.35, 0.009);

  // Static geometry sharing a material becomes one mesh: about ten times
  // fewer draw calls (each pass: image, depth, shadows).
  mergeStatic(solids);
  mergeStatic(decor);

  return {
    solids, decor, lights, items, refuge, fridgeDoor, fridgeLight, ceilingLight, lamp, mats,
    door: new THREE.Vector3(ROOM.w + 0.6, 0, 2.75),
    fridgeFront: new THREE.Vector3(3.5, 0, 1.25),
    sinkFront: new THREE.Vector3(1.8, 0, 1.05),
    tableSide: new THREE.Vector3(2.05, 0, 3.25),
    heat: new THREE.Vector3(3.5, 0.05, 0.1),
    clock,
    setCeiling(on) {
      ceilingLight.intensity = on ? 9 : 0;
      ceilingLight.visible = on;          // no shadow pass while off
      lamp.material = on ? mats.lampOn : mats.lampOff;
    },
    setFridgeOpen(k) {
      fridgeDoor.rotation.y = k * 1.9;
      fridgeLight.intensity = k * 6;
      fridgeLight.visible = k > 0;
    },
  };
}

// A chair's parts become individual solids (the raycaster tests direct
// children of the solids group).
// UVs in metres (world position on the face's plane): textures keep their
// real size on every box instead of stretching over each face.
function metricUV(g, cx, cy, cz) {
  const p = g.attributes.position, n = g.attributes.normal, uv = g.attributes.uv;
  for (let i = 0; i < p.count; i++) {
    const x = p.getX(i) + cx, y = p.getY(i) + cy, z = p.getZ(i) + cz;
    const ax = Math.abs(n.getX(i)), ay = Math.abs(n.getY(i)), az = Math.abs(n.getZ(i));
    if (ax >= ay && ax >= az) uv.setXY(i, z, y);
    else if (ay >= az) uv.setXY(i, x, z);
    else uv.setXY(i, x, y);
  }
  uv.needsUpdate = true;
}

function mergeStatic(group) {
  group.updateMatrixWorld(true);
  const byMat = new Map();
  for (const m of group.children.slice()) {
    if (!m.isMesh || m.userData.dynamic || Array.isArray(m.material)) continue;
    if (!byMat.has(m.material)) byMat.set(m.material, []);
    byMat.get(m.material).push(m);
  }
  for (const [mat, list] of byMat) {
    if (list.length < 2) continue;
    const geos = list.map((m) => {
      let g = m.geometry.index ? m.geometry.toNonIndexed() : m.geometry.clone();
      g.applyMatrix4(m.matrixWorld);
      for (const name of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(name)) g.deleteAttribute(name);
      return g;
    });
    const merged = new THREE.Mesh(mergeGeometries(geos), mat);
    merged.castShadow = list.some((m) => m.castShadow);
    merged.receiveShadow = true;
    list.forEach((m) => group.remove(m));
    group.add(merged);
  }
}

// Everyday objects on the worktop and around: they make the scale read.
function props(solids, decor, mats, top) {
  const add = (mesh, x, y, z, solid = true) => {
    mesh.position.set(x, y, z);
    mesh.castShadow = mesh.receiveShadow = true;
    (solid ? solids : decor).add(mesh);
    return mesh;
  };
  const lathe = (pts, mat, seg = 40) => new THREE.Mesh(new THREE.LatheGeometry(pts.map(([r, y]) => new THREE.Vector2(r, y)), seg), mat);
  // Kettle.
  add(lathe([[0.001, 0], [0.085, 0], [0.095, 0.03], [0.09, 0.15], [0.06, 0.2], [0.02, 0.21], [0.001, 0.215]], mats.kettle), 0.45, top, 0.3);
  // Bottles: olive oil, vinegar, a wine bottle.
  const bottle = (r, h, mat) => lathe([[0.001, 0], [r, 0], [r, h * 0.62], [r * 0.4, h * 0.8], [r * 0.32, h], [0.001, h]], mat, 32);
  add(bottle(0.035, 0.3, mats.bottleGreen), 0.18, top, 0.18);
  add(bottle(0.03, 0.26, mats.bottleAmber), 0.27, top, 0.12);
  add(bottle(0.037, 0.32, mats.bottleDark), 2.85, top, 0.15);
  // Cutting board leaning against the backsplash, a mug, a dish towel.
  const board = add(new THREE.Mesh(new RoundedBoxGeometry(0.34, 0.24, 0.02, 2, 0.008), mats.boardWood), 1.1, top + 0.12, 0.04);
  board.rotation.x = -0.12;
  add(lathe([[0.001, 0], [0.042, 0], [0.045, 0.1], [0.041, 0.1], [0.038, 0.004], [0.001, 0.004]], mats.mug), 2.35, top, 0.45);
  const towel = add(new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.34, 0.006), mats.towel), 0.3, 0.54, 0.605, true);
  towel.rotation.x = 0.03;
  // Plant on the table.
  add(lathe([[0.001, 0], [0.05, 0], [0.065, 0.11], [0.06, 0.11], [0.046, 0.01], [0.001, 0.01]], mats.pot), 1.8, 0.76, 2.55);
  const leafGeo = new THREE.SphereGeometry(1, 12, 8);
  for (let i = 0; i < 9; i++) {
    const a = i / 9 * Math.PI * 2;
    const leaf = new THREE.Mesh(leafGeo, mats.leaf);
    leaf.scale.set(0.012, 0.004, 0.07);
    leaf.position.set(1.8 + Math.cos(a) * 0.04, 0.9 + (i % 3) * 0.02, 2.55 + Math.sin(a) * 0.04);
    leaf.rotation.set(-0.7 - (i % 3) * 0.2, -a + Math.PI / 2, 0);
    leaf.castShadow = true;
    decor.add(leaf);
  }
}

function chair(solids, mats, cx, cz, yaw) {
  const g = new THREE.Group();
  const add = (x, y, z, sx, sy, sz) => {
    const m = new THREE.Mesh(new THREE.BoxGeometry(sx, sy, sz), mats.tableWood);
    m.position.set(x, y, z);
    m.castShadow = m.receiveShadow = true;
    g.add(m);
  };
  const s = 0.42, h = 0.45;
  add(0, h, 0, s, 0.03, s);
  for (const [x, z] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) add(x * (s / 2 - 0.02), h / 2, z * (s / 2 - 0.02), 0.03, h, 0.03);
  add(0, h + 0.25, s / 2 - 0.015, s, 0.3, 0.025);
  g.position.set(cx, 0, cz);
  g.rotation.y = yaw;
  g.updateMatrixWorld(true);
  g.children.slice().forEach((m) => {
    m.applyMatrix4(g.matrixWorld);
    solids.add(m);
  });
}

function makeMaterials() {
  const m = {};
  const floor = T.floorTiles([ROOM.w, ROOM.d]);
  m.floor = new THREE.MeshPhysicalMaterial({ ...floor, roughness: 1, clearcoat: 0.35, clearcoatRoughness: 0.14, normalScale: new THREE.Vector2(0.6, 0.6) });
  const wall = T.plaster([0.7, 0.7]);
  m.wall = new THREE.MeshStandardMaterial({ ...wall, color: 0xd8d2c6, roughness: 1 });
  m.ceiling = new THREE.MeshStandardMaterial({ color: 0xcfc9bd, roughness: 0.95 });
  m.whitePaint = new THREE.MeshStandardMaterial({ color: 0xe8e4da, roughness: 0.5 });
  m.plinth = new THREE.MeshStandardMaterial({ color: 0x2a1c14, roughness: 0.6 });
  const wood = T.wood([1.2, 0.35]);
  m.walnut = new THREE.MeshStandardMaterial({ ...wood, roughness: 1 });
  const tw = T.wood([1.5, 0.5]);
  m.tableWood = new THREE.MeshStandardMaterial({ ...tw, color: 0xc9a27a, roughness: 1 });
  const gr = T.granite([1.5, 1.5]);
  m.granite = new THREE.MeshPhysicalMaterial({ ...gr, roughness: 1, clearcoat: 0.5, clearcoatRoughness: 0.18 });
  const st = T.steel([2, 2]);
  m.steel = new THREE.MeshStandardMaterial({ ...st, metalness: 1, roughness: 1, color: 0xc8ccd0 });
  m.chrome = new THREE.MeshStandardMaterial({ color: 0xffffff, metalness: 1, roughness: 0.08 });
  m.steelBar = new THREE.MeshStandardMaterial({ color: 0xd0d0d0, metalness: 1, roughness: 0.25 });
  const sw = T.subway([3, 1]);
  m.subway = new THREE.MeshPhysicalMaterial({ ...sw, roughness: 1, clearcoat: 1, clearcoatRoughness: 0.05 });
  m.dark = new THREE.MeshStandardMaterial({ color: 0x050403, roughness: 1 });
  m.ovenGlass = new THREE.MeshPhysicalMaterial({ color: 0x050505, roughness: 0.05, metalness: 0.2, clearcoat: 1 });
  m.clock = new THREE.MeshBasicMaterial({ color: 0x33ff88 });
  m.led = new THREE.MeshBasicMaterial({ color: 0xffd9a0 });
  m.glass = new THREE.MeshPhysicalMaterial({ color: 0x223044, transparent: true, opacity: 0.25, roughness: 0.02, metalness: 0, depthWrite: false });
  m.nightSky = new THREE.MeshBasicMaterial({ color: 0x0b1530 });
  m.hallWalls = new THREE.MeshStandardMaterial({ ...T.plaster([0.7, 0.7]), color: 0xd9c7a8, roughness: 1 });
  const wf = T.wood([2, 2]);
  m.woodFloor = new THREE.MeshStandardMaterial({ ...wf, color: 0xb08a60, roughness: 1 });
  const rg = T.rug([1.2, 1.2]);
  m.rug = new THREE.MeshStandardMaterial({ ...rg, roughness: 1 });
  m.fridgeInside = new THREE.MeshStandardMaterial({ color: 0xf2f6fa, roughness: 0.4, emissive: 0x000000 });
  m.ceramic = new THREE.MeshPhysicalMaterial({ color: 0xece6dc, roughness: 0.2, clearcoat: 1, side: THREE.DoubleSide });
  m.glassJar = new THREE.MeshPhysicalMaterial({ color: 0xffffff, roughness: 0.05, transmission: 0.9, thickness: 0.01, transparent: true });
  m.nightlight = new THREE.MeshStandardMaterial({ color: 0xffd09a, emissive: 0xffa040, emissiveIntensity: 3 });
  m.lampOff = new THREE.MeshStandardMaterial({ color: 0xe8e4dc, roughness: 0.6 });
  m.lampOn = new THREE.MeshStandardMaterial({ color: 0xfff6e8, emissive: 0xfff0d8, emissiveIntensity: 4 });
  m.crumb = new THREE.MeshStandardMaterial({ color: 0xd8a860, roughness: 0.85 });
  m.kettle = new THREE.MeshPhysicalMaterial({ color: 0x1d1d20, roughness: 0.25, clearcoat: 1, clearcoatRoughness: 0.1 });
  const bottle = (c) => new THREE.MeshPhysicalMaterial({ color: c, roughness: 0.05, transmission: 0.6, thickness: 0.02, transparent: true, clearcoat: 1 });
  m.bottleGreen = bottle(0x3f5a1c);
  m.bottleAmber = bottle(0x8a4a12);
  m.bottleDark = bottle(0x2a0a12);
  m.boardWood = new THREE.MeshStandardMaterial({ ...T.wood([3, 1]), color: 0xe0b888, roughness: 1 });
  m.mug = new THREE.MeshPhysicalMaterial({ color: 0x2e5c7a, roughness: 0.3, clearcoat: 0.8, side: THREE.DoubleSide });
  m.towel = new THREE.MeshStandardMaterial({ ...T.plaid([6, 6]), color: 0xd06050, roughness: 1 });
  m.pot = new THREE.MeshStandardMaterial({ color: 0xb0643c, roughness: 0.8, side: THREE.DoubleSide });
  m.leaf = new THREE.MeshStandardMaterial({ color: 0x2f6a2a, roughness: 0.6 });
  m.water = new THREE.MeshPhysicalMaterial({ color: 0xffffff, roughness: 0.0, transmission: 1, thickness: 0.01, ior: 1.33, clearcoat: 1, transparent: true });
  return m;
}
