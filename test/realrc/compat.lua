-- ============================================================
-- compat.lua — Lua 5.1 shims so the real RCLootCouncil + Ace libs (written for
-- WoW's Lua 5.1) load under Fengari (Lua 5.4).
-- ============================================================

-- unpack / loadstring moved/renamed in 5.2+
unpack = unpack or table.unpack
loadstring = loadstring or load
if not table.getn then table.getn = function(t) return #t end end
if not math.mod then math.mod = math.fmod end
string.gfind = string.gfind or string.gmatch

-- setfenv / getfenv were removed in 5.2. Polyfill via the debug library by
-- swapping the function's _ENV upvalue. Numeric levels (setfenv(1, env)) are
-- treated as best-effort no-ops (the media/dialog libs that use them are not
-- critical to the loot/vote logic under test).
local function envlookup(fn)
    local i = 1
    while true do
        local n = debug.getupvalue(fn, i)
        if not n then return nil end
        if n == "_ENV" then return i end
        i = i + 1
    end
end
function setfenv(fn, env)
    if type(fn) ~= "function" then return end   -- numeric level: skip
    local idx = envlookup(fn)
    if idx then debug.upvaluejoin(fn, idx, function() return env end, 1) end
    return fn
end
function getfenv(fn)
    if type(fn) ~= "function" then return _G end
    local idx = envlookup(fn)
    if idx then return select(2, debug.getupvalue(fn, idx)) end
    return _G
end

-- 5.1 `module()` — Ace uses it in one spot; make it a harmless no-op.
function module() end

-- gsub 5.1 compat: in Lua 5.1 a `%1` in the replacement with NO capture group
-- meant "the whole match"; 5.4 errors ("invalid use of '%' in replacement
-- string"). RC's roll-pattern parsing relies on the 5.1 behaviour. On failure,
-- retry with %1..%9 rewritten to %0 (the whole match).
local rawgsub = string.gsub
-- Sanitize a replacement string that WoW's 5.1 tolerated but 5.4 rejects:
-- keep %% and %0-%9, but strip the % before any other char (RC uses %(, %., %+
-- etc. in replacements to build patterns). A FUNCTION replacement is used so
-- the sanitizer itself never trips the same 5.4 check.
local function sanitize(repl)
    return (rawgsub(repl, "%%(.)", function(c)
        if c == "%" or c:match("%d") then return "%" .. c end
        return c
    end))
end
string.gsub = function(s, pat, repl, n)
    if type(repl) == "string" then
        local ok, a, b = pcall(rawgsub, s, pat, repl, n)
        if ok then return a, b end
        return rawgsub(s, pat, sanitize(repl), n)
    end
    return rawgsub(s, pat, repl, n)
end

-- Bitwise library (WoW exposes a `bit` table; used by LibSharedMedia etc.).
bit = bit or {
    band  = function(a, b, ...) local r = a & b; for _, v in ipairs({...}) do r = r & v end; return r end,
    bor   = function(a, b, ...) local r = a | b; for _, v in ipairs({...}) do r = r | v end; return r end,
    bxor  = function(a, b, ...) local r = a ~ b; for _, v in ipairs({...}) do r = r ~ v end; return r end,
    bnot  = function(a) return ~a end,
    lshift= function(a, n) return a << n end,
    rshift= function(a, n) return a >> n end,
    arshift = function(a, n) return a // (2 ^ n) end,
    mod   = function(a, b) return a % b end,
}
