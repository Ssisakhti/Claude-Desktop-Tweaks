'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {setup,parseArgs,updateConfig,luaString,renderConfig,digestFiles,runtimeBuild}=require('../scripts/setup.cjs');
const {spawnSync}=require('node:child_process');
function writableDirectories(dir){for(const entry of fs.readdirSync(dir,{withFileTypes:true})){if(entry.isDirectory()){const child=path.join(dir,entry.name);fs.chmodSync(child,0o700);writableDirectories(child);}}}
function temporary(fn){const home=fs.mkdtempSync(path.join(os.tmpdir(),'tweaks-test-'));try{return fn(home);}finally{writableDirectories(home);fs.rmSync(home,{recursive:true,force:true});}}
function seed(home){const folder=path.join(home,'.hammerspoon');fs.mkdirSync(folder);const file=path.join(folder,'init.lua');fs.writeFileSync(file,'-- user settings\nkeep=true\n');return file;}
test('The default mode is a dry run and ambiguous options are rejected',()=>{
 assert.deepEqual(parseArgs([]),{mode:'--dry-run'});assert.deepEqual(parseArgs(['--install']),{mode:'--install'});
 assert.deepEqual(parseArgs(['--restore-backup=/tmp/save']),{mode:'--restore',backupFile:'/tmp/save'});
 for(const args of [['--install','--remove'],['--restore-backup='],['--other'],['--dry-run','--dry-run']])assert.throws(()=>parseArgs(args));
});
test('Markers are unique and Lua paths are not interpreted as code',()=>{
 const base='-- user\n';const first=updateConfig(base,'code');assert.equal(updateConfig(first,'code'),first);assert.equal(updateConfig(first,null),base);
 for(const s of ['-- BEGIN Claude Desktop Tweaks','-- END Claude Desktop Tweaks','-- END Claude Desktop Tweaks\n-- BEGIN Claude Desktop Tweaks',first+first])assert.throws(()=>updateConfig(s,'code'));
 assert.equal(luaString('/tmp/a]]b'), '[=[/tmp/a]]b]=]');
});
test('A dry run does not create the configuration directory',()=>temporary(home=>{
 const result=setup({home});assert.equal(result.mode,'--dry-run');assert.match(result.runtimeDigest,/^[a-f0-9]{64}$/);assert.equal(result.runtimeChanges,true);assert.deepEqual(fs.readdirSync(home),[]);
}));
test('Installation creates private standalone files and restore is exact',()=>temporary(home=>{
 const file=seed(home),original=fs.readFileSync(file,'utf8');const result=setup({home,mode:'--install'});
 assert.equal(fs.readFileSync(result.backup,'utf8'),original);assert.equal(fs.statSync(result.backup).mode&0o777,0o600);
 assert.equal(fs.statSync(file).mode&0o777,0o600);assert.equal(fs.statSync(result.runtime).mode&0o777,0o500);
 assert.deepEqual(fs.readdirSync(result.runtime).sort(),['bundle.json','claude-console-auto.lua','claude-console.lua','manifest.json']);
 for(const name of fs.readdirSync(result.runtime))assert.equal(fs.statSync(path.join(result.runtime,name)).mode&0o777,0o400);
 const installed=fs.readFileSync(file,'utf8');assert.ok(installed.startsWith(original));assert.ok(!installed.includes(path.resolve(__dirname,'..')));assert.ok(installed.includes(result.runtime));
 assert.equal(setup({home,mode:'--install'}).changed,false);
 const restored=setup({home,mode:'--restore',backupFile:result.backup});assert.equal(fs.readFileSync(file,'utf8'),original);assert.equal(fs.readFileSync(restored.backup,'utf8'),installed);assert.ok(fs.existsSync(result.runtime));
 setup({home,mode:'--install'});setup({home,mode:'--remove'});assert.equal(fs.readFileSync(file,'utf8'),original);
}));
test('Changing runtime data produces a different digest',()=>{
 const a={'a':Buffer.from('ab'),'b':Buffer.from('c')},b={'a':Buffer.from('a'),'b':Buffer.from('bc')};assert.notEqual(digestFiles(a),digestFiles(b));assert.equal(digestFiles(a),digestFiles({'b':a.b,'a':a.a}));
 const root=path.resolve(__dirname,'..'),build=runtimeBuild(root);assert.equal(build.digest,digestFiles(build.files));
});
test('An altered or damaged installation is rejected',()=>temporary(home=>{
 const result=setup({home,mode:'--install'}),target=path.join(result.runtime,'claude-console.lua');fs.chmodSync(target,0o600);fs.appendFileSync(target,'\n-- changed');assert.throws(()=>setup({home,mode:'--install'}),/changed/);
}));
test('Configuration, runtime, and backup symlinks are rejected',()=>temporary(home=>{
 const file=seed(home),folder=path.dirname(file);fs.renameSync(file,file+'.real');fs.symlinkSync(file+'.real',file);assert.throws(()=>setup({home,mode:'--install'}));fs.unlinkSync(file);fs.renameSync(file+'.real',file);
 const runtimeRoot=path.join(folder,'claude-desktop-tweaks');fs.symlinkSync(home,runtimeRoot);assert.throws(()=>setup({home,mode:'--install'}));fs.unlinkSync(runtimeRoot);
 const fake=path.join(folder,'init.lua.before-claude-desktop-tweaks-123-abcd.bak');fs.symlinkSync(file,fake);assert.throws(()=>setup({home,mode:'--restore',backupFile:fake}));assert.throws(()=>setup({home,mode:'--restore',backupFile:path.join(home,'other')}));
}));
test('Directory symlinks and public runtime directories are rejected',()=>temporary(home=>{
 fs.mkdirSync(path.join(home,'actual'));fs.symlinkSync(path.join(home,'actual'),path.join(home,'.hammerspoon'));assert.throws(()=>setup({home}));fs.unlinkSync(path.join(home,'.hammerspoon'));
 fs.mkdirSync(path.join(home,'.hammerspoon'));fs.mkdirSync(path.join(home,'.hammerspoon/claude-desktop-tweaks'),{mode:0o755});assert.throws(()=>setup({home}));
}));
test('A failed commit preserves configuration and removes the incomplete installation',()=>temporary(home=>{
 const file=seed(home),original=fs.readFileSync(file,'utf8');const io={...fs,renameSync(a,b){if(b===file)throw new Error('synthetic commit');return fs.renameSync(a,b);}};
 assert.throws(()=>setup({home,mode:'--install',fileSystem:io}),/synthetic commit/);assert.equal(fs.readFileSync(file,'utf8'),original);
 assert.deepEqual(fs.readdirSync(path.join(home,'.hammerspoon/claude-desktop-tweaks')),[]);assert.ok(!fs.readdirSync(path.dirname(file)).some(n=>n.startsWith('init.lua.claude-desktop-tweaks')||n.endsWith('.lock')));
 assert.ok(fs.readdirSync(path.dirname(file)).some(n=>n.endsWith('.bak')));
}));
test('Concurrent user changes are not overwritten',()=>temporary(home=>{
 const file=seed(home);let changed=false;const io={...fs,writeFileSync(target,...args){const result=fs.writeFileSync(target,...args);if(String(target).includes('init.lua.claude-desktop-tweaks-')&&!changed){changed=true;fs.writeFileSync(file,'-- user new settings\n');}return result;}};
 assert.throws(()=>setup({home,mode:'--install',fileSystem:io}),/during the operation/);assert.equal(fs.readFileSync(file,'utf8'),'-- user new settings\n');
}));
test('An existing lock prevents concurrent installation',()=>temporary(home=>{
 const file=seed(home),original=fs.readFileSync(file,'utf8');fs.writeFileSync(path.join(home,'.hammerspoon/.claude-desktop-tweaks.lock'),'owned');assert.throws(()=>setup({home,mode:'--install'}),/EEXIST/);assert.equal(fs.readFileSync(file,'utf8'),original);
}));
const library='/Applications/Hammerspoon.app/Contents/Frameworks/LuaSkin.framework/LuaSkin';
const luaExecutable=['lua5.4','lua'].find(command=>spawnSync(command,['-v'],{encoding:'utf8'}).status===0);
const luaAvailable=fs.existsSync(library)||Boolean(luaExecutable);
function runLua(source){
 if(!fs.existsSync(library)){const result=spawnSync(luaExecutable,['-'],{input:source,encoding:'utf8'});assert.equal(result.status,0,result.stderr);return;}
const runner=`import ctypes,sys
lua=ctypes.CDLL(sys.argv[1]);lua.luaL_newstate.restype=ctypes.c_void_p
lua.luaL_openlibs.argtypes=[ctypes.c_void_p];lua.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
lua.lua_pcallk.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int,ctypes.c_longlong,ctypes.c_void_p]
lua.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lua.lua_tolstring.restype=ctypes.c_char_p
lua.lua_close.argtypes=[ctypes.c_void_p];state=lua.luaL_newstate();lua.luaL_openlibs(state)
try:
 result=lua.luaL_loadstring(state,sys.stdin.buffer.read())
 if result==0:result=lua.lua_pcallk(state,0,1,0,0,None)
 if result:
  error=lua.lua_tolstring(state,-1,None);raise SystemExit(error.decode() if error else 'Lua failure')
finally:lua.lua_close(state)
`;const result=spawnSync('python3',['-c',runner,library],{input:source,encoding:'utf8'});assert.equal(result.status,0,result.stderr);}
test('Lua verifies cleanup before replacement and stops failed startup',{skip:!luaAvailable},()=>{
 const block=renderConfig({runtime:'/installed',statusFile:'/status'});
 for(const scenario of ['success','pending','required','stop-error','start-error','stopped-candidate','snapshot-error'])runLua(`local events={};local scenario=${luaString(scenario)};hs={}
local previous={stop=function()events[#events+1]='old-stop';if scenario=='stop-error' then error('stop failed')end end,snapshot=function()return {running=false,cleanupPending=scenario=='pending',cleanupRequired=scenario=='required'}end}
claudeDesktopTweaks=previous
local candidate={stop=function()events[#events+1]='new-stop'end,snapshot=function()if scenario=='snapshot-error' then error('snapshot failed')end;return {running=scenario~='stopped-candidate'}end}
loadfile=function(file)assert(file=='/installed/claude-console-auto.lua');return function()return {start=function(config)events[#events+1]='new-start';assert(config.driverPath=='/installed/claude-console.lua' and config.bundlePath=='/installed/bundle.json');if scenario=='start-error'then error('start failed')end;return candidate end}end end
local ok=pcall(function()${block} end)
if scenario=='success'then assert(ok and events[1]=='old-stop' and events[2]=='new-start' and claudeDesktopTweaks==candidate)
elseif scenario=='pending' or scenario=='required' or scenario=='stop-error'then assert(not ok and #events==1 and claudeDesktopTweaks==previous)
elseif scenario=='start-error'then assert(not ok and #events==2 and claudeDesktopTweaks==nil)
else assert(not ok and events[3]=='new-stop' and claudeDesktopTweaks==candidate)end
return true`);
});

test('Installed files remain readable after the source directory is removed',{skip:!luaAvailable},()=>temporary(home=>{
 const source=path.join(home,'source');fs.mkdirSync(path.join(source,'integrations/hammerspoon'),{recursive:true});fs.mkdirSync(path.join(source,'lib/persian'),{recursive:true});
 const root=path.resolve(__dirname,'..');for(const name of ['claude-console.lua','claude-console-auto.lua'])fs.copyFileSync(path.join(root,'integrations/hammerspoon',name),path.join(source,'integrations/hammerspoon',name));
 fs.writeFileSync(path.join(source,'lib/persian/console-bundle.cjs'),"module.exports={buildConsoleBundle(){return {version:1,revision:3,probeTemplate:'probe',payloads:{chat:'payload'}}}};");
 const result=setup({home,root:source,mode:'--install'});fs.rmSync(source,{recursive:true});
 runLua(`local root=${luaString(result.runtime)}
assert(type(assert(loadfile(root..'/claude-console.lua'))())=='table')
assert(type(assert(loadfile(root..'/claude-console-auto.lua'))())=='table')
local file=assert(io.open(root..'/bundle.json','r'));assert(#file:read('*a')>0);file:close();return true`);
 const config=fs.readFileSync(path.join(home,'.hammerspoon/init.lua'),'utf8');assert.ok(!config.includes(source));
}));

test('Replacing the runtime parent never deletes unrelated data during cleanup',()=>temporary(home=>{
 const file=seed(home),original=fs.readFileSync(file,'utf8'),folder=path.dirname(file),runtimeRoot=path.join(folder,'claude-desktop-tweaks'),parked=path.join(folder,'parked'),unrelated=path.join(home,'unrelated');fs.mkdirSync(unrelated);
 let target,swapped=false;const io={...fs,writeFileSync(name,...args){const result=fs.writeFileSync(name,...args);if(String(name).includes('init.lua.claude-desktop-tweaks-')&&!swapped){swapped=true;target=fs.readdirSync(runtimeRoot)[0];fs.mkdirSync(path.join(unrelated,target));fs.writeFileSync(path.join(unrelated,target,'keep'),'keep');fs.renameSync(runtimeRoot,parked);fs.symlinkSync(unrelated,runtimeRoot);}return result;}};
 assert.throws(()=>setup({home,mode:'--install',fileSystem:io}),error=>error.cleanupRequired===true);assert.equal(fs.readFileSync(path.join(unrelated,target,'keep'),'utf8'),'keep');assert.equal(fs.readFileSync(file,'utf8'),original);assert.ok(fs.existsSync(path.join(parked,target)));
}));
test('Runtime permission changes are rejected even when content matches',()=>temporary(home=>{
 const result=setup({home,mode:'--install'}),file=path.join(result.runtime,'bundle.json');fs.chmodSync(file,0o600);assert.throws(()=>setup({home,mode:'--install'}),/permissions/);fs.chmodSync(file,0o400);fs.chmodSync(result.runtime,0o700);assert.throws(()=>setup({home,mode:'--install'}),/permissions/);
}));

test('Publication precedes permission locking on systems that require a writable directory',()=>temporary(home=>{
 let observed=false;const io={...fs,renameSync(from,to){if(path.basename(from).startsWith('.staging-')){observed=true;const mode=fs.lstatSync(from).mode&0o777;if(mode!==0o700){const error=new Error('synthetic EACCES');error.code='EACCES';throw error;}}return fs.renameSync(from,to);}};
 const result=setup({home,mode:'--install',fileSystem:io});assert.equal(observed,true);assert.equal(fs.lstatSync(result.runtime).mode&0o777,0o500);
}));
test('Replacing the parent immediately after publication preserves unrelated permissions',()=>temporary(home=>{
 const file=seed(home),original=fs.readFileSync(file,'utf8'),folder=path.dirname(file),runtimeRoot=path.join(folder,'claude-desktop-tweaks'),parked=path.join(folder,'parked'),unrelated=path.join(home,'unrelated');fs.mkdirSync(unrelated);
 let target,swapped=false;const io={...fs,renameSync(from,to){const result=fs.renameSync(from,to);if(path.basename(from).startsWith('.staging-')&&!swapped){swapped=true;target=path.basename(to);fs.mkdirSync(path.join(unrelated,target),{mode:0o700});fs.writeFileSync(path.join(unrelated,target,'keep'),'keep');fs.renameSync(runtimeRoot,parked);fs.symlinkSync(unrelated,runtimeRoot);}return result;}};
 assert.throws(()=>setup({home,mode:'--install',fileSystem:io}),error=>error.cleanupRequired===true);assert.equal(fs.readFileSync(path.join(unrelated,target,'keep'),'utf8'),'keep');assert.equal(fs.lstatSync(path.join(unrelated,target)).mode&0o777,0o700);assert.equal(fs.lstatSync(path.join(parked,target)).mode&0o777,0o500);assert.equal(fs.readFileSync(file,'utf8'),original);
}));
