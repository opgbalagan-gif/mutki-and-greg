/* Stream the content-addressed game package from small static hosting files. */
(() => {
  'use strict';
  const fetchFile = window.fetch.bind(window);
  window.fetch = async (input, options) => {
    const pack = window.GREG_MUTKI_PACK;
    const url = new URL(input instanceof Request ? input.url : String(input), document.baseURI);
    if (!pack || url.href !== new URL(pack.name, document.baseURI).href) return fetchFile(input, options);
    const signal = options?.signal || (input instanceof Request ? input.signal : undefined);
    let index = 0;
    let reader = null;
    let received = 0;
    const stream = new ReadableStream({
      async pull(controller) {
        try {
          while (index < pack.parts.length) {
            const part = pack.parts[index];
            if (!reader) {
              const response = await fetchFile(new URL(part.url, url).href, { signal, credentials: 'same-origin' });
              if (!response.ok) throw new Error(`Game package part ${index + 1}: HTTP ${response.status}`);
              reader = response.body.getReader();
              received = 0;
            }
            const chunk = await reader.read();
            if (chunk.done) {
              if (received !== part.size) throw new Error(`Incomplete game package part ${index + 1}`);
              reader.releaseLock();
              reader = null;
              index++;
              continue;
            }
            received += chunk.value.byteLength;
            if (received > part.size) throw new Error(`Oversized game package part ${index + 1}`);
            controller.enqueue(chunk.value);
            return;
          }
          controller.close();
        } catch (error) {
          controller.error(error);
        }
      },
      cancel(reason) { return reader?.cancel(reason); }
    });
    return new Response(stream, { headers: { 'Content-Type': 'application/octet-stream', 'Content-Length': String(pack.size) } });
  };
})();
