-- ============================================================
-- rc_mock.lua — faithful-enough mock of RCLootCouncil (mirrors 3.23.0).
--
-- The behaviours reproduced here are the ones RCLootCouncil_GuildMastery
-- actually relies on. They are copied from the real 3.23.0 source so the
-- addon's interaction is validly exercised:
--   * RCVotingFrame:Setup / SetupSession  -> the `added` gate that decides
--     whether candidate data (votes/voters/response) is KEPT or RESET.
--   * RCVotingFrame:SetCandidateData      -> direct field write.
--   * RCVotingFrame:HandleVote            -> up-vote mutation WITHOUT touching
--     `response` (this is why GM's response-only auto-save missed votes).
--   * RCLootCouncilML: running / lootTable / isHistoricalLoad / GetItemInfo / Award.
--
-- If a NEW RCLootCouncil changes these, update this file (and see contract.js
-- for the static check that flags renamed/removed RC symbols).
-- ============================================================

local function copyTable(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copyTable(v) end
    return o
end

Sim.group = Sim.group or {}   -- array of member names (set via Sim.setGroup)
function Sim.setGroup(names) Sim.group = names end

-- ---------------- VotingFrame ----------------
local VF = { __lt = {} }

function VF:GetLootTable() return self.__lt end

function VF:SetupCandidate(t, name, response)
    local p = (Sim.players and Sim.players[name]) or {}
    t.candidates[name] = {
        class = p.class or "Unknown", rank = p.rank or "Unknown", role = p.role or "NONE",
        response = response, ilvl = "", diff = "", gear1 = nil, gear2 = nil,
        votes = 0, note = nil, roll = nil, voters = {}, haveVoted = false,
    }
end

function VF:SetupSession(session, t)
    t.added = true
    t.haveVoted = false
    t.candidates = {}
    t.hasRolls = false
    for _, name in ipairs(Sim.group) do
        self:SetupCandidate(t, name, "ANNOUNCED")
    end
end

-- Faithful copy of RC 3.23.0 Setup: candidate data is reset ONLY when the
-- session entry is not already `added`. GM sets added=true on injected entries
-- precisely to keep the votes it re-injects.
function VF:Setup(tbl)
    for session, t in ipairs(tbl) do
        if not t.added then
            self:SetupSession(session, t)
        end
    end
end

function VF:ReceiveLootTable(lt)
    self.__lt = copyTable(lt)
    self:Setup(self.__lt)
    return self.__lt
end

function VF:SetCandidateData(session, candidate, data, val)
    local ok = pcall(function() self.__lt[session].candidates[candidate][data] = val end)
    return ok
end

function VF:GetCandidateData(session, candidate, data)
    local ok, v = pcall(function() return self.__lt[session].candidates[candidate][data] end)
    return ok and v or nil
end

-- Up-vote: mutates votes/voters, NEVER response. Mirrors RC 3.23.0.
function VF:HandleVote(voter, session, name, vote)
    local s = self.__lt[session]
    if not (s and s.candidates[name]) then return end
    local c = s.candidates[name]
    c.votes = (c.votes or 0) + (vote or 1)
    if (vote or 1) > 0 then
        table.insert(c.voters, voter)
    else
        for i = #c.voters, 1, -1 do if c.voters[i] == voter then table.remove(c.voters, i) end end
    end
end

VF.OnEnable = function() end
function VF:Update() end
function VF:Show() end
function VF:Hide() end
function VF:EndSession() end
local vfFrame = Sim.newObject("rcvotingframe")
vfFrame.content = Sim.newObject("frame")
function VF:GetFrame() return vfFrame end
VF.frame = vfFrame

-- ---------------- Master Looter ----------------
local ML = {
    running = false,
    lootTable = {},
    isHistoricalLoad = false,
}
function ML:GetItemInfo(link)
    local it = Sim.items and Sim.items[link]
    return {
        string = it and it.name or "Item", link = link, ilvl = it and it.ilvl or 639,
        texture = it and it.texture or 134400, token = false, classes = nil,
        equipLoc = "INVTYPE_HEAD", type = "Armor", subType = "Cloth",
        typeID = 4, subTypeID = 1,
    }
end
function ML:Award(session, winner)
    local s = self.lootTable[session]
    if s then s.awarded = winner or true end
    -- Mirror RC: the VotingFrame's lootTable session is ALSO marked awarded on a
    -- successful award. This is the field BuildSessionsFromLootTable reads to
    -- capture awarded_to, so the mock must set it for the award to be persisted.
    local vs = VF.__lt and VF.__lt[session]
    if vs then vs.awarded = winner or true end
    return true
end
function ML:UnTrackAndLogLoot() return true end

-- ---------------- Addon object ----------------
local modulesByName = { RCVotingFrame = VF, RCLootCouncilML = ML }
local modulesByType = { votingframe = VF, masterlooter = ML }

-- Permissive fallback: unknown RC methods become no-ops (logged once) so the
-- addon never hard-crashes on an RC helper we didn't model. The methods the
-- addon's LOGIC depends on are all defined concretely above/below.
local warned = {}
local RC = setmetatable({}, {
    __index = function(_, k)
        if not warned[k] then
            warned[k] = true
            -- Uncomment for discovery: print("[rc_mock] unmodeled RC:" .. tostring(k))
        end
        return function() end
    end,
})

RC.version = "3.23.0"
RC.isMasterLooter = true
RC.lootDB = { factionrealm = {} }

function RC:GetModule(name, silent)
    local m = modulesByName[name]
    if not m and not silent then error("RC mock: no module '" .. tostring(name) .. "'") end
    return m
end
function RC:GetActiveModule(mtype) return modulesByType[mtype] end
function RC:GetTypeCodeForItem() return "default" end
function RC:GetHistoryDB() return self.lootDB.factionrealm end
function RC:GetClassColor() return { r = 0.8, g = 0.8, b = 0.8, colorStr = "ffcccccc" } end
function RC:CreateTooltip() end
function RC:HideTooltip() end
function RC:Print(...) print("[RC]", ...) end
function RC:GroupIterator()
    local i = 0
    return function()
        i = i + 1
        return Sim.group[i]
    end
end
-- RCFrame:NewNamed returns a frame that already has a `.content` child (as the
-- real RC widget does), so addon code that draws into f.content works.
RC.UI = setmetatable({
    NewNamed = function(_, _, _, name)
        local frame = Sim.newObject("rcframe")
        frame.__name = name
        frame.content = Sim.newObject("frame")
        frame.title = Sim.newObject("fontstring")
        return frame
    end,
}, { __index = function() return function() return Sim.newObject() end end })
RC.Log = setmetatable({}, { __index = function() return function() end end })

Sim.rc, Sim.vf, Sim.ml = RC, VF, ML

-- ---------------- LibStub ----------------
local aceAddon = {
    GetAddon = function(_, name) if name == "RCLootCouncil" then return RC end return nil end,
    NewAddon = function() return setmetatable({}, { __index = function() return function() end end }) end,
    IterateAddons = function() return function() end end,
}
function LibStub(name)
    if name == "AceAddon-3.0" then return aceAddon end
    return setmetatable({}, { __index = function() return function() return {} end end })
end
