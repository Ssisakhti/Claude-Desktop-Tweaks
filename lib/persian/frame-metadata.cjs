'use strict';
function frameMetadata(location) {
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

module.exports={frameMetadata};
