-- RCLootCouncil_GuildMastery/core.lua
-- Commands : /gm export | /gm history | /gm dump | /gm debug
-- Version  : 1.0.0

local ADDON_NAME = "RCLootCouncil_GuildMastery"
local PREFIX     = "|cFF9B7EDE[GuildMastery]|r"

-- ============================================================
-- Debug gating
-- ============================================================
-- DebugPrint only outputs when RCLootCouncil_GuildMasteryDB.debug == true.
-- Toggle with /gm debug. Use /gm dump for explicit on-demand dumps.

local function DebugPrint(msg)
    local db = RCLootCouncil_GuildMasteryDB
    if db and db.debug then
        print(PREFIX .. " |cFF8888FF[Debug]|r " .. tostring(msg))
    end
end

-- Exposed globally so History.lua can reuse the same gating without duplicating logic.
RCLootCouncil_GuildMastery_DebugPrint = DebugPrint

-- ============================================================
-- Minimal JSON serializer
-- ============================================================

local function escapeStr(s)
    return (s or "")
        :gsub('\\', '\\\\')
        :gsub('"',  '\\"')
        :gsub('\n', '\\n')
        :gsub('\r', '\\r')
        :gsub('\t', '\\t')
end

local function toJSON(val, _depth)
    _depth = _depth or 0
    if _depth > 12 then return '"[MAX_DEPTH]"' end
    local t = type(val)
    if val == nil then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        return tostring(val)
    elseif t == "string" then
        return '"' .. escapeStr(val) .. '"'
    elseif t == "table" then
        local maxN, count = 0, 0
        for k, _ in pairs(val) do
            count = count + 1
            if type(k) == "number" and k > maxN then maxN = k end
        end
        local isArray = (count == 0 or maxN == count)
        if isArray then
            local parts = {}
            for i = 1, maxN do parts[i] = toJSON(val[i], _depth + 1) end
            return "[" .. table.concat(parts, ", ") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                table.insert(parts, '"' .. escapeStr(tostring(k)) .. '": ' .. toJSON(v, _depth + 1))
            end
            return "{" .. table.concat(parts, ", ") .. "}"
        end
    end
    return "null"
end

-- ============================================================
-- RC helpers
-- ============================================================

local function GetRC()
    local ok, rc = pcall(function()
        return LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
    end)
    return (ok and rc) and rc or nil
end

-- Minimum RCLootCouncil version required. Older versions may lack APIs we use
-- (UnTrackAndLogLoot, GetHistoryDB, real_response field on candidates, etc.).
local MIN_RC_VERSION = "3.21.1"

local function ParseSemver(v)
    if type(v) ~= "string" then return 0, 0, 0 end
    local maj, min, pat = v:match("(%d+)%.(%d+)%.?(%d*)")
    return tonumber(maj) or 0, tonumber(min) or 0, tonumber(pat) or 0
end

local function IsRCVersionAtLeast(actual, required)
    local a1, a2, a3 = ParseSemver(actual)
    local r1, r2, r3 = ParseSemver(required)
    if a1 ~= r1 then return a1 > r1 end
    if a2 ~= r2 then return a2 > r2 end
    return a3 >= r3
end

-- Prints a warning if the loaded RCLootCouncil is older than MIN_RC_VERSION.
-- Non-fatal: the addon keeps running, but the user is informed.
local function CheckRCVersion()
    local rc = GetRC()
    if not rc or not rc.version then return end
    if not IsRCVersionAtLeast(rc.version, MIN_RC_VERSION) then
        print(PREFIX .. string.format(
            " |cFFFFAA00Warning:|r RCLootCouncil v%s detected. v%s or higher is recommended for full compatibility.",
            tostring(rc.version), MIN_RC_VERSION))
    end
end

local function GetVFLootTable()
    local rc = GetRC()
    if not rc then return nil end

    local vf
    local ok, m = pcall(function() return rc:GetModule("RCVotingFrame") end)
    if ok and m then vf = m end

    if vf and vf.GetLootTable then
        local ok2, lt = pcall(function() return vf:GetLootTable() end)
        if ok2 and type(lt) == "table" then
            return lt, vf
        end
    end
    return nil, nil
end

local function cleanItemLink(link)
    if not link then return "" end
    return link:match("%[(.-)%]") or link
end

-- ============================================================
-- Popup window with copyable EditBox
-- ============================================================

local exportFrame

local function GetOrCreateExportFrame()
    if exportFrame then return exportFrame end

    local rc = GetRC()
    if not rc then
        print(PREFIX .. " |cFFFF4444Unable to find RCLootCouncil.|r")
        return nil
    end

    -- Use native RCFrame so ElvUI/AddOnSkins styling applies automatically.
    local f = rc.UI:NewNamed("RCFrame", UIParent, "RCGuildMasteryExportFrame", "RCLootCouncil - GuildMastery Export", 350, 440)
    -- Offset slightly bottom-right so it doesn't perfectly hide behind the center History frame
    f:SetPoint("CENTER", UIParent, "CENTER", 50, -50)
    f:SetFrameStrata("DIALOG")

    -- ScrollFrame: vertical scroll only, like RC History
    local scroll = CreateFrame("ScrollFrame", "RCGuildMasteryExportScroll", f.content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     f.content, "TOPLEFT",     12,  -12)
    scroll:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMRIGHT", -32,  44)

    local eb = CreateFrame("EditBox", "RCGuildMasteryExportEditBox", scroll)
    eb:SetAllPoints()
    eb:SetMultiLine(true)
    eb:SetFontObject(ChatFontNormal)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    eb:SetScript("OnCursorChanged", function(self, _, y, _, cursorHeight)
        y = -y
        local offset = scroll:GetVerticalScroll()
        if y < offset then
            scroll:SetVerticalScroll(y)
        else
            y = y + cursorHeight - scroll:GetHeight()
            if y > offset then
                scroll:SetVerticalScroll(y)
            end
        end
    end)
    scroll:SetScrollChild(eb)
    scroll:SetScript("OnSizeChanged", function(self, w)
        eb:SetWidth(w)
    end)

    local btnAll = RCLootCouncil_GuildMastery_MakeButton(f.content, 140, 26, "Select all")
    btnAll:SetPoint("BOTTOMLEFT", f.content, "BOTTOMLEFT", 8, 10)
    btnAll:SetScript("OnClick", function()
        eb:SetFocus()
        eb:HighlightText()
    end)

    local btnClose = RCLootCouncil_GuildMastery_MakeButton(f.content, 90, 26, "Close")
    btnClose:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMRIGHT", -8, 10)
    btnClose:SetScript("OnClick", function() f:Hide() end)

    f.editBox = eb
    exportFrame = f
    return f
end

local function parseItemLink(link)
    if not link or link == "" then return nil end
    local itemId = link:match("Hitem:(%d+)")
    local name   = link:match("%[(.-)%]")
    local ilvl   = 0
    if GetDetailedItemLevelInfo then
        local ok, lvl = pcall(function() return GetDetailedItemLevelInfo(link) end)
        if ok and type(lvl) == "number" then ilvl = lvl end
    end
    return {
        id       = tonumber(itemId) or 0,
        name     = name or "",
        ilvl     = ilvl,
        link_raw = link,
    }
end

-- ============================================================
-- Response labels
-- ============================================================

local RESPONSE_DEFAULTS = {
    ["PASS"]        = "Pass",
    ["AUTOPASS"]    = "Autopass",
    ["ANNOUNCED"]   = "Announced",
    ["WAIT"]        = "Waiting",
    ["TIMEOUT"]     = "Timeout",
    ["REMOVED"]     = "Removed",
    ["NOTHING"]     = "Absent",
    ["NOTELIGIBLE"] = "Not eligible",
    ["BONUSROLL"]   = "Bonus Roll",
    ["DISABLED"]    = "RC disabled",
    ["NOTINRAID"]   = "Out of instance",
}

local function getResponseLabel(rc, typeCode, code)
    if rc and rc.GetResponse then
        local ok, resp = pcall(function() return rc:GetResponse(typeCode, code) end)
        if ok and resp and resp.text
            and not resp.text:find("indisponible")
            and not resp.text:find("unavailable") then
            return resp.text
        end
    end
    local s = tostring(code or "")
    return RESPONSE_DEFAULTS[s] or s
end

-- ============================================================
-- Build sessions from the RC lootTable
-- ============================================================

local function BuildSessionsFromLootTable()
    local lt, _ = GetVFLootTable()
    local rc    = GetRC()
    if not lt then return nil end

    local activeSessions = {}
    for k, sd in pairs(lt) do
        if type(sd) == "table" and sd.candidates and next(sd.candidates) then
            table.insert(activeSessions, k)
        end
    end
    table.sort(activeSessions)
    if #activeSessions == 0 then return nil end

    local sessions = {}
    for _, sessionIdx in ipairs(activeSessions) do
        local sd = lt[sessionIdx]
        local _, _, diffID, diffName = GetInstanceInfo()
        local sessionExport = {
            session       = sessionIdx,
            item          = cleanItemLink(sd.link),
            item_link_raw = sd.link or "",
            item_id       = sd.itemID or 0,
            item_ilvl     = sd.ilvl or 0,
            awarded_to    = sd.awarded or "",
            looted_at     = time(),
            difficulty_id   = diffID   or 0,
            difficulty_name = diffName or "",
            candidates    = {},
        }
        local typeCode = sd.typeCode or sd.equipLoc or nil
        for name, d in pairs(sd.candidates) do
            local responseCode = tostring(d.response or "")
            -- When an item is awarded, RC overwrites d.response with "AWARDED"
            -- and stores the real vote response in d.real_response. We capture
            -- it so we can restore the pre-award state on un-award.
            local realResponseCode = ""
            if d.real_response ~= nil then
                realResponseCode = tostring(d.real_response)
            end
            local voterList = {}
            if type(d.voters) == "table" then
                for _, v in ipairs(d.voters) do table.insert(voterList, tostring(v)) end
            end
            local equipped = {}
            local g1 = parseItemLink(d.gear1)
            local g2 = parseItemLink(d.gear2)
            if g1 then table.insert(equipped, g1) end
            if g2 then table.insert(equipped, g2) end

            table.insert(sessionExport.candidates, {
                name               = name,
                class              = d.class   or "",
                role               = d.role    or "",
                rank               = d.rank    or "",
                spec_id            = d.specID  or 0,
                response           = getResponseLabel(rc, typeCode, d.response),
                response_code      = responseCode,
                real_response_code = realResponseCode,
                ilvl               = tonumber(d.ilvl)  or 0,
                ilvl_diff          = tonumber(d.diff)  or 0,
                roll               = d.roll    or 0,
                votes              = d.votes   or 0,
                voters             = voterList,
                note               = d.note    or "",
                equipped           = equipped,
            })
        end
        table.sort(sessionExport.candidates, function(a, b)
            local ca = tonumber(a.response_code)
            local cb = tonumber(b.response_code)
            if ca and cb then
                if ca ~= cb then return ca < cb end
            elseif ca then return true
            elseif cb then return false end
            if a.votes ~= b.votes then return a.votes > b.votes end
            return a.name < b.name
        end)
        table.insert(sessions, sessionExport)
    end
    return sessions
end

-- ============================================================
-- Auto-save from RC hook
-- ============================================================

local function AutoSaveFromRC()
    local rc = GetRC()
    local ml = rc and rc:GetModule("RCMLCore", true)
    if ml and ml.isHistoricalLoad then
        DebugPrint("AutoSave skipped because isHistoricalLoad is set.")
        return
    end

    if not GMLootHistory then return end
    local sessions = BuildSessionsFromLootTable()
    if not sessions or #sessions == 0 then return end
    DebugPrint("Triggering AutoSaveFromRC (sessions: " .. #sessions .. ")")
    local saved = GMLootHistory:SaveSessions(sessions, true)  -- 5 min dedup
    if saved > 0 then
        print(PREFIX .. string.format(
            " |cFF88FF88Auto-save: %d session(s) added to history.|r",
            saved
        ))
    end
end

local lastAutoExportState = ""

local function CheckAllResponsesReceived()
    local rc = GetRC()
    local ml = rc and rc:GetModule("RCMLCore", true)
    if ml and ml.isHistoricalLoad then return end

    local sessions = BuildSessionsFromLootTable()
    if not sessions or #sessions == 0 then return end

    local allResponded = true
    local stateHash = ""
    for _, s in ipairs(sessions) do
        stateHash = stateHash .. s.session .. "-"
        for _, c in ipairs(s.candidates) do
            if c.response_code == "ANNOUNCED" or c.response_code == "WAIT" then
                allResponded = false
                break
            end
        end
        if not allResponded then break end
    end

    if allResponded then
        if lastAutoExportState ~= stateHash then
            lastAutoExportState = stateHash
            -- Silent auto-save into history (do not open the export popup)
            if GMLootHistory then
                local saved = GMLootHistory:SaveSessions(sessions, true)
                if saved > 0 then
                    print(PREFIX .. string.format(
                        " |cFF88FF88All votes received - %d session(s) saved.|r",
                        saved
                    ))
                end
            end
        end
    else
        lastAutoExportState = ""
    end
end

-- Forward declarations: these functions are defined further below but referenced
-- inside the badge OnClick closure in AddSaveButton (see TryHookRC). Without the
-- forward decl, Lua would resolve the reference to _G.SaveAndReload (= nil).
local SaveAndReload
local CheckPendingRestore

local function TryHookRC()
    local rc = GetRC()
    if not rc then return end

    local function hookMethod(tbl, methodName)
        if tbl and type(tbl[methodName]) == "function" then
            hooksecurefunc(tbl, methodName, function()
                C_Timer.After(0.5, AutoSaveFromRC)
            end)
            return true
        end
        return false
    end

    -- VotingFrame: end of session
    local ok1, vf = pcall(function() return rc:GetModule("RCVotingFrame") end)
    if ok1 and vf then
        local _ = hookMethod(vf, "EndSession") or hookMethod(vf, "Award") or hookMethod(vf, "SessionDone")

        -- Hook on SetCandidateData: fires on every candidate response change.
        local _checkPending = false
        if type(vf.SetCandidateData) == "function" then
            hooksecurefunc(vf, "SetCandidateData", function(self, ses, name, key)
                if key == "response" and not _checkPending then
                    _checkPending = true
                    C_Timer.After(1, function()
                        _checkPending = false
                        CheckAllResponsesReceived()
                    end)
                end
            end)
        end

        -- GuildMastery badge (outside the frame, top-right) to avoid conflicts
        -- with other addons that inject buttons into the internal toolbar.
        local function AddSaveButton()
            local ok, err = pcall(function()
                if not vf.GetFrame then return end
                local f = vf:GetFrame()
                if not f or f.gmSaveBtn then return end

                -- Parent the badge to f.content (not f directly) so it inherits
                -- visibility: when the user collapses the voting frame via the
                -- RCFrame Minimize button, f.content gets Hide() called and the
                -- badge disappears with it. When maximized, content:Show() brings
                -- the badge back. Anchor still references f for positioning.
                local btn = CreateFrame("Button", nil, f.content)
                btn:SetSize(32, 32)
                -- Badge BOTTOMRIGHT anchored to frame TOPRIGHT, offset (-8, +6):
                -- the badge sits above the frame near the top-right corner.
                -- Top placement avoids overlap with RC's right-side tooltips
                -- that appear when hovering a candidate row.
                btn:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -8, 6)
                btn:SetFrameStrata("HIGH")
                btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

                local tex = btn:CreateTexture(nil, "ARTWORK")
                tex:SetAllPoints()
                tex:SetTexture("Interface\\AddOns\\RCLootCouncil_GuildMastery\\Media\\logo-gm.png")

                local hl = btn:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.2)

                btn:SetScript("OnClick", function(_, button)
                    if button == "RightButton" then
                        SaveAndReload()
                    else
                        SlashCmdList["GUILDMASTERY"]("export_active")
                    end
                end)
                btn:SetScript("OnEnter", function()
                    if rc.CreateTooltip then
                        rc:CreateTooltip("|cFFFFD700Save and Export|r\n\n|cFFAAAAAALeft click|r: JSON popup for copy-paste\n|cFFAAAAAARight click|r: Save & Reload + auto-restore\n(triggers GuildMasterySync server upload)")
                    end
                end)
                btn:SetScript("OnLeave", function()
                    if rc.HideTooltip then rc:HideTooltip() end
                end)
                f.gmSaveBtn = btn
            end)
            if not ok then
                print(PREFIX .. " |cFFFF4444AddSaveButton error: |r" .. tostring(err))
            end
        end

        -- Hook OnEnable for future sessions
        if type(vf.OnEnable) == "function" then
            hooksecurefunc(vf, "OnEnable", AddSaveButton)
        end
        -- If the frame already exists (OnEnable already fired), inject now.
        -- We check vf.frame without calling GetFrame() to avoid forcing creation.
        if vf.frame then
            AddSaveButton()
        end
    end

    -- MLCore: awarding
    local ok2, ml = pcall(function() return rc:GetModule("RCMLCore") end)
    if ok2 and ml then
        local _ = hookMethod(ml, "Award") or hookMethod(ml, "AwardItem")
    end
end

-- ============================================================
-- Debug dump (explicit, on-demand via /gm dump)
-- ============================================================

local function DebugDump()
    local lt, vf = GetVFLootTable()
    if not lt then
        print(PREFIX .. " |cFFFF4444Unable to access the VF lootTable.|r")
        return
    end
    local rc = GetRC()
    print(PREFIX .. " ===== DUMP =====")
    for k, sd in pairs(lt) do
        if type(sd) == "table" then
            print(PREFIX .. string.format(" Session[%s] item=%s", tostring(k), cleanItemLink(sd.link)))
            if sd.candidates then
                for name, d in pairs(sd.candidates) do
                    local voterList = {}
                    if type(d.voters) == "table" then
                        for _, v in ipairs(d.voters) do
                            table.insert(voterList, tostring(v))
                        end
                    end
                    local typeCode = sd.typeCode or sd.equipLoc or nil
                    print(PREFIX .. string.format(
                        "   [%s] response=%s(%s) ilvl=%.0f diff=%s votes=%s voters=[%s]",
                        name,
                        getResponseLabel(rc, typeCode, d.response),
                        tostring(d.response),
                        d.ilvl or 0,
                        tostring(d.diff or 0),
                        tostring(d.votes or 0),
                        table.concat(voterList, ",")
                    ))
                end
            else
                print(PREFIX .. "   (no candidates)")
            end
        end
    end
    print(PREFIX .. " ===== END =====")
end

-- ============================================================
-- Main export
-- ============================================================

function RCLootCouncil_GuildMastery_UpdateSyncPayload()
    if not GMLootHistory or not GMLootHistory.GetAllSessions then return end
    local sessions = GMLootHistory:GetAllSessions()

    local exportData = {
        addon            = ADDON_NAME .. "_FullSync",
        version          = "1.0.0",
        timestamp        = date("!%Y-%m-%dT%H:%M:%SZ"),
        is_full_sync     = true,
        sessions         = sessions,
    }

    local json = toJSON(exportData)
    local db = RCLootCouncil_GuildMasteryDB
    if not db then db = {} end
    db.syncPayload = json
end

function RCLootCouncil_GuildMastery_ExportSessions(sessions, suppressSave)
    if not sessions or #sessions == 0 then return end

    local _, _, difficultyID, difficultyName = GetInstanceInfo()

    local exportData = {
        addon            = ADDON_NAME,
        version          = "1.0.0",
        timestamp        = date("!%Y-%m-%dT%H:%M:%SZ"),
        difficulty_id    = difficultyID   or 0,
        difficulty_name  = difficultyName or "",
        sessions         = sessions,
    }

    -- Auto-save into history (deduplicated over 5 min)
    if not suppressSave and GMLootHistory then
        local saved = GMLootHistory:SaveSessions(sessions, true)
        if saved > 0 then
            print(PREFIX .. string.format(
                " |cFF88FF88%d session(s) added to history|r (total: %d).",
                saved, GMLootHistory:GetCount()
            ))
        end
    end

    local totalCandidates = 0
    for _, s in ipairs(sessions) do totalCandidates = totalCandidates + #(s.candidates or {}) end

    local json = toJSON(exportData)

    -- Persist the last export as JSON in the main DB (same file watched by GuildMasterySync)
    local db = RCLootCouncil_GuildMasteryDB
    if not db then db = {} end
    db.lastExport  = json
    db.lastUpdated = date("!%Y-%m-%dT%H:%M:%SZ")

    local f = GetOrCreateExportFrame()
    f.editBox:SetText(json)
    f:Show()
    f:Raise() -- Forces the frame to the top of its strata

    C_Timer.After(0.05, function()
        if f.editBox then
            f.editBox:SetFocus()
            f.editBox:HighlightText()
        end
    end)

    if not suppressSave then
        print(PREFIX .. string.format(
            " Export ready - %d session(s), %d candidates. |cFFFFD700CTRL+C|r to copy.",
            #sessions, totalCandidates
        ))
    end
end

-- ============================================================
-- Save & Reload: save the current session + ReloadUI.
-- On the next PLAYER_LOGIN, CheckPendingRestore() reads the flag and
-- automatically restores the session into the VotingFrame.
-- ============================================================

-- Lists candidates whose response is still pending (ANNOUNCED or WAIT).
-- Returns an array of { session, item, candidate } entries.
local function CollectPendingVoters(sessions)
    local pending = {}
    for _, s in ipairs(sessions or {}) do
        for _, c in ipairs(s.candidates or {}) do
            if c.response_code == "ANNOUNCED" or c.response_code == "WAIT" then
                table.insert(pending, {
                    session   = s.session,
                    item      = s.item,
                    candidate = c.name,
                })
            end
        end
    end
    return pending
end

-- Performs the actual save + flag + ReloadUI. Extracted from SaveAndReload so
-- it can be invoked from a confirmation popup's OnAccept (still a secure
-- hardware-event context, so ReloadUI is allowed).
local function DoSaveAndReload(sessions)
    if not GMLootHistory or not GMLootHistory.SaveSessions then
        print(PREFIX .. " |cFFFF4444History module not loaded.|r")
        return
    end

    local saved = GMLootHistory:SaveSessions(sessions, true)
    if saved <= 0 then
        print(PREFIX .. " |cFFFFAA00No session saved (deduplicated).|r")
        return
    end

    local ts = GMLootHistory:GetLatestTimestamp()
    local db = RCLootCouncil_GuildMasteryDB or {}
    db.pendingRestore = {
        sessionTimestamp = ts,
        savedAt          = time(),
    }
    RCLootCouncil_GuildMasteryDB = db

    -- Forces the SavedVariables write. GuildMasterySync picks up the file
    -- and POSTs to the GuildMastery server.
    print(PREFIX .. " |cFF88FF88Save & Reload - auto-restore on next login.|r")
    -- ReloadUI() is a protected function: it MUST be called SYNCHRONOUSLY
    -- from a hardware-event context (badge click OR popup button click).
    -- No C_Timer.After here, otherwise ADDON_ACTION_BLOCKED.
    ReloadUI()
end

-- Assigned (not `local function`) because it is forward-declared above.
SaveAndReload = function()
    local ok, err = pcall(function()
        local sessions = BuildSessionsFromLootTable()
        if not sessions or #sessions == 0 then
            print(PREFIX .. " |cFFFF4444No active session.|r")
            return
        end

        local pending = CollectPendingVoters(sessions)
        if #pending == 0 then
            -- No pending votes: proceed directly.
            DoSaveAndReload(sessions)
            return
        end

        -- Build a short preview of pending voters (max 3 names + counter).
        local names = {}
        for i = 1, math.min(3, #pending) do
            table.insert(names, pending[i].candidate)
        end
        local sampleStr = table.concat(names, ", ")
        if #pending > 3 then
            sampleStr = sampleStr .. ", +" .. (#pending - 3) .. " more"
        end

        StaticPopupDialogs["GUILDMASTERY_SAVE_RELOAD_WARNING"] = {
            text = string.format(
                "|cFFFFAA00%d candidate(s) have not voted yet:|r\n%s\n\nSend the session to the server anyway?\nTheir current state will be saved as-is.",
                #pending, sampleStr),
            button1       = "Send anyway",
            button2       = "Cancel",
            timeout       = 0,
            whileDead     = true,
            hideOnEscape  = true,
            preferredIndex = STATICPOPUP_NUMDIALOGS,
            OnAccept = function()
                -- Rebuild sessions to capture any late votes that came in
                -- while the popup was open.
                local fresh = BuildSessionsFromLootTable() or sessions
                DoSaveAndReload(fresh)
            end,
        }
        StaticPopup_Show("GUILDMASTERY_SAVE_RELOAD_WARNING")
    end)
    if not ok then
        print(PREFIX .. " |cFFFF4444SaveAndReload error: |r" .. tostring(err))
    end
end

-- On PLAYER_LOGIN, if we have a fresh pendingRestore flag (< 60s), restore the
-- session into the VotingFrame using GMLootHistory:InjectItemsIntoVF.
-- Assigned (not `local function`) because it is forward-declared above.
CheckPendingRestore = function()
    local db = RCLootCouncil_GuildMasteryDB
    if not db or not db.pendingRestore then return end

    local pending = db.pendingRestore
    db.pendingRestore = nil -- consume the flag (avoid replay on subsequent logins)

    local age = time() - (pending.savedAt or 0)
    if age >= 60 then
        DebugPrint("pendingRestore too old (" .. age .. "s) - ignored.")
        return
    end
    if not pending.sessionTimestamp or pending.sessionTimestamp == 0 then return end

    local hist = (db.history or {})
    local items = {}
    for _, e in ipairs(hist) do
        if e.timestamp == pending.sessionTimestamp
           and e.item_link_raw and e.item_link_raw ~= ""
           and (not e.awarded_to or e.awarded_to == "") then
            table.insert(items, e)
        end
    end

    if #items == 0 then
        print(PREFIX .. " |cFFFFAA00No item to restore (perhaps already awarded).|r")
        return
    end

    if not GMLootHistory or not GMLootHistory.InjectItemsIntoVF then
        print(PREFIX .. " |cFFFF4444History module unavailable - cannot restore.|r")
        return
    end

    GMLootHistory:InjectItemsIntoVF(items, {
        silent = true,
        onSuccess = function(n)
            print(PREFIX .. string.format(" |cFF88FF88Session restored after reload (%d item(s)).|r", n))
        end,
        onError = function(msg)
            print(PREFIX .. " |cFFFF4444Could not restore session after reload: |r" .. tostring(msg) .. " |cFFFFAA00Recover it via /gm history.|r")
        end,
    })
end

local function ExportActiveSession()
    local ok, err = pcall(function()
        local sessions = BuildSessionsFromLootTable()
        if not sessions or #sessions == 0 then
            print(PREFIX .. " |cFFFF4444No active session or data unavailable.|r")
            return
        end
        RCLootCouncil_GuildMastery_ExportSessions(sessions, false)
    end)
    if not ok then
        print(PREFIX .. " |cFFFF4444ExportActive error: |r" .. tostring(err))
    end
end

local function ExportLastHistorySession()
    local ok, err = pcall(function()
        if not GMLootHistory or not GMLootHistory.GetLastSavedSessions then
            print(PREFIX .. " |cFFFF4444History module not loaded.|r")
            return
        end
        local sessions = GMLootHistory:GetLastSavedSessions()
        if not sessions or #sessions == 0 then
            print(PREFIX .. " |cFFFFAA00No session in history.|r")
            return
        end
        RCLootCouncil_GuildMastery_ExportSessions(sessions, true)
        print(PREFIX .. " |cFF88FF88Export from history.|r")
    end)
    if not ok then
        print(PREFIX .. " |cFFFF4444ExportHistory error: |r" .. tostring(err))
    end
end

SLASH_GUILDMASTERY1 = "/guildmastery"
SLASH_GUILDMASTERY2 = "/gm"

SlashCmdList["GUILDMASTERY"] = function(msg)
    local cmd = strtrim(msg or ""):lower()
    if cmd == "export" or cmd == "export_vote" then
        ExportLastHistorySession()
    elseif cmd == "export_active" then
        ExportActiveSession()
    elseif cmd == "history" or cmd == "h" or cmd == "hist" then
        if GMLootHistory then
            GMLootHistory:Toggle()
        else
            print(PREFIX .. " |cFFFF4444History module not loaded.|r")
        end
    elseif cmd == "dump" then
        DebugDump()
    elseif cmd == "debug" or cmd == "debug-toggle" or cmd == "debug-on" or cmd == "debug-off" or cmd == "dbg" then
        local db = RCLootCouncil_GuildMasteryDB
        if not db then
            RCLootCouncil_GuildMasteryDB = {}
            db = RCLootCouncil_GuildMasteryDB
        end
        if cmd == "debug-on" then
            db.debug = true
        elseif cmd == "debug-off" then
            db.debug = false
        else
            db.debug = not db.debug
        end
        if db.debug then
            print(PREFIX .. " |cFF88FF88Debug logging enabled.|r")
        else
            print(PREFIX .. " |cFF888888Debug logging disabled.|r")
        end
    else
        print(PREFIX .. " Commands:")
        print("  |cFFFFD700/gm export|r    - export votes as JSON (+ auto-save)")
        print("  |cFFFFD700/gm history|r   - open the session history")
        print("  |cFFFFD700/gm dump|r      - dump all candidates to the chat")
        print("  |cFFFFD700/gm debug|r     - toggle debug logging (off by default)")
        print("  Alias: |cFFAAAAFF/guildmastery|r")
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        -- Hook RC auto-save (delay so RC finishes its init)
        C_Timer.After(3, TryHookRC)
        -- Version check (after RC populates addon.version).
        C_Timer.After(3.5, CheckRCVersion)
        -- Auto-restore post-reload after RC has finished init (TryHookRC at 3s).
        C_Timer.After(4, CheckPendingRestore)
        -- Retention safety-net : prune entries older than 180 days at login,
        -- even when the user does not trigger a sync.
        C_Timer.After(2, function()
            if GMLootHistory and GMLootHistory.PruneOldEntries then
                GMLootHistory:PruneOldEntries()
            end
        end)

        print(PREFIX .. " loaded \194\183 |cFFFFD700/gm export|r \194\183 |cFFFFD700/gm history|r \194\183 |cFFFFD700/gm debug|r")
    elseif event == "PLAYER_LOGOUT" then
        if GMLootHistory and GMLootHistory.UpdateSyncPayload then
            GMLootHistory:UpdateSyncPayload()
        end
    end
end)
