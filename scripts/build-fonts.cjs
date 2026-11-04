#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { isDeepStrictEqual } = require('node:util');
const { createHash } = require('node:crypto');
const ROOT = path.resolve(__dirname, '..');
const ASSETS = path.join(ROOT, 'assets', 'estedad');
const OUTPUT = path.join(ROOT, 'lib', 'persian', 'fonts.json');
const WEIGHTS = Object.freeze([['Variable','100 900']]);
const FONT_SHA256='55910be66020e77f9ff5bf9164e9afc0d9c01e7e186b63808e0cd14f5f87f031';
function buildFonts() {
 if (!fs.existsSync(path.join(ASSETS,'OFL.txt'))) throw new Error('The font OFL license is missing.');
 const bytes=fs.readFileSync(path.join(ASSETS,'Estedad-Variable.woff2'));
 if(bytes.length<48 || bytes.toString('ascii',0,4)!=='wOF2' || bytes.readUInt32BE(8)!==bytes.length) throw new Error('Invalid variable WOFF2 file.');
 if(createHash('sha256').update(bytes).digest('hex')!==FONT_SHA256) throw new Error('The variable font does not match the pinned official release.');
 return [{weight:'100 900',data:bytes.toString('base64')}];
}
function main(args=process.argv.slice(2)) {
 if (args.some(arg=>arg!=='--check') || args.length>1) throw new Error('Only the --check option is accepted.');
 const fonts=buildFonts();
 if (args.includes('--check')) {
  const existing=JSON.parse(fs.readFileSync(OUTPUT,'utf8'));
  if (!isDeepStrictEqual(existing,fonts)) throw new Error('fonts.json does not match the official variable WOFF2; run npm run build:fonts.');
  console.log('The official variable WOFF2 matches; weights 100–900 use one font face.');
  return;
 }
 fs.writeFileSync(OUTPUT,JSON.stringify(fonts)+'\n');
 console.log('The variable font was generated in lib/persian/fonts.json.');
}
if (require.main===module) { try { main(); } catch(error) { console.error(`Error: ${error.message}`); process.exitCode=1; } }
module.exports={buildFonts,main,WEIGHTS};
