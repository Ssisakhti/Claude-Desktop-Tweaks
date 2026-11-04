#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { isDeepStrictEqual } = require('node:util');
const ROOT = path.resolve(__dirname, '..');
const ASSETS = path.join(ROOT, 'assets', 'estedad');
const OUTPUT = path.join(ROOT, 'lib', 'persian', 'fonts.json');
const WEIGHTS = Object.freeze([
 ['Thin',100],['ExtraLight',200],['Light',300],['Regular',400],['Medium',500],
 ['SemiBold',600],['Bold',700],['ExtraBold',800],['Black',900]
]);
function buildFonts() {
 if (!fs.existsSync(path.join(ASSETS,'OFL.txt'))) throw new Error('The font OFL license is missing.');
 return WEIGHTS.map(([name,weight]) => {
  const bytes = fs.readFileSync(path.join(ASSETS,`Estedad-${name}.ttf`));
  if (bytes.length < 12 || bytes.readUInt32BE(0) !== 0x00010000) throw new Error(`Invalid TTF file: Estedad-${name}.ttf`);
  return { weight, data:bytes.toString('base64') };
 });
}
function main(args=process.argv.slice(2)) {
 if (args.some(arg=>arg!=='--check') || args.length>1) throw new Error('Only the --check option is accepted.');
 const fonts=buildFonts();
 if (args.includes('--check')) {
  const existing=JSON.parse(fs.readFileSync(OUTPUT,'utf8'));
  if (!isDeepStrictEqual(existing,fonts)) throw new Error('fonts.json does not match the TTF files; run npm run build:fonts.');
  console.log('All 9 font weights match the TTF files.');
  return;
 }
 fs.writeFileSync(OUTPUT,JSON.stringify(fonts)+'\n');
 console.log('All 9 font weights were generated in lib/persian/fonts.json.');
}
if (require.main===module) { try { main(); } catch(error) { console.error(`Error: ${error.message}`); process.exitCode=1; } }
module.exports={buildFonts,main,WEIGHTS};
