'use strict';
// This bundle contains data and command strings only. It executes no commands.
const { KINDS, classifyFrame, rendererParts } = require('./renderer-source.cjs');
const { CONTROLLER_REVISION } = require('./controller.cjs');
const { consoleFrame, probeConsole, runConsole } = require('./console-payload.cjs');
const { minify_sync } = require('terser');
const vm = require('node:vm');

const NONCE_TOKEN = '__RTL_CONSOLE_NONCE__';
const DOCUMENT_TOKEN = '__RTL_CONSOLE_DOCUMENT_ID__';
const URL_TOKEN = '__RTL_CONSOLE_EXPECTED_URL_JSON__';

function singleLineSource(source) {
 // Require one complete expression so trailing statements cannot disappear.
 new vm.Script('void (' + source + '\n)');
 const result = minify_sync(source, { parse: { expression: true }, compress: false, mangle: false,
  format: { comments: false, beautify: false, semicolons: true, ascii_only: true, max_line_len: false, quote_style: 2 } });
 if (typeof result.code !== 'string' || result.code === '' || /[\r\n\u2028\u2029]/.test(result.code)) {
  throw new Error('Console source must be a single line');
 }
 const expression = '(' + result.code + ')';
 // The driver wraps this value in return await (...). This check only parses it.
 new vm.Script('void (' + expression + ');');
 return expression;
}

function buildConsoleBundle() {
 const weights = require('./fonts.json').length;
 // URL_TOKEN is a complete JSON literal. The other two tokens occur in JSON strings.
 // Validate nonce and documentId against their allowed patterns before substitution.
 const probeRequest = JSON.stringify({ nonce: NONCE_TOKEN, weights, revision: CONTROLLER_REVISION, expectedURL: URL_TOKEN })
  .replace(JSON.stringify(URL_TOKEN), URL_TOKEN);
 const probeTemplate = `(async()=>{const result=await (${probeConsole.toString()})(${classifyFrame.toString()},${consoleFrame.toString()},${probeRequest});console.log(JSON.stringify(result));return result;})()`;
 const parts = rendererParts();
 const install = `kind=>${parts.prefix}{kind}${parts.suffix}`;
 const payloads = Object.fromEntries(KINDS.map(kind => {
  const request = JSON.stringify({ kind, nonce: NONCE_TOKEN, weights, documentId: DOCUMENT_TOKEN, revision: CONTROLLER_REVISION });
  const source = `(async()=>{const result=await (${runConsole.toString()})(${install},${classifyFrame.toString()},${consoleFrame.toString()},${request});console.log(JSON.stringify(result));return result;})()`;
  return [kind, singleLineSource(source)];
 }));
 return { version: 1, revision: CONTROLLER_REVISION, probeTemplate: singleLineSource(probeTemplate), payloads };
}

module.exports = { buildConsoleBundle, singleLineSource, NONCE_TOKEN, DOCUMENT_TOKEN, URL_TOKEN };
