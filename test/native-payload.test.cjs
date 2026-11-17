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
