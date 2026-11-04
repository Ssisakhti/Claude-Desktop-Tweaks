'use strict';
// Build direct console commands without controlling windows or the console prompt.
const { KINDS, classifyFrame, rendererParts } = require('./renderer-source.cjs');
const { CONTROLLER_REVISION } = require('./controller.cjs');

function consoleFrame(location) {
 const frame = { url: location.href, parent: null };
 if (frame.url !== 'about:srcdoc') return frame;
 try {
  // The browser provides origin metadata. Do not read cross-origin frame DOM.
  const origins = location.ancestorOrigins;
  let parent = frame;
  for (let i = 0; i < Math.min(origins.length, 12); i++) {
   parent.parent = { url: origins[i], parent: null };
   parent = parent.parent;
  }
 } catch { return { url: frame.url, parent: null }; }
 return frame;
}

async function probeConsole(classify, readFrame, request) {
 const result = { marker: 'RTL_CONSOLE_PROBE', nonce: request.nonce, kind: null, ok: false,
  documentId: null, controllerPresent: false, healthy: false };
 try {
  if (request.expectedURL !== undefined && request.expectedURL !== null && location.href !== request.expectedURL) {
   return { ...result, reason: 'source-mismatch' };
  }
  const frame = readFrame(location);
  const kind = classify(frame);
  result.kind = kind;
  if (!kind) return { ...result, reason: 'context-mismatch' };
  const targetDocument = document;
  const identity = JSON.stringify(frame);
  const key = '__claudePersianConsoleDocumentV1';
  let record = window[key];
  if (!record || record.document !== targetDocument || record.identity !== identity || !/^[a-f0-9]{32}$/.test(record.id)) {
   let id;
   if (typeof crypto !== 'undefined' && crypto && typeof crypto.randomUUID === 'function') {
    id = crypto.randomUUID().replaceAll('-', '').toLowerCase();
   } else if (typeof crypto !== 'undefined' && crypto && typeof crypto.getRandomValues === 'function') {
    const bytes = crypto.getRandomValues(new Uint8Array(16));
    id = Array.from(bytes, value => value.toString(16).padStart(2, '0')).join('');
   } else return { ...result, reason: 'random-source-unavailable' };
   if (!/^[a-f0-9]{32}$/.test(id)) return { ...result, reason: 'random-source-invalid' };
   record = { document: targetDocument, identity, id };
   Object.defineProperty(window, key, { value: record, configurable: true, writable: true });
  }
  const current = () => document === targetDocument && JSON.stringify(readFrame(location)) === identity && window[key] === record;
  const controller = await window.__claudePersianControllerV2;
  if (!current()) return { ...result, reason: 'context-changed' };
  const status = controller && typeof controller.snapshot === 'function' ? await controller.snapshot() : null;
  if (!current()) return { ...result, reason: 'context-changed' };
  return { ...result, ok: true, documentId: record.id, controllerPresent: Boolean(controller),
   healthy: status?.kind === kind && status.revision === request.revision && status.fontLoaded === true && !status.error && !status.pending &&
    status.stylesAttached === true && status.stylesLoaded === true && status.attachedWeights === request.weights };
 } catch { return { ...result, reason: 'probe-failed' }; }
}

async function runConsole(install, classify, readFrame, request) {
 const base = { marker: 'RTL_CONSOLE_RESULT', nonce: request.nonce, kind: null, ok: false };
 try {
  const frame = readFrame(location);
  const kind = classify(frame);
  base.kind = kind;
  if (!kind || kind !== request.kind) return { ...base, reason: 'context-mismatch' };
  const targetDocument = document;
  const identity = JSON.stringify(frame);
  const identified = () => {
   if (request.documentId === undefined) return true;
   const record = window.__claudePersianConsoleDocumentV1;
   return record?.document === targetDocument && record.identity === identity && record.id === request.documentId;
  };
  if (!identified()) return { ...base, reason: 'document-mismatch' };
  const current = () => document === targetDocument && JSON.stringify(readFrame(location)) === identity && identified();
  const healthKnown = status => typeof status?.stylesAttached === 'boolean' && typeof status?.stylesLoaded === 'boolean' && Number.isInteger(status?.attachedWeights);
  const healthy = status => status?.kind === kind && status.revision === request.revision && status.fontLoaded === true && !status.error && !status.pending &&
   healthKnown(status) && status.stylesAttached && status.stylesLoaded && status.attachedWeights === request.weights;
  const old = await window.__claudePersianControllerV2;
  if (!current()) return { ...base, reason: 'context-changed' };
  if (old) {
   let status = await old.snapshot();
   if (!current()) return { ...base, reason: 'context-changed' };
   if (status?.kind !== kind) return { ...base, reason: 'controller-kind-mismatch' };
   if (status.revision === request.revision && healthKnown(status) && !healthy(status) && typeof old.refresh === 'function') {
    await old.refresh();
    if (!current()) return { ...base, reason: 'context-changed' };
    status = await old.snapshot();
    if (!current()) return { ...base, reason: 'context-changed' };
   }
   if (!healthy(status)) {
    // An older controller in the same namespace can block a new installation.
    // Remove it only through its own dispose method in the same document.
    if (typeof old.dispose !== 'function') return { ...base, reason: 'controller-dispose-unavailable' };
    if (window.__claudePersianControllerV2 !== old) return { ...base, reason: 'controller-changed' };
    await old.dispose();
    if (!current()) return { ...base, reason: 'context-changed' };
    if (window.__claudePersianControllerV2) return { ...base, reason: 'controller-dispose-incomplete' };
   }
  }
  const status = await install(kind);
  if (!current()) return { ...base, reason: 'context-changed' };
  const verified = healthKnown(status);
  const ok = healthy(status);
  // Do not expose samples, page errors, URLs, or DOM content from the snapshot.
  return { ...base, ok, pending: Boolean(status?.pending), fontLoaded: status?.fontLoaded === true,
   stylesAttached: status?.stylesAttached === true,
   stylesLoaded: status?.stylesLoaded === true,
   attachedWeights: verified ? Math.max(0, Math.min(status.attachedWeights, request.weights)) : 0,
   ...(!ok ? { reason: !verified && !status?.pending && !status?.error ? 'health-unverified' : 'application-incomplete' } : {}) };
 } catch { return { ...base, reason: 'application-failed' }; }
}

function validateNonce(nonce) {
 if (typeof nonce !== 'string' || !/^[a-zA-Z0-9_-]{16,80}$/.test(nonce)) throw new TypeError('Invalid console request nonce');
}

function buildConsoleProbe({ nonce, expectedURL = null } = {}) {
 validateNonce(nonce);
 if (expectedURL !== null && typeof expectedURL !== 'string') throw new TypeError('Invalid expected console URL');
 const request = { nonce, weights: require('./fonts.json').length, revision: CONTROLLER_REVISION, expectedURL };
 return `(async()=>{const result=await (${probeConsole.toString()})(${classifyFrame.toString()},${consoleFrame.toString()},${JSON.stringify(request)});console.log(JSON.stringify(result));return result;})()`;
}

function buildConsolePayload({ kind, nonce, fonts, documentId } = {}) {
 if (!KINDS.includes(kind)) throw new RangeError('Expected console kind required');
 validateNonce(nonce);
 if (documentId !== undefined && (typeof documentId !== 'string' || !/^[a-f0-9]{32}$/.test(documentId))) throw new TypeError('Invalid console document ID');
 const parts = rendererParts(fonts === undefined ? {} : { fonts });
 const weights = (fonts ?? require('./fonts.json')).length;
 // Run the engine in this context without eval, Function, or network code loading.
 const install = `kind=>${parts.prefix}{kind}${parts.suffix}`;
 return `(async()=>{const result=await (${runConsole.toString()})(${install},${classifyFrame.toString()},${consoleFrame.toString()},${JSON.stringify({kind,nonce,weights,documentId,revision:CONTROLLER_REVISION})});console.log(JSON.stringify(result));return result;})()`;
}

module.exports = { consoleFrame, runConsole, probeConsole, buildConsoleProbe, buildConsolePayload };
