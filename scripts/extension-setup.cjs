'use strict';
const fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {spawnSync}=require('node:child_process');
const {createHash,randomUUID}=require('node:crypto');
const {buildExtension}=require('../lib/persian/extension-package.cjs');
const {updateConfig}=require('./setup.cjs');
const LABEL='local.claude-desktop-tweaks.environment';
const ID='fmkadmapgofadopljbjfkapdkoienihi';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
function agentXml(){return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>${LABEL}</string>
<key>ProgramArguments</key><array><string>/bin/launchctl</string><string>setenv</string><string>REACT_PROFILE</string><string>1</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
`;}
function stat(file){try{return fs.lstatSync(file);}catch(e){if(e.code==='ENOENT')return null;throw e;}}
function read(file){
 const s=stat(file);if(!s)return null;
 if(!s.isFile()||s.isSymbolicLink()||s.uid!==process.getuid()||s.size>4*1024*1024)throw Error('Invalid installation file.');
 const fd=fs.openSync(file,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);
 try{const now=fs.fstatSync(fd);if(now.ino!==s.ino||now.dev!==s.dev)throw Error('Installation file changed.');return fs.readFileSync(fd);}finally{fs.closeSync(fd);}
}
function checkParents(home,file,create=false){
 const relative=path.relative(home,file);
 if(relative.startsWith('..')||path.isAbsolute(relative))throw Error('Installation path is outside home.');
 let current=home;
 for(const part of ['',...relative.split(path.sep).filter(Boolean)]){
  if(part)current=path.join(current,part);
  let s=stat(current);
  if(!s&&create){fs.mkdirSync(current,{mode:0o700});s=stat(current);}
  if(s&&(!s.isDirectory()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&0o022)!==0))throw Error('Installation directory is invalid or symbolic.');
 }
}
function extensionFiles(root,features){
 const {manifest,source}=buildExtension({features});
 const files={'manifest.json':Buffer.from(JSON.stringify(manifest,null,2)+'\n'),'content.js':Buffer.from(source)};
 for(const [name,source]of [['LICENSE','LICENSE'],['Estedad-OFL.txt','assets/estedad/OFL.txt'],['Nord-LICENSE','assets/nord/LICENSE'],['NOTICE.md','NOTICE.md']])files[name]=fs.readFileSync(path.join(root,source));
 return files;
}
function installExtension({home=os.homedir(),root=path.resolve(__dirname,'..'),platform=process.platform,run=(cmd,args)=>spawnSync(cmd,args,{encoding:'utf8',timeout:10000}),dryRun=false,features}={}){
 if(platform!=='darwin')throw Error('Automatic extension installation requires macOS.');
 if(!path.isAbsolute(home)||!path.isAbsolute(root))throw Error('Absolute installation paths are required.');
 const target=path.join(home,'Library/Application Support/Claude/extensions',ID);
 const stateDir=path.join(home,'Library/Application Support/Claude Desktop Tweaks');
 const receipt=path.join(stateDir,'extension-startup.json');
 const agent=path.join(home,'Library/LaunchAgents',LABEL+'.plist');
 const config=path.join(home,'.hammerspoon/init.lua');
 for(const p of [target,stateDir,path.dirname(agent),path.dirname(config)])checkParents(home,p);
 function command(cmd,args,allowFailure=false){
  const r=run(cmd,args);
  if(r.error||!Number.isInteger(r.status)||(!allowFailure&&r.status!==0))throw Error(`System command failed: ${path.basename(cmd)} ${args[0]}.`);
  return r;
 }
 function closed(name){const r=command('/usr/bin/pgrep',['-x',name],true);if(r.status===0)throw Error(`Quit ${name} and run the installer again. The installer does not quit apps.`);if(r.status!==1)throw Error('Could not verify closed application.');}
 closed('Claude');
 const originalConfig=read(config);
 const updatedConfig=originalConfig&&Buffer.from(updateConfig(originalConfig.toString('utf8'),null));
 const migrate=originalConfig&&!originalConfig.equals(updatedConfig);
 if(migrate)closed('Hammerspoon');
 const files=extensionFiles(root,features),oldReceipt=read(receipt);
 const previous=oldReceipt?JSON.parse(oldReceipt):null;
 if(previous&&previous.previousReactProfile!==null&&typeof previous.previousReactProfile!=='string')throw Error('Invalid extension rollback record.');
 const installed=stat(target);
 if(installed){
  const manifest=read(path.join(target,'manifest.json')),source=read(path.join(target,'content.js'));
  if(!manifest||!source||JSON.parse(manifest).name!=='Claude Desktop Persian Tweaks')throw Error('Existing extension is not owned by this installer.');
  const proven=previous?.extensionSha256===sha(source)||Object.entries(files).every(([name,data])=>read(path.join(target,name))?.equals(data));
  if(!proven)throw Error('Existing extension ownership cannot be verified. Preserve it before installing.');
 }
 const oldAgent=read(agent);
 const normalize=b=>b.toString('utf8').replace(/>\s+</g,'><').trim();
 if(oldAgent&&normalize(oldAgent)!==normalize(Buffer.from(agentXml())))throw Error('Existing startup agent is not owned by this installer.');
 const env=command('/bin/launchctl',['getenv','REACT_PROFILE'],true);
 if(![0,1].includes(env.status))throw Error('Could not read previous launch environment.');
 const beforeEnv=env.status===0?env.stdout.replace(/\n$/,''):null;
 const domain='gui/'+process.getuid();
 const loaded=command('/bin/launchctl',['print',domain+'/'+LABEL],true).status===0;
 if(loaded&&!oldAgent)throw Error('An unowned startup job is already registered.');
 const same=Boolean(installed)&&Object.entries(files).every(([name,data])=>read(path.join(target,name))?.equals(data));
 if(dryRun)return {mode:'--extension-dry-run',changes:!same||!oldAgent||!previous||migrate||!loaded||beforeEnv!=='1',migrationRequired:Boolean(migrate),installed:Boolean(installed)};
 checkParents(home,stateDir,true);
 const lock=path.join(stateDir,'.extension-install.lock');
 const lockFd=fs.openSync(lock,fs.constants.O_WRONLY|fs.constants.O_CREAT|fs.constants.O_EXCL|fs.constants.O_NOFOLLOW,0o600);
 const lockIdentity=fs.fstatSync(lockFd);
 const backup=path.join(stateDir,'backups',Date.now()+'-'+randomUUID());
 const undo=[];let registrationAttempted=false,envTouched=false,backupCreated=false,stage;
 function backupDir(){if(!backupCreated){checkParents(home,backup,true);backupCreated=true;}return backup;}
 function write(file,data,before){
  const now=read(file);if(Boolean(now)!==Boolean(before)||now&&!now.equals(before))throw Error('Installation file changed concurrently.');
  if(now?.equals(data))return;
  checkParents(home,path.dirname(file),true);
  const temp=file+'.cdt-'+randomUUID();
  fs.writeFileSync(temp,data,{flag:'wx',mode:0o600});
  try{const current=read(file);if(Boolean(current)!==Boolean(before)||current&&!current.equals(before))throw Error('Installation file changed concurrently.');fs.renameSync(temp,file);}finally{if(stat(temp))fs.unlinkSync(temp);}
  undo.push(()=>{const current=read(file);if(!current?.equals(data))throw Error('Concurrent changes preserved.');if(before)fs.writeFileSync(file,before,{mode:0o600});else fs.unlinkSync(file);});
 }
 try{
  closed('Claude');if(migrate)closed('Hammerspoon');
  if(!same){
   checkParents(home,path.dirname(target),true);
   stage=target+'.stage-'+randomUUID();fs.mkdirSync(stage,{mode:0o700});
   for(const [name,data]of Object.entries(files))fs.writeFileSync(path.join(stage,name),data,{flag:'wx',mode:0o600});
   const current=stat(target);
   if(Boolean(current)!==Boolean(installed)||current&&(current.ino!==installed.ino||current.dev!==installed.dev))throw Error('Extension directory changed concurrently.');
   if(installed)fs.renameSync(target,path.join(backupDir(),'extension'));
   try{fs.renameSync(stage,target);stage=null;}catch(e){if(installed)fs.renameSync(path.join(backup,'extension'),target);throw e;}
   const identity=stat(target);
   undo.push(()=>{const s=stat(target);if(!s||s.ino!==identity.ino||s.dev!==identity.dev||!Object.entries(files).every(([n,d])=>read(path.join(target,n))?.equals(d))||fs.readdirSync(target).length!==Object.keys(files).length)throw Error('Concurrent extension changes preserved.');fs.rmSync(target,{recursive:true});if(installed)fs.renameSync(path.join(backup,'extension'),target);});
  }
  if(oldAgent===null)write(agent,Buffer.from(agentXml()),null);
  if(!loaded){registrationAttempted=true;envTouched=true;command('/bin/launchctl',['bootstrap',domain,agent]);}
  envTouched=true;command('/bin/launchctl',['setenv','REACT_PROFILE','1']);
  if(command('/bin/launchctl',['getenv','REACT_PROFILE']).stdout.trim()!=='1')throw Error('Launch environment verification failed.');
  command('/bin/launchctl',['print',domain+'/'+LABEL]);
  let hammerspoonBackup=previous?.hammerspoonBackup??null;
  if(migrate){
   hammerspoonBackup=config+'.before-claude-desktop-tweaks-'+Date.now()+'-'+randomUUID()+'.bak';
   fs.writeFileSync(hammerspoonBackup,originalConfig,{flag:'wx',mode:0o600});
   write(config,updatedConfig,originalConfig);
  }
  const record={...previous,installerVersion:1,features:features??{font:true,theme:true,rtl:true},extensionSha256:sha(files['content.js']),agentLabel:LABEL,agentPath:agent,previousReactProfile:previous?previous.previousReactProfile:beforeEnv,hammerspoonBackup};
  if(previous?.extensionSha256!==record.extensionSha256){record.coldStartAfterPermanentSetupVerified=false;delete record.normalLaunchAcceptance;}
  const data=Buffer.from(JSON.stringify(record,null,2)+'\n');
  if(oldReceipt&&!oldReceipt.equals(data))fs.writeFileSync(path.join(backupDir(),'extension-startup.json'),oldReceipt,{flag:'wx',mode:0o600});
  write(receipt,data,oldReceipt);
  return {mode:'--install-extension',installed:true,changed:!same||!oldAgent||!oldReceipt?.equals(data)||Boolean(migrate)||!loaded||beforeEnv!=='1',restartClaude:true,backup:backupCreated?backup:null,hammerspoonBackup,rollbackRecord:receipt};
 }catch(error){
  const failures=[];
  if(registrationAttempted)try{if(command('/bin/launchctl',['print',domain+'/'+LABEL],true).status===0)command('/bin/launchctl',['bootout',domain+'/'+LABEL]);}catch{failures.push('startup job');}
  if(envTouched)try{const current=command('/bin/launchctl',['getenv','REACT_PROFILE'],true);const value=current.status===0?current.stdout.replace(/\n$/,''):null;if(value!==beforeEnv){if(value!=='1')throw Error('Concurrent environment preserved.');command('/bin/launchctl',beforeEnv===null?['unsetenv','REACT_PROFILE']:['setenv','REACT_PROFILE',beforeEnv]);}}catch{failures.push('launch environment');}
  for(const restore of undo.reverse())try{restore();}catch{failures.push('files');}
  if(failures.length)throw Error(`${error.message} Rollback incomplete; preserve backups in ${backup}.`);
  throw error;
 }finally{
  if(stage&&stat(stage))fs.rmSync(stage,{recursive:true});
  fs.closeSync(lockFd);const s=stat(lock);if(s?.ino===lockIdentity.ino&&s.dev===lockIdentity.dev)fs.unlinkSync(lock);
 }
}
module.exports={installExtension,agentXml};
