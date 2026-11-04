'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { parseHTML } = require('linkedom');
const { findSurfaces, isExcluded, contentText, selectorFor, collectTargets } = require('../lib/persian/scope.cjs');

function fixture() {
  return parseHTML(`<!doctype html><html><head><title>نمونه</title></head><body>
    <header dir="ltr"><h1 id="ui-title">عنوان فارسی چت</h1></header><nav dir="ltr"><div data-testid="user-message"><p id="project">پروژهٔ فارسی</p></div><button id="chat-name">نام چت</button><p id="sidebar-english">English project</p><p id="sidebar-mixed">API پروژه</p></nav>
    <aside><p id="sidebar">جلسهٔ فارسی</p></aside>
    <main>
      <div data-testid="user-message" id="user"><p id="user-p">API این متن فارسی است.</p><div role="toolbar"><p id="user-tool">ابزار پیام</p></div></div>
      <div data-testid="assistant-message" id="assistant"><p id="reply">پاسخ فارسی با <strong id="strong">متن ضخیم</strong> و <code id="inline-code">const value = true</code></p>
        <h2 id="heading">عنوان فارسی</h2><blockquote><p id="quote">نقل‌قول فارسی</p></blockquote>
        <ul><li id="list-item">مورد فارسی</li></ul>
        <table id="table"><thead><tr id="head-row"><th id="head-one">ستون اول</th><th id="head-two">ستون دوم</th></tr></thead>
          <tbody><tr id="row"><td id="cell-one">گزارش فارسی</td><td id="cell-two"><p id="cell-p">English value</p></td></tr></tbody></table>
        <pre id="pre"><code id="code">function demo() { return 1; }</code></pre>
        <span class="katex" id="math"><span id="math-inner">x = 2</span></span><math id="mathml"><mi>x</mi></math>
        <button id="button">کپی پاسخ</button><span class="lucide-copy" id="icon">نماد</span><svg><text id="svg-text">نماد</text></svg>
        <div data-testid="message-actions"><p id="actions-text">عملیات پیام</p></div>
      </div>
      <div data-testid="chat-input" contenteditable="true" id="input"><p id="input-p">این ورودی فارسی است.</p></div>
      <div data-testid="user-message" id="plain-user">متن مستقیم پیام کاربر</div>
      <div data-testid="assistant-message" style="display:flex" id="flex-surface"><span id="flex-text">متن در ظرف فلکس</span></div>
      <div data-testid="assistant-message" style="display:grid" id="grid-surface"><span id="grid-text">متن در ظرف گرید</span></div>
      <section aria-label="Artifact">
        <div role="toolbar"><p id="doc-toolbar">نوار ابزار سند</p><textarea placeholder="نباید هدف شود" id="toolbar-input"></textarea></div>
        <article><div class="tiptap ProseMirror" contenteditable="true" id="document-editor"><h1 id="doc-heading">عنوان سند</h1><p id="doc-p">متن فارسی سند</p>
          <table id="doc-table"><tbody><tr id="doc-row"><td id="doc-cell-one">یک</td><td id="doc-cell-two"><p id="doc-cell-p">دو</p></td></tr></tbody></table>
          <code id="doc-code">const متن = 2</code></div></article>
        <section aria-label="Comments">
          <div class="ProseMirror" contenteditable="true" id="comment-composer"><p id="comment-p">کامنت فارسی من</p></div>
          <textarea placeholder="Write a comment" id="comment-textarea">متن کامنت</textarea>
          <div class="ldoc-comment-body" id="comment-body"><p id="comment-body-p">کامنت ثبت‌شده</p></div>
          <div data-testid="comment-content" id="comment-testid"><p id="comment-testid-p">پاسخ کامنت</p></div>
          <div class="comment-content" id="comment-class"><p id="comment-class-p">کامنت دیگر</p></div>
          <button id="comment-send">ارسال کامنت</button>
        </section>
      </section>
    </main>
  </body></html>`).document;
}

function collect(doc, kind) {
  const original = global.getComputedStyle;
  global.getComputedStyle = element => ({ display: element.style.display || 'block' });
  try { return collectTargets(doc, kind); }
  finally {
    if (original === undefined) delete global.getComputedStyle;
    else global.getComputedStyle = original;
  }
}
const ids = elements => elements.map(element => element.id).filter(Boolean);

// Accept DOM candidates only within a verified content surface.
test('Message content gets direction while Persian UI labels receive fonts only', () => {
  const doc = fixture();
  const targets = collect(doc, 'chat');
  assert.ok(ids(targets.surfaces).includes('user'));
  assert.ok(ids(targets.surfaces).includes('assistant'));
  assert.ok(ids(targets.surfaces).includes('input'));
  assert.ok(ids(targets.fonts).includes('user-p'));
  assert.ok(ids(targets.fonts).includes('reply'));
  assert.ok(ids(targets.fonts).includes('strong'));
  assert.ok(ids(targets.blocks).includes('input-p'));
  assert.ok(ids(targets.blocks).includes('plain-user'));
  for (const id of ['project','sidebar','user-tool','actions-text']) {
    assert.ok(ids(targets.fonts).includes(id), id);
    assert.ok(!ids(targets.blocks).includes(id), id);
  }
  for (const id of ['ui-title','chat-name','sidebar-mixed']) {
    assert.ok(ids(targets.fonts).includes(id), id);
    assert.ok(!ids(targets.blocks).includes(id), id);
  }
  assert.ok(!ids(targets.fonts).includes('sidebar-english'));
  for (const root of targets.surfaces) assert.equal(root.closest('nav,aside,header,[role=toolbar]'), null);
});

test('Preserve code, math, and icon fonts; buttons can receive Persian fonts only', () => {
  const doc = fixture();
  const targets = collect(doc, 'chat');
  for (const id of ['inline-code','pre','code','math','math-inner','mathml','icon','svg-text']) {
    assert.equal(isExcluded(doc.getElementById(id)), true, id);
    assert.ok(!ids(targets.fonts).includes(id), id);
    assert.ok(!ids(targets.blocks).includes(id), id);
  }
  assert.equal(isExcluded(doc.getElementById('button')), true);
  assert.ok(ids(targets.fonts).includes('button'));
  assert.ok(!ids(targets.blocks).includes('button'));
});

test('Preserve table order and target only paragraphs or cell text', () => {
  const doc = fixture();
  const orderBefore = [...doc.getElementById('row').children].map(el => el.id);
  const targets = collect(doc, 'chat');
  const blocks = ids(targets.blocks);
  for (const id of ['head-one','head-two','cell-one','cell-p']) assert.ok(blocks.includes(id), id);
  for (const id of ['table','head-row','row','cell-two']) assert.ok(!blocks.includes(id), id);
  assert.deepEqual([...doc.getElementById('row').children].map(el => el.id), orderBefore);
});

test('Do not add direction to message flex and grid containers', () => {
  const targets = collect(fixture(), 'chat');
  for (const id of ['flex-surface','grid-surface']) assert.ok(!ids(targets.blocks).includes(id), id);
  assert.ok(ids(targets.fonts).includes('flex-text'));
  assert.ok(ids(targets.fonts).includes('grid-text'));
});

test('Identify article documents and comment content without toolbars', () => {
  const doc = fixture();
  const targets = collect(doc, 'document');
  for (const id of ['document-editor','comment-composer','comment-textarea','comment-body','comment-testid','comment-class']) assert.ok(ids(targets.surfaces).includes(id), id);
  for (const id of ['doc-heading','doc-p','doc-cell-one','doc-cell-p','comment-p','comment-body-p']) assert.ok(ids(targets.blocks).includes(id), id);
  for (const id of ['doc-toolbar','comment-send']) {
    assert.ok(!ids(targets.blocks).includes(id), id);
    assert.ok(ids(targets.fonts).includes(id), id);
  }
  for (const id of ['toolbar-input','doc-table','doc-row','doc-cell-two','doc-code']) {
    assert.ok(!ids(targets.blocks).includes(id), id);
    assert.ok(!ids(targets.fonts).includes(id), id);
  }
});

test('Cover comments in artifact-content and artifact frames', () => {
  const doc = fixture();
  for (const kind of ['artifact-content','artifact']) {
    const targets = collect(doc, kind);
    for (const id of ['comment-composer','comment-textarea','comment-body','comment-testid','comment-class']) assert.ok(ids(targets.surfaces).includes(id), `${kind}: ${id}`);
    for (const id of ['comment-p','comment-body-p','comment-testid-p','comment-class-p','comment-textarea']) assert.ok(ids(targets.blocks).includes(id), `${kind}: ${id}`);
    assert.ok(ids(targets.fonts).includes('project'));
    assert.ok(!ids(targets.blocks).includes('project'));
    assert.ok(!ids(targets.blocks).includes('sidebar'));
    assert.ok(!ids(targets.blocks).includes('ui-title'));
  }
});

test('Exclude code, math, and message actions from contentText direction votes', () => {
  const doc = fixture();
  const value = contentText(doc.getElementById('assistant'));
  assert.ok(value.includes('پاسخ فارسی'));
  assert.ok(value.includes('متن ضخیم'));
 for (const unwanted of ['const value', 'function demo', 'x = 2', 'کپی پاسخ', 'عملیات پیام']) assert.ok(!value.includes(unwanted), 'Exclude code and message actions from direction votes');
});

test('selectorFor resolves each target back to the same element', () => {
  const doc = fixture();
  for (const kind of ['chat','document','artifact-content']) {
    const targets = collect(doc, kind);
    for (const el of [...targets.fonts,...targets.blocks]) {
      const selector = selectorFor(el);
      assert.ok(selector, el.id);
      assert.equal(doc.querySelector(selector), el, `${el.id}: ${selector}`);
    }
  }
  assert.equal(doc.querySelector(selectorFor(doc.documentElement)), doc.documentElement);
});

test('collectTargets and contentText preserve HTML and document text', () => {
  const doc = fixture();
  const beforeHTML = doc.documentElement.outerHTML;
  const beforeText = doc.documentElement.textContent;
  for (const kind of ['chat','document','artifact-content']) {
    const targets = collect(doc, kind);
    for (const el of targets.surfaces) contentText(el);
  }
  assert.equal(doc.documentElement.outerHTML, beforeHTML);
  assert.equal(doc.documentElement.textContent, beforeText);
});

test('Unknown surfaces have no targets', () => {
  const doc = fixture();
  assert.deepEqual(findSurfaces(doc, 'unknown'), []);
  const targets = collect(doc, 'unknown');
  assert.deepEqual(targets, { surfaces:[], fonts:[], blocks:[] });
});

test('Flex and grid input roots remain layout containers without direction rules', () => {
  for (const display of ['flex','grid']) {
    const doc = parseHTML(`<!doctype html><html><body><div data-testid="chat-input" contenteditable="true" style="display:${display}" id="layout-input"><span>متن ورودی</span></div></body></html>`).document;
    const targets = collect(doc, 'chat');
    assert.ok(!ids(targets.blocks).includes('layout-input'), display);
    assert.ok(targets.fonts.some(el => el.localName === 'span'));
  }
});


test('Read words split across span and strong without artificial spaces', () => {
  const doc = parseHTML('<!doctype html><html><body><p id="split">می<span>‌توان</span><strong>یم</strong> گزارش را بررسی کنیم.</p><p id="greeting">سلا<strong>م</strong> دنیا</p></body></html>').document;
  const before = doc.documentElement.outerHTML;
  assert.equal(contentText(doc.getElementById('split')), 'می‌توانیم گزارش را بررسی کنیم.');
  assert.equal(contentText(doc.getElementById('greeting')), 'سلام دنیا');
  const { estimateDirection } = require('../lib/persian/direction.cjs');
  assert.equal(estimateDirection(contentText(doc.getElementById('greeting'))).rtlWords, 2);
  assert.equal(doc.documentElement.outerHTML, before);
});

test('Shell mode targets Persian UI fonts without content direction rules', () => {
  const doc = fixture();
  const before = doc.documentElement.outerHTML;
  const targets = collect(doc, 'shell');
  assert.deepEqual(targets.surfaces, []);
  assert.deepEqual(targets.blocks, []);
  for (const id of ['project','sidebar','ui-title','chat-name','sidebar-mixed']) assert.ok(ids(targets.fonts).includes(id), id);
  assert.ok(!ids(targets.fonts).includes('sidebar-english'));
  assert.equal(doc.querySelector('nav').getAttribute('dir'), 'ltr');
  assert.equal(doc.querySelector('header').getAttribute('dir'), 'ltr');
  assert.equal(doc.documentElement.outerHTML, before);
});

test('Saved comments target text paragraphs without author names or timestamps', () => {
  const doc = parseHTML(`<!doctype html><html><body>
    <article data-testid="ldoc-thread-card" id="thread-card">
      <div class="group/comment" id="comment-group">
        <div class="flex items-center gap-2" id="comment-header" style="display:flex">
          <button id="comment-author">Saeid Sisakhti</button>
          <time id="comment-time">2m ago</time>
          <button id="comment-menu" aria-label="Comment options">...</button>
        </div>
        <div class="text-pretty" id="saved-comment-body">
          <div class="whitespace-pre-wrap" id="comment-wrap">
            <div id="comment-renderer">
              <div class="space-y-4" id="comment-prose">
                <p dir="ltr" id="saved-comment-p">API این نمونه درخواست‌های کاربران را ثبت می‌کند. سپس، نتیجه را در یک جدول ساده نشان می‌دهد</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </article>
  </body></html>`).document;
  const beforeHTML = doc.documentElement.outerHTML;
  for (const kind of ['artifact','artifact-content','document']) {
    const targets = collect(doc, kind);
    assert.deepEqual(ids(targets.surfaces), ['saved-comment-body'], kind);
    assert.deepEqual(ids(targets.fonts), ['saved-comment-p'], kind);
    assert.deepEqual(ids(targets.blocks), ['saved-comment-p'], kind);
    for (const id of ['thread-card','comment-group','comment-header','comment-author','comment-time','comment-menu','saved-comment-body','comment-wrap','comment-renderer','comment-prose']) {
      assert.ok(!ids(targets.blocks).includes(id), `${kind}: ${id}`);
      assert.ok(!ids(targets.fonts).includes(id), `${kind}: ${id}`);
    }
    assert.equal(doc.querySelector(selectorFor(targets.blocks[0])), doc.getElementById('saved-comment-p'));
  }
  const { estimateDirection } = require('../lib/persian/direction.cjs');
  assert.equal(estimateDirection(contentText(doc.getElementById('saved-comment-p'))).direction, 'rtl');
  assert.equal(doc.getElementById('saved-comment-p').getAttribute('dir'), 'ltr');
  assert.equal(doc.documentElement.outerHTML, beforeHTML);
});

test('Mixed question and option text get direction while button layout is preserved', () => {
 const doc=parseHTML(`<!doctype html><html><body><main>
 <section data-testid="ask-user-question" id="question-card" style="display:flex">
 <div id="question-text">API برای این آزمایش چه نقشی دارد؟</div>
 <div role="radiogroup" id="choices" style="display:grid">
 <button role="radio" id="choice" style="display:flex"><span id="number">1</span><div id="copy">
 <span id="choice-title">API گزینهٔ پیشنهادی برای آزمایش</span>
 <p id="choice-description" dir="ltr">API این گزینه داده‌های نمونه را بررسی می‌کند.</p>
 </div><svg><text id="choice-icon">نماد</text></svg></button>
 </div><button id="skip">Skip</button></section>
 <button id="ordinary"><span id="ordinary-text">دکمهٔ دیگر</span></button>
 </main></body></html>`).document;
 const before=doc.documentElement.outerHTML;
 const {estimateDirection}=require('../lib/persian/direction.cjs');
 const targets=collect(doc,'chat');
 for(const id of ['question-text','choice-title','choice-description']){
  const el=doc.getElementById(id);
  assert.ok(targets.blocks.includes(el),id);
  assert.equal(estimateDirection(contentText(el)).direction,'rtl',id);
 }
 for(const id of ['question-card','choices','choice','copy','choice-icon','skip','ordinary','ordinary-text'])assert.ok(!ids(targets.blocks).includes(id),id);
 assert.equal(doc.documentElement.outerHTML,before);
 assert.deepEqual(collect(doc,'shell').blocks,[]);
});

test('Cover answered Cowork question cards without message IDs', () => {
 const doc=parseHTML(`<!doctype html><html><body>
 <nav><span id="project-label">API پروژهٔ نمونه</span></nav>
 <main><div aria-label="Chat messages" id="history" style="display:flex">
 <section id="answered-card"><div id="card-layout" style="display:grid">
 <div id="saved-question" dir="ltr">API پرسش اول — کدام روش را انتخاب می‌کنید؟ <strong>پیشنهاد</strong> را بررسی کنید.</div>
 <span id="saved-answer" dir="ltr" style="display:block">API روش اول برای این آزمایش مناسب است.</span>
 <span id="english-answer" style="display:block">Use the first option for this experiment.</span>
 <div id="split-word">می<span id="inline-part" style="display:inline">‌توان</span> ادامه داد.</div>
 <button id="card-menu"><span id="menu-text">گزینه‌های بیشتر</span></button>
 </div></section></div></main></body></html>`).document;
 const before=doc.documentElement.outerHTML;
 const {estimateDirection}=require('../lib/persian/direction.cjs');
 for(const changedRoots of [null,[doc.getElementById('saved-answer')]]){
  const original=global.getComputedStyle;
  global.getComputedStyle=el=>({display:el.style.display||'block'});
  let targets;
  try{targets=collectTargets(doc,'chat',changedRoots);}finally{global.getComputedStyle=original;}
  for(const id of changedRoots?['saved-answer']:['saved-question','saved-answer','english-answer','split-word'])assert.ok(ids(targets.blocks).includes(id),id);
  for(const id of ['history','answered-card','card-layout','project-label','card-menu','menu-text','inline-part'])assert.ok(!ids(targets.blocks).includes(id),id);
 }
 assert.equal(estimateDirection(contentText(doc.getElementById('saved-question'))).direction,'rtl');
 assert.equal(estimateDirection(contentText(doc.getElementById('saved-answer'))).direction,'rtl');
 assert.equal(estimateDirection(contentText(doc.getElementById('english-answer'))).direction,'ltr');
 assert.equal(doc.documentElement.outerHTML,before);
 assert.deepEqual(collect(doc,'document').blocks,[]);
});


test('Identify answered cards with contents wrappers and flex child spans', () => {
 const doc=parseHTML(`<!doctype html><html><body><main>
 <div data-ask-user-question id="real-card">
 <div style="display:flex" id="outer-layout"><div style="display:flex" id="inner-layout">
 <div style="display:contents" id="contents-wrapper">
 <span style="display:block" id="real-question">API پرسش نمونه — کدام روش برای آزمایش مناسب است؟</span>
 <span style="display:block" id="real-answer">روش اول برای این آزمایش مناسب است.</span>
 </div></div></div></div></main></body></html>`).document;
 const before=doc.documentElement.outerHTML;
 const targets=collect(doc,'chat');
 assert.deepEqual(ids(targets.surfaces),['real-card']);
 assert.deepEqual(ids(targets.blocks),['real-question','real-answer']);
 for(const id of ['real-card','outer-layout','inner-layout','contents-wrapper'])assert.ok(!ids(targets.blocks).includes(id),id);
 const {estimateDirection}=require('../lib/persian/direction.cjs');
 for(const el of targets.blocks)assert.equal(estimateDirection(contentText(el)).direction,'rtl');
 assert.equal(doc.documentElement.outerHTML,before);
});


test('Set direction on prefilled free-form answers during the first scan',()=>{
 const doc=parseHTML(`<!doctype html><html><body><div data-ask-user-question><textarea id="free-answer">API این پاسخ از قبل نوشته شده است.</textarea><input type="radio" id="radio"><input type="text" id="free-input" value="پاسخ نمونه"><div role="toolbar"><input type="text" id="action-input"></div></div></body></html>`).document;
 const targets=collect(doc,'chat');
 for(const id of ['free-answer','free-input'])assert.ok(ids(targets.blocks).includes(id),id);
 for(const id of ['radio','action-input'])assert.ok(!ids(targets.blocks).includes(id),id);
});


test('Cover active question cards with bdi and regular buttons while preserving layout',()=>{
 for(const marker of ['data-ask-user-input-banner','data-cds="AskUserQuestion"']){
 const doc=parseHTML(`<!doctype html><html><body><div ${marker} id="banner" style="display:flex">
 <div style="display:flex" id="title-row"><span style="display:block" id="title"><bdi id="title-bdi">API کدام روش برای این آزمون مناسب است؟</bdi></span><button id="minimize" aria-label="Minimize"><span>بستن</span></button></div>
 <button id="option" style="display:flex"><span id="number">1</span><div><span style="display:block" id="label"><bdi id="label-bdi">API روش موقت برای این آزمون</bdi></span><div id="description"><bdi id="description-bdi">این روش را برای بررسی انتخاب کنید.</bdi></div></div><span data-cds="Icon" aria-hidden="true" id="icon">نماد</span></button>
 <textarea id="other">API پاسخ فارسی از پیش نوشته شده است.</textarea></div>
 <button id="outside"><bdi id="outside-bdi">API دکمهٔ خارج از کارت</bdi></button></body></html>`).document;
 const before=doc.documentElement.outerHTML;
 const targets=collect(doc,'chat');
 for(const id of ['title','title-bdi','label','label-bdi','description','description-bdi','other'])assert.ok(ids(targets.blocks).includes(id),id);
 for(const id of ['banner','title-row','option','minimize','icon','outside','outside-bdi'])assert.ok(!ids(targets.blocks).includes(id),id);
 assert.equal(doc.documentElement.outerHTML,before);
 }
});
