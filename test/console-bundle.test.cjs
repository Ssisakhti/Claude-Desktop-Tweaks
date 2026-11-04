'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { webcrypto, createHash } = require('node:crypto');
const { parseHTML } = require('linkedom');
const { KINDS } = require('../lib/persian/renderer-source.cjs');
const { CONTROLLER_REVISION } = require('../lib/persian/controller.cjs');
const { buildConsoleProbe, buildConsolePayload } = require('../lib/persian/console-payload.cjs');
const { buildConsoleBundle, singleLineSource, NONCE_TOKEN, DOCUMENT_TOKEN, URL_TOKEN } = require('../lib/persian/console-bundle.cjs');
const nonce = 'synthetic-bundle-request-012345';
const bundle = buildConsoleBundle();
const hash = source => createHash('sha256').update(source).digest('hex');
const count = (source, token) => source.split(token).length - 1;
function probeSource(expectedURL = null) {
 // The URL is a complete JSON literal. Substitute it after the other tokens.
 const literal = JSON.stringify(expectedURL).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
 return bundle.probeTemplate.replace(NONCE_TOKEN, nonce).replace(URL_TOKEN, literal);
}
function payloadSource(kind, documentId) {
 // The public builder also validates the consumer substitution contract.
 buildConsolePayload({ kind, nonce, documentId, fonts: [] });
 return bundle.payloads[kind].replace(NONCE_TOKEN, nonce).replace(DOCUMENT_TOKEN, documentId);
}
function driverProbeWrapper(source, expectedURL) {
 return '(async()=>{if(location.href!==' + JSON.stringify(expectedURL) + '){const result={marker:"RTL_CONSOLE_PROBE",nonce:"' + nonce + '",kind:null,ok:false,reason:"source-mismatch"};console.log(JSON.stringify(result));return result;}return await (' + source + ');})()';
}
function driverApplyWrapper(source, kind, id) {
 return '(async()=>{const record=window.__claudePersianConsoleDocumentV1;if(!record||record.document!==document||record.id!=="' + id + '")'
  + '{const result={marker:"RTL_CONSOLE_RESULT",nonce:"' + nonce + '",kind:"' + kind + '",ok:false,reason:"document-mismatch"};console.log(JSON.stringify(result));return result;}'
  + 'return await (' + source + ');})()';
}
function environment(url = 'https://claude.ai/new') {
 const { document } = parseHTML('<!doctype html><html><head></head><body><div data-testid="assistant-message"><p>API این بند فارسی ساختگی است.</p></div></body></html>');
 const faces = new Set(), timers = new Set(), logs = [];
 document.adoptedStyleSheets = [];
 document.fonts = { has: face => faces.has(face), add: face => faces.add(face), delete: face => faces.delete(face), check: () => true };
 class FontFace {
  constructor(family, bytes, options) { Object.assign(this, { family, bytes, ...options }); this.status = 'unloaded'; }
  async load() { this.status = 'loaded'; return this; }
 }
 class CSSStyleSheet { replaceSync(css) { this.css = css; } }
 class MutationObserver { observe() {} disconnect() {} }
 const context = vm.createContext({ URL, location: { href: url, search: '', ancestorOrigins: [] }, document, window: {}, crypto: webcrypto,
  Uint8Array, FontFace, CSSStyleSheet, MutationObserver, URLSearchParams,
  atob: value => Buffer.from(value, 'base64').toString('binary'),
  getComputedStyle: () => ({ display: 'block', colorScheme: 'light', fontFamily: 'sans-serif', fontWeight: '400', direction: 'ltr', backgroundColor: 'white' }),
  setTimeout(fn) { timers.add(fn); return fn; }, clearTimeout(fn) { timers.delete(fn); },
  console: { log: value => logs.push(value) },
 }, { codeGeneration: { strings: false, wasm: false } });
 return { context, document, faces, timers, logs };
}

test('Serialize only bundle version and templates for the five frame kinds', () => {
 assert.deepEqual(Object.keys(bundle), ['version', 'revision', 'probeTemplate', 'payloads']);
 assert.equal(bundle.version, 1); assert.equal(bundle.revision, CONTROLLER_REVISION);
 assert.deepEqual(Object.keys(bundle.payloads), KINDS);
 const decoded = JSON.parse(JSON.stringify(bundle));
 assert.equal(hash(decoded.probeTemplate), hash(bundle.probeTemplate));
 for (const kind of KINDS) assert.equal(hash(decoded.payloads[kind]), hash(bundle.payloads[kind]));
});

test('Tokens are unique and do not collide with font base64 data', () => {
 assert.equal(count(bundle.probeTemplate, NONCE_TOKEN), 1); assert.equal(count(bundle.probeTemplate, URL_TOKEN), 1);
 assert.equal(count(bundle.probeTemplate, DOCUMENT_TOKEN), 0);
 for (const source of Object.values(bundle.payloads)) {
  assert.equal(count(source, NONCE_TOKEN), 1); assert.equal(count(source, DOCUMENT_TOKEN), 1); assert.equal(count(source, URL_TOKEN), 0);
 }
 for (const font of require('../lib/persian/fonts.json')) {
  for (const token of [NONCE_TOKEN, DOCUMENT_TOKEN, URL_TOKEN]) assert.equal(font.data.includes(token), false);
 }
});

test('Substituted templates match the direct builder single-line output', () => {
 for (const expectedURL of [null, 'https://claude.ai/new?fixture=one']) {
  const source = probeSource(expectedURL);
  assert.equal(hash(source), hash(singleLineSource(buildConsoleProbe({ nonce, expectedURL })))); assert.doesNotThrow(() => new vm.Script(source));
 }
 const documentId = 'ab'.repeat(16);
 for (const kind of KINDS) {
  const source = payloadSource(kind, documentId);
  assert.equal(hash(source), hash(singleLineSource(buildConsolePayload({ kind, nonce, documentId })))); assert.doesNotThrow(() => new vm.Script(source));
 }
});

test('Bundle templates are synchronous ASCII single lines while direct output is preserved', () => {
 for (const source of [bundle.probeTemplate, ...Object.values(bundle.payloads)]) {
  assert.equal(typeof source, 'string'); assert.ok(!/[\r\n\u2028\u2029]/.test(source)); assert.ok(!/[^\x20-\x7e]/.test(source));
  assert.ok(!source.endsWith(';'));
 }
 assert.ok(buildConsoleProbe({ nonce }).includes('\n'));
 assert.ok(buildConsolePayload({ kind: 'chat', nonce, fonts: [] }).includes('\n'));
});

test('Bundle templates parse and run in the real console return-await wrapper', async () => {
 const id = 'ab'.repeat(16), f = environment();
 const source = driverProbeWrapper(probeSource(f.context.location.href), f.context.location.href);
 assert.doesNotThrow(() => new vm.Script(source));
 const before = await vm.runInContext(source, f.context);
 assert.equal(before.ok, true); assert.equal(before.kind, 'chat'); assert.match(before.documentId, /^[a-f0-9]{32}$/);
 for (const kind of KINDS) {
  assert.doesNotThrow(() => new vm.Script(driverApplyWrapper(payloadSource(kind, id), kind, id)), kind);
 }
 const result = await vm.runInContext(driverApplyWrapper(payloadSource('chat', before.documentId), 'chat', before.documentId), f.context);
 assert.equal(result.ok, true); assert.equal(result.attachedWeights, 9);
 f.context.window.__claudePersianControllerV2.dispose();
 const mismatch = await vm.runInContext(driverProbeWrapper(probeSource(f.context.location.href), f.context.location.href + '/different'), f.context);
 assert.equal(mismatch.reason, 'source-mismatch');
 assert.throws(() => singleLineSource('1;globalThis.unexpected=true'), SyntaxError);
});

test('Single-line formatting separates comments and ASI from strings and regexes', () => {
 const source = '(function(){const text="فارسی";const match=/a\\/b/.test("a/b");/* synthetic comment */\nreturn\n{text,match};})()';
 const compact = singleLineSource(source);
 const context = () => vm.createContext({}, { codeGeneration: { strings: false, wasm: false } });
 assert.equal(vm.runInContext(compact, context()), vm.runInContext(source, context()));
 assert.ok(!compact.includes('synthetic comment')); assert.ok(!/[\r\n\u2028\u2029]/.test(compact));
 const values = '(function(){// synthetic line comment\nreturn ["فارسی",`line one\nline two`,/a\\/b/.test("a/b")];})()';
 assert.equal(JSON.stringify(vm.runInContext(singleLineSource(values), context())), JSON.stringify(vm.runInContext(values, context())));
});

test('URLs with quotes and backticks remain data and are absent from output', async () => {
 const specialURL = 'https://claude.ai/new?fixture=' + String.fromCharCode(96, 39, 34, 92, 10, 0x2028, 0x2029) + ';globalThis.injected=true;//';
 const f = environment(specialURL);
 const result = await vm.runInContext(probeSource(specialURL), f.context);
 assert.equal(result.ok, true); assert.equal(result.kind, 'chat'); assert.equal(f.context.injected, undefined);
 assert.ok(!f.logs[0].includes('fixture=')); assert.ok(!f.logs[0].includes('https://'));
 const mismatch = await vm.runInContext(probeSource(specialURL + 'different'), f.context);
 assert.equal(mismatch.reason, 'source-mismatch'); assert.equal(f.context.injected, undefined);
});

test('Reject invalid document IDs before installation', async () => {
 for (const documentId of ['', 'abc', 'a'.repeat(31), 'a'.repeat(33), '";globalThis.injected=true;//']) {
  assert.throws(() => payloadSource('chat', documentId), /document ID/);
 }
 const f = environment();
 const source = bundle.payloads.chat.replace(NONCE_TOKEN, nonce);
 const result = await vm.runInContext(source, f.context);
 assert.equal(result.reason, 'document-mismatch'); assert.equal(f.faces.size, 0); assert.equal(f.document.adoptedStyleSheets.length, 0);
});

test('Bundle probes and payloads repair the same document without eval or network access', async () => {
 const f = environment(), baseline = f.document.documentElement.outerHTML;
 const before = await vm.runInContext(probeSource(f.context.location.href), f.context);
 assert.equal(before.ok, true); assert.equal(before.healthy, false);
 const result = await vm.runInContext(payloadSource('chat', before.documentId), f.context);
 assert.equal(result.ok, true); assert.equal(result.attachedWeights, 9); assert.equal(result.stylesLoaded, true);
 const after = await vm.runInContext(probeSource(f.context.location.href), f.context);
 assert.equal(after.healthy, true); assert.equal(after.documentId, before.documentId);
 assert.equal(f.document.documentElement.outerHTML, baseline); assert.equal(f.faces.size, 9);
 f.context.window.__claudePersianControllerV2.dispose();
 assert.equal(f.faces.size, 0); assert.equal(f.document.adoptedStyleSheets.length, 0); assert.equal(f.timers.size, 0);
});
