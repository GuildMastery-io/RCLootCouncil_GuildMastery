# realrc — run the ACTUAL RCLootCouncil (not a mock)

This mode loads the **real RCLootCouncil** (real Ace3 libraries + real RC Lua,
in TOC/embeds order) into Fengari, on top of Lua 5.1 shims and an extended WoW
API mock, then loads the **real GuildMastery** addon on top — so GM hooks the
genuine `RCVotingFrame` / `RCLootCouncilML` modules.

Use it to answer: *"if I drop in a new RCLootCouncil, does GuildMastery still
load and work against it?"* — actually executing RC, not just checking symbols.

```bash
cd test/realrc
node load_real.js smoke     # load real RC + GM, print a boot report
node load_real.js reload    # + drive GM's restore through the REAL VotingFrame
node load_real.js --rc "D:/path/to/RCLootCouncil" smoke   # point at any RC copy
```

## What a green run proves

```
[load_real] RC loaded OK (82 files, 38 UI-lib files stubbed)
[load_real] GuildMastery loaded OK
=========== REAL-RC BOOT REPORT ===========
RCLootCouncil addon object : true
  version field            : 3.23.0
  RCVotingFrame module     : true      <- real module
  masterlooter module      : true      <- real module
GM badge on real VotingFrame: true     <- GM hooked the REAL frame
...
----- REAL-RC RELOAD TEST -----
RESULT: PASS - GM drove the real VotingFrame and votes survived
```

## How it works / the tricky bits

- `compat.lua` — Lua 5.1 shims: `unpack`, `loadstring`, `setfenv/getfenv`
  (via the debug library), a `bit` table, and a `string.gsub` shim for the 5.1
  replacement-string leniency RC relies on (`%(`, `%1`-without-capture).
- `wow_full.lua` — a much wider WoW API than the base mock, plus the `_G`
  fallback: **unknown globals read as nil** (so Ace libraries bootstrap
  correctly — a truthy fallback makes every lib think it's already loaded),
  **except ALL-CAPS keys**, which read as their own name (WoW UI string
  constants like `DAMAGER`, `ITEM_MOD_*_SHORT`). Unmocked globals are counted
  and the top offenders printed at the end.
- `load_real.js` — resolves the `.toc` + nested `.xml` includes into an ordered
  file list, passes each addon file the `(addonName, privateTable)` varargs WoW
  provides (`local addon = select(2, ...)`), and **stubs the pure-UI libraries**
  (AceGUI, AceConfig, lib-st, MSA-DropDownMenu, LibDialog, AceDBOptions) that
  rely on XML frame templates — GM's loot/vote/reload logic never needs them.
- `libstub_fakes.lua` — registers inert LibStub stand-ins for those skipped libs.
- `boot.lua` — fires `ADDON_LOADED` / `PLAYER_LOGIN`, prints the boot report,
  and (scenario `reload`) drives GM's `InjectItemsIntoVF` into the real frame.

## Limitations

- The RC **UI does not render** (AceGUI/lib-st/MSA are stubbed), so frame-drawing
  code no-ops and a couple of caught, non-fatal UI errors may print during the
  reload test — the loot-table **data** path (what GM reads/writes) runs for real.
- Comms are not networked (single client), so multi-councilman voting still needs
  the game.
- If a new RC pulls in a WoW global we haven't mocked, you'll see it in the
  "unmocked globals" list — add it to `wow_full.lua`.
