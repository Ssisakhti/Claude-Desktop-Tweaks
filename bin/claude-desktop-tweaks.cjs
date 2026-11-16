#!/usr/bin/env node
'use strict';
const {setup,parseArgs}=require('../scripts/setup.cjs');
function main(args=process.argv.slice(2)){
 if(args.length===1&&['--help','-h'].includes(args[0]))return 'Claude Desktop Tweaks\n--install-extension | --extension-dry-run\n--dry-run (default) | --install | --remove | --restore-backup=/path/to/backup\nQuit Claude before installing the extension. Reload Hammerspoon after changing its configuration.';
 if(args.length===1&&['--install-extension','--extension-dry-run'].includes(args[0]))return require('../scripts/extension-setup.cjs').installExtension({dryRun:args[0]==='--extension-dry-run'});
 return setup(parseArgs(args));
}
if(require.main===module){try{const value=main();console.log(typeof value==='string'?value:JSON.stringify(value,null,2));}catch(e){console.error(e.message);process.exitCode=1;}}
module.exports={main};
