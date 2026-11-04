'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { webcrypto } = require('node:crypto');
const { parseHTML } = require('linkedom');
const { KINDS, classifyFrame } = require('../lib/persian/renderer-source.cjs');
const { CONTROLLER_REVISION } = require('../lib/persian/controller.cjs');
const { consoleFrame, runConsole, buildConsoleProbe, buildConsolePayload } = require('../lib/persian/console-payload.cjs');
const nonce = 'synthetic-request-012345';
const fontCount = require('../lib/persian/fonts.json').length;
const request = { kind: 'chat', nonce, weights: fontCount, revision: CONTROLLER_REVISION };
const healthy = { kind: 'chat', revision: CONTROLLER_REVISION, fontLoaded: true, stylesAttached: true, stylesLoaded: true, attachedWeights: fontCount };
const flush = () => new Promise(resolve => setImmediate(resolve));
function deferred() { let resolve; const promise = new Promise(done => { resolve = done; }); return { promise, resolve }; }
function runner({ url = 'https://claude.ai/new', origins = [], old, install = async () => healthy } = {}) {
 const context = vm.createContext({ URL, location: { href: url, ancestorOrigins: origins }, document: {},
  window: { __claudePersianControllerV2: old }, install, classifyFrame, consoleFrame, request });
 const start = () => vm.runInContext(`(${runConsole.toString()})(install,classifyFrame,consoleFrame,request)`, context);
 return { context, start };
}
function probeFixture({ url = 'https://claude.ai/new', origins = [], old, crypto = webcrypto } = {}) {
 const logs = [];
 const context = vm.createContext({ URL, location: { href: url, ancestorOrigins: origins }, document: {}, crypto, Uint8Array,
  window: { __claudePersianControllerV2: old }, console: { log: value => logs.push(value) } });
 const probe = (requestNonce = nonce) => vm.runInContext(buildConsoleProbe({ nonce: requestNonce }), context);
 return { context, logs, probe };
}

test('Console context classification follows the independent five-frame contract', () => {
 const shell = 'file:///Applications/Claude.app/Contents/Resources/app.asar/.vite/renderer/';
 assert.deepEqual(KINDS, ['shell', 'chat', 'artifact', 'artifact-content', 'document']);
 for (const [href, ancestorOrigins, expected] of [
  [shell + 'main_window/index.html', [], 'shell'], [shell + 'quick_window/index.html', [], 'shell'],
  [shell + 'about_window/index.html', [], 'shell'], [shell + 'unknown_window/index.html', [], null],
  ['https://claude.ai/new', [], 'chat'], ['https://claude.ai/code/artifact/fixture', [], 'artifact'],
  ['https://fixture.frame.claudeusercontent.com/', [], 'artifact-content'],
  ['about:srcdoc', ['https://fixture.frame.claudeusercontent.com', 'https://claude.ai'], 'document'],
  ['about:srcdoc', ['https://evil.example'], null], ['about:srcdoc', [], null],
  ['https://claude.ai/login', [], null], ['https://claude.ai/oauth/callback', [], null],
  ['https://claude.ai/api', [], null], ['https://claude.ai.evil.example/', [], null],
  ['https://fixture.frame.claudeusercontent.com.evil.example', [], null], ['about:blank', [], null],
 ]) assert.equal(classifyFrame(consoleFrame({ href, ancestorOrigins })), expected, href);
 const tooDeep = Array(12).fill('https://evil.example').concat('https://fixture.frame.claudeusercontent.com');
 assert.equal(classifyFrame(consoleFrame({ href: 'about:srcdoc', ancestorOrigins: tooDeep })), null);
});

test('Reject srcdoc frames without accessible ancestorOrigins', () => {
 const location = { href: 'about:srcdoc', get ancestorOrigins() { throw new Error('synthetic denied'); } };
 assert.equal(classifyFrame(consoleFrame(location)), null);
 assert.equal(classifyFrame(consoleFrame({ href: 'about:srcdoc' })), null);
});

test('Reject invalid kinds and nonces before building commands', () => {
 for (const kind of [undefined, 'unknown', 'chat);alert(1)']) assert.throws(() => buildConsolePayload({ kind, nonce, fonts: [] }), /kind/);
 for (const value of [undefined, '', 'short', 'a'.repeat(81), 'a'.repeat(16) + '\n', 'a'.repeat(16) + '"']) assert.throws(() => buildConsolePayload({ kind: 'chat', nonce: value, fonts: [] }), /nonce/);
 for (const value of [undefined, '', 'short', 'a'.repeat(81), 'a'.repeat(16) + '\n']) assert.throws(() => buildConsoleProbe({ nonce: value }), /nonce/);
 for (const expectedURL of [1, false, {}, []]) assert.throws(() => buildConsoleProbe({ nonce, expectedURL }), /URL/);
 for (const documentId of [null, '', 'short', 'a'.repeat(31), 'a'.repeat(33), 'Z'.repeat(32), 'a'.repeat(32) + '\n']) {
  assert.throws(() => buildConsolePayload({ kind: 'chat', nonce, fonts: [], documentId }), /document ID/);
 }
 assert.throws(() => buildConsolePayload({ kind: 'chat', nonce, fonts: 'invalid' }), /fonts/);
 for (const kind of KINDS) assert.doesNotThrow(() => new vm.Script(buildConsolePayload({ kind, nonce, fonts: [] })));
});

test('Probe verifies the expected URL before accessing window or controller', async () => {
 const logs = [];
 const expectedURL = 'https://claude.ai/cowork/expected-fixture';
 const source = buildConsoleProbe({ nonce, expectedURL });
 // Intentionally omit document and window. Check the URL before touching either.
 const result = await vm.runInNewContext(source, { URL, location: { href: 'https://claude.ai/new' }, console: { log: value => logs.push(value) } });
 assert.equal(result.reason, 'source-mismatch'); assert.equal(result.ok, false); assert.equal(result.documentId, null);
 assert.equal(result.kind, null); assert.ok(!logs[0].includes(expectedURL)); assert.ok(!logs[0].includes('https://'));
 const f = probeFixture();
 const accepted = await vm.runInContext(buildConsoleProbe({ nonce, expectedURL: f.context.location.href }), f.context);
 assert.equal(accepted.ok, true);
});

test('Probe creates a temporary namespace and random ID only in allowed frames', async () => {
 for (const url of ['https://evil.example', 'https://claude.ai/login', 'about:blank']) {
  const logs = [];
  const result = await vm.runInNewContext(buildConsoleProbe({ nonce }), { URL, location: { href: url }, console: { log: value => logs.push(value) } });
  assert.equal(result.reason, 'context-mismatch'); assert.equal(result.documentId, null); assert.equal(result.kind, null);
  assert.ok(!logs[0].includes(url));
 }
 const f = probeFixture();
 const result = await f.probe();
 assert.equal(result.marker, 'RTL_CONSOLE_PROBE'); assert.equal(result.ok, true); assert.equal(result.kind, 'chat');
 assert.match(result.documentId, /^[a-f0-9]{32}$/); assert.equal(result.controllerPresent, false); assert.equal(result.healthy, false);
 assert.equal((await f.probe('another-synthetic-request')).documentId, result.documentId);
 assert.ok(!Object.keys(f.context.window).includes('__claudePersianConsoleDocumentV1'));
 f.context.document = {};
 assert.notEqual((await f.probe()).documentId, result.documentId);
});

test('Probe stops without a cryptographic random source', async () => {
 for (const crypto of [null, {}, { randomUUID: () => 'invalid' }]) {
  const f = probeFixture({ crypto }); const result = await f.probe();
  assert.equal(result.ok, false); assert.equal(result.documentId, null);
  assert.ok(['random-source-unavailable', 'random-source-invalid', 'probe-failed'].includes(result.reason));
  assert.equal(f.context.window.__claudePersianConsoleDocumentV1, undefined);
 }
 let calls = 0;
 const fallback = probeFixture({ crypto: { getRandomValues(bytes) { calls++; assert.equal(bytes.length, 16); return bytes.fill(17); } } });
 assert.equal((await fallback.probe()).documentId, '11'.repeat(16)); assert.equal(calls, 1);
});

test('Probe reports health only for the current revision without exposing snapshots', async () => {
 for (const [status, expected] of [
  [healthy, true], [{ ...healthy, revision: CONTROLLER_REVISION - 1 }, false],
  [{ ...healthy, stylesLoaded: false }, false], [{ ...healthy, kind: 'document' }, false],
  [{ kind: 'chat', fontLoaded: true }, false],
 ]) {
  const f = probeFixture({ old: { snapshot: () => ({ ...status, sample: [{ text: 'PRIVATE_FIXTURE' }], url: 'https://private.invalid', errorMessage: 'PRIVATE_FIXTURE' }) } });
  const result = await f.probe(); assert.equal(result.ok, true); assert.equal(result.healthy, expected); assert.equal(result.controllerPresent, true);
  assert.deepEqual(Object.keys(result).sort(), ['marker', 'nonce', 'kind', 'ok', 'documentId', 'controllerPresent', 'healthy'].sort());
  assert.ok(!f.logs[0].includes('PRIVATE')); assert.ok(!f.logs[0].includes('https://'));
 }
});

test('Navigation during a probe does not return the previous context ID or success', async () => {
 const gate = deferred(); const f = probeFixture({ old: gate.promise });
 const task = f.probe(); await flush(); f.context.document = {}; gate.resolve(null);
 const result = await task; assert.equal(result.ok, false); assert.equal(result.reason, 'context-changed'); assert.equal(result.documentId, null);
});

test('Document IDs distinguish same-kind frames before reading the controller', async () => {
 const first = probeFixture(), second = probeFixture();
 const firstId = (await first.probe()).documentId, secondId = (await second.probe()).documentId;
 assert.notEqual(firstId, secondId);
 Object.defineProperty(second.context.window, '__claudePersianControllerV2', { configurable: true, get() { throw new Error('controller must not be read'); } });
 const source = buildConsolePayload({ kind: 'chat', nonce, documentId: firstId, fonts: [] });
 const result = await vm.runInContext(source, second.context);
 assert.equal(result.reason, 'document-mismatch'); assert.equal(result.ok, false);
});

test('Reject the previous document ID after same-URL document replacement', async () => {
 const f = probeFixture(); const id = (await f.probe()).documentId;
 f.context.document = {};
 const source = buildConsolePayload({ kind: 'chat', nonce, documentId: id, fonts: [] });
 assert.equal((await vm.runInContext(source, f.context)).reason, 'document-mismatch');
 await f.probe();
 assert.equal((await vm.runInContext(source, f.context)).reason, 'document-mismatch');
});

test('Verify document identity before and after await while retaining manual execution', async () => {
 const f = runner(); const probed = await vm.runInContext(buildConsoleProbe({ nonce }), Object.assign(f.context, { crypto: webcrypto, Uint8Array, console: { log() {} } }));
 f.context.request = { ...request, documentId: probed.documentId };
 assert.equal((await f.start()).ok, true);
 const gate = deferred(); f.context.window.__claudePersianControllerV2 = gate.promise;
 const task = f.start(); await flush(); f.context.window.__claudePersianConsoleDocumentV1.id = 'f'.repeat(32); gate.resolve(null);
 assert.equal((await task).reason, 'context-changed');
 assert.equal((await runner().start()).ok, true);
});

test('Reject disallowed frames and wrong kinds without starting the engine', async () => {
 for (const url of ['https://evil.example/', 'https://claude.ai/login', 'about:srcdoc', 'https://claude.ai/code/artifact/fixture']) {
  const source = buildConsolePayload({ kind: 'chat', nonce, fonts: [] });
  const logs = [];
  // No document exists. Starting the engine would fail this test.
  const result = await vm.runInNewContext(source, { URL, location: { href: url, ancestorOrigins: [] }, console: { log: text => logs.push(text) } });
  assert.equal(result.reason, 'context-mismatch'); assert.equal(result.ok, false);
  assert.equal(logs.length, 1); assert.equal(JSON.parse(logs[0]).nonce, nonce);
  assert.ok(!logs[0].includes(url));
 }
});

test('Navigation while awaiting a controller stops installation before it begins', async () => {
 const gate = deferred(); let installed = 0;
 const f = runner({ old: gate.promise, install: async () => { installed++; return healthy; } });
 const task = f.start(); await flush();
 f.context.location.href = 'https://claude.ai/cowork/another-fixture'; gate.resolve(null);
 const result = await task;
 assert.equal(result.reason, 'context-changed'); assert.equal(installed, 0);
});

test('Same-URL document replacement also stops installation', async () => {
 const gate = deferred(); let installed = 0;
 const f = runner({ old: gate.promise, install: async () => { installed++; return healthy; } });
 const task = f.start(); await flush(); f.context.document = {}; gate.resolve(null);
 assert.equal((await task).reason, 'context-changed'); assert.equal(installed, 0);
});

test('Reject srcdoc parent changes during await even when the kind is unchanged', async () => {
 const gate = deferred(); let installed = 0;
 const f = runner({ url: 'about:srcdoc', origins: ['https://first.frame.claudeusercontent.com'], old: gate.promise,
  install: async () => { installed++; return healthy; } });
 f.context.request = { ...request, kind: 'document' };
 const task = f.start(); await flush(); f.context.location.ancestorOrigins[0] = 'https://second.frame.claudeusercontent.com'; gate.resolve(null);
 assert.equal((await task).reason, 'context-changed'); assert.equal(installed, 0);
});

test('Leave controllers of a different kind untouched', async () => {
 let installed = 0, refreshed = 0;
 const f = runner({ old: { snapshot: () => ({ kind: 'document' }), refresh: () => { refreshed++; } },
  install: async () => { installed++; return healthy; } });
 assert.equal((await f.start()).reason, 'controller-kind-mismatch'); assert.equal(installed, 0); assert.equal(refreshed, 0);
});

test('Navigation during snapshot or refresh prevents further installation', async () => {
 for (const stage of ['snapshot', 'refresh']) {
  const gate = deferred(); let installed = 0;
  const old = { snapshot: () => stage === 'snapshot' ? gate.promise : { ...healthy, stylesAttached: false }, refresh: () => gate.promise };
  const f = runner({ old, install: async () => { installed++; return healthy; } });
  const task = f.start(); await flush(); f.context.location.href = 'https://evil.example/'; gate.resolve(healthy);
  assert.equal((await task).reason, 'context-changed', stage); assert.equal(installed, 0, stage);
 }
});

test('Context changes during installation do not report success', async () => {
 const gate = deferred(); const f = runner({ install: () => gate.promise });
 const task = f.start(); await flush(); f.context.document = {}; gate.resolve(healthy);
 const result = await task; assert.equal(result.reason, 'context-changed'); assert.equal(result.ok, false);
});

test('Do not rescan healthy controllers or expose private data in output', async () => {
 let refreshed = 0;
 const status = { ...healthy, sample: [{ text: 'SYNTHETIC_PRIVATE_CONTENT' }], url: 'https://private.invalid/fixture', extra: 'secret-fixture' };
 const f = runner({ old: { snapshot: () => status, refresh: () => { refreshed++; } }, install: async () => status });
 const result = await f.start(); assert.equal(result.ok, true); assert.equal(refreshed, 0);
 assert.deepEqual(Object.keys(result).sort(), ['marker', 'nonce', 'kind', 'ok', 'pending', 'fontLoaded', 'stylesAttached', 'stylesLoaded', 'attachedWeights'].sort());
 assert.ok(!JSON.stringify(result).includes('PRIVATE')); assert.ok(!JSON.stringify(result).includes('https://'));
});

test('Old or incomplete health does not count as success or expose private errors', async () => {
 for (const [status, reason] of [
  [{ kind: 'chat', fontLoaded: true }, 'health-unverified'],
  [{ ...healthy, stylesAttached: false }, 'application-incomplete'],
  [{ ...healthy, stylesLoaded: false }, 'application-incomplete'],
  [{ ...healthy, attachedWeights: 8 }, 'application-incomplete'],
  [{ ...healthy, fontLoaded: false }, 'application-incomplete'],
  [{ pending: true }, 'application-incomplete'],
  [{ ...healthy, error: 'SYNTHETIC_PRIVATE_ERROR' }, 'application-incomplete'],
 ]) {
  const result = await runner({ install: async () => status }).start();
  assert.equal(result.ok, false); assert.equal(result.reason, reason); assert.ok(!JSON.stringify(result).includes('PRIVATE'));
 }
 const failed = await runner({ install: async () => { throw new Error('SYNTHETIC_PRIVATE_ERROR'); } }).start();
 assert.equal(failed.reason, 'application-failed'); assert.ok(!JSON.stringify(failed).includes('PRIVATE'));
});

test('Dispose older controllers through their own method before reinstalling', async () => {
 let installed = 0, disposed = 0;
 const old = { snapshot: () => ({ kind: 'chat', fontLoaded: true }), dispose: async () => { disposed++; delete f.context.window.__claudePersianControllerV2; } };
 const f = runner({ old, install: async () => { installed++; return healthy; } });
 const result = await f.start(); assert.equal(result.ok, true); assert.equal(disposed, 1); assert.equal(installed, 1);
});

test('Upgrade healthy older revisions through their own dispose method', async () => {
 let disposed = 0, refreshed = 0;
 const old = { snapshot: () => ({ ...healthy, revision: CONTROLLER_REVISION - 1 }), refresh: () => { refreshed++; },
  dispose: () => { disposed++; delete f.context.window.__claudePersianControllerV2; } };
 const f = runner({ old });
 assert.equal((await f.start()).ok, true); assert.equal(disposed, 1); assert.equal(refreshed, 0);
});

test('Missing or failed dispose prevents installation over older controllers', async () => {
 for (const [dispose, reason] of [
  [undefined, 'controller-dispose-unavailable'], [async () => {}, 'controller-dispose-incomplete'],
  [async () => { throw new Error('SYNTHETIC_PRIVATE_ERROR'); }, 'application-failed'],
 ]) {
  let installed = 0;
  const old = { snapshot: () => ({ kind: 'chat', fontLoaded: true }), dispose };
  const result = await runner({ old, install: async () => { installed++; return healthy; } }).start();
  assert.equal(result.reason, reason); assert.equal(installed, 0); assert.ok(!JSON.stringify(result).includes('PRIVATE'));
 }
});

test('Document or controller changes during dispose prevent subsequent installation', async () => {
 for (const change of ['document', 'controller']) {
  const gate = deferred(); let installed = 0;
  const old = { snapshot: () => ({ kind: 'chat', fontLoaded: true }), dispose: () => gate.promise };
  const f = runner({ old, install: async () => { installed++; return healthy; } });
  const task = f.start(); await flush();
  if (change === 'document') f.context.document = {};
  else f.context.window.__claudePersianControllerV2 = {};
  gate.resolve();
  assert.equal((await task).reason, change === 'document' ? 'context-changed' : 'controller-dispose-incomplete'); assert.equal(installed, 0);
 }
});

test('Refresh an unhealthy current controller without disposal after recovery', async () => {
 let restored = false, disposed = false;
 const old = { snapshot: () => ({ ...healthy, stylesAttached: restored }), refresh: () => { restored = true; }, dispose: () => { disposed = true; } };
 const result = await runner({ old }).start(); assert.equal(result.ok, true); assert.equal(restored, true); assert.equal(disposed, false);
});

test('Execute the shared engine only in the selected context without eval or network access', async () => {
 const { document } = parseHTML('<!doctype html><html><head></head><body><aside>نام پروژه</aside><div data-testid="assistant-message"><p>API این بند فارسی برای آزمون است.</p></div></body></html>');
 document.adoptedStyleSheets = [];
 document.fonts = { check: () => true, has: () => false, add() {}, delete() {} };
 const baseline = document.documentElement.outerHTML;
 const logs = [], timers = new Set(), window = {};
 class CSSStyleSheet { replaceSync(css) { this.css = css; } }
 class MutationObserver { observe() {} disconnect() {} }
 const context = vm.createContext({ window, document, URL, URLSearchParams, Uint8Array, CSSStyleSheet, MutationObserver,
  location: { href: 'https://claude.ai/new', search: '', ancestorOrigins: [] },
  getComputedStyle: () => ({ display: 'block', colorScheme: 'light', fontFamily: 'sans-serif', fontWeight: '400', direction: 'ltr', backgroundColor: 'white' }),
  setTimeout(fn) { timers.add(fn); return fn; }, clearTimeout(fn) { timers.delete(fn); },
  console: { log: value => logs.push(value) },
 }, { codeGeneration: { strings: false, wasm: false } });
 const result = await vm.runInContext(buildConsolePayload({ kind: 'chat', nonce, fonts: [] }), context);
 assert.equal(result.ok, true); assert.equal(result.attachedWeights, 0); assert.equal(result.stylesAttached, true);
 assert.equal(document.documentElement.outerHTML, baseline); assert.equal(document.adoptedStyleSheets.length, 2);
 assert.equal(logs.length, 1); assert.ok(!logs[0].includes('sample')); assert.ok(!logs[0].includes('API'));
 assert.equal(typeof window.__claudePersianControllerV2.dispose, 'function');
 window.__claudePersianControllerV2.dispose(); assert.equal(document.adoptedStyleSheets.length, 0); assert.equal(timers.size, 0);
});
