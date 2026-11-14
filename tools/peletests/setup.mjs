// Marks a test of Pele's that called an API nimaki does not provide, or read a model with parse()
// (index.mjs sets the flags), so that tools/peletests.nim can count it apart even when the test
// caught the error.
import { beforeEach, afterEach } from 'vitest';

beforeEach(() => {
  globalThis.__nimakiMissing = undefined;
  globalThis.__nimakiParsed = undefined;
});

afterEach((ctx) => {
  if (globalThis.__nimakiMissing) ctx.task.meta.nimakiMissing = globalThis.__nimakiMissing;
  if (globalThis.__nimakiParsed) ctx.task.meta.nimakiParsed = true;
});
