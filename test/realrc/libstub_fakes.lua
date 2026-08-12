-- ============================================================
-- libstub_fakes.lua — register permissive stand-ins for the pure-UI libraries
-- the loader skips (they need XML frame templates we don't build). Loaded right
-- after LibStub.lua, so RC's `LibStub("AceGUI-3.0")` etc. resolve to an inert
-- object instead of erroring. GM's loot/vote/reload logic never touches these.
-- ============================================================

local FAKE_LIBS = {
    "AceConfig-3.0", "AceConfigRegistry-3.0", "AceConfigCmd-3.0", "AceConfigDialog-3.0",
    "AceGUI-3.0", "AceDBOptions-3.0", "MSA-DropDownMenu-1.0", "ScrollingTable",
    "LibDialog-1.0", "LibDialog-1.1",
}

-- Every method/field access on a fake lib returns the inert safe value P()
-- (callable, indexable, arithmetic/compare-safe) from wow_full.lua.
local mt = {
    __index = function() return function() return Sim.P() end end,
    __call  = function() return Sim.P() end,
}

for _, name in ipairs(FAKE_LIBS) do
    local lib = LibStub:NewLibrary(name, 99999)
    if not lib then lib = LibStub:GetLibrary(name, true) end
    if lib then setmetatable(lib, mt) end
end
