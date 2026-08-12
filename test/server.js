#!/usr/bin/env node
// ============================================================
// server.js — visual (non-headless) simulator. Boots ONE live Lua VM with the
// real addon + mocks, and serves a browser UI that drives it. The Lua state
// persists across requests, so the page reflects the actual addon state.
//
// Usage:  node server.js [port]      (default port 6789 — not 3000 :))
// ============================================================
const http = require("http");
const fs = require("fs");
const path = require("path");
const { execFile } = require("child_process");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const PORT = Number(process.argv[2] || process.env.SIM_PORT || 6789);
const ADDON_DIR = path.resolve(__dirname, "..");
const SIM_DIR = __dirname;

// ---- boot the Lua VM ----
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function dofile(absPath, name) {
  let src = fs.readFileSync(absPath, "utf8");
  if (src.charCodeAt(0) === 0xfeff) src = src.slice(1);
  if (lauxlib.luaL_loadbuffer(L, to_luastring(src), null, to_luastring("@" + name)) !== lua.LUA_OK ||
      lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0) !== lua.LUA_OK) {
    throw new Error("Lua load error in " + name + ": " + lua.lua_tojsstring(L, -1));
  }
}
for (const [p, n] of [
  [path.join(SIM_DIR, "wow_mock.lua"), "wow_mock.lua"],
  [path.join(SIM_DIR, "rc_mock.lua"), "rc_mock.lua"],
  [path.join(SIM_DIR, "fakedata.lua"), "fakedata.lua"],
  [path.join(ADDON_DIR, "History.lua"), "History.lua"],
  [path.join(ADDON_DIR, "core.lua"), "core.lua"],
  [path.join(SIM_DIR, "harness.lua"), "harness.lua"],
  [path.join(SIM_DIR, "web_api.lua"), "web_api.lua"],
]) dofile(p, n);

// Call WebAPI_dispatch(action, a1, a2, a3) and return the JSON string it builds.
function dispatch(action, args) {
  args = args || [];
  lua.lua_getglobal(L, to_luastring("WebAPI_dispatch"));
  lua.lua_pushstring(L, to_luastring(String(action)));
  for (let i = 0; i < 3; i++) {
    if (args[i] === undefined || args[i] === null) lua.lua_pushnil(L);
    else lua.lua_pushstring(L, to_luastring(String(args[i])));
  }
  if (lua.lua_pcall(L, 4, 1, 0) !== lua.LUA_OK) {
    const err = lua.lua_tojsstring(L, -1);
    lua.lua_pop(L, 1);
    return JSON.stringify({ ok: false, log: ["[server] Lua error: " + err], state: null });
  }
  const out = lua.lua_tojsstring(L, -1);
  lua.lua_pop(L, 1);
  return out;
}

// Call a no-arg Lua global returning a string (e.g. WebAPI_savedvars).
function callLuaString(name) {
  lua.lua_getglobal(L, to_luastring(name));
  if (lua.lua_pcall(L, 0, 1, 0) !== lua.LUA_OK) {
    const err = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1);
    throw new Error(err);
  }
  const out = lua.lua_tojsstring(L, -1); lua.lua_pop(L, 1);
  return out;
}

// Dump the live SavedVariables to sim/out/RCLootCouncil_GuildMastery.lua
const OUT_DIR = path.join(SIM_DIR, "out");
const SV_PATH = path.join(OUT_DIR, "RCLootCouncil_GuildMastery.lua");
function writeSavedVars() {
  fs.mkdirSync(OUT_DIR, { recursive: true });
  const body = callLuaString("WebAPI_savedvars");
  fs.writeFileSync(SV_PATH, body, "utf8");
  return { path: SV_PATH, bytes: Buffer.byteLength(body) };
}

// ---- HTTP ----
function send(res, code, type, body) {
  res.writeHead(code, { "Content-Type": type, "Cache-Control": "no-store" });
  res.end(body);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");

  if (req.method === "GET" && url.pathname === "/") {
    return send(res, 200, "text/html; charset=utf-8", fs.readFileSync(path.join(SIM_DIR, "index.html")));
  }

  if (req.method === "POST" && url.pathname === "/api/cmd") {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      let action = "state", args = [];
      try { const j = JSON.parse(body || "{}"); action = j.action || "state"; args = j.args || []; } catch {}
      const out = dispatch(action, args);
      try { writeSavedVars(); } catch (e) { /* keep serving even if the dump fails */ }
      send(res, 200, "application/json", out);
    });
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/export") {
    try {
      const info = writeSavedVars();
      send(res, 200, "application/json", JSON.stringify({ ok: true, path: info.path, bytes: info.bytes }));
    } catch (e) {
      send(res, 200, "application/json", JSON.stringify({ ok: false, error: String(e) }));
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/contract") {
    const dir = url.searchParams.get("dir");
    const argv = dir ? [path.join(SIM_DIR, "contract.js"), dir] : [path.join(SIM_DIR, "contract.js")];
    execFile(process.execPath, argv, (err, stdout, stderr) => {
      const clean = (stdout + (stderr || "")).replace(/\x1b\[[0-9;]*m/g, "");
      send(res, 200, "application/json", JSON.stringify({ ok: !err, text: clean }));
    });
    return;
  }

  send(res, 404, "text/plain", "not found");
});

server.listen(PORT, () => {
  console.log("\n  RCLootCouncil_GuildMastery — visual simulator");
  console.log("  Real addon loaded into a mocked WoW + RC 3.23.0 environment.\n");
  console.log("  ▶  http://localhost:" + PORT + "\n");
  console.log("  (Ctrl+C to stop; change port with: node server.js <port>)\n");
});
