-- ============================================================
-- fakedata.lua — players / loot / raids / dates for the simulator.
-- Provides Sim.players and builder helpers that populate the mock RC
-- VotingFrame + ML with a realistic live session (responses + council votes).
-- ============================================================

-- ---- Players (name-Realm -> profile) ----
Sim.players = {
    ["Ged-Uldaman"]      = { class = "PALADIN", role = "MELEE",  rank = "Guild Master", spec_id = 70 },
    ["Ashkandi-Uldaman"] = { class = "WARRIOR", role = "MELEE",  rank = "Officer",      spec_id = 71 },
    ["Moro-Uldaman"]     = { class = "MAGE",    role = "RANGED", rank = "Raider",       spec_id = 63 },
    ["Sylae-Hyjal"]      = { class = "PRIEST",  role = "HEALER", rank = "Raider",       spec_id = 256 },
    ["Draknar-Hyjal"]    = { class = "DEATHKNIGHT", role = "MELEE", rank = "Trial",     spec_id = 251 },
}

-- ---- Difficulties (WoW difficultyID) ----
Sim.difficulties = {
    LFR    = { id = 17, name = "Looking For Raid" },
    Normal = { id = 14, name = "Normal" },
    Heroic = { id = 15, name = "Heroic" },
    Mythic = { id = 16, name = "Mythic" },
}

-- ---- Bosses / raid ----
Sim.raid = {
    zone = "Liberation of Undermine",
    bosses = { "Vexie and the Geargrinders", "Cauldron of Carnage", "Rik Reverb", "Mug'Zee" },
}

-- ---- Loot items ----  quality: 4=epic, 5=legendary. icon = emoji stand-in.
Sim.loot = {
    { id = 232800, name = "Geargrinder's Spare Keys",     ilvl = 639, boss = "Vexie and the Geargrinders", slot = "Trinket",       quality = 4, icon = "🔧" },
    { id = 232801, name = "Cauldron-Tempered Chestplate", ilvl = 645, boss = "Cauldron of Carnage",        slot = "Chest",         quality = 4, icon = "🛡️" },
    { id = 232802, name = "Reverb Amplifier Ring",        ilvl = 639, boss = "Rik Reverb",                 slot = "Finger",        quality = 4, icon = "💍" },
    { id = 232803, name = "Mug'Zee's Enforcement Baton",  ilvl = 652, boss = "Mug'Zee",                    slot = "Two-Hand Mace", quality = 5, icon = "🔨" },
    { id = 232804, name = "Sprocketwatcher's Drape",      ilvl = 639, boss = "Sprocketmonger Lockenstock", slot = "Back",          quality = 4, icon = "🧣" },
    { id = 232805, name = "Chromebustion Shoulderplates", ilvl = 645, boss = "One-Armed Bandit",           slot = "Shoulder",      quality = 4, icon = "⛏️" },
}
Sim.lootById = {}
for _, it in ipairs(Sim.loot) do
    it.link = Sim.registerItem(it.id, it.name, it.ilvl)
    Sim.lootById[it.id] = it
end

-- Configure the current instance context used by GetInstanceInfo / zone text.
function Sim.enterRaid(difficultyKey)
    local d = Sim.difficulties[difficultyKey or "Mythic"]
    Sim.zone = Sim.raid.zone
    Sim.difficultyID = d.id
    Sim.difficultyName = d.name
    Sim.setGroup({ "Ged-Uldaman", "Ashkandi-Uldaman", "Moro-Uldaman", "Sylae-Hyjal", "Draknar-Hyjal" })
end

-- Build a live loot session on the mock VotingFrame + ML.
--   items: array of { loot=<Sim.loot entry>, boss=<string> }
-- Sessions start with everyone ANNOUNCED and zero votes (as in-game).
function Sim.startSession(items)
    local vf, ml = Sim.vf, Sim.ml
    local lt = {}
    ml.lootTable = {}
    for idx, spec in ipairs(items) do
        local loot = spec.loot
        local entry = {
            link = loot.link, texture = loot.texture, ilvl = loot.ilvl, itemID = loot.id,
            typeCode = "default", equipLoc = "INVTYPE_HEAD", boss = spec.boss,
            awarded = nil, added = nil, candidates = {},
        }
        lt[idx] = entry
        ml.lootTable[idx] = { link = loot.link, session = idx, typeCode = "default",
                              awarded = false, boss = spec.boss }
    end
    ml.running = true
    ml.isHistoricalLoad = false
    -- ReceiveLootTable runs the real Setup (added is nil -> candidates created).
    vf:ReceiveLootTable(lt)
    return vf:GetLootTable()
end

-- Append one loot item to the CURRENT session (starts one if none is running).
-- Existing sessions keep their votes (added=true -> RC Setup preserves them);
-- the new entry (added=nil) gets fresh ANNOUNCED candidates.
function Sim.addLootItem(itemId)
    local loot = Sim.lootById[tonumber(itemId)]
    if not loot then return end
    local vf, ml = Sim.vf, Sim.ml
    local lt = vf:GetLootTable() or {}
    ml.lootTable = ml.lootTable or {}
    local idx = #lt + 1
    lt[idx] = {
        link = loot.link, texture = loot.texture, ilvl = loot.ilvl, itemID = loot.id,
        typeCode = "default", equipLoc = "INVTYPE_HEAD", boss = loot.boss,
        awarded = nil, added = nil, candidates = {},
    }
    ml.lootTable[idx] = { link = loot.link, session = idx, typeCode = "default", awarded = false, boss = loot.boss }
    ml.running = true
    ml.isHistoricalLoad = false
    vf:ReceiveLootTable(lt)
    return idx
end

-- Set a candidate's own loot response (Need/Greed/etc.) via the RC setter,
-- so the addon's SetCandidateData("response") hook fires just like in-game.
--   code: RC numeric response code (1=MainSpec, 2=OffSpec, ...) as string/number
function Sim.setResponse(session, name, code, ilvl, diff)
    local vf = Sim.vf
    vf:SetCandidateData(session, name, "response", tonumber(code) or code)
    if ilvl then vf:SetCandidateData(session, name, "ilvl", ilvl) end
    if diff then vf:SetCandidateData(session, name, "diff", diff) end
end

-- Cast a council up-vote (mirrors a councilman clicking the vote button).
-- Goes through HandleVote -> mutates votes/voters WITHOUT touching response.
function Sim.castVote(voter, session, name, vote)
    Sim.vf:HandleVote(voter, session, name, vote or 1)
end

-- Convenience: a fully-voted session fixture (responses + votes) for one item.
function Sim.populateContestedItem(session)
    Sim.setResponse(session, "Ashkandi-Uldaman", 1, 640.2, 4.8)   -- MainSpec
    Sim.setResponse(session, "Ged-Uldaman",      1, 641.0, 4.0)   -- MainSpec
    Sim.setResponse(session, "Moro-Uldaman",     2, 638.5, 6.5)   -- OffSpec
    Sim.setResponse(session, "Sylae-Hyjal",      1, 637.0, 8.0)   -- MainSpec
    -- Council votes come in AFTER responses (the crux of weakness A).
    Sim.castVote("Ged-Uldaman",      session, "Ashkandi-Uldaman")
    Sim.castVote("Ashkandi-Uldaman", session, "Ashkandi-Uldaman")
    Sim.castVote("Moro-Uldaman",     session, "Ashkandi-Uldaman")
    Sim.castVote("Ged-Uldaman",      session, "Ged-Uldaman")
    Sim.castVote("Sylae-Hyjal",      session, "Sylae-Hyjal")
end
