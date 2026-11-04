#!/usr/bin/env python3
"""Run Lua tests with the Hammerspoon library, without accessing the real UI."""
import argparse
import ctypes
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
runtime = parser.add_mutually_exclusive_group(required=True)
runtime.add_argument('--library')
runtime.add_argument('--lua')
parser.add_argument('--module', default='integrations/hammerspoon/claude-console-auto.lua')
parser.add_argument('--test', default='test/hammerspoon-console-auto.test.lua')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
# JSON quoted paths are valid Lua strings for normal Unix paths. No shell interpolation.
source = f'''arg={{{json.dumps(str((root / args.module).resolve()))}}}
local result=assert(loadfile({json.dumps(str((root / args.test).resolve()))}))()
return string.format('{{"ok":%s,"assertions":%d,"scenarios":%d}}', tostring(result.ok), result.assertions, result.scenarios)
'''
if args.lua:
    result = subprocess.run([args.lua, '-'], input='print((function()\n' + source + '\nend)())', text=True, capture_output=True, timeout=30)
    if result.returncode:
        raise SystemExit(result.stderr.strip() or 'Lua test failed')
    print(result.stdout.strip())
    raise SystemExit(0)

lua = ctypes.CDLL(args.library)
lua.luaL_newstate.restype = ctypes.c_void_p
lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
lua.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
lua.lua_tolstring.restype = ctypes.c_char_p
lua.lua_close.argtypes = [ctypes.c_void_p]
state = lua.luaL_newstate()
lua.luaL_openlibs(state)
try:
    code = lua.luaL_loadstring(state, source.encode())
    if code == 0:
        code = lua.lua_pcallk(state, 0, 1, 0, 0, None)
    result = lua.lua_tolstring(state, -1, None)
    if code:
        raise SystemExit(result.decode() if result else f'Lua error {code}')
    print(result.decode())
finally:
    lua.lua_close(state)
