-- Discover accessibility metadata only. Snapshots exclude text, document titles, and URLs.
local M={}
local bundle='com.anthropic.claudefordesktop'
local appPath='/Applications/Claude.app'
local function eligible(info)
  return info and info.bundle==bundle and info.path==appPath and type(info.pid)=='number'
end
local function toolsTitle(title)return type(title)=='string' and title:match('^Developer Tools %- ')~=nil end
local function claudeURL(url)
  if type(url)~='string' then return false end
  local host='https://claude.ai'
  if url:sub(1,#host)~=host then return false end
  local rest=url:sub(#host+1)
  return rest=='' or rest:match('^[/?#]')~=nil
end
local function sourceKind(url)
  if type(url)~='string' or url:find('[%z\1-\31\127]') or url:find('\226\128[\168\169]') then return nil end
  local host='https://claude.ai'
  if url:sub(1,#host)==host then
    local rest=url:sub(#host+1)
    if rest~='' and not rest:match('^[/?#]') then return nil end
    local path=rest:match('^([^?#]*)') or ''
    for _,part in ipairs({'oauth','login','auth','api'}) do
      if path=='/'..part or path:sub(1,#part+2)=='/'..part..'/' then return nil end
    end
    if path:sub(1,15)=='/code/artifact/' then return 'artifact' end
    return 'chat'
  end
  local prefix='file:///Applications/Claude.app/Contents/Resources/app.asar/.vite/renderer/'
  if url:sub(1,#prefix)==prefix then
    local tail=url:sub(#prefix+1)
    for _,name in ipairs({'main_window','quick_window','about_window','find_in_page'}) do
      if tail:sub(1,#name+1)==name..'/' then return 'shell' end
    end
  end
end

local function settings(config)
  local idle=config.idleSeconds or 2
  local debounce=config.debounceSeconds or 1
  local health=config.healthSeconds or 30
  local retry=config.retrySeconds or 5
  assert(type(idle)=='number' and idle>=2 and idle<=120,'idleSeconds must be at least 2')
  assert(type(debounce)=='number' and debounce>=0.5 and debounce<=30,'invalid debounceSeconds')
  assert(type(health)=='number' and health>=10 and health<=3600,'invalid healthSeconds')
  assert(type(retry)=='number' and retry>=2 and retry<=60,'invalid retrySeconds')
  local interval=config.tickSeconds or 0.5
  assert(type(interval)=='number' and interval>=0.1 and interval<=5,'invalid tickSeconds')
  return idle,debounce,health,retry
end

function M.new(config,adapter,driver)
  local idle,debounce,health,retry=settings(config)
  assert(driver and type(driver.begin)=='function' and type(driver.snapshot)=='function','driver required')
  local running,attention,phase=true,false,'waiting-for-focus'
  local pid,cache,job,stopObserving=nil,{},nil,nil
  local foregroundWindow,activation=nil,0
  local driverStopFailed=false
  local lastApplied,lastCompleted
  local function kindCounts(value)
    if type(value)~='table' then return nil end
    local out={}
    for _,kind in ipairs({'shell','chat','artifact','artifact-content','document'})do
      local count=rawget(value,kind)
      if type(count)=='number' and count>=0 and count<=10000 and count%1==0 then out[kind]=count end
    end
    return out
  end
  local function receiptCopy(value)
    if not value then return nil end
    local out={}
    for key,item in pairs(value)do
      if type(item)=='table' then local nested={};for kind,count in pairs(item)do nested[kind]=count end;out[key]=nested
      else out[key]=item end
    end
    return out
  end
  local lastBeginReason
  local beginReasons={}
  for _,reason in ipairs({'busy','stopped','invalid-request','invalid-source','target-not-focused','existing-tools-left-untouched',
    'target-missing','clipboard-multiple-items-or-unavailable','clipboard-changed','clipboard-unavailable','clipboard-format-unavailable',
    'invalid-or-reused-nonce','payload-unavailable','probe-unavailable','input-monitor-unavailable','adapter-failed'})do beginReasons[reason]=true end
  local counts={started=0,completed=0,failed=0,skipped=0,windows=0,incompleteWindows=0,processChanges=0,observerFailures=0,
    layoutEvents=0,loadEvents=0,metadataEvents=0,focusEvents=0,fingerprintChanges=0,identityCoalesced=0,metadataScans=0,healthScans=0,eventScans=0,
    titledTools=0,hiddenTitledTools=0,embeddedToolsVisible=0,embeddedToolsHidden=0,embeddedToolsUnknown=0,
    sourceCandidates=0,ambiguousSources=0,AXrootsFocusedMismatch=0}
  local function snapshot()
    local copy={};for key,value in pairs(counts)do copy[key]=value end
    if type(adapter.accessibilityStatus)=='function' then
      local ok,status=pcall(adapter.accessibilityStatus)
      if ok and type(status)=='table' then
        for _,key in ipairs({'manualAccessibilityEnabled','manualAccessibilityAttempts','manualAccessibilityFailures'})do
          local value=status[key]
          if type(value)=='number' and value>=0 and value<=3 and value%1==0 then copy[key]=value end
        end
      end
    end
    local appliedCopy,completedCopy=receiptCopy(lastApplied),receiptCopy(lastCompleted)
    local ok,result=pcall(driver.snapshot)
    ok=ok and type(result)=='table'
    local cleanupPending=ok and (result.phase=='cleanup' or result.cleanupPending==true) or false
    local cleanupRequired=driverStopFailed or ok and result.cleanupRequired==true or false
    local lastDriver={}
    if ok and type(result)=='table' then
      lastDriver.appliedKinds=kindCounts(result.appliedKinds)
      lastDriver.probedKinds=kindCounts(result.probedKinds)
      for _,key in ipairs({'phase','reason','failurePhase'})do
        local value=result[key]
        if type(value)=='string' and #value<=80 and value:match('^[%w_-]+$') then lastDriver[key]=value end
      end
      for _,key in ipairs({'ok','cleanupRequired','toolsClosed','clipboardRestored','toolsSamePID','toolsTitleMatch','focusIsSource','focusIsTools','frontmost','focusedWindowPresent','tracking','pastePromptFocused','pasteComparisonTruncated','pasteTransformsCompared','pasteEqualAfterTrailingLF','pasteEqualAfterLineEndSpaces'})do
        if type(result[key])=='boolean' then lastDriver[key]=result[key] end
      end
      for _,key in ipairs({'pasteEnteredLength','pasteExpectedLength','pasteFirstDiff','pasteComparedBytes'})do
        local value=result[key]
        if type(value)=='number' and value>=0 and value<=8388608 and value%1==0 then lastDriver[key]=value end
      end
      for _,key in ipairs({'applied','skipped','contexts','copyVerifications'})do
        local value=result[key]
        if type(value)=='number' and value>=0 and value<=10000 and value%1==0 then lastDriver[key]=value end
      end
      for _,key in ipairs({'toolsExpectedLength','toolsActualLength','toolsFirstDiff'})do
        local value=result[key]
        if type(value)=='number' and value>=0 and value<=65536 and value%1==0 then lastDriver[key]=value end
      end
    end
    return {running=running,phase=phase,attentionRequired=attention or cleanupRequired and not cleanupPending,counts=copy,
      cleanupPending=cleanupPending,cleanupRequired=cleanupRequired,lastDriver=lastDriver,lastBeginReason=lastBeginReason,lastApplied=appliedCopy,lastCompleted=completedCopy}
  end
  local function markDirty(id,event)
    if not running then return end
    -- Opening and closing tools changes app focus. These events do not prove a new document.
    if event=='AXFocusedWindowChanged' or event=='AXFocusedUIElementChanged' or event=='application' then
      counts.focusEvents=counts.focusEvents+1;return
    end
    -- Our layout changes do not prove a new document. The adapter already invalidated metadata.
    if event=='AXLayoutChanged' then counts.layoutEvents=counts.layoutEvents+1;return end
    if event=='AXUIElementDestroyed' or event=='AXWindowCreated' then counts.metadataEvents=counts.metadataEvents+1;return end
    if event=='AXLoadComplete' then counts.loadEvents=counts.loadEvents+1 end
    local now=adapter.now()
    for key,entry in pairs(cache)do
      if id==nil or key==id then
        entry.dirty=true;entry.changedAt=now;entry.generation=(entry.generation or 0)+1;entry.reason='event'
        if event=='AXLoadComplete' then entry.hardGeneration=(entry.hardGeneration or 0)+1 end
      end
    end
  end
  local function cancelDriver()
    if driver.cancel then pcall(driver.cancel) end
  end
  local function fail(entry,now)
    counts.failed=counts.failed+1
    entry.failures=math.min((entry.failures or 0)+1,5)
    entry.nextTry=now+math.min(60,retry*2^(entry.failures-1))
    entry.dirty=true;entry.changedAt=now
  end
  local function tick()
    if not running then return snapshot() end
    local now=adapter.now()
    local info=adapter.identity()
    local nextPID=eligible(info) and info.pid or nil
    if nextPID~=pid then
      if job then cancelDriver() end
      if pid~=nil then counts.processChanges=counts.processChanges+1 end
      pid,cache,job,attention=nextPID,{},nil,false
      foregroundWindow,activation=nil,0
      lastApplied,lastCompleted=nil,nil
      lastBeginReason=nil
      counts.windows=0;counts.incompleteWindows=0
    end
    if job then
      local result=driver.snapshot()
      if result.phase=='cleanup' or result.cleanupPending==true then
        phase='cleanup';return snapshot()
      end
      if result.phase=='complete' or result.phase=='idle' or result.reason or result.cleanupRequired then
        local entry=cache[job.windowId]
        if result.ok==true and result.phase=='complete' then
          counts.completed=counts.completed+1
          lastCompleted={processId=pid,windowId=job.windowId,scan=counts.completed,sourceKind=job.kind,
            appliedKinds=kindCounts(result.appliedKinds),probedKinds=kindCounts(result.probedKinds)}
            for _,key in ipairs({'applied','skipped','contexts','copyVerifications'})do
              local value=result[key]
              if type(value)=='number' and value>=0 and value<=10000 and value%1==0 then lastCompleted[key]=value end
            end
            for _,key in ipairs({'toolsClosed','clipboardRestored'})do
              if type(result[key])=='boolean' then lastCompleted[key]=result[key] end
            end
          if lastCompleted.applied and lastCompleted.applied>=1 then
            lastApplied=lastCompleted
          end
          if entry then
            entry.dirty=entry.generation~=job.generation;entry.lastScan=now;entry.failures=0;entry.nextTry=now+debounce
            entry.coalesceUntil=now+2;entry.scannedHardGeneration=job.hardGeneration
            entry.healthDue=false;entry.observedActivation=activation
          end
          phase='waiting-for-idle'
        else
          if entry then fail(entry,now) else counts.failed=counts.failed+1 end
          if result.cleanupRequired then attention=true;phase='attention-required' else phase='retry-backoff' end
        end
        job=nil
      else phase='scanning' end
      return snapshot()
    end
    if attention then phase='attention-required';return snapshot() end
    if not nextPID then phase='waiting-for-app';return snapshot() end
    if info.frontmost~=true then foregroundWindow=nil;phase='waiting-for-focus';return snapshot() end
    if info.focusedWindow~=foregroundWindow then foregroundWindow=info.focusedWindow;activation=activation+1 end
    local idleTime=adapter.idleSeconds()
    if type(idleTime)~='number' or idleTime<idle then phase='waiting-for-idle';return snapshot() end
    local windows=adapter.windows()
    local seen,focused,hasTools={},nil,false
    counts.incompleteWindows=0
    for _,key in ipairs({'titledTools','hiddenTitledTools','embeddedToolsVisible','embeddedToolsHidden','embeddedToolsUnknown','sourceCandidates','ambiguousSources','AXrootsFocusedMismatch'})do counts[key]=0 end
    for _,window in ipairs(windows)do
      if window.pid==pid then
        seen[window.id]=true
        if window.visible~=false and (window.isTools or toolsTitle(window.title)) then hasTools=true end
        if toolsTitle(window.title) then
          local key=window.visible==false and 'hiddenTitledTools' or 'titledTools';counts[key]=counts[key]+1
        end
        for _,key in ipairs({'embeddedToolsVisible','embeddedToolsHidden','embeddedToolsUnknown','sourceCandidates','ambiguousSources','AXrootsFocusedMismatch'})do
          local value=window[key]
          if type(value)=='number' and value>=0 and value<=12000 and value%1==0 then counts[key]=counts[key]+value end
        end
        if window.incomplete then counts.incompleteWindows=counts.incompleteWindows+1 end
        if window.id==info.focusedWindow then focused=window end
        local kind=sourceKind(window.sourceURL)
        if not window.incomplete and (kind=='chat' or kind=='artifact' or kind=='shell') then
          local entry=cache[window.id]
          if not entry then
            entry={sourceURL=window.sourceURL,fingerprint=window.fingerprint,structure=window.structureFingerprint,
              dirty=true,generation=0,hardGeneration=0,reason='metadata',changedAt=now,lastScan=now,nextTry=now}
            cache[window.id]=entry
          elseif entry.fingerprint~=window.fingerprint or entry.sourceURL~=window.sourceURL then
            local identityOnly=entry.sourceURL==window.sourceURL and type(window.structureFingerprint)=='string'
              and entry.structure==window.structureFingerprint and entry.coalesceUntil and now<=entry.coalesceUntil
              and entry.hardGeneration==entry.scannedHardGeneration
            if identityOnly then counts.identityCoalesced=counts.identityCoalesced+1
            else
              counts.fingerprintChanges=counts.fingerprintChanges+1
              entry.dirty=true;entry.changedAt=now;entry.generation=entry.generation+1;entry.reason='metadata'
            end
            entry.sourceURL=window.sourceURL;entry.fingerprint=window.fingerprint;entry.structure=window.structureFingerprint
          end
        else cache[window.id]=nil end
      end
    end
    for id in pairs(cache)do if not seen[id] then cache[id]=nil end end
    counts.windows=0;for _ in pairs(cache)do counts.windows=counts.windows+1 end
    if hasTools then phase='user-tools-open';return snapshot() end
    if not focused or not cache[focused.id] then phase='unsupported-window';return snapshot() end
    local entry=cache[focused.id]
    if entry.observedActivation~=activation then
      entry.observedActivation=activation
      entry.healthDue=now-entry.lastScan>=health
    end
    if focused.loading==true then phase='waiting-for-load';return snapshot() end
    if now<entry.nextTry then phase='retry-backoff';return snapshot() end
    -- Continue passive metadata polling. Run the quiet fallback only on returning to a window.
    -- A reload with no AX evidence cannot be detected until the next return.
    local due=entry.dirty and now-entry.changedAt>=debounce or not entry.dirty and entry.healthDue==true
    if not due then phase=entry.dirty and 'debouncing' or 'waiting-for-change';return snapshot() end
    local ok,reason=driver.begin({windowId=focused.id,toolsTitle='Developer Tools - '..entry.sourceURL,sourceURL=entry.sourceURL,scan=true})
    lastBeginReason=ok~=true and (type(reason)=='string' and beginReasons[reason] and reason or 'driver-begin-failed') or nil
    if ok==true then
      local reason=entry.dirty and entry.reason or 'health'
      local counter=reason=='metadata' and 'metadataScans' or reason=='event' and 'eventScans' or 'healthScans'
      counts[counter]=counts[counter]+1
      job={windowId=focused.id,generation=entry.generation,hardGeneration=entry.hardGeneration,kind=sourceKind(entry.sourceURL)};counts.started=counts.started+1;phase='scanning'
    elseif reason=='busy' then
      entry.nextTry=now+retry;counts.skipped=counts.skipped+1;phase='driver-busy'
    else
      fail(entry,now);phase='retry-backoff'
      local result=driver.snapshot()
      if result.cleanupRequired then attention=true;phase='attention-required' end
    end
    return snapshot()
  end
  local function stop()
    if not running then return snapshot() end
    running=false
    if stopObserving then pcall(stopObserving);stopObserving=nil end
    if driver.stop then local ok=pcall(driver.stop);driverStopFailed=not ok else cancelDriver() end
    cache={};job=nil;counts.windows=0;counts.incompleteWindows=0;phase='watcher-stopped'
    return snapshot()
  end
  if adapter.observe then
    local ok,value=pcall(adapter.observe,markDirty)
    if ok and type(value)=='function' then stopObserving=value else counts.observerFailures=counts.observerFailures+1 end
  end
  return {tick=function()
    local ok,value=pcall(tick)
    if not ok then
      counts.failed=counts.failed+1;cancelDriver();job=nil;attention=true;phase='attention-required'
      return snapshot()
    end
    return value
  end,markDirty=markDirty,snapshot=snapshot,isRunning=function()return running end,stop=stop}
end

function M.nativeAdapter(hs)
  local observer,observedPID,callback,appWatcher=nil,nil,nil,nil
  local oldWindows,metadataCache,serial,watchRecords={},{},0,{}
  local accessibilityPID,accessibilityEnabled,accessibilityAttempts,accessibilityFailures,accessibilityNext=nil,false,0,0,0
  local function accessibilityStatus()
    return {manualAccessibilityEnabled=accessibilityEnabled and 1 or 0,manualAccessibilityAttempts=accessibilityAttempts,
      manualAccessibilityFailures=accessibilityFailures}
  end
  local function emptyDiagnostic()
    return {axWindows=0,focusedPresent=0,focusedRole='missing',windowIdPresent=0,webAreas=0,
      urlTypes={string=0,table=0,userdata=0,['nil']=0,other=0},sourceCandidates=0,scanIncomplete=0,
      titledTools=0,hiddenTitledTools=0,embeddedToolsVisible=0,embeddedToolsHidden=0,embeddedToolsUnknown=0,
      ambiguousSources=0,AXrootsFocusedMismatch=0}
  end
  local diagnostic=emptyDiagnostic()
  local function invalidate(id)
    if id then metadataCache[id]=nil else metadataCache={}end
  end
  local function attr(element,name)
    if not element then return nil end
    local ok,value=pcall(function()return element:attributeValue(name)end)
    if ok then return value end
  end
  local function axURL(value)
    if type(value)=='string' then return value end
    -- LuaSkin/hs.axuielement converts NSURL to the documented {url=...,filePath=...} table.
    -- Do not invoke unknown userdata or metamethods to construct URLs.
    if type(value)=='table' then
      local url=rawget(value,'url')
      if type(url)=='string' then return url end
    end
  end
  local function app()
    local value=hs.application.get(bundle)
    if value and value:bundleID()==bundle and value:path()==appPath then return value end
  end
  local function axWindowId(element)
    local ok,value=pcall(function()return element:asHSWindow()end)
    return ok and value and value:id() or nil
  end
  local function stopAX()
    if observer then pcall(function()observer:stop()end) end
    observer,observedPID,watchRecords=nil,nil,{}
  end
  local function enableAccessibility(value)
    if accessibilityPID~=value:pid() then
      accessibilityPID,accessibilityEnabled,accessibilityAttempts,accessibilityFailures,accessibilityNext=value:pid(),false,0,0,0
    end
    local now=hs.timer.absoluteTime()/1000000000
    if accessibilityEnabled or accessibilityAttempts>=3 or now<accessibilityNext then return end
    accessibilityAttempts=accessibilityAttempts+1;accessibilityNext=now+5
    local root=hs.axuielement.applicationElement(value)
    if attr(root,'AXManualAccessibility')==true then accessibilityEnabled=true;return end
    -- Use the official Electron API to enable this app AX tree, without system or VoiceOver changes.
    -- https://github.com/electron/electron/blob/main/docs/tutorial/accessibility.md
    local ok,result=pcall(function()return root:setAttributeValue('AXManualAccessibility',true)end)
    if ok and result==root then accessibilityEnabled=true;invalidate()
    else accessibilityFailures=accessibilityFailures+1 end
  end
  local function observeElement(element,notification)
    if not observer then return end
    for _,record in ipairs(watchRecords)do if record.element==element and record.notification==notification then record.seen=true;return end end
    local ok=pcall(function()observer:addWatcher(element,notification)end)
    if ok then watchRecords[#watchRecords+1]={element=element,notification=notification,seen=true} end
  end
  local function ensureAX()
    local value=app()
    if not value then
      stopAX();oldWindows={};invalidate()
      accessibilityPID,accessibilityEnabled,accessibilityAttempts,accessibilityFailures,accessibilityNext=nil,false,0,0,0
      return
    end
    enableAccessibility(value)
    if observedPID==value:pid() then return end
    stopAX();oldWindows={};invalidate()
    observedPID=value:pid()
    if not hs.axuielement.observer then return end
    local ok,result=pcall(function()
      local item=hs.axuielement.observer.new(value:pid())
      item:callback(function(_,element,event)
        if not callback then return end
        local window=attr(element,'AXWindow') or (attr(element,'AXRole')=='AXWindow' and element)
        if window and toolsTitle(attr(window,'AXTitle')) then return end
        local url=axURL(attr(element,'AXURL'))
        if type(url)=='string' and url:sub(1,11)=='devtools://' then return end
        local id=window and axWindowId(window) or nil
        invalidate(id);callback(id,event)
      end)
      return item
    end)
    if not ok or not result then return end
    observer=result;observedPID=value:pid()
    local root=hs.axuielement.applicationElement(value)
    for _,name in ipairs({'AXWindowCreated','AXFocusedWindowChanged','AXUIElementDestroyed'})do observeElement(root,name)end
    pcall(function()observer:start()end)
  end
  local function webAreas(root,previous)
    local queue,index,result={{element=root,depth=0}},1,{}
    local stats={webAreas=0,urlTypes={string=0,table=0,userdata=0,['nil']=0,other=0},sourceCandidates=0}
    while index<=#queue and index<=12000 do
      local item=queue[index];index=index+1
      local role=attr(item.element,'AXRole')
      local skipChildren=false
      local visible=attr(item.element,'AXVisible')
      if item.hidden then visible=false end
      if role=='AXWebArea' then
        stats.webAreas=stats.webAreas+1
        local rawURL=attr(item.element,'AXURL')
        local rawType=type(rawURL)
        if stats.urlTypes[rawType]==nil then rawType='other' end
        stats.urlTypes[rawType]=stats.urlTypes[rawType]+1
        local url=axURL(rawURL)
        local kind=sourceKind(url)
        if kind=='chat' or kind=='artifact' or kind=='shell' then stats.sourceCandidates=stats.sourceCandidates+1 end
        skipChildren=type(url)=='string' and url:sub(1,11)=='devtools://'
        if type(url)=='string' then
          local id
          for _,old in ipairs(previous or {})do if old.element==item.element then id=old.id;break end end
          if not id then serial=serial+1;id=serial end
          local loaded=attr(item.element,'AXLoaded')
          if type(loaded)~='boolean' then loaded=nil end
          result[#result+1]={element=item.element,id=id,url=url,depth=item.depth,visible=visible,loaded=loaded}
        end
      end
      if not skipChildren then
        for _,child in ipairs(attr(item.element,'AXChildren') or {})do queue[#queue+1]={element=child,depth=item.depth+1,hidden=visible==false}end
      end
    end
    return result,index>#queue,stats
  end
  local adapter={}
  adapter.accessibilityStatus=accessibilityStatus
  function adapter.now()return hs.timer.absoluteTime()/1000000000 end
  function adapter.idleSeconds()return hs.host.idleTime()end
  function adapter.identity()
    local value=app();if not value then return nil end
    ensureAX()
    local frontmost=value:isFrontmost()
    local focusedId
    local ok,global=pcall(function()return hs.window and hs.window.focusedWindow and hs.window.focusedWindow()end)
    if not ok then frontmost=false
    elseif global then
      local valid,id=pcall(function()
        local owner=global:application()
        if owner and owner:pid()==value:pid() then return global:id() end
      end)
      if valid and id then focusedId=id else frontmost=false end
    else
      -- Fullscreen can have no global window. Use the app window only in that case.
      local focused=attr(hs.axuielement.applicationElement(value),'AXFocusedWindow')
      focusedId=focused and axWindowId(focused)
    end
    return {pid=value:pid(),bundle=value:bundleID(),path=value:path(),frontmost=frontmost,focusedWindow=focusedId}
  end
  function adapter.windows(diagnosticMode)
    local value=app();if not value then return {} end
    ensureAX()
    local appElement=hs.axuielement.applicationElement(value)
    local roots=attr(appElement,'AXWindows') or {}
    local focused=attr(appElement,'AXFocusedWindow')
    local role=attr(focused,'AXRole')
    local roles={AXWindow=true,AXDialog=true,AXSheet=true,AXSystemDialog=true,AXGroup=true,AXWebArea=true}
    diagnostic={axWindows=type(roots)=='table' and #roots or 0,focusedPresent=focused and 1 or 0,
      focusedRole=focused and (roles[role] and role or 'other') or 'missing',windowIdPresent=focused and axWindowId(focused) and 1 or 0,
      webAreas=0,urlTypes={string=0,table=0,userdata=0,['nil']=0,other=0},sourceCandidates=0,scanIncomplete=0,
      titledTools=0,hiddenTitledTools=0,embeddedToolsVisible=0,embeddedToolsHidden=0,embeddedToolsUnknown=0,
      ambiguousSources=0,AXrootsFocusedMismatch=0}
    local function addStats(stats,complete)
      diagnostic.webAreas=diagnostic.webAreas+stats.webAreas
      diagnostic.sourceCandidates=diagnostic.sourceCandidates+stats.sourceCandidates
      for key,count in pairs(stats.urlTypes)do diagnostic.urlTypes[key]=diagnostic.urlTypes[key]+count end
      if not complete then diagnostic.scanIncomplete=diagnostic.scanIncomplete+1 end
    end
    if type(roots)~='table' then roots={}end
    local rootList,rootIds={},{},{}
    local function addRoot(root)
      if not root then return end
      local id=axWindowId(root)
      if id and rootIds[id] then return end
      for _,old in ipairs(rootList)do if old==root then return end end
      rootList[#rootList+1]=root;if id then rootIds[id]=true end
    end
    local globalId
    local ok,global=pcall(function()return hs.window and hs.window.focusedWindow and hs.window.focusedWindow()end)
    if ok and global then
      local worked,element,id=pcall(function()
        local owner=global:application()
        if not owner or owner:pid()~=value:pid() then return end
        local candidateId=global:id()
        if type(candidateId)~='number' then return end
        local root=hs.axuielement.windowElement(global)
        if root and axWindowId(root)==candidateId then return root,candidateId end
      end)
      if worked and element then
        globalId=id;addRoot(element)
        local found=focused and axWindowId(focused)==id or false
        for _,root in ipairs(roots)do if axWindowId(root)==id then found=true end end
        if not found then diagnostic.AXrootsFocusedMismatch=1 end
      end
    end
    for _,root in ipairs(roots)do addRoot(root)end
    addRoot(focused)
    for _,record in ipairs(watchRecords)do record.seen=false end
    for _,name in ipairs({'AXWindowCreated','AXFocusedWindowChanged','AXUIElementDestroyed'})do observeElement(appElement,name)end
    local out,nextWindows,nextMetadata={},{},{}
    local now=adapter.now()
    for _,root in ipairs(rootList)do
      local id=axWindowId(root)
      if not id and diagnosticMode then
        local _,complete,stats=webAreas(root)
        addStats(stats,complete)
      end
      if id then
        local title=attr(root,'AXTitle')
        local rootVisible=attr(root,'AXVisible')
        if toolsTitle(title) then
          local key=rootVisible==false and 'hiddenTitledTools' or 'titledTools';diagnostic[key]=diagnostic[key]+1
        end
        local areas,complete,stats
        if toolsTitle(title) then areas,complete,stats={},true,{webAreas=0,urlTypes={},sourceCandidates=0}
        else
          local cached=metadataCache[id]
          if cached and cached.root==root and now-cached.at<2 then areas,complete,stats=cached.areas,cached.complete,cached.stats
          else
            areas,complete,stats=webAreas(root,oldWindows[id])
            cached={root=root,areas=areas,complete=complete,stats=stats,at=now}
          end
          nextMetadata[id]=cached
        end
        addStats(stats,complete)
        nextWindows[id]=areas
        local best,rank,depth,ambiguous=nil,nil,nil,false
        local remoteDepth
        for _,area in ipairs(areas)do
          if claudeURL(area.url) and (not remoteDepth or area.depth<remoteDepth) then remoteDepth=area.depth end
        end
        local fingerprint,structure,hasTools={},{},toolsTitle(title) and rootVisible~=false
        local embedded={embeddedToolsVisible=0,embeddedToolsHidden=0,embeddedToolsUnknown=0}
        for _,area in ipairs(areas)do
          if area.url:sub(1,11)~='devtools://' then
            local lifecycle=area.loaded==true and ':loaded' or area.loaded==false and ':loading' or ':unknown'
            fingerprint[#fingerprint+1]=tostring(area.id)..':'..#area.url..':'..area.url..lifecycle
            structure[#structure+1]=#area.url..':'..area.url..lifecycle
          end
          if area.url:sub(1,11)=='devtools://' then
            local key=area.visible==false and 'embeddedToolsHidden' or area.visible==true and 'embeddedToolsVisible' or 'embeddedToolsUnknown'
            embedded[key]=embedded[key]+1;diagnostic[key]=diagnostic[key]+1
            if area.visible~=false then hasTools=true end
          end
          local kind=sourceKind(area.url)
          local priority=kind=='chat' and area.depth==remoteDepth and 1 or kind=='artifact' and area.depth==remoteDepth and 2 or kind=='shell' and 3 or nil
          if priority then
            if not best or priority<rank or priority==rank and area.depth<depth then
              best,rank,depth,ambiguous=area,priority,area.depth,false
            elseif priority==rank and area.depth==depth then ambiguous=true end
          end
          for _,name in ipairs({'AXLoadComplete','AXLayoutChanged','AXUIElementDestroyed'})do observeElement(area.element,name)end
        end
        table.sort(fingerprint);table.sort(structure)
        if ambiguous then diagnostic.ambiguousSources=diagnostic.ambiguousSources+1 end
        for _,name in ipairs({'AXLayoutChanged','AXFocusedUIElementChanged','AXUIElementDestroyed'})do observeElement(root,name)end
        out[#out+1]={id=id,pid=value:pid(),title=title,isTools=hasTools,visible=rootVisible,incomplete=not complete,loading=best and best.loaded==false or false,
          embeddedToolsVisible=embedded.embeddedToolsVisible,embeddedToolsHidden=embedded.embeddedToolsHidden,embeddedToolsUnknown=embedded.embeddedToolsUnknown,
          sourceCandidates=stats.sourceCandidates,ambiguousSources=ambiguous and 1 or 0,
          AXrootsFocusedMismatch=id==globalId and diagnostic.AXrootsFocusedMismatch or 0,
          sourceURL=complete and not ambiguous and best and best.url or nil,fingerprint=table.concat(fingerprint,'|'),structureFingerprint=table.concat(structure,'|')}
      end
    end
    oldWindows=nextWindows;metadataCache=nextMetadata
    for i=#watchRecords,1,-1 do
      local record=watchRecords[i]
      if not record.seen then pcall(function()observer:removeWatcher(record.element,record.notification)end);table.remove(watchRecords,i) end
    end
    return out
  end
  function adapter.diagnostics()
    diagnostic=emptyDiagnostic()
    local ok=pcall(adapter.windows,true)
    local result={};for key,value in pairs(diagnostic)do
      if type(value)=='table' then
        result[key]={};for name,count in pairs(value)do result[key][name]=count end
      else result[key]=value end
    end
    if not ok then result.scanIncomplete=result.scanIncomplete+1 end
    for key,value in pairs(accessibilityStatus())do result[key]=value end
    return result
  end
  function adapter.observe(fn)
    callback=fn
    local watcher=hs.application.watcher
    appWatcher=watcher.new(function(_,event,value)
      if not callback then return end
      if value and value:bundleID()==bundle and value:path()==appPath and (event==watcher.launched or event==watcher.activated or event==watcher.terminated) then
        if event==watcher.terminated then stopAX();oldWindows={};invalidate() else ensureAX();invalidate()end
        if callback then callback(nil,'application')end
      end
    end):start()
    ensureAX()
    return function()
      callback=nil;stopAX();oldWindows={};invalidate()
      if appWatcher then appWatcher:stop();appWatcher=nil end
    end
  end
  return adapter
end

function M.start(config,hs)
  settings(config)
  assert(type(config.bundlePath)=='string' and config.bundlePath:sub(1,1)=='/','absolute bundlePath required')
  assert(type(config.driverPath)=='string' and config.driverPath:sub(1,1)=='/','absolute driverPath required')
  assert(config.statusFile==nil or type(config.statusFile)=='string' and config.statusFile:sub(1,1)=='/','absolute statusFile required')
  local file=assert(io.open(config.bundlePath,'r'),'console bundle unavailable')
  local source=file:read('*a');file:close()
  local data=hs.json.decode(source)
  assert(type(data)=='table' and data.version==1 and type(data.revision)=='number' and data.revision>=1
    and type(data.probeTemplate)=='string' and type(data.payloads)=='table','invalid console bundle')
  local function nonceValue(value)
    assert(type(value)=='string' and #value>=16 and #value<=80 and value:match('^[%w_-]+$'),'invalid nonce')
    return value
  end
  local function probe(nonce,expectedURL)
    nonceValue(nonce)
    assert(expectedURL==nil or sourceKind(expectedURL),'invalid expected source URL')
    local encoded='null'
    if expectedURL~=nil then
      -- Native hs.json.encode requires a table. Encode a scalar through a single-item array.
      local array=hs.json.encode({expectedURL})
      assert(type(array)=='string','expected URL encoding unavailable')
      encoded=array:match('^%s*%[%s*(.-)%s*%]%s*$')
      assert(encoded and encoded:sub(1,1)=='"' and encoded:sub(-1)=='"','invalid expected URL encoding')
    end
    assert(type(encoded)=='string','expected URL encoding unavailable')
    assert(data.probeTemplate:find('__RTL_CONSOLE_NONCE__',1,true) and data.probeTemplate:find('__RTL_CONSOLE_EXPECTED_URL_JSON__',1,true),'invalid probe template')
    return (data.probeTemplate:gsub('__RTL_CONSOLE_NONCE__',function()return nonce end):gsub('__RTL_CONSOLE_EXPECTED_URL_JSON__',function()return encoded end))
  end
  local function payload(kind,nonce,documentId)
    nonceValue(nonce)
    assert(type(documentId)=='string' and #documentId==32 and documentId:match('^[a-f0-9]+$'),'invalid document ID')
    local template=data.payloads[kind]
    assert(type(template)=='string' and template:find('__RTL_CONSOLE_NONCE__',1,true) and template:find('__RTL_CONSOLE_DOCUMENT_ID__',1,true),'invalid payload template')
    return (template:gsub('__RTL_CONSOLE_NONCE__',function()return nonce end):gsub('__RTL_CONSOLE_DOCUMENT_ID__',function()return documentId end))
  end
  local driverConfig={probe=probe,payload=payload,timeout=config.timeout}
  local driver=config.driver
  if not driver then
    local driverModule=assert(loadfile(config.driverPath))()
    driver=driverModule.start(driverConfig,hs)
  end
  local adapter=config.adapter or M.nativeAdapter(hs)
  local controller=M.new(config,adapter,driver)
  local rawSnapshot,rawTick,rawStop=controller.snapshot,controller.tick,controller.stop
  local saved,writeFailures,writeFailed,nextWrite=nil,0,false,0
  local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~='table' then return a==b end
    for key,value in pairs(a)do if not same(value,b[key])then return false end end
    for key in pairs(b)do if a[key]==nil then return false end end
    return true
  end
  controller.snapshot=function()
    local result=rawSnapshot()
    result.statusWriteFailed=writeFailed;result.counts.statusWriteFailures=writeFailures
    return result
  end
  local function publish(force)
    local result=controller.snapshot()
    if not config.statusFile or same(result,saved) or not force and adapter.now()<nextWrite then return result end
    -- Write only the allowlisted snapshot, without window metadata.
    local output=controller.snapshot();output.statusWriteFailed=false
    local ok,written=pcall(hs.json.write,output,config.statusFile,true,true)
    if ok and written==true then saved=output;writeFailed=false;nextWrite=0
    else writeFailures=writeFailures+1;writeFailed=true;nextWrite=adapter.now()+5 end
    return controller.snapshot()
  end
  controller.tick=function()rawTick();return publish(false)end
  local timer,stopping,timerRunning=nil,false,true
  local function stopTimer()if timer and timerRunning then timer:stop();timerRunning=false end end
  local ok,result=pcall(hs.timer.doEvery,config.tickSeconds or 0.5,function()
    local status=controller.tick()
    if stopping and not status.cleanupPending then stopTimer() end
  end)
  timer=ok and result or nil
  if not ok or not timer then controller.stop();error('coordinator timer unavailable')end
  controller.stop=function()
    stopping=true;rawStop()
    local status=publish(true)
    if not status.cleanupPending then stopTimer()end
    return status
  end
  publish(true)
  return controller
end

M.sourceKind=sourceKind
return M
