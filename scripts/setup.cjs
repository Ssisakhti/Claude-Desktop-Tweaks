'use strict';
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {createHash,randomUUID}=require('node:crypto');
const BEGIN='-- BEGIN Claude Desktop Tweaks';
const END='-- END Claude Desktop Tweaks';
const SOURCES=Object.freeze({'claude-console-auto.lua':'integrations/hammerspoon/claude-console-auto.lua','claude-console.lua':'integrations/hammerspoon/claude-console.lua'});
function luaString(value){let equals='';while(value.includes(']'+equals+']'))equals+='=';return '['+equals+'['+value+']'+equals+']';}
function updateConfig(original,block){
 const start=original.indexOf(BEGIN),end=original.indexOf(END);
 if((start<0)!==(end<0)||(start>=0&&(end<start||original.indexOf(BEGIN,start+BEGIN.length)>=0||original.indexOf(END,end+END.length)>=0)))throw new Error('Configuration markers are ambiguous.');
 const base=start<0?original:original.slice(0,start)+original.slice(end+END.length).replace(/^\r?\n/,'');
 return block?base+(base&&!base.endsWith('\n')?'\n':'')+BEGIN+'\n'+block+'\n'+END+'\n':base;
}
function renderConfig({runtime,statusFile}){return `do
 local previous=claudeDesktopTweaks
 if previous then
  assert(type(previous.stop)=='function' and type(previous.snapshot)=='function','cleanup unavailable')
  previous.stop()
  local status=previous.snapshot()
  assert(type(status)=='table' and status.running==false and not status.cleanupPending and not status.cleanupRequired,'cleanup incomplete')
  claudeDesktopTweaks=nil
 end
 local module=assert(loadfile(${luaString(path.join(runtime,'claude-console-auto.lua'))}))()
 local candidate
 local ok,reason=pcall(function()
 candidate=module.start({driverPath=${luaString(path.join(runtime,'claude-console.lua'))},bundlePath=${luaString(path.join(runtime,'bundle.json'))},statusFile=${luaString(statusFile)},idleSeconds=2,timeout=60},hs)
 claudeDesktopTweaks=candidate
 assert(type(candidate)=='table' and type(candidate.stop)=='function' and type(candidate.snapshot)=='function','startup failed')
 local status=candidate.snapshot()
 if type(status)~='table' or status.running~=true or status.cleanupRequired then
  error('startup incomplete')
 end
 end)
 if not ok then
  if type(candidate)=='table' and type(candidate.stop)=='function' then pcall(candidate.stop) end
  error(reason)
 end
end`;}
function statAt(io,file){try{return io.lstatSync(file);}catch(e){if(e.code==='ENOENT')return null;throw e;}}
function directory(io,file,privateMode=false){const s=statAt(io,file);if(s&&(!s.isDirectory()||s.isSymbolicLink()||(privateMode&&(s.mode&0o077)!==0)||(process.getuid&&s.uid!==process.getuid())))throw new Error('Installation directory is invalid or not private.');return s;}
function read(io,file,privateMode=false){
 const s=statAt(io,file);if(!s)return null;
 if(!s.isFile()||s.isSymbolicLink()||(privateMode&&(s.mode&0o077)!==0)||(process.getuid&&s.uid!==process.getuid()))throw new Error('File is invalid or not private.');
 const fd=io.openSync(file,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);
 try{const current=io.fstatSync(fd);if(current.dev!==s.dev||current.ino!==s.ino)throw new Error('File changed during the operation.');const data=io.readFileSync(fd),after=io.fstatSync(fd);if(after.size!==s.size||after.mtimeMs!==s.mtimeMs||after.mode!==s.mode||data.length!==after.size)throw new Error('File changed during the operation.');return {data,dev:s.dev,ino:s.ino,mode:s.mode,mtime:s.mtimeMs};}finally{io.closeSync(fd);}
}
function unchanged(io,file,prior){const now=read(io,file);if(Boolean(now)!==Boolean(prior)||now&&(now.dev!==prior.dev||now.ino!==prior.ino||now.mode!==prior.mode||now.mtime!==prior.mtime||!now.data.equals(prior.data)))throw new Error('Configuration changed during the operation.');}
function digestFiles(files){const hash=createHash('sha256');for(const name of Object.keys(files).sort()){hash.update(name+'\0');hash.update(files[name]);hash.update('\0');}return hash.digest('hex');}
function runtimeBuild(root,io=fs){
 const files={};for(const [name,source]of Object.entries(SOURCES)){const file=read(io,path.join(root,source));if(!file)throw new Error('Runtime file is missing.');files[name]=file.data;}
 const {buildConsoleBundle}=require(path.join(root,'lib/persian/console-bundle.cjs'));
 files['bundle.json']=Buffer.from(JSON.stringify(buildConsoleBundle()));
 return {files,digest:digestFiles(files)};
}
function verifyRuntime(io,target,build,staging=false){
 const dir=directory(io,target,true);if(!dir||(dir.mode&0o777)!==(staging?0o700:0o500))throw new Error('Runtime directory permissions have changed.');
 const expected=[...Object.keys(build.files),'manifest.json'].sort();
 if(JSON.stringify(io.readdirSync(target).sort())!==JSON.stringify(expected))throw new Error('Installed content has changed.');
 const copied={};for(const name of Object.keys(build.files)){const file=read(io,path.join(target,name),true);if(file&&(file.mode&0o777)!==0o400)throw new Error('Runtime file permissions have changed.');if(!file||!file.data.equals(build.files[name]))throw new Error('Installed content has changed.');copied[name]=file.data;}
 const record=read(io,path.join(target,'manifest.json'),true);
 if(record&&(record.mode&0o777)!==0o400)throw new Error('Runtime manifest permissions have changed.');
 const manifest=record&&JSON.parse(record.data.toString('utf8'));
 if(!manifest||manifest.version!==1||manifest.digest!==build.digest||digestFiles(copied)!==manifest.digest)throw new Error('Installation manifest is invalid.');
}
function sameIdentity(io,file,expected,isDirectory=false){
 const now=statAt(io,file);return Boolean(expected&&now&&!now.isSymbolicLink()&&(isDirectory?now.isDirectory():now.isFile())&&now.dev===expected.dev&&now.ino===expected.ino);
}
function removeOwnedDirectory(io,target,identity,parent,parentIdentity){
 if(!target)return true;
 if(!sameIdentity(io,parent,parentIdentity,true)||!sameIdentity(io,target,identity,true))return false;
 io.chmodSync(target,0o700);io.rmSync(target,{recursive:true});return true;
}
function parseArgs(args){const options={mode:'--dry-run'};let chosen=false;for(const arg of args){
 if(['--dry-run','--install','--remove'].includes(arg)){if(chosen)throw new Error('Execution option is repeated.');options.mode=arg;chosen=true;}
 else if(arg.startsWith('--restore-backup=')){if(chosen||!arg.slice(17))throw new Error('Backup path is invalid.');options.mode='--restore';options.backupFile=arg.slice(17);chosen=true;}
 else throw new Error('Unknown option.');
 }return options;}
function setup({mode='--dry-run',backupFile,home=os.homedir(),root=path.resolve(__dirname,'..'),fileSystem:io=fs}={}){
 if(!['--dry-run','--install','--remove','--restore'].includes(mode))throw new Error('Execution option is invalid.');
 if(!path.isAbsolute(home)||!path.isAbsolute(root))throw new Error('An absolute path is required.');
 directory(io,home);
 const folder=path.join(home,'.hammerspoon'),file=path.join(folder,'init.lua'),runtimeRoot=path.join(folder,'claude-desktop-tweaks');
 directory(io,folder);directory(io,runtimeRoot,true);
 const original=read(io,file),text=original?original.data.toString('utf8'):'';
 if(text.includes('\0'))throw new Error('Configuration is invalid.');
 let updated,build,runtime;
 if(mode==='--restore'){
  if(typeof backupFile!=='string'||path.dirname(backupFile)!==folder||!/^init\.lua\.before-claude-desktop-tweaks-[0-9]+-[a-f0-9-]+\.bak$/.test(path.basename(backupFile)))throw new Error('Backup path is invalid.');
  const prior=read(io,backupFile,true);if(!prior||prior.data.includes(0))throw new Error('Backup is invalid.');updated=prior.data.toString('utf8');
 }else if(mode==='--remove')updated=updateConfig(text,null);
 else{build=runtimeBuild(root,io);runtime=path.join(runtimeRoot,build.digest);if(statAt(io,runtime))verifyRuntime(io,runtime,build);updated=updateConfig(text,renderConfig({runtime,statusFile:path.join(runtimeRoot,'status.json')}));}
 if(mode==='--dry-run')return {mode,changes:updated!==text,runtime,runtimeDigest:build.digest,runtimeChanges:!statAt(io,runtime)};
 if(updated===text&&(!runtime||statAt(io,runtime)))return {mode,changed:false,runtime};
 io.mkdirSync(folder,{recursive:true,mode:0o700});directory(io,folder);
 const parent=io.lstatSync(folder),lock=path.join(folder,'.claude-desktop-tweaks.lock');
 const lockFd=io.openSync(lock,fs.constants.O_WRONLY|fs.constants.O_CREAT|fs.constants.O_EXCL|fs.constants.O_NOFOLLOW,0o600);
 const lockIdentity=io.fstatSync(lockFd);
 let stage,stageIdentity,temp,tempIdentity,runtimeIdentity,runtimeParent,created=false,committed=false,backup=null,failure;
 try{
  unchanged(io,file,original);
  if(build){
   if(!statAt(io,runtimeRoot))io.mkdirSync(runtimeRoot,{mode:0o700});runtimeParent=directory(io,runtimeRoot,true);
   if(!statAt(io,runtime)){
    stage=path.join(runtimeRoot,'.staging-'+randomUUID());io.mkdirSync(stage,{mode:0o700});stageIdentity=io.lstatSync(stage);
    for(const [name,data]of Object.entries(build.files))io.writeFileSync(path.join(stage,name),data,{flag:'wx',mode:0o400});
    io.writeFileSync(path.join(stage,'manifest.json'),JSON.stringify({version:1,digest:build.digest}),{flag:'wx',mode:0o400});
    verifyRuntime(io,stage,build,true);
    // Keep the directory writable during the rename; apply final permissions only through our owned descriptor.
    const stageFd=io.openSync(stage,fs.constants.O_RDONLY|fs.constants.O_DIRECTORY|fs.constants.O_NOFOLLOW);
    try{
     const owned=io.fstatSync(stageFd);
     if(!owned.isDirectory()||owned.dev!==stageIdentity.dev||owned.ino!==stageIdentity.ino||
       !sameIdentity(io,folder,parent,true)||!sameIdentity(io,runtimeRoot,runtimeParent,true)||!sameIdentity(io,stage,stageIdentity,true))throw new Error('Runtime directory changed during the operation.');
     io.renameSync(stage,runtime);stage=null;created=true;runtimeIdentity=owned;
     io.fchmodSync(stageFd,0o500);
     if(!sameIdentity(io,folder,parent,true)||!sameIdentity(io,runtimeRoot,runtimeParent,true)||!sameIdentity(io,runtime,runtimeIdentity,true))throw new Error('Runtime directory changed during the operation.');
    }finally{io.closeSync(stageFd);}
   }
   verifyRuntime(io,runtime,build);
  }
  if(original){backup=file+'.before-claude-desktop-tweaks-'+Date.now()+'-'+randomUUID()+'.bak';io.writeFileSync(backup,original.data,{flag:'wx',mode:0o600});}
  temp=file+'.claude-desktop-tweaks-'+randomUUID();io.writeFileSync(temp,updated,{flag:'wx',mode:0o600});tempIdentity=statAt(io,temp);
  const currentParent=directory(io,folder);if(!currentParent||currentParent.dev!==parent.dev||currentParent.ino!==parent.ino)throw new Error('Directory changed during the operation.');
  unchanged(io,file,original);if(build){const current=directory(io,runtimeRoot,true);if(!current||current.dev!==runtimeParent.dev||current.ino!==runtimeParent.ino)throw new Error('Runtime directory changed during the operation.');verifyRuntime(io,runtime,build);}
  if(!sameIdentity(io,temp,tempIdentity)||read(io,temp,true)?.data.toString('utf8')!==updated)throw new Error('Temporary file changed during the operation.');
  io.renameSync(temp,file);temp=null;committed=true;
 }catch(error){failure=error;throw error;}finally{
  let cleanupRequired=false;
  try{
   if(temp){if(sameIdentity(io,folder,parent,true)&&sameIdentity(io,temp,tempIdentity))io.unlinkSync(temp);else cleanupRequired=true;}
   if(stage&&!removeOwnedDirectory(io,stage,stageIdentity,runtimeRoot,runtimeParent))cleanupRequired=true;
   if(created&&!committed&&!removeOwnedDirectory(io,runtime,runtimeIdentity,runtimeRoot,runtimeParent))cleanupRequired=true;
  }catch{cleanupRequired=true;}finally{
   io.closeSync(lockFd);
   if(sameIdentity(io,folder,parent,true)&&sameIdentity(io,lock,lockIdentity))io.unlinkSync(lock);else cleanupRequired=true;
  }
  if(cleanupRequired&&failure){failure.cleanupRequired=true;failure.message+=' Cleanup is incomplete; moved files were preserved.';}
 }

 return {mode,changed:true,config:file,runtime,runtimeDigest:build?.digest,backup,reloadRequired:true};
}
module.exports={setup,parseArgs,updateConfig,renderConfig,luaString,runtimeBuild,digestFiles};
