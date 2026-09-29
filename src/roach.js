// The cockroach: a 3.5 cm body built from shaped primitives, six jointed
// legs walking in a tripod gait (like a real cockroach), and two long
// antennae that sway. Local frame: +Z forward (head), +Y up (off the
// surface), +X left.
import * as THREE from 'three';

const UP = new THREE.Vector3(0, 1, 0);

export function buildRoach() {
  const root = new THREE.Group();
  const body = new THREE.Group();
  root.add(body);

  const chitin = new THREE.MeshPhysicalMaterial({
    color: 0x4a1b0a, roughness: 0.45, metalness: 0.0, clearcoat: 0.35, clearcoatRoughness: 0.32,
    sheen: 0.3, sheenColor: 0x9a4a20,
  });
  const chitinLight = chitin.clone();
  chitinLight.color = new THREE.Color(0x9a6238);
  const dark = new THREE.MeshPhysicalMaterial({ color: 0x2a120a, roughness: 0.4, clearcoat: 0.8, clearcoatRoughness: 0.2 });
  const legMat = new THREE.MeshStandardMaterial({ color: 0x4a2412, roughness: 0.5 });

  const ell = (rx, ry, rz, mat, x, y, z, seg = 32) => {
    const m = new THREE.Mesh(new THREE.SphereGeometry(1, seg, seg / 2), mat);
    m.scale.set(rx, ry, rz);
    m.position.set(x, y, z);
    m.castShadow = true;
    body.add(m);
    return m;
  };
  // Abdomen under the wings, the two tegmina (wings) meeting on the back,
  // the pronotum shield with its pale rim, and the head tucked below it.
  // One flat oval for the folded wings (widest behind the middle), with a
  // fine seam where they overlap.
  ell(0.0058, 0.0022, 0.0135, dark, 0, 0.0026, -0.004);
  const wings = ell(0.0068, 0.0021, 0.0148, chitin, 0, 0.0034, -0.0042, 48);
  wings.scale.x = 0.0068;
  const seam = new THREE.Mesh(new THREE.BoxGeometry(0.00025, 0.0002, 0.024), dark);
  seam.position.set(0.0004, 0.0055, -0.0055);
  seam.rotation.y = 0.03;
  body.add(seam);
  // Pronotum: a wide shield hiding the head, with a pale translucent rim.
  ell(0.0071, 0.0016, 0.0056, chitinLight, 0, 0.0032, 0.0098);
  ell(0.0062, 0.0018, 0.0049, chitin, 0, 0.0037, 0.0095);
  ell(0.0024, 0.0021, 0.0022, dark, 0, 0.0022, 0.0148, 24);
  for (const s of [-1, 1]) {
    const cercus = new THREE.Mesh(new THREE.ConeGeometry(0.0006, 0.004, 8), dark);
    cercus.position.set(s * 0.0022, 0.003, -0.0185);
    cercus.rotation.set(-Math.PI / 2 - 0.2, 0, s * 0.35);
    body.add(cercus);
  }

  // --- legs (2-bone IK toward animated foot targets) -------------------------------
  const seg = new THREE.CylinderGeometry(0.00062, 0.00035, 1, 6);
  seg.translate(0, 0.5, 0);
  const legs = [];

  const hips = [0.0072, 0.0015, -0.0045];
  // Rest feet [side, forward]: front legs reach ahead, middle and hind
  // legs splay backward like a real cockroach.
  const reach = [[0.0105, 0.0135], [0.0135, -0.0035], [0.0125, -0.0175]];
  for (let i = 0; i < 3; i++) {
    for (const side of [1, -1]) {
      const femur = new THREE.Mesh(seg, legMat);
      const tibia = new THREE.Mesh(seg, legMat);

      femur.castShadow = tibia.castShadow = true;
      body.add(femur, tibia);
      legs.push({
        femur, tibia,
        hip: new THREE.Vector3(side * 0.0033, 0.0022, hips[i]),
        rest: new THREE.Vector3(side * reach[i][0], 0, reach[i][1]),
        // Tripod: (L1, R2, L3) against (R1, L2, R3).
        phase: ((i % 2 === 0) === (side === 1)) ? 0 : Math.PI,
        side,
        len: i === 2 ? 0.0115 : i === 1 ? 0.0095 : 0.0085,
      });
    }
  }

  // --- antennae ----------------------------------------------------------------------
  const antMat = new THREE.MeshStandardMaterial({ color: 0x3a1a0c, roughness: 0.6 });
  const antennae = [-1, 1].map((side) => {
    const mesh = new THREE.Mesh(new THREE.BufferGeometry(), antMat);
    body.add(mesh);
    return { mesh, side };
  });

  const tmpA = new THREE.Vector3(), tmpB = new THREE.Vector3(), knee = new THREE.Vector3();
  const q = new THREE.Quaternion();

  function place(mesh, a, b) {
    tmpA.subVectors(b, a);
    const l = tmpA.length();
    mesh.position.copy(a);
    q.setFromUnitVectors(UP, tmpA.divideScalar(l || 1));
    mesh.quaternion.copy(q);
    mesh.scale.set(1, l, 1);
  }

  let gait = 0;
  let time = 0;
  let antFrame = 0;

  return {
    root,
    // travelled: metres moved this frame; speed: m/s (for body bob).
    animate(dt, travelled, running) {
      time += dt;
      gait += travelled / 0.011 * Math.PI;
      const moving = travelled > 1e-5;
      for (const L of legs) {
        const ph = gait + L.phase;
        const swing = moving ? Math.sin(ph) : 0;
        const lift = moving ? Math.max(0, Math.cos(ph)) : 0;
        const foot = tmpB.copy(L.rest);
        foot.z += swing * 0.0045;
        foot.y = lift * 0.003;
        // Knee: up and out from the hip-foot midpoint.
        const d = tmpA.subVectors(foot, L.hip);
        const dist = d.length();
        const h = Math.sqrt(Math.max(0, L.len * L.len - (dist / 2) * (dist / 2)));
        knee.addVectors(L.hip, foot).multiplyScalar(0.5);
        knee.y += h * 0.5;
        knee.x += L.side * h * 0.8;
        place(L.femur, L.hip, knee);
        place(L.tibia, knee, foot.clone());
      }
      body.position.y = moving ? Math.abs(Math.sin(gait)) * 0.0003 : 0;
      body.rotation.z = moving ? Math.sin(gait) * 0.02 : 0;
      // Antennae: long, curving outward and back over the body, sweeping.
      if (antFrame++ % 2 === 0) {
        for (const A of antennae) {
          const pts = [];
          const sweep = Math.sin(time * (running ? 9 : 3) + A.side) * 0.35 + (moving ? 0 : Math.sin(time * 1.3 + A.side * 2) * 0.25);
          for (let k = 0; k <= 8; k++) {
            const t = k / 8;
            const a = A.side * (0.35 + t * 0.5 + sweep * t);
            const r = 0.034 * t;
            pts.push(new THREE.Vector3(Math.sin(a) * r * 0.9, 0.004 + Math.sin(t * Math.PI) * 0.006 + t * 0.002, 0.017 + Math.cos(a) * r));
          }
          A.mesh.geometry.dispose();
          A.mesh.geometry = new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 16, 0.00022, 4, false);
        }
      }
    },
  };
}
