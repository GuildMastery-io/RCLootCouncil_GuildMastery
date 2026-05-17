# Changelog

## 1.1.0 — 2026-05-17

### Features

- **Local history is now bounded to 180 days.** A new `GMLootHistory:PruneOldEntries()` runs before every sync payload generation (so old sessions never leak to the companion or backend) and once at every `PLAYER_LOGIN` as a safety net for users who do not sync. Aligns with the GuildMastery web app retention policy. Debug output available with `/gm debug`.

### Internal

- `RETENTION_DAYS = 180` constant in `History.lua`. Keep this synchronized with the corresponding backend / companion constants if you ever change it.

## 1.0.0 — 2026-05-16

Initial public release on CurseForge.

### Features

- **Local 3-column history of every vote session** (date / item / candidate detail), persisted across logout via account-wide `SavedVariables`. WoW class colors on candidate rows, native item tooltips, granular deletion (date, item, individual candidate).
- **Auto-save on RC events** — silent capture when all candidates have voted, when a session ends, and when an item is awarded. 5-minute deduplication on `(session_num, item_id)` to avoid creating doublons between auto-saves.
- **One-click export badge** injected on the top of the RCLootCouncil voting frame:
  - **Left click**: opens a popup with the JSON ready to copy-paste into the GuildMastery web app.
  - **Right click**: saves the session, sets a `pendingRestore` flag, and triggers `ReloadUI()` so the SavedVariables file is flushed to disk for the GuildMasterySync companion to pick up. The voting frame is auto-restored after the reload so the master looter can keep working without interruption.
- **Unaward button** (orange undo icon) in the history detail panel — reverts an attribution locally **and** propagates the deletion to RCLootCouncil's own history (broadcast to other council members when used by the master looter).
- **Stale-session guard** — blocks reload of sessions older than 2 days to prevent restoring archived data into the current raid flow.
- **Restore previous session** — green refresh icon next to each date that re-injects unawarded items into the RC voting frame for re-voting / re-awarding.

### Slash commands

- `/gm export` / `/gm export_vote` — export the last saved session as JSON
- `/gm export_active` — export the currently active session
- `/gm history` / `/gm h` / `/gm hist` — open the history window
- `/gm dump` — explicit candidate dump in chat (diagnostics)
- `/gm debug` / `/gm dbg` — toggle debug logging (off by default)
- Alias: `/guildmastery`

### Compatibility

- World of Warcraft Retail — The War Within 12.0.5 (build 67602), Interface `120005`
- RCLootCouncil >= 3.21.1
