#!/usr/bin/env node
// ============================================================
// load_real.js — loads the ACTUAL RCLootCouncil (real Ace libs + real RC Lua,
// in TOC/embeds order) into Fengari, on top of an extended WoW mock + Lua 5.1
// shims, then loads the REAL GuildMastery addon and runs a smoke check.
//
// This is the "run the real RC" mode. Heavy and best-effort: WoW is a huge API.
//
// Usage:
//   node load_real.js [scenario]        scenario: smoke (default) | reload
//   node load_real.js --rc "<RC folder>"
// ============================================================
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const SIM_DIR = path.resolve(__dirname, "..");
const REALRC_DIR = __dirname;
const ADDON_DIR = path.resolve(SIM_DIR, "..");

// --- locate RCLootCouncil ---
function findRC() {
  const i = process.argv.indexOf("--rc");
  if (i >= 0 && process.argv[i + 1]) return process.argv[i + 1];
  const cands = [
    "C:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/RCLootCouncil",
    "C:/Program Files/World of Warcraft/_retail_/Interface/AddOns/RCLootCouncil",
  ];
  for (const c of cands) if (fs.existsSync(c)) return c;
  throw new Error("RCLootCouncil not found; pass --rc <folder>");
}
const RC_DIR = findRC();
const scenario = process.argv.find((a, i) => i >= 2 && !a.startsWith("--") && process.argv[i - 1] !== "--rc") || "smoke";

// --- resolve TOC + nested XML into an ordered .lua file list ---
function xmlIncludes(xmlPath) {
  // Returns ordered list of { type:'script'|'include', file:absPath }.
  const dir = path.dirname(xmlPath);
  const txt = fs.readFileSync(xmlPath, "utf8");
  const out = [];
  const re = /<(Script|Include)\s+file\s*=\s*"([^"]+)"/gi;
  let m;
  while ((m = re.exec(txt))) {
    const rel = m[2].replace(/\\/g, "/");
    out.push({ type: m[1].toLowerCase(), file: path.resolve(dir, rel) });
  }
  return out;
}
const skipped = [];
function expand(entryAbs, acc, seen) {
  if (!fs.existsSync(entryAbs)) { skipped.push(entryAbs); return; } // stripped/optional
  const ext = path.extname(entryAbs).toLowerCase();
  if (ext === ".lua") {
    acc.push(entryAbs);
  } else if (ext === ".xml") {
    if (seen.has(entryAbs)) return;
    seen.add(entryAbs);
    for (const inc of xmlIncludes(entryAbs)) expand(inc.file, acc, seen);
  }
}
function resolveToc(tocPath) {
  const dir = path.dirname(tocPath);
  const txt = fs.readFileSync(tocPath, "utf8");
  const acc = [], seen = new Set();
  for (const line of txt.split(/\r?\n/)) {
    const s = line.trim();
    if (!s || s.startsWith("#")) continue;
    const rel = s.replace(/\\/g, "/");
    expand(path.resolve(dir, rel), acc, seen);
  }
  return acc;
}

// --- boot Fengari ---
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function dostring(src) {
  if (lauxlib.luaL_dostring(L, to_luastring(src)) !== lua.LUA_OK) {
    throw new Error("init snippet: " + lua.lua_tojsstring(L, -1));
  }
}

// WoW passes (addonName, addonPrivateTable) as varargs to every addon file:
// RC relies on `local addon = select(2, ...)`. We do the vararg wiring in Lua
// (SIM_loadfile) — the private table is looked up in a Lua-side registry so
// every file of an addon mutates the SAME object. Defined once via bootstrap().
function bootstrapLoader() {
  dostring(`
    _ADDON_TABLES = {}
    function SIM_loadfile(src, chunkname, addonName)
      local chunk, err = load(src, "@" .. chunkname)
      if not chunk then error("compile " .. chunkname .. ": " .. tostring(err), 0) end
      if addonName then
        _ADDON_TABLES[addonName] = _ADDON_TABLES[addonName] or {}
        return chunk(addonName, _ADDON_TABLES[addonName])
      end
      return chunk()
    end
  `);
}

let CURRENT = "?";
function dofile(absPath, name, addonName) {
  CURRENT = name || path.basename(absPath);
  let src;
  try { src = fs.readFileSync(absPath, "utf8"); }
  catch (e) { throw new Error("cannot read " + CURRENT + ": " + e.message); }
  if (src.charCodeAt(0) === 0xfeff) src = src.slice(1);
  lua.lua_getglobal(L, to_luastring("SIM_loadfile"));
  lua.lua_pushstring(L, to_luastring(src));
  lua.lua_pushstring(L, to_luastring(CURRENT));
  if (addonName != null) lua.lua_pushstring(L, to_luastring(addonName));
  else lua.lua_pushnil(L);
  if (lua.lua_pcall(L, 3, 0, 0) !== lua.LUA_OK) {
    throw new Error("in " + CURRENT + ":\n  " + lua.lua_tojsstring(L, -1));
  }
}

function setGlobalString(name, val) {
  lua.lua_pushstring(L, to_luastring(val));
  lua.lua_setglobal(L, to_luastring(name));
}

try {
  // 1) Lua 5.1 shims + extended WoW mock (before anything WoW-ish loads).
  bootstrapLoader();
  setGlobalString("RC_DIR", RC_DIR.replace(/\\/g, "/"));
  dofile(path.join(REALRC_DIR, "compat.lua"), "compat.lua");
  dofile(path.join(SIM_DIR, "wow_mock.lua"), "wow_mock.lua");     // reuse base mock
  dofile(path.join(REALRC_DIR, "wow_full.lua"), "wow_full.lua");  // extend + permissive fallback

  // 2) The REAL RCLootCouncil, in TOC/embeds order.
  // Pure-UI libraries GM's loot/vote logic doesn't need. They rely on XML
  // frame templates we don't build; we skip them and register permissive
  // LibStub fakes instead (see libstub_fakes.lua), so RC's CORE still loads.
  const DENY = [
    "/Libs/AceConfig-3.0/", "/Libs/AceGUI-3.0/", "/Libs/AceGUI-3.0-SharedMediaWidgets/",
    "/Libs/AceDBOptions-3.0/", "/Libs/MSA-DropDownMenu-1.0/", "/Libs/lib-st/",
    "/Libs/LibDialog-1.0/",
    "/Patches/",   // Blizzard UI taint workaround; irrelevant headless
  ];
  const denied = (f) => DENY.some((d) => f.replace(/\\/g, "/").includes(d));

  const rcFiles = resolveToc(path.join(RC_DIR, "RCLootCouncil.toc"));
  console.log("[load_real] resolved " + rcFiles.length + " RC .lua files");
  let loaded = 0, skippedUI = 0;
  for (const f of rcFiles) {
    if (denied(f)) { skippedUI++; continue; }
    dofile(f, path.relative(RC_DIR, f).replace(/\\/g, "/"), "RCLootCouncil");
    loaded++;
    // Right after LibStub registers, inject fakes for the skipped UI libs.
    if (path.basename(f).toLowerCase() === "libstub.lua") {
      dofile(path.join(REALRC_DIR, "libstub_fakes.lua"), "libstub_fakes.lua");
    }
  }
  console.log("[load_real] RC loaded OK (" + loaded + " files, " + skippedUI + " UI-lib files stubbed)");

  // 3) Load the REAL GuildMastery addon on top of real RC (TOC order).
  dofile(path.join(ADDON_DIR, "History.lua"), "History.lua", "RCLootCouncil_GuildMastery");
  dofile(path.join(ADDON_DIR, "core.lua"), "core.lua", "RCLootCouncil_GuildMastery");
  console.log("[load_real] GuildMastery loaded OK");

  // 4) Init everything by firing the events RC's + GM's frames listen for.
  setGlobalString("SIM_CMD", scenario);
  dofile(path.join(REALRC_DIR, "boot.lua"), "boot.lua");

  console.log("\n[load_real] DONE — reached scenario '" + scenario + "'.");
} catch (e) {
  console.error("\n\x1b[31m[load_real] FAILED at: " + CURRENT + "\x1b[0m");
  console.error(String(e.message || e));
  process.exit(1);
}
