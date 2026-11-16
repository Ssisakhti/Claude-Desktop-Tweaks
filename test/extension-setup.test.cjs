'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {installExtension,agentXml}=require('../scripts/extension-setup.cjs');
const root=path.resolve(__dirname,'..');
function fixture(t){
 const home=fs.mkdtempSync(path.join(os.tmpdir(),'cdt-extension-'));
 t.after(()=>fs.rmSync(home,{recursive:true,force:true}));
 const state={env:null,loaded:false,claude:false,hammerspoon:false,fail:null,calls:[]};
 function run(command,args){
  state.calls.push([command,...args]);
  if(command==='/usr/bin/pgrep')return {status:state[args[1]==='Claude'?'claude':'hammerspoon']?0:1,stdout:''};
  if(command!=='/bin/launchctl')throw Error('Unexpected command');
  const [action]=args;
  if(action===state.fail)return {status:1,stdout:''};
  if(action==='getenv')return {status:state.env===null?1:0,stdout:state.env===null?'':state.env+'\n'};
  if(action==='print')return {status:state.loaded?0:1,stdout:''};
  if(action==='bootstrap')state.loaded=true;
  if(action==='bootout')state.loaded=false;
  if(action==='setenv')state.env=args[2];
  if(action==='unsetenv')state.env=null;
  return {status:0,stdout:''};
 }
 const options={home,root,platform:'darwin',run};
 const target=path.join(home,'Library/Application Support/Claude/extensions/fmkadmapgofadopljbjfkapdkoienihi');
 const record=path.join(home,'Library/Application Support/Claude Desktop Tweaks/extension-startup.json');
 const agent=path.join(home,'Library/LaunchAgents/local.claude-desktop-tweaks.environment.plist');
 return {home,state,options,target,record,agent};
}
test('Install once and repeat without losing original rollback state',t=>{
 const f=fixture(t);const a=installExtension(f.options);
 assert.equal(f.state.env,'1');assert.equal(f.state.loaded,true);
 for(const name of ['manifest.json','content.js','LICENSE','Estedad-OFL.txt','Nord-LICENSE','NOTICE.md'])assert.ok(fs.existsSync(path.join(f.target,name)));
 assert.equal(JSON.parse(fs.readFileSync(path.join(f.target,'manifest.json'))).content_scripts[0].all_frames,true);
 const first=JSON.parse(fs.readFileSync(f.record));assert.equal(first.previousReactProfile,null);
 const b=installExtension(f.options);assert.equal(b.changed,false);
 assert.equal(JSON.parse(fs.readFileSync(f.record)).previousReactProfile,null);
 assert.equal(fs.readFileSync(f.agent,'utf8'),agentXml());
 assert.equal(a.installed,true);
});
test('Dry run and unsupported platforms never write or run system mutations',t=>{
 const f=fixture(t);installExtension({...f.options,dryRun:true});assert.deepEqual(fs.readdirSync(f.home),[]);
 assert.ok(!f.state.calls.some(c=>['bootstrap','setenv','bootout','unsetenv'].includes(c[1])));
 assert.throws(()=>installExtension({...f.options,platform:'linux'}),/macOS/);
});
test('Refuse a running Claude and do not quit it',t=>{
 const f=fixture(t);f.state.claude=true;assert.throws(()=>installExtension(f.options),/Quit Claude/);
 assert.deepEqual(fs.readdirSync(f.home),[]);
});
test('Preserve unknown extensions and agents',t=>{
 const f=fixture(t);fs.mkdirSync(f.target,{recursive:true});fs.writeFileSync(path.join(f.target,'manifest.json'),'{}');
 assert.throws(()=>installExtension(f.options),/extension/i);assert.equal(fs.readFileSync(path.join(f.target,'manifest.json'),'utf8'),'{}');
 fs.rmSync(f.target,{recursive:true});fs.mkdirSync(path.dirname(f.agent),{recursive:true});fs.writeFileSync(f.agent,'unrelated');
 assert.throws(()=>installExtension(f.options),/agent/i);assert.equal(fs.readFileSync(f.agent,'utf8'),'unrelated');
});
test('Migrate only the owned legacy block and preserve unrelated configuration',t=>{
 const f=fixture(t);const dir=path.join(f.home,'.hammerspoon');fs.mkdirSync(dir);
 const original='-- user config\n-- BEGIN Claude Desktop Tweaks\nold()\n-- END Claude Desktop Tweaks\nkeep()\n';
 fs.writeFileSync(path.join(dir,'init.lua'),original);f.state.hammerspoon=true;
 assert.throws(()=>installExtension(f.options),/Quit Hammerspoon/);
 assert.equal(fs.readFileSync(path.join(dir,'init.lua'),'utf8'),original);
 f.state.hammerspoon=false;installExtension(f.options);
 assert.equal(fs.readFileSync(path.join(dir,'init.lua'),'utf8'),'-- user config\nkeep()\n');
 const record=JSON.parse(fs.readFileSync(f.record));assert.equal(fs.readFileSync(record.hammerspoonBackup,'utf8'),original);
});
test('Failed registration restores files and previous environment',t=>{
 const f=fixture(t);f.state.env='previous';f.state.fail='bootstrap';
 assert.throws(()=>installExtension(f.options),/bootstrap/);
 assert.equal(f.state.env,'previous');assert.equal(fs.existsSync(f.target),false);assert.equal(fs.existsSync(f.agent),false);assert.equal(fs.existsSync(f.record),false);
});
test('Failed reinstallation preserves previous working extension and receipt',t=>{
 const f=fixture(t);installExtension(f.options);const original=fs.readFileSync(f.record);const source=fs.readFileSync(path.join(f.target,'content.js'));
 f.state.fail='setenv';assert.throws(()=>installExtension(f.options),/setenv/);
 assert.deepEqual(fs.readFileSync(f.record),original);assert.deepEqual(fs.readFileSync(path.join(f.target,'content.js')),source);
});
test('Reject symlinked parents instead of writing outside the chosen home',t=>{
 const f=fixture(t);const other=fs.mkdtempSync(path.join(os.tmpdir(),'cdt-other-'));t.after(()=>fs.rmSync(other,{recursive:true,force:true}));
 fs.symlinkSync(other,path.join(f.home,'Library'));assert.throws(()=>installExtension(f.options),/symbolic|directory/i);assert.deepEqual(fs.readdirSync(other),[]);
});
test('A receipt commit failure rolls back migration, registration, environment, and extension',t=>{
 const f=fixture(t);const dir=path.join(f.home,'.hammerspoon');fs.mkdirSync(dir);
 const original='-- BEGIN Claude Desktop Tweaks\nold()\n-- END Claude Desktop Tweaks\nkeep()\n';
 const config=path.join(dir,'init.lua');fs.writeFileSync(config,original);
 const rename=fs.renameSync;
 fs.renameSync=(from,to)=>{if(to===f.record)throw Error('simulated receipt commit failure');return rename(from,to);};
 try{assert.throws(()=>installExtension(f.options),/receipt commit failure/);}finally{fs.renameSync=rename;}
 assert.equal(fs.readFileSync(config,'utf8'),original);assert.equal(f.state.env,null);assert.equal(f.state.loaded,false);
 assert.equal(fs.existsSync(f.target),false);assert.equal(fs.existsSync(f.agent),false);assert.equal(fs.existsSync(f.record),false);
});
test('Update a receipt-proven older source and keep its complete directory backup',t=>{
 const f=fixture(t);installExtension(f.options);
 const old=Buffer.from('// older owned source\n');fs.writeFileSync(path.join(f.target,'content.js'),old);
 const record=JSON.parse(fs.readFileSync(f.record));record.extensionSha256=require('node:crypto').createHash('sha256').update(old).digest('hex');
 fs.writeFileSync(f.record,JSON.stringify(record));fs.writeFileSync(path.join(f.target,'old-extra.txt'),'preserve');
 const result=installExtension(f.options);assert.equal(result.changed,true);
 assert.deepEqual(fs.readFileSync(path.join(result.backup,'extension/content.js')),old);
 assert.equal(fs.readFileSync(path.join(result.backup,'extension/old-extra.txt'),'utf8'),'preserve');
 assert.equal(fs.existsSync(path.join(f.target,'old-extra.txt')),false);
 assert.equal(JSON.parse(fs.readFileSync(f.record)).previousReactProfile,null);
});
test('A concurrent installation lock prevents system mutations',t=>{
 const f=fixture(t);installExtension(f.options);fs.writeFileSync(path.join(path.dirname(f.record),'.extension-install.lock'),'busy');
 const count=f.state.calls.length;assert.throws(()=>installExtension(f.options),/EEXIST/);
 assert.ok(!f.state.calls.slice(count).some(c=>['bootstrap','setenv','bootout','unsetenv'].includes(c[1])));
});
test('Rollback handles bootstrap failure after its job and environment already changed',t=>{
 const f=fixture(t);const run=f.options.run;
 f.options.run=(cmd,args)=>{if(cmd==='/bin/launchctl'&&args[0]==='bootstrap'){f.state.loaded=true;f.state.env='1';return {status:1,stdout:''};}return run(cmd,args);};
 assert.throws(()=>installExtension(f.options),/bootstrap/);
 assert.equal(f.state.loaded,false);assert.equal(f.state.env,null);
 assert.equal(fs.existsSync(f.target),false);assert.equal(fs.existsSync(f.agent),false);assert.equal(fs.existsSync(f.record),false);
});
