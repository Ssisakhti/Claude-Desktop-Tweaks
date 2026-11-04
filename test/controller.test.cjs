'use strict';
// Test the controller contract with a simulated DOM and FontFace implementation.
// Validate actual font loading and Chromium rendering separately.
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const { parseHTML } = require('linkedom');
const { estimateDirection, stableDirection } = require('../lib/persian/direction.cjs');
const { nordThemeCss } = require('../lib/persian/nord.cjs');
const { CONTROLLER_REVISION,installController } = require('../lib/persian/controller.cjs');
const weights = [100,200,300,400,500,600,700,800,900];
const fonts = weights.map(weight => ({ weight, data: Buffer.from([0,1,2,3]).toString('base64') }));
const key = '__claudePersianControllerV2';

function deferred() {
 let resolve; const promise = new Promise(done => { resolve = done; });
 return { promise, resolve };
}
function fixture({ gate = null, failWeight = null, directionRegression = false, shellDark = false, historyCount = 0 } = {}) {
 const { document } = parseHTML(`<!doctype html><html class="${shellDark ? '' : 'dark'}"><head></head><body${shellDark ? ' class="darkTheme"' : ''}>
   <aside${directionRegression ? ' dir="rtl"' : ''}><button id="project" data-native-font='"Sidebar Native", sans-serif'>پروژهٔ فارسی</button></aside>
   <main>${Array.from({length:historyCount},(_,i)=>`<div data-testid="assistant-message"><p id="history-${i}">این پیام قدیمی شمارهٔ ${i} است.</p></div>`).join('')}<div data-testid="assistant-message">
     <h1 id="heading" data-native-font='"Native Heading", serif'>API عنوان فارسی برای بررسی</h1>
     <p id="paragraph" data-native-font='"Native Body", sans-serif'>API باید این متن فارسی را درست نمایش دهد.</p>
     ${directionRegression ? `<div data-ask-user-question><div id="question-flex" style="display:flex"><div style="display:contents"><span id="question-span" dir="ltr">API کدام روش برای این آزمایش مناسب است؟</span><span id="answer-span" dir="ltr">روش اول برای این آزمایش مناسب است.</span></div></div></div><p id="generated-ltr" dir="ltr">API این نمونه درخواست‌های کاربران را ثبت می‌کند. سپس، نتیجه را در یک جدول ساده نشان می‌دهد</p>
     <p id="generated-rtl" dir="rtl">This example records incoming requests and displays the results in a simple table.</p>
     <table id="regression-table" dir="ltr"><tbody><tr id="regression-row"><td id="first-cell" dir="ltr">این ستون فارسی است.</td><td id="second-cell" dir="rtl">English cell content remains readable.</td></tr></tbody></table>` : ''}
     <button id="action" data-native-font='"Native Button", sans-serif'>دکمهٔ فارسی</button>
     <pre><code id="code" data-native-font='"Native Mono", monospace'>const نام = 1;</code></pre>
   </div><div data-testid="chat-input" contenteditable="true"><p id="input" data-native-font='"Input Native", sans-serif'>پیام فارسی من</p></div></main>
  </body></html>`);
 const state = { faces: [], added: [], sheets: [], observers: [], timers: [], listeners: [], removedListeners: [], failWeight, mutations: [], computed: [] };
 const window = {};
 const baseline = document.toString();
 const originalAddEventListener = document.addEventListener.bind(document);
 document.addEventListener = (type, listener, options) => { state.listeners.push(type); return originalAddEventListener(type, listener, options); };
 const originalRemoveEventListener=document.removeEventListener.bind(document);
 document.removeEventListener=(type,listener,options)=>{state.removedListeners.push(type);return originalRemoveEventListener(type,listener,options);};
 Object.defineProperty(document, 'adoptedStyleSheets', { configurable:true, get: () => state.sheets, set:value => { state.sheets=value; } });
 Object.defineProperty(document, 'fonts', { configurable:true, value: { add(face) { if(!state.added.includes(face))state.added.push(face); }, has(face) { return state.added.includes(face); }, delete(face) { const i=state.added.indexOf(face); if(i>=0)state.added.splice(i,1); return i>=0; }, check() { return weights.every(weight => state.added.some(face => face.weight === String(weight))); } } });
 for (const el of document.querySelectorAll('*')) {
  el.setAttribute = (...args) => { state.mutations.push(['setAttribute',args[0]]); throw new Error('Unexpected DOM mutation'); };
  el.removeAttribute = (...args) => { state.mutations.push(['removeAttribute',args[0]]); throw new Error('Unexpected DOM mutation'); };
  el.appendChild = () => { state.mutations.push(['appendChild']); throw new Error('Unexpected DOM mutation'); };
 }
 class FontFace {
  constructor(family, bytes, options) { Object.assign(this,{family,bytes,...options}); state.faces.push(this); }
  async load() {
   if (gate) await gate.promise;
   if (this.weight === String(state.failWeight)) throw new Error('simulated font decode failure');
   this.status='loaded';
   return this;
  }
 }
 class CSSStyleSheet {
  constructor() { this.css=''; this.disabled=false; }
  replaceSync(css) { this.css=css; }
 }
 class MutationObserver {
  constructor(callback) { this.callback=callback; state.observers.push(this); }
  observe(target,options) { this.target=target; this.options=options; }
  disconnect() { this.disconnected=true; }
 }
 function getComputedStyle(el) {
  state.computed.push(el.id);
  const computed = {
   fontFamily: el.getAttribute('data-native-font') || '"Native Default", sans-serif',
   direction:el.closest('[dir]')?.getAttribute('dir') || 'ltr', display:el.style.display || (el.localName==='button'?'inline-block':'block'),
   colorScheme:el===document.documentElement&&!shellDark?'dark':'normal', backgroundColor:'rgb(46, 52, 64)', fontWeight:'400'
  };
  for (const sheet of state.sheets) {
   if (sheet.disabled) continue;
   for (const [,selector,body] of sheet.css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    let matches=false;
    try { matches=el.matches(selector.trim()); } catch {}
    if (!matches) continue;
    const family=body.match(/font-family:([^;]+?)(?:!important)?;/);
    const direction=body.match(/direction:(rtl|ltr)/);
    if (family) computed.fontFamily=family[1].replace(/!important$/,'').trim();
    if (direction) computed.direction=direction[1];
   }
  }
  return computed;
 }
 const context=vm.createContext({
  window, document, FontFace, CSSStyleSheet, MutationObserver, Uint8Array, URLSearchParams,
  location:{search:shellDark?'':'?m=dark'}, getComputedStyle,
  atob:value=>Buffer.from(value,'base64').toString('binary'),
  setTimeout(callback,delay) { const timer={callback,delay,cleared:false}; state.timers.push(timer); return timer; },
  clearTimeout(timer) { if(timer)timer.cleared=true; },
  module:{exports:{}}
 });
 vm.runInContext(fs.readFileSync(path.join(__dirname,'../lib/persian/scope.cjs'),'utf8'),context);
 const scope=context.module.exports;
 context.module={exports:{}};
 vm.runInContext(fs.readFileSync(path.join(__dirname,'../lib/persian/controller.cjs'),'utf8'),context);
 return { document, window, state, baseline, context, apply:context.module.exports.installController, scope, bidi:{estimateDirection,stableDirection}, nord:{nordThemeCss}, getComputedStyle };
}

test('Snapshots and standalone toString functions match the module revision',async()=>{
 const f=fixture();
 assert.equal(CONTROLLER_REVISION,3);
 assert.equal(installController.revision,CONTROLLER_REVISION);
 assert.equal(f.apply.revision,CONTROLLER_REVISION);
 const serialized=vm.runInContext('('+f.apply.toString()+')',f.context);
 assert.equal(serialized.revision,undefined,'serialized function has no module properties');
 const installed=await serialized({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 assert.equal(installed.revision,CONTROLLER_REVISION);
 assert.equal(f.window[key].snapshot().revision,CONTROLLER_REVISION);
 assert.equal(installed.healthy,true);
});

test('Dispose healthy older controllers before installing the timer-enabled revision',async()=>{
 const f=fixture();let stopped=0;
 const old={snapshot:()=>({healthy:true,fontLoaded:true,stylesAttached:true}),dispose(){
  if(f.window[key]===old){stopped++;delete f.window[key];}
 }};
 f.window[key]=old;
 const results=await Promise.all([f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord),f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord)]);
 for(const result of results){assert.equal(result.revision,CONTROLLER_REVISION);assert.equal(result.healthy,true);}
 assert.equal(stopped,1);assert.notEqual(f.window[key],old);
 assert.equal(f.state.faces.length,9);assert.equal(f.state.observers.length,1);
 assert.equal(f.state.timers.filter(timer=>timer.delay===1500&&!timer.cleared).length,1);
});

test('Older controllers without verified removal cannot cause duplicate installs or upgrade loops',async()=>{
 for(const dispose of [undefined,()=>{}]){
  const f=fixture(),old={snapshot:()=>({healthy:true}),dispose};f.window[key]=old;
  await assert.rejects(f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord),/cannot be upgraded safely|did not stop/);
  assert.equal(f.window[key],old);assert.equal(f.state.faces.length,0);assert.equal(f.state.timers.length,0);
 }
});

test('Concurrent installation creates nine font faces, one observer, and two stylesheets', async()=>{
 const gate=deferred(),f=fixture({gate});
 const first=f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 const second=f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 assert.equal(f.state.faces.length,9);
 assert.equal(typeof f.window[key].then,'function');
 assert.equal(f.state.observers.length,0);
 gate.resolve();
 const [a,b]=await Promise.all([first,second]);
 assert.equal(a.fontLoaded,true); assert.equal(b.fontLoaded,true);
 assert.equal(f.state.faces.length,9); assert.equal(f.state.added.length,9);
 assert.equal(f.state.observers.length,1); assert.equal(f.state.sheets.length,2);
 assert.equal(a.passes,1); assert.equal(b.passes,1);
 await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 assert.equal(f.state.faces.length,9); assert.equal(f.state.observers.length,1); assert.equal(f.state.sheets.length,2);
});

test('Preserve original fallback fonts separately for paragraphs, headings, and buttons', async()=>{
 const f=fixture();
 await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 for(const [id,native] of [['paragraph','Native Body'],['heading','Native Heading'],['action','Native Button'],['project','Sidebar Native']]) {
  const font=f.getComputedStyle(f.document.getElementById(id)).fontFamily;
  assert.ok(font.startsWith('"Claude Persian Estedad",'),`${id}: ${font}`);
  assert.ok(font.includes(`"${native}"`),`${id}: ${font}`);
 }
 assert.equal(f.getComputedStyle(f.document.getElementById('code')).fontFamily,'"Native Mono", monospace');
 assert.equal(f.getComputedStyle(f.document.getElementById('project')).direction,'ltr');
 assert.equal(f.getComputedStyle(f.document.getElementById('action')).direction,'ltr');
});

test('Install and refresh preserve document text, HTML, and attributes', async()=>{
 const f=fixture();
 await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 f.window[key].refresh();
 assert.equal(f.document.toString(),f.baseline);
 assert.deepEqual(f.state.mutations,[]);
 assert.equal(f.state.sheets.length,2);
});

test('Refresh does not repeatedly append fallback font names',async()=>{
 const f=fixture();
 await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 f.window[key].refresh(); f.window[key].refresh();
 const family=f.getComputedStyle(f.document.getElementById('paragraph')).fontFamily;
 assert.equal(family.split('Claude Persian Estedad').length-1,1);
 assert.ok(family.includes('Native Body'));
});

test('Actual health detects missing font weights and missing or disabled stylesheets',async()=>{
 const f=fixture();
 const installed=await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 const controller=f.window[key];
 assert.equal(installed.healthy,true);assert.equal(installed.stylesLoaded,true);
 assert.equal(installed.stylesAttached,true);assert.equal(installed.attachedWeights,9);
 assert.deepEqual(Array.from(installed.weights),weights.map(String));
 // A fallback font can make check succeed. Verify membership of each face separately.
 f.document.fonts.check=()=>true;
 for(const face of f.state.faces){
  f.document.fonts.delete(face);
  const missing=controller.snapshot();
  assert.equal(missing.fontLoaded,false,face.weight);
  assert.equal(missing.healthy,false,face.weight);
  assert.equal(missing.weights.length,8);
  assert.equal(missing.attachedWeights,8);
  assert.ok(!missing.weights.includes(face.weight));
  f.document.fonts.add(face);
 }
 const face=f.state.faces[0];face.status='loading';
 assert.equal(controller.snapshot().fontLoaded,false);
 face.status='loaded';
 const owned=[...f.state.sheets];
 for(const sheet of owned){
  f.document.adoptedStyleSheets=owned.filter(item=>item!==sheet);
  assert.equal(controller.snapshot().stylesLoaded,false);
  assert.equal(controller.snapshot().stylesAttached,false);
  assert.equal(controller.snapshot().fontLoaded,true);
  assert.equal(controller.snapshot().healthy,false);
  f.document.adoptedStyleSheets=[...owned];
  sheet.disabled=true;
  assert.equal(controller.snapshot().stylesLoaded,false);
  assert.equal(controller.snapshot().stylesAttached,true);
  sheet.disabled=false;
 }
 assert.equal(controller.snapshot().healthy,true);
});

test('Refresh restores removed styles and fonts without duplication or removing app resources',async()=>{
 const f=fixture();
 const nativeBefore={css:'',native:true},nativeAfter={css:'',native:true};
 const nativeFace={weight:'native'};
 f.document.adoptedStyleSheets=[nativeBefore];f.document.fonts.add(nativeFace);
 await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 const controller=f.window[key],owned=f.state.sheets.filter(sheet=>sheet!==nativeBefore);
 const paragraph=f.document.getElementById('paragraph');
 f.document.adoptedStyleSheets=[nativeBefore,nativeAfter];
 f.document.fonts.delete(f.state.faces[4]);
 assert.equal(f.getComputedStyle(paragraph).direction,'ltr');
 controller.refresh();
 assert.equal(controller.snapshot().healthy,true);
 assert.equal(f.getComputedStyle(paragraph).direction,'rtl');
 assert.deepEqual(Array.from(f.document.adoptedStyleSheets),[nativeBefore,nativeAfter,...owned]);
 assert.equal(f.state.added.length,10);assert.ok(f.document.fonts.has(nativeFace));
 for(let i=0;i<3;i++)controller.refresh();
 assert.deepEqual(Array.from(f.document.adoptedStyleSheets),[nativeBefore,nativeAfter,...owned]);
 assert.equal(f.state.faces.length,9);assert.equal(f.state.added.length,10);
 assert.equal(f.state.observers.length,1);assert.equal(f.document.toString(),f.baseline);
 controller.dispose();
 assert.deepEqual(Array.from(f.document.adoptedStyleSheets),[nativeBefore,nativeAfter]);
 assert.deepEqual(f.state.added,[nativeFace]);
 controller.refresh();
 assert.equal(controller.snapshot().healthy,false);
 assert.equal(controller.snapshot().fontLoaded,false);
 assert.equal(controller.snapshot().stylesLoaded,false);
 assert.deepEqual(Array.from(f.document.adoptedStyleSheets),[nativeBefore,nativeAfter]);
 assert.deepEqual(f.state.added,[nativeFace]);
});

test('Reinstallation restores unhealthy controllers without rescanning healthy controllers',async()=>{
 const f=fixture();
 await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 const controller=f.window[key],owned=[...f.state.sheets];
 f.document.adoptedStyleSheets=[owned[0]];owned[0].disabled=true;
 f.document.fonts.delete(f.state.faces[0]);
 const repaired=await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 assert.equal(repaired.healthy,true);assert.equal(repaired.weights.length,9);
 assert.equal(f.window[key],controller);assert.equal(f.state.faces.length,9);
 assert.equal(f.state.observers.length,1);assert.equal(f.state.sheets.length,2);
 assert.equal(repaired.passes,2);
 const repeated=await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 assert.equal(repeated.passes,2);assert.equal(f.state.added.length,9);
 assert.deepEqual(Array.from(f.document.adoptedStyleSheets),owned);
});

test('Passive checks restore removed resources without commands or healthy-document scans',async()=>{
 const f=fixture();
 const native={css:'',native:true};f.document.adoptedStyleSheets=[native];
 await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 const controller=f.window[key];
 const tick=()=>{
  const pending=f.state.timers.filter(timer=>timer.delay===1500&&!timer.cleared);
  assert.equal(pending.length,1,'one pending health timer');
  pending[0].cleared=true;pending[0].callback();
 };
 const initial=controller.snapshot();f.state.computed.length=0;
 for(let i=0;i<4;i++)tick();
 assert.equal(f.state.computed.length,0,'healthy checks do not read computed styles or scan DOM');
 assert.equal(controller.snapshot().fullPasses,initial.fullPasses);
 f.document.adoptedStyleSheets=[native];
 for(const face of f.state.faces)f.document.fonts.delete(face);
 tick();
 const repaired=controller.snapshot();
 assert.equal(repaired.healthy,true);assert.equal(repaired.attachedWeights,9);
 assert.equal(repaired.fullPasses,initial.fullPasses+1);
 assert.equal(f.document.adoptedStyleSheets[0],native);
 assert.equal(f.document.adoptedStyleSheets.length,3);assert.equal(f.state.faces.length,9);
 assert.equal(f.getComputedStyle(f.document.getElementById('paragraph')).direction,'rtl');
 tick();assert.equal(controller.snapshot().fullPasses,repaired.fullPasses);
 controller.dispose();
 assert.ok(f.state.timers.every(timer=>timer.cleared));
 const timerCount=f.state.timers.length;
 for(const timer of [...f.state.timers])if(timer.delay===1500)timer.callback();
 assert.equal(f.state.timers.length,timerCount,'disposed health callbacks cannot restart polling');
 assert.deepEqual(Array.from(f.document.adoptedStyleSheets),[native]);
 assert.equal(f.state.added.length,0);
});

test('Passive checks defer during composition and recover after composition ends',async()=>{
 const f=fixture();
 await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 const controller=f.window[key],input=f.document.getElementById('input');
 const tick=()=>{
  const pending=f.state.timers.filter(timer=>timer.delay===1500&&!timer.cleared);
  assert.equal(pending.length,1);pending[0].cleared=true;pending[0].callback();
 };
 input.dispatchEvent(new (f.document.defaultView.Event)('compositionstart',{bubbles:true}));
 f.document.adoptedStyleSheets=[];f.document.fonts.delete(f.state.faces[0]);
 const passes=controller.snapshot().passes;
 tick();tick();
 assert.equal(f.document.adoptedStyleSheets.length,0);assert.equal(f.state.added.length,8);
 assert.equal(controller.snapshot().passes,passes);
 input.dispatchEvent(new (f.document.defaultView.Event)('compositionend',{bubbles:true}));
 tick();
 assert.equal(controller.snapshot().healthy,true);
 assert.equal(controller.snapshot().passes,passes+1);
 assert.equal(f.document.toString(),f.baseline);
 controller.dispose();assert.ok(f.state.timers.every(timer=>timer.cleared));
});

test('Font loading failure clears pending state and permits reinstallation',async()=>{
 const f=fixture({failWeight:400});
 await assert.rejects(f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord),/simulated font decode failure/);
 assert.equal(Object.hasOwn(f.window,key),false);
 await Promise.resolve();
 assert.equal(f.state.added.length,0);
 assert.equal(f.state.observers.length,0);assert.equal(f.state.sheets.length,0);
 f.state.failWeight=null;
 const result=await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 assert.equal(result.fontLoaded,true);assert.equal(f.state.observers.length,1);assert.equal(f.state.sheets.length,2);
});


test('Visual paragraph and cell direction overrides Claude direction while preserving HTML and UI order',async()=>{
 const f=fixture({directionRegression:true});
 const el=id=>f.document.getElementById(id);
 // Read initial direction from the real document attribute and verify the visual override.
 assert.equal(f.getComputedStyle(el('generated-ltr')).direction,'ltr');
 assert.equal(f.getComputedStyle(el('generated-rtl')).direction,'rtl');
 const order=[...el('regression-row').children].map(cell=>cell.id);
 await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 for(const [id,attribute,display] of [
  ['generated-ltr','ltr','rtl'],['generated-rtl','rtl','ltr'],
  ['first-cell','ltr','rtl'],['second-cell','rtl','ltr'],
  ['question-span','ltr','rtl'],['answer-span','ltr','rtl']
 ]) {
  assert.equal(el(id).getAttribute('dir'),attribute,`${id}: original dir attribute`);
  assert.equal(f.getComputedStyle(el(id)).direction,display,`${id}: display direction`);
 }
 assert.equal(f.getComputedStyle(el('project')).direction,'rtl');
 assert.equal(f.getComputedStyle(el('action')).direction,'ltr');
 assert.equal(f.getComputedStyle(el('question-flex')).direction,'ltr');
 assert.equal(f.getComputedStyle(el('regression-table')).direction,'ltr');
 assert.equal(f.getComputedStyle(el('regression-row')).direction,'ltr');
 assert.deepEqual([...el('regression-row').children].map(cell=>cell.id),order);
 f.window[key].refresh();
 assert.equal(f.getComputedStyle(el('generated-ltr')).direction,'rtl');
 assert.equal(f.getComputedStyle(el('generated-rtl')).direction,'ltr');
 assert.equal(f.document.toString(),f.baseline);
 assert.deepEqual(f.state.mutations,[]);
});


test('Apply Nord to darkTheme body shells and remove it in light mode',async()=>{
 const f=fixture({shellDark:true});
 assert.equal(f.getComputedStyle(f.document.documentElement).colorScheme,'normal');
 assert.equal(f.document.documentElement.className,'');
 assert.equal(f.document.body.className,'darkTheme');
 const result=await f.apply({kind:'shell'},fonts,f.scope,f.bidi,f.nord);
 assert.equal(result.dark,true);
 assert.equal(f.state.sheets[0].css,f.nord.nordThemeCss({forceDark:true}));
 assert.ok(f.state.sheets[0].css.length>0);
 assert.equal(f.document.toString(),f.baseline);
 // The page changes its own mode. Mutation guards remain active for controller code.
 const nativeSetAttribute=Object.getPrototypeOf(f.document.body).setAttribute;
 nativeSetAttribute.call(f.document.body,'class','');
 nativeSetAttribute.call(f.document.documentElement,'class','lightTheme');
 const lightBaseline=f.document.toString();
 f.state.observers[0].callback([{type:'attributes',attributeName:'class',target:f.document.body}]);
 const refreshTimer=f.state.timers.find(timer=>timer.delay===180&&!timer.cleared);
 assert.ok(refreshTimer,'body class change schedules a refresh');
 refreshTimer.callback();
 assert.equal(f.window[key].snapshot().dark,false);
 assert.equal(f.state.sheets[0].css,'');
 assert.equal(f.document.toString(),lightBaseline);
 assert.deepEqual(f.state.mutations,[]);
});


test('Updating one paragraph in a 300-message chat does not reprocess earlier paragraphs',async()=>{
 const f=fixture({historyCount:300});
 const initial=await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 assert.ok(initial.scannedBlocks>=300);
 f.state.computed.length=0;
 const paragraph=f.document.getElementById('paragraph');
 paragraph.firstChild.data='این متن پس از دریافت بخش تازهٔ پاسخ تغییر کرد.';
 f.state.observers[0].callback([{type:'characterData',target:paragraph.firstChild}]);
 f.state.timers.find(timer=>timer.delay===180&&!timer.cleared).callback();
 const active=f.window[key].snapshot();
 assert.equal(active.partialPasses,1);
 assert.equal(active.scannedBlocks,1);
 assert.ok(!f.state.computed.some(id=>/^history-/.test(id)&&Number(id.slice(8))>=8));
 assert.ok(f.getComputedStyle(f.document.getElementById('history-299')).fontFamily.includes('Claude Persian Estedad'));
 f.state.timers.filter(timer=>timer.delay===1000&&!timer.cleared).at(-1).callback();
 assert.equal(f.window[key].snapshot().partialPasses,2);
});

test('Structural changes rebuild positional selectors and remove deleted targets',async()=>{
 const f=fixture({historyCount:2});
 await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 const removed=f.document.getElementById('history-0').parentElement;
 removed.remove();
 f.state.observers[0].callback([{type:'childList',target:f.document.querySelector('main'),addedNodes:[],removedNodes:[removed]}]);
 f.state.timers.find(timer=>timer.delay===180&&!timer.cleared).callback();
 assert.equal(f.window[key].snapshot().fullPasses,2);
 assert.equal(f.getComputedStyle(f.document.getElementById('history-1')).direction,'rtl');
 assert.ok(f.getComputedStyle(f.document.getElementById('paragraph')).fontFamily.includes('Claude Persian Estedad'));
});


test('Disposal removes owned fonts, CSS, and listeners and permits reinstallation',async()=>{
 const f=fixture();
 const nativeSheet={native:true,css:''},nativeFace={weight:'native'};
 f.document.adoptedStyleSheets=[nativeSheet];f.document.fonts.add(nativeFace);
 await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 const controller=f.window[key],observer=f.state.observers[0];
 assert.equal(f.getComputedStyle(f.document.getElementById('paragraph')).direction,'rtl');
 controller.dispose();controller.dispose();
 assert.equal(observer.disconnected,true);
 assert.equal(f.document.adoptedStyleSheets.length,1);assert.equal(f.document.adoptedStyleSheets[0],nativeSheet);
 assert.deepEqual(f.state.added,[nativeFace]);
 assert.equal(f.window[key],undefined);
 assert.deepEqual(f.state.removedListeners,['compositionstart','compositionend','input']);
 assert.ok(f.state.timers.every(timer=>timer.cleared));
 const timerCount=f.state.timers.length;
 f.document.getElementById('input').dispatchEvent(new (f.document.defaultView.Event)('input',{bubbles:true}));
 for(const timer of [...f.state.timers])timer.callback();
 observer.callback([{type:'childList',target:f.document.querySelector('main')}]);
 controller.refresh();
 assert.equal(f.state.timers.length,timerCount);
 assert.equal(f.document.adoptedStyleSheets.length,1);assert.equal(f.document.adoptedStyleSheets[0],nativeSheet);
 assert.equal(f.getComputedStyle(f.document.getElementById('paragraph')).direction,'ltr');
 assert.equal(f.document.toString(),f.baseline);
 await f.apply({kind:'chat'},fonts,f.scope,f.bidi,f.nord);
 assert.equal(f.document.adoptedStyleSheets.length,3);
 assert.equal(f.state.added.length,10);
 assert.equal(f.getComputedStyle(f.document.getElementById('paragraph')).direction,'rtl');
});
