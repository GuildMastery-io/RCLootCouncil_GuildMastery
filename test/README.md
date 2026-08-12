# RCLootCouncil_GuildMastery — local simulator

A tiny offline harness that **runs the real addon Lua** (`../History.lua`,
`../core.lua`) inside a mocked World of Warcraft + RCLootCouncil environment, so
you can test loot/vote/reload logic **without launching the game or being in a
raid**.

This folder is **versioned but never shipped** — the release zip only packages
the addon files (`.toc`, `core.lua`, `History.lua`, `Media/`), so `test/` (and
its `node_modules/`) never reach players.

## Requirements

- Node.js (already used here: v22). Fengari (a Lua 5.4 VM in JS) is the only
  dependency and is installed locally.

```bash
cd test
npm install        # once
```

## Visual mode (browser)

```bash
node server.js          # http://localhost:6789  (change: node server.js 8899)
```

Opens a live control panel: enter a raid, start a session, click Need/Greed and
▲vote per candidate, advance the virtual clock, then hit the **Save & Reload**
badge and **Relog** — the loot table redraws and you can see the votes/voters
survive (or not). Runs the scenario suite, `/gm testrestore`, and the RC
contract check from buttons too. One authoritative Lua state (the real addon)
backs the whole page.

## What it does (headless)

Two independent checks:

### 1. Functional harness — "does the addon work / did I break it?"

```bash
node run.js            # runs all scenarios (default)
node run.js smoke      # load + hooks + badge injection
node run.js testrestore # the addon's own /gm testrestore self-test
node run.js reload     # save+reload during a session keeps votes/voters
node run.js dedup      # council votes refresh the saved snapshot (no stale 0)
```

It loads the **actual** addon files, so a syntax error or a broken assumption
fails here immediately. Exit code is non-zero if any assertion fails.

Key moving parts:
- `wow_mock.lua` — WoW API surface + a **virtual clock** (`Sim.advance(sec)`)
  and a deterministic timer scheduler, so time-dependent logic (the 5-min dedup
  window) is testable instantly.
- `rc_mock.lua` — a faithful-enough RCLootCouncil (mirrors 3.23.0), including
  the `VotingFrame:Setup` "added-gate" and `HandleVote` semantics the addon
  relies on.
- `fakedata.lua` — players / loot / bosses / difficulties + builders to stage a
  live session with responses and council votes.
- `harness.lua` — the scenarios and assertions.

### 1b. Run the REAL RCLootCouncil — `realrc/`

The scenarios above mock RC. To actually **execute the real RCLootCouncil**
(real Ace libs + real RC Lua) with GM hooking its genuine modules, see
[`realrc/`](realrc/README.md):

```bash
node realrc/load_real.js smoke     # load real RC + GM, boot report
node realrc/load_real.js reload    # drive GM's restore through the real VotingFrame
```

### 2. API contract check — "did a new RCLootCouncil break us?"

```bash
node contract.js                          # auto-detects the retail RC folder
node contract.js "D:/path/to/RCLootCouncil" # or point it anywhere
```

Statically scans a RCLootCouncil install for every RC symbol the addon depends
on (module names, VotingFrame/ML methods, candidate fields) and reports
`OK`/`MISS` with `file:line`. This is what would have caught the `RCMLCore`
bug. The required symbols live in `contract.json` — edit it as the addon's RC
usage evolves.

## Typical workflow when a new RCLootCouncil ships

1. Drop the new RCLootCouncil into the WoW AddOns folder (or anywhere).
2. `node contract.js "<that folder>"` → confirm no `MISS`.
3. If a symbol changed, update `rc_mock.lua` to match the new behaviour.
4. `node run.js` → confirm all scenarios still pass.

## Limitations

- The RC mock reproduces only the behaviour the addon touches — it is **not**
  RCLootCouncil. `contract.js` is the guard for RC-side changes.
- The live cross-client comms path (real council members voting over the
  network) is not simulated; that still needs a party/alt in-game.
