# RCLootCouncil_GuildMastery (addon) — working conventions

Public repo. Keep it clean and professional.

## Code style
- Comments and code in **English**. (Conversations with the maintainer are in French.)
- Comment only the non-obvious — the *why*, not the *what*. Do not add noise.

## Versioning & changelog
- Any **new addon version** gets a **mini changelog in English** in `CHANGELOG.md`.

## Release notes → Discord changelog
Every change shipped to the **addon**, the **web app** (nocturnys), or the **sync app** must come with a short, **English**, user-facing note suitable for posting in the Discord updates/changelog channel. Keep it concise (what changed, why it matters to users). Provide it alongside the change so the maintainer can copy-paste it.

Sibling repos: `../GuildMasterySync` (sync app), `../nocturnys` (web app/server). The loot sync protocol spans all three — keep the shared identity/authority rules in sync.
