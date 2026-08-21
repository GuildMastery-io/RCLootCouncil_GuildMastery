# Changelog

## 1.4.2 — 2026-08-21

### Fixes

- Fixed a Lua error that could stop certain `/gm history` sessions from opening or reloading.
- A player's vote reason (such as "upgrade") is no longer lost when you un-award an item.
- Re-awarding an item from a reloaded session now records the award in RCLootCouncil's own history too, not just `/gm history`.
- Players' notes are no longer all replaced by an empty note after reloading a session.

## 1.4.1 — 2026-08-18

### Fixes

- **Single-item session no longer skips the "all votes in" save.** `CheckAllResponsesReceived` built its de-spam key (`stateHash`) from the session index only, so two consecutive single-item sessions both hashed to `"1-"`. When every response arrived within one debounce window (no intervening not-all-responded pass to reset the guard), the second session collided with the first's saved state and was silently skipped — leaving no `/gm history` entry to reopen after closing the frame. A 2-item session (`"1-2-"`) never collided, which is why the bug only showed with a single loot. `stateHash` now includes `item_id` + `awarded_to`, so distinct loot is always distinct.
- **Awarding an item in a reloaded session now updates `/gm history`.** Restoring a session via `/gm history` sets `isHistoricalLoad`, which used to short-circuit **every** auto-save — so an award made on the reloaded session reached RCLootCouncil's own history but never `/gm history` (it kept showing the item as un-awarded; the only workaround was left-clicking the GuildMastery badge to force a save). The guard is now removed from `AutoSaveFromRC` only: it runs solely from the `Award`/`EndSession` hooks (never from the re-injection cascade, which still goes through the guarded `CheckAllResponsesReceived`/`RefreshCurrentSessionVotes`), so the award is persisted through the normal 5-minute-dedup save and updates the reloaded entry in place.
- **Candidate roles no longer show "None" after a reload.** RCLootCouncil freezes `candidate.role` at announce time (`player.role or "NONE"`) and never refreshes it, even though it keeps `specID` up to date. Old/late entries therefore stored `role = "NONE"` while the spec was perfectly known, and the reload displayed "None". The role is now derived from the spec (`GetSpecializationInfoByID`) when the stored role is missing/NONE — applied both at save time and on reload.

### Tooling

- Offline test suite gains `singleitem` and `reloadAward` regression scenarios (both proven to fail without their fix); real-RC 3.23.0 reload harness and a headless web-API driver validate the same paths end-to-end.
- **CI now publishes to CurseForge automatically** via `BigWigsMods/packager` (on each `vX.Y.Z` tag), in addition to the GitHub release.

## 1.4.0 — 2026-08-12

### Compatibility

- **World of Warcraft Retail 12.1.0** (build 69273) — Interface bumped `120005` → `120100`.
- **Verified against RCLootCouncil 3.23.0.** Every RC API touchpoint (VotingFrame `ReceiveLootTable`/`SetCandidateData`, candidate `votes`/`voters`/`response`/`real_response`, ML `lootTable`/`Award`, `GetTypeCodeForItem`, `GetHistoryDB`/`UnTrackAndLogLoot`) was checked; RC's 3.23.0 additions (Column API, opt-in Session Data) are additive and do not affect this addon.

### Fixes

- **Wrong ML module name (`RCMLCore`) corrected to the real one.** `core.lua` fetched the Master Looter module via `GetModule("RCMLCore")`, which **never existed** in RCLootCouncil (the module is `RCLootCouncilML`, type `masterlooter`). Two consequences are now fixed: (1) the `isHistoricalLoad` guard — meant to stop auto-save from re-capturing a *restored* session — never triggered, and (2) the `Award`/`AwardItem` hooks were never installed. A new `GetMLModule()` helper mirrors `History.lua`'s already-correct `GetActiveModule("masterlooter")`.
- **Reload restore is now selected by stable entry `id`, not by timestamp.** The post-reload auto-restore matched history entries with `timestamp == GetLatestTimestamp()`. That equality was fragile (second-boundary splits, colliding duplicates) and could restore a subset or the wrong entry. `SaveSessions` now returns the ids it wrote and `pendingRestore` restores exactly that set (timestamp match kept as a legacy fallback).
- **Council votes now refresh the saved snapshot.** RC applies up-votes with a direct table write inside `HandleVote` (no `response` change), so the response-driven auto-save missed them and a saved entry could keep a stale `votes = 0`. A new debounced, silent refresh (`HandleVote` hook → `RefreshCurrentSessionVotes`) re-captures the live loot table so the dedup updates the recent entry with current votes.

### Tooling

- **`/gm testrestore`** — offline self-test of the save → reload → restore vote-preservation path. Fabricates a session with votes, runs the real save + id-based restore selection, and diffs the result — no raid or live RC session required. (The live VotingFrame injection itself still needs a real session.)

## 1.3.0 — 2026-07-25

### Fixes

- **Raid difficulty is now preserved in the history.** `GetInstanceInfo()` was correctly read at export time, but `SaveSessions` did not store `difficulty_id`/`difficulty_name` in the history entry. As a result the full sync (`GetAllSessions`) returned loot with no difficulty, and the web app defaulted it to Normal (e.g. a Mythic ilvl 298 item treated as Normal). Difficulty is now persisted on save, backfilled when a duplicate is merged (first capture out of instance → re-capture in the raid), and exposed by `GetAllSessions`/`GetLastSavedSessions`.
- Note: only affects loot captured **after** this update. Older history entries remain without difficulty (the web app derives it from item level).

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
