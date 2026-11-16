'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { buildExtension, extensionKind, startExtension } = require('../lib/persian/extension-package.cjs');

test('Register nested artifact and opaque document frames without broad permissions', () => {
 const { manifest, source } = buildExtension();
 const script = manifest.content_scripts[0];
 assert.equal(script.all_frames, true);
 assert.equal(script.match_origin_as_fallback, true);
 assert.equal(script.match_about_blank, true);
 assert.deepEqual(script.matches, ['https://claude.ai/*', 'https://*.frame.claudeusercontent.com/*']);
 assert.equal(manifest.permissions, undefined);
 assert.equal(manifest.background, undefined);
 assert.equal(script.run_at, 'document_idle');
 assert.doesNotThrow(() => new vm.Script(source));
 assert.ok(source.includes('__claudePersianExtensionV1'));
 assert.ok(source.includes('Claude Persian Estedad'));
 assert.ok(!/\beval\s*\(|new Function|fetch\s*\(/.test(source));
});

test('Classify real nested frame shapes and refuse unrelated opaque frames', () => {
 assert.equal(extensionKind({ href:'https://claude.ai/chat/example' }), 'chat');
 assert.equal(extensionKind({ href:'https://claude.ai/code/artifact/example' }), 'artifact');
 assert.equal(extensionKind({ href:'https://example.frame.claudeusercontent.com/_f/' }), 'artifact-content');
 assert.equal(extensionKind({ href:'about:srcdoc', ancestorOrigins:['https://example.frame.claudeusercontent.com','https://claude.ai'] }), 'document');
 for (const href of ['https://example.org/', 'https://claude.ai/login', 'https://claude.ai/api/x', 'about:blank', 'file:///tmp/x']) {
  assert.equal(extensionKind({ href }), null);
 }
 assert.equal(extensionKind({ href:'about:srcdoc', ancestorOrigins:['https://example.org'] }), null);
 assert.equal(extensionKind({ href:'about:srcdoc', get ancestorOrigins(){ throw Error('inaccessible'); } }), null);
});

test('Extension lifecycle waits for installation before disposing owned resources', async () => {
 const window = {};
 const context = vm.createContext({ window, location:{href:'https://claude.ai/chat/example'}, Promise });
 const start = vm.runInContext(`(${startExtension.toString()})`, context);
 let release, installs=0, disposals=0;
 const pending = new Promise(resolve => { release=resolve; });
 const install = async () => {
  installs++;
  await pending;
  window.__claudePersianControllerV2 = {
   snapshot:() => ({ healthy:true }),
   dispose:async () => { disposals++; delete window.__claudePersianControllerV2; },
  };
 };
 const first = start(()=>'document', l=>l, install);
 await Promise.resolve();
 await start(()=>'document', l=>l, install);
 assert.equal(installs,1);
 const disposing = window.__claudePersianExtensionV1.dispose();
 assert.equal(disposals,0);
 release();
 await first;
 await disposing;
 assert.equal(disposals,1);
 assert.equal(window.__claudePersianControllerV2,undefined);
 assert.equal(window.__claudePersianExtensionV1,undefined);
});

test('Unsupported frames do nothing and failed installation is reported without private errors', async () => {
 const window = {};
 const context = vm.createContext({ window, location:{href:'https://example.org'}, Promise });
 const start = vm.runInContext(`(${startExtension.toString()})`, context);
 let calls=0;
 assert.equal(await start(()=>null,l=>l,()=>{calls++;}),null);
 assert.equal(calls,0);
 const result=await start(()=>'chat',l=>l,async()=>{throw Error('private detail');});
 assert.equal(result.failed,true);
 assert.equal(JSON.stringify(result).includes('private detail'),false);
 await window.__claudePersianExtensionV1.dispose();
 assert.equal(window.__claudePersianExtensionV1,undefined);
});
