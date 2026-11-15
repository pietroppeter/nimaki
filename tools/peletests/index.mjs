// Pele's public API (src/index.ts at the pin), drawn by nimaki: tools/peletests.nim points Pele's
// test suites here instead of Pele's own src/index.js. `render`, `detectType` and `supports`
// call nimaki's JavaScript build (bridge.nim); the text measurer stays Pele's, as in difftest.
// `parse` returns nimaki's model, written as Pele's (tools/models.nim), and `render` draws it.
// What nimaki does not provide (mount, zoom) throws, and the tests that use it are counted apart.
import { createRequire } from 'node:module';
import { PeleError } from 'PELE_SRC/errors.js';
export { PeleError };

const require = createRequire(import.meta.url);
const bridge = require(process.env.NIMAKI_BRIDGE);

// PeleError is Pele's own class, so that a PeleError from nimaki and one from a part of Pele a test calls
// directly (a parser, say) are the same thing to `instanceof`.

export class NotInNimaki extends Error {
  constructor(what) {
    super(`nimaki does not provide ${what}`);
    this.name = 'NotInNimaki';
    // read by setup.mjs: the test used an API nimaki does not have, whatever it caught
    globalThis.__nimakiMissing = what;
  }
}

function call(f) {
  try {
    return f();
  } catch (e) {
    if (e && e.peleError) throw new PeleError(e.message, e.code, e);
    throw e;
  }
}

export function render(source, options = {}) {
  if (typeof source === 'string') return call(() => bridge.nimakiRender(source, options));
  const drawn = source && typeof source === 'object' ? call(() => bridge.nimakiRenderModel(source, options)) : null;
  if (drawn === null) throw new TypeError('render() takes diagram text or a model that parse() returned.');
  return drawn;
}

// Read by setup.mjs: the test read a model, which is Pele's in shape only where
// tools/parsediff.nim says so.
export function parse(source, options = {}) {
  globalThis.__nimakiParsed = true;
  const model = call(() => bridge.nimakiParse(source, options));
  for (const name of METHODS[model.type] ?? []) {
    Object.defineProperty(model, name, { value: (arg) => bridge.nimakiModelCall(model, name, arg), enumerable: false });
  }
  if (model.type === 'agentflow') {
    Object.defineProperty(model, 'subgraph', { value: (id) => model.subgraphLookup?.get(id), enumerable: false });
    for (const [method, severity] of [['emitWarning', 'warning'], ['emitError', 'error']]) {
      Object.defineProperty(model, method, { value: (id, message, ctx) => emit(model, id, severity, message, ctx), enumerable: false });
    }
  }
  return model;
}

// The methods of Pele's models that its tests call, run by nimaki (bridge.nim).
const METHODS = { gantt: ['getTasks'], agentflow: ['semanticModel', 'vertexKind'] };

// Pele's AgentflowDb.emit, for a test that builds Pele's own graph from the model: a finding
// already recorded (nimaki's parse builds the graph too) is recorded once.
function emit(db, id, severity, message, ctx) {
  const anchor = ctx?.nodeId ?? ctx?.edgeId;
  const diagnostic = { id, severity, message };
  if (ctx?.nodeId) diagnostic.nodeId = ctx.nodeId;
  else if (ctx?.edgeId) diagnostic.edgeId = ctx.edgeId;
  const mapping = anchor ? db.firstMapping?.get(anchor) : undefined;
  if (mapping) diagnostic.position = mapping.position;
  const key = anchor ?? '';
  const same = db.reported.get(key);
  if (same === undefined) db.reported.set(key, [diagnostic]);
  else {
    for (const d of same) {
      if (d.id === id && d.severity === severity && d.message === message && d.nodeId === diagnostic.nodeId &&
          d.edgeId === diagnostic.edgeId) return;
    }
    same.push(diagnostic);
  }
  db.diagnostics.push(diagnostic);
}

export function detectType(text) {
  return bridge.nimakiDetectType(text);
}

export function supports(text) {
  return bridge.nimakiSupports(text);
}

export function mount() { throw new NotInNimaki('mount()'); }
export function enableZoom() { throw new NotInNimaki('enableZoom()'); }
export function register() { throw new NotInNimaki('register()'); }
export function registered() { throw new NotInNimaki('registered()'); }
export { forgetTextWidths } from 'PELE_SRC/text/measurer.js';
