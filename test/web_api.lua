-- ============================================================
-- web_api.lua — bridges the live Lua sim state to the browser UI (server.js).
-- Exposes WebAPI.dispatch(action, a1..a4) -> JSON string {ok, log, state}.
-- ============================================================

-- ---- tiny JSON encoder (controlled data only) ----
local function jesc(s)
    return (tostring(s):gsub('[%z\1-\31\\"]', function(c)
        local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return map[c] or string.format('\\u%04x', string.byte(c))
    end))
end

local function isArray(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do if t[i] == nil then return false end end
    return true, n
end

local function encode(v)
    local tv = type(v)
    if tv == "nil" then return "null"
    elseif tv == "boolean" then return v and "true" or "false"
    elseif tv == "number" then return (v ~= v or v == math.huge or v == -math.huge) and "null" or tostring(v)
    elseif tv == "string" then return '"' .. jesc(v) .. '"'
    elseif tv == "table" then
        local arr, n = isArray(v)
        if arr then
            local parts = {}
            for i = 1, n do parts[i] = encode(v[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, val in pairs(v) do
                parts[#parts + 1] = '"' .. jesc(k) .. '":' .. encode(val)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end
Sim.jsonEncode = encode

-- ---- response code -> readable label (matches RC defaults closely enough) ----
local RESP = { ["1"] = "MainSpec / Need", ["2"] = "OffSpec / Greed", ["3"] = "Greed",
               ["4"] = "Minor Upgrade", ["0"] = "Pass", ANNOUNCED = "Announced", WAIT = "Waiting" }
local function respLabel(code)
    return RESP[tostring(code)] or tostring(code)
end

-- ---- snapshot the whole visible state ----
local function state()
    local db = RCLootCouncil_GuildMasteryDB or {}
    local s = {
        clock       = os.date("!%Y-%m-%d %H:%M:%S", math.floor(Sim.clock)),
        clockEpoch  = math.floor(Sim.clock),
        zone        = Sim.zone or "—",
        difficulty  = Sim.difficultyName or "—",
        mlRunning   = Sim.ml.running and true or false,
        historical  = Sim.ml.isHistoricalLoad and true or false,
        reloadReq   = Sim.reloadRequested and true or false,
        historyCount = #(db.history or {}),
        pending     = db.pendingRestore ~= nil,
        pendingIds  = (db.pendingRestore and db.pendingRestore.ids and #db.pendingRestore.ids) or 0,
        group = {}, loot = {}, sessions = {},
    }
    for _, name in ipairs(Sim.group or {}) do
        local p = Sim.players[name] or {}
        table.insert(s.group, { name = name, class = p.class or "?" })
    end
    for _, it in ipairs(Sim.loot or {}) do
        table.insert(s.loot, { id = it.id, name = it.name, ilvl = it.ilvl,
                               boss = it.boss, slot = it.slot, quality = it.quality, icon = it.icon })
    end
    local lt = Sim.vf:GetLootTable() or {}
    for idx, entry in ipairs(lt) do
        local meta = Sim.lootById[entry.itemID] or {}
        local sess = { session = idx, item = (entry.link or ""):match("%[(.-)%]") or "?",
                       itemId = entry.itemID, boss = entry.boss or meta.boss or "",
                       ilvl = entry.ilvl or meta.ilvl, quality = meta.quality or 4,
                       icon = meta.icon or "❓", slot = meta.slot or "",
                       awarded = (type(entry.awarded) == "string") and entry.awarded or "",
                       candidates = {} }
        for name, c in pairs(entry.candidates or {}) do
            table.insert(sess.candidates, {
                name = name, class = c.class or "?",
                response = respLabel(c.response), responseCode = tostring(c.response),
                votes = c.votes or 0,
                voters = c.voters or {},
                haveVoted = c.haveVoted and true or false,
            })
        end
        table.sort(sess.candidates, function(a, b)
            if a.votes ~= b.votes then return a.votes > b.votes end
            return a.name < b.name
        end)
        table.insert(s.sessions, sess)
    end
    -- Persisted history = exactly what the /gm history window lists.
    s.history = {}
    for _, e in ipairs(db.history or {}) do
        local cands = {}
        for _, c in ipairs(e.candidates or {}) do
            table.insert(cands, {
                name = c.name, class = c.class or "?",
                response = respLabel(c.response_code or c.response),
                votes = c.votes or 0, voters = c.voters or {},
            })
        end
        table.insert(s.history, {
            id = e.id, date = e.date or "?", time = e.time_str or "",
            instance = e.instance or "?", item = e.item or "?",
            itemId = e.item_id or 0, ilvl = e.item_ilvl or 0,
            difficulty = e.difficulty_name or "", boss = e.boss or "",
            awarded = e.awarded_to or "", candidates = cands,
        })
    end
    return s
end
Sim.webState = state

-- ---- action dispatch (primitive args from JS) ----
local function resetAll()
    RCLootCouncil_GuildMasteryDB = { history = {}, version = 1 }
    Sim.ml.running = false; Sim.ml.isHistoricalLoad = false; Sim.ml.lootTable = {}
    Sim.vf.__lt = {}; Sim.reloadRequested = false
    Sim.timers = {}
end

-- The GuildMastery badge + RC hooks are installed by TryHookRC, which only runs
-- on PLAYER_LOGIN. If the user starts a session before clicking "Login", the
-- badge is missing and Save & Reload fails. Self-heal: install the hooks on
-- demand so the order of clicks no longer matters.
local function ensureHooked()
    local f = Sim.vf and Sim.vf:GetFrame()
    if not (f and f.gmSaveBtn) then Sim.login() end
end

local Actions = {}
function Actions.state()        end   -- no-op: just returns the current snapshot
function Actions.reset()        resetAll(); Sim.login() end   -- re-install hooks after reset
function Actions.enterRaid(d)   Sim.enterRaid(d or "Mythic"); ensureHooked() end
function Actions.login()        Sim.login() end
function Actions.relog()        Sim.relog() end
function Actions.advance(sec)   Sim.advance(tonumber(sec) or 60) end
function Actions.badgeReload()  ensureHooked(); Sim.clickBadgeReload() end
function Actions.testrestore()  SlashCmdList["GUILDMASTERY"]("testrestore") end
function Actions.history()      SlashCmdList["GUILDMASTERY"]("history") end

function Actions.addItem(id)
    if not Sim.group or #Sim.group == 0 then Sim.enterRaid("Mythic") end
    ensureHooked()
    Sim.addLootItem(id)
end

function Actions.startDemo()
    if not Sim.group or #Sim.group == 0 then Sim.enterRaid("Mythic") end
    ensureHooked()
    Sim.startSession({
        { loot = Sim.loot[1], boss = Sim.raid.bosses[1] },
        { loot = Sim.loot[2], boss = Sim.raid.bosses[2] },
    })
end

function Actions.setResponse(session, name, code)
    Sim.setResponse(tonumber(session), name, tonumber(code) or code, 640, 5)
    Sim.advance(2)   -- let the response hook settle
end

function Actions.vote(voter, session, name)
    Sim.castVote(voter, tonumber(session), name)
    Sim.advance(3)   -- let the HandleVote hook settle
end

function Actions.populate(session)
    Sim.populateContestedItem(tonumber(session) or 1)
    Sim.advance(3)
end

function Actions.award(session, winner)
    session = tonumber(session)
    local lt = Sim.vf:GetLootTable()
    if lt[session] then lt[session].awarded = winner end
    Sim.ml:Award(session, winner)   -- fires GM's Award hook -> AutoSaveFromRC
    Sim.advance(1)
end

-- Close the voting frame the way it closes in-game when a session ends: archive
-- the live session into GM history FIRST (so it can be reopened later from
-- /gm history), then empty the frame. History is kept.
function Actions.endSession()
    local lt = Sim.vf:GetLootTable()
    if Sim.ml.running and not Sim.ml.isHistoricalLoad and lt and #lt > 0 then
        SlashCmdList["GUILDMASTERY"]("export_active")   -- captures + saves to history
    end
    Sim.ml.running = false
    Sim.ml.isHistoricalLoad = false
    Sim.vf.__lt = {}
    print("[sim] Voting frame closed. Session archived to /gm history - reopen it with 'Charger cette session'.")
end

-- Replays the /gm history "restore" (green refresh) button for one date:
-- re-inject that date's UNAWARDED items into the voting frame.
function Actions.loadDate(date)
    local db = RCLootCouncil_GuildMasteryDB or {}
    local items = {}
    for _, e in ipairs(db.history or {}) do
        if e.date == date and e.item_link_raw and e.item_link_raw ~= ""
           and (not e.awarded_to or e.awarded_to == "") then
            table.insert(items, e)
        end
    end
    if #items == 0 then
        if #(db.history or {}) == 0 then
            print("[history] history is empty (Reset clears it) - nothing to restore.")
        else
            print("[history] no unawarded item to restore for " .. tostring(date) .. " (already awarded, or wrong date).")
        end
        return
    end
    -- Real button restores when no session is active; end any live one first.
    Sim.ml.running = false; Sim.vf.__lt = {}
    GMLootHistory:InjectItemsIntoVF(items)
end

function Actions.scenario(name)
    Sim.pass, Sim.fail = 0, 0
    local fn = Sim.Scenarios and Sim.Scenarios[name]
    if not fn then print("Unknown scenario: " .. tostring(name)); return end
    local ok, err = pcall(fn)
    if not ok then print("[ERROR] " .. tostring(err)) end
    print(string.format("==== %s: %d passed, %d failed ====", name, Sim.pass, Sim.fail))
end

-- ---- SavedVariables serializer -------------------------------------------
-- Emits valid Lua matching the shape WoW writes to
-- WTF/Account/<acct>/SavedVariables/RCLootCouncil_GuildMastery.lua
local function sv_key(k)
    if type(k) == "number" then return "[" .. k .. "]" end
    return '["' .. tostring(k):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"]'
end
local function sv_val(v, indent)
    local tv = type(v)
    if tv == "string" then return '"' .. v:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
    elseif tv == "number" or tv == "boolean" then return tostring(v)
    elseif tv == "table" then
        local pad, pad2 = string.rep("\t", indent), string.rep("\t", indent + 1)
        local isArr, n = isArray(v)
        local parts = {}
        if isArr then
            for i = 1, n do parts[#parts + 1] = pad2 .. sv_val(v[i], indent + 1) .. "," end
        else
            -- stable key order for readable diffs
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = k end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, k in ipairs(keys) do
                parts[#parts + 1] = pad2 .. sv_key(k) .. " = " .. sv_val(v[k], indent + 1) .. ","
            end
        end
        if #parts == 0 then return "{}" end
        return "{\n" .. table.concat(parts, "\n") .. "\n" .. pad .. "}"
    end
    return "nil"
end

function WebAPI_savedvars()
    local db = RCLootCouncil_GuildMasteryDB or {}
    return "\n-- Generated by sim/ (mock WoW SavedVariables dump)\n"
        .. "RCLootCouncil_GuildMasteryDB = " .. sv_val(db, 0) .. "\n"
end

function WebAPI_dispatch(action, a1, a2, a3)
    Sim.drainLog()   -- clear stale lines; capture only this action's output
    local fn = Actions[action]
    local ok, err = true, nil
    if fn then ok, err = pcall(fn, a1, a2, a3)
    else print("Unknown action: " .. tostring(action)) end
    if not ok then print("[action error] " .. tostring(err)) end
    return encode({ ok = ok and true or false, log = Sim.drainLog(), state = state() })
end
