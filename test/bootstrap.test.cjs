'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),{spawnSync}=require('node:child_process'),{createHash}=require('node:crypto');
const script=path.resolve(__dirname,'../scripts/install.sh');
function fixture(t,bad=false,platform="Darwin",arch="arm64"){const dir=fs.mkdtempSync(path.join(os.tmpdir(),'cdt-bootstrap-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));const home=path.join(dir,'home'),bin=path.join(dir,'bin');fs.mkdirSync(home);fs.mkdirSync(bin);const asset=`claude-tweaks_${platform==='Linux'?'linux':'darwin'}_${arch==='x86_64'?'amd64':'arm64'}`;const bytes=Buffer.from('#!/bin/sh\nexit 0\n');fs.writeFileSync(path.join(dir,'binary'),bytes);fs.writeFileSync(path.join(dir,'checksums'),`${bad?'0'.repeat(64):createHash('sha256').update(bytes).digest('hex')}  ${asset}\n`);fs.writeFileSync(path.join(bin,'uname'),`#!/bin/sh\nif [ "$1" = "-m" ]; then echo ${arch}; else echo ${platform}; fi\n`,{mode:0o755});fs.writeFileSync(path.join(bin,'curl'),'#!/bin/sh\nout=\nurl=\nwhile [ "$#" -gt 0 ]; do case "$1" in --output) out=$2; shift;; https:*) url=$1;; esac; shift; done\ncase "$url" in */checksums.txt) cp "$FIXTURE/checksums" "$out";; */claude-tweaks_*) cp "$FIXTURE/binary" "$out";; *) exit 1;; esac\n',{mode:0o755});return {home,env:{...process.env,HOME:home,FIXTURE:dir,PATH:bin+':'+process.env.PATH}};}
test('Bootstrap installs a verified standalone binary without Node or Go',t=>{const f=fixture(t);const r=spawnSync('/bin/bash',[script,'--version','v1.1.0','--no-launch'],{env:f.env,encoding:'utf8'});assert.equal(r.status,0,r.stderr);const target=path.join(f.home,'Library/Application Support/Claude Desktop Tweaks/releases/v1.1.0/arm64/claude-tweaks');assert.equal(fs.statSync(target).mode&0o777,0o700);assert.match(r.stdout,/verified/i);});
test('Bad checksum never installs executable files',t=>{const f=fixture(t,true);const r=spawnSync('/bin/bash',[script,'--version','v1.1.0','--no-launch'],{env:f.env,encoding:'utf8'});assert.notEqual(r.status,0);assert.deepEqual(fs.readdirSync(f.home),[]);});
test('Bootstrap preserves symlink targets and unknown existing binaries',t=>{const f=fixture(t);const outside=fs.mkdtempSync(path.join(os.tmpdir(),'cdt-outside-'));t.after(()=>fs.rmSync(outside,{recursive:true,force:true}));fs.symlinkSync(outside,path.join(f.home,'Library'));let r=spawnSync('/bin/bash',[script,'--version','v1.1.0','--no-launch'],{env:f.env,encoding:'utf8'});assert.notEqual(r.status,0);assert.deepEqual(fs.readdirSync(outside),[]);fs.unlinkSync(path.join(f.home,'Library'));const dir=path.join(f.home,'Library/Application Support/Claude Desktop Tweaks/releases/v1.1.0/arm64');fs.mkdirSync(dir,{recursive:true});fs.writeFileSync(path.join(dir,'claude-tweaks'),'unrelated');r=spawnSync('/bin/bash',[script,'--version','v1.1.0','--no-launch'],{env:f.env,encoding:'utf8'});assert.notEqual(r.status,0);assert.equal(fs.readFileSync(path.join(dir,'claude-tweaks'),'utf8'),'unrelated');});
test('Bootstrap rejects unsafe versions before downloading',t=>{const f=fixture(t);const r=spawnSync('/bin/bash',[script,'--version','../../bad','--no-launch'],{env:f.env,encoding:'utf8'});assert.notEqual(r.status,0);assert.deepEqual(fs.readdirSync(f.home),[]);});

test('Linux bootstrap installs both architectures and honors XDG_DATA_HOME',t=>{for(const [machine,arch] of [['x86_64','amd64'],['aarch64','arm64']]){const f=fixture(t,false,'Linux',machine);f.env.XDG_DATA_HOME=path.join(f.home,'data files');const r=spawnSync('/bin/bash',[script,'--version','v1.1.4','--no-launch'],{env:f.env,encoding:'utf8'});assert.equal(r.status,0,r.stderr);assert.equal(fs.statSync(path.join(f.env.XDG_DATA_HOME,'Claude Desktop Tweaks/releases/v1.1.4',arch,'claude-tweaks')).mode&0o777,0o700);}});
test('Linux bootstrap preserves external and symlink XDG directories',t=>{const f=fixture(t,false,'Linux','x86_64');f.env.XDG_DATA_HOME='/tmp/external-cdt-data';const r=spawnSync('/bin/bash',[script,'--version','v1.1.4','--no-launch'],{env:f.env,encoding:'utf8'});assert.notEqual(r.status,0);assert.deepEqual(fs.readdirSync(f.home),[]);});

test('Bootstrap reports download and verification phases without terminal escapes in a pipe',t=>{
 const f=fixture(t);const r=spawnSync('/bin/bash',[script,'--version','v1.4.1','--no-launch'],{env:f.env,encoding:'utf8'});
 assert.equal(r.status,0,r.stderr);assert.match(r.stdout,/Downloading installer/);assert.match(r.stdout,/Verifying download/);assert.match(r.stdout,/Download verified/);assert.doesNotMatch(r.stdout+r.stderr,/\x1b/);
});
test('Download metrics show real percent and omit it for unknown lengths',()=>{
 const source=fs.readFileSync(script,'utf8');const helpers=source.match(/# Progress helpers\n([\s\S]*?)# End progress helpers/);assert.ok(helpers,'progress formatter missing');
 const run=(total)=>spawnSync('/bin/bash',['-c',helpers[1]+`\nprogress_metrics 1048576 ${total} 2`],{encoding:'utf8'});
 assert.match(run(2097152).stdout,/50%/);assert.match(run(2097152).stdout,/1\.0 \/ 2\.0 MB/);assert.match(run(2097152).stdout,/512 KB\/s/);
 assert.doesNotMatch(run(0).stdout,/%/);assert.match(run(0).stdout,/1\.0 MB/);
});

test('Interactive download refreshes one region and finishes at a real 100 percent',t=>{
 const f=fixture(t);const curl=path.join(f.env.FIXTURE,'bin/curl');
 fs.writeFileSync(curl,`#!/bin/sh
out= headers= url=
while [ "$#" -gt 0 ]; do case "$1" in --output) out=$2;shift;; --dump-header) headers=$2;shift;; https:*) url=$1;; esac;shift;done
case "$url" in */checksums.txt) source="$FIXTURE/checksums";; *) source="$FIXTURE/binary";; esac
length=$(wc -c < "$source" | tr -d ' ')
printf 'HTTP/2 200\\r\\nContent-Length: %s\\r\\n\\r\\n' "$length" > "$headers"
head -c 4 "$source" > "$out"
sleep 0.3
cat "$source" > "$out"
sleep 0.3
`,{mode:0o755});
 const harness=`import os,pty,subprocess,select,errno\nm,s=pty.openpty()\np=subprocess.Popen(['/bin/bash',${JSON.stringify(script)},'--version','v1.4.1','--no-launch'],stdout=s,stderr=s,env=os.environ.copy())\nos.close(s)\nout=b''\nwhile True:\n try:\n  data=os.read(m,65536)\n  if not data:break\n  out+=data\n except OSError as e:\n  if e.errno==errno.EIO:break\n  raise\nos.close(m)\np.wait(timeout=10)\nprint(out.decode())\nraise SystemExit(p.returncode)\n`;
 const result=spawnSync('python3',['-c',harness],{env:{...f.env,TERM:'xterm-256color',NO_COLOR:'1'},encoding:'utf8',timeout:15000});
 assert.equal(result.status,0,result.stderr);assert.match(result.stdout,/100%/);assert.match(result.stdout,/KB\/s/);assert.match(result.stdout,/\x1b\[2A/);assert.doesNotMatch(result.stdout,/38;2;/,'NO_COLOR is respected');
});

test('Cancelled downloads stop the transfer and remove scratch files',async t=>{
 const {spawn}=require('node:child_process');const f=fixture(t);const scratch=path.join(f.env.FIXTURE,'scratch');fs.mkdirSync(scratch);f.env.TMPDIR=scratch;
 fs.writeFileSync(path.join(f.env.FIXTURE,'bin/curl'),'#!/bin/sh\nprintf "%s" "$$" > "$FIXTURE/transfer-pid"\nexec sleep 20\n',{mode:0o755});
 const child=spawn('/bin/bash',[script,'--version','v1.4.1','--no-launch'],{env:f.env,stdio:'pipe'});
 t.after(()=>child.kill('SIGKILL'));let errors='';child.stderr.on('data',b=>errors+=b);
 const closed=new Promise(resolve=>child.once('close',(code,signal)=>resolve({code,signal})));
 const deadline=Date.now()+4000;while(!fs.existsSync(path.join(f.env.FIXTURE,'transfer-pid'))){assert.ok(Date.now()<deadline,'transfer did not start');await new Promise(r=>setTimeout(r,20));}
 const pid=Number(fs.readFileSync(path.join(f.env.FIXTURE,'transfer-pid'),'utf8'));child.kill('SIGTERM');const result=await closed;
 assert.equal(result.code,130,errors);assert.throws(()=>process.kill(pid,0));assert.deepEqual(fs.readdirSync(scratch),[]);assert.deepEqual(fs.readdirSync(f.home),[]);assert.match(errors,/cancelled/);
});
test('Narrow terminals use plain progress instead of wrapping cursor updates',()=>{
 const source=fs.readFileSync(script,'utf8');const helpers=source.match(/# Progress helpers\n([\s\S]*?)# End progress helpers/)[1];
 const r=spawnSync('/bin/bash',['-c',helpers+'\nprogress_tty=1; progress_drawn=0; COLUMNS=30; progress_frame "Downloading installer" "Receiving data"'],{encoding:'utf8'});
 assert.equal(r.status,0,r.stderr);assert.doesNotMatch(r.stderr,/\x1b/);
});
