-- ============================================================
-- wow_full.lua — extends wow_mock.lua with a much wider WoW API surface for
-- loading the REAL RCLootCouncil, plus a permissive _G fallback for the long
-- tail of C_* APIs. Loaded AFTER wow_mock.lua.
-- ============================================================

-- ---- universal permissive value -------------------------------------------
-- Callable, indexable, assignable, concat-safe. Used for unknown globals and
-- their children so RC's load-time feature probing doesn't hard-crash.
-- A fully metamethod-complete "safe value": callable, indexable, assignable,
-- and inert in arithmetic (→0), comparison (→false), length (→0) and concat
-- (→string). Used for unknown globals + their children so RC's UI libs that
-- reach XML-defined frame children (which we don't build) never hard-crash.
local PMT
local function P()
    return setmetatable({}, PMT)
end
local function sconcat(a, b)
    local function s(x) return type(x) == "string" and x or (type(x) == "number" and tostring(x) or "") end
    return s(a) .. s(b)
end
PMT = {
    __index    = function() return P() end,
    __call     = function() return P() end,
    __newindex = function() end,
    __concat   = sconcat,
    __tostring = function() return "" end,
    __len      = function() return 0 end,
    __eq       = function() return false end,
    __lt       = function() return false end,
    __le       = function() return false end,
    __add = function() return 0 end, __sub = function() return 0 end,
    __mul = function() return 0 end, __div = function() return 0 end,
    __mod = function() return 0 end, __pow = function() return 0 end,
    __unm = function() return 0 end,
}
Sim.P = P

-- ---- concrete constants RC branches on ----
WOW_PROJECT_ID = 1
WOW_PROJECT_MAINLINE = 1
WOW_PROJECT_CLASSIC = 2
WOW_PROJECT_WRATH_CLASSIC = 11
WOW_PROJECT_CATACLYSM_CLASSIC = 14
LE_EXPANSION_LEVEL_CURRENT = 10
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
HIGHLIGHT_FONT_COLOR = { r = 1, g = 1, b = 1 }
RED_FONT_COLOR = { r = 1, g = 0.1, b = 0.1 }
ITEM_QUALITY_COLORS = setmetatable({}, { __index = function() return { hex = "|cffffffff", r = 1, g = 1, b = 1 } end })
LE_ITEM_QUALITY_EPIC = 4
MAX_RAID_MEMBERS = 40
NUM_LE_ITEM_QUALITYS = 8
Enum = setmetatable({}, { __index = function() return setmetatable({}, { __index = function() return 0 end }) end })
Constants = setmetatable({}, { __index = function() return P() end })

-- ---- data-returning functions (must give real strings/numbers) ----
local ME = "Ged-Uldaman"
function UnitName(u) if u == "player" then return "Ged", "Uldaman" end return "Ged", "Uldaman" end
function UnitFullName(u) return "Ged", "Uldaman" end
function GetUnitName() return ME end
function UnitClass() return "Paladin", "PALADIN", 2 end
function UnitClassBase() return "PALADIN", 2 end
function UnitRace() return "Human", "Human", 1 end
function UnitGUID() return "Player-1234-00000001" end
function UnitLevel() return 80 end
function UnitExists() return true end
function UnitIsUnit(a, b) return a == b end
function UnitIsGroupLeader() return true end
function UnitInParty() return false end
function UnitInRaid() return 1 end
function UnitFactionGroup() return "Alliance", "Alliance" end
function UnitSex() return 2 end
function GetRealmName() return "Uldaman" end
function GetNormalizedRealmName() return "Uldaman" end
function GetPlayerInfoByGUID() return "Human", "Warrior", "WARRIOR", "Alliance", 2, "Ashkandi", "Uldaman" end
function IsInRaid() return true end
function IsInGroup() return true end
function IsInInstance() return true, "raid" end
function GetNumGroupMembers() return #(Sim.group or {}) end
function GetNumSubgroupMembers() return 0 end
function GetLootMethod() return "master", 0, 0 end
function GetRaidRosterInfo(i)
    local name = (Sim.group or {})[i]
    if not name then return nil end
    return name:match("^[^-]+"), 0, 1, 80, "Paladin", "PALADIN", "Uldaman", true, false, "NONE", false, "DAMAGER"
end
function GetInstanceInfo2() return GetInstanceInfo() end
function GetDifficultyInfo(id) return (Sim.difficultyName or "Mythic"), "raid" end
function GetTime2() return Sim.clock end
function GetFramerate() return 60 end
function GetLocale() return "enUS" end
function GetBuildInfo() return "12.1.0", "69273", nil, 120100 end
function GetAddOnMetadata(_, key)
    if key == "Version" then return "3.23.0" end
    return nil
end
function IsAddOnLoaded() return true, true end
function GetNumAddOns() return 1 end
function GetRealZoneText2() return Sim.zone or "?" end
function GetDetailedItemLevelInfo(link) local it = Sim.items and Sim.items[link]; return it and it.ilvl or 639 end
function GetContainerNumSlots() return 0 end
function debugprofilestop() return math.floor(Sim.clock * 1000) end
function ReloadUI2() end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function InCombatLockdown() return false end
function GetCVar() return "0" end
function GetCVarBool() return false end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a, GetRGBA = function() return r, g, b, a end, GenerateHexColor = function() return "ffffffff" end } end
function CreateColorFromHexString() return CreateColor(1, 1, 1, 1) end
function ColorMixin() return {} end
function Mixin(t) return t or {} end
function CreateFromMixins() return {} end
function CreateAndInitFromMixin() return {} end
function format(...) return string.format(...) end
strjoin = function(sep, ...) return table.concat({ ... }, sep) end
strsplit = strsplit
function strconcat(...) return table.concat({ ... }) end
function tContains(t, v) for _, x in ipairs(t or {}) do if x == v then return true end end return false end
function tDeleteItem(t, v) for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) end end end
function tIndexOf(t, v) for i, x in ipairs(t or {}) do if x == v then return i end end end
function tInvert(t) local o = {} for k, v in pairs(t or {}) do o[v] = k end return o end
function CopyTable(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = (type(v) == "table") and CopyTable(v) or v end
    return o
end
function Round(n) return math.floor((n or 0) + 0.5) end
function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function SecondsToTime(s) return tostring(s) .. "s" end
function date2() end
function debugstack() return "" end
function geterrorhandler() return function(e) print("[lua error] " .. tostring(e)) end end
function seterrorhandler() end
function securecall(f, ...) if type(f) == "function" then return f(...) end end
function issecurevariable() return false end
function IsLoggedIn() return true end
function After() end
function C_CreateFromMixins() return {} end
function getglobal(n) return rawget(_G, n) end
function setglobal(n, v) rawset(_G, n, v) end

-- WoW string.* / math.* global aliases.
strmatch = string.match; strfind = string.find; strsub = string.sub
strlen = string.len; strlower = string.lower; strupper = string.upper
strrep = string.rep; strbyte = string.byte; strchar = string.char
gmatch = string.gmatch; gsub = string.gsub
ceil = math.ceil; floor = math.floor; abs = math.abs
min = math.min; max = math.max; sqrt = math.sqrt; mod = math.fmod; random = math.random
function issecretvalue() return false end
function issecurevariable() return false, nil end
function tFilter(tbl, pred, isArray)
    local out = {}
    if isArray then
        for _, v in ipairs(tbl) do if pred(v) then out[#out + 1] = v end end
    else
        for k, v in pairs(tbl) do if pred(v) then out[k] = v end end
    end
    return out
end
MSA_DropDownMenu_Create = function() return Sim.newObject("dropdown") end
function Ambiguate(name) return (tostring(name):gsub("%-.+$", "")) end
function GetNumClasses() return 13 end
local CLASS_FILES = { "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","DEATHKNIGHT","SHAMAN",
                      "MAGE","WARLOCK","MONK","DRUID","DEMONHUNTER","EVOKER" }
C_CreatureInfo = setmetatable({
    GetClassInfo = function(i)
        local f = CLASS_FILES[i]
        if not f then return nil end
        return { classID = i, className = f:sub(1,1) .. f:sub(2):lower(), classFile = f }
    end,
    GetRaceInfo = function() return { raceID = 1, raceName = "Human", clientFileString = "Human" } end,
    GetFactionInfo = function() return { groupTag = "Alliance", name = "Alliance" } end,
}, { __index = function() return function() return P() end end })
function GetClassInfo(i) return C_CreatureInfo.GetClassInfo(i) end
function IsGuildMember() return true end
function IsInGuildGroup() return false end
function CanEditOfficerNote() return true end
function GetGuildRosterInfo() return "Ged", "Guild Master", 0, 80, "Paladin", "Uldaman", "", "", true, 0, "PALADIN" end
function GetNumGuildMembers() return 1 end
function ChatFrame_AddMessageEventFilter() end
function ChatFrame_RemoveMessageEventFilter() end
function ChatEdit_GetActiveWindow() return nil end
function ChatEdit_ChooseBoxForSend() return DEFAULT_CHAT_FRAME end
function RegisterNewSlashCommand() end
function hooksecurefunc_orig() end
function GetChatWindowInfo() return "General" end
function FCF_GetCurrentChatFrame() return DEFAULT_CHAT_FRAME end
function SetCVar() end
function RegisterCVar() end
function C_TimerAfter() end
function BNConnected() return false end
function IsTrialAccount() return false end
function IsVeteranTrialAccount() return false end
function GetMaxLevelForExpansionLevel() return 80 end
function UnitPosition() return 0, 0, 0, 0 end
function GetBestMapForUnit() return 0 end
function SetPortraitTexture() end
function SetPortraitToTexture() end
function GetItemIcon() return 134400 end
function GetItemQualityColor() return 0.6, 0.4, 0.9, "ffa335ee" end
function GetItemStatDelta() return {} end
function IsEquippableItem() return true end
function IsArtifactRelicItem() return false end
function PlayerHasToy() return false end
function C_ToyBoxGetToyInfo() return nil end

-- MSA-DropDownMenu global functions (the lib file is stubbed; RC calls these
-- globals to build its right-click menus, which GM doesn't need).
MSA_DropDownMenu_CreateInfo   = function() return {} end
MSA_DropDownMenu_AddButton    = function() end
MSA_DropDownMenu_AddSeparator = function() end
MSA_ToggleDropDownMenu        = function() end
MSA_HideDropDownMenu          = function() end
MSA_CloseDropDownMenus        = function() end
MSA_DropDownMenu_Initialize   = function() end
MSA_DropDownMenu_SetWidth     = function() end
MSA_DropDownMenu_SetText      = function() end
MSA_DropDownMenu_SetSelectedValue = function() end
MSA_DropDownMenu_GetSelectedValue = function() end
MSA_DropDownMenu_SetAnchor    = function() end
MSA_UIDropDownMenu_CreateInfo = function() return {} end
EasyMenu                      = function() end
-- Blizzard UIDropDownMenu equivalents (some code paths use these directly).
UIDropDownMenu_CreateInfo     = function() return {} end
UIDropDownMenu_AddButton      = function() end
ToggleDropDownMenu            = function() end
CloseDropDownMenus            = function() end
function GetCurrentRegion() return 3 end          -- EU
function GetCurrentRegionName() return "EU" end
function GetExpansionLevel() return 10 end
function GetServerExpansionLevel() return 10 end
function GetAccountExpansionLevel() return 10 end
function PlaySound() end
function PlaySoundFile() end
function StopSound() end
function GetSpellInfo(id) return "Spell", nil, 134400, 0, 0, 0, id end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 70, "Retribution", "desc", 134400, "DAMAGER", "STR" end
function GetSpecializationInfoByID() return 70, "Retribution", "desc", 134400, "DAMAGER", "Paladin", "PALADIN" end
function GetInspectSpecialization() return 70 end
function GetNumSpecializations() return 4 end
function UnitGroupRolesAssigned() return "DAMAGER" end
function GetGuildInfo() return "GuildMastery", "Member", 0 end
function IsInGuild() return true end
function GetTime3() return Sim.clock end
function GetNetStats() return 0, 0, 30, 30 end
function RequestTimePlayed() end
function GetQuestResetTime() return 86400 end
function GetXPExhaustion() return 0 end
function SendChatMessage() end
function SendAddonMessage() end
function RegisterAddonMessagePrefix() return true end
function IsEncounterInProgress() return false end
function GetInstanceLockTimeRemaining() return 0 end
function EJ_GetEncounterInfo() return "Boss" end
function EJ_GetInstanceInfo() return "Instance" end
function EJ_GetNumTiers() return 0 end
function EJ_SelectTier() end
function EJ_GetCurrentTier() return 1 end
function EJ_SelectInstance() end
function EJ_GetInstanceByIndex() return nil end
function EJ_GetEncounterInfoByIndex() return nil end
function EJ_GetCreatureInfo() return nil end
function EJ_GetLootInfoByIndex() return nil end
function EJ_SetLootFilter() end
function EJ_GetNumLoot() return 0 end
function EJ_SetDifficulty() end
function EJ_GetTierInfo() return "Tier" end
function UnitAffectingCombat() return false end
function GetMouseFocus() return nil end
function GetCursorPosition() return 0, 0 end
function GetScreenWidth() return 1920 end
function GetScreenHeight() return 1080 end
function GetPhysicalScreenSize() return 1920, 1080 end
function UIParent_OnEvent() end
function InterfaceOptions_AddCategory() end
function Settings() end
function CreateAtlasMarkup() return "" end
function GetAtlasInfo() return nil end
function C_GetClassColor() return 0.8, 0.8, 0.8 end
function BNGetInfo() return nil end
function GetBattlefieldStatus() return "none" end

-- Common C_* namespaces as permissive tables (real methods no-op / return P()).
for _, ns in ipairs({
    "C_AddOns","C_ChatInfo","C_Container","C_CVar","C_EncounterJournal","C_MythicPlus",
    "C_PartyInfo","C_LootHistory","C_Map","C_UnitAuras","C_Timer","C_Item","C_ClassColor",
    "C_SpecializationInfo","C_PlayerInfo","C_GuildInfo","C_FriendList","C_Texture","C_TradeInfo",
    "C_ScrollingMessageFrame","C_Social","C_TooltipInfo","C_Spell","C_Reputation","C_DateAndTime",
    "C_Widget","C_UIWidgetManager","C_Loot","C_Bank","C_Traits","C_Engraving","C_WowTokenPublic",
}) do
    if _G[ns] == nil then _G[ns] = setmetatable({}, { __index = function() return function() return P() end end }) end
end
-- Keep our concrete C_Timer / C_Item from wow_mock.lua.
C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
C_ClassColor.GetClassColor = function() return CreateColor(0.8, 0.8, 0.8, 1) end
C_AddOns.GetAddOnMetadata = function(_, key) return GetAddOnMetadata(_, key) end
C_AddOns.IsAddOnLoaded = function() return true end
C_Item.GetItemInfo = GetItemInfo

function GetClassColor(cls)
    return 0.8, 0.8, 0.8, "ffcccccc"
end
RAID_CLASS_COLORS = setmetatable({}, { __index = function()
    return { r = 0.8, g = 0.8, b = 0.8, colorStr = "ffcccccc", GetRGB = function() return 0.8, 0.8, 0.8 end }
end })
CLASS_ICON_TCOORDS = setmetatable({}, { __index = function() return { 0, 0.25, 0, 0.25 } end })
LOCALIZED_CLASS_NAMES_MALE = setmetatable({}, { __index = function(_, k) return k end })
LOCALIZED_CLASS_NAMES_FEMALE = setmetatable({}, { __index = function(_, k) return k end })

-- UI constant tables various libs index into.
TOOLTIP_DEFAULT_BACKGROUND_COLOR = { r = 0.09, g = 0.09, b = 0.19 }
TOOLTIP_DEFAULT_COLOR = { r = 1, g = 1, b = 1 }
FACTION_BAR_COLORS = setmetatable({}, { __index = function() return { r = 0.5, g = 0.5, b = 0.5 } end })
PLAYER_FACTION_GROUP = setmetatable({}, { __index = function() return "Alliance" end })
DEFAULT_CHAT_FRAME = setmetatable({ AddMessage = function() end }, { __index = function() return function() end end })
GameFontNormal = Sim.newObject("font")
GameFontHighlight = Sim.newObject("font")
GameFontNormalSmall = Sim.newObject("font")
GameFontHighlightSmall = Sim.newObject("font")
GameFontDisable = Sim.newObject("font")
NumberFontNormal = Sim.newObject("font")
ChatFontNormal = Sim.newObject("font")
UIParent = UIParent or Sim.newObject("frame")
WorldFrame = Sim.newObject("frame")
UISpecialFrames = UISpecialFrames or {}
UIDropDownMenu_GetCurrentDropDown = function() end
BackdropTemplateMixin = {}
SOUNDKIT = setmetatable({}, { __index = function() return 0 end })
-- WoW global string constants RC parses/patterns against.
RANDOM_ROLL_PATTERN = "%s rolls %d (%d-%d)"
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
LOOT_ROLL_YOU_WON = "You won: %s"
ERR_LOOT_GONE = "Loot gone"
ITEM_LEVEL = "Item Level %d"
ITEM_LEVEL_ABBR = "iLvl"
ROLL_DISENCHANT = "Disenchant"
NEED = "Need"
GREED = "Greed"
PASS = "Pass"
LOOT = "Loot"
UNKNOWN = "Unknown"
ALL = "All"
NONE = "None"
CLOSE = "Close"
CANCEL = "Cancel"
ACCEPT = "Accept"
YES = "Yes"
NO = "No"
OKAY = "Okay"
DELETE = "Delete"
GUILD = "Guild"
FRIENDS = "Friends"
PLAYER = "Player"
TARGET = "Target"
REQUEST_ROLL = "Request Roll"
ROLL = "Roll"
MAINSPEC_TOOLTIP = "Main Spec"
OFFSPEC_TOOLTIP = "Off Spec"
VOTE = "Vote"
ROLLS = "Rolls"
DISENCHANT = "Disenchant"
CLASS = "Class"
NAME = "Name"
RANK = "Rank"
LEVEL = "Level"
ITEMS = "Items"
REMOVE = "Remove"
ENABLE = "Enable"
DISABLE = "Disable"
DONE = "Done"
CONTINUE = "Continue"
RANDOM_ROLL = "Random Roll"
MASTER_LOOTER = "Master Looter"
RAID = "Raid"
PARTY = "Party"
INSTANCE = "Instance"
COMBATLOG = "Combat Log"
REFRESH = "Refresh"
-- Item stat short labels (Utils/EncounterJournalData indexes many of these).
for _, k in ipairs({
    "AGILITY", "STRENGTH", "INTELLECT", "STAMINA", "SPIRIT", "VERSATILITY",
    "CRIT_RATING", "HASTE_RATING", "MASTERY_RATING", "DODGE_RATING", "PARRY_RATING",
    "BLOCK_RATING", "ATTACK_POWER", "SPELL_POWER", "RESILIENCE_RATING", "HIT_RATING",
    "EXPERTISE_RATING", "PVP_POWER", "EXTRA_ARMOR", "AGI_STR_INT", "AGI", "STR", "INT",
    "CR_LIFESTEAL", "CR_SPEED", "CR_AVOIDANCE", "CORRUPTION", "CORRUPTION_RESISTANCE",
}) do
    _G["ITEM_MOD_" .. k .. "_SHORT"] = k:gsub("_", " ")
    _G["ITEM_MOD_" .. k] = k:gsub("_", " ")
end
ITEM_MOD_AGILITY_SHORT = "Agility"
ITEM_MOD_STRENGTH_SHORT = "Strength"
ITEM_MOD_INTELLECT_SHORT = "Intellect"
STAT_AVERAGE_ITEM_LEVEL = "Item Level"
DAMAGER = "Damage"
HEALER = "Healer"
TANK = "Tank"
MELEE = "Melee"
RANGED = "Ranged"
ROLE = "Role"
SPEC = "Specialization"
DAMAGE = "Damage"
HEALING = "Healing"
Enum.ItemQuality = setmetatable({ Epic = 4, Rare = 3, Uncommon = 2, Common = 1, Poor = 0, Legendary = 5 }, { __index = function() return 0 end })

-- ---- fallback: unknown globals read as nil (real WoW semantics), logged.
-- CRITICAL: this must be nil, not P(). Libraries bootstrap with
--   local Lib = _G[MAJOR]; if not Lib then ...define... end
-- A truthy P() there makes every Ace lib think it's already loaded and silently
-- become a no-op. nil lets them define themselves correctly. Crash sites from
-- genuinely-missing tables are handled by defining them concretely above (and
-- by stubbing the XML-template UI libs in libstub_fakes.lua).
-- ALL-CAPS keys are almost always WoW UI string constants (BLOCK, DAMAGER,
-- ITEM_MOD_*_SHORT, …). Returning the key as a string makes the many
-- `_G.SOME_CONSTANT .. "..."` concatenations work without enumerating them all.
-- Everything else stays nil so library bootstrap (`if not Lib then`) is correct.
Sim.missingGlobals = Sim.missingGlobals or {}
setmetatable(_G, {
    __index = function(_, k)
        if type(k) == "string" then
            Sim.missingGlobals[k] = (Sim.missingGlobals[k] or 0) + 1
            if k:match("^[A-Z][A-Z0-9_]*$") then return k end   -- UI string constant
        end
        return nil
    end,
})
