/* Run with Playwright installed (or NODE_PATH pointing at the bundled runtime).
 * Uses two isolated browser contexts and the real public signaling service.
 * Serves only docs/; never opens a user's browser profile.
 */
const { chromium } = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../docs');
const output = path.resolve(__dirname, '../artifacts/coop/browser');
fs.mkdirSync(output, { recursive: true });
const types = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html', '.pck': 'application/octet-stream', '.jpg': 'image/jpeg', '.png': 'image/png' };
const server = http.createServer((req, res) => {
  const target = path.resolve(root, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname));
  if (target !== root && !target.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
  const file = target === root ? path.join(root, 'index.html') : target;
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404).end(); return; }
  res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
  res.setHeader('Cache-Control', 'no-store');
  fs.createReadStream(file).pipe(res);
});
let browser;
const pages = [];
const errors = [];
const testSuper = process.env.COOP_TEST_SUPER === '1';
const click = (page, x, y) => page.mouse.click(x * 405 / 720, y * 720 / 1280);
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function waitFor(page, predicate, label, timeout = 30000) {
  try { await page.waitForFunction(predicate, null, { timeout }); }
  catch (error) {
    console.log(label, await page.evaluate(() => window.coopTest));
    throw error;
  }
}
async function phone(url) {
  const context = await browser.newContext({ viewport: { width: 405, height: 720 }, hasTouch: true });
  const page = await context.newPage();
  pages.push(page);
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', e => {
    if (e.type() === 'error' && /SCRIPT ERROR|Parse Error|Invalid/.test(e.text())) errors.push(e.text());
  });
  await page.addInitScript(() => {
    window.coopTest = { events: [], state: null, room: null, stopped: false };
    let bridge;
    Object.defineProperty(window, 'GregMutkiCoop', {
      get: () => bridge,
      set: value => {
        bridge = value;
        const originalPoll = value.poll;
        const originalSnapshot = value.snapshot;
        const originalClose = value.close;
        value.close = () => { window.coopTest.stopped = true; return originalClose(); };
        value.poll = () => {
          const raw = originalPoll();
          for (const event of JSON.parse(raw)) {
            if (event.type === 'room') window.coopTest.room = event.code;
            if (event.type === 'message' && event.data.type === 'snapshot') window.coopTest.state = event.data;
            else { window.coopTest.events.push(event); if (window.coopTest.events.length > 20) window.coopTest.events.shift(); }
          }
          return raw;
        };
        value.snapshot = raw => { window.coopTest.state = JSON.parse(raw); return originalSnapshot(raw); };
      }
    });
  });
  await page.goto(url, { waitUntil: 'load', timeout: 60000 });
  await page.waitForFunction(() => !document.getElementById('status'), null, { timeout: 60000 });
  await delay(3000);
  return page;
}
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}/`;
  browser = await chromium.launch({ headless: true, args: ['--autoplay-policy=no-user-gesture-required'], ...(process.env.COOP_BROWSER ? { executablePath: process.env.COOP_BROWSER } : {}) });
  const host = await phone(base);
  await host.screenshot({ path: path.join(output, '01-modes.png') });
  await click(host, 360, 1058);
  await delay(250);
  await click(host, 360, 726);
  await waitFor(host, () => !!window.coopTest.room, 'create room');
  const code = await host.evaluate(() => window.coopTest.room);
  console.log('ROOM_READY', code);
  await host.screenshot({ path: path.join(output, '02-room.png') });
  await click(host, 360, 765); // Open the original full-screen character artwork.
  await delay(250);
  await click(host, 180, 1120); // Greg's original portrait/name hit area.
  const guest = await phone(base + '#room=' + code);
  await click(guest, 360, 930);
  await waitFor(guest, () => window.coopTest.events.some(e => e.type === 'connected'), 'join room');
  await delay(400);
  await click(guest, 540, 1120); // Mutki on the unchanged artwork.
  await delay(200);
  await host.screenshot({ path: path.join(output, '02-selection-p1-p2.png') });
  await waitFor(host, () => window.coopTest.state?.phase === 'intro', 'shared intro host');
  await waitFor(guest, () => window.coopTest.state?.phase === 'intro', 'shared intro guest');
  const introStarted = Date.now();
  await host.screenshot({ path: path.join(output, '03-intro.png') });
  // Old skip coordinates and Escape must not bypass the supplied video.
  await click(host, 360, 1217);
  await guest.keyboard.press('Escape');
  await delay(400);
  assert.equal(await host.evaluate(() => window.coopTest.state.phase), 'intro');
  assert.equal(await host.evaluate(() => window.coopTest.state.enemies.length), 0);
  assert.equal(await host.evaluate(() => window.coopTest.state.elapsed), 0);
  await waitFor(host, () => window.coopTest.state?.phase === 'combat', 'video ends in shared combat', 45000);
  await waitFor(guest, () => window.coopTest.state?.phase === 'combat', 'guest follows video into combat');
  assert(Date.now() - introStarted >= 14000, 'the complete intro plays before combat');
  console.log('CONNECTED: real WebRTC, distinct heroes, full intro video, automatic shared combat');
  await delay(600);
  await guest.evaluate(() => {
    Object.defineProperty(document, 'hidden', { value: true, configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await waitFor(host, () => window.coopTest.state?.paused, 'background pauses host');
  const pausedState = await host.evaluate(() => window.coopTest.state);
  await delay(600);
  assert.equal(await host.evaluate(() => window.coopTest.state.elapsed), pausedState.elapsed);
  await guest.evaluate(() => {
    delete document.hidden;
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await waitFor(host, () => window.coopTest.state && !window.coopTest.state.paused, 'return resumes host');
  await host.screenshot({ path: path.join(output, '04-host-combat.png') });
  await guest.screenshot({ path: path.join(output, '05-guest-combat.png') });
  const deadline = Date.now() + 90000;
  let checkedRounds = 0;
  let previousRound = 0;
  let superTested = false;
  while (Date.now() < deadline) {
    const state = await host.evaluate(() => window.coopTest.state);
    if (state.phase === 'combat' && !state.paused) {
      if (testSuper && !superTested && state.charges.greg >= 100 && state.fighters.greg.state === 'idle' && state.enemies.some(e => e.state !== 'dead' && Math.sign(e.x - state.fighters.greg.x) === state.fighters.greg.direction)) {
        await click(host, 204, 1184);
        await waitFor(host, () => window.coopTest.state?.phase === 'super_video', 'super clip starts');
        await waitFor(guest, () => window.coopTest.state?.phase === 'super_video', 'both phones show super clip');
        const beforeVideo = await host.evaluate(() => window.coopTest.state);
        await delay(600);
        await host.screenshot({ path: path.join(output, 'super-video-host.png') });
        await guest.screenshot({ path: path.join(output, 'super-video-guest.png') });
        await guest.evaluate(() => {
          Object.defineProperty(document, 'hidden', { value: true, configurable: true });
          document.dispatchEvent(new Event('visibilitychange'));
        });
        await waitFor(host, () => window.coopTest.state?.paused, 'pause during super video');
        await delay(400);
        await guest.evaluate(() => {
          delete document.hidden;
          document.dispatchEvent(new Event('visibilitychange'));
        });
        await waitFor(host, () => !window.coopTest.state?.paused, 'resume video without resuming battle');
        await click(host, 610, 1227); // Tapping the old skip location must do nothing.
        await delay(400);
        const waitingVideo = await host.evaluate(() => window.coopTest.state);
        assert.equal(waitingVideo.phase, 'super_video');
        assert.deepEqual(waitingVideo.enemies, beforeVideo.enemies);
        assert.equal(waitingVideo.elapsed, beforeVideo.elapsed);
        await waitFor(host, () => window.coopTest.state?.phase === 'super_attack', 'video leads into arena super');
        await waitFor(host, () => window.coopTest.state?.assist?.active, 'supplied Mutki wave animation');
        await waitFor(guest, () => window.coopTest.state?.assist?.active, 'wave replicated to guest');
        await host.screenshot({ path: path.join(output, 'super-arena-animation.png') });
        await waitFor(host, () => window.coopTest.state?.assist?.frame >= 24, 'purple wave release');
        await host.screenshot({ path: path.join(output, 'super-arena-wave-host.png') });
        await guest.screenshot({ path: path.join(output, 'super-arena-wave-guest.png') });
        await waitFor(host, () => window.coopTest.state?.phase !== 'super_attack', 'arena super finishes');
        superTested = true;
        console.log('GREG_SUPER_BROWSER_PASS: actual-clip/two-phones/network-pause/no-skip/natural-completion/arena-animation');
        continue;
      }
      for (const [id, page] of [['greg', host], ['mutki', guest]]) {
        const fighter = state.fighters[id];
        const enemy = state.enemies.filter(e => e.state !== 'dead').sort((a, b) => Math.abs(a.x - fighter.x) - Math.abs(b.x - fighter.x))[0];
        if (fighter.state === 'idle' && enemy && Math.abs(enemy.x - fighter.x) < 235) {
          if (testSuper && id === 'greg') {
            await page.keyboard.press(enemy.x < fighter.x ? 'ArrowLeft' : 'ArrowRight');
            await page.keyboard.press('1');
          } else await click(page, enemy.x < fighter.x ? 140 : 580, 980);
        }
      }
    } else if (state.phase === 'round' && state.round !== previousRound) {
      previousRound = state.round;
      await waitFor(guest, () => window.coopTest.state?.phase === 'round', 'round replication');
      assert.deepEqual(await guest.evaluate(() => window.coopTest.state.totals), state.totals);
      checkedRounds++;
      console.log('ROUND', state.round, state.totals);
      await host.screenshot({ path: path.join(output, `round-${state.round}.png`) });
      await click(host, 360, 1040);
      await delay(250);
      assert.equal(await host.evaluate(() => window.coopTest.state.phase), 'round');
      await click(guest, 360, 1040);
    } else if (state.phase === 'exit') break;
    else if (state.phase === 'failed') throw new Error('Mission failed during browser combat');
    await delay(50);
  }
  assert.equal(checkedRounds, 3);
  if (testSuper) assert.equal(superTested, true, 'charged Greg super was exercised');
  // Closing a phone must stop its teammate instead of continuing alone.
  await guest.close();
  await waitFor(host, () => window.coopTest.stopped || window.coopTest.events.some(e => e.type === 'closed'), 'disconnect');
  await delay(200);
  await host.screenshot({ path: path.join(output, 'disconnect.png') });
  assert.deepEqual(errors, []);
  console.log('COOP_BROWSER_PASS: real-signaling/real-WebRTC/two-phones/3-rounds/equal-scores/disconnect');
})().catch(async error => {
  console.error(error);
  for (let i = 0; i < pages.length; i++) {
    if (!pages[i].isClosed()) {
      await pages[i].screenshot({ path: path.join(output, `failure-${i}.png`) }).catch(() => {});
      console.log('PHONE', i, await pages[i].evaluate(() => window.coopTest).catch(() => null));
    }
  }
  process.exitCode = 1;
}).finally(async () => {
  await browser?.close();
  server.close();
});
