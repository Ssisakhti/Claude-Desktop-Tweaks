'use strict';
// Text surfaces were checked against version 4.4212.0 DOM. UI containers are excluded.
const QUESTION = '[data-ask-user-input-banner],[data-cds="AskUserQuestion"],[data-ask-user-question],[data-testid*="ask-user-question"],[data-testid="user-question"],[role="radiogroup"],fieldset:has(input[type="radio"]),form:has(input[type="radio"])';
// The preview is aria-hidden for accessibility, but its visible text still needs
// font and bidi styling. Keep that exception inside the composer only.
function isPromptSuggestion(el) {
 return !!el?.matches('[data-prompt-suggestion-ghost]') &&
  !!el.closest('[data-cds="ChatComposer"],[data-cds="ChatComposerEditor"],.epitaxy-prompt,[data-testid="chat-input"]') &&
  !el.closest('nav,aside,header,[role="toolbar"],button,[role="button"],pre,code');
}
function findSurfaces(doc, kind) {
 const found = new Set();
 const add = selector => { for (const el of doc.querySelectorAll(selector)) found.add(el); };
 if (kind === 'chat') {
  add(QUESTION);
  for(const el of doc.querySelectorAll('[data-prompt-suggestion-ghost]'))if(isPromptSuggestion(el))found.add(el);
 }
 if (kind === 'chat') add('[data-testid="user-message"],[data-testid="assistant-message"],[data-testid="chat-input"],.font-claude-response,[aria-label="Chat messages"],[data-testid="chat-messages"],.ProseMirror[contenteditable="true"][role="textbox"]');
 if (kind === 'document') add('article > .tiptap.ProseMirror,article > .ProseMirror');
 if (kind === 'artifact' || kind === 'artifact-content' || kind === 'document') {
  add('[contenteditable="true"].ProseMirror,textarea[placeholder*="comment" i],textarea[aria-label*="comment" i], [data-testid*="comment-body"],[data-testid*="comment-content"],.ldoc-comment-body,.comment-body,.comment-content,[data-testid="ldoc-thread-card"] .text-pretty');
 }
 return [...found].filter(el => !el.closest('nav,aside,header,[role="toolbar"]'));
}
// Plain Persian handoff text is sometimes wrapped in a code fence by the model.
// Keep declared programming languages and highlighted source in their original font.
function isProseCode(el) {
 if(!el?.matches('pre'))return false;
 const code=el.querySelector('code');if(!code)return false;
 const language=code.getAttribute('data-language')||el.getAttribute('data-language')||
  ((code.className+' '+el.className).match(/(?:language-|lang-)([\w-]+)/)||[])[1]||'';
 if(language&&!/^(text|txt|plain|plaintext|markdown|md)$/i.test(language))return false;
 if(code.matches('.token,.hljs,[class*="hljs-"]')||code.querySelector('.token,.hljs,[class*="hljs-"]'))return false;
 const text=code.textContent;
 const arabic=/(?=\p{Letter})\p{Script_Extensions=Arabic}/u;
 if(!arabic.test(text))return false;
 if(language)return true;
 if(/^\s*(?:const|let|var|function|class|def|import|from|return|print|select|insert|create|update|delete|echo|printf|export|curl|npm|node|python|bash|sudo|git)\b/im.test(text)||/[{}=;]/.test(text))return false;
 const words=(text.match(/\S+/g)||[]).filter(w=>/\p{Letter}/u.test(w)&&!/[\\/@]/.test(w)&&!/\.[a-z]{1,12}\b/i.test(w));
 return words.length>0&&words.filter(w=>arabic.test(w)).length/words.length>0.4;
}
function isUiTextBlock(el) {
 if(!el?.matches('span,div,p,bdi')||el.matches('[role="button"],[role="radio"],[role="checkbox"],[role="switch"],[role="textbox"],[contenteditable]'))return false;
 const faded=el.matches('.dframe-fade-label');
 if(!faded&&el.closest('.dframe-fade-label'))return false;
 if(el.querySelector(faded?'div,p,button,input,select,textarea,a,svg,[role="button"],[role="radio"]':'div,p,span,bdi,button,input,select,textarea,a,svg,[role="button"],[role="radio"]'))return false;
 if(!faded&&!el.closest('[role="tooltip"],[data-cds="OverflowTooltip"]')&&!(el.matches('.truncate')&&el.closest('nav,aside')))return false;
 return /(?=\p{Letter})\p{Script_Extensions=Arabic}/u.test(el.textContent)&&!/flex|grid/.test(getComputedStyle(el).display);
}
function isExcluded(el) {
 const control=el.closest('button,[role="button"],[role="radio"]');
 if(control && !(control!==el && control.closest(QUESTION)))return true;
 if(el.closest('pre,code')&&!isProseCode(el.closest('pre')))return true;
 const hidden=el.closest('[aria-hidden="true"]');
 if(hidden){
  const ghost=el.closest('[data-prompt-suggestion-ghost]');
  if(!isPromptSuggestion(ghost)||hidden!==ghost||ghost.parentElement?.closest('[aria-hidden="true"]'))return true;
 }
 return !!el.closest('nav,aside,header,[role="toolbar"],svg,i,kbd,samp,.token,.hljs,[class*="mtk"],math,.katex,mjx-container,.MathJax,.monaco-editor,.cm-editor,[data-testid="message-actions"],[data-testid="user-message-actions"],[data-testid="heading-collapse"],[class*="lucide" i],[class*="codicon" i]');
}
function contentText(el) {
 const walker = el.ownerDocument.createTreeWalker(el, 4);
 let text='', n;
 const ownSuggestion=el.closest('[data-prompt-suggestion-ghost]');
 while ((n=walker.nextNode())) if(n.parentElement && !isExcluded(n.parentElement)) {
  const suggestion=n.parentElement.closest('[data-prompt-suggestion-ghost]');
  // A preview is not accepted editor content and must not vote for its direction.
  if(!isPromptSuggestion(suggestion)||suggestion===ownSuggestion)text += n.nodeValue;
 }
 return text;
}
function selectorFor(el) {
 const parts=[];
 for(let n=el;n&&n.nodeType===1;n=n.parentElement){
  if(n===n.ownerDocument.documentElement){parts.unshift(':root');break;}
  const tag=n.localName;
  let index=1;for(let s=n.previousElementSibling;s;s=s.previousElementSibling)if(s.localName===tag)index++;
  parts.unshift(`${tag}:nth-of-type(${index})`);
  if(parts.length>60)return null;
 }
 return parts.join(' > ');
}
function collectTargets(doc, kind, changedRoots = null) {
 if(!['chat','artifact','artifact-content','document','shell'].includes(kind))return {surfaces:[],fonts:[],blocks:[]};
 const surfaces=findSurfaces(doc,kind), fonts=new Set(), blocks=new Set();
 const roots=changedRoots ? surfaces.flatMap(surface=>changedRoots.filter(root=>surface.contains(root))) : surfaces;
 for(const root of roots){
  if(root.matches('textarea,input')) {fonts.add(root);blocks.add(root);continue;}
  // Include an empty composer so its font is ready before the first keystroke.
  if(root.matches('[contenteditable="true"]')||isPromptSuggestion(root))fonts.add(root);
  if(kind==='chat')for(const pre of root.querySelectorAll('pre'))if(isProseCode(pre)){fonts.add(pre);blocks.add(pre);}
  if(kind==='chat')for(const el of root.querySelectorAll('textarea,input[type="text"],input:not([type])')){
   if(!isExcluded(el)&&!el.closest('button,[role="button"]')&&el.closest(QUESTION+', [data-testid="chat-input"]')){fonts.add(el);blocks.add(el);}
  }
  const walker=doc.createTreeWalker(root,4);let n;
  while((n=walker.nextNode()))if(n.nodeValue.trim()&&n.parentElement&&!isExcluded(n.parentElement))fonts.add(n.parentElement);
  for(const el of [root,...root.querySelectorAll('p,h1,h2,h3,h4,h5,h6,li,td,th,blockquote')]){
   if(isExcluded(el)||/flex|grid/.test(getComputedStyle(el).display))continue;
   if(el===root && surfaces.includes(root) && !root.matches('[data-testid="chat-input"],[contenteditable]'))continue;
   if(el===root&&surfaces.includes(root)&&!isPromptSuggestion(root)&&root.querySelector('p,h1,h2,h3,li,td,th,blockquote'))continue;
   if(el.matches('li,blockquote')&&el.querySelector('table'))continue;
   if(el.matches('td,th')&&el.querySelector('p,li,h1,h2,h3'))continue;
   blocks.add(el);
  }
  // A new title bdi can isolate its English prefix as LTR from the Persian paragraph.
  if(kind==='chat')for(const el of root.querySelectorAll('bdi')){
   if(el.closest(QUESTION)&&!isExcluded(el))blocks.add(el);
  }
  // Set question text direction before and after an answer, separately from layout.
  // Do not target inline spans. A word split across spans must remain one paragraph.
  if(kind==='chat')for(const el of [root,...root.querySelectorAll('span,label,div,p')]){
   if(el===root&&surfaces.includes(root))continue;
   const display=getComputedStyle(el).display;
   if(!isExcluded(el)&&!el.querySelector('p,div,span,label,button,input,svg')&&!/flex|grid/.test(display)&&(!el.matches('span,label')||/^(block|inline-block|list-item)$/.test(display)))blocks.add(el);
  }
  // User messages can contain text directly in a div without a paragraph.
  for(const el of fonts) {
   if(!root.contains(el)||isExcluded(el))continue;
   if(el.matches('div')&&!el.querySelector('p,div,ul,ol,table')&&!/flex|grid/.test(getComputedStyle(el).display))blocks.add(el);
  }
 }
 // Direction belongs to isolated text labels, never their control containers.
 for(const uiRoot of changedRoots || [doc.documentElement]) {
 const uiWalker=doc.createTreeWalker(uiRoot,4);let uiNode;
 while((uiNode=uiWalker.nextNode())){
  const el=uiNode.parentElement;
  if(el && /[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]/u.test(uiNode.nodeValue) && !el.closest('script,style,svg,i,pre,code,kbd,samp,.token,.hljs,[class*="mtk"],math,.katex,mjx-container,.MathJax,.monaco-editor,.cm-editor,[class*="lucide" i],[class*="codicon" i]')){fonts.add(el);const label=el.closest('.dframe-fade-label')||el;if(isUiTextBlock(label)){fonts.add(label);blocks.add(label);}}
 }
 }
 return {surfaces,fonts:[...fonts],blocks:[...blocks]};
}
module.exports={isPromptSuggestion,isUiTextBlock,isProseCode,findSurfaces,isExcluded,contentText,selectorFor,collectTargets};
