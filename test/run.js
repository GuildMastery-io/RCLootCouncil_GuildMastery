#!/usr/bin/env node
// ============================================================
// run.js — boots a Lua 5.4 VM (Fengari) with a mocked WoW + RCLootCouncil
// environment, loads the REAL RCLootCouncil_GuildMastery Lua files, and runs
// a scenario. Because it loads the actual addon source, a syntax error or a
// broken assumption shows up here immediately.
//
// Usage:  node run.js [scenario]
//   scenarios: smoke | testrestore | reload | dedup | all  (default: all)
// ============================================================
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");
const { LUA_MULTRET } = lua;

const ADDON_DIR = path.resolve(__dirname, "..");
const SIM_DIR = __dirname;

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function fail(msg) {
  console.error("\n\x1b[31m[sim] " + msg + "\x1b[0m");
  process.exit(1);
}

// Load + run a Lua file; abort with the Lua error message on failure.
function dofile(absPath, chunkName) {
  let src;
  try {
    src = fs.readFileSync(absPath, "utf8");
  } catch (e) {
    fail("cannot read " + absPath + ": " + e.message);
  }
  // Strip a UTF-8 BOM if present (WoW files sometimes have one).
  if (src.charCodeAt(0) === 0xfeff) src = src.slice(1);
  const name = "@" + (chunkName || path.basename(absPath));
  if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring(name)) !== lua.LUA_OK) {
    fail("compile error in " + chunkName + ":\n  " + lua.lua_tojsstring(L, -1));
  }
  if (lua.lua_pcall(L, 0, LUA_MULTRET, 0) !== lua.LUA_OK) {
    fail("runtime error while loading " + chunkName + ":\n  " + lua.lua_tojsstring(L, -1));
  }
}

// Load order mirrors the addon TOC (History.lua before core.lua), sandwiched
// between the mocks (before) and the harness/scenarios (after).
dofile(path.join(SIM_DIR, "wow_mock.lua"), "wow_mock.lua");
dofile(path.join(SIM_DIR, "rc_mock.lua"), "rc_mock.lua");
dofile(path.join(SIM_DIR, "fakedata.lua"), "fakedata.lua");
dofile(path.join(ADDON_DIR, "History.lua"), "History.lua"); // <-- REAL addon
dofile(path.join(ADDON_DIR, "core.lua"), "core.lua"); // <-- REAL addon
dofile(path.join(SIM_DIR, "harness.lua"), "harness.lua");

// Pass the requested scenario to Lua and invoke Sim.run.
const scenario = process.argv[2] || "all";
lua.lua_pushstring(L, to_luastring(scenario));
lua.lua_setglobal(L, to_luastring("SIM_CMD"));

lua.lua_getglobal(L, to_luastring("Sim"));
lua.lua_getfield(L, -1, to_luastring("run"));
lua.lua_pushvalue(L, -2); // Sim (self)
lua.lua_pushstring(L, to_luastring(scenario));
if (lua.lua_pcall(L, 2, 1, 0) !== lua.LUA_OK) {
  fail("scenario '" + scenario + "' errored:\n  " + lua.lua_tojsstring(L, -1));
}
const exitCode = lua.lua_tointeger(L, -1);
process.exit(Number(exitCode) || 0);
