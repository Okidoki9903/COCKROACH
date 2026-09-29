// The real player path (no test hooks): title, "Jouer", keys. Also reports
// render cost. node tests/play.mjs <out-dir>
import { open } from './serve.mjs';
import path from 'node:path';

const out = process.argv[2] || '/tmp/play';
const { page, logs, close } = await openReal();
async function openReal() {
  const o = await open('');                   // opens ?test; reload without it
  await o.page.goto(o.page.url().replace('?test', ''));
  await o.page.waitForSelector('#play');
  return o;
}
await page.waitForTimeout(3000);
await page.screenshot({ path: path.join(out, '1_titre.png') });
await page.click('#play');
await page.waitForTimeout(1500);
await page.keyboard.press('KeyE');            // leave the refuge
await page.keyboard.down('KeyW');
await page.waitForTimeout(6000);
await page.keyboard.up('KeyW');
await page.screenshot({ path: path.join(out, '2_en_jeu.png') });
await page.keyboard.press('Escape');
await page.waitForTimeout(800);
await page.screenshot({ path: path.join(out, '3_pause.png') });
const info = await page.evaluate(() => ({
  hud: !document.getElementById('hud').hidden,
  pause: !!document.getElementById('pause'),
  title: !document.getElementById('title').hidden,
}));
console.log(JSON.stringify(info));
console.log(logs.filter((l) => !l.includes('AudioContext') && !l.includes('pointer')).join('\n'));
await close();
