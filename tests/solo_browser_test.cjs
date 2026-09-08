/* Exercise the shipped browser package with iPhone display settings.
 * Only the local test HTML receives --smoke-test; production HTML is unchanged.
 * Requires Web Audio so the full video can finish naturally.
 */
const { webkit, chromium, devices } = require('playwright');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../docs');
const output = path.resolve(__dirname, '../artifacts/greg_super_arena/browser');
fs.mkdirSync(output, { recursive: true });
const types = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.html': 'text/html', '.png': 'image/png', '.jpg': 'image/jpeg' };
const server = http.createServer((req, res) => {
  const requested = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  const file = path.resolve(root, '.' + (requested === '/' ? '/index.html' : requested));
  if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) { res.writeHead(404).end(); return; }
  res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
  res.setHeader('Cache-Control', 'no-store');
  if (file.endsWith('index.html')) {
    const html = fs.readFileSync(file, 'utf8');
    assert(html.includes('"args":[]'));
    res.end(html.replace('"args":[]', '"args":["--","--smoke-test"]'));
  } else fs.createReadStream(file).pipe(res);
});

let browser;
let page;
const log = [];
const errors = [];
const engineName = process.env.SOLO_BROWSER || 'chromium';
let navigations = 0;
(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  browser = await (engineName === 'webkit' ? webkit : chromium).launch({
    headless: true,
    ...(engineName === 'chromium' ? { executablePath: process.env.COOP_BROWSER, args: ['--autoplay-policy=no-user-gesture-required'] } : {}),
  });
  const context = await browser.newContext({ ...devices['iPhone 15 Pro Max'] });
  page = await context.newPage();
  page.on('framenavigated', frame => { if (frame === page.mainFrame()) navigations++; });
  page.on('crash', () => errors.push('Browser page crashed'));
  page.on('pageerror', error => {
    // The packaged smoke path quits Godot after PASS. Keep teardown messages
    // separate from failures that happened while the game was being exercised.
    if (log.some(line => line.startsWith('SMOKE_TEST_PASS:'))) {
      log.push('After engine shutdown: ' + error.message);
    } else errors.push(error.message);
  });
  page.on('console', message => {
    const text = message.text();
    log.push(text);
    if (/SMOKE:|SMOKE_TEST_/.test(text)) console.log(text);
    if (/SCRIPT ERROR|Parse Error|SMOKE_TEST_FAIL/.test(text)) errors.push(text);
  });
  await page.goto(`http://127.0.0.1:${server.address().port}/`, { waitUntil: 'load', timeout: 90000 });
  // Real play starts with a tap on the menu. The automatic smoke path skips
  // that gesture, so explicitly unlock browser audio before the video starts.
  async function waitForLog(fragment) {
    const deadline = Date.now() + 90000;
    while (!log.some(line => line.includes(fragment)) && errors.length === 0 && Date.now() < deadline) {
      await page.waitForTimeout(100);
    }
    assert(log.some(line => line.includes(fragment)), 'reached ' + fragment);
  }
  await waitForLog('SMOKE: character selected:');
  await page.keyboard.press('Shift');
  const hasWebAudio = await page.evaluate(() => Boolean(window.AudioContext || window.webkitAudioContext));
  assert(hasWebAudio, 'This browser build lacks Web Audio; run the complete video scenario in Chromium or a WebKit build with audio support.');
  const videoMode = 'natural-video';
  console.log('Video scenario:', videoMode);
  const deadline = Date.now() + 120000;
  while (!log.some(line => line.includes('SMOKE_TEST_PASS')) && errors.length === 0 && Date.now() < deadline) {
    await page.waitForTimeout(500);
  }
  await page.screenshot({ path: path.join(output, `${engineName}-solo-complete.png`) });
  assert.deepEqual(errors, []);
  assert(log.some(line => line.includes('Greg Power triggered from the Super Attack button')), 'super completes and resumes control');
  assert(log.some(line => line.includes('SMOKE_TEST_PASS')), 'packaged solo flow passes');
  assert.equal(navigations, 1, 'no page reload during or after the super');
  console.log(`SOLO_BROWSER_PASS: ${engineName}/iPhone-15-Pro-Max-layout/real-package/${videoMode}/wave/resume/no-reload`);
})().catch(async error => {
  console.error(error);
  if (page && !page.isClosed()) await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
  process.exitCode = 1;
}).finally(async () => {
  fs.writeFileSync(path.join(output, `${engineName}-log.txt`), log.join('\n'));
  await browser?.close();
  server.close();
});
