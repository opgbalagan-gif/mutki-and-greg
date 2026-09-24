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
  if (file.endsWith('index.html')) {
    const html = fs.readFileSync(file, 'utf8');
    assert(html.includes('"args":[]'));
    res.end(html.replace('"args":[]', '"args":["--","--coop-test"]'));
  } else fs.createReadStream(file).pipe(res);
});
let browser;
const pages = [];
const errors = [];
const testSuper = process.env.COOP_TEST_SUPER !== '0';
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
  page.on('requestfailed', request => console.log('REQUEST_FAILED', new URL(request.url()).hostname, request.failure()?.errorText));
  page.on('console', e => {
    if (e.type() === 'error' && /SCRIPT ERROR|Parse Error|Invalid/.test(e.text())) errors.push(e.text());
  });
  await page.addInitScript(() => {
    window.coopTest = { events: [], state: null, localProgress: null, room: null, stopped: false };
    let bridge;
    Object.defineProperty(window, 'GregMutkiCoop', {
      get: () => bridge,
      set: value => {
        bridge = value;
        value.testState = raw => { window.coopTest.arena = JSON.parse(raw); };
        const originalPoll = value.poll;
        const originalSnapshot = value.snapshot;
        const originalSend = value.send;
        value.send = raw => {
          const message = JSON.parse(raw);
          if (message.type === 'progress') window.coopTest.localProgress = message.value;
          return originalSend(raw);
        };
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
  await click(host, 360, 1217);
  await guest.keyboard.press('Escape');
  await delay(400);
  assert.equal(await host.evaluate(() => window.coopTest.state.phase), 'intro');
  await waitFor(host, () => window.coopTest.state?.phase === 'combat', 'intro host', 45000);
  await waitFor(guest, () => window.coopTest.state?.phase === 'combat', 'intro guest');
  assert(Date.now() - introStarted >= 14000, 'the complete common intro plays');
  const initial = await host.evaluate(() => window.coopTest.state);
  assert.equal(initial.mode, 'separate-arenas-v2');
  assert(!('fighters' in initial) && !('enemies' in initial), 'the session does not replicate combat actors');
  console.log('CONNECTED: real WebRTC, shared intro, two separate arenas');
  await delay(600);
  await guest.evaluate(() => {
    Object.defineProperty(document, 'hidden', { value: true, configurable: true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await waitFor(host, () => window.coopTest.state?.paused, 'background pauses session');
  const pausedElapsed = await host.evaluate(() => window.coopTest.state.progress.greg.elapsed);
  await delay(600);
  assert.equal(await host.evaluate(() => window.coopTest.state.progress.greg.elapsed), pausedElapsed);
  await guest.evaluate(() => {
    delete document.hidden;
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await waitFor(host, () => !window.coopTest.state?.paused, 'resume session');
  await host.screenshot({ path: path.join(output, '04-host-own-arena.png') });
  await guest.screenshot({ path: path.join(output, '05-guest-own-arena.png') });
  const deadline = Date.now() + 180000;
  let checkedRounds = 0;
  let previousRound = 0;
  let superStarted = false;
  let superFinished = false;
  let superGuestElapsed = null;
  let guestContinuedDuringSuper = false;
  let sawFirstFinisher = false;
  let tick = 0;
  while (Date.now() < deadline) {
    const state = await host.evaluate(() => window.coopTest.state);
    if (state.phase === 'combat' && !state.paused) {
      const greg = state.progress.greg;
      const mutki = state.progress.mutki;
      if (greg.status !== mutki.status) sawFirstFinisher = true;
      const hostArena = await host.evaluate(() => window.coopTest.arena);
      if (testSuper && !superStarted && greg.charge >= 100 && hostArena.state === 'idle') await click(host, 204, 1184);
      if (greg.activity === 'super_video' && !superStarted) {
        superStarted = true;
        superGuestElapsed = mutki.elapsed;
        await host.screenshot({ path: path.join(output, 'super-local-video.png') });
        await guest.screenshot({ path: path.join(output, 'super-other-arena.png') });
        console.log('LOCAL_SUPER_STARTED');
      }
      if (superStarted && ['super_video', 'super_attack'].includes(greg.activity)) {
        if (mutki.elapsed > superGuestElapsed + 0.3) guestContinuedDuringSuper = true;
        assert(!['super_video', 'super_attack'].includes(mutki.activity), 'the other phone keeps its own arena');
      }
      if (superStarted && !['super_video', 'super_attack'].includes(greg.activity)) superFinished = true;
      // Observe only this phone's arena, then use ordinary player inputs.
      for (const [id, page] of [['greg', host], ['mutki', guest]]) {
        const progress = state.progress[id];
        const arena = await page.evaluate(() => window.coopTest.arena);
        const target = arena.enemies.filter(enemy => enemy.hp > 0).sort((a, b) => Math.abs(a.x - arena.x) - Math.abs(b.x - arena.x))[0];
        if (progress.status === 'fighting' && arena.local_phase === 'combat' && arena.state === 'idle' && target && Math.abs(target.x - arena.x) < 235) {
          await page.keyboard.press(target.x < arena.x ? 'ArrowLeft' : 'ArrowRight');
          await page.keyboard.press(id === 'greg' && testSuper && !superStarted ? '1' : 'Space');
        }
      }
      tick++;
    } else if (state.phase === 'round' && state.round !== previousRound) {
      previousRound = state.round;
      await waitFor(guest, () => window.coopTest.state?.phase === 'round', 'round synchronization');
      assert.deepEqual(await guest.evaluate(() => window.coopTest.state.totals), state.totals);
      assert(Object.values(state.round_states).every(value => value !== 'fighting'));
      checkedRounds++;
      console.log('ROUND', state.round, JSON.stringify(state.totals), JSON.stringify(state.round_states));
      await host.screenshot({ path: path.join(output, `round-${state.round}.png`) });
      await click(host, 360, 1040);
      await delay(250);
      assert.equal(await host.evaluate(() => window.coopTest.state.phase), 'round', 'both must confirm the results');
      await click(guest, 360, 1040);
    } else if (state.phase === 'exit') break;
    else if (state.phase === 'failed') throw new Error('Both heroes fell during automated browser play');
    await delay(80);
  }
  assert.equal(checkedRounds, 3);
  assert(sawFirstFinisher, 'one arena finishes and waits for the other');
  if (testSuper) {
    assert(superStarted && superFinished, 'the local video and wave complete');
    assert(guestContinuedDuringSuper, 'the second arena keeps progressing during the first phone super');
  }
  const finished = await host.evaluate(() => window.coopTest.state);
  assert.equal(finished.progress.greg.defeated, 18);
  assert.equal(finished.progress.mutki.defeated, 18);
  // Inspect the common exit, then finish the existing closing story on both phones.
  await click(host, 360, 935);
  await waitFor(host, () => window.coopTest.state?.phase === 'outro', 'common ending');
  for (let step = 0; step < 8; step++) {
    if (await host.evaluate(() => window.coopTest.state?.phase === 'complete')) break;
    await click(host, 530, 1210);
    await click(guest, 530, 1210);
    await delay(450);
  }
  await waitFor(host, () => window.coopTest.state?.phase === 'complete', 'final winner');
  await waitFor(guest, () => window.coopTest.state?.phase === 'complete', 'same final winner');
  assert.deepEqual(await guest.evaluate(() => window.coopTest.state.totals), finished.totals);
  await delay(1700); // Let the displayed score counters reach their final totals.
  await host.screenshot({ path: path.join(output, '06-final-host.png') });
  await guest.screenshot({ path: path.join(output, '07-final-guest.png') });
  await click(host, 360, 1040);
  await click(guest, 360, 1040);
  await waitFor(host, () => window.coopTest.state?.phase === 'intro', 'replay in the same room');
  assert.deepEqual(await host.evaluate(() => window.coopTest.state.totals), { greg: 0, mutki: 0 });
  await guest.close();
  await waitFor(host, () => window.coopTest.stopped || window.coopTest.events.some(e => e.type === 'closed'), 'disconnect');
  assert.deepEqual(errors, []);
  console.log('COOP_BROWSER_PASS: real-signaling/WebRTC/separate-arenas/own-super/18-enemies-each/3-rounds/shared-results/final/replay/disconnect');
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
