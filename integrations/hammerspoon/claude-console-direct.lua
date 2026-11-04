-- Experimental dispatch into an explicitly handed-off, newly owned console.
-- No native adapter is loaded by this module. No startup hook is provided.
-- The stable watcher does not use this module.
-- Adapter methods must target the handed-off console atomically, without activating apps:
-- claim(capability), inspect(handle), promptValue(handle), writePrompt(handle,expected,value),
-- focusPrompt(handle), execute(handle,expected), receipt(handle,nonce,sequence), release(handle,close).
-- inspect returns owned, pid, bundle, path, sourceWindowId, toolsWindowId, contextId,
-- documentId, sourceURL, and interactionVersion. interactionVersion tracks external console interaction,
-- not unrelated keyboard/mouse activity in another app. Claim must verify a fresh console,
-- an empty prompt, and a source/document receipt; caller-supplied metadata is not proof.
-- release(handle,true) must recheck owned PID/window/context/document identity and an
-- empty prompt atomically before closing. It must never activate the app. On refusal,
-- leave the console open. release(handle,false) releases tracking without UI mutation.
local M={}
local function id(v)return type(v)=='string' and #v==32 and v:match('^[a-f0-9]+$')~=nil end
local function integer(v)return type(v)=='number' and v>=1 and v%1==0 end
local function quote(v)
 return '"'..v:gsub('[%z\1-\31\\"]',function(c)
  if c=='"' then return '\\"' elseif c=='\\' then return '\\\\' end
  return string.format('\\u%04x',c:byte())
 end):gsub('\226\128\168','\\u2028'):gsub('\226\128\169','\\u2029')..'"'
end
local function sourceURL(value)
 if type(value)~='string' or value:find('[%z\1-\31\127]') or value:find('\226\128[\168\169]') then return false end
 if value=='about:srcdoc' then return true end
 if value:match('^https://[a-z0-9-]+%.frame%.claudeusercontent%.com/') then return true end
 local shell=value:match('^file:///Applications/Claude%.app/Contents/Resources/app%.asar/%.vite/renderer/([^/]+)/')
 if shell=='main_window' or shell=='quick_window' or shell=='about_window' or shell=='find_in_page'then return true end
 local tail=value:match('^https://claude%.ai(.*)$')
 if not tail or tail~='' and not tail:match('^[/?#]') then return false end
 local path=tail:match('^([^?#]*)')or''
 for _,part in ipairs({'auth','oauth','api','login'})do if path=='/'..part or path:sub(1,#part+2)=='/'..part..'/'then return false end end
 return true
end
local function eligible(s)
 return type(s)=='table' and s.owned==true and s.bundle=='com.anthropic.claudefordesktop'
  and s.path=='/Applications/Claude.app' and integer(s.pid) and integer(s.sourceWindowId)
  and integer(s.toolsWindowId) and type(s.contextId)=='string' and #s.contextId>0
  and id(s.documentId) and sourceURL(s.sourceURL) and type(s.interactionVersion)=='number'
end
-- Build data commands without eval, source concatenation from data, or replacing existing globals.
-- applyBody is trusted repository code, not user text. It can use window[namespace].chunks.join('').
function M.dataPlan(namespace,nonce,data,applyBody)
 assert(type(namespace)=='string' and #namespace<=64 and namespace:match('^__cdt_[a-zA-Z0-9_]+$'),'invalid namespace')
 assert(id(nonce),'invalid nonce')
 assert(type(data)=='string' and #data<=262144 and data:match('^[A-Za-z0-9+/=]*$'),'invalid data')
 assert(type(applyBody)=='string' and #applyBody>0 and #applyBody<=10000,'invalid apply body')
 local ref='window['..quote(namespace)..']'
 local owned=ref..'&&'..ref..'.owner==='..quote(nonce)
 local commands={'if(Object.prototype.hasOwnProperty.call(window,'..quote(namespace)..'))throw Error("namespace-exists");'..ref..'={owner:'..quote(nonce)..',chunks:[]};'}
 for offset=1,#data,6000 do commands[#commands+1]='if(!('..owned..'))throw Error("namespace-changed");'..ref..'.chunks.push('..quote(data:sub(offset,offset+5999))..');' end
 commands[#commands+1]='if(!('..owned..'))throw Error("namespace-changed");'..applyBody
 local cleanup='if('..owned..')delete window['..quote(namespace)..'];'
 return {commands=commands,cleanup=cleanup}
end
function M.new(config,adapter)
 config=config or {}
 local timeout=config.timeout or 15
 assert(type(timeout)=='number' and timeout>0 and timeout<=60,'invalid timeout')
 local totalTimeout=config.totalTimeout or 120
 assert(type(totalTimeout)=='number' and totalTimeout>=timeout and totalTimeout<=300,'invalid total timeout')
 for _,name in ipairs({'now','claim','inspect','promptValue','writePrompt','focusPrompt','execute','receipt','release'})do assert(type(adapter[name])=='function','missing adapter method: '..name)end
 local tx,used=nil,{}
 local last={experimental=true,phase='idle',ok=false,completed=0,cleanupRequired=false}
 local function snapshot()local out={};for k,v in pairs(last)do out[k]=v end;return out end
 local function release(close)
  local ok,result=pcall(adapter.release,tx.handle,close)
  last.released=ok and result==true
  if not last.released then
   last.cleanupRequired=true;last.ok=false;last.phase='stopped';last.reason=last.reason or 'release-failed'
   -- An incomplete native close must not leak event taps or observers. Keep the
   -- cleanup warning, but release tracking without any further UI mutation.
   if close then pcall(adapter.release,tx.handle,false)end
  end
 end
 local function fail(reason)
  last.phase='stopped';last.ok=false;last.reason=reason;last.cleanupRequired=tx and (tx.mayHaveBuffers or tx.promptPending) or false
  if tx then
   -- Never clear a changed prompt or close a console after any guard failure.
   release(false);tx=nil
  end
  return snapshot()
 end
 local fields={'pid','bundle','path','sourceWindowId','toolsWindowId','contextId','documentId','sourceURL','interactionVersion'}
 local function guard()
  local current=adapter.inspect(tx.handle)
  if not eligible(current)then return 'ownership-lost' end
  for _,key in ipairs(fields)do if current[key]~=tx.identity[key]then return 'target-changed' end end
 end
 local function source(body,sequence)
  local header='const d=document;const r=window.__claudePersianConsoleDocumentV1;'
   ..'const valid=()=>location.href==='..quote(tx.identity.sourceURL)..'&&document===d&&window.__claudePersianConsoleDocumentV1===r&&!!r&&r.document===document&&r.id==='..quote(tx.identity.documentId)..';'
  local receipt='{marker:"CDT_DIRECT_RECEIPT",nonce:'..quote(tx.nonce)..',sequence:'..sequence..',documentId:'..quote(tx.identity.documentId)
  return '(async()=>{'..header..'if(!valid()){console.log(JSON.stringify('..receipt..',ok:false}));return;}'
   ..'try{await(async()=>{'..body..'})();console.log(JSON.stringify('..receipt..',ok:valid()}));}'
   ..'catch(e){console.log(JSON.stringify('..receipt..',ok:false}));}})()'
 end
 local function prepare(body)
  tx.code=source(body,tx.sequence);tx.stage='write';tx.deadline=adapter.now()+timeout
  last.phase=tx.cleaning and 'cleanup' or 'writing'
 end
 local function begin(request)
  if tx then return false,'busy' end
  if type(request)~='table' or not id(request.nonce) or used[request.nonce] then return false,'invalid-or-reused-nonce' end
  if type(request.plan)~='table' or type(request.plan.commands)~='table' or #request.plan.commands<1 or #request.plan.commands>48
   or type(request.plan.cleanup)~='string' or #request.plan.cleanup>2048 then return false,'invalid-plan' end
  local commands={}
  for index,body in ipairs(request.plan.commands)do
   if type(body)~='string' or #body<1 or #body>12000 then return false,'invalid-command' end
   commands[index]=body
  end
  local handle=adapter.claim(request.ownership)
  if not handle then return false,'ownership-required' end
  local identity=adapter.inspect(handle)
  if not eligible(identity) or adapter.promptValue(handle)~='' then adapter.release(handle,false);return false,'invalid-handoff' end
  local copy={};for _,key in ipairs(fields)do copy[key]=identity[key]end
  used[request.nonce]=true
  tx={handle=handle,identity=copy,nonce=request.nonce,commands=commands,cleanup=request.plan.cleanup,index=1,sequence=1,mayHaveBuffers=false,totalDeadline=adapter.now()+totalTimeout}
  last={experimental=true,phase='writing',ok=false,completed=0,cleanupRequired=false}
  prepare(commands[1]);return true
 end
 local function tick()
  if not tx then return snapshot()end
  local reason=guard();if reason then return fail(reason)end
  if adapter.now()>tx.totalDeadline then return fail('transaction-timeout')end
  if adapter.now()>tx.deadline then return fail('timeout')end
  local value=adapter.promptValue(tx.handle)
  if tx.stage=='write' then
   if value~='' then return fail('prompt-not-empty')end
   if adapter.writePrompt(tx.handle,'',tx.code)~=true then return fail('write-refused')end
   tx.promptPending=true;tx.stage='echo';last.phase=tx.cleaning and 'cleanup' or 'waiting-for-echo'
  elseif tx.stage=='echo' then
   -- A write acknowledgement is not evidence that AXValue has changed yet.
   if value~=tx.code then
    if value~='' then return fail('prompt-changed')end
    return snapshot()
   end
   if adapter.focusPrompt(tx.handle)~=true then return fail('prompt-focus-refused')end
   tx.stage='execute';last.phase=tx.cleaning and 'cleanup' or 'waiting-for-local-focus'
  elseif tx.stage=='execute' then
   if value~=tx.code then return fail('prompt-changed')end
   -- execute must recheck local console focus, exact code, and handle identity atomically.
   local result=adapter.execute(tx.handle,tx.code)
   if result=='pending'then return snapshot()end
   if result~=true then return fail('execute-refused')end
   tx.mayHaveBuffers=true;tx.stage='receipt';last.phase=tx.cleaning and 'cleanup' or 'waiting-for-receipt'
  else
   if value~='' and value~=tx.code then return fail('prompt-changed')end
   local receipt=adapter.receipt(tx.handle,tx.nonce,tx.sequence)
   if receipt==nil then return snapshot()end
   if type(receipt)~='table' or receipt.marker~='CDT_DIRECT_RECEIPT' or receipt.nonce~=tx.nonce
    or receipt.sequence~=tx.sequence or receipt.documentId~=tx.identity.documentId then return fail('receipt-mismatch')end
   if value~='' then return snapshot()end
   tx.promptPending=false
   if receipt.ok~=true then
    if tx.cleaning then return fail('cleanup-failed')end
    -- A failed first command might have rejected an existing namespace. Do not
    -- run deletion code until at least one initialization receipt succeeded.
    if last.completed==0 then return fail('execution-failed')end
    tx.failure='execution-failed';tx.cleaning=true;tx.sequence=tx.sequence+1;prepare(tx.cleanup);return snapshot()
   end
   if tx.cleaning then
    last.ok=tx.failure==nil;last.reason=tx.failure;last.phase=last.ok and 'complete' or 'stopped';last.cleanupRequired=false
    release(true);tx=nil;return snapshot()
   end
   last.completed=last.completed+1;tx.index=tx.index+1;tx.sequence=tx.sequence+1
   if tx.index>#tx.commands then tx.cleaning=true;prepare(tx.cleanup)else prepare(tx.commands[tx.index])end
  end
  return snapshot()
 end
 return {begin=function(request)
   local ok,value,reason=pcall(begin,request)
   if not ok then if tx then fail('adapter-failed')end;return false,'adapter-failed'end
   return value,reason
  end,tick=function()local ok,value=pcall(tick);if not ok then return fail('adapter-failed')end;return value end,
  snapshot=snapshot,stop=function()if tx then return fail('cancelled')end;return snapshot()end}
end
return M
