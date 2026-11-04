-- Run the simulated adapter only. Do not target real UI or the system clipboard.
local M=assert(loadfile(assert(arg[1])))()
local assertions,scenarios=0,0
local function check(value,message)assertions=assertions+1;assert(value,message)end
local function fixture(options)
  options=options or {};scenarios=scenarios+1
  local state={now=0,activity=0,focused=10,pid=123,frontmost=true,tracking=false,windows={{id=10,title='Claude',pid=123}},
    clipboard={['public.utf8-plain-text']='sample',['public.html']='<p>sample</p>',['public.rtf']='{sample}'},
    clipboardVersion=4,prompt='',context='JavaScript context: top',focusedPrompt=false,events={},closed={}}
  if options.existing then state.windows[#state.windows+1]={id=20,title='Developer Tools - existing'} end
  local function event(name)state.events[#state.events+1]=name end
  local adapter={now=function()return state.now end,activity=function()return state.activity end,
    identity=function()return {pid=state.pid,bundle=options.wrongBundle and 'other' or 'com.anthropic.claudefordesktop',path=options.wrongPath and '/tmp/Claude.app' or '/Applications/Claude.app',frontmost=state.frontmost,focusedWindow=state.focused}end,
    windows=function()return state.windows end,
    captureClipboard=function()if options.multi then return nil,'clipboard-multiple-items' end;return {data=state.clipboard,version=state.clipboardVersion}end,
    clipboardUnchanged=function(saved)return saved.version==state.clipboardVersion end,
    clipboardVersion=function()return state.clipboardVersion end,
    nonce=function()return '0123456789abcdef0123456789abcdef'end,
    beginTracking=function()event('tracking');state.tracking=true;return true end,
    isTracking=function()return state.tracking end,
    endTracking=function()event('untracking');state.tracking=false end,
    openTools=function(id,pid)
      check(id==10 and pid==123,'open exact target');event('open')
      if not options.noTools then
        state.windows[#state.windows+1]={id=20,title=options.toolsTitle or 'Developer Tools - synthetic',pid=options.toolsPID or 123};state.focused=20
        if options.ambiguousTools then state.windows[#state.windows+1]={id=21,title='Developer Tools - synthetic 2',pid=123} end
      end
      return not options.menuFails
    end,
    openContexts=function(target)check(target.id==20,'context exact tools');event('contexts');return true end,
    contexts=function()
      local list={{title='fixture.frame.claudeusercontent.com'},{title='top'}}
      if options.ambiguousContext then list[#list+1]={title='fixture.frame.claudeusercontent.com'} end
      return list
    end,
    selectContext=function(_,option)event('select');check(option.title=='fixture.frame.claudeusercontent.com','context from list');if not options.contextStuck then state.context='JavaScript context: fixture' end;return true end,
    contextLabel=function()return state.context end,
    promptValue=function()return state.prompt end,
    focusPrompt=function()event('focus');state.focusedPrompt=true;return true end,
    promptFocused=function()return state.focusedPrompt end,
    writeClipboard=function(source)event('write');state.payloadSource=source;state.clipboard=source;state.clipboardVersion=5;return 5,not options.writeFails end,
    paste=function()event('paste');state.prompt=options.partialPaste and 'partial' or state.clipboard;return true end,
    execute=function()event('return');state.prompt='';return true end,
    result=function(_,nonce)
      if options.noResult then return nil end
      return {marker='RTL_CONSOLE_RESULT',nonce=options.wrongNonce and 'stale' or nonce,kind=options.wrongKind and 'chat' or 'artifact-content',ok=not options.applyFails}
    end,
    restoreClipboard=function(saved,version)
      event('restore');if state.clipboardVersion~=version then return false end
      state.clipboard=saved.data;state.clipboardVersion=6;return true
    end,
    closeTools=function(target,pid)
      check(target.id==20 and target.title=='Developer Tools - synthetic','close exact tools id and title')
      if state.pid~=pid then return false end
      for i,value in ipairs(state.windows)do if value.id==target.id and value.title==target.title then
        event('close');state.closed[#state.closed+1]=target.id;table.remove(state.windows,i);return true
      end end
      return false
    end}
  local original=state.clipboard
  local config={timeout=options.timeout or 2,payload=function(kind,nonce,documentId)
    state.payloadDocumentId=documentId
    return '(async()=>{globalThis.executed=true;return {marker:"RTL_CONSOLE_RESULT",nonce:"'..nonce..'",kind:"'..kind..'",ok:true,documentId:"'..documentId..'"};})()'
  end}
  local driver=M.new(config,adapter)
  local request={windowId=10,kind='artifact-content',context='fixture.frame.claudeusercontent.com',contextLabel='JavaScript context: fixture',
    documentId=string.rep('a',32),toolsTitle='Developer Tools - synthetic'}
  return {state=state,driver=driver,request=request,adapter=adapter,original=original,config=config,
    run=function(untilPhase)
      for _=1,30 do
        driver.tick()
        if driver.snapshot().phase==untilPhase then return end
        state.now=state.now+0.1
      end
    end}
end
local f=fixture();check(f.driver.begin(f.request),'start');f.run('complete');local result=f.driver.snapshot()
check(result.ok and result.toolsClosed and result.clipboardRestored,'complete only after cleanup')
check(f.state.clipboard==f.original and f.state.clipboard['public.rtf']=='{sample}','all clipboard formats preserved')
check(table.concat(f.state.events,',')=='tracking,open,contexts,select,focus,write,paste,return,restore,close,untracking','ordered transaction')
check(#f.state.windows==1 and f.state.windows[1].id==10,'main window remains')
for key in pairs(result)do check(key~='title' and key~='url' and key~='payload' and key~='clipboard','no private snapshot')end
for _,options in ipairs({{wrongBundle=true},{wrongPath=true},{existing=true},{multi=true}})do
  f=fixture(options);check(not f.driver.begin(f.request),'preflight refused');check(#f.state.events==0,'preflight no modification')
end
f=fixture();check(f.driver.begin(f.request),'start busy');check(not f.driver.begin(f.request),'busy refused');f.driver.cancel();check(#f.state.events==2,'cancel before open no UI')
for _,change in ipairs({'frontmost','focused','pid','activity'})do
  f=fixture();f.driver.begin(f.request);f.run('paste')
  if change=='frontmost' then f.state.frontmost=false elseif change=='focused' then f.state.focused=10 elseif change=='pid' then f.state.pid=124 else f.state.activity=1 end
  f.driver.tick();check(not f.driver.snapshot().ok,'guard cancelled '..change)
  check(not table.concat(f.state.events,','):find('write'),'no paste after guard '..change)
end
f=fixture();f.driver.begin(f.request);f.run('paste');f.state.prompt='user draft';f.driver.tick();check(f.driver.snapshot().reason=='prompt-focus-changed','nonempty prompt preserved');check(f.state.prompt=='user draft','draft not erased')
f=fixture();f.driver.begin(f.request);f.run('paste');f.state.focusedPrompt=false;f.driver.tick();check(f.driver.snapshot().reason=='prompt-focus-changed','prompt focus checked before paste')
f=fixture();f.driver.begin(f.request);f.run('execute');f.state.focusedPrompt=false;f.driver.tick();check(not table.concat(f.state.events,','):find('return'),'focus loss prevents Return');check(f.state.clipboard==f.original,'clipboard restored after focus loss')
f=fixture();f.driver.begin(f.request);f.run('paste');f.state.clipboardVersion=30;f.state.clipboard='new user clipboard';f.driver.tick();check(f.state.clipboard=='new user clipboard','new clipboard before paste untouched')
f=fixture({noResult=true});f.driver.begin(f.request);f.run('await-result');f.state.clipboardVersion=30;f.state.clipboard='new user clipboard';f.state.now=5;f.driver.tick();check(f.state.clipboard=='new user clipboard','new clipboard during wait untouched');check(not f.driver.snapshot().clipboardRestored,'restore conflict reported')
for _,options in ipairs({{wrongNonce=true},{wrongKind=true},{applyFails=true},{partialPaste=true},{writeFails=true},{ambiguousContext=true},{ambiguousTools=true}})do
  f=fixture(options);f.driver.begin(f.request);f.run('done');check(not f.driver.snapshot().ok,'failed state never success');check(f.state.clipboard==f.original,'failure preserves clipboard')
end
f=fixture({contextStuck=true});f.driver.begin(f.request);f.run('done');check(f.driver.snapshot().reason=='timeout','selection must be confirmed');check(not table.concat(f.state.events,','):find('write'),'no paste in unconfirmed context')
f=fixture({noTools=true});f.driver.begin(f.request);f.run('done');check(f.driver.snapshot().reason=='timeout','tools wait bounded');check(#f.state.closed==0,'no close without owned tools')
f=fixture();f.driver.begin(f.request);f.run('paste');f.state.context='JavaScript context: other';f.driver.tick();check(f.driver.snapshot().reason=='context-changed','context rechecked before paste')
f=fixture();f.driver.begin(f.request);f.run('execute');f.state.context='JavaScript context: other';f.driver.tick();check(not table.concat(f.state.events,','):find('return'),'context rechecked before Return')
f=fixture();f.driver.begin(f.request);f.run('paste');f.state.windows[2].title='Developer Tools - changed';f.driver.tick();check(f.driver.snapshot().reason=='tools-changed','title change prevents cleanup');check(#f.state.closed==0,'changed tools untouched')
f=fixture();f.driver.begin(f.request);f.run('paste');f.adapter.promptFocused=function()error('synthetic')end;f.driver.tick();check(f.driver.snapshot().reason=='adapter-failed','adapter failure bounded');check(f.state.clipboard==f.original,'exception clipboard safe')
f=fixture();f.adapter.beginTracking=function()return false end;check(not f.driver.begin(f.request),'input monitor failure refused');check(f.driver.snapshot().reason=='input-monitor-unavailable','input monitor failure reported')
f=fixture();f.adapter.beginTracking=function()error('synthetic')end;check(not f.driver.begin(f.request),'tracking exception bounded');check(f.driver.snapshot().reason=='adapter-failed','tracking exception reported')
f=fixture();local closing=0
f.adapter.closeTools=function()return 'pending'end
f.adapter.toolsClosed=function()closing=closing+1;return closing==3 end
f.driver.begin(f.request);f.run('cleanup');check(not f.driver.snapshot().ok,'close request alone not success')
f.driver.tick();f.driver.tick();check(not f.driver.snapshot().ok,'close waits for actual absence')
f.driver.tick();check(f.driver.snapshot().ok and f.state.clipboard==f.original,'async close verified')
f=fixture();f.adapter.closeTools=function()return 'pending'end;f.adapter.toolsClosed=function()return false end
f.driver.begin(f.request);f.run('cleanup');f.state.now=10;f.driver.tick();check(f.driver.snapshot().reason=='tools-cleanup-failed','async close has separate bounded deadline')
f=fixture();f.adapter.closeTools=function()return 'pending'end;f.adapter.toolsClosed=function()error('synthetic')end
f.driver.begin(f.request);f.run('cleanup');f.driver.tick();check(f.driver.snapshot().reason=='tools-cleanup-failed','async close exception cannot hang')
f=fixture();f.driver.begin(f.request);f.driver.tick();f.state.activity=1;f.driver.tick()
check(#f.state.closed==0,'activity during tools creation prevents ownership claim')
check(not f.driver.snapshot().toolsClosed,'unowned newly visible tools are not reported closed')
f=fixture({timeout=10,toolsTitle='Developer Tools - opening'});f.driver.begin(f.request);f.driver.tick();f.driver.tick()
check(f.driver.snapshot().phase=='await-tools' and #f.state.closed==0,'transient title waits without ownership')
check(f.driver.snapshot().toolsSamePID and not f.driver.snapshot().toolsTitleMatch and f.driver.snapshot().toolsFirstDiff>0,'safe mismatch diagnostics available')
f.state.now=1;f.state.windows[2].title='Developer Tools - synthetic';f.run('complete')
check(f.driver.snapshot().ok and f.driver.snapshot().toolsTitleMatch and f.driver.snapshot().toolsFirstDiff==0,'transient title becomes exact before command')
f=fixture({timeout=10,toolsTitle='Developer Tools - persistent'});f.driver.begin(f.request);f.driver.tick();f.driver.tick();f.state.now=2.01;f.driver.tick()
check(f.driver.snapshot().reason=='tools-title-mismatch' and #f.state.closed==0,'persistent title mismatch fails after two seconds without closing')
check(f.driver.snapshot().toolsExpectedLength==#f.request.toolsTitle and f.driver.snapshot().toolsActualLength==#'Developer Tools - persistent','diagnostics contain lengths only')
f=fixture({timeout=10,toolsTitle=''});f.driver.begin(f.request);f.driver.tick();f.driver.tick()
check(f.driver.snapshot().phase=='await-tools' and f.driver.snapshot().toolsActualLength==0 and f.driver.snapshot().toolsSamePID,'blank title is an unproven official-PID candidate')
check(not table.concat(f.state.events,','):find('contexts') and #f.state.closed==0,'blank candidate receives no code or close')
f.state.windows[2].title='Developer Tools - synthetic';f.run('complete')
check(f.driver.snapshot().ok,'blank native title may become exact on later tick')
f=fixture({timeout=10,toolsTitle=''});f.driver.begin(f.request);f.driver.tick();f.driver.tick()
f.state.windows[3]={id=21,pid=123,title='Unrelated new official window'};f.driver.tick()
check(f.driver.snapshot().reason=='ambiguous-tools' and #f.state.closed==0,'conflicting new window blocks blank-candidate attribution')
f=fixture({timeout=10,toolsTitle='A different window'});f.driver.begin(f.request);f.driver.tick();f.driver.tick();f.state.now=2.01;f.driver.tick()
check(f.driver.snapshot().reason=='tools-title-mismatch' and #f.state.closed==0,'wrong non-tool title cannot acquire ownership')
f=fixture({timeout=10,toolsTitle='',toolsPID=999});f.driver.begin(f.request);f.driver.tick();f.driver.tick()
check(f.driver.snapshot().reason=='tools-process-mismatch' and #f.state.closed==0,'blank foreign-PID window rejected immediately')
f=fixture({timeout=10,toolsTitle=''});f.driver.begin(f.request);f.driver.tick();f.driver.tick();f.state.activity=1;f.driver.tick()
check(f.driver.snapshot().reason=='user-activity' and #f.state.closed==0,'user input cancels blank candidate wait')
f=fixture({timeout=10,toolsPID=999});f.driver.begin(f.request);f.driver.tick();f.driver.tick()
check(f.driver.snapshot().reason=='tools-process-mismatch' and not f.driver.snapshot().toolsSamePID,'wrong candidate PID fails immediately')
f=fixture({timeout=10,toolsTitle='Developer Tools - opening'});f.driver.begin(f.request);f.driver.tick();f.driver.tick()
f.state.windows[2].id=21;f.state.focused=21;f.driver.tick()
check(f.driver.snapshot().reason=='tools-candidate-changed' and #f.state.closed==0,'transient wait cannot switch candidate identity')
f=fixture({timeout=10});f.driver.begin(f.request);f.driver.tick();f.state.focused=10;f.driver.tick()
check(f.driver.snapshot().phase=='await-tools','source focus may remain during native window opening')
f.state.focused=20;f.run('complete');check(f.driver.snapshot().ok,'exact candidate becomes focused without focus stealing')
local function focusTransitionFixture()
  local f=fixture({timeout=10});f.driver.begin(f.request);f.driver.tick()
  local identity=f.adapter.identity;local reads=0
  f.adapter.identity=function()reads=reads+1;if reads==2 then f.state.focused=10 end;return identity()end
  f.driver.tick();f.adapter.identity=identity
  return f
end
f=focusTransitionFixture()
check(f.driver.snapshot().phase=='waiting-for-tools-focus','source focus returning during frontend creation waits safely')
check(not table.concat(f.state.events,','):find('contexts'),'focus readiness wait sends no menu action')
f.state.focused=20;f.run('complete');check(f.driver.snapshot().ok,'native focus readiness eventually continues')
f=focusTransitionFixture();f.state.now=2.1;f.driver.tick()
check(f.driver.snapshot().reason=='focus-changed' and #f.state.closed==0,'source focus readiness bounded without unproven close')
check(f.driver.snapshot().failurePhase=='open-contexts' and f.driver.snapshot().focusIsSource and not f.driver.snapshot().focusIsTools,'safe failure phase and focus diagnostics')
check(f.driver.snapshot().frontmost and f.driver.snapshot().focusedWindowPresent and f.driver.snapshot().tracking,'safe readiness flags preserved')
f=focusTransitionFixture();f.state.focused=77;f.driver.tick()
check(f.driver.snapshot().reason=='focus-changed' and not f.driver.snapshot().focusIsSource,'foreign window never qualifies for readiness wait')
f=focusTransitionFixture();f.state.activity=1;f.driver.tick()
check(f.driver.snapshot().reason=='user-activity','user activity cancels readiness wait immediately')
f=fixture();local opens=0;local originalOpen=f.adapter.openContexts
f.adapter.openContexts=function(target)opens=opens+1;if opens<3 then return 'pending' end;return originalOpen(target)end
f.driver.begin(f.request);f.driver.tick();f.driver.tick()
check(f.driver.snapshot().phase=='waiting-for-contexts','missing context button waits for frontend readiness')
f.run('complete');check(f.driver.snapshot().ok and opens==3,'context menu action happens once after frontend ready')
f=fixture();f.adapter.openContexts=function()return 'pending'end;f.driver.begin(f.request);f.run('done')
check(f.driver.snapshot().reason=='timeout' and #f.state.closed==0,'missing frontend has bounded wait without unproven close')
f=fixture();f.adapter.openContexts=function()return false end;f.driver.begin(f.request);f.run('done')
check(f.driver.snapshot().reason=='contexts-open-failed','rejected context action remains immediate failure')
f=fixture({timeout=10});local menuOpens=0;local menuOpen=f.adapter.openContexts;local menuOptions=f.adapter.contexts
f.adapter.openContexts=function(target)menuOpens=menuOpens+1;return menuOpen(target)end
f.adapter.contexts=function(target)if menuOpens<2 then return nil end;return menuOptions(target)end
f.driver.begin(f.request);f.run('complete')
check(f.driver.snapshot().ok and menuOpens==2,'missing menu acknowledgement retries after bounded delay')
f=fixture({timeout=10});menuOpens=0;menuOpen=f.adapter.openContexts
f.adapter.openContexts=function(target)menuOpens=menuOpens+1;return menuOpen(target)end
f.adapter.contexts=function()return nil end;f.state.prompt='user draft untouched';f.driver.begin(f.request);f.run('done')
check(menuOpens==3 and f.driver.snapshot().reason=='contexts-menu-unavailable','menu retries stop after three attempts')
check(f.state.prompt=='user draft untouched' and not table.concat(f.state.events,','):find('select'),'missing menu never sends selection keys to prompt')
f=fixture();f.driver.begin(f.request);f.run('focus-prompt');local originalValue=f.adapter.promptValue;f.adapter.promptValue=function()return nil end;f.driver.tick()
check(f.driver.snapshot().phase=='waiting-for-prompt','missing prompt waits before any clipboard change')
check(f.state.clipboard==f.original,'prompt readiness wait preserves clipboard')
f.adapter.promptValue=originalValue;f.run('complete');check(f.driver.snapshot().ok,'prompt appearing later continues safely')
f=fixture();f.driver.begin(f.request);f.run('focus-prompt');f.adapter.promptValue=function()return nil end;f.run('done')
check(f.driver.snapshot().reason=='timeout' and f.state.clipboard==f.original,'missing prompt wait is bounded')
f=fixture();f.driver.begin(f.request);f.run('focus-prompt');f.state.prompt='user draft';f.driver.tick()
check(f.driver.snapshot().reason=='prompt-not-empty','nonempty prompt is never treated as pending readiness')
for _,options in ipairs({{toolsTitle='Developer Tools - unrelated'},{toolsPID=999},{menuFails=true},{noTools=true}})do
  f=fixture(options);f.driver.begin(f.request);f.run('done')
  check(#f.state.closed==0,'unrelated or uncertain tool is never closed')
  check(not f.driver.snapshot().toolsClosed and f.driver.snapshot().cleanupRequired,'unknown tool state requires cleanup')
  check(f.driver.snapshot().toolsUnverified,'unknown tool state is explicit')
end
f=fixture({applyFails=true});f.driver.begin(f.request);f.run('done')
check(#f.state.closed==0 and f.driver.snapshot().toolsUnverified,'same-title wrong-document receipt cannot authorize close')
f=fixture({wrongNonce=true});f.driver.begin(f.request);f.run('done')
check(#f.state.closed==0 and f.driver.snapshot().cleanupRequired,'stale receipt cannot authorize close')
for _,phase in ipairs({'paste','execute'})do
  f=fixture();f.driver.begin(f.request);f.run(phase);f.state.tracking=false;f.driver.tick()
  check(f.driver.snapshot().reason=='input-monitor-unavailable','disabled monitor blocks '..phase)
  check(not table.concat(f.state.events,','):find('return'),'disabled monitor never executes')
end
f=fixture();f.adapter.beginTracking=function()return nil end;check(not f.driver.begin(f.request),'nil monitor start refused');check(#f.state.closed==0,'nil start no UI close')
f=fixture();f.driver.begin(f.request);f.run('execute');f.state.clipboardVersion=80;f.state.clipboard='user replacement';f.driver.tick()
check(not table.concat(f.state.events,','):find('return'),'clipboard replacement prevents Return')
check(f.state.clipboard=='user replacement','replacement clipboard preserved before Return')
f=fixture();local originalPaste=f.adapter.paste;f.adapter.paste=function(target)originalPaste(target);f.state.prompt=f.state.prompt..'\n';return true end
f.driver.begin(f.request);f.run('done');local pasteMeta=f.driver.snapshot()
check(pasteMeta.reason=='paste-not-verified' and pasteMeta.pasteEqualAfterTrailingLF,'trailing LF diagnostic never authorizes execution')
check(pasteMeta.pasteEnteredLength==pasteMeta.pasteExpectedLength+1 and pasteMeta.pasteFirstDiff==pasteMeta.pasteExpectedLength+1,'paste length and first difference metrics')
check(not table.concat(f.state.events,','):find('return'),'paste diagnostic mismatch emits no Return')
f=fixture();originalPaste=f.adapter.paste;f.adapter.paste=function(target)originalPaste(target);f.state.prompt=f.state.prompt..' ';return true end
f.driver.begin(f.request);f.run('done');pasteMeta=f.driver.snapshot()
check(pasteMeta.pasteEqualAfterLineEndSpaces and not pasteMeta.pasteEqualAfterTrailingLF,'line-end space candidate remains diagnostic only')
f=fixture();f.driver.begin(f.request);f.run('execute');local completePrompt=f.state.prompt;f.state.prompt=completePrompt:sub(1,30);f.driver.tick()
check(f.driver.snapshot().phase=='execute' and not table.concat(f.state.events,','):find('return'),'large paste prefix waits without Return')
f.state.prompt=completePrompt;f.driver.tick();check(table.concat(f.state.events,','):find('return'),'full paste permits Return after recheck')
-- AX can expose only the viewport. Allow fallback execution only after a complete copy.
local function copyFixture(options)
  options=options or {};local f=fixture({timeout=10});local state=f.state
  f.adapter.paste=function()state.events[#state.events+1]='paste';state.prompt='viewport substring';return true end
  f.adapter.selectSourceForVerification=function()
    state.events[#state.events+1]='select-all';state.selection=true;return true
  end
  f.adapter.copySelectedSource=function()
    state.events[#state.events+1]='copy';state.copyReads=0
    if not options.noDelta then
      state.clipboardVersion=state.clipboardVersion+(options.extraDelta and 2 or 1)
      state.clipboard=options.truncated and state.payloadSource:sub(1,30) or state.payloadSource
    end
    return true
  end
  f.adapter.pollCopiedSource=function(_,previous)
    state.copyReads=(state.copyReads or 0)+1
    if state.clipboardVersion==previous then return nil end
    if state.clipboardVersion~=previous+1 then return {conflict=true} end
    if options.lazy and state.copyReads==1 then return {version=state.clipboardVersion} end
    return {version=state.clipboardVersion,contents=state.clipboard}
  end
  f.adapter.collapseSourceSelection=function()
    state.events[#state.events+1]='right';if not options.collapseStuck then state.selection=false end;return true
  end
  f.adapter.sourceSelectionEmpty=function()return state.selection==false end
  return f
end
f=copyFixture();f.driver.begin(f.request);f.run('complete')
check(f.driver.snapshot().ok and f.driver.snapshot().copyVerifications==1,'exact full copied source authorizes fallback')
check(f.state.clipboard==f.original and f.state.clipboard['public.html']=='<p>sample</p>' and f.state.clipboard['public.rtf']=='{sample}','copy lease restores all original UTI formats')
check(table.concat(f.state.events,','):find('select%-all,copy,right,return,restore'),'select copy collapse then Return order')
f=copyFixture({lazy=true});f.driver.begin(f.request);f.run('complete')
check(f.driver.snapshot().ok and f.state.copyReads==2,'lazy copied content may arrive at same verified owner count')
f=copyFixture({noDelta=true});f.driver.begin(f.request);f.run('done')
check(f.driver.snapshot().phase=='copy-timeout' and not table.concat(f.state.events,','):find('return'),'unchanged clipboard containing payload never proves copy')
check(f.state.clipboard==f.original,'copy timeout restores original owned clipboard')
f=copyFixture({truncated=true});f.driver.begin(f.request);f.run('done')
check(f.driver.snapshot().phase=='copied-source-mismatch' and not table.concat(f.state.events,','):find('return'),'truncated copied source never executes')
check(f.state.clipboard~=f.original and not f.driver.snapshot().clipboardRestored,'unknown copied data never adopts a new lease')
f=copyFixture({extraDelta=true});f.driver.begin(f.request);f.run('done')
check(f.driver.snapshot().phase=='clipboard-copy-conflict' and not f.driver.snapshot().clipboardRestored,'multiple clipboard changes never adopted')
f=copyFixture();f.driver.begin(f.request);f.run('copy-select');f.state.clipboardVersion=6;f.state.clipboard='new user clipboard';f.driver.tick()
check(not table.concat(f.state.events,','):find('select%-all') and f.state.clipboard=='new user clipboard','clipboard race before selection preserves user data')
f=copyFixture();f.driver.begin(f.request);f.run('copy-copy');f.state.clipboardVersion=6;f.state.clipboard='new user clipboard';f.driver.tick()
check(not table.concat(f.state.events,','):find(',copy,') and f.state.clipboard=='new user clipboard','clipboard race between CmdA and CmdC stops copy')
f=copyFixture({noDelta=true});f.driver.begin(f.request);f.run('copy-wait');f.state.clipboardVersion=6;f.state.clipboard='background sync replacement';f.driver.tick()
check(f.driver.snapshot().phase=='copied-source-mismatch' and f.state.clipboard=='background sync replacement','sole foreign delta with wrong content is never overwritten')
f=copyFixture();f.driver.begin(f.request);f.run('copy-wait');f.state.activity=1;f.state.clipboardVersion=7;f.state.clipboard='user copy during wait';f.driver.tick()
check((f.state.copyReads or 0)==0 and f.state.clipboard=='user copy during wait','user activity during copy aborts before clipboard read')
f=copyFixture();f.driver.begin(f.request);f.run('copy-select');f.state.focused=10;f.driver.tick()
check(not table.concat(f.state.events,','):find('select%-all'),'foreign prompt never receives CmdA')
f=copyFixture();f.driver.begin(f.request);f.run('copy-copy');f.state.focusedPrompt=false;f.driver.tick()
check(not table.concat(f.state.events,','):find(',copy,'),'lost prompt focus never receives CmdC')
f=copyFixture({collapseStuck=true});f.driver.begin(f.request);f.run('done')
check(f.driver.snapshot().phase=='copy-collapse-unverified' and not table.concat(f.state.events,','):find('return'),'selected source cannot execute until collapse verified')
check(f.state.clipboard==f.original,'exact-copy failure during collapse restores adopted lease')
f=copyFixture();f.driver.begin(f.request);f.run('execute-copied');f.state.clipboardVersion=7;f.state.clipboard='replacement after exact copy';f.driver.tick()
check(not table.concat(f.state.events,','):find('return') and f.state.clipboard=='replacement after exact copy','clipboard lease checked again just before Return')
for _,bad in ipairs({'','xyz',string.rep('A',32),string.rep('a',31),string.rep('a',33)})do
  f=fixture();f.request.documentId=bad;check(not f.driver.begin(f.request),'invalid document ID refused');check(#f.state.events==0,'invalid document ID no action')
end
f=fixture();f.request.documentId=nil;check(not f.driver.begin(f.request),'missing document ID refused')
f=fixture();f.request.toolsTitle=nil;check(not f.driver.begin(f.request),'missing exact tool title refused')
f=fixture();f.request.toolsTitle='Claude';check(not f.driver.begin(f.request),'non-tool expected title refused')
f=fixture();f.driver.begin(f.request);f.run('execute');check(f.state.payloadDocumentId==f.request.documentId,'document ID reaches payload builder')
local guardedSource=f.state.payloadSource
f=fixture();f.config.payload=nil;f.config.payloads={['artifact-content']='(()=>"__RTL_CONSOLE_NONCE__")()'}
check(not f.driver.begin(f.request),'template without document placeholder refused')
f=fixture();f.config.payload=nil;f.config.payloads={['artifact-content']='(()=>"__RTL_CONSOLE_NONCE_____RTL_CONSOLE_DOCUMENT_ID__")()'}
check(f.driver.begin(f.request),'both template placeholders accepted');f.run('execute')
check(not f.state.payloadSource:find('__RTL_CONSOLE_DOCUMENT_ID__',1,true),'document template substituted')
-- Pin the top source before scanning. Give each subsequent command a fresh nonce.
local function scanFixture(options)
  options=options or {}
  local f=fixture({timeout=40});local state=f.state
  f.request={windowId=10,toolsTitle='Developer Tools - synthetic',sourceURL='https://claude.ai/new',scan=true}
  local fullDocumentTitle='{"title":"Synthetic document","scope":"ordinary frame"}'
  local truncatedPrefix=fullDocumentTitle:sub(1,25)
  local documentTitle=options.truncatedTitle and (truncatedPrefix..'\226\128\166') or options.jsonTitle and '{"title":"سند ساختگی"}' or 'document'
  local entries={{title='top claude.ai',contextLabel='JavaScript context: top',frame=true},
    {title='DevTools Performance Metrics',frame=false},{title='Electron Isolated Context',frame=false},
    {title=documentTitle,frame=true},{title='comments',frame=true},{title='same-document',frame=true},
    {title='healthy',frame=true},{title='unrelated',frame=true},{title='⚙ completion-gzip',frame=false}}
  if options.duplicateTop then entries[#entries+1]={title='top duplicate',frame=true} end
  if options.duplicateFrame then entries[#entries+1]={title='comments',frame=true} end
  if options.overlapTruncated then entries[#entries+1]={title=truncatedPrefix..' longer\226\128\166',frame=true} end
  if options.shorterTruncated then entries[#entries+1]={title=truncatedPrefix:sub(1,12)..'\226\128\166',frame=true} end
  for index,entry in ipairs(entries)do entry.index=index;entry.contextLabel=entry.contextLabel or ('JavaScript context: '..entry.title)end
  local surfaces={['top claude.ai']={kind='chat',id=string.rep('a',32),healthy=options.topHealthy},document={kind='document',id=string.rep('b',32)},
    comments={kind='artifact-content',id=string.rep('c',32)},['same-document']={kind='document',id=string.rep('b',32)},
    healthy={kind='chat',id=string.rep('d',32),healthy=true}}
  surfaces[documentTitle]={kind='document',id=string.rep('b',32)}
  local number=0;state.commands={};state.selected='top claude.ai'
  f.adapter.nonce=function()number=number+1;return options.reuseNonce and string.rep('n',32) or string.format('%032x',number)end
  f.adapter.contexts=function()return entries end
  f.adapter.selectContext=function(_,entry)
    state.selected=entry.title;state.context=entry.contextLabel
    if entry.title==documentTitle then
      if options.truncatedTitle then state.context='JavaScript context: '..fullDocumentTitle..' (1790000000-000e/)' end
      if options.wrongExpansion then state.context='JavaScript context: unrelated expanded name (1790000000-000e/)' end
      if options.suffix then state.context=state.context..' (1790000000-000e/)' end
      if options.prefixCollision then state.context=entry.contextLabel..'-other (1790000000-000e/)' end
      if options.trailingSuffix then state.context=entry.contextLabel..' (1790000000-000e/) other)' end
    end
    return true
  end
  f.adapter.dismissContexts=function()return true end
  local originalPayload=f.config.payload
  f.config.payload=function(kind,nonce,id)
    state.command={kind=kind,nonce=nonce,id=id,type='apply',context=state.selected};state.commands[#state.commands+1]=state.command
    return originalPayload(kind,nonce,id)
  end
  f.config.probe=function(nonce,expectedURL)
    state.command={nonce=nonce,expectedURL=expectedURL,type='probe',context=state.selected};state.commands[#state.commands+1]=state.command
    return '(async()=>({marker:"RTL_CONSOLE_PROBE",nonce:"'..nonce..'",ok:true,kind:"chat",documentId:"'..string.rep('a',32)..'",healthy:false}))()'
  end
  f.adapter.result=function(_,nonce,marker)
    local command=state.command
    if command.type=='apply' then return {marker=marker,nonce=nonce,kind=command.kind,ok=not options.applyFails} end
    if options.sourceMismatch and command.expectedURL then return {marker=marker,nonce=nonce,ok=false,reason='source-mismatch'} end
    if options.childFails and not command.expectedURL then return {marker=marker,nonce=nonce,ok=false,reason='probe-failed'} end
    local surface=surfaces[state.selected]
    if not surface then return {marker=marker,nonce=nonce,ok=false,reason='context-mismatch'} end
    return {marker=marker,nonce=nonce,ok=true,kind=surface.kind,documentId=surface.id,healthy=surface.healthy==true}
  end
  f.scanUntil=function(phase)
    for _=1,1000 do
      f.driver.tick();local current=f.driver.snapshot()
      if current.phase==phase or current.reason then return current end
      state.now=state.now+0.05
    end
    return f.driver.snapshot()
  end
  return f
end
f=scanFixture();check(f.driver.begin(f.request),'scan begins without caller document ID');f.scanUntil('execute');local sourceGuard=f.state.payloadSource
local scanResult=f.scanUntil('complete')
check(scanResult.ok and scanResult.applied==3 and scanResult.skipped==3 and scanResult.contexts==6,'all ordinary contexts scanned and summarized')
check(scanResult.sourceWindowId==10 and scanResult.sourcePID==123,'source evidence uses native numeric identifiers only')
check(scanResult.appliedKinds.chat==1 and scanResult.appliedKinds.document==1 and scanResult.appliedKinds['artifact-content']==1,'successful applies counted by verified kind')
check(scanResult.probedKinds.chat==2 and scanResult.probedKinds.document==2 and scanResult.probedKinds['artifact-content']==1,'healthy and repeated documents still count valid probes')
local allowedKinds={shell=true,chat=true,artifact=true,['artifact-content']=true,document=true}
local mapKeys=0;for kind,count in pairs(scanResult.probedKinds)do mapKeys=mapKeys+1;check(allowedKinds[kind] and type(count)=='number','kind evidence has fixed safe keys')end
check(mapKeys==5 and scanResult.probedKinds.shell==0 and scanResult.appliedKinds.artifact==0,'all five evidence kinds present with zero counts')
scanResult.probedKinds.chat=999;scanResult.appliedKinds['https://private.example/fixture']=12
local detached=f.driver.snapshot()
check(detached.probedKinds.chat==2 and detached.appliedKinds['https://private.example/fixture']==nil,'kind evidence maps detached and private keys rejected')
check(#f.state.commands==9 and #f.state.closed==1,'one source probe then bounded frame commands and exact close')
check(f.state.commands[1].expectedURL=='https://claude.ai/new','first command proves exact source URL')
local nonces={};for index,command in ipairs(f.state.commands)do
  check(not nonces[command.nonce],'each command nonce unique');nonces[command.nonce]=true
  if index>1 then check(command.expectedURL==nil,'only source probe has expected URL') end
  check(not command.context:find('Metrics') and not command.context:find('Isolated') and not command.context:find('⚙'),'non-frame worlds excluded')
end
check(f.state.clipboard==f.original,'scan restores original multi-format clipboard once')
f=scanFixture({sourceMismatch=true});f.driver.begin(f.request);f.scanUntil('complete')
check(#f.state.commands==1 and #f.state.closed==0,'unproven source never applies children or closes tools')
check(f.driver.snapshot().toolsUnverified and f.driver.snapshot().cleanupRequired,'unproven source cleanup explicit')
f=scanFixture({childFails=true});f.driver.begin(f.request);f.scanUntil('complete')
check(#f.state.closed==1 and not f.driver.snapshot().ok,'proven source permits safe cleanup after child failure')
f=scanFixture({reuseNonce=true});f.driver.begin(f.request);f.scanUntil('complete')
check(f.driver.snapshot().reason=='invalid-or-reused-nonce' and #f.state.closed==1,'reused nonce aborts after source proof')
f=scanFixture({duplicateTop=true});f.driver.begin(f.request);f.scanUntil('complete')
check(#f.state.closed==0 and f.driver.snapshot().reason=='context-ambiguous-or-missing','duplicate top is unproven')
f=scanFixture({duplicateFrame=true});f.driver.begin(f.request);f.scanUntil('complete')
check(#f.state.closed==1 and f.driver.snapshot().reason=='duplicate-context','duplicate ordinary frame fails after proof')
f=scanFixture({applyFails=true});f.driver.begin(f.request);f.scanUntil('complete')
check(#f.state.closed==1 and not f.driver.snapshot().ok,'failed apply safely closes proven tools')
check(f.driver.snapshot().appliedKinds.chat==0 and f.driver.snapshot().probedKinds.chat==1,'failed apply never inflates applied-kind evidence')
f=fixture();f.driver.begin(f.request);f.run('complete');check(f.driver.snapshot().appliedKinds['artifact-content']==1,'explicit apply has kind evidence')
f.state.focused=10;check(f.driver.begin(f.request),'new transaction starts after completion')
local reset=f.driver.snapshot();check(reset.appliedKinds['artifact-content']==0 and reset.probedKinds.chat==0,'new transaction resets kind evidence')
f.driver.cancel()
f=scanFixture();f.adapter.result=function(_,nonce,marker)return {marker=marker,nonce=nonce,ok=true,kind='https://private.example/unknown',documentId=string.rep('a',32),healthy=false}end
f.driver.begin(f.request);f.scanUntil('complete')
check(f.driver.snapshot().reason=='probe-result-invalid' and f.driver.snapshot().probedKinds['https://private.example/unknown']==nil,'invalid kind cannot leak into evidence map')
f=scanFixture();local sourceOptions=f.adapter.contexts
f.adapter.contexts=function(target)if f.state.command and f.state.command.type=='apply' then return nil end;return sourceOptions(target)end
f.driver.begin(f.request);f.scanUntil('complete')
check(f.driver.snapshot().reason=='contexts-menu-unavailable' and #f.state.closed==1,'frame-list menu retry failure safely closes proven source tools')
f=scanFixture({topHealthy=true});f.driver.begin(f.request);local healthyScan=f.scanUntil('complete')
check(healthyScan.ok and healthyScan.applied==2 and healthyScan.skipped==4,'healthy source skips apply and still proves tools')
f=scanFixture();f.config.probe=nil;f.config.probeTemplate='(async()=>({nonce:"__RTL_CONSOLE_NONCE__",expectedURL:__RTL_CONSOLE_EXPECTED_URL_JSON__}))()'
check(f.driver.begin(f.request),'probe template accepted');f.scanUntil('execute')
check(not f.state.payloadSource:find('__RTL_CONSOLE_EXPECTED_URL_JSON__',1,true),'probe URL JSON placeholder replaced')
f=scanFixture();f.request.sourceURL=nil;check(not f.driver.begin(f.request),'scan requires exact source URL')
for _,separator in ipairs({'\226\128\168','\226\128\169'})do
  f=scanFixture();f.request.sourceURL='https://claude.ai/new?value='..separator
  local accepted,reason=f.driver.begin(f.request)
  check(not accepted and reason=='invalid-source' and #f.state.events==0,'raw Unicode URL line separator rejected before any UI')
end
f=scanFixture();f.request.sourceURL='https://claude.ai/new?value=%E2%80%A8';check(f.driver.begin(f.request),'percent-encoded URL separator remains supported');f.driver.cancel()
f=scanFixture({jsonTitle=true,suffix=true});f.driver.begin(f.request);local suffixed=f.scanUntil('complete')
check(suffixed.ok and suffixed.applied==3,'JSON title with complete parenthesized path suffix accepted')
f=scanFixture({truncatedTitle=true});f.driver.begin(f.request);local expanded=f.scanUntil('complete')
check(expanded.ok and expanded.applied==3,'unique truncated JSON label expands to exact full button name')
check(expanded.contextExpectedEndsEllipsis==false or expanded.contextExpectedLength>0,'context diagnostics contain lengths and ellipsis flag only')
for _,options in ipairs({{truncatedTitle=true,overlapTruncated=true},{truncatedTitle=true,shorterTruncated=true}})do
  f=scanFixture(options);f.driver.begin(f.request);f.scanUntil('complete')
  check(f.driver.snapshot().reason=='context-prefix-ambiguous' and f.driver.snapshot().applied==1,'overlapping ordinary truncated prefixes fail before child apply')
end
f=scanFixture({truncatedTitle=true,wrongExpansion=true});f.driver.begin(f.request);f.scanUntil('complete')
check(f.driver.snapshot().reason=='timeout' and f.driver.snapshot().contextExpectedEndsEllipsis,'unrelated full label cannot match truncated prefix')
f=scanFixture({truncatedTitle=true});f.driver.begin(f.request)
for _=1,300 do
  f.driver.tick();f.state.now=f.state.now+0.05
  if f.driver.snapshot().phase=='paste' and f.state.command.type=='apply' and f.state.command.kind=='document' then break end
end
f.state.context=f.state.context:gsub('1790000000','1790000001');f.driver.tick()
check(f.driver.snapshot().reason=='context-changed','expanded full context is exact-pinned before command')
for _,options in ipairs({{jsonTitle=true,prefixCollision=true},{jsonTitle=true,trailingSuffix=true}})do
  f=scanFixture(options);f.driver.begin(f.request);f.scanUntil('complete')
  check(not f.driver.snapshot().ok and f.driver.snapshot().reason=='timeout','context suffix does not allow prefix collision or trailing text')
end
f=scanFixture({jsonTitle=true,suffix=true});f.driver.begin(f.request)
for _=1,300 do
  f.driver.tick();f.state.now=f.state.now+0.05
  if f.driver.snapshot().phase=='paste' and f.state.command.type=='apply' and f.state.command.kind=='document' then break end
end
local priorEvents=#f.state.events;f.state.context=f.state.context:gsub('1790000000','1790000001');f.driver.tick()
check(f.driver.snapshot().reason=='context-changed','actual suffixed label pinned before paste')
check(#f.state.events>priorEvents and f.state.events[priorEvents+1]=='restore','changed pinned label triggers cleanup without paste')
f=fixture();f.driver.begin(f.request);f.run('await-context');f.state.context='JavaScript context: fixture (1790000000-000e/)';f.run('done')
check(not f.driver.snapshot().ok and f.driver.snapshot().reason=='timeout','explicit API keeps exact label matching')
-- Run final code in a Node VM without opening any app or real UI.
scenarios=scenarios+1
local payloadModule=arg[1]:gsub('integrations/hammerspoon/claude%-console%.lua$','lib/persian/console-payload.cjs')
local js=[=[
const assert=require('node:assert/strict'),vm=require('node:vm');
const source=process.argv[1];
(async()=>{
 for(const [id,sameDocument] of [['b'.repeat(32),true],['a'.repeat(32),false],['a'.repeat(32),true]]){
  const document={},sandbox={document,window:{},console:{log(){}}};
  sandbox.window.__claudePersianConsoleDocumentV1={id,document:sameDocument?document:{}};
  const result=await vm.runInNewContext(source,sandbox);
  if(id==='a'.repeat(32)&&sameDocument){assert.equal(result.ok,true);assert.equal(sandbox.executed,true);}
  else {assert.equal(result.reason,'document-mismatch');assert.equal(sandbox.executed,undefined);}
 }
 const {buildConsolePayload}=require(process.argv[2]);
 const wrong=buildConsolePayload({kind:'chat',nonce:'n'.repeat(32),documentId:'a'.repeat(32),fonts:[]});
 const result=await vm.runInNewContext(wrong,{URL,document:{},window:{},location:{href:'https://fixture.frame.claudeusercontent.com/'},console:{log(){}}});
 assert.equal(result.ok,false);assert.equal(result.reason,'context-mismatch');
 const sourceProbe=await vm.runInNewContext(process.argv[3],{location:{href:'https://claude.ai/other'},console:{log(){}}});
 assert.equal(sourceProbe.reason,'source-mismatch');assert.equal(sourceProbe.ok,false);
 process.stdout.write('GUARDS_OK');
})().catch(error=>{process.stderr.write(error.message);process.exitCode=1;});
]=]
local function shellQuote(value)return "'"..value:gsub("'","'\\''").."'"end
local pipe=assert(io.popen('node -e '..shellQuote(js)..' '..shellQuote(guardedSource)..' '..shellQuote(payloadModule)..' '..shellQuote(sourceGuard),'r'))
local output=pipe:read('*a');local success=pipe:close()
check(success and output=='GUARDS_OK','actual JavaScript document and context guards')
-- readAllData preserves only the first item. Reject multiple items before any change.
scenarios=scenarios+1
local changes=0
local clip={types={{'public.text','public.html'}},data={['public.text']='text',['public.html']='html'},version=1}
local hs={pasteboard={allContentTypes=function()return clip.types end,readAllData=function()return clip.data end,changeCount=function()return clip.version end,
  clearContents=function()changes=changes+1;clip.types={}end,writeAllData=function()changes=changes+1;return true end}}
local native=M.nativeAdapter(hs)
local saved=native.captureClipboard();check(saved and saved.data['public.html']=='html','single item formats captured')
clip.types={{'public.text'},{'public.text'}};check(not native.captureClipboard(),'multiple items refused');check(changes==0,'multi-item refusal before any write')
clip.types={{'public.text','public.rtf'}};check(not native.captureClipboard(),'unreadable format refused');check(changes==0,'unreadable format before any write')
clip.types={};local empty=native.captureClipboard();check(empty.empty,'empty clipboard captured');check(native.restoreClipboard(empty,1),'clearContents nil return handled')
clip.version=2;check(not native.restoreClipboard(empty,1),'clipboard ownership guarded')
-- AXPress does not select a context. The driver must use Home and arrow keys.
scenarios=scenarios+1
local function node(attrs)
  local value={attrs=attrs}
  function value:attributeValue(name)return self.attrs[name]end
  function value:setAttributeValue(name,newValue)if name~='AXFocused' then self.attrs[name]=newValue end;return self end
  function value:performAction()error('option AXPress must not select context')end
  return value
end
local button=node({AXRole='AXButton',AXTitle='',AXDescription='JavaScript context: top'})
local first=node({AXRole='AXMenuItem',AXTitle='top'})
local second=node({AXRole='AXMenuItem',AXTitle='fixture'})
local promptNode=node({AXRole='AXTextArea',AXDescription='Console prompt',AXValue='',AXFocused=false})
local initialMenu=node({AXRole='AXMenu',AXChildren={first,second}})
local root=node({AXRole='AXWindow',AXChildren={button,initialMenu,promptNode}})
local appRoot=node({AXFocusedUIElement=promptNode})
local nativeApp,nativeWindow={},{}
local visible=true
function nativeApp:bundleID()return 'com.anthropic.claudefordesktop'end
function nativeApp:path()return '/Applications/Claude.app'end
function nativeApp:pid()return 123 end
function nativeApp:isFrontmost()return true end
function nativeApp:allWindows()return visible and {nativeWindow} or {}end
function nativeWindow:id()return 20 end
function nativeWindow:title()return 'Developer Tools - synthetic'end
function nativeWindow:application()return nativeApp end
function nativeWindow:close()return true end
local keys,selected={},0
local tapEnabled=false
local nativeNow=0
local nativeClipVersion,nativeClipText,nativeClipReads=999,'fixture source',0
local nativeClipTypes={{'public.utf8-plain-text'}}
local nativeHS={application={get=function()return nativeApp end,applicationForPID=function()return nativeApp end},processInfo={processID=55},
  timer={secondsSinceEpoch=function()return nativeNow end},
  pasteboard={changeCount=function()return nativeClipVersion end,allContentTypes=function()return nativeClipTypes end,
    getContents=function()nativeClipReads=nativeClipReads+1;return nativeClipText end},
  window={focusedWindow=function()return nativeWindow end},
  axuielement={windowElement=function()return root end,applicationElement=function()return appRoot end},
  eventtap={event={types={keyDown=1,flagsChanged=2,mouseMoved=3,leftMouseDown=4,rightMouseDown=5,otherMouseDown=6,scrollWheel=7},properties={eventSourceUnixProcessID=1}},
    new=function()return {start=function(self)tapEnabled=true;return self end,isEnabled=function()return tapEnabled end,stop=function()tapEnabled=false end}end,
    keyStroke=function(modifiers,key,_,target)
    check(target==nativeApp,'key targets exact app');keys[#keys+1]=key
    if key=='home' then selected=1 elseif key=='down' then selected=selected+1
    elseif key=='return' then
      local present=false;for _,child in ipairs(root.attrs.AXChildren or {})do if child==initialMenu then present=true end end
      if appRoot.attrs.AXFocusedUIElement==button and not present then root.attrs.AXChildren={button,initialMenu,promptNode}
      else button.attrs.AXDescription='JavaScript context: '..(selected==2 and 'fixture' or 'top') end
    elseif key=='`' then check(modifiers[1]=='ctrl','official console focus shortcut');promptNode.attrs.AXFocused=true;button.attrs.AXFocused=false;appRoot.attrs.AXFocusedUIElement=promptNode
    elseif key=='space' then root.attrs.AXChildren={button,initialMenu,promptNode} end
  end}}
native=M.nativeAdapter(nativeHS)
local target={id=20,title='Developer Tools - synthetic',pid=123}
check(native.beginTracking()==true and native.isTracking(),'native monitor active')
local originalChildren=root.attrs.AXChildren
root.attrs.AXChildren={button,promptNode}
function button:performAction()return false end
check(not native.openContexts(target),'AXPress false is a rejected action')
function button:performAction()return self end
check(native.openContexts(target)=='pending','AXPress accepted object waits for actual menu')
root.attrs.AXChildren=originalChildren
check(native.openContexts(target)==true,'actual menu acknowledgement completes opening')
root.attrs.AXChildren={promptNode}
check(native.openContexts(target)=='pending','native missing context button returns pending')
root.attrs.AXChildren={button}
check(native.promptValue(target)==nil and native.focusPrompt(target)=='pending','native missing prompt returns pending')
root.attrs.AXChildren=originalChildren
root.attrs.AXChildren={button,promptNode}
local originalSetFocus=button.setAttributeValue
local focusRequested=false
function button:setAttributeValue(name,value)
  if name=='AXFocused' and value==true then focusRequested=true else self.attrs[name]=value end
  return self
end
keys={};check(native.openContexts(target)=='pending' and #keys==0,'first AXPress has no immediate key fallback')
check(native.openContexts(target)=='pending' and focusRequested and #keys==0,'button focus request waits for next tick')
check(native.openContexts(target)=='pending' and #keys==0,'delayed focus does not send Return into prompt')
button.attrs.AXFocused=true;appRoot.attrs.AXFocusedUIElement=button;promptNode.attrs.AXFocused=false
check(native.openContexts(target)=='pending' and #keys==1 and keys[1]=='return','Return opens verified button only after delayed focus')
check(native.openContexts(target)==true and #native.contexts(target)==2,'native opening succeeds only after menu exists')
root.attrs.AXChildren={button,promptNode};button.setAttributeValue=originalSetFocus
button.attrs.AXFocused=false;promptNode.attrs.AXFocused=true;appRoot.attrs.AXFocusedUIElement=promptNode;keys={}
check(native.openContexts(target)=='pending','new menu opening starts asynchronously')
check(native.openContexts(target)=='pending' and native.openContexts(target)=='pending' and #keys==0,'failed button focus never sends Return into prompt')
local menuMeta=native.menuDiagnostics(target)
check(menuMeta.menuButtonFocusedType=='boolean' and not menuMeta.menuActiveIsButton and menuMeta.menuPromptIsActive,'menu focus diagnostics are bounded metadata')
nativeNow=2.01;local opened,openReason=native.openContexts(target)
check(not opened and openReason=='context-button-open-timeout','missing button focus fails after bounded two seconds')
native.endTracking();check(native.beginTracking(),'native tracking can restart after bounded menu failure');nativeNow=0
check(native.contexts(target)==nil,'no menu means no stale item fallback')
root.attrs.AXChildren=originalChildren;keys={};promptNode.attrs.AXFocused=false
check(native.selectContext(target,{title='fixture'}),'keyboard context selection')
check(table.concat(keys,',')=='home,down,return','Home Down Return sequence')
check(native.contextLabel(target)=='JavaScript context: fixture','actual context title confirmed')
check(not native.promptFocused(target),'stale AX focused element insufficient')
check(native.focusPrompt(target) and native.promptFocused(target),'console shortcut establishes verified focus')
local beforeReplacement=#keys
check(not native.paste(target,5) and not native.execute(target,5),'native clipboard version checked at input boundary')
check(#keys==beforeReplacement,'native replaced clipboard emits no key')
local keyCount=#keys;tapEnabled=false
check(not native.paste(target) and not native.execute(target),'native disabled monitor prevents paste and Return')
check(#keys==keyCount,'native disabled monitor emits no key');tapEnabled=true
-- Verify each copy keystroke against the current context and lease.
scenarios=scenarios+1
local inputLabel=native.contextLabel(target)
check(native.selectSourceForVerification(target,999,inputLabel,0) and keys[#keys]=='a','native CmdA targets owned prompt')
check(native.copySelectedSource(target,999,inputLabel,0) and keys[#keys]=='c','native CmdC is a separate guarded action')
check(native.pollCopiedSource(target,999,inputLabel,0)==nil and nativeClipReads==0,'native unchanged clipboard never read as copy receipt')
nativeClipVersion=1000
local copied=native.pollCopiedSource(target,999,inputLabel,0)
check(copied.version==1000 and copied.contents=='fixture source' and nativeClipReads==1,'native sole delta returns full clipboard text')
nativeClipVersion=1001;local beforeRead=nativeClipReads
check(native.pollCopiedSource(target,999,inputLabel,0).conflict and nativeClipReads==beforeRead,'native multi-change copy race never reads new user data')
nativeClipVersion=1000;local beforeKeys=#keys
check(not native.copySelectedSource(target,999,inputLabel,0) and #keys==beforeKeys,'native lease loss blocks CmdC')
check(not native.selectSourceForVerification(target,1000,'JavaScript context: foreign',0) and #keys==beforeKeys,'native foreign context blocks CmdA')
appRoot.attrs.AXFocusedUIElement=button
check(not native.selectSourceForVerification(target,1000,inputLabel,0) and #keys==beforeKeys,'native foreign focused element blocks CmdA')
appRoot.attrs.AXFocusedUIElement=promptNode
check(native.collapseSourceSelection(target,1000,inputLabel,0) and keys[#keys]=='right','native collapse uses Right only')
promptNode.attrs.AXSelectedText='selected'
check(native.sourceSelectionEmpty(target)==false,'native selected text prevents execute confirmation')
promptNode.attrs.AXSelectedText='';check(native.sourceSelectionEmpty(target)==true,'native empty selection confirmed')
promptNode.attrs.AXSelectedText=nil;promptNode.attrs.AXSelectedTextRange={_location=99,_length=0}
check(native.sourceSelectionEmpty(target)==true,'native documented range can confirm collapse')
promptNode.attrs.AXSelectedTextRange={location=0,length=5};check(native.sourceSelectionEmpty(target)==false,'nonzero selection range rejected')
promptNode.attrs.AXSelectedTextRange=nil;check(native.sourceSelectionEmpty(target)==nil,'unknown selection shape fails closed')
local originalGetter=nativeHS.pasteboard.getContents
nativeHS.pasteboard.getContents=function()nativeClipVersion=1001;return 'racing value'end
local raced=native.pollCopiedSource(target,999,inputLabel,0)
check(raced.conflict and raced.contents==nil,'native version change during clipboard read invalidates receipt')
nativeHS.pasteboard.getContents=originalGetter;nativeClipVersion=1000
nativeClipTypes={{'public.text'},{'public.text'}};beforeRead=nativeClipReads
check(native.pollCopiedSource(target,999,inputLabel,0).conflict and nativeClipReads==beforeRead,'native multi-item copy refused without reading')
nativeClipTypes={{'public.utf8-plain-text'}};nativeClipVersion=999
check(native.closeTools(target,123)=='pending','native close is asynchronous')
check(not native.toolsClosed(target,123),'native still open is not success');visible=false
check(native.toolsClosed(target,123),'native absence confirms close')
-- A fullscreen window may appear only in AXFocusedWindow.
scenarios=scenarios+1
function root:asHSWindow()return nativeWindow end
appRoot.attrs.AXFocusedWindow=root;appRoot.attrs.AXWindows={root}
nativeHS.window.focusedWindow=function()return nil end
check(native.identity().focusedWindow==20,'fullscreen AX focused fallback')
check(#native.windows()==1 and native.windows()[1].pid==123,'fullscreen AX windows fallback')
check(not native.toolsClosed(target,123),'AX-only existing tools never reported closed')
function nativeWindow:close()return false end
check(not native.closeTools(target,123),'native rejected close does not report pending success')
function nativeWindow:close()return true end
-- A real context menu can be a group. Each direct child has an ordinal.
scenarios=scenarios+1
local function text(value)return node({AXRole='AXStaticText',AXValue=value})end
local function row(title,detail)return node({AXRole='AXGroup',AXChildren={node({AXRole='AXGroup',AXChildren={text(title),text(detail)}})}})end
local rows={row('top','claude.ai'),row('DevTools Performance Metrics','claude.ai'),row('Electron Isolated Context','claude.ai'),
  row('opaque-frame','claude.ai'),row('synthetic-document','fixture.frame.claudeusercontent.com'),row('about:srcdoc','IFrame'),row('⚙ completion-gzip','claude.ai')}
local menu=node({AXRole='AXMenu',AXChildren=rows})
root.attrs.AXChildren={button,promptNode,menu}
local options=native.contexts(target)
check(#options==7 and options[5].title=='synthetic-document','direct menu groups parsed once each')
check(options[5].index==5 and options[6].index==6,'ordinals include skipped worlds')
check(options[1].frame and options[4].frame and options[5].frame and options[6].frame,'ordinary frames recognized')
check(not options[2].frame and not options[3].frame and not options[7].frame,'isolated metrics worker rows rejected')
local contextDiagnostic=native.contextDiagnostics(target)
check(contextDiagnostic.menuCount==1 and contextDiagnostic.childCount==7,'context diagnostics report shape only')
check(contextDiagnostic.rows[6].srcdocPrefix and contextDiagnostic.rows[6].staticTexts==2,'context diagnostics identify split srcdoc row')
for _,entry in ipairs(contextDiagnostic.rows)do check(entry.title==nil and entry.details==nil and entry.text==nil,'context diagnostics omit text')end
promptNode.attrs.AXValue='\n';local promptDiagnostic=native.promptDiagnostics(target)
check(promptDiagnostic.valueType=='string' and promptDiagnostic.length==1 and promptDiagnostic.whitespaceOnly,'prompt metrics diagnose newline without exposing content')
promptNode.attrs.AXChildren={node({AXRole='AXGroup',AXChildren={}})}
check(native.promptValue(target)=='','verified empty LF and one empty line-group normalize to empty')
for _,value in ipairs({' ','\n\n','\r\n','known text','known text\n'})do
  promptNode.attrs.AXValue=value;check(native.promptValue(target)==value,'user whitespace and text never trimmed')
end
promptNode.attrs.AXValue='\n';promptNode.attrs.AXChildren={node({AXRole='AXGroup',AXChildren={text('inconsistent user text')}})}
check(native.promptValue(target)=='\n','LF with actual child text is not empty sentinel')
promptNode.attrs.AXChildren={node({AXRole='AXGroup',AXChildren={}}),node({AXRole='AXGroup',AXChildren={}})}
check(native.promptValue(target)=='\n','two line-groups never qualify as empty sentinel')
promptNode.attrs.AXChildren={node({AXRole='AXStaticText',AXValue=''})}
check(native.promptValue(target)=='\n','unverified child role never qualifies as empty sentinel')
promptNode.attrs.AXChildren=nil;check(native.promptValue(target)=='\n','missing line shape never qualifies as empty sentinel')
promptNode.attrs.AXValue='a\n b';promptNode.attrs.AXChildren={node({AXRole='AXGroup',AXChildren={text('a')}}),node({AXRole='AXGroup',AXChildren={text(' b')}})}
local reconstructed=native.promptReconstructionDiagnostics(target,'a\n b')
check(reconstructed.allGroups and reconstructed.reconstructedEqual and reconstructed.lineCount==2,'group reconstruction matches exact lines')
promptNode.attrs.AXChildren={node({AXRole='AXGroup',AXChildren={text('a\226\128\139')}})}
reconstructed=native.promptReconstructionDiagnostics(target,'a')
check(not reconstructed.reconstructedEqual and reconstructed.reconstructedBytes[1]==226,'first-difference byte metadata only')
check(reconstructed.markerCandidates[1].count==1 and reconstructed.markerCandidates[1].equalAfterRemoval,'Unicode marker candidate is diagnostic only')
check(native.promptValue(target)=='a\n b','reconstruction diagnostics do not alter source or normalize text')
promptNode.attrs.AXChildren=nil
promptNode.attrs.AXValue={synthetic='hidden'};promptDiagnostic=native.promptDiagnostics(target)
check(promptDiagnostic.valueType=='table' and promptDiagnostic.fields==1 and promptDiagnostic.text==nil,'attributed prompt shape only')
promptNode.attrs.AXValue=''
local hidden=node({AXRole='AXMenu',AXVisible=false,AXChildren={row('stale','claude.ai')}})
root.attrs.AXChildren={button,promptNode,menu,hidden}
check(#native.contexts(target)==7,'AXVisible false is preserved and stale hidden menu ignored')
keys={};check(native.selectContext(target,options[5]),'native group selection')
check(table.concat(keys,',')=='home,down,down,down,down,return','native selection keeps actual ordinal')
rows[#rows+1]=row('synthetic-document','fixture.frame.claudeusercontent.com')
local duplicated,duplicateReason=native.contexts(target)
check(not duplicated and duplicateReason=='duplicate-context','duplicate ordinary group fails safely')
rows[#rows]=nil;rows[#rows+1]=row('DevTools Performance Metrics','claude.ai')
check(#native.contexts(target)==8,'duplicate excluded world does not block frame scan')
rows[#rows]=row('synthetic-document','other.frame.claudeusercontent.com')
local duplicateName,duplicateNameReason=native.contexts(target)
check(not duplicateName and duplicateNameReason=='duplicate-context','same ordinary title with different origin also refused')
appRoot.attrs.AXFocusedWindow=nil;appRoot.attrs.AXWindows={}
check(native.toolsClosed(target,123),'native close verified after AX disappearance too')
return {ok=true,assertions=assertions,scenarios=scenarios}
