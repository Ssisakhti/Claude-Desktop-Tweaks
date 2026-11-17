'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { NORD, palette, nordThemeCss, nordComputedOverrides } = require('../lib/persian/nord.cjs');

// Independent sRGB contrast calculation; it does not simulate transparency or browser compositing.
function luminance(hex) {
  const rgb = hex.slice(1).match(/../g).map(value => parseInt(value, 16) / 255)
    .map(value => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722;
}
function contrast(a, b) { const x = luminance(a), y = luminance(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }

test('The sixteen colors match the official Nord palette', () => {
  assert.deepEqual(Object.values(NORD), [
    '#2e3440','#3b4252','#434c5e','#4c566a','#d8dee9','#e5e9f0','#eceff4','#8fbcbb',
    '#88c0d0','#81a1c1','#5e81ac','#bf616a','#d08770','#ebcb8b','#a3be8c','#b48ead',
  ]);
  assert.ok(Object.isFrozen(NORD));
  assert.ok(Object.isFrozen(palette()));
});

test('Text, links, errors, and success states meet AA contrast on main surfaces', () => {
  const c = palette();
  for (const foreground of ['text','textSecondary','textMuted','accentText','errorText','successText','warning']) {
    for (const background of ['background','surface','hover']) {
      const ratio = contrast(c[foreground], c[background]);
      assert.ok(ratio >= 4.5, `${foreground}/${background}: ${ratio.toFixed(3)}`);
    }
  }
});

test('Selected text, colored button text, and status messages remain readable', () => {
  const c = palette();
  for (const [fg,bg] of [['selectionText','selection'],['onAccent','accent'],['onAccent','accentHover'],['errorText','errorBackground'],['successText','successBackground']]) {
    assert.ok(contrast(c[fg], c[bg]) >= 4.5, `${fg}/${bg}`);
  }
});

test('Functional borders and focus indicators have at least 3:1 contrast', () => {
  const c = palette();
  for (const fg of ['border','focus','composerFocus']) for (const bg of ['background','surface','hover']) {
    assert.ok(contrast(c[fg], c[bg]) >= 3, `${fg}/${bg}`);
  }
  // borderSubtle is decorative and does not identify a control or focus.
});

test('Default mode targets only explicit dark markers', () => {
  const css = nordThemeCss();
  for (const block of css.matchAll(/([^{}]+)\{[^{}]*\}/g)) {
    assert.ok(block[1].trim().startsWith(':is(.darkTheme,html.dark,'), block[1]);
  }
  assert.doesNotMatch(css, /prefers-color-scheme|@media/);
  assert.doesNotMatch(css, /(?:^|\n):root\s*\{/);
});

test('forceDark applies only to verified frames without adding DOM markers', () => {
  const css = nordThemeCss({ forceDark: true });
  assert.match(css, /^:is\(:root,\.cds-root\) \{/);
  assert.doesNotMatch(css, /darkTheme|data-theme|data-mode|classList|setAttribute/);
  assert.match(css, /:is\(:root,\.cds-root\) ::selection/);
});

test('Generate HSL values for current Claude variables and hex for older variables', () => {
  const css = nordThemeCss();
  for (const name of ['bg-100','bg-300','text-100','text-400','border-100','accent-000','danger-000','success-000','oncolor-100']) {
    assert.match(css, new RegExp(`--${name}: \\d+(?:\\.\\d+)? \\d+(?:\\.\\d+)?% \\d+(?:\\.\\d+)?% !important;`));
  }
  assert.match(css, /--claude-background-color: #2e3440 !important;/);
  assert.match(css, /--claude-foreground-color: #eceff4 !important;/);
});

test('Theme changes colors and focus paint without direction, layout, or font rules', () => {
  const css = nordThemeCss({ forceDark: true });
  const properties = [...css.matchAll(/(?:^|[;{])\s*([\w-]+)\s*:/g)].map(match => match[1]);
  const permitted = new Set(['color','background-color','border-color','outline-color','outline','outline-offset']);
  assert.ok(properties.length > 40);
  for (const property of properties) assert.ok(property.startsWith('--') || permitted.has(property), property);
  for(const rule of css.matchAll(/([^{}]+)\{([^{}]*)\}/g))if(/(?:^|;)\s*outline(?:-offset)?:/.test(rule[2])){assert.match(rule[1],/:focus-within/);assert.match(rule[1],/ChatComposer/);}
  assert.doesNotMatch(css, /(?:^|[;{])\s*(?:direction|unicode-bidi|text-align|display|position|flex|grid|order|float|padding|margin|width|height|font|filter|invert|transform)\s*:/i);
});


test('CDS tokens receive complete colors and nested roots receive the theme', () => {
  const c = palette();
  const overrides = nordComputedOverrides(['--cds-surface-0','--cds-surface-popover','--cds-text-primary','--cds-fill-control-hover','--cds-border-strong']);
  assert.deepEqual(overrides, {
    '--cds-surface-0': c.background, '--cds-surface-popover': c.hover,
    '--cds-text-primary': c.text, '--cds-fill-control-hover': NORD.nord6 + '33',
    '--cds-border-strong': c.border,
  });
  const css = nordThemeCss({ forceDark: true });
  assert.match(css, /:is\(:root,\.cds-root\) \{/);
  assert.match(css, /--cds-surface-0: #2e3440 !important;/);
  assert.match(css, /--cds-text-primary: #eceff4 !important;/);
});

test('Reject unknown tokens and font or layout tokens even with color-like names', () => {
  const supplied = {
    '--cds-font-size-text-entry-floor': '16px',
    '--cds-avatar-text-xs': '12px',
    '--cds-text-unknown': '#fff',
    '--cds-shimmer-text-delay': '0s',
    '--color-grid-columns': '2',
    '--color-brand-unknown': '#fff',
    '--color-white': '#fff',
    '--cds-text-primary': '#fff',
  };
  assert.deepEqual(nordComputedOverrides(supplied), { '--cds-text-primary': palette().text });
  assert.deepEqual(nordComputedOverrides(new Set(['--cds-surface-0','--cds-font-size-text-entry-floor'])), { '--cds-surface-0': palette().background });
});


test('Panels and sidebar use Nord0 while cards use Nord1', () => {
  const c = palette();
  assert.equal(c.background, NORD.nord0);
  assert.equal(c.surface, NORD.nord1);
  assert.equal(c.hover, NORD.nord1);
  const css = nordThemeCss({ forceDark: true });
  assert.match(css, /--bg-000: 220 16\.364% 21\.569% !important;/);
  assert.match(css, /--cds-surface-panel: #2e3440 !important;/);
  assert.match(css, /:where\(body,aside\) \{ background-color: #2e3440 !important; \}/);
  assert.match(css, /:where\(\[data-cds="Card"\]\)[^}]+background-color: #3b4252 !important;/);
  assert.match(css, /--cds-fill-ghost-hover: #eceff413 !important;/);
  assert.match(css, /--cds-fill-ghost-selected: #eceff426 !important;/);
});

test('The CDS page explicitly uses Nord0 independently of parent surfaces', () => {
  assert.deepEqual(nordComputedOverrides(['--cds-page-bg']), { '--cds-page-bg': NORD.nord0 });
  for (const forceDark of [false, true]) {
    const css = nordThemeCss({ forceDark });
    assert.match(css, /--cds-page-bg: #2e3440 !important;/);
    assert.doesNotMatch(css, /--cds-page-bg:\s*(?:var\(|#3b4252)/);
  }
});

test('The inner chat editor is transparent while cards use Nord1', () => {
  for (const forceDark of [false, true]) {
    const css = nordThemeCss({ forceDark });
    const rules = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].map(match => ({ selector: match[1].trim(), declarations: match[2] }));
    const editorBackgroundRules = rules.filter(rule => rule.selector.includes('[data-testid="chat-input"]') && /background-color\s*:/.test(rule.declarations));
    assert.equal(editorBackgroundRules.length, 1);
    assert.match(editorBackgroundRules[0].declarations, /^\s*background-color:\s*transparent\s*!important;\s*$/);
    const elevatedRule = rules.find(rule => rule.selector.includes('[data-cds="Card"]'));
    assert.ok(elevatedRule);
    assert.match(css,/--cds-fill-field: #eceff40d/);
    assert.ok(!elevatedRule.selector.includes('chat-input'));
    assert.match(elevatedRule.declarations, /^\s*background-color:\s*#3b4252\s*!important;\s*$/);
  }
});

test('The new-chat base and top controls share a color while floating surfaces remain separate', () => {
 const colors=nordComputedOverrides(['--cds-surface-0','--cds-surface-1','--cds-page-bg','--cds-surface-2','--cds-surface-3']);
 assert.equal(colors['--cds-surface-1'],colors['--cds-surface-0']);
 assert.equal(colors['--cds-page-bg'],colors['--cds-surface-0']);
 assert.equal(colors['--cds-surface-2'],NORD.nord1);
 assert.equal(colors['--cds-surface-3'],NORD.nord1);
});

test('Interaction fills stay translucent when painted over card text and table borders',()=>{
 const tokens=['--cds-bg-neutral','--cds-bg-neutral-chip','--cds-fill-card','--cds-fill-card-hover','--cds-fill-secondary','--cds-fill-control','--cds-fill-field','--cds-fill-ghost-hover','--cds-fill-ghost-selected','--cds-fill-button-ghost-hover','--cds-fill-secondary-hover','--cds-fill-control-hover','--cds-bg-neutral-hover','--cds-bg-neutral-chip-hover'];
 const values=nordComputedOverrides(tokens);
 for(const name of tokens){
  assert.match(values[name],/^#[0-9a-f]{8}$/,name);
  const opacity=parseInt(values[name].slice(-2),16)/255;
  assert.ok(opacity>0&&opacity<=0.25,`${name} must not mask underlying content`);
 }
 const lines=nordComputedOverrides(['--cds-border-line','--cds-border-line-muted']);
 assert.equal(lines['--cds-border-line'],NORD.nord3);
 assert.ok(lines['--cds-border-line-muted']);
});

test('Ghost overlays keep card text readable when drawn above both text and surface',()=>{
 const composite=(under,over)=>{
  const alpha=parseInt(over.slice(7),16)/255;
  return '#'+[0,1,2].map(i=>Math.round(parseInt(under.slice(1+i*2,3+i*2),16)*(1-alpha)+parseInt(over.slice(1+i*2,3+i*2),16)*alpha).toString(16).padStart(2,'0')).join('');
 };
 const overlays=nordComputedOverrides(['--cds-bg-neutral','--cds-fill-card','--cds-fill-card-hover','--cds-fill-ghost-hover','--cds-fill-ghost-selected']);
 for(const overlay of Object.values(overlays))for(const surface of [NORD.nord0,NORD.nord1]){
  assert.ok(contrast(composite(NORD.nord4,overlay),composite(surface,overlay))>=4.5);
  assert.notEqual(composite(NORD.nord3,overlay),composite(surface,overlay),'row separator survives the overlay');
 }
});

test('Composite search fields keep their native transparent input surface',()=>{
 const css=nordThemeCss({forceDark:true});
 for(const rule of css.matchAll(/([^{}]+)\{([^{}]*)\}/g))if(/background-color:/.test(rule[2])){
  assert.ok(!/(?:^|[, (])(?:input|textarea|select)\b/.test(rule[1]),'field backgrounds belong to semantic tokens, not nested controls');
 }
 assert.match(css,/--cds-fill-field: #eceff40d/);
});

test('Nested CDS roots preserve accent popup surfaces and their contrasting text',()=>{
 const css=nordThemeCss({forceDark:true});
 const rules=[...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)];
 const variables=rules.find(r=>r[1].includes(':is(:root,.cds-root)')&&r[2].includes('--cds-on-accent'));
 assert.ok(variables);
 assert.doesNotMatch(variables[2],/(?:^|;|\n)\s*background-color\s*:/,'nested roots may use semantic accent or danger surfaces');
 assert.ok(rules.some(r=>r[1].trim()===':root'&&/background-color: #2e3440/.test(r[2])));
 assert.ok(contrast(palette().accent,palette().onAccent)>=4.5);
});

test('Prompt suggestions have a distinct readable color without recoloring accepted editor text',()=>{
 const c=palette(),css=nordThemeCss({forceDark:true});
 assert.ok(c.promptSuggestion);
 assert.ok(contrast(c.promptSuggestion,c.surface)>=4.5);
 assert.ok(contrast(c.promptSuggestion,c.text)>=1.7);
 const rule=[...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].find(r=>r[1].includes('[data-prompt-suggestion-ghost]'));
 assert.ok(rule,'target the actual ghost marker, not user text');
 assert.match(rule[2],new RegExp('color: '+c.promptSuggestion+' !important;'));
 assert.doesNotMatch(rule[1],/contenteditable|data-message-box/);
 assert.doesNotMatch(rule[2],/visibility|display|opacity|content\s*:/,'native acceptance and ghost visibility remain unchanged');
});

test('Composer focus draws a restrained one-pixel inset outline without changing box geometry',()=>{
 const css=nordThemeCss({forceDark:true});
 const rule=[...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].find(r=>r[1].includes('[data-cds="ChatComposer"]')&&r[1].includes(':focus-within'));
 assert.ok(rule,'both mouse and keyboard focus must mark the visible composer shell');
 assert.match(rule[1],/> \.rounded-composer/);
 assert.match(rule[2],/outline: 1px solid #81a1c1 !important;/);
 assert.match(rule[2],/outline-offset: -1px !important;/);
 assert.doesNotMatch(rule[2],/padding|margin|border-width|height|width/);
});

test('Gruvbox text, controls, focus and ghost preview meet contrast targets',()=>{
 const c=palette('gruvbox');
 for(const fg of ['text','textSecondary','textMuted','accentText','errorText','successText','warning','promptSuggestion'])for(const bg of ['background','surface','hover'])assert.ok(contrast(c[fg],c[bg])>=4.5,`${fg}/${bg}`);
 for(const [fg,bg] of [['selectionText','selection'],['onAccent','accent'],['onAccent','accentHover'],['errorText','errorBackground'],['successText','successBackground']])assert.ok(contrast(c[fg],c[bg])>=4.5,`${fg}/${bg}`);
 for(const fg of ['border','focus','composerFocus'])for(const bg of ['background','surface'])assert.ok(contrast(c[fg],c[bg])>=3,`${fg}/${bg}`);
 assert.ok(contrast(c.promptSuggestion,c.text)>=1.7,'ghost differs from accepted text');
});
