'use strict';
async function installController(config,fonts,scope,bidi,nord) {
 // Keep the literal inside the function so toString payloads need no module variable.
 const revision=3;
 const key='__claudePersianControllerV2';
 if(window[key]){
  const previous=window[key],active=await previous;
  const status=active.snapshot();
  if(status.revision===revision){
   if(!status.healthy)active.refresh?.();
   return active.snapshot();
  }
  if(typeof active.dispose!=='function')throw new Error('Existing RTL controller cannot be upgraded safely');
  await active.dispose();
  if(window[key]===previous||window[key]===active)throw new Error('Previous RTL controller did not stop');
  // A concurrent request may have installed the new version first.
  if(window[key])return installController(config,fonts,scope,bidi,nord);
 }
 if(!document.documentElement)return {pending:true};
 const task=(async()=>{
 const family='Claude Persian Estedad';
 const ranges='U+0600-06FF,U+0750-077F,U+08A0-08FF,U+200C-200F,U+FB50-FDFF,U+FE70-FEFF';
 const faces=await Promise.all(fonts.map(async f=>{
  const face=new FontFace(family,Uint8Array.from(atob(f.data),c=>c.charCodeAt(0)).buffer,{weight:String(f.weight),style:'normal',unicodeRange:ranges});
  await face.load();return face;
 }));
 for(const face of faces)document.fonts.add(face);
 const fontSheet=new CSSStyleSheet(),themeSheet=new CSSStyleSheet();
 document.adoptedStyleSheets=[...document.adoptedStyleSheets,themeSheet,fontSheet];
 const previous=new WeakMap();let timer=null,settleTimer=null,composing=false,disposed=false,lastSurfaces=[];
 const fontRules=new Map(),blockRules=new Map();
 let pendingFull=false,settlingFull=false,pendingRoots=new Set(),settlingRoots=new Set();
 let lastBlocks=[],lastDark=null;
 let state={revision,kind:config.kind,fontLoaded:true,weights:faces.map(f=>f.weight),passes:0,fullPasses:0,partialPasses:0};
 function restoreResources(){
  if(disposed)return;
  const sheets=document.adoptedStyleSheets;
  const missing=[themeSheet,fontSheet].filter(sheet=>!sheets.includes(sheet));
  if(missing.length)document.adoptedStyleSheets=[...sheets,...missing];
  for(const face of faces)if(!document.fonts.has(face))document.fonts.add(face);
 }
 function isDark(){
  const root=document.documentElement;
  const explicit=root.getAttribute('data-theme');
  if(explicit==='light'||root.classList.contains('lightTheme'))return false;
  return getComputedStyle(root).colorScheme.split(/\s+/).includes('dark')||root.classList.contains('dark')||root.classList.contains('darkTheme')||document.body?.classList.contains('darkTheme')||new URLSearchParams(location.search).get('m')==='dark';
 }
 function scan(settled=false,changedRoots=null){
  if(disposed||composing)return;
  fontSheet.disabled=true;themeSheet.disabled=true;
  try{
   restoreResources();
   const dark=isDark();
   const {surfaces,fonts:fontTargets,blocks}=scope.collectTargets(document,config.kind,changedRoots);
   lastSurfaces=surfaces;
   if(!changedRoots){fontRules.clear();blockRules.clear();}
   else for(const root of changedRoots){
    for(const el of fontRules.keys())if(root.contains(el))fontRules.delete(el);
    for(const el of blockRules.keys())if(root.contains(el))blockRules.delete(el);
   }
   let rtl=0,ltr=0,neutral=0;
   for(const el of fontTargets){
    const selector=scope.selectorFor(el);if(!selector)continue;
    const fallback=getComputedStyle(el).fontFamily;
    fontRules.set(el,`${selector}{font-family:"${family}",${fallback}!important;}`);
   }
   for(const el of blocks){
    const selector=scope.selectorFor(el);if(!selector)continue;
    const text=el.matches('textarea,input')?el.value:scope.contentText(el);
    const editable=el.isContentEditable||el.matches('textarea,input');
    const direction=(editable||!settled)?bidi.stableDirection(text,previous.get(el)):bidi.estimateDirection(text).direction;
    previous.set(el,direction);
    if(direction==='neutral'){blockRules.set(el,{direction,rule:''});continue;}
    blockRules.set(el,{direction,rule:`${selector}{direction:${direction}!important;text-align:start!important;unicode-bidi:isolate!important;}`});
   }
   fontSheet.replaceSync([...fontRules.values(),...[...blockRules.values()].map(value=>value.rule)].join('\n'));
   if(dark!==lastDark){themeSheet.replaceSync(dark?nord.nordThemeCss({forceDark:true}):'');lastDark=dark;}
   lastBlocks=[...blockRules.keys()];
   for(const value of blockRules.values()){
    if(value.direction==='rtl')rtl++;else if(value.direction==='ltr')ltr++;else neutral++;
   }
   const {error,...previousState}=state;
   state={...previousState,passes:state.passes+1,surfaces:surfaces.length,fontTargets:fontRules.size,scannedBlocks:blocks.length,fullPasses:state.fullPasses+(changedRoots?0:1),partialPasses:state.partialPasses+(changedRoots?1:0),rtlBlocks:rtl,ltrBlocks:ltr,neutralBlocks:neutral,dark,background:getComputedStyle(document.body||document.documentElement).backgroundColor};
  }catch(e){state={...state,error:String(e.message).slice(0,160)};}
  finally{fontSheet.disabled=false;themeSheet.disabled=false;}
 }
 // Structural changes can invalidate positional selectors.
 function changedRoot(el){
  if(!el||el===document.documentElement||el===document.body)return null;
  const block=el.closest('p,h1,h2,h3,h4,h5,h6,li,td,th,blockquote,textarea,input,[contenteditable="true"],[data-testid="user-message"],[data-testid="assistant-message"]');
  if(!block)return null;
  // Recheck direction on lists and blockquotes around the paragraph.
  let root=block;
  for(let parent=block.parentElement;parent;parent=parent.parentElement){
   if(parent.matches('li,blockquote,td,th'))root=parent;
   if(lastSurfaces.includes(parent))break;
  }
  return root;
 }
 function compact(roots){return [...roots].filter(root=>root.isConnected && ![...roots].some(other=>other!==root&&other.contains(root)));}
 function schedule(root=null){
  if(disposed)return;
  if(root){pendingRoots.add(root);settlingRoots.add(root);}else{pendingFull=true;settlingFull=true;pendingRoots.clear();settlingRoots.clear();}
  if(!timer&&!composing)timer=setTimeout(()=>{
   timer=null;
   if(composing)return;
   const roots=pendingFull?null:compact(pendingRoots);
   pendingFull=false;pendingRoots.clear();
   scan(false,roots);
  },180);
  clearTimeout(settleTimer);
  settleTimer=setTimeout(()=>{
   if(composing)return;
   // Rebuild selectors after structural changes before the final check.
   if(pendingFull||settlingFull){scan(true);pendingFull=false;settlingFull=false;pendingRoots.clear();}
   else {const roots=compact(settlingRoots);if(roots.length)scan(true,roots);}
   settlingRoots.clear();
  },1000);
 }
 const observer=new MutationObserver(mutations=>{
  for(const m of mutations){
   const el=m.target.nodeType===1?m.target:m.target.parentElement;
   if(!el)continue;
   if(m.type==='characterData'){
    if(lastSurfaces.some(root=>root.contains(el))||/[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]/u.test(m.target.nodeValue||''))schedule(changedRoot(el));
   }else if(m.type==='attributes'){
    if(el===document.documentElement||el===document.body||el.classList.contains('cds-root'))schedule();
    else if(lastSurfaces.some(root=>root.contains(el)))schedule(changedRoot(el));
   }else if(m.type==='childList'){
    // Adding or removing a sibling can change a positional selector.
    schedule();
   }
  }
 });
 observer.observe(document.documentElement,{subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:['class','data-theme','style','dir']});
 const onCompositionStart=()=>{composing=true;};
 const onCompositionEnd=event=>{composing=false;schedule(changedRoot(event.target));};
 const onInput=event=>schedule(changedRoot(event.target));
 document.addEventListener('compositionstart',onCompositionStart,true);
 document.addEventListener('compositionend',onCompositionEnd,true);
 document.addEventListener('input',onInput,true);
 function resourceHealth(){
  const attached=faces.filter(face=>document.fonts.has(face));
  const loaded=attached.filter(face=>face.status==='loaded');
  const fontLoaded=!disposed&&loaded.length===faces.length;
  const stylesAttached=!disposed&&[themeSheet,fontSheet].every(sheet=>document.adoptedStyleSheets.includes(sheet));
  const stylesLoaded=stylesAttached&&!themeSheet.disabled&&!fontSheet.disabled;
  return {fontLoaded,weights:loaded.map(face=>face.weight),attachedWeights:attached.length,stylesAttached,stylesLoaded,healthy:fontLoaded&&stylesLoaded&&!state.error};
 }
 function snapshot(){
  return {...state,...resourceHealth(),sample:lastBlocks.slice(0,8).map(el=>({tag:el.tagName,editable:el.isContentEditable,direction:getComputedStyle(el).direction,font:getComputedStyle(el).fontFamily,weight:getComputedStyle(el).fontWeight}))};
 }
 scan();
 // The editor may appear after hydration.
 const hydrationTimers=[setTimeout(()=>schedule(),700),setTimeout(()=>schedule(),2400)];
 // Removing adoptedStyleSheets or FontFace emits no DOM event. Check resource health only.
 let healthTimer=null;
 function checkHealth(){
  if(disposed)return;
  if(!composing&&!resourceHealth().healthy)scan();
  if(!disposed)healthTimer=setTimeout(checkHealth,1500);
 }
 healthTimer=setTimeout(checkHealth,1500);
 function dispose(){
  if(disposed)return;
  disposed=true;observer.disconnect();
  clearTimeout(timer);clearTimeout(settleTimer);
  clearTimeout(healthTimer);
  for(const timer of hydrationTimers)clearTimeout(timer);
  document.removeEventListener('compositionstart',onCompositionStart,true);
  document.removeEventListener('compositionend',onCompositionEnd,true);
  document.removeEventListener('input',onInput,true);
  document.adoptedStyleSheets=document.adoptedStyleSheets.filter(sheet=>sheet!==fontSheet&&sheet!==themeSheet);
  for(const face of faces)document.fonts.delete(face);
  fontRules.clear();blockRules.clear();pendingRoots.clear();settlingRoots.clear();lastBlocks=[];lastSurfaces=[];
  if(window[key]===task||window[key]?.dispose===dispose)delete window[key];
 }
 return {snapshot,refresh:scan,dispose};
 })();
 window[key]=task;
 try{const active=await task;window[key]=active;return active.snapshot();}
 catch(error){delete window[key];throw error;}
}
const CONTROLLER_REVISION=3;
installController.revision=CONTROLLER_REVISION;
module.exports={installController,CONTROLLER_REVISION};
