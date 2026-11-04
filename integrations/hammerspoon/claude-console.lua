-- Run an explicit request or a bounded scan in this window internal console.
-- Navigation coverage depends on the external watcher and live validation.
local M = {}
local bundle = 'com.anthropic.claudefordesktop'
local path = '/Applications/Claude.app'
local kinds = {shell=true,chat=true,artifact=true,['artifact-content']=true,document=true}
local function kindCounts(value)
  local out={}
  for kind in pairs(kinds)do
    local count=type(value)=='table' and value[kind] or 0
    out[kind]=type(count)=='number' and count==count and count>=0 and count<=10000 and count%1==0 and count or 0
  end
  return out
end
local function eligible(info)
  return info and info.bundle == bundle and info.path == path and type(info.pid) == 'number'
end
local function isTools(window)
  return window and type(window.title)=='string' and window.title:match('^Developer Tools %- ') ~= nil
end
local function documentId(value)return type(value)=='string' and #value==32 and value:match('^[a-f0-9]+$')~=nil end
local function topContext(option)return type(option.title)=='string' and option.title:lower():match('^top')~=nil end
local function contextMatches(actual,base,scan,expansion)
  if actual==base then return true end
  if not scan or type(actual)~='string' then return false end
  if actual:sub(1,#base+2)==base..' (' and actual:sub(-1)==')' then
    local suffix=actual:sub(#base+3,-2)
    if suffix~='' and not suffix:find('[\r\n()]') then return true end
  end
  if expansion and expansion.unique then
    local full=actual:match('^(.-) %([^()\r\n]+%)$') or actual
    return not full:find('[\r\n]') and #full>#expansion.prefix and full:sub(1,#expansion.prefix)==expansion.prefix
      and full:sub(-3)~='\226\128\166'
  end
  return false
end
local function jsonString(value)
  if value==nil then return 'null' end
  return '"'..value:gsub('[%z\1-\31\\"]',function(char)
    if char=='"' then return '\\"' elseif char=='\\' then return '\\\\' end
    return string.format('\\u%04x',string.byte(char))
  end):gsub('\226\128\168','\\u2028'):gsub('\226\128\169','\\u2029')..'"'
end
local function ordinaryContext(option)
  if option.frame==false then return false end
  local title=(type(option.title)=='string' and option.title:lower() or '')..' '..(option.details or ''):lower()
  if title:find('isolated',1,true) or title:find('metrics',1,true) or title:find('worker',1,true)
    or title:find('extension',1,true) or title:find('devtools',1,true) or title:find('⚙',1,true) then return false end
  if option.frame==true then return true end
  title=(option.title or ''):lower()
  return topContext(option) or title=='about:srcdoc' or title:match('^https?://')~=nil
    or title:match('^[a-z0-9-]+%.frame%.claudeusercontent%.com')~=nil
    or title=='claude.ai' or title:match('^file:///Applications/Claude%.app/')~=nil
end

-- The adapter retains AX metadata. Snapshots contain no titles, URLs, or text.
function M.new(config, adapter)
  local transaction, last = nil, {experimental=true,phase='idle',ok=false,applied=0,skipped=0,contexts=0,cleanupRequired=false,
    appliedKinds=kindCounts(),probedKinds=kindCounts()}
  local timeout = config.timeout or 20
  assert(type(timeout)=='number' and timeout>0 and timeout<=60, 'invalid timeout')
  local function snapshot()
    local out={};for key,value in pairs(last) do
      out[key]=(key=='appliedKinds' or key=='probedKinds') and kindCounts(value) or value
    end;return out
  end
  local function titleDiagnostic(s,candidate)
    local actual=type(candidate.title)=='string' and candidate.title or ''
    local expected=s.request.toolsTitle
    local first=0
    for index=1,math.min(#actual,#expected)do if actual:byte(index)~=expected:byte(index) then first=index;break end end
    if first==0 and #actual~=#expected then first=math.min(#actual,#expected)+1 end
    s.titleDiagnostic={toolsExpectedLength=#expected,toolsActualLength=#actual,toolsSamePID=candidate.pid==s.pid,
      toolsTitleMatch=actual==expected,toolsFirstDiff=first}
    for key,value in pairs(s.titleDiagnostic)do last[key]=value end
  end
  local function pasteDiagnostic(s,entered,focused)
    local actual=type(entered)=='string' and entered or ''
    local expected=s.payload
    local limit=math.min(#actual,#expected,1048576)
    local first=0
    for index=1,limit do if actual:byte(index)~=expected:byte(index) then first=index;break end end
    if first==0 and limit==math.min(#actual,#expected) and #actual~=#expected then first=limit+1 end
    local transformed=#actual<=8388608 and #expected<=8388608
    local equalSpaces=false
    if transformed then
      local function stripEnds(value)return value:gsub('[ \t]+(\r?\n)','%1'):gsub('[ \t]+$','')end
      equalSpaces=stripEnds(actual)==stripEnds(expected)
    end
    s.pasteDiagnostic={pasteEnteredType=type(entered),pasteEnteredLength=#actual,pasteExpectedLength=#expected,
      pastePromptFocused=focused==true,pasteFirstDiff=first,pasteComparedBytes=limit,
      pasteComparisonTruncated=first==0 and limit<math.min(#actual,#expected),pasteTransformsCompared=transformed,
      pasteEqualAfterTrailingLF=transformed and actual==expected..'\n',pasteEqualAfterLineEndSpaces=equalSpaces}
  end
  local function contextDiagnostic(s,actual)
    local expected=s.request.contextLabel
    local value=type(actual)=='string' and actual or ''
    local first=0
    for index=1,math.min(#expected,#value,65536)do if expected:byte(index)~=value:byte(index) then first=index;break end end
    if first==0 and #expected~=#value then first=math.min(#expected,#value)+1 end
    s.contextDiagnostic={contextExpectedLength=#expected,contextActualLength=#value,
      contextExpectedEndsEllipsis=expected:sub(-3)=='\226\128\166',contextFirstDiff=first}
    for key,item in pairs(s.contextDiagnostic)do last[key]=item end
  end
  local function menuDiagnostic(s)
    if not adapter.menuDiagnostics then return end
    local ok,value=pcall(adapter.menuDiagnostics,s.tools)
    if not ok or type(value)~='table' then return end
    s.menuDiagnostic={}
    for _,key in ipairs({'menuButtonPresent','menuButtonFocused','menuActiveIsButton','menuPromptIsActive','menuPromptFocused'})do
      if type(value[key])=='boolean' then s.menuDiagnostic[key]=value[key] end
    end
    for _,key in ipairs({'menuButtonFocusedType','menuOpeningStage'})do
      if type(value[key])=='string' and value[key]:match('^[%w_-]+$') and #value[key]<=40 then s.menuDiagnostic[key]=value[key] end
    end
    for key,item in pairs(s.menuDiagnostic)do last[key]=item end
  end
  local function newNonce(used)
    local value=adapter.nonce()
    if type(value)~='string' or not value:match('^[%w_-]+$') or #value<16 or #value>80 or (used and used[value]) then return nil end
    if used then used[value]=true end
    return value
  end
  local function applySource(kind,nonce,id)
    local source
    if config.payload then source=config.payload(kind,nonce,id)
    else
      source=config.payloads and config.payloads[kind]
      if type(source)~='string' or not source:find('__RTL_CONSOLE_NONCE__',1,true)
        or not source:find('__RTL_CONSOLE_DOCUMENT_ID__',1,true) then return nil end
      source=source:gsub('__RTL_CONSOLE_NONCE__',function()return nonce end):gsub('__RTL_CONSOLE_DOCUMENT_ID__',function()return id end)
    end
    if type(source)~='string' or source=='' or not source:find(nonce,1,true) or not source:find(id,1,true) then return nil end
    return '(async()=>{const record=window.__claudePersianConsoleDocumentV1;if(!record||record.document!==document||record.id!=="'..id..'")'
      ..'{const result={marker:"RTL_CONSOLE_RESULT",nonce:"'..nonce..'",kind:"'..kind..'",ok:false,reason:"document-mismatch"};console.log(JSON.stringify(result));return result;}'
      ..'return await ('..source..');})()'
  end
  local function probeSource(nonce,expectedURL)
    local source
    if config.probe then source=config.probe(nonce,expectedURL)
    else
      source=config.probeTemplate
      if type(source)~='string' or not source:find('__RTL_CONSOLE_NONCE__',1,true)
        or not source:find('__RTL_CONSOLE_EXPECTED_URL_JSON__',1,true) then return nil end
      source=source:gsub('__RTL_CONSOLE_NONCE__',function()return nonce end)
        :gsub('__RTL_CONSOLE_EXPECTED_URL_JSON__',function()return jsonString(expectedURL)end)
    end
    if type(source)~='string' or source=='' or not source:find(nonce,1,true) then return nil end
    if not expectedURL then return source end
    return '(async()=>{if(location.href!=='..jsonString(expectedURL)..'){const result={marker:"RTL_CONSOLE_PROBE",nonce:"'..nonce..'",kind:null,ok:false,reason:"source-mismatch"};console.log(JSON.stringify(result));return result;}return await ('..source..');})()'
  end
  local function command(s,kind,id,expectedURL)
    local nonce=newNonce(s.usedNonces)
    if not nonce then return false,'invalid-or-reused-nonce' end
    local ok,source=pcall(function()if kind then return applySource(kind,nonce,id) else return probeSource(nonce,expectedURL)end end)
    if not ok or not source then return false,kind and 'payload-unavailable' or 'probe-unavailable' end
    s.nonce=nonce;s.payload=source;s.command=kind and 'apply' or 'probe';s.expectedKind=kind
    s.copyAttempted=false;s.copyVerified=false;s.copyOriginalVersion=nil;s.copyDeadline=nil
    return true
  end
  local function publish(s,reason,applied,restored,closed)
    if adapter.endTracking then pcall(adapter.endTracking) end
    last={experimental=true,phase=reason or 'complete',kind=s.request.kind,pid=s.pid,
      ok=applied==true and restored and closed,clipboardRestored=restored,toolsClosed=closed,
      cleanupRequired=s.openRequested==true and not closed,toolsUnverified=s.openRequested==true and s.proven~=true}
    last.applied=s.applied or 0;last.skipped=s.skipped or 0;last.contexts=s.contextCount or 0
    last.appliedKinds=kindCounts(s.appliedKinds);last.probedKinds=kindCounts(s.probedKinds)
    last.sourceWindowId=s.request.windowId;last.sourcePID=s.pid
    last.copyVerifications=s.copyVerifications or 0
    for key,value in pairs(s.titleDiagnostic or {})do last[key]=value end
    for key,value in pairs(s.pasteDiagnostic or {})do last[key]=value end
    for key,value in pairs(s.menuDiagnostic or {})do last[key]=value end
    for key,value in pairs(s.contextDiagnostic or {})do last[key]=value end
    if reason or not closed then for key,value in pairs(s.guardDiagnostic or {})do last[key]=value end end
    if not restored then last.reason='clipboard-changed-or-restore-failed'
    elseif reason then last.reason=reason
    elseif not closed then last.reason='tools-cleanup-failed' end
    transaction=nil
    return snapshot()
  end
  local function finish(reason, applied)
    local s=transaction
    if not s then return snapshot() end
    if s.phase=='cleanup' then return snapshot() end
    local restored, closed=true,not s.openRequested
    if s.clipboardVersion then
      local ok,value=pcall(adapter.restoreClipboard,s.clipboard,s.clipboardVersion)
      restored=ok and value==true
    end
    if s.tools and s.proven then
      local ok,value=pcall(adapter.closeTools,s.tools,s.pid)
      if ok and value=='pending' and adapter.toolsClosed then
        s.phase='cleanup';s.cleanup={reason=reason,applied=applied,restored=restored,deadline=adapter.now()+2}
        last.phase='cleanup';last.clipboardRestored=restored;last.toolsClosed=false
        last.cleanupRequired=true;last.toolsUnverified=false
        return snapshot()
      end
      closed=ok and value==true
    end
    return publish(s,reason,applied,restored,closed)
  end
  local function guard(s)
    local info=adapter.identity()
    local tracking=adapter.isTracking and adapter.isTracking()==true or false
    local toolId=s.tools and s.tools.id or s.pendingTools and s.pendingTools.id
    s.guardDiagnostic={failurePhase=s.phase,focusIsSource=info and info.focusedWindow==s.request.windowId or false,
      focusIsTools=info and toolId~=nil and info.focusedWindow==toolId or false,
      frontmost=info and info.frontmost==true or false,focusedWindowPresent=info and info.focusedWindow~=nil or false,tracking=tracking}
    if not eligible(info) or info.pid~=s.pid then return 'process-changed' end
    if not info.frontmost then return 'focus-changed' end
    if adapter.activity()~=s.activity then return 'user-activity' end
    if not tracking then return 'input-monitor-unavailable' end
    local expected=s.tools and s.tools.id or s.pendingTools and s.pendingTools.id or s.request.windowId
    local pendingFocus=false
    if info.focusedWindow~=expected and not (s.pendingTools and info.focusedWindow==s.request.windowId) then
      if s.tools and not s.proven and s.phase=='open-contexts' and info.focusedWindow==s.request.windowId
        and s.focusReadyUntil and adapter.now()<=s.focusReadyUntil then pendingFocus=true
      else return 'focus-changed' end
    end
    if s.tools then
      local found=false
      for _,window in ipairs(adapter.windows()) do
        if window.id==s.tools.id and window.title==s.tools.title and window.pid==s.pid and isTools(window) then found=true end
      end
      if not found then return 'tools-changed' end
    end
    if adapter.now()>s.deadline then return 'timeout' end
    return nil,pendingFocus
  end
  local function copyInputGuard(s)
    if adapter.contextLabel(s.tools)~=s.request.contextLabel then return 'context-changed' end
    if not adapter.promptFocused(s.tools) then return 'prompt-focus-changed' end
    if not adapter.clipboardVersion or adapter.clipboardVersion()~=s.clipboardVersion then return 'clipboard-changed' end
  end
  local function begin(request)
    if transaction then return false,'busy' end
    if type(request)~='table' or type(request.windowId)~='number'
      or request.windowId<1 or request.windowId%1~=0
      or type(request.toolsTitle)~='string' or not isTools({title=request.toolsTitle}) then return false,'invalid-request' end
    if request.scan==true then
      if type(request.sourceURL)~='string' or request.sourceURL=='' or #request.sourceURL>8192
        or request.sourceURL:find('[%z\1-\31\127]') or request.sourceURL:find('\226\128\168',1,true)
        or request.sourceURL:find('\226\128\169',1,true) then return false,'invalid-source' end
    elseif not kinds[request.kind] or type(request.context)~='string' or request.context==''
      or type(request.contextLabel)~='string' or request.contextLabel=='' or not documentId(request.documentId) then return false,'invalid-request' end
    local info=adapter.identity()
    if not eligible(info) or not info.frontmost or info.focusedWindow~=request.windowId then return false,'target-not-focused' end
    local seen, target={},false
    for _,window in ipairs(adapter.windows()) do
      if isTools(window) then return false,'existing-tools-left-untouched' end
      seen[window.id]=true
      if window.id==request.windowId then target=true end
    end
    if not target then return false,'target-missing' end
    -- Check before changing a menu, focus, or the clipboard.
    local clipboard,reason=adapter.captureClipboard()
    if not clipboard then return false,reason or 'clipboard-unavailable' end
    local scan=request.scan==true
    local s={request={windowId=request.windowId,kind=request.kind,context=scan and 'top' or request.context,
      contextLabel=scan and 'JavaScript context: top' or request.contextLabel,
      documentId=request.documentId,toolsTitle=request.toolsTitle,sourceURL=request.sourceURL,scan=scan},
      pid=info.pid,seen=seen,clipboard=clipboard,usedNonces={},seenDocuments={},sourcePending=scan,
      applied=0,skipped=0,copyVerifications=0,contextCount=scan and 0 or 1,appliedKinds=kindCounts(),probedKinds=kindCounts(),
      phase='open',deadline=adapter.now()+timeout,activity=adapter.activity()}
    local firstKind;if not scan then firstKind=request.kind end
    local prepared,problem=command(s,firstKind,request.documentId,scan and request.sourceURL or nil)
    if not prepared then return false,problem end
    transaction=s
    if not adapter.beginTracking or adapter.beginTracking()~=true then finish('input-monitor-unavailable');return false,'input-monitor-unavailable' end
    last={experimental=true,phase='open',kind=request.kind,pid=info.pid,ok=false,applied=0,skipped=0,contexts=0,cleanupRequired=false,
      appliedKinds=kindCounts(),probedKinds=kindCounts(),sourceWindowId=request.windowId,sourcePID=info.pid}
    return true
  end
  local function nextContext(s)
    if not s.sourceVerified then return finish('source-unverified') end
    s.menuAttemptCount=0;s.menuAttemptTime=nil;s.contextExpansion=nil
    if not s.contextQueue then s.phase='scan-list';return end
    s.contextIndex=s.contextIndex+1
    local option=s.contextQueue[s.contextIndex]
    if not option then return finish(nil,true) end
    s.request.context=option.title;s.request.contextLabel=option.contextLabel or ('JavaScript context: '..option.title)
    s.request.contextOrdinal=option.index;s.request.contextKey=option.key
    local ok,problem=command(s,nil,nil,nil)
    if not ok then return finish(problem) end
    s.phase='open-contexts'
  end
  local function step()
    local s=transaction
    if not s then return snapshot() end
    if s.phase=='cleanup' then
      local pending=s.cleanup
      local ok,closed=pcall(adapter.toolsClosed,s.tools,s.pid)
      if ok and closed==true then return publish(s,pending.reason,pending.applied,pending.restored,true) end
      if not ok or adapter.now()>pending.deadline then return publish(s,pending.reason,pending.applied,pending.restored,false) end
      return snapshot()
    end
    if s.phase=='await-tools' then
      -- User input can create another window. Verify ownership before claiming it.
      if adapter.activity()~=s.activity then return finish('user-activity') end
      local candidates={}
      for _,window in ipairs(adapter.windows()) do
        -- A new window may have no title while its frontend initializes.
        -- It remains a candidate. Require an exact title and valid probe before code or close.
        if not s.seen[window.id] then candidates[#candidates+1]=window end
      end
      if #candidates>1 then return finish('ambiguous-tools') end
      if #candidates==1 then
        local candidate=candidates[1]
        titleDiagnostic(s,candidate)
        if candidate.pid~=s.pid then return finish('tools-process-mismatch') end
        if s.pendingTools and candidate.id~=s.pendingTools.id then return finish('tools-candidate-changed') end
        local focused=adapter.identity()
        if candidate.title==s.request.toolsTitle and focused and focused.focusedWindow==candidate.id then
          -- Do not claim this window for automatic close until a valid receipt arrives.
          s.tools={id=candidate.id,title=candidate.title,pid=candidate.pid};s.pendingTools=nil;s.phase='open-contexts';s.focusReadyUntil=adapter.now()+2
        elseif not s.pendingTools then s.pendingTools={id=candidate.id,pid=candidate.pid,since=adapter.now()} end
      end
      if s.pendingTools and adapter.now()-s.pendingTools.since>=2 then return finish('tools-title-mismatch') end
    end
    local reason,waitingFocus=guard(s)
    if reason then return finish(reason) end
    if waitingFocus then last.phase='waiting-for-tools-focus';return snapshot() end
    if s.phase=='open' then
      s.openRequested=true
      if adapter.openTools(s.request.windowId,s.pid)~=true then return finish('tools-open-failed') end
      s.phase='await-tools'
    elseif s.phase=='open-contexts' then
      local opened,problem=adapter.openContexts(s.tools);menuDiagnostic(s)
      if opened=='pending' then last.phase='waiting-for-contexts';return snapshot() end
      if opened~=true then return finish(problem=='context-button-open-timeout' and problem or 'contexts-open-failed') end
      s.menuAttemptCount=(s.menuAttemptCount or 0)+1;s.menuAttemptTime=adapter.now()
      s.phase='select-context'
    elseif s.phase=='select-context' then
      local options,problem=adapter.contexts(s.tools)
      if problem then return finish(problem) end
      if options then
        local matches={}
        for _,option in ipairs(options) do
          local nameMatches=option.title==s.request.context or (s.sourcePending and topContext(option))
          if nameMatches and ordinaryContext(option) and (not s.request.contextOrdinal or option.index==s.request.contextOrdinal)
            and (not s.request.contextKey or option.key==s.request.contextKey) then matches[#matches+1]=option end
        end
        if #matches~=1 then return finish('context-ambiguous-or-missing') end
        s.contextExpansion=nil
        if s.request.scan and matches[1].title:sub(-3)=='\226\128\166' then
          local prefix=matches[1].title:sub(1,-4)
          if prefix=='' then return finish('context-prefix-ambiguous') end
          for _,option in ipairs(options)do
            local same=option==matches[1] or option.index and matches[1].index and option.index==matches[1].index
            if not same and ordinaryContext(option) then
              local other=option.title
              local truncated=other:sub(-3)=='\226\128\166'
              if truncated then other=other:sub(1,-4) end
              if other:sub(1,#prefix)==prefix or truncated and prefix:sub(1,#other)==other then return finish('context-prefix-ambiguous') end
            end
          end
          s.contextExpansion={prefix='JavaScript context: '..prefix,unique=true}
        end
        if s.sourcePending then
          s.request.context=matches[1].title;s.request.contextLabel=matches[1].contextLabel or 'JavaScript context: top'
        end
        if adapter.selectContext(s.tools,matches[1])~=true then return finish('context-select-failed') end
        s.phase='await-context'
      elseif s.menuAttemptTime and adapter.now()-s.menuAttemptTime>=0.5 then
        if s.menuAttemptCount>=3 then return finish('contexts-menu-unavailable') end
        s.phase='open-contexts'
      end
    elseif s.phase=='await-context' then
      local actual=adapter.contextLabel(s.tools)
      contextDiagnostic(s,actual)
      if contextMatches(actual,s.request.contextLabel,s.request.scan,s.contextExpansion) then
        -- Accept display truncation only for initial selection. Pin the exact title from here.
        s.request.contextLabel=actual;s.contextExpansion=nil;s.phase='focus-prompt'
      end
    elseif s.phase=='scan-list' then
      local opened,problem=adapter.openContexts(s.tools);menuDiagnostic(s)
      if opened=='pending' then last.phase='waiting-for-contexts';return snapshot() end
      if opened~=true then return finish(problem=='context-button-open-timeout' and problem or 'contexts-open-failed') end
      s.menuAttemptCount=(s.menuAttemptCount or 0)+1;s.menuAttemptTime=adapter.now()
      s.phase='scan-contexts'
    elseif s.phase=='scan-contexts' then
      local options,problem=adapter.contexts(s.tools)
      if problem then return finish(problem) end
      if options then
        if #options>128 then return finish('too-many-contexts') end
        local queue,keys={},{}
        for index,option in ipairs(options) do
          local key=option.title
          if ordinaryContext(option) then
            if keys[key] then return finish('duplicate-context') end
            keys[key]=true
          end
          if not topContext(option) and ordinaryContext(option) then
            queue[#queue+1]={title=option.title,contextLabel=option.contextLabel,key=option.key,index=option.index or index}
          end
        end
        s.contextQueue=queue;s.contextIndex=0
        -- Close the menu before the next command, even when no frames remain.
        if adapter.dismissContexts and adapter.dismissContexts(s.tools)~=true then return finish('contexts-dismiss-failed') end
        local finished=nextContext(s);if finished then return finished end
      elseif s.menuAttemptTime and adapter.now()-s.menuAttemptTime>=0.5 then
        if s.menuAttemptCount>=3 then return finish('contexts-menu-unavailable') end
        s.phase='scan-list'
      end
    elseif s.phase=='focus-prompt' then
      local value=adapter.promptValue(s.tools)
      if value==nil then last.phase='waiting-for-prompt';return snapshot() end
      if value~='' then return finish('prompt-not-empty') end
      local focused=adapter.focusPrompt(s.tools)
      if focused=='pending' then last.phase='waiting-for-prompt';return snapshot() end
      if focused~=true then return finish('prompt-focus-failed') end
      s.phase='paste'
    elseif s.phase=='paste' then
      if adapter.contextLabel(s.tools)~=s.request.contextLabel then return finish('context-changed') end
      if adapter.promptValue(s.tools)~='' or not adapter.promptFocused(s.tools) then return finish('prompt-focus-changed') end
      -- Do not overwrite a clipboard that changed after capture.
      if s.clipboardVersion then
        if adapter.clipboardVersion()~=s.clipboardVersion then return finish('clipboard-changed') end
      elseif adapter.clipboardUnchanged(s.clipboard)~=true then return finish('clipboard-changed') end
      local version,written=adapter.writeClipboard(s.payload)
      s.clipboardVersion=version
      if not version or written==false then return finish('clipboard-write-failed') end
      if adapter.isTracking()~=true then return finish('input-monitor-unavailable') end
      if not adapter.promptFocused(s.tools) then return finish('prompt-focus-changed') end
      if adapter.paste(s.tools,s.clipboardVersion)~=true then return finish('paste-failed') end
      s.phase='execute'
    elseif s.phase=='execute' then
      if adapter.contextLabel(s.tools)~=s.request.contextLabel then return finish('context-changed') end
      local focused=adapter.promptFocused(s.tools)
      local entered=adapter.promptValue(s.tools)
      if not focused then pasteDiagnostic(s,entered,focused);return finish('paste-not-verified') end
      if entered~=s.payload then
        -- Pasting a large string can span several ticks. Never send Return early.
        if type(entered)=='string' and #entered<#s.payload and s.payload:sub(1,#entered)==entered then return snapshot() end
        pasteDiagnostic(s,entered,focused)
        local supported=adapter.selectSourceForVerification and adapter.copySelectedSource and adapter.pollCopiedSource
          and adapter.collapseSourceSelection and adapter.sourceSelectionEmpty
        if not s.copyAttempted and supported then s.copyAttempted=true;s.phase='copy-select'
        else return finish('paste-not-verified') end
        last.phase=s.phase;return snapshot()
      end
      if not adapter.clipboardVersion or adapter.clipboardVersion()~=s.clipboardVersion then return finish('clipboard-changed') end
      if adapter.isTracking()~=true then return finish('input-monitor-unavailable') end
      if adapter.execute(s.tools,s.clipboardVersion)~=true then return finish('execute-failed') end
      s.phase='await-result'
    elseif s.phase=='copy-select' then
      local problem=copyInputGuard(s);if problem then return finish(problem) end
      if adapter.selectSourceForVerification(s.tools,s.clipboardVersion,s.request.contextLabel,s.activity)~=true then return finish('copy-select-failed') end
      s.copyOriginalVersion=s.clipboardVersion;s.phase='copy-copy'
    elseif s.phase=='copy-copy' then
      local problem=copyInputGuard(s);if problem then return finish(problem) end
      if adapter.copySelectedSource(s.tools,s.clipboardVersion,s.request.contextLabel,s.activity)~=true then return finish('copy-request-failed') end
      s.copyDeadline=adapter.now()+2;s.phase='copy-wait'
    elseif s.phase=='copy-wait' then
      if adapter.contextLabel(s.tools)~=s.request.contextLabel then return finish('context-changed') end
      if not adapter.promptFocused(s.tools) then return finish('prompt-focus-changed') end
      local receipt=adapter.pollCopiedSource(s.tools,s.copyOriginalVersion,s.request.contextLabel,s.activity)
      if receipt then
        if receipt.conflict or receipt.version~=s.copyOriginalVersion+1 then return finish('clipboard-copy-conflict') end
        if receipt.contents~=nil then
          if type(receipt.contents)~='string' or receipt.contents~=s.payload then return finish('copied-source-mismatch') end
          -- Only a complete copy of the same source proves ownership of the new clipboard version.
          -- Never replace unknown new clipboard content with the saved clipboard.
          s.clipboardVersion=receipt.version
          s.copyVerified=true;s.copyVerifications=s.copyVerifications+1;s.phase='copy-collapse'
        elseif adapter.now()>s.copyDeadline then return finish('copied-source-unavailable') end
      elseif adapter.now()>s.copyDeadline then return finish('copy-timeout') end
    elseif s.phase=='copy-collapse' then
      local problem=copyInputGuard(s);if problem then return finish(problem) end
      if not s.copyVerified or adapter.collapseSourceSelection(s.tools,s.clipboardVersion,s.request.contextLabel,s.activity)~=true then return finish('copy-collapse-failed') end
      s.selectionDeadline=adapter.now()+0.5;s.phase='copy-confirm'
    elseif s.phase=='copy-confirm' then
      local problem=copyInputGuard(s);if problem then return finish(problem) end
      if adapter.sourceSelectionEmpty(s.tools)==true then s.phase='execute-copied'
      elseif adapter.now()>s.selectionDeadline then return finish('copy-collapse-unverified') end
    elseif s.phase=='execute-copied' then
      local problem=copyInputGuard(s);if problem then return finish(problem) end
      if not s.copyVerified or adapter.sourceSelectionEmpty(s.tools)~=true then return finish('copy-collapse-unverified') end
      if adapter.execute(s.tools,s.clipboardVersion)~=true then return finish('execute-failed') end
      s.phase='await-result'
    elseif s.phase=='await-result' then
      local marker=s.command=='probe' and 'RTL_CONSOLE_PROBE' or 'RTL_CONSOLE_RESULT'
      local result=adapter.result(s.tools,s.nonce,marker)
      if result then
        if result.nonce~=s.nonce or result.marker~=marker then return finish('result-mismatch') end
        if s.command=='probe' then
          if result.ok~=true then
            if s.sourcePending then return finish('source-probe-failed') end
            if result.reason~='context-mismatch' then return finish('context-probe-failed') end
            s.contextCount=s.contextCount+1;s.skipped=s.skipped+1
            local finished=nextContext(s);if finished then return finished end
          else
            if not kinds[result.kind] or not documentId(result.documentId) or type(result.healthy)~='boolean' then return finish('probe-result-invalid') end
            s.probedKinds[result.kind]=s.probedKinds[result.kind]+1
            if s.sourcePending then s.proven=true;s.sourceVerified=true;s.sourcePending=false end
            s.contextCount=s.contextCount+1
            if s.seenDocuments[result.documentId] or result.healthy then
              s.seenDocuments[result.documentId]=true;s.skipped=s.skipped+1
              local finished=nextContext(s);if finished then return finished end
            else
              if not s.sourceVerified then return finish('source-unverified') end
              s.seenDocuments[result.documentId]=true
              local ok,problem=command(s,result.kind,result.documentId,nil)
              if not ok then return finish(problem) end
              s.phase='focus-prompt'
            end
          end
        else
          if result.kind~=s.expectedKind then return finish('result-mismatch') end
          if result.ok~=true then return finish('application-failed') end
          s.proven=true;s.applied=s.applied+1;s.appliedKinds[s.expectedKind]=s.appliedKinds[s.expectedKind]+1
          if not s.request.scan then return finish(nil,true) end
          local finished=nextContext(s);if finished then return finished end
        end
      end
    end
    last.phase=s.phase;last.applied=s.applied;last.skipped=s.skipped;last.contexts=s.contextCount;last.copyVerifications=s.copyVerifications
    last.appliedKinds=kindCounts(s.appliedKinds);last.probedKinds=kindCounts(s.probedKinds)
    return snapshot()
  end
  return {begin=function(request)
      local ok,value,reason=pcall(begin,request)
      if not ok then finish('adapter-failed');return false,'adapter-failed' end
      return value,reason
    end,snapshot=snapshot,cancel=function()return finish('cancelled')end,
    tick=function()
      local ok,value=pcall(step)
      if not ok then
        if transaction and transaction.phase=='cleanup' then
          local s=transaction;local pending=s.cleanup or {}
          return publish(s,'adapter-failed',false,pending.restored==true,false)
        end
        return finish('adapter-failed')
      end
      return value
    end}
end

-- The native adapter connects Hammerspoon APIs to the state machine.
function M.nativeAdapter(hs)
  local expectedPID, activity, tap, opening = nil,0,nil,nil
  local function app()
    local value
    if expectedPID then value=hs.application.applicationForPID(expectedPID) else value=hs.application.get(bundle) end
    if value and value:bundleID()==bundle and value:path()==path then return value end
  end
  local foreground
  local function attribute(element,name)
    if not element then return nil end
    local ok,value=pcall(function()return element:attributeValue(name)end)
    if ok then return value end
  end
  local function nativeWindows()
    local value=app();local out,seen,axById={},{},{}
    if not value then return out,axById end
    local function add(candidate,element)
      if not candidate then return end
      local ok,id=pcall(function()if candidate:application():pid()==value:pid() then return candidate:id() end end)
      if not ok or type(id)~='number' then return end
      if not seen[id] then seen[id]=true;out[#out+1]=candidate end
      if element then axById[id]=element end
    end
    local ok,windows=pcall(function()return value:allWindows()end)
    if ok then for _,candidate in ipairs(windows or {}) do add(candidate) end end
    local root=hs.axuielement.applicationElement(value)
    local function fromAX(element)
      if element then local worked,candidate=pcall(function()return element:asHSWindow()end);if worked then add(candidate,element) end end
    end
    for _,element in ipairs(attribute(root,'AXWindows') or {}) do fromAX(element) end
    fromAX(attribute(root,'AXFocusedWindow'))
    return out,axById
  end
  foreground=function(target)
    local value=app();if not value or not value:isFrontmost() then return nil end
    local ok,focused=pcall(hs.window.focusedWindow)
    if not ok or not focused then
      local element=attribute(hs.axuielement.applicationElement(value),'AXFocusedWindow')
      if element then local worked,candidate=pcall(function()return element:asHSWindow()end);if worked then focused=candidate end end
    end
    if focused and focused:application():pid()==value:pid() and (not target or focused:id()==target.id) then return focused end
  end
  local function walk(root,predicate,limit)
    local stack,found,count={root},{},0
    while #stack>0 and count<(limit or 4000) do
      local element=table.remove(stack);count=count+1
      if predicate(element) then found[#found+1]=element end
      local children=attribute(element,'AXChildren') or {}
      for i=#children,1,-1 do stack[#stack+1]=children[i] end
    end
    return found
  end
  local function window(target)
    local value=app();if not value then return nil end
    for _,candidate in ipairs(nativeWindows()) do
      if candidate:id()==target.id and candidate:title()==target.title and candidate:application():pid()==target.pid
        and isTools({title=candidate:title()}) then return candidate end
    end
  end
  local function axWindow(target)
    local value=window(target);if not value then return nil end
    local _,elements=nativeWindows()
    if elements[target.id] then return elements[target.id] end
    return hs.axuielement.windowElement(value)
  end
  local function label(element)
    for _,name in ipairs({'AXTitle','AXDescription','AXValue'}) do
      local value=attribute(element,name)
      if type(value)=='string' and value~='' then return value end
    end
  end
  local function prompt(target)
    local root=axWindow(target);if not root then return nil end
    local found=walk(root,function(e)return attribute(e,'AXRole')=='AXTextArea' and attribute(e,'AXDescription')=='Console prompt'end)
    return #found==1 and found[1] or nil
  end
  local function contextButton(target)
    local root=axWindow(target);if not root then return nil end
    local found=walk(root,function(e)local text=label(e);return attribute(e,'AXRole')=='AXButton' and type(text)=='string' and text:match('^JavaScript context: ')~=nil end)
    return #found==1 and found[1] or nil
  end
  local adapter={}
  function adapter.now()return hs.timer.secondsSinceEpoch()end
  function adapter.nonce()return (hs.host.uuid():gsub('-',''))end
  function adapter.activity()return activity end
  function adapter.isTracking()return tap~=nil and tap:isEnabled()==true end
  function adapter.identity()
    local value=app();if not value then return nil end
    local focused=foreground()
    return {pid=value:pid(),bundle=value:bundleID(),path=value:path(),frontmost=value:isFrontmost(),focusedWindow=focused and focused:id()}
  end
  function adapter.windows()
    local out={};local value=app();if not value then return out end
    for _,item in ipairs(nativeWindows()) do out[#out+1]={id=item:id(),title=item:title(),pid=item:application():pid()} end
    return out
  end
  function adapter.captureClipboard()
    local count=hs.pasteboard.changeCount()
    local items=hs.pasteboard.allContentTypes()
    if type(items)~='table' or #items>1 then return nil,'clipboard-multiple-items-or-unavailable' end
    local data=hs.pasteboard.readAllData()
    if hs.pasteboard.changeCount()~=count then return nil,'clipboard-changed' end
    if #items==1 and type(data)~='table' then return nil,'clipboard-unavailable' end
    if #items==1 then
      if type(items[1])~='table' then return nil,'clipboard-unavailable' end
      for _,uti in ipairs(items[1]) do if data[uti]==nil then return nil,'clipboard-format-unavailable' end end
    end
    return {version=count,data=data,empty=#items==0}
  end
  function adapter.clipboardUnchanged(saved)return hs.pasteboard.changeCount()==saved.version end
  function adapter.clipboardVersion()return hs.pasteboard.changeCount()end
  function adapter.writeClipboard(source)
    local ok,result=pcall(hs.pasteboard.setContents,source)
    return hs.pasteboard.changeCount(),ok and result==true
  end
  function adapter.restoreClipboard(saved,version)
    if hs.pasteboard.changeCount()~=version then return false end
    if saved.empty then
      hs.pasteboard.clearContents()
      local items=hs.pasteboard.allContentTypes()
      return type(items)=='table' and #items==0
    end
    if hs.pasteboard.writeAllData(saved.data)~=true then return false end
    local restored=hs.pasteboard.readAllData()
    if type(restored)~='table' then return false end
    for uti,data in pairs(saved.data) do if restored[uti]~=data then return false end end
    return true
  end
  function adapter.beginTracking()
    local value=app();expectedPID=value and value:pid() or nil
    local types=hs.eventtap.event.types
    assert(type(hs.processInfo.processID)=='number','event source PID required')
    tap=hs.eventtap.new({types.keyDown,types.flagsChanged,types.mouseMoved,types.leftMouseDown,types.rightMouseDown,types.otherMouseDown,types.scrollWheel},function(event)
      local source=event:getProperty(hs.eventtap.event.properties.eventSourceUnixProcessID)
      if source~=hs.processInfo.processID then activity=activity+1 end
      return false
    end):start()
    return tap and tap:isEnabled()==true
  end
  function adapter.endTracking()if tap then tap:stop();tap=nil end;expectedPID=nil;opening=nil end
  function adapter.openTools(id,pid)
    local value=app();local focused=foreground({id=id})
    if not value or value:pid()~=pid or not focused or focused:id()~=id or not value:isFrontmost() then return false end
    return value:selectMenuItem({'Developer','Show Dev Tools'})==true
  end
  function adapter.openContexts(target)
    if not foreground(target) or not adapter.isTracking() then opening=nil;return false end
    if opening and (opening.id~=target.id or opening.pid~=target.pid or opening.title~=target.title) then
      opening=nil;return false,'context-button-target-changed'
    end
    if opening and adapter.now()>=opening.deadline then return false,'context-button-open-timeout' end
    local button=contextButton(target)
    if not button then return 'pending' end
    local options=adapter.contexts(target)
    if type(options)=='table' and #options>0 then opening=nil;return true end
    if not opening then
      local result=button:performAction('AXPress')
      if result==nil or result==false then return false end
      opening={id=target.id,pid=target.pid,title=target.title,stage='after-press',deadline=adapter.now()+2}
      return 'pending'
    end
    if opening.stage=='after-press' then
      button:setAttributeValue('AXFocused',true);opening.stage='focus-pending';return 'pending'
    end
    if opening.stage~='focus-pending' then return 'pending' end
    local value=app();local active=value and attribute(hs.axuielement.applicationElement(value),'AXFocusedUIElement')
    local input=prompt(target)
    if not foreground(target) or not adapter.isTracking() then return false end
    if active~=button or attribute(button,'AXFocused')~=true or input and attribute(input,'AXFocused')==true then return 'pending' end
    -- Send Return only to the verified button, never the Console prompt.
    hs.eventtap.keyStroke({},'return',0,value)
    opening.stage='return-posted';return 'pending'
  end
  function adapter.menuDiagnostics(target)
    local button=contextButton(target);local value=app()
    local active=value and attribute(hs.axuielement.applicationElement(value),'AXFocusedUIElement')
    local input=prompt(target);local focused=button and attribute(button,'AXFocused')
    return {menuButtonPresent=button~=nil,menuButtonFocusedType=type(focused),menuButtonFocused=focused==true,
      menuActiveIsButton=button~=nil and active==button,menuPromptIsActive=input~=nil and active==input,
      menuPromptFocused=input~=nil and attribute(input,'AXFocused')==true,
      menuOpeningStage=opening and opening.stage or 'none'}
  end
  function adapter.contexts(target)
    local root=axWindow(target);if not root then return nil end
    local menus=walk(root,function(e)return attribute(e,'AXRole')=='AXMenu' and attribute(e,'AXVisible')~=false end)
    if #menus>1 then return nil,'context-menu-ambiguous' end
    if #menus==0 then return nil end
    local found=attribute(menus[1],'AXChildren') or {}
    local out,seen={},{ }
    for _,element in ipairs(found) do
      local role=attribute(element,'AXRole')
      if role~='AXSeparator' and role~='AXStaticText' then
        local texts={}
        for _,text in ipairs(walk(element,function(e)return attribute(e,'AXRole')=='AXStaticText'end,400)) do
          local value=attribute(text,'AXValue') or label(text)
          if type(value)=='string' and value~='' then texts[#texts+1]=value end
        end
        local title=texts[1] or label(element)
        if type(title)=='string' and title~='' then
          local detail={};for i=2,#texts do detail[#detail+1]=texts[i] end
          local option={title=title,details=table.concat(detail,' '),element=element,index=#out+1,
            contextLabel=topContext({title=title}) and 'JavaScript context: top' or ('JavaScript context: '..title)}
          option.key=title..'\0'..option.details
          option.frame=title=='top' or title=='about:srcdoc' or option.details:match('claude%.ai')~=nil
            or option.details:match('frame%.claudeusercontent%.com')~=nil or ordinaryContext(option)
          if not ordinaryContext(option) then option.frame=false end
          if ordinaryContext(option) then
            if seen[option.title] then return nil,'duplicate-context' end
            seen[option.title]=true
          end
          out[#out+1]=option
        end
      end
    end
    return #out>0 and out or nil
  end
  function adapter.contextDiagnostics(target)
    local root=axWindow(target)
    local result={rootPresent=root~=nil,menuCount=0,childCount=0,rows={}}
    if not root then return result end
    local menus=walk(root,function(e)return attribute(e,'AXRole')=='AXMenu' and attribute(e,'AXVisible')~=false end)
    result.menuCount=#menus
    if #menus~=1 then return result end
    local children=attribute(menus[1],'AXChildren') or {};result.childCount=#children
    local allowed={AXGroup=true,AXMenuItem=true,AXStaticText=true,AXSeparator=true}
    for index,element in ipairs(children)do
      local texts=walk(element,function(e)return attribute(e,'AXRole')=='AXStaticText'end,400)
      local first=texts[1] and (attribute(texts[1],'AXValue') or label(texts[1])) or label(element)
      local text=type(first)=='string' and first or ''
      local role=attribute(element,'AXRole')
      result.rows[#result.rows+1]={ordinal=index,role=allowed[role] and role or 'other',staticTexts=#texts,
        firstType=type(first),firstLength=#text,firstEndsEllipsis=text:sub(-3)=='\226\128\166',topPrefix=text:lower():match('^top')~=nil,
        srcdocPrefix=text:match('^about:srcdoc')~=nil,combinedSrcdocIFrame=text:match('^about:srcdoc%s+IFrame$')~=nil,
        combinedFrameHost=text:match('%s[%w%-]+%.frame%.claudeusercontent%.com$')~=nil,
        combinedClaudeHost=text:match('%sclaude%.ai$')~=nil}
    end
    return result
  end
  function adapter.selectContext(target,option)
    if not foreground(target) then return false end
    local found=adapter.contexts(target);if not found then return false end
    local matches={};for index,candidate in ipairs(found) do
      if candidate.title==option.title and (not option.index or option.index==candidate.index)
        and (not option.key or option.key==candidate.key) then matches[#matches+1]=index end
    end
    if #matches~=1 then return false end
    -- AXPress only focuses some frontends. Select with the keyboard.
    local expectedActivity=activity
    local function key(name)
      if not foreground(target) or activity~=expectedActivity or not adapter.isTracking() then return false end
      hs.eventtap.keyStroke({},name,0,app());return true
    end
    if not key('home') then return false end
    for _=2,matches[1] do if not key('down') then return false end end
    return key('return')
  end
  function adapter.dismissContexts(target)
    if not foreground(target) or not adapter.isTracking() then return false end
    hs.eventtap.keyStroke({},'escape',0,app());return true
  end
  function adapter.contextLabel(target)local button=contextButton(target);return button and label(button)end
  function adapter.promptValue(target)
    local element=prompt(target);if not element then return nil end
    local value=attribute(element,'AXValue')
    if value=='\n' then
      -- In the tested DevTools, an empty prompt has one line group and a display LF.
      -- A user Enter creates two line groups/LFs. Never trim spaces or text.
      local children=attribute(element,'AXChildren')
      if type(children)=='table' and #children==1 and attribute(children[1],'AXRole')=='AXGroup' then
        local texts=walk(element,function(e)return attribute(e,'AXRole')=='AXStaticText'end,400)
        if #texts==0 then return '' end
      end
    end
    return value
  end
  function adapter.promptDiagnostics(target)
    local element=prompt(target);local value=element and attribute(element,'AXValue')
    local children=element and attribute(element,'AXChildren')
    local result={present=element~=nil,valueType=type(value),length=0,whitespaceOnly=false,exactLF=value=='\n',
      childrenKnown=type(children)=='table',childCount=type(children)=='table' and #children or 0,textChildren=0,nonemptyTextChildren=0}
    local childRole=type(children)=='table' and children[1] and attribute(children[1],'AXRole')
    local roles={AXGroup=true,AXStaticText=true,AXTextArea=true}
    result.firstChildRole=roles[childRole] and childRole or 'other'
    if type(value)=='string' then result.length=#value;result.whitespaceOnly=value:match('^%s*$')~=nil
    elseif type(value)=='table' then local count=0;for _ in pairs(value)do count=count+1 end;result.fields=count end
    if element then
      for _,child in ipairs(walk(element,function(e)return e~=element and attribute(e,'AXRole')=='AXStaticText'end,400))do
        result.textChildren=result.textChildren+1
        local text=attribute(child,'AXValue') or label(child)
        if type(text)=='string' and text~='' then result.nonemptyTextChildren=result.nonemptyTextChildren+1 end
      end
    end
    return result
  end
  function adapter.promptReconstructionDiagnostics(target,expected)
    local result={present=false,allGroups=false,lineCount=0,staticTexts=0,visited=0,truncated=false,
      expectedLength=type(expected)=='string' and #expected or 0,valueEqual=false,reconstructedEqual=false,
      withoutTerminalEmptyGroupEqual=false,emptyMarkerNormalizedEqual=false,emptyMarkerLines=0}
    if type(expected)~='string' or #expected>8388608 then return result end
    local element=prompt(target);if not element then return result end
    result.present=true
    local value=attribute(element,'AXValue');result.valueEqual=value==expected
    local groups=attribute(element,'AXChildren')
    if type(groups)~='table' then return result end
    result.allGroups=true;result.lineCount=#groups
    local lines,normalized={},{}
    local function texts(node,fragments)
      result.visited=result.visited+1
      if result.visited>20000 then result.truncated=true;return end
      if attribute(node,'AXRole')=='AXStaticText' then
        local text=attribute(node,'AXValue')
        if type(text)~='string' then result.allGroups=false;return end
        fragments[#fragments+1]=text;result.staticTexts=result.staticTexts+1
      else for _,child in ipairs(attribute(node,'AXChildren') or {})do texts(child,fragments)end end
    end
    for _,group in ipairs(groups)do
      if attribute(group,'AXRole')~='AXGroup' then result.allGroups=false end
      local fragments={};texts(group,fragments);local line=table.concat(fragments)
      lines[#lines+1]=line
      if line=='\226\128\139' then result.emptyMarkerLines=result.emptyMarkerLines+1;normalized[#normalized+1]=''
      else normalized[#normalized+1]=line end
    end
    local reconstructed=table.concat(lines,'\n');result.reconstructedLength=#reconstructed
    result.reconstructedEqual=reconstructed==expected
    result.emptyMarkerNormalizedEqual=table.concat(normalized,'\n')==expected
    if #lines>1 and lines[#lines]=='' then result.withoutTerminalEmptyGroupEqual=table.concat(lines,'\n',1,#lines-1)==expected end
    result.firstDiff=0
    for index=1,math.min(#expected,#reconstructed,1048576)do if expected:byte(index)~=reconstructed:byte(index) then result.firstDiff=index;break end end
    if result.firstDiff==0 and #expected~=#reconstructed then result.firstDiff=math.min(#expected,#reconstructed)+1 end
    result.expectedBytes={};result.reconstructedBytes={}
    if result.firstDiff>0 then
      for index=result.firstDiff,result.firstDiff+2 do
        local a,b=expected:byte(index),reconstructed:byte(index)
        if a then result.expectedBytes[#result.expectedBytes+1]=a end
        if b then result.reconstructedBytes[#result.reconstructedBytes+1]=b end
      end
    end
    result.markerCandidates={}
    for _,candidate in ipairs({{'U200B','\226\128\139'},{'U2028','\226\128\168'},{'U2029','\226\128\169'},
      {'U200E','\226\128\142'},{'U200F','\226\128\143'},{'U2068','\226\129\168'},{'U2069','\226\129\169'}})do
      local filtered,count=reconstructed:gsub(candidate[2],'')
      result.markerCandidates[#result.markerCandidates+1]={codepoint=candidate[1],count=count,equalAfterRemoval=filtered==expected}
    end
    return result
  end
  function adapter.promptFocused(target)
    local value=app();local element=prompt(target)
    local focused=foreground(target)
    return value and focused
      and element and attribute(element,'AXFocused')==true
      and attribute(hs.axuielement.applicationElement(value),'AXFocusedUIElement')==element or false
  end
  function adapter.focusPrompt(target)
    if not foreground(target) then return false end
    local element=prompt(target);if not element then return 'pending' end
    element:setAttributeValue('AXFocused',true)
    -- Verify the result on the next tick using the native window and exact prompt.
    if not foreground(target) then return false end
    hs.eventtap.keyStroke({'ctrl'},'`',0,app())
    return true
  end
  function adapter.paste(target,version)
    if not adapter.isTracking() or type(version)~='number' or hs.pasteboard.changeCount()~=version or not adapter.promptFocused(target) then return false end
    hs.eventtap.keyStroke({'cmd'},'v',0,app());return true
  end
  function adapter.execute(target,version)
    if not adapter.isTracking() or type(version)~='number' or hs.pasteboard.changeCount()~=version or not adapter.promptFocused(target) then return false end
    hs.eventtap.keyStroke({},'return',0,app());return true
  end
  local function ownedPrompt(target,version,contextLabel,expectedActivity)
    return type(version)=='number' and type(contextLabel)=='string' and type(expectedActivity)=='number'
      and activity==expectedActivity and adapter.isTracking() and foreground(target)~=nil
      and adapter.promptFocused(target) and adapter.contextLabel(target)==contextLabel
      and hs.pasteboard.changeCount()==version
  end
  function adapter.selectSourceForVerification(target,version,contextLabel,expectedActivity)
    if not ownedPrompt(target,version,contextLabel,expectedActivity) then return false end
    hs.eventtap.keyStroke({'cmd'},'a',0,app());return true
  end
  function adapter.copySelectedSource(target,version,contextLabel,expectedActivity)
    if not ownedPrompt(target,version,contextLabel,expectedActivity) then return false end
    hs.eventtap.keyStroke({'cmd'},'c',0,app());return true
  end
  function adapter.pollCopiedSource(target,previousVersion,contextLabel,expectedActivity)
    if activity~=expectedActivity or not adapter.isTracking() or not foreground(target)
      or not adapter.promptFocused(target) or adapter.contextLabel(target)~=contextLabel then return {conflict=true} end
    local version=hs.pasteboard.changeCount()
    if version==previousVersion then return nil end
    if version~=previousVersion+1 then return {conflict=true} end
    local types=hs.pasteboard.allContentTypes()
    if type(types)~='table' or #types~=1 then return {conflict=true} end
    local ok,contents=pcall(hs.pasteboard.getContents)
    if hs.pasteboard.changeCount()~=version then return {conflict=true} end
    return {version=version,contents=ok and contents or nil}
  end
  function adapter.collapseSourceSelection(target,version,contextLabel,expectedActivity)
    if not ownedPrompt(target,version,contextLabel,expectedActivity) then return false end
    hs.eventtap.keyStroke({},'right',0,app());return true
  end
  function adapter.sourceSelectionEmpty(target)
    if not adapter.promptFocused(target) then return false end
    local element=prompt(target)
    local selected=attribute(element,'AXSelectedText')
    if type(selected)=='string' then return selected=='' end
    local range=attribute(element,'AXSelectedTextRange')
    if type(range)=='table' then
      local length=rawget(range,'length')
      if length==nil then length=rawget(range,'_length') end
      if type(length)=='number' then return length==0 end
    end
    return nil
  end
  function adapter.result(target,nonce,marker)
    local root=axWindow(target);if not root then return nil end
    local values=walk(root,function(e)return attribute(e,'AXRole')=='AXStaticText'end,8000)
    for _,element in ipairs(values) do
      local text=attribute(element,'AXValue')
      if type(text)=='string' and text:sub(1,1)=='{' and text:find(nonce,1,true) then
        local ok,value=pcall(hs.json.decode,text)
        if ok and type(value)=='table' and value.nonce==nonce and value.marker==(marker or 'RTL_CONSOLE_RESULT') then return value end
      end
    end
  end
  function adapter.closeTools(target,pid)
    local value=app();if not value or value:pid()~=pid then return false end
    local item=window(target);if not item then return false end
    if item:close()~=true then return false end
    -- Close by exact window ID and title. Never send Command+W.
    return 'pending'
  end
  function adapter.toolsClosed(target,pid)
    local value=app();if not value or value:pid()~=pid then return false end
    for _,item in ipairs(nativeWindows()) do if item:id()==target.id then return false end end
    return true
  end
  return adapter
end

function M.start(config,hs)
  local driver=M.new(config,M.nativeAdapter(hs))
  local timer,stopping
  timer=hs.timer.doEvery(0.15,function()
    local result=driver.tick()
    if stopping and result.phase~='cleanup' then timer:stop() end
  end)
  return {begin=function(request)if stopping then return false,'stopped' end;return driver.begin(request)end,
    snapshot=driver.snapshot,cancel=driver.cancel,
    stop=function()
      stopping=true;local result=driver.cancel()
      if result.phase~='cleanup' then timer:stop() end
      return result
    end}
end
return M
