// Entry point: renderer, world, cockroach, camera, post-processing, loop.
import * as THREE from 'three';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { buildKitchen } from './kitchen.js';
import { buildRoach } from './roach.js';
import { Walker, FollowCamera } from './walker.js';
import { buildPost } from './post.js';
import { Input } from './input.js';
import { Game } from './game.js';

const params = new URLSearchParams(location.search);
if (params.has('test')) {
  // Reproducible runs for the automated checks (mulberry32).
  let seed = Number(params.get('seed') || 1) >>> 0;
  Math.random = () => { seed = (seed + 0x6d2b79f5) >>> 0; let t = seed; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const canvas = document.getElementById('view');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance', preserveDrawingBuffer: params.has('test') });
renderer.setPixelRatio(Math.min(devicePixelRatio, params.get('q') === 'low' ? 1 : 1.5));
renderer.setSize(innerWidth, innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFShadowMap;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 1.05;

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x05060a);
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
scene.environmentIntensity = 0.25;

const camera = new THREE.PerspectiveCamera(58, innerWidth / innerHeight, 0.004, 30);

const kitchen = buildKitchen(scene);
// The locomotion raycasts against the solids: their world matrices must be
// valid before the first render.
scene.updateMatrixWorld(true);
const roach = buildRoach();
scene.add(roach.root);
const walker = new Walker(kitchen.solids);
const follow = new FollowCamera(camera, walker);
const input = new Input(canvas);
const quality = params.get('q') || 'high';
const post = buildPost(renderer, scene, camera, quality);
const game = new Game({ scene, kitchen, walker, follow, roach, input, camera, renderer, canvas });
game.onQuality = (q) => {
  post.setQuality(q);
  renderer.setPixelRatio(Math.min(devicePixelRatio, q === 'low' ? 1 : 1.5));
  renderer.shadowMap.enabled = true;
  post.setSize(innerWidth, innerHeight);
};
game.onQuality(game.settings.quality);

addEventListener('resize', () => {
  camera.aspect = innerWidth / innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(innerWidth, innerHeight);
  post.setSize(innerWidth, innerHeight);
});

const basis = new THREE.Matrix4();
function syncRoach() {
  walker.basis(basis);
  roach.root.position.copy(walker.pos);
  roach.root.quaternion.setFromRotationMatrix(basis);
}

let last = performance.now();
let time = 0;
let fpsAcc = 0, fpsFrames = 0;
export function frame(dt, render = true) {
  time += dt;
  game.update(dt);
  syncRoach();
  roach.animate(dt, walker.travelled, game.sprinting);
  follow.update(dt);
  if (render) {
    post.setFocus(camera.position.distanceTo(walker.pos));
    post.render(time);
    game.afterRender();
  }
  input.endFrame();
}

function loop(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  fpsAcc += dt; fpsFrames++;
  if (fpsAcc > 1) { game.fps = fpsFrames / fpsAcc; fpsAcc = 0; fpsFrames = 0; }
  frame(dt);
  requestAnimationFrame(loop);
}

game.start();
syncRoach();
// Compile the shaders for every light state now, not the first time the
// human flips a switch (that would stutter).
for (const on of [true, false]) {
  kitchen.setCeiling(on);
  kitchen.setFridgeOpen(on ? 1 : 0);
  renderer.compile(scene, camera);
  post.render(0);
}
document.getElementById('loading').remove();
if (params.has('test')) {
  // Deterministic stepping for automated screenshots and checks.
  window.__game = { THREE, game, walker, follow, kitchen, camera, renderer, post, step(n, dt = 1 / 60) { for (let i = 0; i < n; i++) frame(dt); },
    // Logic only, no rendering (fast), for behaviour tests.
    sim(n, dt = 1 / 60) { scene.updateMatrixWorld(); for (let i = 0; i < n; i++) frame(dt, false); } };
  document.getElementById('title').hidden = true;
  game.begin();
} else {
  requestAnimationFrame(loop);
}
