-- Run simulated metadata and driver only. No real UI is targeted.
local M=assert(loadfile(assert(arg[1])))()
local assertions,scenarios=0,0
local function check(value,message)assertions=assertions+1;assert(value,message)end
local function fixture(options)
  scenarios=scenarios+1;options=options or {}
  local state={now=0,idle=3,frontmost=true,pid=123,focused=10,requests={},result={phase='idle',ok=false},
    windows={{id=10,pid=123,sourceURL='https://claude.ai/new',fingerprint='first',structureFingerprint='one-chat'}},observerStops=0,driverStops=0,cancels=0}
  local notify
  local adapter={now=function()return state.now end,idleSeconds=function()return state.idle end,
    identity=function()
      if state.noApp then return nil end
      return {pid=state.pid,bundle=options.wrongBundle and 'other' or 'com.anthropic.claudefordesktop',
        path=options.wrongPath and '/tmp/Claude.app' or '/Applications/Claude.app',frontmost=state.frontmost,focusedWindow=state.focused}
    end,windows=function()return state.windows end,
    observe=function(fn)notify=fn;return function()state.observerStops=state.observerStops+1;notify=nil end end}
  local driver={snapshot=function()return state.result end,begin=function(request)
    if state.refuse then return false,state.refuse end
    state.requests[#state.requests+1]=request;state.result={phase='open',ok=false};return true
  end,cancel=function()state.cancels=state.cancels+1;state.result={phase='cancelled',reason='cancelled',ok=false}end,
    stop=function()state.driverStops=state.driverStops+1;state.result={phase=state.asyncCleanup and 'cleanup' or 'cancelled',ok=false}end}
  local config={};for key,value in pairs(options.config or {})do config[key]=value end
  local controller=M.new(config,adapter,driver)
  controller.tick()
  return {state=state,adapter=adapter,driver=driver,controller=controller,
    advance=function(seconds)state.now=state.now+seconds;return controller.tick()end,
    dirty=function(id,event)if notify then notify(id,event)end end,
    complete=function(result)state.result=result or {phase='complete',ok=true};return controller.tick()end}
end

local f=fixture();check(#f.state.requests==0,'discovery debounces before opening tools')
f.advance(1.1);check(#f.state.requests==1,'idle focused window starts one scan')
local request=f.state.requests[1]
check(request.scan==true and request.windowId==10 and request.sourceURL=='https://claude.ai/new','scan request matches source window')
check(request.toolsTitle=='Developer Tools - https://claude.ai/new','exact tools title derived from source URL')
f.advance(3);check(#f.state.requests==1,'no second job while driver busy')
f.complete();check(f.controller.snapshot().counts.completed==1,'complete receipt counted')
f.advance(2);check(#f.state.requests==1,'healthy unchanged metadata does not repeatedly open tools')
f.state.windows[1].fingerprint='new-child-frame';f.advance(1);check(#f.state.requests==1,'frame discovery debounced')
f.advance(1.1);check(#f.state.requests==2,'frame metadata change rescans focused source')

f=fixture();f.advance(1.1)
f.complete({phase='complete',ok=true,applied=1,contexts=2,copyVerifications=1,toolsClosed=true,clipboardRestored=true,sourceURL='PRIVATE',
 appliedKinds={chat=1,document=-1,PRIVATE=3},probedKinds={chat=1,['artifact-content']=1,PRIVATE='secret'}})
local applied=f.controller.snapshot().lastApplied
check(applied.processId==123 and applied.applied==1 and applied.copyVerifications==1 and applied.toolsClosed and applied.clipboardRestored,'successful application retains fresh process and safe receipt counts')
check(applied.scan==1 and applied.sourceKind=='chat','application evidence identifies safe source kind and completed scan ordinal')
check(f.controller.snapshot().lastCompleted.contexts==2,'completed scan evidence retains safe coverage count')
check(applied.windowId==10 and applied.appliedKinds.chat==1 and applied.probedKinds['artifact-content']==1,'native window and valid frame kinds retained')
check(applied.appliedKinds.document==nil and applied.appliedKinds.PRIVATE==nil and applied.probedKinds.PRIVATE==nil,'invalid counts and unknown frame keys excluded')
applied.appliedKinds.chat=99;check(f.controller.snapshot().lastApplied.appliedKinds.chat==1,'nested frame evidence cannot mutate stored receipt')
check(applied.sourceURL==nil,'retained application contains no private source')
applied.applied=99;check(f.controller.snapshot().lastApplied.applied==1,'application receipt snapshots cannot mutate stored evidence')
f.dirty(10,'AXLoadComplete');f.advance(2);f.complete({phase='failure',ok=false,reason='application-failed'})
check(f.controller.snapshot().lastApplied.applied==1,'later failure does not erase successful application evidence')
f.state.pid=124;f.state.windows[1].pid=124;f.advance(1)
check(f.controller.snapshot().lastApplied==nil,'process change clears old application evidence')
check(f.controller.snapshot().lastCompleted==nil,'process change clears old completed scan evidence')

f=fixture();f.state.idle=0;f.advance(10);check(#f.state.requests==0,'typing prevents work')
f.state.idle=3;f.state.frontmost=false;f.advance(1);check(#f.state.requests==0,'background app never focused by watcher')
f.state.frontmost=true;f.advance(1);check(#f.state.requests==1,'scan begins only after idle and focus')
for _,options in ipairs({{wrongPath=true},{wrongBundle=true}})do
  f=fixture(options);f.advance(30);check(#f.state.requests==0,'unofficial app never receives a job')
end
f=fixture();f.state.windows[2]={id=20,pid=123,sourceURL='https://claude.ai/chat/fixture',fingerprint='second'}
f.advance(1.1);check(f.state.requests[1].windowId==10,'new background window not selected')
f.complete();f.state.focused=20;f.advance(2)
check(f.state.requests[2].windowId==20,'new source window is handled when focused')
f.complete();f.state.windows[2]=nil;f.state.focused=10;f.advance(1)
check(f.controller.snapshot().counts.windows==1,'destroyed windows removed from cache')

f=fixture();f.advance(1.1);f.complete();f.advance(20);check(#f.state.requests==1,'same URL reload without event is not claimed instant')
f.advance(10.1);f.advance(300);check(#f.state.requests==1,'unchanged foreground window has no periodic console popups')
f.state.frontmost=false;f.advance(1);f.state.frontmost=true;f.advance(1)
check(#f.state.requests==2 and f.controller.snapshot().counts.healthScans==1,'eventless same-URL fallback runs once on real return after cooldown')
f.complete();f.advance(300);check(#f.state.requests==2,'activation fallback does not become a periodic foreground timer')
f=fixture();f.advance(1.1);f.complete();f.state.frontmost=false;f.advance(1);f.state.frontmost=true;f.advance(1)
f.advance(300);check(#f.state.requests==1,'return before cooldown does not queue a delayed console popup')
f=fixture();f.advance(1.1);f.complete();f.dirty(10,'AXLoadComplete');f.advance(0.4)
check(#f.state.requests==1,'AX dirty is debounced');f.advance(0.7);check(#f.state.requests==2,'AX load marks document dirty')
f=fixture();f.advance(1.1);f.dirty(10,'AXLoadComplete');f.complete();f.advance(1.1)
check(#f.state.requests==2,'dirty generation arriving during scan survives successful completion')
f=fixture();f.advance(1.1);f.dirty(nil,'AXFocusedWindowChanged');f.complete();f.advance(2)
check(#f.state.requests==1,'own tools focus transitions do not create another scan')
f=fixture();f.advance(1.1);f.dirty(10,'AXFocusedUIElementChanged');f.complete();f.advance(2)
check(#f.state.requests==1,'own prompt focus transitions do not dirty source window')

f=fixture();f.state.windows[1].structureFingerprint='one-chat';f.advance(1.1)
for _=1,3 do f.dirty(10,'AXLayoutChanged')end
f.complete();f.dirty(nil,'application');f.dirty(10,'AXFocusedUIElementChanged')
f.state.windows[1].fingerprint='rebuilt-AX-identity';f.advance(0.5)
f.dirty(10,'AXUIElementDestroyed');f.advance(2)
check(#f.state.requests==1,'own layout focus and AX identity rebuilding do not reopen tools')
local coalesced=f.controller.snapshot().counts
check(coalesced.layoutEvents==3 and coalesced.identityCoalesced==1 and coalesced.focusEvents==2 and coalesced.metadataEvents==1,'safe counters distinguish layout focus and coalesced identity noise')
for _=1,4 do f.dirty(10,'AXLayoutChanged');f.advance(3)end
check(#f.state.requests==1,'repeated source layout changes without frame changes stay passive')
f.advance(160);check(#f.state.requests==1 and f.controller.snapshot().counts.healthScans==0,'passive layout does not schedule periodic console health popups')

f=fixture();f.state.windows[1].structureFingerprint='one-chat';f.advance(1.1);f.complete()
f.state.windows[1].fingerprint='new-child';f.state.windows[1].structureFingerprint='chat-and-child'
f.dirty(10,'AXLayoutChanged');f.advance(0.5);f.advance(1.1)
check(#f.state.requests==2 and f.controller.snapshot().counts.metadataScans==2,'child frame creation survives post-job coalescing')

f=fixture();f.state.windows[1].structureFingerprint='one-chat';f.advance(1.1)
f.dirty(10,'AXLoadComplete');f.complete();f.state.windows[1].fingerprint='reloaded-same-url'
f.advance(0.5);f.advance(1.1)
check(#f.state.requests==2 and f.controller.snapshot().counts.loadEvents==1,'same-URL load during job survives AX identity coalescing')

f=fixture();f.state.windows[1].structureFingerprint='one-chat';f.advance(1.1);f.complete();f.advance(2.1)
f.state.windows[1].fingerprint='later-new-document';f.advance(0.1);f.advance(1.1)
check(#f.state.requests==2,'identity change outside short post-job window still triggers scan')
f=fixture();f.advance(1.1);f.complete();f.advance(40)
f.state.windows[1].loading=true;f.state.windows[1].fingerprint='same-url-loading';f.state.windows[1].structureFingerprint='one-chat-loading'
f.advance(1.1);f.advance(5)
check(#f.state.requests==1 and f.controller.snapshot().phase=='waiting-for-load','passive loading witness prevents console work during load')
f.state.windows[1].loading=false;f.state.windows[1].fingerprint='same-url-loaded';f.state.windows[1].structureFingerprint='one-chat-loaded'
f.state.idle=0;f.advance(10);check(#f.state.requests==1,'reload witness still respects active typing')
f.state.idle=3;f.advance(1);f.advance(1.1)
check(#f.state.requests==2 and f.controller.snapshot().counts.metadataScans==2,'same-URL reload metadata restores promptly after load and idle without activation')

f=fixture();f.state.windows[2]={id=20,pid=123,title='Developer Tools - user',isTools=true};f.advance(30)
check(#f.state.requests==0 and f.controller.snapshot().phase=='user-tools-open','existing user tools prevent job creation')
f=fixture();f.state.windows[1].sourceURL=nil;f.state.windows[1].isSystemDialog=true;f.advance(30)
check(#f.state.requests==0 and f.controller.snapshot().phase=='unsupported-window','native Quick Entry with no web area skipped')
f=fixture();f.state.windows[1].incomplete=true;f.advance(30)
check(#f.state.requests==0 and f.controller.snapshot().counts.incompleteWindows==1,'incomplete AX discovery never starts a success-capable job')
f=fixture();f.state.windows[1].sourceURL='https://claude.ai/code/artifact/fixture';f.advance(1.1);f.advance(1.1)
check(#f.state.requests==1 and f.state.requests[1].sourceURL=='https://claude.ai/code/artifact/fixture','independent artifact window is a valid scan source')
f=fixture();f.advance(1.1);f.complete({phase='failure',reason='application-failed',ok=false})
f.advance(4);check(#f.state.requests==1,'failure backoff prevents immediate reopen')
f.advance(1.1);check(#f.state.requests==2,'failure retries after bounded backoff')
f.complete({phase='failure',reason='tools-unverified',cleanupRequired=true,ok=false});f.advance(90)
check(#f.state.requests==2 and f.controller.snapshot().attentionRequired,'cleanup failure blocks repeated popups')
f.dirty(10,'AXLayoutChanged');f.advance(90);check(#f.state.requests==2,'dirty event cannot clear cleanup attention')
f=fixture();f.advance(1.1)
f.complete({phase='await-close',cleanupPending=true,cleanupRequired=true,ok=false})
check(f.controller.snapshot().phase=='cleanup' and not f.controller.snapshot().attentionRequired,'explicit pending cleanup is not a terminal failure')
f.complete();check(f.controller.snapshot().counts.completed==1 and f.controller.snapshot().counts.failed==0,'pending flag retains job until complete')
f=fixture();f.state.refuse='busy';f.advance(1.1);check(f.controller.snapshot().phase=='driver-busy','external busy driver waits')
check(f.controller.snapshot().lastBeginReason=='busy','safe busy begin reason exposed')
f.state.refuse=nil;f.advance(5.1);check(#f.state.requests==1,'busy driver retried without concurrent work')
check(f.controller.snapshot().lastBeginReason==nil,'successful begin clears previous rejection reason')
for _,reason in ipairs({'clipboard-multiple-items-or-unavailable','clipboard-unavailable','clipboard-format-unavailable','target-not-focused','probe-unavailable','input-monitor-unavailable'})do
  f=fixture();f.state.refuse=reason;f.advance(1.1)
  check(f.controller.snapshot().lastBeginReason==reason,'fixed begin reason preserved without raw error')
end
for _,reason in ipairs({'https://private.invalid/fixture','PRIVATE_DATA','user secret error'})do
  f=fixture();f.state.refuse=reason;f.advance(1.1)
  check(f.controller.snapshot().lastBeginReason=='driver-begin-failed','unknown begin reason replaced by safe constant')
end

f=fixture();f.advance(1.1);f.state.pid=456;f.state.windows[1].pid=456;f.advance(1)
check(f.state.cancels==1 and f.controller.snapshot().counts.processChanges==1,'PID swap cancels old job and clears cache')
f.advance(1.1);check(#f.state.requests==2,'new PID gets a fresh scan')
f=fixture();f.advance(1.1);f.state.noApp=true;f.advance(1)
check(f.controller.snapshot().counts.windows==0 and f.controller.snapshot().phase=='waiting-for-app','quit clears source cache')
f=fixture();f.advance(1.1);local first=f.controller.snapshot();first.counts.started=900
check(f.controller.snapshot().counts.started==1,'snapshot count table detached from internal state')
for key in pairs(f.controller.snapshot())do check(key~='url' and key~='sourceURL' and key~='fingerprint' and key~='title','no private metadata in snapshot')end
f.state.asyncCleanup=true;local stopped=f.controller.stop()
check(not stopped.running and stopped.phase=='watcher-stopped' and stopped.cleanupPending,'stop reports pending driver cleanup')
check(f.state.driverStops==1 and f.state.observerStops==1,'stop releases driver and observers')
f.state.result={phase='complete',ok=false,cleanupRequired=true}
check(f.controller.snapshot().cleanupRequired and not f.controller.snapshot().cleanupPending,'post-stop cleanup result stays observable')
local starts=#f.state.requests;f.controller.stop();f.advance(100);f.controller.markDirty(10)
check(#f.state.requests==starts and f.state.driverStops==1 and not f.controller.isRunning(),'stopped watcher cannot restart or leak driver work')
for _,config in ipairs({{idleSeconds=1},{debounceSeconds=0},{healthSeconds=1},{retrySeconds=0},{tickSeconds=0}})do
  scenarios=scenarios+1;check(not pcall(function()M.new(config,{}, {})end),'invalid scheduler config rejected')
end

-- The real driver state core must retain asynchronous close until its final receipt.
scenarios=scenarios+1
local Core=assert(loadfile((arg[1]:gsub('claude%-console%-auto%.lua$','claude-console.lua'))))()
local integration={now=0,focused=10,tracking=false,version=1,clipboard='original',prompt='',closed=false,nonce=0}
local sourceURL='https://claude.ai/new'
local nativeWindows={{id=10,title='Claude',pid=123}}
local driverAdapter={now=function()return integration.now end,activity=function()return 0 end,
  identity=function()return {pid=123,bundle='com.anthropic.claudefordesktop',path='/Applications/Claude.app',frontmost=true,focusedWindow=integration.focused}end,
  windows=function()return nativeWindows end,
  captureClipboard=function()return {version=integration.version,data=integration.clipboard}end,
  clipboardUnchanged=function(saved)return saved.version==integration.version end,
  clipboardVersion=function()return integration.version end,
  nonce=function()integration.nonce=integration.nonce+1;return string.format('%032x',integration.nonce)end,
  beginTracking=function()integration.tracking=true;return true end,isTracking=function()return integration.tracking end,
  endTracking=function()integration.tracking=false end,
  openTools=function()
    nativeWindows[2]={id=20,title='Developer Tools - '..sourceURL,pid=123};integration.focused=20;return true
  end,
  openContexts=function()return true end,
  contexts=function()return {{title='top',frame=true,index=1,key='top',contextLabel='JavaScript context: top'}}end,
  selectContext=function()return true end,contextLabel=function()return 'JavaScript context: top'end,
  promptValue=function()return integration.prompt end,focusPrompt=function()return true end,promptFocused=function()return true end,
  writeClipboard=function(value)integration.clipboard=value;integration.version=integration.version+1;return integration.version,true end,
  paste=function()integration.prompt=integration.clipboard;return true end,
  execute=function()integration.prompt='';return true end,
  result=function(_,nonce,marker)return {marker=marker,nonce=nonce,ok=true,kind='chat',documentId=string.rep('a',32),healthy=true}end,
  dismissContexts=function()return true end,
  restoreClipboard=function(saved,version)
    if version~=integration.version then return false end
    integration.clipboard=saved.data;integration.version=integration.version+1;return true
  end,
  closeTools=function()integration.closeRequested=true;return 'pending'end,
  toolsClosed=function()
    if integration.closed then nativeWindows[2]=nil;integration.focused=10;return true end
    return false
  end}
local realDriver=Core.new({probe=function(nonce)return 'probe_'..nonce end},driverAdapter)
local integrationAdapter={now=driverAdapter.now,identity=driverAdapter.identity,idleSeconds=function()return 3 end,
  windows=function()return {{id=10,pid=123,sourceURL=sourceURL,fingerprint='source'}}end}
local coordinator=M.new({},integrationAdapter,realDriver)
coordinator.tick();integration.now=1.1;coordinator.tick()
check(coordinator.snapshot().counts.started==1,'integration coordinator starts the real driver scan')
for _=1,50 do
  realDriver.tick();coordinator.tick()
  if realDriver.snapshot().phase=='cleanup' then break end
  integration.now=integration.now+0.01
end
check(realDriver.snapshot().phase=='cleanup' and realDriver.snapshot().cleanupRequired,'real driver awaits native close with cleanupRequired set')
local pendingState=coordinator.snapshot()
check(pendingState.phase=='cleanup' and pendingState.cleanupPending and not pendingState.attentionRequired,'coordinator keeps real driver cleanup pending without false attention')
check(pendingState.counts.failed==0 and pendingState.counts.completed==0,'pending close is neither failure nor success')
coordinator.markDirty(10,'AXFocusedUIElementChanged')
realDriver.tick();coordinator.tick()
check(coordinator.snapshot().phase=='cleanup','job remains attached while close still pending')
integration.closed=true;realDriver.tick();coordinator.tick()
local finalState=coordinator.snapshot()
check(realDriver.snapshot().ok and finalState.counts.completed==1 and finalState.counts.failed==0,'verified close completes the same coordinator job')
check(not finalState.attentionRequired and not finalState.cleanupPending and integration.clipboard=='original','successful async close clears pending state and preserves clipboard')
integration.now=integration.now+1.1;coordinator.tick()
check(coordinator.snapshot().counts.started==1,'own focus notification during real driver cleanup cannot schedule another job after debounce')
coordinator.stop()

-- native AX fixture: metadata identity is stable and does not depend on text/title reads.
local function node(attributes)
  local value={attrs=attributes,reads={}}
  function value:attributeValue(name)
    self.reads[name]=(self.reads[name] or 0)+1
    if name=='AXValue' or name=='AXDescription' then error('private text must not be read')end
    return self.attrs[name]
  end
  function value:asHSWindow()return self.nativeWindow end
  return value
end
local function nativeFixture(options)
  scenarios=scenarios+1;options=options or {}
  local s={pid=123,time=0,idle=3,watcherStops=0,observerStops=0,observerStarts=0,registered={},rootReads=0}
  local shell=node({AXRole='AXWebArea',AXURL='file:///Applications/Claude.app/Contents/Resources/app.asar/.vite/renderer/main_window/index.html',AXChildren={}})
  local chat=node({AXRole='AXWebArea',AXURL='https://claude.ai/chat/fixture',AXChildren={}})
  local artifact=node({AXRole='AXWebArea',AXURL='https://claude.ai/code/artifact/fixture',AXChildren={}})
  local content=node({AXRole='AXWebArea',AXURL='https://fixture.frame.claudeusercontent.com/',AXChildren={}})
  local doc=node({AXRole='AXWebArea',AXURL='about:srcdoc',AXChildren={}})
  artifact.attrs.AXChildren={content};content.attrs.AXChildren={doc};chat.attrs.AXChildren={artifact}
  local window=node({AXRole='AXWindow',AXTitle='Claude',AXChildren={shell,chat}})
  window.nativeWindow={id=function()return 10 end}
  local appRoot=node({AXRole='AXApplication',AXWindows=options.fullscreen and {} or {window},AXFocusedWindow=window})
  function appRoot:setAttributeValue(name,value)
    check(name=='AXManualAccessibility' and value==true,'bootstrap only sets official Electron app accessibility attribute')
    s.accessibilitySets=(s.accessibilitySets or 0)+1
    if options.accessibilityFailure=='false' then return false end
    if options.accessibilityFailure=='nil' then return nil,'unsupported' end
    if options.accessibilityFailure=='error' then error('unsupported')end
    self.attrs[name]=value;return self
  end
  if options.requireAccessibility then
    local originalAttribute=appRoot.attributeValue
    function appRoot:attributeValue(name)
      if (name=='AXWindows' or name=='AXFocusedWindow') and self.attrs.AXManualAccessibility~=true then
        return name=='AXWindows' and {} or nil
      end
      return originalAttribute(self,name)
    end
  end
  local app={bundleID=function()return bundle or 'com.anthropic.claudefordesktop'end,path=function()return '/Applications/Claude.app'end,
    pid=function()return s.pid end,isFrontmost=function()return true end}
  local watcher={launched=1,activated=2,terminated=3,new=function(fn)s.appCallback=fn;return {start=function(self)return self end,stop=function()s.watcherStops=s.watcherStops+1 end}end}
  local hs={application={get=function()return app end,watcher=watcher},host={idleTime=function()return s.idle end},
    timer={absoluteTime=function()return s.time*1000000000 end},axuielement={applicationElement=function()return appRoot end}}
  if not options.noObserver then
    hs.axuielement.observer={new=function(pid)
      check(pid==s.pid,'AX observer tied to current PID')
      local object={}
      function object:callback(fn)s.axCallback=fn end
      function object:addWatcher(element,notification)
        if options.unsupportedNotifications then error('unsupported notification')end
        s.registered[#s.registered+1]={element=element,notification=notification};return self
      end
      function object:removeWatcher()s.removed=(s.removed or 0)+1 end
      function object:start()s.observerStarts=s.observerStarts+1;return self end
      function object:stop()s.observerStops=s.observerStops+1 end
      return object
    end}
  end
  return {state=s,hs=hs,app=app,appRoot=appRoot,window=window,shell=shell,chat=chat,artifact=artifact,doc=doc,content=content,adapter=M.nativeAdapter(hs)}
end

local n=nativeFixture({requireAccessibility=true});local stop=n.adapter.observe(function()end)
check(n.adapter.windows()[1].sourceURL==n.chat.attrs.AXURL and n.state.accessibilitySets==1,'fresh Electron tree becomes discoverable through native bootstrap without another AX client')
n.adapter.identity();n.adapter.windows();n.adapter.diagnostics()
check(n.state.accessibilitySets==1 and n.adapter.accessibilityStatus().manualAccessibilityEnabled==1,'successful bootstrap runs only once per PID')
n.state.pid=124;n.appRoot.attrs.AXManualAccessibility=false
n.adapter.identity()
check(n.state.accessibilitySets==2 and n.adapter.accessibilityStatus().manualAccessibilityAttempts==1,'new PID gets its own accessibility bootstrap')
stop()
for _,failure in ipairs({'false','nil','error'})do
  n=nativeFixture({requireAccessibility=true,accessibilityFailure=failure});stop=n.adapter.observe(function()end)
  local d=n.adapter.diagnostics()
  check(d.manualAccessibilityEnabled==0 and d.manualAccessibilityFailures==1 and d.sourceCandidates==0,'unsupported bootstrap never reports success or invented source coverage')
  n.adapter.identity();check(n.state.accessibilitySets==1,'failed bootstrap retry is throttled')
  n.state.time=5;n.adapter.identity();n.state.time=10;n.adapter.identity();n.state.time=100;n.adapter.identity()
  check(n.state.accessibilitySets==3 and n.adapter.accessibilityStatus().manualAccessibilityFailures==3,'unsupported bootstrap retries are bounded without endless calls')
  local controller=M.new({},n.adapter,{begin=function()error('no source must start')end,snapshot=function()return {phase='idle'}end})
  local status=controller.tick()
  check(status.counts.manualAccessibilityEnabled==0 and status.counts.manualAccessibilityFailures==3,'safe coordinator status exposes native bootstrap failure')
  stop()
end
n=nativeFixture();n.app.path=function()return '/tmp/unofficial.app'end;stop=n.adapter.observe(function()end)
check(n.adapter.identity()==nil and n.state.accessibilitySets==nil,'unofficial app never receives accessibility attribute writes')
stop()
n=nativeFixture({fullscreen=true});local dirty={};stop=n.adapter.observe(function(id,event)dirty[#dirty+1]={id=id,event=event}end)
check(n.adapter.identity().focusedWindow==10,'AXFocusedWindow fallback supplies full-screen ID')
local globalWindow={application=function()return {pid=function()return 999 end}end,id=function()return 3183 end}
n.hs.window={focusedWindow=function()return globalWindow end}
local identity=n.adapter.identity()
check(identity.frontmost==false and identity.focusedWindow==nil,'other-app global focused window blocks stale app AX focus')
local requests=0
local guardAdapter={identity=n.adapter.identity,now=n.adapter.now,idleSeconds=n.adapter.idleSeconds,windows=n.adapter.windows}
local guarded=M.new({},guardAdapter,{snapshot=function()return {phase='idle'}end,begin=function()requests=requests+1;return false,'target-not-focused'end})
guarded.tick();n.state.time=5;guarded.tick()
check(requests==0 and guarded.snapshot().phase=='waiting-for-focus' and guarded.snapshot().counts.failed==0,'foreign global focus waits without failed jobs or retry backoff')
globalWindow.application=function()return n.app end;globalWindow.id=function()return 55 end
identity=n.adapter.identity()
check(identity.frontmost==true and identity.focusedWindow==55,'own global focused window ID overrides stale AX window ID')
globalWindow=nil;identity=n.adapter.identity()
check(identity.frontmost==true and identity.focusedWindow==10,'nil global focused window retains fullscreen AX fallback')
n.hs.window.focusedWindow=function()error('unavailable')end
identity=n.adapter.identity()
check(identity.frontmost==false and identity.focusedWindow==nil,'failed global focus lookup is closed without AX fallback')
n.hs.window=nil
local windows=n.adapter.windows();check(#windows==1 and windows[1].sourceURL=='https://claude.ai/chat/fixture','shallow chat preferred over shell and artifact')
local fingerprint=windows[1].fingerprint
local structure=windows[1].structureFingerprint
local roleReads=n.window.reads.AXChildren
check(n.adapter.windows()[1].fingerprint==fingerprint,'stable AX element identities do not cause perpetual dirty')
check(n.window.reads.AXChildren==roleReads,'metadata traversal reused for at least two seconds')
n.content.attrs.AXChildren={node({AXRole='AXWebArea',AXURL='about:srcdoc',AXChildren={}})}
n.state.axCallback(nil,n.content,'AXLayoutChanged')
local replaced=n.adapter.windows()[1]
check(replaced.fingerprint~=fingerprint and replaced.structureFingerprint==structure,'same-URL child replacement separates AX identity from frame URL structure')
n.window.attrs.AXChildren={n.artifact}
n.state.axCallback(nil,n.window,'AXLayoutChanged')
check(n.adapter.windows()[1].sourceURL==n.artifact.attrs.AXURL,'independent artifact source accepted when no chat web area exists')
n.state.axCallback(nil,n.chat,'AXLoadComplete');check(#dirty==3,'AX load event delivered without document text')
n.window.attrs.AXTitle='Developer Tools - synthetic';n.state.axCallback(nil,n.window,'AXLayoutChanged')
check(#dirty==3,'own DevTools metadata events are ignored')
local childrenReads=n.window.reads.AXChildren
check(n.adapter.windows()[1].isTools,'native tools detected by window title')
check(n.window.reads.AXChildren==childrenReads,'independent DevTools root traversal skipped')
stop();check(n.state.watcherStops==1 and n.state.observerStops==1,'native watcher and AX observer stopped')
local before=#dirty;n.state.appCallback(nil,1,n.app);check(#dirty==before and n.state.observerStarts==1,'stopped native callbacks cannot restart observers')

n=nativeFixture({noObserver=true});stop=n.adapter.observe(function()end)
local staleRoot=node({AXRole='AXWindow',AXTitle='Claude',AXChildren={}})
staleRoot.nativeWindow={id=function()return 77 end}
n.appRoot.attrs.AXWindows={staleRoot};n.appRoot.attrs.AXFocusedWindow=staleRoot
local focusedNative={id=function()return 10 end,application=function()return n.app end}
n.hs.window={focusedWindow=function()return focusedNative end}
local elementCalls=0
n.hs.axuielement.windowElement=function(candidate)elementCalls=elementCalls+1;check(candidate==focusedNative,'global AX conversion uses the owned focused window');return n.window end
local discovered=n.adapter.windows()
check(discovered[1].id==10 and discovered[1].sourceURL==n.chat.attrs.AXURL,'owned global focused source missing from AX lists is discovered first')
local mismatch=n.adapter.diagnostics()
check(mismatch.AXrootsFocusedMismatch==1 and mismatch.sourceCandidates==3 and mismatch.ambiguousSources==0,'global AX mismatch and source candidates are auditable counts')
local request
local globalCoordinator=M.new({},n.adapter,{snapshot=function()return {phase='idle'}end,begin=function(value)request=value;return true end})
globalCoordinator.tick();n.state.time=1.1;globalCoordinator.tick()
check(request and request.windowId==10 and request.sourceURL==n.chat.attrs.AXURL,'normal global focused source reaches driver with exact window binding')
check(globalCoordinator.snapshot().counts.AXrootsFocusedMismatch==1 and globalCoordinator.snapshot().counts.sourceCandidates==3,'source inventory counters persist in safe coordinator status')
staleRoot.nativeWindow.id=function()return 10 end;n.state.time=3.2
discovered=n.adapter.windows()
check(#discovered==1 and discovered[1].sourceURL==n.chat.attrs.AXURL,'global AX root wins deduplication over stale root with the same ID')
focusedNative.application=function()return {pid=function()return 999 end}end
local beforeCalls=elementCalls;n.state.time=5.3
discovered=n.adapter.windows()
check(elementCalls==beforeCalls and discovered[1].sourceURL==nil,'foreign focused window is not converted or included in source inventory')
focusedNative.application=function()return n.app end
n.hs.axuielement.windowElement=function()return staleRoot end
staleRoot.nativeWindow.id=function()return 77 end;n.state.time=7.4
discovered=n.adapter.windows()
check(#discovered==1 and discovered[1].id==77 and discovered[1].sourceURL==nil,'mismatched converted AX window ID is rejected')
n.hs.axuielement.windowElement=function()return n.window end
n.window.attrs.AXChildren={n.chat,node({AXRole='AXWebArea',AXURL='https://claude.ai/chat/other-fixture',AXChildren={}})};n.state.time=9.5
discovered=n.adapter.windows();mismatch=n.adapter.diagnostics()
check(discovered[1].sourceURL==nil and mismatch.ambiguousSources==1,'global fallback does not loosen ambiguous top-level source rejection')
stop()

n=nativeFixture({noObserver=true});stop=n.adapter.observe(function()end)
fingerprint=n.adapter.windows()[1].fingerprint
check(n.adapter.windows()[1].fingerprint==fingerprint,'poll-only fallback retains AX identity cache')
n.chat.attrs.AXURL='https://claude.ai/oauth/callback';n.state.time=2.1
check(n.adapter.windows()[1].sourceURL==n.shell.attrs.AXURL,'auth surface not selected; shell fallback remains')
n.window.attrs.AXChildren={};n.state.time=4.2
check(n.adapter.windows()[1].sourceURL==nil,'native system dialog without web area unsupported')
stop()
n=nativeFixture({noObserver=true});stop=n.adapter.observe(function()end)
n.chat.attrs.AXLoaded=true
local loadedWindow=n.adapter.windows()[1]
n.chat.attrs.AXLoaded=false;n.state.time=2.1
local loadingWindow=n.adapter.windows()[1]
check(loadingWindow.loading==true and loadingWindow.fingerprint~=loadedWindow.fingerprint and loadingWindow.structureFingerprint~=loadedWindow.structureFingerprint,'AXLoaded false is preserved as same-element same-URL loading witness')
n.chat.attrs.AXLoaded=true;n.state.time=4.2
local reloadedWindow=n.adapter.windows()[1]
check(not reloadedWindow.loading and reloadedWindow.fingerprint==loadedWindow.fingerprint,'AXLoaded completion returns to loaded document metadata without text reads')
stop()
n=nativeFixture({unsupportedNotifications=true});stop=n.adapter.observe(function()end)
check(n.adapter.windows()[1].sourceURL==n.chat.attrs.AXURL,'unsupported AX notifications do not prevent polling')
stop()
n=nativeFixture({noObserver=true});stop=n.adapter.observe(function()end)
for _=1,12005 do n.window.attrs.AXChildren[#n.window.attrs.AXChildren+1]=node({AXRole='AXGroup',AXChildren={}})end
local incomplete=n.adapter.windows()[1]
check(incomplete.incomplete and incomplete.sourceURL==nil,'node cap produces incomplete discovery instead of accepted source')
stop()
n=nativeFixture({noObserver=true});stop=n.adapter.observe(function()end)
local devtools=node({AXRole='AXWebArea',AXURL='devtools://devtools/bundled/devtools_app.html',AXChildren={node({AXRole='AXGroup'})}})
local original=n.adapter.windows()[1]
n.window.attrs.AXChildren[#n.window.attrs.AXChildren+1]=devtools;n.state.time=2.1
local docked=n.adapter.windows()[1]
check(docked.isTools and docked.fingerprint==original.fingerprint and docked.structureFingerprint==original.structureFingerprint,'DevTools itself is excluded from source frame fingerprints')
n.window.attrs.AXChildren={n.shell,devtools}
n.state.time=4.2
check(n.adapter.windows()[1].isTools and devtools.reads.AXChildren==nil,'embedded DevTools subtree not traversed')
stop()
n=nativeFixture({noObserver=true});stop=n.adapter.observe(function()end)
local embeddedTools=node({AXRole='AXWebArea',AXURL='devtools://devtools/bundled/devtools_app.html',AXVisible=false,AXChildren={}})
n.window.attrs.AXChildren[#n.window.attrs.AXChildren+1]=embeddedTools
local hidden=n.adapter.windows()[1]
check(not hidden.isTools and hidden.embeddedToolsHidden==1,'explicit AXVisible false remains false and hidden embedded tools do not block')
local d=n.adapter.diagnostics()
check(d.embeddedToolsHidden==1 and d.embeddedToolsVisible==0 and d.embeddedToolsUnknown==0 and d.titledTools==0,'safe diagnostics distinguish hidden embedded tools from titled tools')
local requests=0
local visibilityCoordinator=M.new({},n.adapter,{snapshot=function()return {phase='idle'}end,begin=function()requests=requests+1;return true end})
visibilityCoordinator.tick();n.state.time=1.1;visibilityCoordinator.tick()
check(requests==1 and visibilityCoordinator.snapshot().counts.embeddedToolsHidden==1,'hidden embedded tools allow source scan and safe status counter')
embeddedTools.attrs.AXVisible=true;n.state.time=3.2
local shown=n.adapter.windows()[1]
check(shown.isTools and shown.embeddedToolsVisible==1,'visible docked tools remain protected')
embeddedTools.attrs.AXVisible=nil;n.state.time=5.3
local unknownVisibility=n.adapter.windows()[1]
check(unknownVisibility.isTools and unknownVisibility.embeddedToolsUnknown==1,'unknown embedded visibility remains protected')
local wrapper=node({AXRole='AXGroup',AXVisible=false,AXChildren={embeddedTools}})
n.window.attrs.AXChildren={n.shell,n.chat,wrapper};n.state.time=7.4
check(not n.adapter.windows()[1].isTools,'explicit hidden ancestor also hides embedded tools')
n.window.attrs.AXTitle='Developer Tools - synthetic';n.window.attrs.AXVisible=false;n.state.time=9.5
d=n.adapter.diagnostics()
check(not n.adapter.windows()[1].isTools and d.hiddenTitledTools==1 and d.titledTools==0,'explicit hidden titled tools are counted separately')
n.window.attrs.AXVisible=nil;n.state.time=11.6;d=n.adapter.diagnostics()
check(n.adapter.windows()[1].isTools and d.titledTools==1,'unknown visibility titled tools remain protected')
stop()
n=nativeFixture({fullscreen=true});stop=n.adapter.observe(function()end)
for _,element in ipairs({n.shell,n.chat,n.artifact,n.content,n.doc})do
  element.attrs.AXURL=setmetatable({url=element.attrs.AXURL},{__tostring=function()error('NSURL data must not be converted with tostring')end})
end
local diagnostic=n.adapter.diagnostics()
check(diagnostic.axWindows==0 and diagnostic.focusedPresent==1 and diagnostic.focusedRole=='AXWindow','diagnostics describe full-screen AX fallback using safe metadata')
check(diagnostic.windowIdPresent==1 and diagnostic.webAreas==5 and diagnostic.urlTypes.table==5,'diagnostics count raw URL table values')
check(diagnostic.sourceCandidates==3 and diagnostic.scanIncomplete==0,'documented NSURL table data produces valid source candidates')
check(n.adapter.windows()[1].sourceURL==n.chat.attrs.AXURL.url,'standard AX URL table normalized without userdata stringification')
for key,value in pairs(diagnostic)do
  check(key~='title' and key~='url' and key~='sourceURL' and key~='documentId' and key~='context','diagnostics contain no private fields')
  if type(value)=='string' then check(value=='AXWindow','only whitelisted role string appears')end
end
diagnostic.urlTypes.table=900
check(n.adapter.diagnostics().urlTypes.table==5,'diagnostic tables detached from internal state')
stop()
n=nativeFixture({noObserver=true});stop=n.adapter.observe(function()end)
n.window.nativeWindow=nil
diagnostic=n.adapter.diagnostics()
check(diagnostic.windowIdPresent==0 and diagnostic.focusedPresent==1 and diagnostic.webAreas==5,'diagnostics distinguish missing native ID from missing web areas')
stop()
n=nativeFixture({noObserver=true});stop=n.adapter.observe(function()end)
local unknown=node({AXRole='AXWebArea',AXURL=io.stdout,AXChildren={}})
n.window.attrs.AXChildren={unknown};diagnostic=n.adapter.diagnostics()
check(diagnostic.urlTypes.userdata==1 and diagnostic.sourceCandidates==0,'unknown userdata never normalized into a source URL')
n.state.time=3
unknown.attrs.AXURL=setmetatable({},{__index=function()error('URL metamethod must not run')end})
diagnostic=n.adapter.diagnostics()
check(diagnostic.urlTypes.table==1 and diagnostic.sourceCandidates==0,'URL table read uses raw data without metamethod access')
stop()
for _,url in ipairs({'https://claude.ai.evil.example/','https://claude.ai:443/new','https://claude.ai/login','https://claude.ai/api/fixture','about:blank','file:///tmp/app.asar/.vite/renderer/main_window/index.html'})do
  check(M.sourceKind(url)==nil,'unsupported source URL rejected')
end
check(M.sourceKind('https://claude.ai/code/artifact/fixture')=='artifact','artifact URL classified separately')
check(M.sourceKind('https://claude.ai/new')=='chat','chat URL accepted')
for _,last in ipairs({168,169})do
  check(M.sourceKind('https://claude.ai/new?fixture='..string.char(226,128,last))==nil,'raw Unicode line separator rejected')
end
check(M.sourceKind('https://claude.ai/new?fixture=%E2%80%A8')=='chat','encoded Unicode separator remains URL data')

-- start wiring: templates are substituted as data, not by shell or executable string construction.
scenarios=scenarios+1
local originalOpen,originalLoadfile=io.open,loadfile
local captured,started= nil,0
local templates={version=1,revision=3,probeTemplate='probe("__RTL_CONSOLE_NONCE__",__RTL_CONSOLE_EXPECTED_URL_JSON__)',
  payloads={chat='payload("__RTL_CONSOLE_NONCE__","__RTL_CONSOLE_DOCUMENT_ID__")'}}
local driverState={phase='idle'}
local driver={snapshot=function()return driverState end,begin=function()return true end,stop=function()started=started-1 end}
local timerStopped,timerCallback,clock=0,nil,0
local fakeHS={json={decode=function(source)check(source=='synthetic-json','bundle read once');return templates end,
  encode=function(value)
    assert(type(value)=='table','native JSON encoder rejects primitive values')
    check(#value==1 and type(value[1])=='string','expected source encoded through one-element array')
    return ' [ "'..value[1]:gsub('\\','\\\\'):gsub('"','\\"')..'" ] '
  end},
  timer={doEvery=function(interval,fn)check(interval==0.5,'bounded coordinator timer');timerCallback=fn;return {stop=function()timerStopped=timerStopped+1 end}end}}
local fakeAdapter={now=function()return clock end,identity=function()return nil end,idleSeconds=function()return 3 end,windows=function()return {}end}
io.open=function(path,mode)check(path=='/bundle.json' and mode=='r','read exact bundle');return {read=function()return 'synthetic-json'end,close=function()end}end
loadfile=function(path)
  if path=='/driver.lua' then return function()return {start=function(config)captured=config;started=started+1;return driver end}end end
  return originalLoadfile(path)
end
local ok,errorMessage=pcall(function()
  local controller=M.start({bundlePath='/bundle.json',driverPath='/driver.lua',adapter=fakeAdapter},fakeHS)
  check(started==1 and type(captured.probe)=='function' and type(captured.payload)=='function','start passes template functions to driver')
  local nonce,id='0123456789abcdef0123456789abcdef','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  check(captured.probe(nonce,nil)=='probe("'..nonce..'",null)','nil source guard encoded as JSON null')
  local url='https://claude.ai/chat/fixture?x="quoted"'
  check(captured.probe(nonce,url)=='probe("'..nonce..'","https://claude.ai/chat/fixture?x=\\"quoted\\"")','URL safely JSON encoded')
  check(captured.payload('chat',nonce,id)=='payload("'..nonce..'","'..id..'")','nonce and document ID template substitution')
  check(not pcall(captured.probe,'bad',nil),'bad nonce refused')
  check(not pcall(captured.payload,'chat',nonce,'bad'),'bad document ID refused')
  check(not pcall(captured.probe,nonce,'https://evil.example/'),'unsupported source refused before probe')
  controller.stop();check(started==0 and timerStopped==1,'start handle stops driver and coordinator timer')
  local injected=M.start({bundlePath='/bundle.json',driverPath='/driver.lua',adapter=fakeAdapter,driver=driver},fakeHS)
  check(started==0,'injected driver avoids constructing a native driver');injected.stop()

  local writes,writeCalls,failWrites={},0,false
  fakeHS.json.write=function(value,path)
    check(path=='/status.json','status written only to configured absolute path');writeCalls=writeCalls+1
    if failWrites then return false end
    writes[#writes+1]=value;return true
  end
  driverState={phase='await-result',reason='https://private.invalid/fixture',ok=false,applied=2,skipped=1,contexts=3,
    toolsExpectedLength=34,toolsActualLength=35,toolsFirstDiff=8,toolsSamePID=true,toolsTitleMatch=false,
    pasteExpectedLength=2190708,pasteEnteredLength=21942,pasteFirstDiff=1,pasteComparedBytes=21942,pastePromptFocused=true,
    title='PRIVATE',sourceURL='https://private.invalid',context='PRIVATE',documentId='PRIVATE'}
  local statusDriver={snapshot=function()return driverState end,begin=function()return true end,
    stop=function()driverState={phase='cleanup',ok=false}end}
  local statusController=M.start({bundlePath='/bundle.json',driverPath='/driver.lua',adapter=fakeAdapter,driver=statusDriver,statusFile='/status.json'},fakeHS)
  check(#writes==1 and writes[1].lastDriver.applied==2 and writes[1].lastDriver.contexts==3,'safe driver counts written at startup')
  local last=writes[#writes].lastDriver
  check(last.toolsExpectedLength==34 and last.toolsActualLength==35 and last.toolsFirstDiff==8 and last.toolsSamePID==true and last.toolsTitleMatch==false,'safe title diagnostics retained without title content')
  check(last.pasteExpectedLength==2190708 and last.pasteEnteredLength==21942 and last.pasteFirstDiff==1 and last.pastePromptFocused==true,'paste diagnostics retain only counts and flags')
  check(last.title==nil and last.sourceURL==nil and last.context==nil and last.documentId==nil and last.reason==nil,'driver private fields and URL-shaped reason excluded')
  driverState.toolsExpectedLength=-1;driverState.toolsActualLength=65537;driverState.toolsFirstDiff=0.5
  driverState.toolsSamePID='true';driverState.toolsTitleMatch=1
  driverState.pasteExpectedLength=8388609;driverState.pasteEnteredLength=-1;driverState.pasteFirstDiff=0.5;driverState.pastePromptFocused='PRIVATE'
  local invalid=statusController.snapshot().lastDriver
  check(invalid.toolsExpectedLength==nil and invalid.toolsActualLength==nil and invalid.toolsFirstDiff==nil and invalid.toolsSamePID==nil and invalid.toolsTitleMatch==nil,'invalid title diagnostic types and ranges excluded')
  check(invalid.pasteExpectedLength==nil and invalid.pasteEnteredLength==nil and invalid.pasteFirstDiff==nil and invalid.pastePromptFocused==nil,'invalid paste diagnostics excluded')
  driverState.toolsExpectedLength=34;driverState.toolsActualLength=35;driverState.toolsFirstDiff=8
  driverState.toolsSamePID=true;driverState.toolsTitleMatch=false
  statusController.tick();local unchanged=writeCalls;statusController.tick();statusController.tick()
  check(writeCalls==unchanged,'unchanged status is not written again')
  driverState.phase='execute';statusController.tick();check(writeCalls==unchanged+1,'driver phase change persisted without focus changes')
  failWrites=true;driverState.phase='await-result';statusController.tick()
  local failed=statusController.snapshot()
  check(failed.statusWriteFailed and failed.counts.statusWriteFailures==1,'write failure visible without crashing coordinator')
  local attempts=writeCalls;statusController.tick();check(writeCalls==attempts,'failed status writes have retry backoff')
  failWrites=false;clock=6;statusController.tick()
  check(not statusController.snapshot().statusWriteFailed and writes[#writes].counts.statusWriteFailures==1,'status write recovers and keeps failure count')
  local stopsBefore=timerStopped
  local pending=statusController.stop()
  check(pending.cleanupPending and timerStopped==stopsBefore,'status monitor stays until driver cleanup finishes')
  check(writes[#writes].phase=='watcher-stopped' and writes[#writes].cleanupPending,'pending stop written honestly')
  driverState={phase='complete',ok=false,toolsClosed=true,clipboardRestored=true};timerCallback()
  check(timerStopped==stopsBefore+1 and not writes[#writes].cleanupPending,'final cleanup persisted before monitor timer stops')
  check(writes[#writes].running==false and writes[#writes].lastDriver.toolsClosed,'final stopped status retains safe cleanup evidence')
end)
io.open,loadfile=originalOpen,originalLoadfile
check(ok,errorMessage)
return {ok=true,assertions=assertions,scenarios=scenarios}
