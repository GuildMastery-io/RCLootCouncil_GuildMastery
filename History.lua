-- RCLootCouncil_GuildMastery/History.lua
-- 3-column history UI: Dates -> Items -> Vote details
-- /gm history

local PREFIX = "|cFF9B7EDE[GuildMastery]|r"
GMLootHistory = {}

-- Local debug helper backed by the shared gating flag from core.lua.
-- Output only when RCLootCouncil_GuildMasteryDB.debug == true (toggle with /gm debug).
local function DebugPrint(msg)
    local db = RCLootCouncil_GuildMasteryDB
    if db and db.debug then
        print(PREFIX .. " |cFF8888FF[Debug]|r " .. tostring(msg))
    end
end

-- ============================================================
-- Helper: access RC's ML module
-- ============================================================

local function GetRCML()
    local ok, rc = pcall(function() return LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil") end)
    if not ok or not rc then return nil end
    if not rc.isMasterLooter then return nil end
    local ok2, ml = pcall(function() return rc:GetActiveModule("masterlooter") end)
    if not ok2 or not ml then return nil end
    return ml
end

local function GetRCVF()
    local ok, rc = pcall(function() return LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil") end)
    if not ok or not rc then return nil end
    local ok2, vf = pcall(function() return rc:GetModule("RCVotingFrame") end)
    if not ok2 or not vf then return nil end
    return vf
end

-- Find the most recent RC history entry awarded to `playerName` for
-- `itemLinkRaw`. Returns (id, indexInLootDB, lootDBKey) to allow deletion.
-- Tolerates "Name" and "Name-Realm" variants.
local function FindLatestRCHistoryEntry(playerName, itemLinkRaw)
    if not playerName or playerName == "" or not itemLinkRaw or itemLinkRaw == "" then
        return nil
    end
    local ok, rc = pcall(function() return LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil") end)
    if not ok or not rc or type(rc.GetHistoryDB) ~= "function" then return nil end

    local ok2, lootDB = pcall(function() return rc:GetHistoryDB() end)
    if not ok2 or type(lootDB) ~= "table" then return nil end

    -- Try the full name first, then without the -Realm suffix.
    local key = playerName
    local entries = lootDB[key]
    if not entries then
        local short = playerName:match("^([^-]+)")
        if short and short ~= playerName then
            key = short
            entries = lootDB[short]
        end
    end
    if type(entries) ~= "table" or #entries == 0 then return nil end

    -- Walk backwards (most recent comes last).
    for i = #entries, 1, -1 do
        local e = entries[i]
        if e and e.lootWon == itemLinkRaw and e.id then
            return e.id, i, key
        end
    end
    return nil
end

-- Remove an entry from the RC history. If we are ML, use UnTrackAndLogLoot
-- which broadcasts to the other council members. Otherwise fall back to a
-- local tremove. Returns true if anything was removed.
local function RemoveFromRCHistory(playerName, itemLinkRaw)
    local id, idx, key = FindLatestRCHistoryEntry(playerName, itemLinkRaw)
    if not id then return false, "no_entry" end

    -- Path 1: ML broadcasts via UnTrackAndLogLoot
    local ml = GetRCML()
    if ml and type(ml.UnTrackAndLogLoot) == "function" then
        local okML = pcall(function() ml:UnTrackAndLogLoot(id) end)
        if okML then return true, "broadcast" end
    end

    -- Path 2: local removal (non-ML or broadcast failed)
    local ok, rc = pcall(function() return LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil") end)
    if not ok or not rc then return false, "no_rc" end
    local ok2, lootDB = pcall(function() return rc:GetHistoryDB() end)
    if not ok2 or not lootDB or not lootDB[key] then return false, "no_db" end

    local okLocal = pcall(function()
        tremove(lootDB[key], idx)
        if #lootDB[key] == 0 then lootDB[key] = nil end
    end)
    if okLocal then return true, "local" end
    return false, "err"
end

-- Maximum age (in days) above which the RC reload button refuses to restore
-- a historical session into the VotingFrame. Avoids polluting the loot flow
-- with data weeks or months old.
local MAX_RELOAD_AGE_DAYS = 2

-- True if the most recent item in the batch is older than MAX_RELOAD_AGE_DAYS.
local function IsBatchTooOld(items)
    if not items or #items == 0 then return false end
    local maxAgeSec = MAX_RELOAD_AGE_DAYS * 86400
    local now = time()
    local latest = 0
    for _, e in ipairs(items) do
        if (e.timestamp or 0) > latest then latest = e.timestamp end
    end
    return (now - latest) > maxAgeSec
end

-- ============================================================
-- DB
-- ============================================================

local function GetDB()
    if not RCLootCouncil_GuildMasteryDB then RCLootCouncil_GuildMasteryDB = {} end
    local db = RCLootCouncil_GuildMasteryDB
    if not db.history then db.history = {} end
    if not db.version  then db.version  = 1 end
    return db
end

-- ============================================================
-- Save
-- ============================================================

local _saveCounter = 0

local function UpdateRecentDuplicate(s, matched)
    local hist = GetDB().history
    local now  = time()
    -- Look in the last 30 entries.
    for i = #hist, math.max(1, #hist - 30), -1 do
        if not matched[i] then
            local e = hist[i]
            if (now - (e.timestamp or 0)) < 300
               and e.session_num == (s.session   or 0)
               and e.item_id     == (s.item_id   or 0) then
                -- Recent entry found: update it.
                e.awarded_to = s.awarded_to or ""
                e.candidates = s.candidates or {}
                e.timestamp  = now
                matched[i] = true   -- prevents another item from this batch matching the same entry
                return true
            end
        end
    end
    return false
end

function GMLootHistory:SaveSessions(sessions, dedup)
    if not sessions or #sessions == 0 then return 0 end
    local count = 0
    local matched = {}   -- indices already updated in this batch
    for _, s in ipairs(sessions) do
        if dedup and UpdateRecentDuplicate(s, matched) then
            -- Entry was updated (merge).
            count = count + 1
        else
            -- New entry.
            _saveCounter = _saveCounter + 1
            local ts = time()
            local t  = date("*t")
            -- Stable, deterministic id (SHARED formula with the server and the
            -- companion: `${looted_at}_${session}_${item_id}`). `created_at` is
            -- frozen at creation; `timestamp` acts as updated_at (mutated).
            table.insert(GetDB().history, {
                id            = ts .. "_" .. (s.session or 0) .. "_" .. (s.item_id or 0),
                created_at    = ts,
                timestamp     = ts,
                date          = string.format("%02d/%02d/%04d", t.day, t.month, t.year),
                time_str      = string.format("%02d:%02d:%02d", t.hour, t.min, t.sec),
                instance      = GetRealZoneText() or "?",
                session_num   = s.session     or 0,
                item          = s.item        or "",
                item_link_raw = s.item_link_raw or "",
                item_id       = s.item_id     or 0,
                item_ilvl     = s.item_ilvl   or 0,
                awarded_to    = s.awarded_to  or "",
                boss          = s.boss        or "",
                candidates    = s.candidates  or {},
            })
            count = count + 1
        end
    end

    if count > 0 and RCLootCouncil_GuildMastery_UpdateSyncPayload then
        RCLootCouncil_GuildMastery_UpdateSyncPayload()
    end

    return count
end

-- Styled button factory. Replaces UIPanelButtonTemplate (whose default red
-- border looks dated). Used by the export popup (core.lua) and the history
-- window bottom buttons. Exposed globally so core.lua can call it without
-- duplicating the code.
--   parent : the parent frame
--   w, h   : button size
--   text   : label
--   opts   : optional table with `danger = true` (red accent for destructive actions)
function RCLootCouncil_GuildMastery_MakeButton(parent, w, h, text, opts)
    opts = opts or {}
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(w, h)

    -- Backdrop fill
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    if opts.danger then
        bg:SetColorTexture(0.25, 0.08, 0.08, 0.95)
    else
        bg:SetColorTexture(0.10, 0.10, 0.14, 0.95)
    end

    -- Thin 1px border via four edge textures (Backdrop API is restricted now)
    local borderR, borderG, borderB =
        (opts.danger and 0.55 or 0.35),
        (opts.danger and 0.25 or 0.35),
        (opts.danger and 0.25 or 0.42)
    local function makeEdge(point1, point2)
        local t = btn:CreateTexture(nil, "BORDER")
        t:SetColorTexture(borderR, borderG, borderB, 0.9)
        return t
    end
    local top = makeEdge()
    top:SetHeight(1); top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    local bot = makeEdge()
    bot:SetHeight(1); bot:SetPoint("BOTTOMLEFT"); bot:SetPoint("BOTTOMRIGHT")
    local lef = makeEdge()
    lef:SetWidth(1); lef:SetPoint("TOPLEFT"); lef:SetPoint("BOTTOMLEFT")
    local rig = makeEdge()
    rig:SetWidth(1); rig:SetPoint("TOPRIGHT"); rig:SetPoint("BOTTOMRIGHT")

    -- Hover highlight (subtle white overlay)
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    -- Label
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("CENTER", 0, 0)
    if opts.danger then
        fs:SetTextColor(0.95, 0.55, 0.55)
    else
        fs:SetTextColor(0.92, 0.92, 0.95)
    end
    fs:SetText(text)
    btn:SetFontString(fs)

    -- Pressed offset (label nudges down 1px for tactile feedback)
    btn:SetScript("OnMouseDown", function() fs:SetPoint("CENTER", 0, -1) end)
    btn:SetScript("OnMouseUp",   function() fs:SetPoint("CENTER", 0, 0) end)

    return btn
end

function GMLootHistory:GetCount() return #GetDB().history end

-- ============================================================
-- Retention : drop entries older than RETENTION_DAYS days.
-- Mirrors the server-side retention policy enforced by the GuildMastery
-- web app (cf. src/lib/loot-sessions/cleanup.ts in the nocturnys repo).
-- Keep these two constants synchronized.
-- ============================================================
local RETENTION_DAYS = 180
local RETENTION_SECONDS = RETENTION_DAYS * 24 * 60 * 60

function GMLootHistory:PruneOldEntries()
    local hist = GetDB().history
    if not hist or #hist == 0 then return 0 end

    local cutoff = time() - RETENTION_SECONDS
    local kept = {}
    local dropped = 0
    for _, e in ipairs(hist) do
        if (e.timestamp or 0) >= cutoff then
            table.insert(kept, e)
        else
            dropped = dropped + 1
        end
    end

    if dropped > 0 then
        GetDB().history = kept
        DebugPrint(string.format("PruneOldEntries: dropped %d entry(ies) older than %d days", dropped, RETENTION_DAYS))
    end
    return dropped
end

function GMLootHistory:GetLastSavedSessions()
    local hist = GetDB().history
    if not hist or #hist == 0 then return nil end

    -- Find the most recent timestamp.
    local latestTimestamp = 0
    for _, e in ipairs(hist) do
        if (e.timestamp or 0) > latestTimestamp then
            latestTimestamp = e.timestamp
        end
    end

    if latestTimestamp == 0 then return nil end

    -- Collect every session with that timestamp.
    local sessions = {}
    for _, e in ipairs(hist) do
        if e.timestamp == latestTimestamp then
            table.insert(sessions, {
                session       = e.session_num,
                item          = e.item,
                item_link_raw = e.item_link_raw,
                item_id       = e.item_id,
                item_ilvl     = e.item_ilvl,
                awarded_to    = e.awarded_to,
                boss          = e.boss,
                candidates    = e.candidates,
                looted_at     = e.timestamp or 0,
            })
        end
    end

    return sessions
end

function GMLootHistory:GetAllSessions()
    -- Always prune before serializing : this is the unique entry point that
    -- feeds the `is_full_sync` payload sent to the backend. Without pruning
    -- here, old sessions would be re-sent indefinitely and re-inserted by
    -- the server (which would purge them again on the next lazy-cleanup pass).
    GMLootHistory:PruneOldEntries()

    local hist = GetDB().history
    if not hist or #hist == 0 then return {} end

    local sessions = {}
    for _, e in ipairs(hist) do
        -- Soft in-place migration of legacy entries (< v2):
        --  - `created_at` = frozen looted_at (never mutated). Best-effort for
        --    existing entries: freeze it to the current timestamp.
        --  - `id` = SHARED formula `${created_at}_${session}_${item_id}`
        --    (same on the server and companion), recomputed idempotently.
        local createdAt = e.created_at or e.timestamp or 0
        e.created_at = createdAt
        e.id = createdAt .. "_" .. (e.session_num or 0) .. "_" .. (e.item_id or 0)
        table.insert(sessions, {
            id            = e.id,
            session       = e.session_num,
            item          = e.item,
            item_link_raw = e.item_link_raw,
            item_id       = e.item_id,
            item_ilvl     = e.item_ilvl,
            awarded_to    = e.awarded_to,
            boss          = e.boss,
            candidates    = e.candidates,
            looted_at     = createdAt,          -- frozen (creation)
            updated_at    = e.timestamp or createdAt,  -- mutated (award/unaward)
            date          = e.date,
        })
    end

    return sessions
end

-- Returns the largest `timestamp` present in the history. Used after
-- SaveSessions to identify the batch just added (auto-restore post-reload).
function GMLootHistory:GetLatestTimestamp()
    local hist = GetDB().history
    local latest = 0
    for _, e in ipairs(hist) do
        if (e.timestamp or 0) > latest then latest = e.timestamp end
    end
    return latest
end

-- ============================================================
-- Restore items into the VotingFrame.
-- Used by the history reload button (_reloadBtn) and by the post-reload
-- auto-restore on PLAYER_LOGIN after the badge right-click triggers ReloadUI.
--
-- opts (optional):
--   silent     = bool, suppresses progress messages
--   onSuccess  = fn(n) called after successful injection
--   onError    = fn(msg) called on failure
-- ============================================================

function GMLootHistory:InjectItemsIntoVF(items, opts)
    opts = opts or {}
    local silent     = opts.silent
    local onSuccess  = opts.onSuccess
    local onError    = opts.onError

    local function _msg(text, color)
        if not silent then
            print(PREFIX .. " |" .. (color or "cFFFFFFFF") .. text .. "|r")
        end
    end
    local function _err(text, color)
        _msg(text, color or "cFFFF4444")
        if onError then onError(text) end
    end

    local ml = GetRCML()
    if not ml then
        _err("You must be Master Looter to use this function.")
        return
    end
    if ml.running then
        _err("An RC session is already active. End it first.", "cFFFFAA00")
        return
    end
    local vf = GetRCVF()
    if not vf then
        _err("Unable to access the RC VotingFrame.")
        return
    end
    if not items or #items == 0 then
        _err("No item to restore.", "cFFFFAA00")
        return
    end

    _msg("Loading items into cache... please wait.", "cFFFFD700")

    -- Injection function (called once all items are cached).
    local function DoInject(attempt)
        attempt = attempt or 1
        local allCached = true
        for _, entry in ipairs(items) do
            if not GetItemInfo(entry.item_link_raw) then
                allCached = false
                if entry.item_link_raw and entry.item_link_raw ~= "" then
                    local itemID = entry.item_link_raw:match("item:(%d+)")
                    if itemID and C_Item and C_Item.RequestLoadItemDataByID then
                        C_Item.RequestLoadItemDataByID(tonumber(itemID))
                    end
                end
            end
        end

        if not allCached then
            if attempt >= 15 then
                _msg("Warning: some items could not be loaded after 7s (" .. tostring(attempt) .. "). Forcing injection...", "cFFFFAA00")
            else
                C_Timer.After(0.5, function() DoInject(attempt + 1) end)
                return
            end
        end

        DebugPrint("Starting injection (attempt " .. tostring(attempt) .. ")")

        local okData, errData = pcall(function()
            -- Build the lootTable in the format expected by RCVotingFrame.
            local fakeLT = {}
            for idx, entry in ipairs(items) do
                local tex = "Interface\\Icons\\INV_Misc_QuestionMark"
                if entry.item_link_raw then
                    local _, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(entry.item_link_raw)
                    if itemTexture then tex = itemTexture end
                end

                local sessionEntry = {
                    link      = entry.item_link_raw,
                    texture   = tex,
                    ilvl      = entry.item_ilvl or 0,
                    -- Preserve the itemID in the injected lootTable. Without it,
                    -- BuildSessionsFromLootTable reads `sd.itemID or 0` on the
                    -- next save and would create a history entry with item_id=0,
                    -- breaking the 5-min dedup against the pre-reload entry.
                    itemID    = entry.item_id or 0,
                    awarded   = nil,
                    added     = true,
                    haveVoted = false,
                    hasRolls  = false,
                    candidates = {},
                }
                for _, c in ipairs(entry.candidates or {}) do
                    local rCode = tostring(c.response_code or "")
                    local rcResp
                    local n = tonumber(rCode)
                    if n then rcResp = n
                    elseif rCode ~= "" then rcResp = rCode
                    else rcResp = "PASS" end
                    local votersList = {}
                    if type(c.voters) == "table" then
                        for _, v in ipairs(c.voters) do table.insert(votersList, v) end
                    end
                    sessionEntry.candidates[c.name] = {
                        class    = c.class   or "WARRIOR",
                        rank     = c.rank    or "",
                        role     = c.role    or "NONE",
                        response = rcResp,
                        ilvl     = c.ilvl    or "",
                        diff     = c.ilvl_diff or "",
                        gear1    = nil,
                        gear2    = nil,
                        votes    = c.votes   or 0,
                        voters   = votersList,
                        note     = c.note    or nil,
                        roll     = (c.roll and c.roll > 0) and c.roll or nil,
                        haveVoted = (#votersList > 0),
                    }
                end
                fakeLT[idx] = sessionEntry

                -- Populate the MasterLooter lootTable so Award works.
                local mlEntry = {
                    attempts = 0,
                    awarded = false,
                    bagged = false,
                    boss = entry.boss or (RCLootCouncil and RCLootCouncil.bossName) or "Unknown",
                    isSent = true,
                    link = entry.item_link_raw,
                    lootSlot = nil,
                    owner = nil,
                    session = idx,
                    typeCode = RCLootCouncil and RCLootCouncil:GetTypeCodeForItem(entry.item_link_raw) or "default"
                }
                local itemInfo = ml:GetItemInfo(entry.item_link_raw)
                if itemInfo then
                    for k, v in pairs(itemInfo) do
                        mlEntry[k] = v
                    end
                end
                ml.lootTable[idx] = mlEntry
            end

            ml.running          = true
            ml.isHistoricalLoad = true  -- core.lua skips auto-save for this session

            local ok, err = pcall(function() vf:ReceiveLootTable(fakeLT) end)
            if not ok then
                _err("VotingFrame injection error: " .. tostring(err))
                ml.running          = false
                ml.isHistoricalLoad = false
                wipe(ml.lootTable)
                return
            end
            GMLootHistory:Hide()
            _msg(string.format("%d unawarded item(s) reloaded into RC.", #items), "cFF88FF88")
            if onSuccess then onSuccess(#items) end
        end)

        if not okData then
            _err("Internal error while preparing data: " .. tostring(errData))
            ml.running          = false
            ml.isHistoricalLoad = false
            wipe(ml.lootTable)
        end
    end

    DoInject(1)
end

-- ============================================================
-- Display helpers
-- ============================================================

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class:upper()]
    return c and string.format("|cFF%02X%02X%02X", c.r*255, c.g*255, c.b*255) or "|cFFCCCCCC"
end

local function ResponseColor(code)
    local n = tonumber(code)
    if     n == 1 then return "|cFF00FF7F"
    elseif n == 2 then return "|cFFFFAA00"
    elseif code == "PASS" or code == "AUTOPASS" then return "|cFF888888"
    else   return "|cFFCCCCCC" end
end

local function Fmt(n)
    if not n or n == 0 then return "?" end
    return (math.floor(n) == n) and tostring(math.floor(n)) or string.format("%.4g", n)
end

local function DateKey(d)
    local dd, mm, yy = d:match("(%d+)/(%d+)/(%d+)")
    return dd and (tonumber(yy)*10000 + tonumber(mm)*100 + tonumber(dd)) or 0
end

-- ============================================================
-- Deletion
-- ============================================================

local function DeleteDate(dateStr)
    local hist = GetDB().history
    local changed = false
    for i = #hist, 1, -1 do
        local e = hist[i]
        local key = e.date .. " " .. e.time_str
        if key == dateStr then table.remove(hist, i); changed = true end
    end
    if changed and RCLootCouncil_GuildMastery_UpdateSyncPayload then RCLootCouncil_GuildMastery_UpdateSyncPayload() end
end

local function DeleteItem(entryId)
    local hist = GetDB().history
    for i = #hist, 1, -1 do
        if hist[i].id == entryId then
            table.remove(hist, i)
            if RCLootCouncil_GuildMastery_UpdateSyncPayload then RCLootCouncil_GuildMastery_UpdateSyncPayload() end
            break
        end
    end
end

local function DeleteCandidate(entryId, candidateName)
    local hist = GetDB().history
    for _, e in ipairs(hist) do
        if e.id == entryId then
            for j = #e.candidates, 1, -1 do
                if e.candidates[j].name == candidateName then
                    table.remove(e.candidates, j)
                    if RCLootCouncil_GuildMastery_UpdateSyncPayload then RCLootCouncil_GuildMastery_UpdateSyncPayload() end
                    break
                end
            end
            break
        end
    end
end

-- ============================================================
-- Grouping by date
-- ============================================================

local function BuildDateGroups()
    local hist, map, keys = GetDB().history, {}, {}
    for _, e in ipairs(hist) do
        local key = e.date .. " " .. e.time_str
        if not map[key] then map[key] = {}; table.insert(keys, key) end
        table.insert(map[key], e)
    end
    table.sort(keys, function(a, b)
        local dk_a = DateKey(a:sub(1,10))
        local dk_b = DateKey(b:sub(1,10))
        if dk_a == dk_b then
            return (a:match("%d%d:%d%d:%d%d") or "") > (b:match("%d%d:%d%d:%d%d") or "")
        end
        return dk_a > dk_b
    end)
    local groups = {}
    for _, k in ipairs(keys) do
        table.sort(map[k], function(a, b) return a.time_str > b.time_str end)
        local timePart = k:match("(%d%d:%d%d):") or k:match("%d%d:%d%d") or ""
        local label = k:sub(1,10) .. "  -  |cFF999999" .. timePart .. "|r"
        table.insert(groups, { date = k, label = label, entries = map[k] })
    end
    return groups
end

-- ============================================================
-- Layout constants
-- ============================================================

local FRAME_W     = 960
local FRAME_H     = 530
local ROW_H       = 22
local SB_W        = 16
local DEL_W       = 20   -- width of x button
local EXP_W       = 20   -- width of export button
local RELOAD_W    = 20   -- width of RC reload button (refresh icon, consistent with the others)

local DATE_SF_L   = 8
local DATE_SF_W   = 300
local DATE_SC_W   = DATE_SF_W - SB_W*2 - 4

local SEP1_X      = DATE_SF_L + DATE_SF_W + 8

local ITEMS_SF_L  = SEP1_X + 1 + 6
local ITEMS_SF_W  = 262
local ITEMS_SC_W  = ITEMS_SF_W - SB_W*2 - 4

local SEP2_X      = ITEMS_SF_L + ITEMS_SF_W + 8

local DETAIL_SF_L = SEP2_X + 1 + 6

local HDR_Y       = -28
local FILTER_Y    = -50
local SEP_H_Y     = -74
local SF_TOP_Y    = -76
local SF_BOT_Y    = 36

-- Detail panel: positions inside the scroll content
local DET_W         = FRAME_W - DETAIL_SF_L - SB_W*2 - 12
local DET_ITEM_Y    = 0
local DET_META_Y    = -24
local DET_AWARD_Y   = -42
local DET_CHDR_Y    = -66
local DET_CANDS_Y   = -88    -- starting y for candidate rows
local DET_CAND_H    = 22

-- ============================================================
-- Window state
-- ============================================================

local _frame             = nil
local _dateSC            = nil
local _itemSC            = nil
local _detailSC          = nil
local _detFS_item        = nil
local _detFS_meta        = nil
local _detFS_award       = nil
local _detUnawardBtn     = nil
local _detFS_candHdr     = nil
local _countLabel        = nil
local _selectedDate      = nil
local _selectedEntry     = nil
local _dateGroups        = {}
local _dateFilterStr     = ""
local _itemFilterStr     = ""

local _dateBtnPool      = {}
local _itemBtnPool      = {}
local _candidateBtnPool = {}

local function GetPoolBtn(pool, idx, parent)
    if not pool[idx] then pool[idx] = CreateFrame("Button", nil, parent) end
    return pool[idx]
end

local function MakeDelBtn(parent)
    local db = CreateFrame("Button", nil, parent)
    db:SetSize(DEL_W, DEL_W)
    local tex = db:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")

    db:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
    db:SetPushedTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Down")

    db:SetScript("OnEnter", function(self) if self:GetParent():GetScript("OnEnter") then self:GetParent():GetScript("OnEnter")(self:GetParent()) end end)
    db:SetScript("OnLeave", function(self) if self:GetParent():GetScript("OnLeave") then self:GetParent():GetScript("OnLeave")(self:GetParent()) end end)
    return db
end

local function MakeExportBtn(parent)
    local eb = CreateFrame("Button", nil, parent)
    eb:SetSize(EXP_W, EXP_W)

    local tex = eb:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")

    eb:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")

    eb:SetScript("OnEnter", function(self)
        local p = self:GetParent()
        if p and p:GetScript("OnEnter") then p:GetScript("OnEnter")(p) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Export as JSON")
        GameTooltip:Show()
    end)
    eb:SetScript("OnLeave", function(self)
        local p = self:GetParent()
        if p and p:GetScript("OnLeave") then p:GetScript("OnLeave")(p) end
        GameTooltip:Hide()
    end)
    return eb
end

local function MakeReloadBtn(parent)
    -- Icon button (styled like MakeDelBtn / MakeExportBtn) instead of
    -- UIPanelButtonTemplate which used to render an ugly red border.
    local rb = CreateFrame("Button", nil, parent)
    rb:SetSize(RELOAD_W, RELOAD_W)

    local tex = rb:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\BUTTONS\\UI-RefreshButton")
    tex:SetVertexColor(0.6, 1.0, 0.6) -- green tint (keeps the "import RC" semantics of the old green text)

    rb:SetHighlightTexture("Interface\\BUTTONS\\UI-RefreshButton")
    local hl = rb:GetHighlightTexture()
    hl:SetVertexColor(1.0, 1.0, 1.0)
    hl:SetBlendMode("ADD")

    rb:SetPushedTexture("Interface\\BUTTONS\\UI-RefreshButton")
    local pushed = rb:GetPushedTexture()
    pushed:SetVertexColor(0.4, 0.8, 0.4)

    rb:SetScript("OnEnter", function(self)
        local p = self:GetParent()
        if p and p:GetScript("OnEnter") then p:GetScript("OnEnter")(p) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cFF88FF88Reload into RC Loot|r")
        GameTooltip:AddLine("Injects this date's unawarded items into the RC Session Frame.\n|cFFFFAA00Must be Master Looter, no active session.|r", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    rb:SetScript("OnLeave", function(self)
        local p = self:GetParent()
        if p and p:GetScript("OnLeave") then p:GetScript("OnLeave")(p) end
        GameTooltip:Hide()
    end)
    return rb
end

-- Forward declarations
local RefreshDateList
local RebuildAll
local UpdateDetail

-- ============================================================
-- Detail panel: update
-- ============================================================

UpdateDetail = function(entry)
    _selectedEntry = entry
    if not _detailSC or not _detFS_item then return end
    for _, b in ipairs(_candidateBtnPool) do b:Hide() end

    if not entry then
        _detFS_item:SetText("|cFF555555Select an item in the middle column.|r")
        _detFS_meta:SetText(""); _detFS_award:SetText(""); _detFS_candHdr:SetText("")
        if _detUnawardBtn then _detUnawardBtn:Hide() end
        _detailSC:SetHeight(-DET_CANDS_Y)
        return
    end

    -- Item
    _detFS_item:SetText((entry.item_link_raw ~= "") and entry.item_link_raw or entry.item)

    -- Meta
    local parts = {}
    if entry.item_ilvl and entry.item_ilvl > 0 then table.insert(parts, "ilvl "..Fmt(entry.item_ilvl)) end
    if entry.instance  and entry.instance  ~= "" then table.insert(parts, entry.instance) end
    table.insert(parts, entry.date .. " " .. entry.time_str)
    _detFS_meta:SetText("|cFF888888" .. table.concat(parts, "  \194\183  ") .. "|r")

    -- Award
    if entry.awarded_to ~= "" then
        _detFS_award:SetText("Awarded to: |cFFFFD700" .. entry.awarded_to .. "|r")
        if _detUnawardBtn then _detUnawardBtn:Show() end
    else
        _detFS_award:SetText("|cFF666666Not awarded|r")
        if _detUnawardBtn then _detUnawardBtn:Hide() end
    end

    -- Candidates header
    _detFS_candHdr:SetText("|cFFAAAACC Candidates|r |cFF777788(" .. #entry.candidates .. ")|r")

    -- Candidate rows
    for i, c in ipairs(entry.candidates) do
        local btn = GetPoolBtn(_candidateBtnPool, i, _detailSC)
        btn:SetHeight(DET_CAND_H)
        local yOff = DET_CANDS_Y - (i-1)*DET_CAND_H
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",  _detailSC, "TOPLEFT",  0, yOff)
        btn:SetPoint("TOPRIGHT", _detailSC, "TOPRIGHT", 0, yOff)
        btn:Show()

        if not btn._bg then
            btn._bg = btn:CreateTexture(nil, "BACKGROUND"); btn._bg:SetAllPoints()
        end
        local even = (i % 2 == 0)
        btn._bg:SetColorTexture(even and 0.09 or 0.05, even and 0.09 or 0.05, even and 0.14 or 0.09, 0.85)
        btn._even = even

        if not btn._hl then
            btn._hl = btn:CreateTexture(nil, "HIGHLIGHT"); btn._hl:SetAllPoints()
            btn._hl:SetColorTexture(0.4, 0.28, 0.70, 0.22)
        end

        -- Class color square
        if not btn._ccSq then
            btn._ccSq = btn:CreateTexture(nil, "ARTWORK")
            btn._ccSq:SetSize(10, 10)
            btn._ccSq:SetPoint("LEFT", btn, "LEFT", 4, 0)
        end
        local cc = c.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class:upper()]
        if cc then btn._ccSq:SetColorTexture(cc.r, cc.g, cc.b, 1)
        else        btn._ccSq:SetColorTexture(0.7, 0.7, 0.7, 1) end

        -- Note icon (if present)
        if not btn._noteIcon then
            btn._noteIcon = btn:CreateTexture(nil, "ARTWORK")
            btn._noteIcon:SetSize(14, 14)
            btn._noteIcon:SetTexture("Interface\\FriendsFrame\\UI-Toast-ChatBubbleIcon")
        end

        local hasNote = (c.note and c.note ~= "")
        if hasNote then
            btn._noteIcon:SetPoint("LEFT", btn._ccSq, "RIGHT", 4, 0)
            btn._noteIcon:Show()
        else
            btn._noteIcon:Hide()
        end

        -- x button: delete candidate
        if not btn._delBtn then
            btn._delBtn = MakeDelBtn(btn)
            btn._delBtn:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        end

        -- Text
        if not btn._fsText then
            btn._fsText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn._fsText:SetPoint("RIGHT", btn, "RIGHT", -(DEL_W + 4), 0)
            btn._fsText:SetJustifyH("LEFT"); btn._fsText:SetWordWrap(false)
        end
        -- Adjust left point based on whether the note icon is visible
        local textLeftOff = hasNote and (4 + 10 + 4 + 14 + 4) or (4 + 10 + 4)
        btn._fsText:SetPoint("LEFT", btn, "LEFT", textLeftOff, 0)

        local cc_str = ClassColor(c.class)
        local rc_str = ResponseColor(c.response_code)
        local stat = ""
        local candIlvl = tonumber(c.ilvl)
        if candIlvl and candIlvl > 0 then
            local candDiff = tonumber(c.ilvl_diff)
            local diffStr = (candDiff and candDiff ~= 0)
                and (" (" .. (candDiff > 0 and "+" or "") .. Fmt(candDiff) .. ")")
                or ""
            stat = "|cFF888888 ilvl"..Fmt(candIlvl)..diffStr.."|r"
        end
        if c.votes and c.votes > 0 then stat = stat.."|cFF888888  "..c.votes.."v|r" end
        if c.roll  and c.roll  > 0 then stat = stat.."|cFF666666 r"..c.roll.."|r" end
        btn._fsText:SetText(string.format("%s%s|r  %s%s|r%s", cc_str, c.name, rc_str, c.response, stat))

        btn._candidate = c
        btn._entryId   = entry.id

        -- Hover tooltip
        btn:SetScript("OnEnter", function(self)
            local cand = self._candidate
            if not cand then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(ClassColor(cand.class)..(cand.name or "?").."|r", 1, 1, 1)
            if cand.roll   and cand.roll   > 0  then GameTooltip:AddLine("Roll: "..cand.roll, 0.8, 0.8, 0.8) end
            if cand.voters and #cand.voters > 0  then GameTooltip:AddLine("Voters: "..table.concat(cand.voters, ", "), 0.7, 0.7, 0.8) end
            if cand.note   and cand.note   ~= "" then GameTooltip:AddLine("Note: "..cand.note, 1, 0.8, 0) end
            if cand.equipped then
                for _, g in ipairs(cand.equipped) do
                    if g.name and g.name ~= "" then
                        GameTooltip:AddLine("Equipped: "..g.name.." ("..Fmt(g.ilvl)..")", 0.6, 0.6, 0.6)
                    end
                end
            end
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Delete candidate
        btn._delBtn:SetScript("OnClick", function()
            local eid  = btn._entryId
            local name = btn._candidate and btn._candidate.name
            if not eid or not name then return end

            StaticPopupDialogs["GUILDMASTERY_DELETE_CANDID"] = {
                text = "Do you really want to delete the data of "..name.." for this vote?",
                button1 = "Confirm", button2 = "Cancel",
                OnAccept = function()
                    DeleteCandidate(eid, name)
                    _dateGroups = BuildDateGroups()
                    -- Re-find the updated entry
                    local upd = nil
                    for _, e in ipairs(GetDB().history) do if e.id == eid then upd = e; break end end
                    UpdateDetail(upd)
                    if _countLabel then
                        local n = #GetDB().history
                        _countLabel:SetText("|cFF888888"..n.." "..(n>1 and "sessions saved" or "session saved").."|r")
                    end
                end,
                timeout = 0, whileDead = true, hideOnEscape = true,
            }
            StaticPopup_Show("GUILDMASTERY_DELETE_CANDID")
        end)
    end

    _detailSC:SetHeight(math.max(-DET_CANDS_Y + #entry.candidates * DET_CAND_H, 1))
end

-- ============================================================
-- Items column (middle)
-- ============================================================

local function PopulateItems(dateStr)
    if not _itemSC then return end
    for _, b in ipairs(_itemBtnPool) do b:Hide() end
    if not dateStr then _itemSC:SetHeight(1); return end

    local entries = nil
    for _, g in ipairs(_dateGroups) do
        if g.date == dateStr then entries = g.entries; break end
    end
    if not entries then _itemSC:SetHeight(1); return end

    local filt = _itemFilterStr
    local rows  = {}
    for _, e in ipairs(entries) do
        if filt == "" or e.item:lower():find(filt, 1, true) then
            table.insert(rows, e)
        end
    end

    local TIME_W = 36
    local ICON_W = ROW_H - 2
    local ICON_X = TIME_W + 4
    local ITEM_X = ICON_X + ICON_W + 4

    for i, entry in ipairs(rows) do
        local btn = GetPoolBtn(_itemBtnPool, i, _itemSC)
        btn:SetHeight(ROW_H)
        btn:SetPoint("TOPLEFT",  _itemSC, "TOPLEFT",  0, -(i-1)*ROW_H)
        btn:SetPoint("TOPRIGHT", _itemSC, "TOPRIGHT", 0, -(i-1)*ROW_H)
        btn:Show()

        if not btn._bg then
            btn._bg = btn:CreateTexture(nil, "BACKGROUND"); btn._bg:SetAllPoints()
        end
        local even = (i % 2 == 0)
        btn._bg:SetColorTexture(even and 0.09 or 0.05, even and 0.09 or 0.05, even and 0.14 or 0.09, 0.85)
        btn._even = even

        if not btn._hl then
            btn._hl = btn:CreateTexture(nil, "HIGHLIGHT"); btn._hl:SetAllPoints()
            btn._hl:SetColorTexture(0.4, 0.28, 0.70, 0.22)
        end

        -- Time
        if not btn._fsTime then
            btn._fsTime = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn._fsTime:SetPoint("LEFT", btn, "LEFT", 2, 0)
            btn._fsTime:SetWidth(TIME_W); btn._fsTime:SetJustifyH("LEFT")
        end
        btn._fsTime:SetText("|cFF888888"..entry.time_str:sub(1,5).."|r")

        -- Icon
        if not btn._icon then
            btn._icon = btn:CreateTexture(nil, "ARTWORK")
            btn._icon:SetSize(ICON_W, ICON_W)
            btn._icon:SetPoint("LEFT", btn, "LEFT", ICON_X, 0)
        end
        local tex = entry.item_link_raw ~= "" and select(10, GetItemInfo(entry.item_link_raw))
        btn._icon:SetTexture(tex or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- x button (delete item)
        if not btn._delBtn then
            btn._delBtn = MakeDelBtn(btn)
            btn._delBtn:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
        end

        -- Export button
        if not btn._expBtn then
            btn._expBtn = MakeExportBtn(btn)
            btn._expBtn:SetPoint("RIGHT", btn._delBtn, "LEFT", -2, 0)
        end

        -- Awarded badge (just before the export button)
        if not btn._fsBadge then
            btn._fsBadge = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            btn._fsBadge:SetPoint("RIGHT", btn._expBtn, "LEFT", -4, 0)
            btn._fsBadge:SetWidth(14); btn._fsBadge:SetJustifyH("RIGHT")
        end
        local awarded = entry.awarded_to ~= ""
        btn._fsBadge:SetText(awarded and "|cFFFFD700\195\151|r" or "")

        -- Item name
        if not btn._fsItem then
            btn._fsItem = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btn._fsItem:SetPoint("LEFT", btn, "LEFT", ITEM_X, 0)
            btn._fsItem:SetJustifyH("LEFT"); btn._fsItem:SetWordWrap(false)
        end
        local rOff = awarded and -(DEL_W + EXP_W + 4 + 14 + 2) or -(DEL_W + EXP_W + 6)
        btn._fsItem:SetPoint("RIGHT", btn, "RIGHT", rOff, 0)
        btn._fsItem:SetText((entry.item_link_raw ~= "") and entry.item_link_raw or entry.item)

        btn._entry = entry
        btn._even  = even

        -- Item tooltip
        btn:SetScript("OnEnter", function(self)
            local e = self._entry
            if e and e.item_link_raw ~= "" then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(e.item_link_raw)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Item selection
        btn:SetScript("OnClick", function(self)
            for _, b in ipairs(_itemBtnPool) do
                if b:IsShown() and b._bg then
                    local ev = b._even
                    b._bg:SetColorTexture(ev and 0.09 or 0.05, ev and 0.09 or 0.05, ev and 0.14 or 0.09, 0.85)
                end
            end
            self._bg:SetColorTexture(0.28, 0.17, 0.52, 0.92)
            UpdateDetail(self._entry)
        end)

        -- Export item
        btn._expBtn:SetScript("OnClick", function()
            local e = btn._entry
            if not e then return end
            local sessionsToExport = {{
                session       = e.session_num,
                item          = e.item,
                item_link_raw = e.item_link_raw,
                item_id       = e.item_id,
                item_ilvl     = e.item_ilvl,
                awarded_to    = e.awarded_to,
                candidates    = e.candidates
            }}
            if RCLootCouncil_GuildMastery_ExportSessions then
                RCLootCouncil_GuildMastery_ExportSessions(sessionsToExport, true)
            end
        end)

        -- Delete item
        btn._delBtn:SetScript("OnClick", function()
            local eid = btn._entry and btn._entry.id
            if not eid then return end

            StaticPopupDialogs["GUILDMASTERY_DELETE_ITEM"] = {
                text = "Do you really want to delete this item from history?",
                button1 = "Confirm", button2 = "Cancel",
                OnAccept = function()
                    local wasSelected = _selectedEntry and _selectedEntry.id == eid
                    DeleteItem(eid)
                    _dateGroups = BuildDateGroups()
                    RefreshDateList()
                    PopulateItems(_selectedDate)
                    if wasSelected then UpdateDetail(nil) end
                    if _countLabel then
                        local n = #GetDB().history
                        _countLabel:SetText("|cFF888888"..n.." "..(n>1 and "sessions saved" or "session saved").."|r")
                    end
                end,
                timeout = 0, whileDead = true, hideOnEscape = true,
            }
            StaticPopup_Show("GUILDMASTERY_DELETE_ITEM")
        end)
    end

    _itemSC:SetHeight(math.max(#rows * ROW_H, 1))
end

-- ============================================================
-- Dates column (left)
-- ============================================================

RefreshDateList = function()
    if not _dateSC then return end
    for _, b in ipairs(_dateBtnPool) do b:Hide() end

    local filt = _dateFilterStr
    local idx  = 0
    for _, g in ipairs(_dateGroups) do
        if filt == "" or g.date:lower():find(filt, 1, true) then
            idx = idx + 1
            local btn = GetPoolBtn(_dateBtnPool, idx, _dateSC)
            btn:SetHeight(ROW_H + 4)
            btn:SetPoint("TOPLEFT",  _dateSC, "TOPLEFT",  0, -(idx-1)*(ROW_H+4))
            btn:SetPoint("TOPRIGHT", _dateSC, "TOPRIGHT", 0, -(idx-1)*(ROW_H+4))
            btn:Show()

            if not btn._bg then
                btn._bg = btn:CreateTexture(nil, "BACKGROUND"); btn._bg:SetAllPoints()
            end
            btn._bg:SetColorTexture(0.07, 0.07, 0.12, 0.9)

            if not btn._hl then
                btn._hl = btn:CreateTexture(nil, "HIGHLIGHT"); btn._hl:SetAllPoints()
                btn._hl:SetColorTexture(0.4, 0.28, 0.70, 0.22)
            end

            -- x button (delete date)
            if not btn._delBtn then
                btn._delBtn = MakeDelBtn(btn)
                btn._delBtn:SetPoint("RIGHT", btn, "RIGHT", -2, 0)
            end

            -- RC reload button (reload into session frame)
            if not btn._reloadBtn then
                btn._reloadBtn = MakeReloadBtn(btn)
                btn._reloadBtn:SetPoint("RIGHT", btn._delBtn, "LEFT", -2, 0)
            end

            -- Export button
            if not btn._expBtn then
                btn._expBtn = MakeExportBtn(btn)
                btn._expBtn:SetPoint("RIGHT", btn._reloadBtn, "LEFT", -2, 0)
            end

            -- Counter (just before the export button)
            if not btn._fsCount then
                btn._fsCount = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                btn._fsCount:SetPoint("RIGHT", btn._expBtn, "LEFT", -4, 0)
                btn._fsCount:SetWidth(18); btn._fsCount:SetJustifyH("RIGHT")
            end
            btn._fsCount:SetText("|cFF888888"..(#g.entries).."|r")

            -- Date
            if not btn._fsDate then
                btn._fsDate = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                btn._fsDate:SetPoint("LEFT",  btn, "LEFT",  6, 0)
                btn._fsDate:SetPoint("RIGHT", btn._fsCount, "LEFT", -2, 0)
                btn._fsDate:SetJustifyH("LEFT")
            end
            btn._fsDate:SetText(g.label or g.date)
            btn._fsDate:SetTextColor(1, 1, 1)

            if g.date == _selectedDate then
                btn._bg:SetColorTexture(0.20, 0.12, 0.38, 0.95)
                btn._fsDate:SetTextColor(0.8, 0.6, 1.0)
            end

            local dateStr = g.date
            local dateEntries = g.entries   -- captured for the callbacks
            btn:SetScript("OnClick", function(self)
                _selectedDate  = dateStr
                for _, b in ipairs(_dateBtnPool) do
                    if b:IsShown() and b._bg and b._fsDate then
                        b._bg:SetColorTexture(0.07, 0.07, 0.12, 0.9)
                        b._fsDate:SetTextColor(1, 1, 1)
                    end
                end
                self._bg:SetColorTexture(0.20, 0.12, 0.38, 0.95)
                self._fsDate:SetTextColor(0.8, 0.6, 1.0)
                PopulateItems(_selectedDate)
                UpdateDetail(nil)
            end)

            -- RC reload: rebuilds the VotingFrame with archived votes, no rebroadcast.
            btn._reloadBtn:SetScript("OnClick", function()
                local items = {}
                for _, entry in ipairs(dateEntries) do
                    if entry.item_link_raw and entry.item_link_raw ~= ""
                       and (not entry.awarded_to or entry.awarded_to == "") then
                        table.insert(items, entry)
                    end
                end
                -- Stale-session safeguard: block if the session is older than
                -- MAX_RELOAD_AGE_DAYS. Prevents accidental restoration of a
                -- session that is weeks old.
                if #items > 0 and IsBatchTooOld(items) then
                    print(PREFIX .. string.format(
                        " |cFFFF4444Session is older than %d day(s) - restoration blocked.|r",
                        MAX_RELOAD_AGE_DAYS))
                    return
                end
                GMLootHistory:InjectItemsIntoVF(items)
            end)

            -- Export date
            btn._expBtn:SetScript("OnClick", function()
                local sessionsToExport = {}
                for _, entry in ipairs(g.entries) do
                    table.insert(sessionsToExport, {
                        session       = entry.session_num,
                        item          = entry.item,
                        item_link_raw = entry.item_link_raw,
                        item_id       = entry.item_id,
                        item_ilvl     = entry.item_ilvl,
                        awarded_to    = entry.awarded_to,
                        candidates    = entry.candidates
                    })
                end
                if RCLootCouncil_GuildMastery_ExportSessions then
                    RCLootCouncil_GuildMastery_ExportSessions(sessionsToExport, true)
                end
            end)

            -- Delete date
            btn._delBtn:SetScript("OnClick", function()
                StaticPopupDialogs["GUILDMASTERY_DELETE_DATE"] = {
                    text = "Do you really want to delete every session of this date?",
                    button1 = "Confirm", button2 = "Cancel",
                    OnAccept = function()
                        DeleteDate(dateStr)
                        if _selectedDate == dateStr then
                            _selectedDate = nil
                        end
                        _dateGroups = BuildDateGroups()
                        RefreshDateList()
                        PopulateItems(_selectedDate)
                        if not _selectedDate then UpdateDetail(nil) end
                        if _countLabel then
                            local n = #GetDB().history
                            _countLabel:SetText("|cFF888888"..n.." "..(n>1 and "sessions saved" or "session saved").."|r")
                        end
                    end,
                    timeout = 0, whileDead = true, hideOnEscape = true,
                }
                StaticPopup_Show("GUILDMASTERY_DELETE_DATE")
            end)
        end
    end
    _dateSC:SetHeight(math.max(idx * (ROW_H + 4), 1))
end

RebuildAll = function()
    _dateGroups = BuildDateGroups()
    RefreshDateList()
    if _selectedDate then
        local found = false
        for _, g in ipairs(_dateGroups) do if g.date == _selectedDate then found = true; break end end
        if not found then _selectedDate = nil end
    end
    if _selectedDate then
        PopulateItems(_selectedDate)
    else
        for _, b in ipairs(_itemBtnPool) do b:Hide() end
        if _itemSC then _itemSC:SetHeight(1) end
        UpdateDetail(nil)
    end
    if _selectedDate and _selectedEntry then
        -- Verify that the selected entry still exists
        local found = false
        local hist  = GetDB().history
        for _, e in ipairs(hist) do if e.id == _selectedEntry.id then found = true; break end end
        if not found then UpdateDetail(nil)
        else UpdateDetail(_selectedEntry) end
    end
    if _countLabel then
        local n = #GetDB().history
        _countLabel:SetText("|cFF888888"..n.." "..(n>1 and "sessions saved" or "session saved").."|r")
    end
end

-- ============================================================
-- Frame construction
-- ============================================================

function GMLootHistory:GetOrCreateFrame()
    if _frame then return _frame end

    local rc
    local ok, res = pcall(function() return LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil") end)
    if ok then rc = res end

    -- Hide any leftover frame in memory (WoW does not destroy frames on /reload)
    if _G["RCGMLootHistoryFrame"] then _G["RCGMLootHistoryFrame"]:Hide() end

    local f
    if rc and rc.UI then
        -- The 5th parameter of RCFrame:NewNamed is the TITLE width (ex: 250), the 6th is the height.
        f = rc.UI:NewNamed("RCFrame", UIParent, "RCGMLootHistoryFrameV2", "GuildMastery - Vote history", 300, FRAME_H)
        f:SetWidth(FRAME_W) -- This automatically resizes f.content via RCFrame's internal HookScript
        f:SetPoint("CENTER")

        -- Solid dark background directly on f.content (no tiled texture)
        if f.content and f.content.SetBackdrop then
            f.content:SetBackdrop({
                bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile     = false,
                edgeSize = 12,
                insets   = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            f.content:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
            f.content:SetBackdropBorderColor(0.3, 0.3, 0.5, 0.8)
        end
    else
        f = CreateFrame("Frame", "RCGMLootHistoryFrameV2", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(FRAME_W, FRAME_H)
        f.content = f -- fallback for the rest of the code
        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.title:SetPoint("LEFT", f.TitleBg, "LEFT", 5, 0)
        f.title:SetText("GuildMastery - Vote history")
        f:SetPoint("CENTER")
        f:SetMovable(true); f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop",  f.StopMovingOrSizing)
        f:SetFrameStrata("HIGH"); f:SetFrameLevel(100)
        f:SetClampedToScreen(true)
    end

    -- Vertical separators
    local function VSep(x)
        local s = f.content:CreateTexture(nil, "ARTWORK"); s:SetWidth(1)
        s:SetPoint("TOPRIGHT",    f.content, "TOPLEFT",    x, -26)
        s:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMLEFT", x,  SF_BOT_Y)
        s:SetColorTexture(0.3, 0.3, 0.4, 0.9)
    end
    VSep(SEP1_X); VSep(SEP2_X)

    -- Headers
    local function Hdr(txt, x, w)
        local fs = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", f.content, "TOPLEFT", x, HDR_Y)
        fs:SetWidth(w); fs:SetJustifyH("LEFT")
        fs:SetText("|cFFBBBBCC"..txt.."|r")
    end
    Hdr("Raid dates",          DATE_SF_L,   DATE_SC_W)
    Hdr("Time  Item",          ITEMS_SF_L,  ITEMS_SC_W)
    Hdr("Session detail",      DETAIL_SF_L, DET_W)

    -- Horizontal separator
    local function HSep(x1, x2)
        local s = f.content:CreateTexture(nil, "ARTWORK"); s:SetHeight(1)
        s:SetPoint("TOPLEFT",  f.content, "TOPLEFT", x1, SEP_H_Y)
        s:SetPoint("TOPRIGHT", f.content, "TOPLEFT", x2, SEP_H_Y)
        s:SetColorTexture(0.35, 0.35, 0.45, 0.9)
    end
    HSep(DATE_SF_L,   SEP1_X)
    HSep(ITEMS_SF_L,  SEP2_X)
    HSep(DETAIL_SF_L, FRAME_W - 4)

    -- Dates ScrollFrame
    local dateSF = CreateFrame("ScrollFrame", "RCGMHistDateSF", f.content, "UIPanelScrollFrameTemplate")
    dateSF:SetPoint("TOPLEFT",     f.content, "TOPLEFT",    DATE_SF_L,                    SF_TOP_Y)
    dateSF:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMLEFT", DATE_SF_L + DATE_SF_W - SB_W, SF_BOT_Y)
    dateSF:SetFrameLevel(f.content:GetFrameLevel() + 5)
    local dateSC = CreateFrame("Frame", nil, dateSF)
    dateSC:SetWidth(DATE_SC_W); dateSC:SetHeight(1)
    dateSF:SetScrollChild(dateSC)
    _dateSC = dateSC

    -- Items ScrollFrame
    local itemSF = CreateFrame("ScrollFrame", "RCGMHistItemSF", f.content, "UIPanelScrollFrameTemplate")
    itemSF:SetPoint("TOPLEFT",     f.content, "TOPLEFT",    ITEMS_SF_L,                    SF_TOP_Y)
    itemSF:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMLEFT", ITEMS_SF_L + ITEMS_SF_W - SB_W, SF_BOT_Y)
    itemSF:SetFrameLevel(f.content:GetFrameLevel() + 5)
    local itemSC = CreateFrame("Frame", nil, itemSF)
    itemSC:SetWidth(ITEMS_SC_W); itemSC:SetHeight(1)
    itemSF:SetScrollChild(itemSC)
    _itemSC = itemSC

    -- Detail ScrollFrame
    local detSF = CreateFrame("ScrollFrame", "RCGMHistDetailSF", f.content, "UIPanelScrollFrameTemplate")
    detSF:SetPoint("TOPLEFT",     f.content, "TOPLEFT",    DETAIL_SF_L,   SF_TOP_Y)
    detSF:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMRIGHT", -(SB_W + 8),  SF_BOT_Y)
    detSF:SetFrameLevel(f.content:GetFrameLevel() + 5)

    -- Detail content: Frame (not EditBox) with FontStrings + candidate rows
    local detSC = CreateFrame("Frame", nil, detSF)
    detSC:SetWidth(DET_W); detSC:SetHeight(1)
    detSF:SetScrollChild(detSC)
    _detailSC = detSC

    -- Header FontStrings
    _detFS_item = detSC:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    _detFS_item:SetPoint("TOPLEFT",  detSC, "TOPLEFT",  4, DET_ITEM_Y)
    _detFS_item:SetPoint("TOPRIGHT", detSC, "TOPRIGHT", -4, DET_ITEM_Y)
    _detFS_item:SetJustifyH("LEFT"); _detFS_item:SetWordWrap(false)
    _detFS_item:SetText("|cFF555555Select a date to get started.|r")

    _detFS_meta = detSC:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    _detFS_meta:SetPoint("TOPLEFT",  detSC, "TOPLEFT",  4, DET_META_Y)
    _detFS_meta:SetPoint("TOPRIGHT", detSC, "TOPRIGHT", -4, DET_META_Y)
    _detFS_meta:SetJustifyH("LEFT")

    _detFS_award = detSC:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    _detFS_award:SetPoint("TOPLEFT",  detSC, "TOPLEFT",  4, DET_AWARD_Y)
    -- Leaves 22px on the right for the "unaward" button
    _detFS_award:SetPoint("TOPRIGHT", detSC, "TOPRIGHT", -26, DET_AWARD_Y)
    _detFS_award:SetJustifyH("LEFT")

    -- "Unaward" button: amber rotating-arrow icon, visible only when
    -- entry.awarded_to ~= "". Click -> confirmation popup -> reset.
    _detUnawardBtn = CreateFrame("Button", nil, detSC)
    _detUnawardBtn:SetSize(18, 18)
    _detUnawardBtn:SetPoint("TOPRIGHT", detSC, "TOPRIGHT", -4, DET_AWARD_Y - 2)

    local ua_tex = _detUnawardBtn:CreateTexture(nil, "ARTWORK")
    ua_tex:SetAllPoints()
    ua_tex:SetTexture("Interface\\BUTTONS\\UI-RotationLeft-Button-Up")
    ua_tex:SetVertexColor(1.0, 0.75, 0.4) -- amber = "go back"

    _detUnawardBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-RotationLeft-Button-Up")
    local ua_hl = _detUnawardBtn:GetHighlightTexture()
    ua_hl:SetVertexColor(1.0, 1.0, 1.0)
    ua_hl:SetBlendMode("ADD")

    _detUnawardBtn:SetPushedTexture("Interface\\BUTTONS\\UI-RotationLeft-Button-Down")

    _detUnawardBtn:Hide()

    _detUnawardBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cFFFFAA00Unaward|r")
        GameTooltip:AddLine("Removes the item award.\nThe item becomes eligible for restoration again.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    _detUnawardBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    _detUnawardBtn:SetScript("OnClick", function()
        if not _selectedEntry or _selectedEntry.awarded_to == "" then return end
        local prevName = _selectedEntry.awarded_to or "?"
        StaticPopupDialogs["GUILDMASTERY_UNAWARD"] = {
            text          = string.format("Unaward this item from |cFFFFD700%s|r?", prevName),
            button1       = "Confirm",
            button2       = "Cancel",
            timeout       = 0,
            whileDead     = true,
            hideOnEscape  = true,
            preferredIndex = STATICPOPUP_NUMDIALOGS,
            OnAccept = function()
                local hist = GetDB().history
                local itemLinkRaw = _selectedEntry.item_link_raw
                for _, e in ipairs(hist) do
                    if e.id == _selectedEntry.id then
                        e.awarded_to = ""
                        -- Reset the candidates that RC marked "AWARDED" on
                        -- award. Without this, the reload via the refresh
                        -- button would re-display "Assigned" on the candidate.
                        if e.candidates then
                            for _, c in ipairs(e.candidates) do
                                if c.response_code == "AWARDED" then
                                    if c.real_response_code and c.real_response_code ~= "" then
                                        c.response_code = c.real_response_code
                                    else
                                        c.response_code = "WAIT"
                                    end
                                    c.response = "" -- RC will recompute the label from the code
                                end
                            end
                        end
                        break
                    end
                end
                if RCLootCouncil_GuildMastery_UpdateSyncPayload then
                    RCLootCouncil_GuildMastery_UpdateSyncPayload()
                end

                -- Try to sync to RCLootCouncil history (broadcast if ML).
                local rcOk, rcMode = RemoveFromRCHistory(prevName, itemLinkRaw)
                local rcMsg
                if rcOk and rcMode == "broadcast" then
                    rcMsg = "GM + RC (broadcast)"
                elseif rcOk and rcMode == "local" then
                    rcMsg = "GM + RC local"
                else
                    rcMsg = "GM only (RC sync unavailable)"
                end

                -- Refresh: detail panel + items column (for visual feedback)
                UpdateDetail(_selectedEntry)
                if _selectedDate and PopulateItems then PopulateItems(_selectedDate) end
                print(PREFIX .. string.format(
                    " |cFF88FF88Item unawarded (was: %s) - %s.|r",
                    prevName, rcMsg))
            end,
        }
        StaticPopup_Show("GUILDMASTERY_UNAWARD")
    end)

    -- Thin separator line just above the Candidates header for visual polish
    local detSep = detSC:CreateTexture(nil, "ARTWORK")
    detSep:SetHeight(1)
    detSep:SetPoint("TOPLEFT",  detSC, "TOPLEFT",  4,  DET_CHDR_Y + 4)
    detSep:SetPoint("TOPRIGHT", detSC, "TOPRIGHT", -4, DET_CHDR_Y + 4)
    detSep:SetColorTexture(0.3, 0.3, 0.38, 0.6)

    _detFS_candHdr = detSC:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    _detFS_candHdr:SetPoint("TOPLEFT",  detSC, "TOPLEFT",  4, DET_CHDR_Y)
    _detFS_candHdr:SetPoint("TOPRIGHT", detSC, "TOPRIGHT", -4, DET_CHDR_Y)
    _detFS_candHdr:SetJustifyH("LEFT")

    -- Filters (created AFTER the scroll frames)
    local function MakeFilter(name, x, w, placeholder, onChange)
        local eb = CreateFrame("EditBox", name, f.content, "InputBoxTemplate")
        eb:SetSize(w, 20)
        eb:SetPoint("TOPLEFT", f.content, "TOPLEFT", x, FILTER_Y)
        eb:SetFontObject("GameFontNormalSmall")
        eb:SetAutoFocus(false); eb:SetMaxLetters(60)

        local hint = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("LEFT", eb, "LEFT", 5, 0)
        hint:SetPoint("RIGHT", eb, "RIGHT", -4, 0)
        hint:SetJustifyH("LEFT")
        hint:SetText("|cFF666666"..placeholder.."|r")

        local function syncHint(self)
            hint:SetShown(self:GetText() == "")
        end
        eb:SetScript("OnTextChanged",     function(self) syncHint(self); onChange(self:GetText():lower()) end)
        eb:SetScript("OnEditFocusGained", function(self) hint:Hide() end)
        eb:SetScript("OnEditFocusLost",   function(self) syncHint(self) end)
        eb:SetScript("OnEscapePressed",   function(self) self:SetText(""); self:ClearFocus() end)
        return eb
    end

    MakeFilter("RCGMHistDateFilterEB", DATE_SF_L, DATE_SC_W + 4, "Filter by date...", function(v)
        _dateFilterStr = v
        RefreshDateList()
        PopulateItems(_selectedDate)
    end)

    MakeFilter("RCGMHistItemFilterEB", ITEMS_SF_L, SEP2_X - ITEMS_SF_L - 6, "Filter by item...", function(v)
        _itemFilterStr = v
        RefreshDateList()
        PopulateItems(_selectedDate)
    end)

    -- Bottom buttons (custom styled, dark + accent border)
    local btnClose = RCLootCouncil_GuildMastery_MakeButton(f.content, 80, 22, "Close")
    btnClose:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMRIGHT", -8, 8)
    btnClose:SetScript("OnClick", function() f:Hide() end)

    local btnClear = RCLootCouncil_GuildMastery_MakeButton(f.content, 120, 22, "Clear history", { danger = true })
    btnClear:SetPoint("BOTTOMLEFT", f.content, "BOTTOMLEFT", 160, 8)
    btnClear:SetScript("OnClick", function()
        StaticPopupDialogs["GUILDMASTERY_CLEAR_HISTORY"] = {
            text = "Clear all vote history?",
            button1 = "Confirm", button2 = "Cancel",
            OnAccept = function()
                GetDB().history = {}
                _selectedDate = nil
                _selectedEntry = nil
                RebuildAll()
                print(PREFIX .. " History cleared.")
            end,
            timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("GUILDMASTERY_CLEAR_HISTORY")
    end)

    -- The second Close button has been removed.

    tinsert(UISpecialFrames, "RCGMLootHistoryFrameV2")
    _frame = f
    return f
end

-- ============================================================
-- Public API
-- ============================================================

function GMLootHistory:Show()
    local f = self:GetOrCreateFrame()
    RebuildAll()
    f:Show(); f:Raise()
end

function GMLootHistory:Hide()
    if _frame then _frame:Hide() end
end

function GMLootHistory:Toggle()
    if _frame and _frame:IsShown() then self:Hide() else self:Show() end
end
