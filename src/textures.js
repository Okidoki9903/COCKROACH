// Procedural PBR textures (colour, roughness, normal), drawn on canvases at
// load time: no downloaded image, no licence to track.
import * as THREE from 'three';

// --- noise -------------------------------------------------------------------

function hash(x, y, seed) {
  let h = (x * 374761393 + y * 668265263 + seed * 982451653) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967295;
}

function smooth(t) { return t * t * (3 - 2 * t); }

// Tileable value noise, period p cells.
function vnoise(x, y, p, seed) {
  const xi = Math.floor(x), yi = Math.floor(y);
  const xf = smooth(x - xi), yf = smooth(y - yi);
  const m = (v) => ((v % p) + p) % p;
  const a = hash(m(xi), m(yi), seed), b = hash(m(xi + 1), m(yi), seed);
  const c = hash(m(xi), m(yi + 1), seed), d = hash(m(xi + 1), m(yi + 1), seed);
  return a + (b - a) * xf + (c - a) * yf + (a - b - c + d) * xf * yf;
}

// Fractal noise in [0,1], tileable over the unit square (u,v in [0,1)).
export function fbm(u, v, base, octaves, seed) {
  let sum = 0, amp = 0.5, norm = 0, f = base;
  for (let o = 0; o < octaves; o++) {
    sum += amp * vnoise(u * f, v * f, f, seed + o * 17);
    norm += amp;
    amp *= 0.5;
    f *= 2;
  }
  return sum / norm;
}

// --- canvas helpers ----------------------------------------------------------------

function canvas(size) {
  const c = document.createElement('canvas');
  c.width = c.height = size;
  return c;
}

// Fills colour, roughness and height arrays with fn(u, v) -> [r,g,b, rough, height].
function paint(size, fn) {
  const col = canvas(size), rough = canvas(size);
  const cc = col.getContext('2d'), rc = rough.getContext('2d');
  const ci = cc.createImageData(size, size), ri = rc.createImageData(size, size);
  const height = new Float32Array(size * size);
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const o = fn(x / size, y / size);
      const i = (y * size + x) * 4;
      ci.data[i] = o[0]; ci.data[i + 1] = o[1]; ci.data[i + 2] = o[2]; ci.data[i + 3] = 255;
      const r = Math.max(0, Math.min(255, o[3] * 255));
      ri.data[i] = ri.data[i + 1] = ri.data[i + 2] = r; ri.data[i + 3] = 255;
      height[y * size + x] = o[4];
    }
  }
  cc.putImageData(ci, 0, 0);
  rc.putImageData(ri, 0, 0);
  return { col, rough, height, size };
}

// Tangent-space normal map from a tileable height field.
function normalFrom(height, size, strength) {
  const c = canvas(size);
  const ctx = c.getContext('2d');
  const img = ctx.createImageData(size, size);
  const h = (x, y) => height[((y + size) % size) * size + ((x + size) % size)];
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = (h(x + 1, y) - h(x - 1, y)) * strength;
      const dy = (h(x, y + 1) - h(x, y - 1)) * strength;
      const l = Math.hypot(dx, dy, 1);
      const i = (y * size + x) * 4;
      img.data[i] = (-dx / l * 0.5 + 0.5) * 255;
      img.data[i + 1] = (dy / l * 0.5 + 0.5) * 255;
      img.data[i + 2] = (1 / l * 0.5 + 0.5) * 255;
      img.data[i + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return c;
}

function tex(c, repeat, srgb) {
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeat[0], repeat[1]);
  t.anisotropy = 8;
  if (srgb) t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

// Builds {map, roughnessMap, normalMap} with the given repeat.
function pbr(p, repeat, normalStrength) {
  return {
    map: tex(p.col, repeat, true),
    roughnessMap: tex(p.rough, repeat, false),
    normalMap: tex(normalFrom(p.height, p.size, normalStrength), repeat, false),
  };
}

const cache = {};

// --- materials' textures -----------------------------------------------------------

// Large glazed floor tiles, 2 x 2 tiles per texture. Warm grey, glossy
// glaze with faint wear, rough recessed grout.
export function floorTiles(repeat) {
  if (!cache.floor) {
    cache.floor = paint(1024, (u, v) => {
      const tu = (u * 2) % 1, tv = (v * 2) % 1;
      const ti = Math.floor(u * 2) + Math.floor(v * 2) * 2;
      const g = 0.006;
      const grout = tu < g || tu > 1 - g || tv < g || tv > 1 - g;
      const n = fbm(u, v, 6, 5, 3);
      const fine = fbm(u, v, 64, 3, 9);
      if (grout) {
        const k = 70 + n * 30;
        return [k, k * 0.95, k * 0.9, 0.9, 0.0];
      }
      const tone = 0.92 + hash(ti, 1, 7) * 0.12;
      const k = (104 + n * 34 + fine * 10) * tone;
      const wear = fbm(u, v, 3, 3, 21);
      const rough = 0.14 + fine * 0.1 + Math.max(0, wear - 0.55) * 0.6;
      return [k * 1.02, k * 0.98, k * 0.92, rough, 1.0 - fine * 0.03];
    });
  }
  return pbr(cache.floor, repeat, 6);
}

// Walnut veneer for cabinet fronts.
export function wood(repeat) {
  if (!cache.wood) {
    cache.wood = paint(512, (u, v) => {
      const warp = fbm(u, v, 3, 3, 5) * 6;
      const grain = Math.sin((u * 40 + warp) * Math.PI) * 0.5 + 0.5;
      const n = fbm(u, v * 0.15, 24, 4, 11);
      const k = 0.55 + grain * 0.2 + n * 0.25;
      return [110 * k, 70 * k, 42 * k, 0.45 + n * 0.2, grain * 0.4 + n * 0.6];
    });
  }
  return pbr(cache.wood, repeat, 1.5);
}

// Painted plaster wall.
export function plaster(repeat) {
  if (!cache.plaster) {
    cache.plaster = paint(512, (u, v) => {
      const n = fbm(u, v, 8, 5, 31);
      const k = 205 + n * 25;
      return [k, k * 0.97, k * 0.9, 0.85, n];
    });
  }
  return pbr(cache.plaster, repeat, 2);
}

// Glossy subway tiles (backsplash): 4 x 8 bricks per texture.
export function subway(repeat) {
  if (!cache.subway) {
    cache.subway = paint(512, (u, v) => {
      const row = Math.floor(v * 8);
      const uu = (u * 4 + (row % 2) * 0.5) % 1;
      const vv = (v * 8) % 1;
      const g = 0.03;
      const grout = uu < g * 0.5 || uu > 1 - g * 0.5 || vv < g || vv > 1 - g;
      const n = fbm(u, v, 16, 3, 41);
      if (grout) return [150, 148, 140, 0.9, 0];
      const edge = Math.min(uu, 1 - uu, vv * 0.5, (1 - vv) * 0.5);
      const bevel = Math.min(1, edge / 0.04);
      const k = 222 + n * 18;
      return [k * 0.98, k, k * 0.98, 0.08 + n * 0.08, 0.3 + bevel * 0.7];
    });
  }
  return pbr(cache.subway, repeat, 4);
}

// Dark speckled granite for the worktop.
export function granite(repeat) {
  if (!cache.granite) {
    cache.granite = paint(512, (u, v) => {
      const n = fbm(u, v, 32, 3, 51);
      const s = hash(Math.floor(u * 512), Math.floor(v * 512), 5);
      let k = 30 + n * 25;
      if (s > 0.993) k = 120;
      else if (s > 0.95) k = 62;
      return [k, k * 0.96, k * 0.92, 0.32 + n * 0.2, n];
    });
  }
  return pbr(cache.granite, repeat, 1);
}

// Brushed steel (fridge, sink).
export function steel(repeat) {
  if (!cache.steel) {
    cache.steel = paint(256, (u, v) => {
      const s = fbm(u * 0.02, v, 128, 2, 61);
      const k = 170 + s * 40;
      return [k, k, k * 1.02, 0.28 + s * 0.12, s];
    });
  }
  return pbr(cache.steel, repeat, 0.5);
}

// Pyjama plaid for the human's trousers.
export function plaid(repeat) {
  if (!cache.plaid) {
    cache.plaid = paint(256, (u, v) => {
      const band = (t, w) => (Math.abs(((t % 0.25) + 0.25) % 0.25 - 0.125) < w ? 1 : 0);
      const a = band(u, 0.03) + band(v, 0.03);
      const b = band(u + 0.06, 0.008) + band(v + 0.06, 0.008);
      const n = fbm(u, v, 64, 2, 71);
      let c = [52, 58, 72];
      if (a === 1) c = [30, 34, 44];
      if (a === 2) c = [18, 20, 26];
      if (b) c = [150, 140, 128];
      const k = 0.9 + n * 0.2;
      return [c[0] * k, c[1] * k, c[2] * k, 0.95, n];
    });
  }
  return pbr(cache.plaid, repeat, 1);
}

// Woven rug: dense two-tone loops.
export function rug(repeat) {
  if (!cache.rug) {
    cache.rug = paint(512, (u, v) => {
      const loop = Math.sin(u * 512 * Math.PI) * Math.sin(v * 512 * Math.PI);
      const stripes = Math.floor(v * 16) % 2;
      const n = fbm(u, v, 32, 3, 81);
      const k = stripes ? 0.35 : 0.55;
      const c = (60 + n * 50) * (0.75 + loop * 0.25) * k * 2;
      return [c * 0.8, c * 0.85, c, 1.0, loop * 0.5 + n * 0.5];
    });
  }
  return pbr(cache.rug, repeat, 3);
}
