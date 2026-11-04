'use strict';
// Build frame boundaries and renderer source for the internal console only.
const fs = require('node:fs');
const path = require('node:path');
const { installController, CONTROLLER_REVISION } = require('./controller.cjs');
const KINDS = Object.freeze(['shell', 'chat', 'artifact', 'artifact-content', 'document']);

function classifyFrame(frame) {
 try {
  const u = new URL(frame.url);
  if (u.protocol === 'file:' && /\/app\.asar\/\.vite\/renderer\/(main_window|quick_window|about_window|find_in_page)\//.test(decodeURIComponent(u.pathname))) return 'shell';
  if (u.protocol === 'https:' && u.hostname === 'claude.ai' && !/^\/(oauth|login|auth|api)(?:\/|$)/.test(u.pathname)) return u.pathname.startsWith('/code/artifact/') ? 'artifact' : 'chat';
  if (u.protocol === 'https:' && /^[a-z0-9-]+\.frame\.claudeusercontent\.com$/.test(u.hostname)) return 'artifact-content';
  if (frame.url === 'about:srcdoc') for (let p = frame.parent, i = 0; p && i < 12; p = p.parent, i++) {
   const ancestor = new URL(p.url);
   if (ancestor.protocol === 'https:' && /^[a-z0-9-]+\.frame\.claudeusercontent\.com$/.test(ancestor.hostname)) return 'document';
  }
 } catch {}
 return null;
}

function rendererParts(options = {}) {
 const fonts = options.fonts ?? require('./fonts.json');
 if (!Array.isArray(fonts)) throw new TypeError('fonts must be an array');
 const modules = ['scope', 'direction', 'nord'].map(name => `${JSON.stringify(name)}:(function(){const module={exports:{}};${fs.readFileSync(path.join(__dirname, name + '.cjs'), 'utf8')}\nreturn module.exports;})()`).join(',');
 return {
  revision: CONTROLLER_REVISION,
  prefix: `(async()=>{const modules={${modules}};return (${installController.toString()})(`,
  suffix: `,${JSON.stringify(fonts)},modules.scope,modules.direction,modules.nord);})()`,
 };
}

module.exports = { KINDS, classifyFrame, rendererParts };
