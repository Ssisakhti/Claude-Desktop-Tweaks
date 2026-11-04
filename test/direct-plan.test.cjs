'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { parseHTML } = require('linkedom');
const { buildDirectPlan } = require('../lib/persian/direct-plan.cjs');
const { KINDS, classifyFrame } = require('../lib/persian/renderer-source.cjs');
const { consoleFrame } = require('../lib/persian/console-payload.cjs');
const font = require('../lib/persian/fonts.json')[0];
const nonce = 'a'.repeat(32), namespace = '__cdt_plan_fixture';
const options = { namespace, nonce, kind: 'chat' };
function fixture(kind = 'chat', { failFont = false } = {}) {
 const { document } = parseHTML('<!doctype html><html class="dark"><head></head><body><aside>عنوان فارسی</aside><div data-testid="assistant-message"><p>API متن فارسی برای آزمون</p></div><article><div class="tiptap ProseMirror" contenteditable="true"><p>سند فارسی</p><table><tr><td>ستون اول</td><td>Second column</td></tr></table></div></article><textarea aria-label="Comment">کامنت فارسی</textarea></body></html>');
 const urls = { shell: 'file:///Applications/Claude.app/Contents/Resources/app.asar/.vite/renderer/main_window/index.html', chat: 'https://claude.ai/new', artifact: 'https://claude.ai/code/artifact/fixture', 'artifact-content': 'https://fixture.frame.claudeusercontent.com/example/', document: 'about:srcdoc' };
 const location = { href: urls[kind], search: '', ancestorOrigins: kind === 'document' ? ['https://fixture.frame.claudeusercontent.com', 'https://claude.ai'] : [] };
 const baseline = document.documentElement.outerHTML, faces = new Set(), created = [], timers = new Set(), logs = [];
 document.adoptedStyleSheets = [];
 document.fonts = { add: face => faces.add(face), has: face => faces.has(face), delete: face => faces.delete(face), check: () => true };
 class FontFace {
  constructor(family, bytes, properties) { Object.assign(this, { family, bytes }, properties); created.push(this); }
  async load() { if (failFont) throw Error('SYNTHETIC_PRIVATE_FONT_ERROR'); this.status = 'loaded'; return this; }
 }
 class CSSStyleSheet { constructor() { this.css = ''; this.disabled = false; } replaceSync(css) { this.css = css; } }
 class MutationObserver { observe() {} disconnect() {} }
 const window = { __claudePersianConsoleDocumentV1: { document, id: 'b'.repeat(32), identity: JSON.stringify(consoleFrame(location)) } };
 const context = vm.createContext({ window, document, location, URL, URLSearchParams, Uint8Array, FontFace, CSSStyleSheet, MutationObserver,
  atob: text => Buffer.from(text, 'base64').toString('binary'),
  getComputedStyle: () => ({ display: 'block', colorScheme: 'dark', fontFamily: 'sans-serif', fontWeight: '400', direction: 'ltr', backgroundColor: 'black' }),
  setTimeout(fn) { timers.add(fn); return fn; }, clearTimeout(fn) { timers.delete(fn); }, console: { log: value => logs.push(value) },
 }, { codeGeneration: { strings: false, wasm: false } });
 const execute = code => vm.runInContext(`(async()=>{${code}})()`, context, { timeout: 1000 });
 const dispose = () => window.__claudePersianControllerV2?.dispose();
 return { context, window, document, baseline, faces, created, logs, timers, execute, dispose };
}
async function run(f, plan, count = plan.commands.length) { for (const code of plan.commands.slice(0, count)) await f.execute(code); }

test('Direct builder rejects code-shaped parameters and stays within transport limits', () => {
 for (const bad of ['', '__cdt_x;alert(1)', 'wrong', '__cdt_' + 'a'.repeat(60), undefined]) assert.throws(() => buildDirectPlan({ ...options, namespace: bad }), /namespace/);
 for (const bad of ['', 'A'.repeat(32), 'a'.repeat(31), 'a'.repeat(32) + '\n', undefined]) assert.throws(() => buildDirectPlan({ ...options, nonce: bad }), /nonce/);
 for (const bad of ['', 'unknown', 'chat);alert(1)', undefined]) assert.throws(() => buildDirectPlan({ ...options, kind: bad }), /kind/);
 const plan = buildDirectPlan(options);
 assert.ok(plan.commands.length <= 48); assert.ok(plan.commands.length > 25);
 assert.ok(plan.cleanup.length <= 2048);
 for (const command of plan.commands) {
  assert.ok(Buffer.byteLength(command) <= 12000);
  assert.equal(/[\r\n\u2028\u2029]/.test(command), false);
  assert.equal(/\beval\s*\(|new\s+Function\b/.test(command), false);
  new vm.Script(`(async()=>{${command}})()`);
 }
});

test('Full direct plan installs the shared controller and complete official variable font in every supported kind', async () => {
 for (const kind of KINDS) {
  const f = fixture(kind), plan = buildDirectPlan({ ...options, kind });
  assert.equal(classifyFrame(consoleFrame(f.context.location)), kind);
  await run(f, plan);
  const controller = f.window.__claudePersianControllerV2, snapshot = controller.snapshot();
  assert.equal(snapshot.kind, kind); assert.equal(snapshot.healthy, true); assert.equal(snapshot.attachedWeights, 1);
  assert.equal(f.created.length, 1); assert.equal(f.created[0].weight, '100 900');
  assert.deepEqual(Buffer.from(f.created[0].bytes), Buffer.from(font.data, 'base64'));
  assert.equal(f.document.adoptedStyleSheets.length, 2);
  assert.equal(f.document.documentElement.outerHTML, f.baseline, 'stored text, table order and controls remain unchanged');
  await f.execute(plan.cleanup);
  assert.equal(f.window[namespace], undefined, 'font chunks and helper functions are removed');
  assert.equal(f.window.__claudePersianControllerV2, controller, 'successful production controller is retained');
  assert.equal(controller.snapshot().healthy, true);
  assert.equal(f.logs.length, 0, 'plan body does not emit page content or additional receipts');
  f.dispose(); assert.equal(f.faces.size, 0); assert.equal(f.document.adoptedStyleSheets.length, 0); assert.equal(f.timers.size, 0);
 }
});

test('Direct plan refuses existing or replaced namespace ownership and preserves foreign state', async () => {
 const plan = buildDirectPlan(options), f = fixture();
 const existing = { owner: nonce, chunks: ['existing'] }; f.window[namespace] = existing;
 await assert.rejects(f.execute(plan.commands[0]), /namespace-exists/);
 assert.equal(f.window[namespace], existing);
 delete f.window[namespace]; await f.execute(plan.commands[0]);
 const foreign = { owner: 'c'.repeat(32), chunks: ['foreign'] }; f.window[namespace] = foreign;
 for (const code of plan.commands.slice(1)) await assert.rejects(f.execute(code), /namespace-changed/);
 await f.execute(plan.cleanup); assert.equal(f.window[namespace], foreign); assert.equal(f.created.length, 0);
});

test('Direct final application rejects the wrong kind or document identity before installing', async () => {
 for (const mismatch of ['kind', 'document']) {
  const f = fixture(), plan = buildDirectPlan({ ...options, kind: mismatch === 'kind' ? 'document' : 'chat' });
  await run(f, plan, plan.commands.length - 1);
  if (mismatch === 'document') f.window.__claudePersianConsoleDocumentV1.identity = 'different-document';
  await assert.rejects(f.execute(plan.commands.at(-1)), /application-unverified/);
  assert.equal(f.created.length, 0); assert.equal(f.window.__claudePersianControllerV2, undefined);
  await f.execute(plan.cleanup); assert.equal(f.window[namespace], undefined);
 }
});

test('A failed actual controller install is not reported as a successful direct application', async () => {
 const f = fixture('chat', { failFont: true }), plan = buildDirectPlan(options);
 await run(f, plan, plan.commands.length - 1);
 await assert.rejects(f.execute(plan.commands.at(-1)), /application-unverified/);
 assert.equal(f.window.__claudePersianControllerV2, undefined); assert.equal(f.faces.size, 0);
 await f.execute(plan.cleanup); assert.equal(f.window[namespace], undefined); assert.deepEqual(f.logs, []);
});
