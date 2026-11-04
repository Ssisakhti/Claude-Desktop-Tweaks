'use strict';
// Build an opt-in direct plan from trusted repository functions and local font data.
// This module does not open consoles, execute commands, or install startup hooks.
const fs = require('node:fs');
const path = require('node:path');
const { singleLineSource } = require('./console-bundle.cjs');
const { installController, CONTROLLER_REVISION } = require('./controller.cjs');
const { KINDS, classifyFrame } = require('./renderer-source.cjs');
const { runConsole, consoleFrame } = require('./console-payload.cjs');

function buildDirectPlan({ namespace, nonce, kind } = {}) {
 if (typeof namespace !== 'string' || namespace.length > 64 || !/^__cdt_[A-Za-z0-9_]+$/.test(namespace)) throw new TypeError('Invalid direct namespace');
 if (typeof nonce !== 'string' || !/^[a-f0-9]{32}$/.test(nonce)) throw new TypeError('Invalid direct nonce');
 if (!KINDS.includes(kind)) throw new TypeError('Invalid direct kind');
 const fonts = require('./fonts.json');
 if (fonts.length !== 1 || fonts[0].weight !== '100 900' || typeof fonts[0].data !== 'string' || !/^[A-Za-z0-9+/=]+$/.test(fonts[0].data) || fonts[0].data.length > 262144) throw new Error('Invalid local variable font');
 const key = JSON.stringify(namespace), owner = JSON.stringify(nonce), ref = `window[${key}]`;
 const guard = `const s=${ref};if(!s||s.owner!==${owner})throw Error("namespace-changed");`;
 const commands = [`if(Object.prototype.hasOwnProperty.call(window,${key}))throw Error("namespace-exists");${ref}={owner:${owner},chunks:[]};`];
 for (let offset = 0; offset < fonts[0].data.length; offset += 6000) commands.push(`${guard}s.chunks.push(${JSON.stringify(fonts[0].data.slice(offset, offset + 6000))});`);
 for (const [name, property] of [['scope', 'scope'], ['direction', 'direction'], ['nord', 'nord']]) {
  const source = `(()=>{const module={exports:{}};${fs.readFileSync(path.join(__dirname, name + '.cjs'), 'utf8')}\nreturn module.exports;})()`;
  commands.push(`${guard}s.${property}=${singleLineSource(source)};`);
 }
 commands.push(`${guard}s.install=${singleLineSource('(' + installController.toString() + ')')};`);
 const request = JSON.stringify({ kind, nonce, weights: fonts.length, revision: CONTROLLER_REVISION });
 commands.push(`${guard}const result=await (${runConsole.toString()})(k=>s.install({kind:k},[{weight:"100 900",data:s.chunks.join("")}],s.scope,s.direction,s.nord),${classifyFrame.toString()},${consoleFrame.toString()},{...${request},documentId:window.__claudePersianConsoleDocumentV1.id});if(result.marker!=="RTL_CONSOLE_RESULT"||result.nonce!==${owner}||result.kind!==${JSON.stringify(kind)}||result.ok!==true||result.fontLoaded!==true||result.stylesAttached!==true||result.stylesLoaded!==true||result.attachedWeights!==1)throw Error("application-unverified");`);
 const compact = commands.map(command => singleLineSource(`(async()=>{${command}})()`)).map(expression => `await ${expression};`);
 if (compact.length > 48 || compact.some(command => Buffer.byteLength(command) > 12000)) throw new Error('Direct command limits exceeded');
 return { commands: compact, cleanup: `if(${ref}&&${ref}.owner===${owner})delete window[${key}];` };
}
module.exports = { buildDirectPlan };
