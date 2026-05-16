[![GitHub release](https://img.shields.io/github/v/release/GuildMastery-io/RCLootCouncil_GuildMastery?include_prereleases&label=release)](https://github.com/GuildMastery-io/RCLootCouncil_GuildMastery/releases)
[![WoW Retail](https://img.shields.io/badge/WoW-12.0.5-F8B700?logo=battle.net&logoColor=white)](https://worldofwarcraft.com/)
[![Discord](https://img.shields.io/badge/Discord-join-7289DA?logo=discord&logoColor=white)](https://discord.gg/AVRSs9P2Xk)
[![Website](https://img.shields.io/badge/website-guildmastery.io-9B7EDE)](https://www.guildmastery.io)

# RCLootCouncil - GuildMastery

A [RCLootCouncil](https://github.com/evil-morfar/RCLootCouncil2) extension that captures, archives and exports loot vote sessions as JSON, ready to be ingested by the [GuildMastery](https://www.guildmastery.io) web app.

## Features

- **Local history of every vote session** persisted across logout (account-wide `SavedVariables`).
- **3-column browser** (date / item / candidate detail) with WoW class colors, item tooltips, granular deletion.
- **Auto-save on RC events** — silent capture when all candidates have voted, when a session ends, and when an item is awarded. 5-minute deduplication on `(session_num, item_id)` to avoid duplicates between auto-saves.
- **One-click export** — a small badge button injected on the top-right corner of the RCLootCouncil voting frame:
  - **Left click**: open a popup with the JSON ready to copy-paste into the GuildMastery web app.
  - **Right click**: save the session + `ReloadUI()` so the SavedVariables file is flushed to disk for the GuildMasterySync companion to pick up. The session is auto-restored in the voting frame after the reload.
- **Unaward button** (orange undo icon) in the history detail panel — reverts an attribution locally **and** propagates the deletion to RCLootCouncil's own history (broadcast to other council members if you are the master looter).
- **Stale-session guard** — blocks restoration of sessions older than 2 days to avoid polluting current raid flow with archived data.
- **Restore previous session** — green refresh icon next to each date that re-injects the unawarded items into the RC voting frame for re-voting / re-awarding.

## Slash commands

| Command | Action |
|---|---|
| `/gm export` | Export the most recent saved session as JSON |
| `/gm export_active` | Export the currently active voting session |
| `/gm history` | Open/close the history window |
| `/gm dump` | Dump the current loot table candidates in chat (diagnostics) |
| `/gm debug` | Toggle debug logging on/off (off by default) |

Alias: `/guildmastery`.

## Installation

Drop the `RCLootCouncil_GuildMastery` folder into `Interface\AddOns\` and reload your UI. `RCLootCouncil` must be installed and enabled.

## Requirements

- World of Warcraft Retail — The War Within 12.0.5 (build 67602), Interface `120005`
- `RCLootCouncil` >= 3.21.1

## JSON export schema

The exported payload follows this shape (consumed by GuildMastery `saveRcExport` server action):

```json
{
  "addon": "RCLootCouncil_GuildMastery",
  "version": "1.0.0",
  "timestamp": "2026-05-16T22:36:00Z",
  "difficulty_id": 16,
  "difficulty_name": "Mythic",
  "sessions": [
    {
      "session": 1,
      "item": "Regard de prophète d'Aln",
      "item_link_raw": "|cff...|Hitem:232556::::::::289:268::44::::::::|h[Regard de prophète d'Aln]|h|r",
      "item_id": 232556,
      "item_ilvl": 289,
      "awarded_to": "Ged-Uldaman",
      "looted_at": 1747432596,
      "candidates": [
        {
          "name": "Ged-Uldaman",
          "class": "PALADIN",
          "role": "MELEE",
          "rank": "Officer",
          "spec_id": 70,
          "response": "Free Upgrade",
          "response_code": "AWARDED",
          "real_response_code": "1",
          "ilvl": 284.9,
          "ilvl_diff": 4.1,
          "roll": 27,
          "votes": 1,
          "voters": ["Ged-Uldaman"],
          "note": "",
          "equipped": []
        }
      ]
    }
  ]
}
```

## Architecture

- `core.lua` (~790 lines) — RC hooks, slash commands, JSON serializer, the badge button, the save-and-reload flow.
- `History.lua` (~1530 lines) — `GMLootHistory` API (SaveSessions, GetLastSavedSessions, GetAllSessions, Toggle), 3-column UI, stale-session guard, unaward button, RC history sync.

Public API exposed to other addons:

```lua
-- Save sessions into GM history (deduplicated). Returns count.
GMLootHistory:SaveSessions(sessions, dedup)

-- Re-inject items into the RC voting frame from a list of history entries.
GMLootHistory:InjectItemsIntoVF(items, { silent = bool, onSuccess = fn, onError = fn })

-- Toggle / show / hide the history window.
GMLootHistory:Toggle()
GMLootHistory:Show()
GMLootHistory:Hide()
```

## SavedVariables

Stored in `WTF/Account/<accountname>/SavedVariables/RCLootCouncil_GuildMastery.lua`:

| Key | Type | Purpose |
|---|---|---|
| `history` | array | Accumulated history entries |
| `lastExport` | string | Last JSON export payload (consumed by external sync tools) |
| `syncPayload` | string | Full-sync JSON of every entry |
| `lastUpdated` | string | ISO-8601 timestamp of the last save |
| `pendingRestore` | table\|nil | Transient flag set before `ReloadUI()`, consumed at next login |
| `debug` | bool | Debug logging flag (toggled by `/gm debug`) |
| `version` | int | Schema version (currently `1`) |

## Bug reports & feedback

- Preferred: open an issue on [GitHub](https://github.com/GuildMastery-io/RCLootCouncil_GuildMastery/issues)
- Or join the [GuildMastery Discord](https://discord.gg/AVRSs9P2Xk) and post in the addon support channel

## License

All rights reserved — see [LICENSE](LICENSE). The source is published for transparency, reference, and bug reporting. Forks, modifications and redistributions require prior written permission.

## Credits

Authored by **Ged** (Uldaman-EU) as an extension to [RCLootCouncil](https://github.com/evil-morfar/RCLootCouncil2) maintained by [evil-morfar](https://github.com/evil-morfar).
