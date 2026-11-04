-- Synthetic adapter only. No native app, console, clipboard, or user data is accessed.
local M=assert(loadfile(assert(arg[1])))()
local assertions,scenarios=0,0
local function check(value,message)assertions=assertions+1;assert(value,message)end
local nonce=string.rep('a',32)
local documentId=string.rep('b',32)
local function fixture(options)
 scenarios=scenarios+1;options=options or {}
 local state={now=0,prompt='',writes=0,executes=0,focuses=0,releases={},pending=nil,receipt=nil,
  codes={},identity={owned=true,pid=123,bundle='com.anthropic.claudefordesktop',path='/Applications/Claude.app',
   sourceWindowId=10,toolsWindowId=20,contextId='top',documentId=documentId,sourceURL='https://claude.ai/chat/synthetic',interactionVersion=0}}
 local handle={};local token={}
 local adapter={now=function()return state.now end,
  claim=function(capability)if options.noClaim or capability~=token then return nil end;return handle end,
  inspect=function(h)check(h==handle,'inspect uses opaque claimed handle');return state.identity end,
  promptValue=function(h)check(h==handle,'prompt reads use owned handle');return state.prompt end,
  writePrompt=function(h,before,code)
   check(h==handle and before=='' and state.prompt==before,'compare-and-write requires exact old prompt')
   state.writes=state.writes+1;state.pending=code
   if not options.delayed then state.prompt=code end
   return not options.writeRefused
  end,
  focusPrompt=function(h)check(h==handle,'focus is local to claimed console');state.focuses=state.focuses+1;return not options.focusRefused end,
  execute=function(h,expected)
   check(h==handle and expected==state.prompt,'Return requires exact verified complete code')
   if options.focusPending then return 'pending'end
   if options.executeRefused then return false end
   state.executes=state.executes+1;state.codes[#state.codes+1]=expected
   check(not expected:find('eval%(') and not expected:find('new Function'),'dispatch does not evaluate serialized source')
   check(expected:find('location.href===',1,true) and expected:find('r.document===document',1,true),'page script independently verifies source and document')
   state.prompt=''
   state.receipt={marker='CDT_DIRECT_RECEIPT',nonce=nonce,sequence=state.executes,documentId=documentId,ok=not options.executionFails and state.executes~=options.failAt}
   if options.executionFails and state.executes>1 then state.receipt.ok=true end
   return true
  end,
  receipt=function(h,n,sequence)check(h==handle and n==nonce and sequence>=1,'read exact receipt nonce and ordinal');return options.noReceipt and nil or state.receipt end,
  release=function(h,close)check(h==handle,'release uses claimed capability');state.releases[#state.releases+1]=close;return not options.releaseFails end}
 local controller=M.new({timeout=2},adapter)
 local request={ownership=token,nonce=nonce,plan=M.dataPlan('__cdt_fixture',nonce,'YWJj','const text=window.__cdt_fixture.chunks.join("");')}
 return {state=state,controller=controller,request=request,options=options,adapter=adapter,
  run=function(limit)
   for _=1,limit or 100 do
    controller.tick();state.now=state.now+0.01
    local phase=controller.snapshot().phase
    if phase=='complete' or phase=='stopped'then break end
   end
   return controller.snapshot()
  end}
end
local f=fixture();check(f.controller.begin(f.request),'explicit ownership starts transaction')
local result=f.run()
check(result.ok and result.phase=='complete' and not result.cleanupRequired,'all receipts and namespace cleanup complete')
check(f.state.executes==4 and result.completed==3,'bootstrap data and apply execute before cleanup')
check(f.state.releases[1]==true,'only successfully cleaned owned console is eligible for close')
for k in pairs(result)do check(k~='sourceURL' and k~='documentId' and k~='contextId' and k~='code','snapshot excludes target and source content')end
check(not f.controller.begin(f.request),'nonce reuse rejected')

f=fixture({delayed=true});check(f.controller.begin(f.request),'delayed AX handoff')
f.controller.tick();f.controller.tick()
check(f.state.executes==0 and f.state.focuses==0,'accepted write does not count as visible AX echo')
f.state.prompt=f.state.pending
f.controller.tick();check(f.state.executes==0,'local focus is a separate verified stage')
f.controller.tick();check(f.state.executes==1,'exact delayed echo permits targeted Return')
f.controller.stop();check(f.controller.snapshot().cleanupRequired,'cancelled namespace work reports required cleanup')
check(f.state.releases[1]==false,'cancelled console is never automatically closed')

for _,key in ipairs({'pid','sourceWindowId','toolsWindowId','contextId','documentId','sourceURL','interactionVersion'})do
 f=fixture();f.controller.begin(f.request);f.controller.tick()
 local old=f.state.identity[key]
 f.state.identity[key]=type(old)=='number' and old+1 or old..'changed'
 local s=f.controller.tick()
 check(s.phase=='stopped' and not s.ok,'changed '..key..' stops transaction')
 check(f.state.executes==0 and f.state.releases[1]==false,'changed target prevents Return and automatic close')
 check(s.cleanupRequired,'pending AX writes are reported even before JS execution')
end
f=fixture();f.controller.begin(f.request);f.state.identity.owned=false;f.controller.tick()
check(f.controller.snapshot().reason=='ownership-lost','lost ownership is closed without actions')
check(f.state.writes==0,'lost ownership prevents writes')

for _,phaseTicks in ipairs({0,1,2,3})do
 f=fixture();f.controller.begin(f.request)
 for _=1,phaseTicks do f.controller.tick()end
 f.state.prompt='user input';f.controller.tick()
 check(f.controller.snapshot().phase=='stopped','user prompt stops at each stage')
 check(f.state.prompt=='user input','user console text is never cleared')
 check(f.state.releases[1]==false,'prompt conflict never closes console')
end
f=fixture({delayed=true});f.controller.begin(f.request);f.controller.tick();f.state.now=3;f.controller.tick()
check(f.controller.snapshot().reason=='timeout' and f.controller.snapshot().cleanupRequired,'delayed write timeout remains explicit cleanup')
f=fixture({noReceipt=true});f.controller.begin(f.request);f.controller.tick();f.controller.tick();f.controller.tick();f.state.now=3;f.controller.tick()
check(f.controller.snapshot().reason=='timeout','missing result times out without sending duplicate commands')
check(f.state.executes==1,'receipt timeout never repeats a command')

for _,field in ipairs({'nonce','sequence','documentId','marker'})do
 f=fixture();f.controller.begin(f.request);f.controller.tick();f.controller.tick();f.controller.tick()
 f.state.receipt[field]=field=='sequence' and 99 or 'wrong'
 f.controller.tick();check(f.controller.snapshot().reason=='receipt-mismatch','wrong '..field..' cannot authorize cleanup or progress')
 check(f.state.releases[1]==false,'bad receipt keeps owned console open')
end
f=fixture({executionFails=true});f.controller.begin(f.request);local s=f.run()
check(not s.ok and s.cleanupRequired and f.state.executes==1,'failed bootstrap never deletes an existing namespace')
check(f.state.releases[1]==false,'uncertain bootstrap remains available for inspection')
f=fixture({failAt=2});f.controller.begin(f.request);s=f.run()
check(not s.ok and s.reason=='execution-failed' and not s.cleanupRequired,'verified later failure cleans its own initialized namespace')
check(f.state.executes==3 and f.state.releases[1]==true,'failure cleanup completes before owned-console release')
f=fixture({releaseFails=true});f.controller.begin(f.request);s=f.run()
check(s.cleanupRequired and s.released==false and not s.ok,'release failure is never hidden')

for _,options in ipairs({{noClaim=true},{writeRefused=true},{focusRefused=true},{executeRefused=true}})do
 f=fixture(options);local ok=f.controller.begin(f.request)
 if ok then f.run()end
 check(not ok or not f.controller.snapshot().ok,'adapter refusal never produces success')
end
f=fixture();f.controller.begin(f.request);f.controller.tick();f.state.now=121;f.controller.tick()
check(f.controller.snapshot().reason=='transaction-timeout','whole transaction remains bounded independently of per-command progress')
f=fixture({focusPending=true});f.controller.begin(f.request);f.run(10)
check(f.state.executes==0,'pending local focus does not dispatch Return')
f.state.now=4;f.controller.tick();check(f.controller.snapshot().reason=='timeout','local focus waiting is bounded')
f=fixture();f.request.ownership={};check(not f.controller.begin(f.request),'unrelated capability cannot claim console')
f=fixture();f.state.prompt='existing';check(not f.controller.begin(f.request),'handoff refuses nonempty prompt')
check(f.state.prompt=='existing','handoff preserves existing prompt')
f=fixture();f.state.identity.sourceURL='https://claude.ai.evil.invalid/';check(not f.controller.begin(f.request),'lookalike origin is rejected')
for _,url in ipairs({'https://claude.ai/login','https://claude.ai/api/data','https://claude.ai/auth/callback'})do
 f=fixture();f.state.identity.sourceURL=url;check(not f.controller.begin(f.request),'auth and API routes are rejected')
end
for _,url in ipairs({'file:///Applications/Claude.app/Contents/Resources/app.asar/.vite/renderer/unknown/index.html',
 'file:///tmp/Claude.app/Contents/Resources/app.asar/.vite/renderer/main_window/index.html',
 'https://claude.ai/chat/'..string.char(226,128,168), 'https://claude.ai/chat/'..string.char(226,128,169)})do
 f=fixture();f.state.identity.sourceURL=url;check(not f.controller.begin(f.request),'unknown shells and raw Unicode separators are rejected')
end
for _,directory in ipairs({'main_window','quick_window','about_window','find_in_page'})do
 f=fixture();f.state.identity.sourceURL='file:///Applications/Claude.app/Contents/Resources/app.asar/.vite/renderer/'..directory..'/index.html'
 check(f.controller.begin(f.request),'known renderer directory accepted');f.controller.stop()
end
f=fixture();f.request.nonce='bad';check(not f.controller.begin(f.request),'nonce format is bounded')
f=fixture();f.request.plan.commands[1]=string.rep('x',12001);check(not f.controller.begin(f.request),'oversized commands rejected before ownership claim')
for _,args in ipairs({{'existing',nonce,'YWJj','x'},{'__cdt_valid','bad','YWJj','x'},{'__cdt_valid',nonce,'x";attack()','x'}})do
 check(not pcall(M.dataPlan,table.unpack(args)),'invalid data plan rejected')
end
local plan=M.dataPlan('__cdt_valid',nonce,string.rep('A',12001),'const complete=true;')
check(#plan.commands==5,'large font data splits into bounded chunks')
check(plan.commands[1]:find('hasOwnProperty',1,true)~=nil,'bootstrap cannot replace an existing namespace')
check(plan.cleanup:find('.owner===',1,true)~=nil,'cleanup checks exact namespace ownership')
f=fixture();f.controller.begin(f.request);f.controller.stop();local before=f.state.writes;f.controller.tick()
check(f.state.writes==before and f.controller.snapshot().reason=='cancelled','stopped dispatcher cannot resume')

-- Parse and execute the generated JavaScript in Node's isolated VM. Only synthetic
-- source files are passed to Node; no command text or source URL enters the shell.
f=fixture()
f.state.identity.sourceURL='https://claude.ai/chat/synthetic?x=";globalThis.injected=true;//`'
f.request.plan=M.dataPlan('__cdt_fixture',nonce,'YWJj',
 'await new Promise(resolve=>{globalThis.continueApply=resolve;});globalThis.appliedData=window.__cdt_fixture.chunks.join("");')
check(f.controller.begin(f.request),'generated source fixture starts')
check(f.run().ok,'generated source fixture completes')
local files={}
local function file(contents)
 local name=os.tmpname();local out=assert(io.open(name,'wb'));out:write(contents);out:close();files[#files+1]=name;return name
end
local harness=file([====[
'use strict';
const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const codes=process.argv.slice(2).map(path=>fs.readFileSync(path,'utf8'));
for(const source of codes)new vm.Script(source);
function environment(){
 const document={};const logs=[];const window={__claudePersianConsoleDocumentV1:{document,id:'b'.repeat(32)}};
 const context=vm.createContext({window,document,location:{href:'https://claude.ai/chat/synthetic?x=";globalThis.injected=true;//`'},console:{log(value){logs.push(JSON.parse(value));}}});
 return {context,window,logs};
}
(async()=>{
 const f=environment();
 for(let index=0;index<codes.length;index++){
  const pending=vm.runInContext(codes[index],f.context,{timeout:1000});
  if(f.context.continueApply){const resume=f.context.continueApply;delete f.context.continueApply;resume();}
  await pending;
  assert.equal(f.logs.at(-1).ok,true);
  assert.equal(f.logs.at(-1).sequence,index+1);
 }
 assert.equal(f.context.appliedData,'YWJj');
 assert.equal(f.context.injected,undefined,'hostile-looking URL remains string data');
 assert.equal(f.window.__cdt_fixture,undefined,'only owned temporary namespace is removed');
 const existing=environment();const original={owner:'a'.repeat(32),chunks:['original']};existing.window.__cdt_fixture=original;
 await vm.runInContext(codes[0],existing.context,{timeout:1000});
 assert.equal(existing.logs.at(-1).ok,false);
 assert.equal(existing.window.__cdt_fixture,original,'bootstrap refuses to overwrite an existing namespace');
 const changed=environment();
 await vm.runInContext(codes[0],changed.context,{timeout:1000});
 await vm.runInContext(codes[1],changed.context,{timeout:1000});
 const applying=vm.runInContext(codes[2],changed.context,{timeout:1000});
 assert.equal(typeof changed.context.continueApply,'function');
 changed.context.document={};changed.window.__claudePersianConsoleDocumentV1={document:changed.context.document,id:'b'.repeat(32)};
 changed.context.continueApply();await applying;
 assert.equal(changed.logs.at(-1).ok,false,'document replacement during await cannot report success');
})().catch(error=>{console.error(error);process.exitCode=1;});
]====])
local command="node '"..harness:gsub("'","'\\''").."'"
for _,code in ipairs(f.state.codes)do local name=file(code);command=command.." '"..name:gsub("'","'\\''").."'"end
local nodeOK=os.execute(command)
for _,name in ipairs(files)do os.remove(name)end
check(nodeOK==true or nodeOK==0,'generated JS syntax source guards data isolation and cleanup pass in Node')

print(string.format('direct dispatch: %d assertions, %d scenarios',assertions,scenarios))
return {ok=true,assertions=assertions,scenarios=scenarios}
