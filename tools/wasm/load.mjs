// Loads build/wasm/nimaki.wasm (tools/wasm/build.sh) in Node and returns `render(source, now)`,
// which gives `{ svg }` as nimaki.js and Pele do, or throws with nimaki's message.
// Used by tools/bench.mjs (engine `wasm`) and tools/wasm/check.mjs.
import { readFileSync } from 'node:fs';
import { WASI } from 'node:wasi';

export async function loadWasm(file) {
  const wasi = new WASI({ version: 'preview1', env: { TZ: 'UTC' } });
  const { instance } = await WebAssembly.instantiate(readFileSync(file), wasi.getImportObject());
  wasi.initialize(instance);
  const x = instance.exports;
  x.nimakiInit();
  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  return function render(source, now) {
    const bytes = encoder.encode(source);
    const p = x.nimakiAlloc(bytes.length + 1);
    new Uint8Array(x.memory.buffer, p, bytes.length).set(bytes);
    const status = x.nimakiRender(p, bytes.length, now);
    x.nimakiFree(p);
    const text = decoder.decode(new Uint8Array(x.memory.buffer, x.nimakiResult(), x.nimakiResultLen()));
    if (status !== 0) throw new Error(text);
    return { svg: text };
  };
}
