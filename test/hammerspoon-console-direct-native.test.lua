-- Native API simulation only. No real app or system input is touched.
local M=assert(loadfile(assert(arg[1])))()
local assertions,scenarios=0,0
local function check(v,message)assertions=assertions+1;assert(v,message)end
local nonce=string.rep('a',32);local documentId=string.rep('b',32)
local function node(attrs)
 local e={attrs=attrs or{}}
 function e:attributeValue(k)return self.attrs[k]end
 function e:setAttributeValue(k,v)
  self.sets=self.sets or{};self.sets[#self.sets+1]={k,v}
  if k=='AXValue'then self.pending=v else self.attrs[k]=v end
  return self
 end
 function e:isAttributeSettable()return true end
 function e:asHSWindow()return self.window end
 return e
end
local function fixture(options)
 scenarios=scenarios+1;options=options or{}
 local s={pid=123,foreground=999,focusWindow=20,returns=0,closes=0,tapStops=0,observerStops=0,version=0}
 local a={pid=function()return s.pid end,bundleID=function()return options.wrongBundle and 'other' or 'com.anthropic.claudefordesktop'end,path=function()return options.wrongPath and '/tmp/Claude.app' or '/Applications/Claude.app'end}
 local sourceArea=node({AXRole='AXWebArea',AXURL='https://claude.ai/chat/synthetic'})
 local prompt=node({AXRole='AXTextArea',AXDescription='Console prompt',AXValue='\n',AXChildren={node({AXRole='AXGroup'})},AXFocused=false})
 local context=node({AXRole='AXButton',AXTitle='JavaScript context: top'})
 local source=node({AXRole='AXWindow',AXChildren={sourceArea}})
 local tools=node({AXRole='AXWindow',AXChildren={prompt,context}})
 local function window(id,title,element)
  local w={id=function()return id end,title=function()return title end,application=function()return a end}
  function w:close()s.closes=s.closes+1;if not options.asyncClose then s.tools=false end;return not options.closeRefused end
  element.window=w;return w
 end
 local sourceWindow=window(10,'Synthetic chat',source)
 local toolsWindow=window(20,'Developer Tools - https://claude.ai/chat/synthetic',tools)
 local root=node({AXRole='AXApplication'})
 function a:allWindows()local out={sourceWindow};if s.tools then out[#out+1]=toolsWindow end;return out end
 local oldAttr=root.attributeValue
 function root:attributeValue(k)
  if k=='AXWindows'then local out={source};if s.tools then out[#out+1]=tools end;return out end
  if k=='AXFocusedWindow'then return s.tools and s.focusWindow==20 and tools or source end
  if k=='AXFocusedUIElement'then return s.localFocus and prompt or sourceArea end
  return oldAttr(self,k)
 end
 local tap={start=function(self)s.tapActive=not options.tapDisabled;return self end,isEnabled=function()return s.tapActive end,stop=function()s.tapStops=s.tapStops+1;s.tapActive=false end}
 local observer={callback=function(self,fn)s.observerCallback=fn;return self end,addWatcher=function(self)
   s.registrations=(s.registrations or 0)+1
   if options.observerRefused then error('refused')end
   if options.registrationFailureAt==s.registrations then
    if options.registrationReturnsFalse then return false end
    return nil
   end
   return self
  end,start=function(self)s.observerActive=true;return self end,isRunning=function()return s.observerActive end,stop=function()s.observerStops=s.observerStops+1;s.observerActive=false end}
 local hs={processInfo={processID=77},host={uuid=function()return nonce end},timer={secondsSinceEpoch=function()return 0 end},
 application={get=function()return a end,applicationForPID=function(pid)return pid==s.pid and a or nil end,frontmostApplication=function()return {pid=function()return s.foreground end}end},
 axuielement={applicationElement=function(value)check(value==a,'official app root only');return root end,windowElement=function(w)return w==sourceWindow and source or tools end,observer={new=function(pid)check(pid==123,'observer bound to owned PID');return observer end}},
 eventtap={event={types={keyDown=1,flagsChanged=2,leftMouseDown=3,rightMouseDown=4,otherMouseDown=5,scrollWheel=6},properties={eventSourceUnixProcessID=9}},
 new=function(_,fn)s.eventCallback=fn;return tap end,
 keyStroke=function(modifiers,key,delay,target)check(#modifiers==0 and key=='return'and delay==0 and target==a,'only app-targeted Return is sent');s.returns=s.returns+1;prompt.attrs.AXValue='\n'end},
 json={decode=function(text)
  if text=='{"handoff"}'then return {marker='CDT_DIRECT_HANDOFF',nonce=nonce,kind='chat',ok=not options.badProbe,documentId=documentId}end
  if text=='{"dispatch"}'then return {marker='CDT_DIRECT_RECEIPT',nonce=nonce,sequence=1,documentId=options.wrongDocument and string.rep('c',32)or documentId,ok=true}end
  return nil
 end}}
 -- Receipt scanning first filters marker strings. These stand-in strings keep JSON
 -- parsing in the fake API while exercising the native AX traversal and filtering.
 local handoff='{"marker":"CDT_DIRECT_HANDOFF","handoff":true}'
 local dispatch='{"marker":"CDT_DIRECT_RECEIPT","dispatch":true}'
 hs.json.decode=function(text)
  if text==handoff then return {marker='CDT_DIRECT_HANDOFF',nonce=nonce,kind='chat',ok=not options.badProbe,documentId=documentId}end
  if text==dispatch then return {marker='CDT_DIRECT_RECEIPT',nonce=nonce,sequence=1,documentId=options.wrongDocument and string.rep('c',32)or documentId,ok=true}end
  return nil
 end
 local adapter=M.new(hs)
 local function addReceipt(text)tools.attrs.AXChildren[#tools.attrs.AXChildren+1]=node({AXRole='AXStaticText',AXValue=text})end
 return {s=s,hs=hs,adapter=adapter,area=sourceArea,prompt=prompt,context=context,tools=tools,source=source,
  handoff=handoff,dispatch=dispatch,addReceipt=addReceipt,
  capture=function()return adapter.capture(10,'https://claude.ai/chat/synthetic')end,
  bind=function(token)s.tools=true;addReceipt(handoff);return adapter.bind(token,20)end,
  event=function(pid)s.eventCallback({getProperty=function()return pid end})end}
end
local f=fixture();local capture=f.capture();check(type(capture)=='table','capture creates opaque token')
check(f.adapter.probeCode({})==nil,'caller cannot forge capture token')
local code=f.adapter.probeCode(capture)
check(code:find('location.href!==',1,true) and code:find('crypto.getRandomValues',1,true),'bootstrap probe checks URL and creates cryptographic document identity')
local ownership=f.bind(capture);check(type(ownership)=='table','native receipt binds fresh console')
check(f.adapter.claim({})==nil,'caller cannot forge ownership token')
local handle=f.adapter.claim(ownership);check(type(handle)=='table','one-shot ownership claim succeeds')
check(f.adapter.claim(ownership)==nil,'ownership handoff cannot be replayed')
check(f.adapter.inspect(handle).documentId==documentId and f.adapter.inspect(handle).sourceWindowId==10,'native identity binds source and document receipt')
check(f.adapter.promptValue(handle)=='','display LF is normalized only for empty prompt structure')
check(f.adapter.writePrompt(handle,'','console.log(42)'),'native AX write accepts asynchronous update')
check(f.adapter.promptValue(handle)=='','write acceptance does not claim an immediate echo')
f.prompt.attrs.AXValue=f.prompt.pending
check(f.adapter.promptValue(handle)=='console.log(42)','exact echo becomes readable later')
check(f.adapter.focusPrompt(handle),'only local prompt focus requested')
check(f.adapter.execute(handle,'console.log(42)')=='pending','local AX focus acknowledgement is verified asynchronously')
f.s.localFocus=true
check(f.adapter.execute(handle,'console.log(42)'),'targeted Return works while unrelated app remains foreground')
check(f.s.foreground==999 and f.s.returns==1,'adapter never activates the app')
f.addReceipt(f.dispatch)
check(f.adapter.receipt(handle,nonce,1).documentId==documentId,'exact dispatch receipt is read from console')
check(f.adapter.release(handle,true),'verified empty owned console closes and releases')
check(f.s.closes==1 and f.s.tapStops==1 and f.s.observerStops==1,'release stops native monitors')
check(f.adapter.inspect(handle)==nil,'released handle cannot be reused')

f=fixture();f.s.tools=true;check(f.capture()==nil,'capture refuses pre-existing developer tools')
f=fixture();capture=f.capture();check(f.adapter.bind(capture,10)==nil,'source window cannot masquerade as new console')
f=fixture();capture=f.capture();f.s.tools=true;check(f.adapter.bind(capture,20)==nil,'caller metadata cannot replace a real probe receipt')
f=fixture({badProbe=true});capture=f.capture();check(f.bind(capture)==nil,'failed source probe does not mint ownership')
f=fixture();capture=f.capture();f.s.tools=true;f.addReceipt(f.handoff);f.addReceipt(f.handoff);check(f.adapter.bind(capture,20)==nil,'duplicate bootstrap receipts are ambiguous')
f=fixture();capture=f.capture();f.s.tools=true;f.prompt.attrs.AXValue='user text';f.addReceipt(f.handoff);check(f.adapter.bind(capture,20)==nil,'nonempty console cannot be handed off')
f=fixture();capture=f.capture();f.area.attrs.AXURL='https://claude.ai/chat/changed';check(f.bind(capture)==nil,'source navigation before handoff invalidates capture')
for _,options in ipairs({{wrongPath=true},{wrongBundle=true}})do f=fixture(options);check(f.capture()==nil,'unofficial process cannot be captured')end
for _,options in ipairs({{tapDisabled=true},{observerRefused=true}})do
 f=fixture(options);capture=f.capture();check(f.bind(capture)==nil,'missing native monitoring refuses handoff')
 check(f.s.closes==0,'failed monitoring never closes user interface')
end

for _,ordinal in ipairs({1,2,3})do
 for _,returnsFalse in ipairs({false,true})do
  f=fixture({registrationFailureAt=ordinal,registrationReturnsFalse=returnsFalse});capture=f.capture()
  check(f.bind(capture)==nil,'nil or false required watcher registration refuses handoff')
  check(f.s.tapStops==1 and f.s.observerStops==1,'partial lifecycle registration stops all monitors')
  check(f.s.closes==0 and not f.s.observerActive,'failed registration never closes the console or starts an unobserved session')
 end
end
for _,missing in ipairs({'property','properties-table','event-type'})do
 f=fixture();capture=f.capture()
 if missing=='property'then f.hs.eventtap.event.properties.eventSourceUnixProcessID=nil
 elseif missing=='properties-table'then f.hs.eventtap.event.properties=nil
 else f.hs.eventtap.event.types.leftMouseDown=nil end
 check(f.bind(capture)==nil,'missing event source or required event type refuses handoff')
 check(f.s.tapActive~=true and f.s.closes==0,'unsupported event API leaves no active monitor or UI mutation')
end

local function claimed(options)
 local f=fixture(options);local capture=f.capture();local ownership=f.bind(capture);local handle=f.adapter.claim(ownership);return f,handle
end
f,handle=claimed();f.event(100);check(f.adapter.inspect(handle).interactionVersion==0,'unrelated foreground keyboard input does not block background dispatch')
f.s.foreground=123;f.s.focusWindow=20;f.event(77)
check(f.adapter.inspect(handle).interactionVersion==0,'own synthetic events do not look like user interaction')
f.event(0)
check(f.adapter.inspect(handle).interactionVersion==1,'external input in the owned foreground console is tracked')
check(not f.adapter.writePrompt(handle,'','code') and f.s.returns==0,'external console input blocks mutation and Return')
check(not f.adapter.release(handle,true)and f.s.closes==0,'external interaction prevents automatic close')
check(f.adapter.release(handle,false),'conflicted handle can release tracking without closing')
f,handle=claimed();f.s.foreground=123;f.s.focusWindow=10;f.event(0)
check(f.adapter.inspect(handle).interactionVersion==0,'input in another Claude window is not labelled console input')
for _,change in ipairs({'context','source','pid','observer','tap','prompt'})do
 f,handle=claimed()
 if change=='context'then f.context.attrs.AXTitle='JavaScript context: different'
 elseif change=='source'then f.area.attrs.AXURL='https://claude.ai/chat/new'
 elseif change=='pid'then f.s.pid=124
 elseif change=='observer'then f.s.observerActive=false
 elseif change=='tap'then f.s.tapActive=false
 else f.tools.attrs.AXChildren[#f.tools.attrs.AXChildren+1]=node({AXRole='AXTextArea',AXDescription='Console prompt',AXValue=''})end
 check(f.adapter.inspect(handle)==nil,'changed '..change..' invalidates native handle')
 check(not f.adapter.writePrompt(handle,'','code')and not f.adapter.release(handle,true),'invalidated handle never writes or closes')
 check(f.adapter.release(handle,false),'invalidated tracking can be released without UI mutation')
end
f,handle=claimed();f.s.observerCallback(nil,f.area,'AXLoadComplete')
check(f.adapter.inspect(handle)==nil,'observed reload invalidates document handoff')
f,handle=claimed();f.prompt.attrs.AXValue='new user text'
check(not f.adapter.writePrompt(handle,'','code') and not f.adapter.release(handle,true),'read/write and release recheck exact current prompt')
check(f.prompt.attrs.AXValue=='new user text'and f.s.closes==0,'user prompt remains unchanged')
f,handle=claimed();f.prompt.attrs.AXValue=' ';check(f.adapter.promptValue(handle)==' ','spaces are not trimmed into empty prompts')
f,handle=claimed();f.prompt.attrs.AXChildren={node({AXRole='AXGroup'}),node({AXRole='AXGroup'})}
check(f.adapter.promptValue(handle)=='\n','user-entered LF structure is not normalized into empty prompt')
f,handle=claimed({wrongDocument=true});f.addReceipt(f.dispatch);f.adapter.receipt(handle,nonce,1)
check(not f.adapter.release(handle,true),'wrong-document receipt cannot authorize close')
f,handle=claimed({asyncClose=true});f.addReceipt(f.dispatch);f.adapter.receipt(handle,nonce,1)
check(not f.adapter.release(handle,true),'accepted but unfinished native close is not reported complete')
check(f.s.closes==1,'asynchronous close targets only the owned console once')
f=fixture();capture=f.capture();check(f.adapter.discard(capture),'unused capture can be discarded without UI mutation')
check(f.adapter.probeCode(capture)==nil,'discarded capture cannot mint probe commands')

f,handle=claimed();f.addReceipt(f.dispatch);f.adapter.receipt(handle,nonce,1)
local previousAttribute=f.prompt.attributeValue;local raced=false
function f.prompt:attributeValue(name)
 if name=='AXValue' and not raced then raced=true;f.s.foreground=123;f.s.focusWindow=20;f.event(0)end
 return previousAttribute(self,name)
end
check(not f.adapter.release(handle,true)and f.s.closes==0,'close rechecks console interaction after prompt reads')
f.adapter.release(handle,false)
f=fixture();capture=f.capture();ownership=f.bind(capture);f.context.attrs.AXTitle='JavaScript context: changed'
check(f.adapter.claim(ownership)==nil and f.s.tapStops==1,'handoff-to-claim context race releases monitoring')
f,handle=claimed();f.addReceipt(f.dispatch)
check(f.adapter.receipt(handle,string.rep('c',32),1)==nil,'different nonce cannot authorize receipt')
check(not f.adapter.release(handle,true),'close requires a verified dispatch result')
f.adapter.release(handle,false)
for _,value in ipairs({'https://claude.ai/auth/callback','https://claude.ai/api/private',
 'https://claude.ai.evil.invalid/chat','https://claude.ai/chat/'..string.char(226,128,168),
 'file:///Applications/Claude.app/Contents/Resources/app.asar/.vite/renderer/unknown/index.html'})do
 f=fixture();f.area.attrs.AXURL=value;check(f.adapter.capture(10,value)==nil,'native capture rejects unsupported source')
end

-- Validate the actual bootstrap JavaScript in Node, with no system/app APIs.
f=fixture();capture=f.capture();local probeCode=f.adapter.probeCode(capture)
local files={}
local function file(value)local name=os.tmpname();local out=assert(io.open(name,'wb'));out:write(value);out:close();files[#files+1]=name;return name end
local probeFile=file(probeCode)
local harness=file([====[
'use strict';
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const {webcrypto}=require('node:crypto');
const code=fs.readFileSync(process.argv[2],'utf8');new vm.Script(code);
function fixture(href='https://claude.ai/chat/synthetic'){
 const document={},window={},logs=[];
 const context=vm.createContext({document,window,location:{href},crypto:webcrypto,console:{log(value){logs.push(JSON.parse(value));}}});
 return {document,window,logs,context};
}
const fresh=fixture();vm.runInContext(code,fresh.context,{timeout:1000});
assert.equal(fresh.logs[0].ok,true);assert.match(fresh.logs[0].documentId,/^[a-f0-9]{32}$/);
assert.equal(fresh.window.__claudePersianConsoleDocumentV1.document,fresh.document);
const before=fresh.window.__claudePersianConsoleDocumentV1;
vm.runInContext(code,fresh.context,{timeout:1000});assert.equal(fresh.window.__claudePersianConsoleDocumentV1,before);
const different=fixture('https://example.invalid/');vm.runInContext(code,different.context,{timeout:1000});
assert.equal(different.logs[0].ok,false);assert.equal(different.window.__claudePersianConsoleDocumentV1,undefined);
const foreign=fixture();foreign.window.__claudePersianConsoleDocumentV1={document:{},id:'b'.repeat(32)};
const original=foreign.window.__claudePersianConsoleDocumentV1;vm.runInContext(code,foreign.context,{timeout:1000});
assert.equal(foreign.logs[0].ok,false);assert.equal(foreign.window.__claudePersianConsoleDocumentV1,original);
assert.deepEqual(Object.keys(fresh.logs[0]).sort(),['documentId','kind','marker','nonce','ok']);
]====])
local function shellQuote(v)return "'"..v:gsub("'","'\\''").."'"end
local nodeOK=os.execute('node '..shellQuote(harness)..' '..shellQuote(probeFile))
for _,name in ipairs(files)do os.remove(name)end
check(nodeOK==true or nodeOK==0,'native bootstrap JS syntax URL guard namespace ownership and receipt pass in Node')

print(string.format('direct native: %d assertions, %d scenarios',assertions,scenarios))
return {ok=true,assertions=assertions,scenarios=scenarios}
