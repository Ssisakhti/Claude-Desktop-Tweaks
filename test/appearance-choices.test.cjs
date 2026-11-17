'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {buildExtension}=require('../lib/persian/extension-package.cjs');
const {nordThemeCss}=require('../lib/persian/nord.cjs');
test('Extension accepts independent font and theme choices and embeds both variable fonts',()=>{
 const features={font:true,theme:true,rtl:false,fontFamily:'vazirmatn',themeName:'gruvbox'};
 const {source}=buildExtension({features});
 assert.ok(source.includes(JSON.stringify(features)));
 assert.ok(source.includes('Claude Persian Vazirmatn'));
});
test('Unknown font and theme choices are rejected',()=>{
 for(const extra of [{fontFamily:'missing'},{themeName:'missing'},{extra:true}])assert.throws(()=>buildExtension({features:{font:true,theme:true,rtl:true,...extra}}));
});
test('Gruvbox uses its warm palette with shared interaction and composer rules',()=>{
 const css=nordThemeCss({forceDark:true,theme:'gruvbox'});
 assert.ok(css.includes('#1d2021'));
 assert.ok(css.includes('#fbf1c7'));
 assert.ok(css.includes('#fabd2f'));
 assert.ok(!css.includes('#2e3440'));
 assert.ok(css.includes('outline: 1px solid'));
 assert.ok(css.includes('[data-prompt-suggestion-ghost]'));
 assert.ok(css.includes('--cds-fill-card-hover'));
});
