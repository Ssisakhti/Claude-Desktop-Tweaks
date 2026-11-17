'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
test('Native payload template reproduces every independently selected extension',t=>{
 const {writeNativePayload}=require('../scripts/build-native-payload.cjs');
 const {buildExtension}=require('../lib/persian/extension-package.cjs');
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'cdt-payload-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
 writeNativePayload(dir);const template=fs.readFileSync(path.join(dir,'content.js'),'utf8');
 assert.equal(template.split('__CDT_FEATURES__').length,2);
 for(let i=0;i<8;i++){
  const features={font:!!(i&1),theme:!!(i&2),rtl:!!(i&4)};
  assert.equal(template.replace('__CDT_FEATURES__',JSON.stringify(features)),buildExtension({features}).source);
 }
 for(const file of ['LICENSE','Estedad-OFL.txt','Nord-LICENSE','Vazirmatn-OFL.txt','Gruvbox-NOTICE.md','NOTICE.md'])assert.ok(fs.statSync(path.join(dir,file)).size>0);
});
test('Development extension build includes all required font and theme notices',t=>{
 const {spawnSync}=require('node:child_process');
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'cdt-extension-build-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
 const result=spawnSync(process.execPath,[path.resolve(__dirname,'../scripts/build-extension.cjs'),dir],{encoding:'utf8'});
 assert.equal(result.status,0,result.stderr);
 for(const name of ['Estedad-OFL.txt','Vazirmatn-OFL.txt','Nord-LICENSE','Gruvbox-NOTICE.md'])assert.ok(fs.statSync(path.join(dir,name)).size>0);
});
