'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {frameMetadata}=require('../lib/persian/frame-metadata.cjs');
test('Frame metadata uses browser-provided ancestors without accessing frame DOM',()=>{
 const location={href:'about:srcdoc',ancestorOrigins:['https://sample.frame.claudeusercontent.com','https://claude.ai']};
 assert.deepEqual(frameMetadata(location),{url:'about:srcdoc',parent:{url:location.ancestorOrigins[0],parent:{url:location.ancestorOrigins[1],parent:null}}});
 assert.deepEqual(frameMetadata({href:'https://claude.ai/chat/sample',get ancestorOrigins(){throw Error('not needed');}}),{url:'https://claude.ai/chat/sample',parent:null});
 assert.deepEqual(frameMetadata({href:'about:srcdoc',get ancestorOrigins(){throw Error('blocked');}}),{url:'about:srcdoc',parent:null});
});
