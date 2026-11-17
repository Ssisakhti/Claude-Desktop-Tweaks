'use strict';
const { classifyFrame, rendererParts } = require('./renderer-source.cjs');
const { consoleFrame } = require('./console-payload.cjs');

function extensionKind(location) {
 return classifyFrame(consoleFrame(location));
}

async function startExtension(classify, readFrame, install) {
 const kind = classify(readFrame(location));
 if (!kind || kind === 'shell') return null;
 const key = '__claudePersianExtensionV1';
 if (window[key]) return window[key].snapshot();
 let stopped = false;
 let failure = false;
 const ready = Promise.resolve().then(() => install(kind));
 const handle = {
  snapshot() {
   const controller = window.__claudePersianControllerV2;
   return { running:!stopped, kind, failed:failure,
    controller:controller && typeof controller.snapshot === 'function' ? controller.snapshot() : null };
  },
  async dispose() {
   stopped = true;
   try { await ready; } catch {}
   const controller = await window.__claudePersianControllerV2;
   if (controller) await controller.dispose();
   if (window[key] === handle) delete window[key];
  },
 };
 window[key] = handle;
 try { await ready; } catch { failure = true; }
 return handle.snapshot();
}

function buildExtension(options = {}) {
 const parts = rendererParts(options);
 const manifest = {
  manifest_version:3,
  name:'Claude Desktop Persian Tweaks',
  version:'1.4.1',
  description:'Local Persian fonts, mixed text direction, and color themes for Claude.',
  content_scripts:[{
   matches:['https://claude.ai/*', 'https://*.frame.claudeusercontent.com/*'],
   exclude_matches:['https://claude.ai/oauth/*', 'https://claude.ai/login/*', 'https://claude.ai/auth/*', 'https://claude.ai/api/*'],
   js:['content.js'],
   run_at:'document_idle',
   all_frames:true,
   match_about_blank:true,
   match_origin_as_fallback:true,
  }],
 };
 const features = options.features;
 if(features!==undefined){
  if(!features||['font','theme','rtl'].some(k=>typeof features[k]!=='boolean')||Object.keys(features).some(k=>!['font','theme','rtl','fontFamily','themeName'].includes(k)))throw new TypeError('Invalid feature selection');
  if(features.fontFamily!==undefined&&!['estedad','vazirmatn'].includes(features.fontFamily))throw new TypeError('Invalid font selection');
  if(features.themeName!==undefined&&!['nord','gruvbox'].includes(features.themeName))throw new TypeError('Invalid theme selection');
 }
 const source = `'use strict';\n(${startExtension.toString()})(${classifyFrame.toString()},${consoleFrame.toString()},async kind=>${parts.prefix}{kind,features:${JSON.stringify(features ?? {font:true,theme:true,rtl:true})}}${parts.suffix});\n`;
 return { manifest, source };
}

module.exports = { buildExtension, extensionKind, startExtension };
