-- Experimental native adapter for claude-console-direct.lua. No startup hook.
-- capture() must run BEFORE a trusted bootstrap creates a console. probeCode()
-- returns a source-guarded probe for that bootstrap to execute and verify; bind()
-- reads its real receipt itself. No caller-provided proof table is accepted.
-- This adapter never opens consoles, activates apps, uses the clipboard, or quits apps.
local M={}
local bundle,path='com.anthropic.claudefordesktop','/Applications/Claude.app'
local function id(v)return type(v)=='string' and #v==32 and v:match('^[a-f0-9]+$')~=nil end
local function quote(s)return '"'..s:gsub('[%z\1-\31\\"]',function(c)return c=='"' and '\\"' or c=='\\' and '\\\\' or string.format('\\u%04x',c:byte())end):gsub('\226\128\168','\\u2028'):gsub('\226\128\169','\\u2029')..'"'end
local function kind(url)
 if type(url)~='string' or url:find('[%z\1-\31\127]') or url:find('\226\128[\168\169]')then return nil end
 if url=='about:srcdoc'then return 'document'end
 if url:match('^https://[a-z0-9-]+%.frame%.claudeusercontent%.com/')then return 'artifact-content'end
 local shell=url:match('^file:///Applications/Claude%.app/Contents/Resources/app%.asar/%.vite/renderer/([^/]+)/')
 if shell=='main_window' or shell=='quick_window' or shell=='about_window' or shell=='find_in_page'then return 'shell'end
 local tail=url:match('^https://claude%.ai(.*)$')
 if not tail or tail~='' and not tail:match('^[/?#]')then return nil end
 local route=tail:match('^([^?#]*)')or''
 for _,p in ipairs({'auth','oauth','login','api'})do if route=='/'..p or route:sub(1,#p+2)=='/'..p..'/'then return nil end end
 return route:sub(1,15)=='/code/artifact/' and 'artifact' or 'chat'
end
function M.new(hs)
 local captures,ownerships,handles={},{},{}
 local function attr(e,name)if not e then return nil end;local ok,v=pcall(function()return e:attributeValue(name)end);return ok and v or nil end
 local function app(pid)
  local a;if pid then a=hs.application.applicationForPID(pid)else a=hs.application.get(bundle)end
  if a and (not pid or a:pid()==pid) and a:bundleID()==bundle and a:path()==path then return a end
 end
 local function tree(root,predicate)
  local stack,found,n={root},{},0
  while #stack>0 and n<8000 do
   local e=table.remove(stack);n=n+1
   if predicate(e)then found[#found+1]=e end
   for _,c in ipairs(attr(e,'AXChildren')or{})do stack[#stack+1]=c end
  end
  if #stack>0 then return nil end
  return found
 end
 local function windows(a)
  local out={}
  local function add(w,e)
   if w and w:application():pid()==a:pid()then out[w:id()]={window=w,element=e or hs.axuielement.windowElement(w),title=w:title()}end
  end
  for _,w in ipairs(a:allWindows()or{})do add(w)end
  local root=hs.axuielement.applicationElement(a)
  for _,e in ipairs(attr(root,'AXWindows')or{})do add(e:asHSWindow(),e)end
  local e=attr(root,'AXFocusedWindow');if e then add(e:asHSWindow(),e)end
  return out
 end
 local function url(e)
  local value=attr(e,'AXURL');if type(value)=='table'then value=rawget(value,'url')end
  return type(value)=='string' and value or nil
 end
 local function source(record,all)
  local s=all[record.sourceWindowId];if not s then return false end
  local areas=tree(s.element,function(e)return attr(e,'AXRole')=='AXWebArea' and url(e)==record.sourceURL end)
  return areas and #areas==1 and areas[1]==record.sourceElement
 end
 local function console(record,all)
  local w=all[record.toolsWindowId]
  if not w or w.title~=record.toolsTitle then return nil end
  local prompts=tree(w.element,function(e)return attr(e,'AXRole')=='AXTextArea' and attr(e,'AXDescription')=='Console prompt'end)
  local contexts=tree(w.element,function(e)
   if attr(e,'AXRole')~='AXButton'then return false end
   for _,name in ipairs({'AXTitle','AXDescription','AXValue'})do local v=attr(e,name);if type(v)=='string' and v:match('^JavaScript context: ')then return true end end
   return false
  end)
  if not prompts or #prompts~=1 or not contexts or #contexts~=1 then return nil end
  local label
  for _,name in ipairs({'AXTitle','AXDescription','AXValue'})do local v=attr(contexts[1],name);if type(v)=='string' and v:match('^JavaScript context: ')then label=v;break end end
  return {window=w.window,element=w.element,prompt=prompts[1],context=label}
 end
 local function emptyValue(prompt)
  local value=attr(prompt,'AXValue')
  if value=='\n' then
   local children=attr(prompt,'AXChildren')
   local texts=tree(prompt,function(e)return attr(e,'AXRole')=='AXStaticText'end)
   if type(children)=='table' and #children==1 and attr(children[1],'AXRole')=='AXGroup' and texts and #texts==0 then return ''end
  end
  return value
 end
 local function receipt(c,marker,nonce,sequence)
  local rows=tree(c.element,function(e)return attr(e,'AXRole')=='AXStaticText'end)
  if not rows then return nil end
  local found
  for _,e in ipairs(rows)do
   local value=attr(e,'AXValue')
   if type(value)=='string' and #value<=2048 and value:sub(1,1)=='{' and value:find(marker,1,true)then
    local ok,r=pcall(hs.json.decode,value)
    if ok and type(r)=='table' and r.marker==marker and r.nonce==nonce and (not sequence or r.sequence==sequence)then
     if found then return nil end
     found=r
    end
   end
  end
  return found
 end
 local function stopTracking(r)
  if r.tap then r.tap:stop();r.tap=nil end
  if r.observer then r.observer:stop();r.observer=nil end
 end
 local function inspectRecord(r)
  if not r or r.released or r.invalid or not r.tap or r.tap:isEnabled()~=true or not r.observer or r.observer:isRunning()~=true then return nil end
  local a=app(r.pid);if not a then return nil end
  local all=windows(a);if not source(r,all)then return nil end
  local c=console(r,all)
  if not c or c.context~=r.contextId or c.prompt~=r.prompt then return nil end
  return a,c
 end
 local api={}
 function api.capture(sourceWindowId,expectedURL)
  local a=app();if not a or not kind(expectedURL)then return nil,'invalid-source'end
  local all=windows(a);local s=all[sourceWindowId];if not s then return nil,'source-missing'end
  local seen={};for key,w in pairs(all)do seen[key]=true;if type(w.title)=='string' and w.title:match('^Developer Tools %- ')then return nil,'existing-tools'end end
  local areas=tree(s.element,function(e)return attr(e,'AXRole')=='AXWebArea' and url(e)==expectedURL end)
  if not areas or #areas~=1 then return nil,'source-ambiguous'end
  local nonce=(hs.host.uuid():gsub('-','')):lower();if not id(nonce)then return nil,'nonce-unavailable'end
  local token={};captures[token]={pid=a:pid(),sourceWindowId=sourceWindowId,sourceURL=expectedURL,sourceElement=areas[1],seen=seen,nonce=nonce,kind=kind(expectedURL)}
  return token
 end
 function api.probeCode(token)
  local r=captures[token];if not r then return nil end
  local receiptBase='{marker:"CDT_DIRECT_HANDOFF",nonce:'..quote(r.nonce)..',kind:'..quote(r.kind)
  return '(()=>{if(location.href!=='..quote(r.sourceURL)..'){console.log(JSON.stringify('..receiptBase..',ok:false}));return;}let r=window.__claudePersianConsoleDocumentV1;if(r&&(r.document!==document||!(/^[a-f0-9]{32}$/.test(r.id)))){console.log(JSON.stringify('..receiptBase..',ok:false}));return;}if(!r){const bytes=crypto.getRandomValues(new Uint8Array(16));r={document,identity:JSON.stringify({url:location.href,parent:null}),id:Array.from(bytes,x=>x.toString(16).padStart(2,"0")).join("")};window.__claudePersianConsoleDocumentV1=r;}console.log(JSON.stringify('..receiptBase..',ok:true,documentId:r.id}));})()'
 end
 function api.bind(token,toolsWindowId)
  local r=captures[token];if not r then return nil,'invalid-capture'end
  local a=app(r.pid);if not a then return nil,'process-changed'end
  local all=windows(a);if r.seen[toolsWindowId] or not source(r,all)then return nil,'ownership-unproven'end
  r.toolsWindowId=toolsWindowId;r.toolsTitle='Developer Tools - '..r.sourceURL
  local c=console(r,all);if not c or emptyValue(c.prompt)~=''then return nil,'console-not-ready'end
  local proof=receipt(c,'CDT_DIRECT_HANDOFF',r.nonce)
  if not proof or proof.ok~=true or proof.kind~=r.kind or not id(proof.documentId)then return nil,'probe-unverified'end
  r.documentId=proof.documentId;r.contextId=c.context;r.prompt=c.prompt;r.interactionVersion=0;r.initialVersion=0
  local ok=pcall(function()
   assert(type(hs.processInfo.processID)=='number')
   local types=hs.eventtap.event.types
   local properties=hs.eventtap.event.properties
   assert(type(properties)=='table' and type(properties.eventSourceUnixProcessID)=='number','event source property required')
   for _,name in ipairs({'keyDown','flagsChanged','leftMouseDown','rightMouseDown','otherMouseDown','scrollWheel'})do
    assert(type(types[name])=='number','required event type unavailable')
   end
   r.tap=hs.eventtap.new({types.keyDown,types.flagsChanged,types.leftMouseDown,types.rightMouseDown,types.otherMouseDown,types.scrollWheel},function(event)
    local worked=pcall(function()
     if r.released then return end
     if event:getProperty(hs.eventtap.event.properties.eventSourceUnixProcessID)==hs.processInfo.processID then return end
     local front=hs.application.frontmostApplication()
     if front and front:pid()==r.pid then
      local focused=attr(hs.axuielement.applicationElement(a),'AXFocusedWindow')
      local w=focused and focused:asHSWindow()
      if not w or w:id()==r.toolsWindowId then r.interactionVersion=r.interactionVersion+1 end
     end
    end)
    if not worked then r.invalid=true end
    return false
   end):start()
   assert(r.tap:isEnabled()==true)
   r.observer=hs.axuielement.observer.new(r.pid)
   r.observer:callback(function(_,_,name)if not r.released and (name=='AXLoadComplete' or name=='AXUIElementDestroyed')then r.invalid=true end end)
   local function watch(element,event)
    local registered=r.observer:addWatcher(element,event)
    assert(registered~=nil and registered~=false,'required lifecycle watcher unavailable')
   end
   watch(r.sourceElement,'AXLoadComplete');watch(r.sourceElement,'AXUIElementDestroyed')
   watch(c.element,'AXUIElementDestroyed');r.observer:start();assert(r.observer:isRunning()==true)
  end)
  if not ok then stopTracking(r);return nil,'tracking-unavailable'end
  captures[token]=nil;local ownership={};ownerships[ownership]=r;return ownership
 end
 function api.claim(ownership)
  local r=ownerships[ownership];if not r then return nil end
  ownerships[ownership]=nil
  local _,c=inspectRecord(r)
  if not c or r.interactionVersion~=0 or emptyValue(c.prompt)~=''then stopTracking(r);return nil end
  local handle={};handles[handle]=r;return handle
 end
 function api.inspect(handle)
  local r=handles[handle];local a,c=inspectRecord(r);if not a then return nil end
  return {owned=true,pid=r.pid,bundle=bundle,path=path,sourceWindowId=r.sourceWindowId,toolsWindowId=r.toolsWindowId,contextId=r.contextId,documentId=r.documentId,sourceURL=r.sourceURL,interactionVersion=r.interactionVersion}
 end
 function api.now()return hs.timer.secondsSinceEpoch()end
 function api.promptValue(handle)local _,c=inspectRecord(handles[handle]);return c and emptyValue(c.prompt)or nil end
 function api.writePrompt(handle,expected,value)
  local r=handles[handle];local _,c=inspectRecord(r)
  if not c or r.interactionVersion~=r.initialVersion or emptyValue(c.prompt)~=expected or type(value)~='string' or #value>14000 or c.prompt:isAttributeSettable('AXValue')~=true then return false end
  local result=c.prompt:setAttributeValue('AXValue',value);return result~=nil and result~=false
 end
 function api.focusPrompt(handle)
  local r=handles[handle];local _,c=inspectRecord(r);if not c or r.interactionVersion~=r.initialVersion then return false end
  local result=c.prompt:setAttributeValue('AXFocused',true);return result~=nil and result~=false
 end
 function api.execute(handle,expected)
  local r=handles[handle];local a,c=inspectRecord(r)
  if not a or r.interactionVersion~=r.initialVersion or emptyValue(c.prompt)~=expected then return false end
  if attr(c.prompt,'AXFocused')~=true or attr(hs.axuielement.applicationElement(a),'AXFocusedUIElement')~=c.prompt then return 'pending'end
  -- All guards are repeated inside the same operation immediately before Return.
  local a2,c2=inspectRecord(r)
  if not a2 or c2.prompt~=c.prompt then return false end
  local sameCode=emptyValue(c2.prompt)==expected
  local localFocus=attr(c2.prompt,'AXFocused')==true and attr(hs.axuielement.applicationElement(a2),'AXFocusedUIElement')==c2.prompt
  if not sameCode or not localFocus or r.interactionVersion~=r.initialVersion then return false end
  hs.eventtap.keyStroke({},'return',0,a2);return true
 end
 function api.receipt(handle,nonce,sequence)
  local r=handles[handle];local _,c=inspectRecord(r);if not c then return nil end
  local result=receipt(c,'CDT_DIRECT_RECEIPT',nonce,sequence)
  if result and result.documentId==r.documentId then r.lastReceipt=result end
  return result
 end
 function api.release(handle,close)
  local r=handles[handle];if not r then return false end
  if close then
   -- No app activation, Command+W, or ownership fallback is permitted here.
   local _,c=inspectRecord(r)
   if not c or r.interactionVersion~=r.initialVersion or emptyValue(c.prompt)~=''or not r.lastReceipt or r.lastReceipt.ok~=true or r.lastReceipt.documentId~=r.documentId then return false end
   if c.window:application():pid()~=r.pid or c.window:id()~=r.toolsWindowId or c.window:title()~=r.toolsTitle then return false end
   local _,latest=inspectRecord(r)
   if not latest or latest.prompt~=c.prompt then return false end
   local stillEmpty=emptyValue(latest.prompt)==''
   if not stillEmpty or r.interactionVersion~=r.initialVersion then return false end
   if c.window:close()~=true then return false end
   -- An asynchronous close is conservatively reported as incomplete. The caller
   -- must retain a cleanup warning; an accepted close request is not proof of close.
   local after=app(r.pid);if after and windows(after)[r.toolsWindowId]then return false end
  end
  r.released=true;stopTracking(r);handles[handle]=nil;return true
 end
 function api.discard(token)
  local r=captures[token]or ownerships[token]
  if r then r.released=true;stopTracking(r);captures[token]=nil;ownerships[token]=nil;return true end
  return false
 end
 return api
end
return M
