'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {spawnSync}=require('node:child_process');
const cli=path.resolve(__dirname,'../bin/claude-desktop-tweaks.cjs');
test('The CLI provides help and rejects unknown options',()=>{
 const help=spawnSync(process.execPath,[cli,'--help'],{encoding:'utf8'});assert.equal(help.status,0);assert.match(help.stdout,/Claude Desktop Tweaks/);
 const invalid=spawnSync(process.execPath,[cli,'--unknown'],{encoding:'utf8'});assert.equal(invalid.status,1);assert.equal(invalid.stdout,'');
});
test('The default CLI mode writes no files in the test home',()=>{
 const home=fs.mkdtempSync(path.join(os.tmpdir(),'tweaks-cli-'));try{
 const result=spawnSync(process.execPath,[cli],{env:{...process.env,HOME:home},encoding:'utf8'});assert.equal(result.status,0,result.stderr);assert.equal(JSON.parse(result.stdout).mode,'--dry-run');assert.deepEqual(fs.readdirSync(home),[]);
 }finally{fs.rmSync(home,{recursive:true,force:true});}
});
