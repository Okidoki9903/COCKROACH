// Screenshots through headless Chromium (software WebGL).
// node tests/shot.mjs <out-dir> [script.json]
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
let chromium;
try { ({ chromium } = require('playwright')); } catch { ({ chromium } = require('/opt/node22/lib/node_modules/playwright')); }
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const p = path.join(root, decodeURIComponent(req.url.split('?')[0]));
  const f = fs.existsSync(p) && fs.statSync(p).isDirectory() ? path.join(p, 'index.html') : p;
  if (!fs.existsSync(f)) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(res);
}).listen(0);
const port = server.address().port;

const out = process.argv[2] || '/tmp/shots';
fs.mkdirSync(out, { recursive: true });
const shots = JSON.parse(fs.readFileSync(process.argv[3], 'utf8'));
const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const logs = [];
page.on('console', (m) => logs.push(m.type() + ': ' + m.text()));
page.on('pageerror', (e) => logs.push('PAGEERROR: ' + e.message));
await page.goto(`http://localhost:${port}/index.html?test${shots.query || ''}`);
await page.waitForFunction(() => window.__game, null, { timeout: 120000 }).catch(() => {});
for (const s of shots.steps) {
  if (s.eval) await page.evaluate(s.eval);
  if (s.step) await page.evaluate((n) => window.__game.step(n), s.step);
  if (s.shot) await page.screenshot({ path: path.join(out, s.shot + '.png') });
  if (s.log) console.log(s.shot || '', await page.evaluate(s.log));
}
console.log(logs.filter((l) => !l.includes('GPU stall')).slice(0, 30).join('\n'));
await browser.close();
server.close();
