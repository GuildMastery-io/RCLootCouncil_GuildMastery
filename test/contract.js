#!/usr/bin/env node
// ============================================================
// contract.js — static check that a RCLootCouncil install still exposes every
// API symbol RCLootCouncil_GuildMastery depends on. Run this after dropping in
// a NEW RCLootCouncil to catch RC-side renames/removals (the "RCMLCore" class
// of breakage) BEFORE loading the game.
//
// Usage:
//   node contract.js                       # auto-detect the retail RC folder
//   node contract.js "<path to RCLootCouncil folder>"
// ============================================================
const fs = require("fs");
const path = require("path");

const CONTRACT = require("./contract.json");

// Candidate locations for the installed RCLootCouncil (first that exists wins).
const DEFAULT_RC_DIRS = [
  "C:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/RCLootCouncil",
  "C:/Program Files/World of Warcraft/_retail_/Interface/AddOns/RCLootCouncil",
];

function findRCDir(argDir) {
  if (argDir) {
    if (!fs.existsSync(argDir)) fail("target folder does not exist: " + argDir);
    return argDir;
  }
  for (const d of DEFAULT_RC_DIRS) if (fs.existsSync(d)) return d;
  fail("could not auto-detect RCLootCouncil; pass the folder path as an argument.");
}

function fail(msg) {
  console.error("\x1b[31m[contract] " + msg + "\x1b[0m");
  process.exit(2);
}

// Recursively collect .lua sources, remembering per-file line offsets so we can
// report file:line for a match against the concatenated blob.
function collectLua(dir) {
  const files = [];
  (function walk(d) {
    for (const name of fs.readdirSync(d)) {
      const p = path.join(d, name);
      const st = fs.statSync(p);
      if (st.isDirectory()) {
        if (name === "Libs" || name === ".git") continue; // skip vendored libs
        walk(p);
      } else if (name.endsWith(".lua")) {
        files.push(p);
      }
    }
  })(dir);
  return files;
}

function locate(files, regex) {
  for (const f of files) {
    const lines = fs.readFileSync(f, "utf8").split(/\r?\n/);
    for (let i = 0; i < lines.length; i++) {
      if (regex.test(lines[i])) {
        return { file: f, line: i + 1 };
      }
    }
  }
  return null;
}

const rcDir = findRCDir(process.argv[2]);
const files = collectLua(rcDir);
console.log("[contract] scanning " + files.length + " .lua files in:\n  " + rcDir + "\n");

let missing = 0;
const green = (s) => "\x1b[32m" + s + "\x1b[0m";
const red = (s) => "\x1b[31m" + s + "\x1b[0m";

for (const sym of CONTRACT.symbols) {
  const hit = locate(files, new RegExp(sym.pattern));
  if (hit) {
    const rel = path.relative(rcDir, hit.file).replace(/\\/g, "/");
    console.log("  " + green("OK  ") + sym.name.padEnd(32) + " " + rel + ":" + hit.line);
  } else {
    missing++;
    console.log("  " + red("MISS") + " " + sym.name.padEnd(32) + " (" + sym.note + ")");
  }
}

console.log("");
if (missing === 0) {
  console.log(green("[contract] PASS: all " + CONTRACT.symbols.length + " RC API symbols present."));
  process.exit(0);
} else {
  console.log(red("[contract] FAIL: " + missing + " symbol(s) missing — RCLootCouncil_GuildMastery may break."));
  process.exit(1);
}
