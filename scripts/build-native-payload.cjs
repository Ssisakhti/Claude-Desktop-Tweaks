'use strict';
const fs=require('node:fs'),path=require('node:path');
const {buildExtension}=require('../lib/persian/extension-package.cjs');
function writeNativePayload(destination){
 const {manifest,source}=buildExtension();
 const marker=JSON.stringify({font:true,theme:true,rtl:true});
 if(source.split(marker).length!==2)throw Error('Feature configuration must occur exactly once.');
 fs.mkdirSync(destination,{recursive:true});
 fs.writeFileSync(path.join(destination,'content.js'),source.replace(marker,'__CDT_FEATURES__'));
 fs.writeFileSync(path.join(destination,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 for(const [to,from]of [['LICENSE','LICENSE'],['Estedad-OFL.txt','assets/estedad/OFL.txt'],['Nord-LICENSE','assets/nord/LICENSE'],['NOTICE.md','NOTICE.md'],['Terminal-LICENSES.txt','assets/terminal/LICENSES.txt']])fs.copyFileSync(path.join(__dirname,'..',from),path.join(destination,to));
}
if(require.main===module)writeNativePayload(path.join(__dirname,'../native/internal/installer/payload'));
module.exports={writeNativePayload};
