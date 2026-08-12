-- ============================================================
-- harness.lua — drives the REAL addon through the mocked WoW+RC environment.
-- Defines Sim.run(scenario) used by run.js. Scenarios return via SIM exit code
-- (0 = all assertions passed, 1 = at least one failed / errored).
-- ============================================================

Sim.pass, Sim.fail = 0, 0
local function ok(cond, label)
    if cond then
        Sim.pass = Sim.pass + 1
        print("  [PASS] " .. label)
    else
        Sim.fail = Sim.fail + 1
        print("  [FAIL] " .. label)
    end
    return cond
end

-- ---- drivers ----
function Sim.login()
    Sim.fireEvent("PLAYER_LOGIN")
    Sim.advance(6)          -- runs TryHookRC(3) / CheckPendingRestore(4) / prune(2)
end

-- Simulate a UI reload: WoW wipes the running session + frames but KEEPS the
-- SavedVariables (RCLootCouncil_GuildMasteryDB). pendingRestore therefore
-- survives, exactly as in-game.
function Sim.relog()
    Sim.ml.running = false
    Sim.ml.isHistoricalLoad = false
    Sim.ml.lootTable = {}
    Sim.vf.__lt = {}
    Sim.reloadRequested = false
    Sim.login()
end

-- Right-click the GuildMastery badge => SaveAndReload().
function Sim.clickBadgeReload()
    local f = Sim.vf:GetFrame()
    local btn = f and f.gmSaveBtn
    if not (btn and btn.__scripts.OnClick) then
        print("  [ERR] badge button not found (TryHookRC / AddSaveButton failed)")
        return false
    end
    btn.__scripts.OnClick(btn, "RightButton")
    return true
end

-- Fingerprint of the live loot table votes: name -> "votes|voter1,voter2".
function Sim.voteFP(session)
    local lt = Sim.vf:GetLootTable()
    local s = lt[session]
    local fp = {}
    if s and s.candidates then
        for name, c in pairs(s.candidates) do
            fp[name] = tostring(c.votes or 0) .. "|" .. table.concat(c.voters or {}, ",")
        end
    end
    return fp
end

local function fpEqual(a, b)
    for k, v in pairs(a) do if b[k] ~= v then return false, k end end
    for k, v in pairs(b) do if a[k] ~= v then return false, k end end
    return true
end

local function countHistory(item_id)
    local db = RCLootCouncil_GuildMasteryDB or {}
    local n = 0
    for _, e in ipairs(db.history or {}) do
        if e.item_id == item_id then n = n + 1 end
    end
    return n
end

local function resetDB()
    RCLootCouncil_GuildMasteryDB = { history = {}, version = 1 }
end

-- ============================================================
-- Scenarios
-- ============================================================
local Scenarios = {}

-- Loads the addon and pokes the basic surfaces; catches load-time / hook-time
-- Lua errors ("does anything blow up").
function Scenarios.smoke()
    print("== smoke ==")
    resetDB()
    Sim.enterRaid("Mythic")
    Sim.login()
    ok(type(GMLootHistory) == "table", "GMLootHistory global present")
    ok(type(SlashCmdList["GUILDMASTERY"]) == "function", "/gm slash handler registered")
    ok(Sim.vf:GetFrame().gmSaveBtn ~= nil, "GuildMastery badge injected onto voting frame")
    ok(type(RCLootCouncil_GuildMastery_UpdateSyncPayload) == "function", "sync payload builder present")
    -- exercise a couple of commands
    SlashCmdList["GUILDMASTERY"]("dump")
    SlashCmdList["GUILDMASTERY"]("history")
end

-- The addon's own offline self-test command.
function Scenarios.testrestore()
    print("== /gm testrestore ==")
    resetDB()
    Sim.enterRaid("Mythic")
    Sim.login()
    SlashCmdList["GUILDMASTERY"]("testrestore")
    ok(true, "/gm testrestore ran without error")
end

-- THE reload bug: save+reload during an open session must restore the SAME
-- votes/voters. Exercises real BuildSessions -> DoSaveAndReload -> SaveSessions
-- -> pendingRestore -> CheckPendingRestore -> InjectItemsIntoVF -> RC Setup.
function Scenarios.reload()
    print("== reload keeps votes ==")
    resetDB()
    Sim.enterRaid("Mythic")
    Sim.login()

    Sim.startSession({
        { loot = Sim.loot[1], boss = "Vexie and the Geargrinders" },
        { loot = Sim.loot[2], boss = "Cauldron of Carnage" },
    })
    Sim.populateContestedItem(1)
    -- second item: a couple of responses + one vote
    Sim.setResponse(2, "Draknar-Hyjal", 1, 646.0, 1.0)
    Sim.setResponse(2, "Ged-Uldaman",  2, 641.0, 4.0)
    Sim.castVote("Ged-Uldaman", 2, "Draknar-Hyjal")
    Sim.advance(3)  -- let response/vote hooks settle

    local before1, before2 = Sim.voteFP(1), Sim.voteFP(2)
    print("  pre-reload s1 Ashkandi = " .. (before1["Ashkandi-Uldaman"] or "nil"))

    ok(Sim.clickBadgeReload(), "badge right-click triggered SaveAndReload")
    ok(Sim.reloadRequested, "ReloadUI was requested")
    ok(RCLootCouncil_GuildMasteryDB.pendingRestore ~= nil, "pendingRestore flag set")
    ok(type(RCLootCouncil_GuildMasteryDB.pendingRestore.ids) == "table"
        and #RCLootCouncil_GuildMasteryDB.pendingRestore.ids > 0, "pendingRestore carries entry ids (restore-by-id)")

    Sim.relog()

    local after1, after2 = Sim.voteFP(1), Sim.voteFP(2)
    print("  post-reload s1 Ashkandi = " .. (after1["Ashkandi-Uldaman"] or "nil"))
    local eq1 = fpEqual(before1, after1)
    local eq2 = fpEqual(before2, after2)
    ok(eq1, "session 1 votes/voters preserved across reload")
    ok(eq2, "session 2 votes/voters preserved across reload")
end

-- Weakness A: council votes arriving AFTER responses must refresh the saved
-- snapshot (common case: votes within the 5-min dedup window -> single entry,
-- fresh votes). Note: gaps > 5 min are a known pre-existing dedup limitation.
function Scenarios.dedup()
    print("== votes refresh the saved snapshot ==")
    resetDB()
    Sim.enterRaid("Heroic")
    Sim.login()

    Sim.startSession({ { loot = Sim.loot[3], boss = "Rik Reverb" } })
    -- 1) responses only -> response hook auto-saves a votes=0 snapshot
    Sim.setResponse(1, "Ashkandi-Uldaman", 1, 640, 5)
    Sim.setResponse(1, "Ged-Uldaman",      1, 641, 4)
    Sim.setResponse(1, "Moro-Uldaman",     2, 638, 6)
    Sim.setResponse(1, "Sylae-Hyjal",      1, 637, 8)
    Sim.setResponse(1, "Draknar-Hyjal",    1, 639, 6)
    Sim.advance(2)  -- CheckAllResponsesReceived fires
    ok(countHistory(232802) == 1, "one history entry after responses")

    -- 2) council votes 30s later (within dedup window) -> vote hook refreshes
    Sim.advance(30)
    Sim.castVote("Ged-Uldaman",      1, "Ashkandi-Uldaman")
    Sim.castVote("Ashkandi-Uldaman", 1, "Ashkandi-Uldaman")
    Sim.castVote("Moro-Uldaman",     1, "Ashkandi-Uldaman")
    Sim.advance(3)  -- HandleVote hook -> RefreshCurrentSessionVotes

    ok(countHistory(232802) == 1, "still a single entry (dedup updated, no duplicate)")
    -- read the saved votes for the winner
    local saved
    for _, e in ipairs(RCLootCouncil_GuildMasteryDB.history) do
        if e.item_id == 232802 then
            for _, c in ipairs(e.candidates or {}) do
                if c.name == "Ashkandi-Uldaman" then saved = c.votes end
            end
        end
    end
    ok(saved == 3, "saved snapshot has current votes (3), not stale 0 (got " .. tostring(saved) .. ")")
end

Sim.Scenarios = Scenarios   -- exposed for the web UI

function Sim.run(_, cmd)
    cmd = cmd or "all"
    local order = { "smoke", "testrestore", "reload", "dedup" }
    local toRun = (cmd == "all") and order or { cmd }
    for _, name in ipairs(toRun) do
        local fn = Scenarios[name]
        if not fn then
            print("Unknown scenario: " .. tostring(name))
            return 1
        end
        local ok_, err = pcall(fn)
        if not ok_ then
            Sim.fail = Sim.fail + 1
            print("  [ERROR] scenario '" .. name .. "': " .. tostring(err))
        end
        print("")
    end
    print(string.format("==== RESULT: %d passed, %d failed ====", Sim.pass, Sim.fail))
    return (Sim.fail == 0) and 0 or 1
end
