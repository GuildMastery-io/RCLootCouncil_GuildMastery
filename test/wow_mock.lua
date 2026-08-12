-- ============================================================
-- wow_mock.lua — minimal World of Warcraft API surface used by
-- RCLootCouncil_GuildMastery (core.lua + History.lua).
--
-- Goals:
--   * Deterministic VIRTUAL CLOCK (Sim.clock) so the 5-min dedup window and
--     "long deliberation" cases are testable without real waiting.
--   * Deterministic TIMER SCHEDULER (C_Timer.After queues; Sim.advance runs).
--   * A permissive UI frame mock so the addon's ~1500 lines of frame code load
--     and run without us enumerating every widget method.
--   * Real behaviour only where the addon's LOGIC depends on it.
-- ============================================================

Sim = Sim or {}
Sim.clock  = Sim.clock  or 1723000000   -- base epoch (~2024); advanced by Sim.advance
Sim.timers = {}                          -- { {due=<epoch>, fn=<function>}, ... }
Sim.frames = {}                          -- CreateFrame'd frames (for event firing)

-- ---- print: strip WoW colour escapes so CLI output stays readable ----
-- Also mirrored into Sim.logBuffer so the web UI can show the addon's chat.
Sim.logBuffer = Sim.logBuffer or {}
local _rawprint = print
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local s = tostring(select(i, ...))
        s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
        parts[#parts + 1] = s
    end
    local line = table.concat(parts, "\t")
    _rawprint(line)
    Sim.logBuffer[#Sim.logBuffer + 1] = line
end
function Sim.drainLog()
    local out = Sim.logBuffer
    Sim.logBuffer = {}
    return out
end

-- ---- clock ----
function time()
    return math.floor(Sim.clock)
end
function date(fmt, t)
    -- os.date honours the "!" UTC prefix and "*t" table form used by the addon.
    return os.date(fmt, t or math.floor(Sim.clock))
end
function GetServerTime() return time() end
function GetTime() return Sim.clock end

-- Advance the virtual clock by `seconds` and fire any timers now due.
-- Returns the number of timers fired.
function Sim.advance(seconds)
    local target = Sim.clock + (seconds or 0)
    local fired = 0
    -- Fire due timers in chronological order, allowing new timers scheduled by
    -- callbacks to run within the same advance if they become due.
    while true do
        local nextIdx, nextDue = nil, nil
        for i, tm in ipairs(Sim.timers) do
            if tm.due <= target and (nextDue == nil or tm.due < nextDue) then
                nextIdx, nextDue = i, tm.due
            end
        end
        if not nextIdx then break end
        local tm = table.remove(Sim.timers, nextIdx)
        Sim.clock = math.max(Sim.clock, tm.due)
        local ok, err = pcall(tm.fn)
        if not ok then _rawprint("[timer error] " .. tostring(err)) end
        fired = fired + 1
    end
    Sim.clock = target
    return fired
end

C_Timer = {
    After = function(delay, fn)
        table.insert(Sim.timers, { due = Sim.clock + (delay or 0), fn = fn })
    end,
    NewTicker = function(_, fn) return { Cancel = function() end } end,
}

-- ---- hooksecurefunc: post-hook wrapper ----
function hooksecurefunc(a, b, c)
    local tbl, name, post
    if type(a) == "table" then tbl, name, post = a, b, c
    else tbl, name, post = _G, a, b end
    local orig = tbl[name]
    tbl[name] = function(...)
        local r = { orig and orig(...) }
        post(...)
        return table.unpack(r)
    end
end

-- ---- table helpers (WoW globals) ----
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
tremove = table.remove
function strtrim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function strsplit(sep, s)
    local out = {}
    for part in tostring(s):gmatch("([^" .. sep .. "]+)") do out[#out + 1] = part end
    return table.unpack(out)
end

-- ---- UI object ------------------------------------------------------------
-- Frames are plain tables: UNKNOWN fields read as nil (so `if f.gmSaveBtn then
-- return end` and the `f.content = f` fallback behave like real WoW), while the
-- widget METHODS the addon calls are provided as no-ops via a shared __index
-- method table. Methods that feed logic return realistic values.
local NOOP = function(self) return self end
local Methods = {}
local function noopReturningChild() return Sim.newObject() end

-- Bulk no-op setters / layout / misc methods used by the addon UI.
for _, name in ipairs({
    "SetPoint","SetAllPoints","ClearAllPoints","SetSize","SetWidth","SetHeight",
    "SetScale","SetAlpha","SetShown","SetFrameStrata","SetFrameLevel","Raise","Lower",
    "SetMovable","EnableMouse","SetClampedToScreen","RegisterForClicks","RegisterForDrag",
    "SetBackdrop","SetBackdropColor","SetBackdropBorderColor","SetColorTexture","SetTexture",
    "SetVertexColor","SetBlendMode","SetTexCoord","SetFontObject","SetJustifyH","SetJustifyV",
    "SetTextColor","SetWordWrap","SetMultiLine","SetMaxLetters","SetAutoFocus","SetFocus",
    "ClearFocus","HighlightText","SetHyperlink","SetOwner","AddLine","AddDoubleLine",
    "ClearLines","SetScrollChild","SetVerticalScroll","SetHorizontalScroll","SetFontString",
    "SetHighlightTexture","SetPushedTexture","SetNormalTexture","SetDisabledTexture",
    "SetHitRectInsets","StartMoving","StopMovingOrSizing","RegisterForMouse","SetText",
    "SetFont","SetPropagateKeyboardInput","SetToplevel","EnableKeyboard","SetResizable",
    "SetDrawLayer","SetParent","SetID","SetMinMaxValues","SetValue","SetObeyStepOnDrag",
    "SetStepsPerPage","SetValueStep","Enable","Disable","SetChecked","SetIndentedWordWrap",
}) do Methods[name] = NOOP end

-- Methods that must return something usable.
Methods.CreateFontString     = noopReturningChild
Methods.CreateTexture        = noopReturningChild
Methods.CreateAnimationGroup = noopReturningChild
Methods.GetHighlightTexture  = noopReturningChild
Methods.GetPushedTexture     = noopReturningChild
Methods.GetNormalTexture     = noopReturningChild
Methods.GetRegions           = noopReturningChild
Methods.GetHeight       = function() return 20 end
Methods.GetWidth        = function() return 100 end
Methods.GetFrameLevel   = function() return 1 end
Methods.GetVerticalScroll = function() return 0 end
Methods.GetVerticalScrollRange = function() return 0 end
Methods.GetName    = function(self) return self.__name end
Methods.GetParent  = function(self) return self.__parent end
Methods.GetText    = function(self) return self.__text end
Methods.SetText    = function(self, t) self.__text = t; return self end
Methods.IsShown    = function(self) return self.__shown ~= false end
Methods.IsVisible  = function(self) return self.__shown ~= false end
Methods.Show       = function(self) self.__shown = true; return self end
Methods.Hide       = function(self) self.__shown = false; return self end
Methods.SetScript       = function(self, ev, fn) self.__scripts[ev] = fn; return self end
Methods.GetScript       = function(self, ev) return self.__scripts[ev] end
Methods.HookScript      = function(self, ev, fn) self.__scripts[ev] = fn; return self end
Methods.RegisterEvent   = function(self, ev) self.__events[ev] = true; return self end
Methods.UnregisterEvent = function(self, ev) self.__events[ev] = nil; return self end

-- __index heuristic: a defined method wins; otherwise an UNKNOWN PascalCase key
-- (WoW widget methods are PascalCase: SetPoint, GetName…) becomes a no-op that
-- returns self (safe for setter chains); a lowercase key (addon data fields
-- like gmSaveBtn, content, editBox) reads as nil, like a real unset field.
local genericMethod = function(self) return self end   -- setter-like: chainable
local genericGetter = function() return nil end        -- getter-like: nil (so `x or default` works)
local FrameMT = {
    __index = function(_, k)
        local m = Methods[k]
        if m ~= nil then return m end
        if type(k) == "string" and k:match("^%u") then
            -- Getters return nil (safe in `NumLines() or 0`, guarded indexing);
            -- everything else (setters) returns self for chaining.
            if k:match("^Get") or k:match("^Num") or k:match("^Is") or k:match("^Has") or k:match("^Can") then
                return genericGetter
            end
            return genericMethod
        end
        return nil
    end,
    __concat = function(a, b)
        local function s(x) return type(x) == "string" and x or (type(x) == "number" and tostring(x) or "") end
        return s(a) .. s(b)
    end,
    __tostring = function() return "<frame>" end,
}

function Sim.newObject(kind)
    return setmetatable({ __sim = true, __kind = kind, __scripts = {}, __events = {} }, FrameMT)
end

function CreateFrame(frameType, name, parent, template)
    local f = Sim.newObject("frame")
    f.__name, f.__parent, f.__frameType = name, parent, frameType
    if name then _G[name] = f end
    table.insert(Sim.frames, f)
    return f
end

-- Fire a WoW event to every frame registered for it (drives OnEvent handlers).
function Sim.fireEvent(event, ...)
    for _, f in ipairs(Sim.frames) do
        if f.__events[event] and f.__scripts.OnEvent then
            local ok, err = pcall(f.__scripts.OnEvent, f, event, ...)
            if not ok then _rawprint("[event error] " .. event .. ": " .. tostring(err)) end
        end
    end
end

-- ---- StaticPopup: auto-accept so save+reload flows complete headless ----
StaticPopupDialogs = {}
function StaticPopup_Show(key)
    local d = StaticPopupDialogs[key]
    if d and d.OnAccept then d.OnAccept() end
    return Sim.newObject("popup")
end

-- ---- ReloadUI: does NOT reload (we simulate relog via Sim.relog) ----
Sim.reloadRequested = false
function ReloadUI() Sim.reloadRequested = true end

-- ---- misc globals ----
UIParent   = Sim.newObject("frame")
GameTooltip = Sim.newObject("frame")
GameTooltip.SetOwner   = function() end
GameTooltip.AddLine    = function() end
GameTooltip.AddDoubleLine = function() end
GameTooltip.SetHyperlink  = function() end
GameTooltip.ClearLines = function() end

RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 0.8, g = 0.8, b = 0.8 } end })

function GetRealZoneText() return Sim.zone or "Liberation of Undermine" end
function GetInstanceInfo()
    -- name, type, difficultyID, difficultyName, ...
    return (Sim.zone or "Liberation of Undermine"), "raid",
           (Sim.difficultyID or 16), (Sim.difficultyName or "Mythic"),
           30, 0, false, 1273, 8
end

-- Item cache: link -> {name, ilvl, texture}. Sim.registerItem populates it.
Sim.items = {}
function Sim.registerItem(id, name, ilvl)
    local link = "|cffa335ee|Hitem:" .. id .. "::::::::80:0::::::|h[" .. name .. "]|h|r"
    Sim.items[link] = { id = id, name = name, ilvl = ilvl or 639, texture = 134400 }
    Sim.items[tostring(id)] = Sim.items[link]
    return link
end
function GetItemInfo(link)
    local it = link and Sim.items[link]
    if not it then
        -- Unknown but well-formed link: still return a usable tuple.
        local nm = tostring(link):match("%[(.-)%]") or "Unknown Item"
        return nm, link, 4, 639, 80, "", "", 1, "INVTYPE_HEAD", 134400, 0
    end
    -- name, link, quality, ilvl, reqLevel, class, subclass, stackCount, equipLoc, texture, sellPrice
    return it.name, link, 4, it.ilvl, 80, "Armor", "Cloth", 1, "INVTYPE_HEAD", it.texture, 0
end
function GetItemInfoInstant(link)
    local it = link and Sim.items[link]
    local id = it and it.id or tonumber(tostring(link):match("item:(%d+)")) or 0
    return id, "INVTYPE_HEAD", "Armor", "Cloth", it and it.texture or 134400
end
C_Item = {
    RequestLoadItemDataByID = function() end,
    DoesItemExistByID       = function() return true end,
    GetItemInfoInstant      = GetItemInfoInstant,
}

function GetAddOnMetadata() return nil end

-- Slash command registry (WoW global).
SlashCmdList = {}

-- Frames closable with Escape (WoW global list).
UISpecialFrames = {}
