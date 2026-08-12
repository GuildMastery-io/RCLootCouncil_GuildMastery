-- ============================================================
-- boot.lua — initialise the real RC + GuildMastery by firing WoW events, then
-- report what came up. Loaded last by load_real.js.
-- ============================================================

if Sim.enterRaid then Sim.enterRaid("Mythic") end

-- AceAddon runs OnInitialize on ADDON_LOADED and OnEnable on PLAYER_LOGIN;
-- RC + GM register their own frames for these.
Sim.fireEvent("ADDON_LOADED", "RCLootCouncil")
Sim.fireEvent("ADDON_LOADED", "RCLootCouncil_GuildMastery")
Sim.advance(1)
Sim.fireEvent("PLAYER_ENTERING_WORLD", true, false)
Sim.fireEvent("PLAYER_LOGIN")
Sim.advance(6)   -- run GM's TryHookRC(3) / CheckPendingRestore(4) timers

print("")
print("=========== REAL-RC BOOT REPORT ===========")

local rc = _G.RCLootCouncil or (LibStub and select(2, pcall(function()
    return LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
end)))
print("RCLootCouncil addon object : " .. tostring(rc ~= nil))
if rc then
    print("  version field            : " .. tostring(rc.version))
    local okVF, vf = pcall(function() return rc:GetModule("RCVotingFrame") end)
    local okML, ml = pcall(function() return rc:GetActiveModule("masterlooter") end)
    print("  RCVotingFrame module     : " .. tostring(okVF and vf ~= nil))
    print("  masterlooter module      : " .. tostring(okML and ml ~= nil))
    if okVF and vf then
        print("    vf:ReceiveLootTable     : " .. type(vf.ReceiveLootTable))
        print("    vf:GetLootTable         : " .. type(vf.GetLootTable))
        print("    vf:HandleVote           : " .. type(vf.HandleVote))
    end
end

print("GMLootHistory present      : " .. tostring(type(GMLootHistory) == "table"))
print("/gm slash handler          : " .. tostring(type(SlashCmdList and SlashCmdList["GUILDMASTERY"]) == "function"))

-- Did GM hook the REAL VotingFrame (badge injected + methods hooked)?
if rc then
    local okVF, vf = pcall(function() return rc:GetModule("RCVotingFrame") end)
    if okVF and vf then
        local okF, frame = pcall(function() return vf:GetFrame() end)
        local badge = okF and frame and frame.gmSaveBtn
        print("GM badge on real VotingFrame: " .. tostring(badge ~= nil))
    end
end

-- ---- reload scenario: exercise GM's restore against the REAL VotingFrame ----
if SIM_CMD == "reload" and rc then
    print("")
    print("----- REAL-RC RELOAD TEST -----")
    local vf = rc:GetModule("RCVotingFrame")
    local ml = rc:GetActiveModule("masterlooter")
    rc.isMasterLooter = true
    -- Real RC only enables the ML module on becoming master looter; simulate an
    -- active ML so lootTable exists (as it would mid-session in game).
    if ml then ml.running = false; ml.isHistoricalLoad = false; ml.lootTable = ml.lootTable or {} end

    -- Seed GM history with a voted session, then use GM's OWN restore path
    -- (InjectItemsIntoVF) to push it into the REAL VotingFrame.
    RCLootCouncil_GuildMasteryDB = { history = {}, version = 1 }
    local link = Sim.registerItem(232800, "Geargrinder's Spare Keys", 639)
    local items = { {
        id = "t_1_232800", date = "01/01/2026", session_num = 1,
        item = "Geargrinder's Spare Keys", item_link_raw = link, item_id = 232800, item_ilvl = 639,
        awarded_to = "", boss = "Vexie",
        candidates = {
            { name = "Ashkandi-Uldaman", class = "WARRIOR", role = "MELEE", rank = "Officer",
              response = "1", response_code = "1", votes = 3, voters = { "Ged-Uldaman", "Ashkandi-Uldaman", "Moro-Uldaman" } },
            { name = "Ged-Uldaman", class = "PALADIN", role = "MELEE", rank = "Guild Master",
              response = "2", response_code = "2", votes = 0, voters = {} },
        },
    } }

    local okInj, injErr = pcall(function()
        GMLootHistory:InjectItemsIntoVF(items, { silent = false,
            onError = function(m) print("  [inject onError] " .. tostring(m)) end })
    end)
    Sim.advance(2)
    print("InjectItemsIntoVF into real VF: " .. tostring(okInj) .. (injErr and (" err=" .. tostring(injErr)) or ""))

    -- Read the votes back out of the REAL VotingFrame's live loot table.
    local lt = vf:GetLootTable()
    local s1 = lt and lt[1]
    local ash = s1 and s1.candidates and s1.candidates["Ashkandi-Uldaman"]
    if ash then
        local fp = tostring(ash.votes) .. "|" .. table.concat(ash.voters or {}, ",")
        print("real VF Ashkandi votes      : " .. fp)
        print("RESULT: " .. (fp == "3|Ged-Uldaman,Ashkandi-Uldaman,Moro-Uldaman"
            and "PASS - GM drove the real VotingFrame and votes survived"
            or  "FAIL - votes not preserved (" .. fp .. ")"))
    else
        print("RESULT: FAIL - candidate not found in real VotingFrame lootTable")
    end
    print("-------------------------------")
end

-- Top missing globals (what a fuller mock would still need).
local miss = {}
for k, n in pairs(Sim.missingGlobals or {}) do miss[#miss + 1] = { k = k, n = n } end
table.sort(miss, function(a, b) return a.n > b.n end)
print("Distinct unmocked globals  : " .. #miss)
for i = 1, math.min(15, #miss) do
    print(string.format("    %-32s x%d", miss[i].k, miss[i].n))
end
print("===========================================")
