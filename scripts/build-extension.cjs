'use strict';
const fs = require('node:fs');
const path = require('node:path');
const { buildExtension } = require('../lib/persian/extension-package.cjs');
const destination = process.argv[2];
if (!destination || !path.isAbsolute(destination)) throw new Error('Provide an absolute output directory');
const { manifest, source } = buildExtension();
fs.mkdirSync(destination, { recursive:true });
fs.writeFileSync(path.join(destination, 'manifest.json'), JSON.stringify(manifest,null,2)+'\n');
fs.writeFileSync(path.join(destination, 'content.js'), source);
for (const [name, original] of [['LICENSE','LICENSE'], ['Estedad-OFL.txt','assets/estedad/OFL.txt'], ['Nord-LICENSE','assets/nord/LICENSE'], ['Vazirmatn-OFL.txt','assets/vazirmatn/OFL.txt'], ['Gruvbox-NOTICE.md','assets/gruvbox/SOURCE.md'], ['NOTICE.md','NOTICE.md']]) {
 fs.copyFileSync(path.join(__dirname,'..',original),path.join(destination,name));
}
console.log('Built local extension with font and license notices.');
