const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const code = fs.readFileSync(path.join(__dirname, '../web/net/pack-loader.js'), 'utf8');
function loader(parts, replies) {
  const calls = [];
  const window = {
    GREG_MUTKI_PACK: { name: 'index-test.pck', size: parts.reduce((sum, p) => sum + p.size, 0), parts },
    fetch: async (url, options) => {
      calls.push(String(url));
      if (options?.signal?.aborted) throw options.signal.reason;
      const reply = replies[new URL(url, 'https://example.test/game/').pathname];
      return new Response(reply?.data, { status: reply?.status || 200 });
    }
  };
  vm.runInNewContext(code, { window, document: { baseURI: 'https://example.test/game/?v=123#room=ABC234' }, URL, Request, Response, ReadableStream });
  return { fetch: window.fetch, calls };
}
(async () => {
  const parts = [{ url: 'packs/one.bin', size: 2 }, { url: 'packs/two.bin', size: 3 }];
  const replies = { '/game/packs/one.bin': { data: Uint8Array.of(1, 2) }, '/game/packs/two.bin': { data: Uint8Array.of(3, 4, 5) } };
  const good = loader(parts, replies);
  const response = await good.fetch('index-test.pck');
  assert.equal(response.headers.get('content-length'), '5');
  assert.deepEqual([...new Uint8Array(await response.arrayBuffer())], [1, 2, 3, 4, 5]);
  assert.deepEqual(good.calls, ['https://example.test/game/packs/one.bin', 'https://example.test/game/packs/two.bin']);
  await good.fetch('index.wasm');
  assert.equal(good.calls.at(-1), 'index.wasm');
  const missing = loader(parts, { ...replies, '/game/packs/two.bin': { status: 404 } });
  await assert.rejects((await missing.fetch('index-test.pck')).arrayBuffer(), /HTTP 404/);
  const short = loader(parts, { ...replies, '/game/packs/two.bin': { data: Uint8Array.of(3) } });
  await assert.rejects((await short.fetch('index-test.pck')).arrayBuffer(), /Incomplete/);
  const aborted = loader(parts, replies);
  const controller = new AbortController();
  controller.abort(new Error('Stopped download'));
  await assert.rejects((await aborted.fetch('index-test.pck', { signal: controller.signal })).arrayBuffer(), /Stopped download/);
  console.log('PACK_LOADER_PASS: exact-bytes/order/repo-subpath/progress/unrelated-files/missing-part/truncation/abort');
})().catch(error => { console.error(error); process.exitCode = 1; });
