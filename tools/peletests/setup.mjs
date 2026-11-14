// Marks a test of Pele's that called an API nimaki does not provide (index.mjs sets the flag),
// so that tools/peletests.nim counts it apart even when the test caught the error.
import { beforeEach, afterEach } from 'vitest';

beforeEach(() => {
  globalThis.__nimakiMissing = undefined;
});

afterEach((ctx) => {
  if (globalThis.__nimakiMissing) ctx.task.meta.nimakiMissing = globalThis.__nimakiMissing;
});
