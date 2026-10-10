-- astra_hook_monitor.lua
-- tempel di executor SEBELUM load bootstrap Luarmor

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ts          = tostring

-- ============================================================
-- LOAD ASTRA UI
-- ============================================================
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/Ali-lov3/AstraUiLib/refs/heads/main/Source.lua"))()

local Window = Library.CreateWindow({
    Title        = "Nyx // Hook Monitor",
    Logo         = 0,
    Anonymous    = false,
    ConfigFolder = "NyxConfigs",
})

-- ============================================================
-- CONFIG
-- ============================================================
local CFG = {
    silent    = true,
    dump_min  = 40,
    dedup     = true,
    max_dumps = 200,
    max_log   = 500,
}

local dumped       = {}
local dumped_count = 0
local HOOK_TAG     = "[N-HOOK]"

local State = {
    log        = {},
    payloads   = {},
    selected   = nil,
    stats      = { http=0, get=0, load=0, char=0, concat=0, bxor=0, dump=0, env=0 },
    toggles    = {
        http=true, get=true, load=true, char=false, concat=true,
        bxor=false, sethook=true, upvalue=true, bytedump=true,
    },
    exec_count = 0,
}

-- ============================================================
-- TABS & SECTIONS
-- ============================================================
local MainTab     = Window:CreateTab({ Name = "Live Log",   Icon = "scroll-text" })
local PayloadTab  = Window:CreateTab({ Name = "Payloads",   Icon = "package" })
local StatsTab    = Window:CreateTab({ Name = "Stats",      Icon = "activity" })
local CfgTab      = Window:CreateTab({ Name = "Controls",   Icon = "settings" })

local MainSection    = MainTab:CreateSection({ Name = "hook stream",    Side = "Left" })
local PayloadSection = PayloadTab:CreateSection({ Name = "captured",    Side = "Left" })
local StatsSection   = StatsTab:CreateSection({ Name = "counters",     Side = "Left" })
local CtrlSection    = CfgTab:CreateSection({ Name = "hook toggles",   Side = "Left" })

-- ============================================================
-- UI ELEMENTS
-- ============================================================
local LogLabel = MainSection:AddLabel("waiting for hook events...")

MainSection:AddButton({
    Name = "clear log",
    Callback = function()
        State.log = {}
        Library.Notify({ Title = "Log", Text = "cleared", Icon = "check", Duration = 2 })
    end,
})
MainSection:AddButton({
    Name = "copy log to clipboard",
    Callback = function()
        if setclipboard then
            setclipboard(table.concat(State.log, "\n"))
            Library.Notify({ Title = "Log", Text = "copied", Icon = "check", Duration = 2 })
        end
    end,
})

local PayloadDropdown = PayloadSection:AddDropdown({
    Name    = "select payload",
    Options = {},
    Default = nil,
    Callback = function(selected)
        for _, p in ipairs(State.payloads) do
            if p.label == selected then
                State.selected = p
                Library.Notify({
                    Title = "Payload",
                    Text  = p.label .. "\n" .. p.preview:sub(1, 100),
                    Icon  = "package",
                    Duration = 4,
                })
                break
            end
        end
    end,
})

PayloadSection:AddButton({
    Name = "load selected payload",
    Callback = function()
        if not State.selected then
            Library.Notify({ Title = "Payload", Text = "none selected", Icon = "alert", Duration = 2 })
            return
        end
        local src = State.selected.source
        local chunk = (loadstring or load)(src, "@nyx_reload")
        if chunk then
            task.spawn(function()
                local ok, err = pcall(chunk)
                Library.Notify({
                    Title = "Reload",
                    Text  = ok and "ok" or ("err: " .. ts(err)),
                    Icon  = ok and "check" or "alert",
                    Duration = 3,
                })
            end)
        end
    end,
})
PayloadSection:AddButton({
    Name = "copy source to clipboard",
    Callback = function()
        if State.selected and setclipboard then
            setclipboard(State.selected.source)
            Library.Notify({ Title = "Payload", Text = "copied", Icon = "check", Duration = 2 })
        end
    end,
})

local StatsLabel = StatsSection:AddLabel("http: 0\nhttpget: 0\nload: 0\n...")

-- ---------- CONTROLS ----------
local function mkToggle(name, key)
    CtrlSection:AddToggle({
        Name    = name,
        Default = State.toggles[key],
        Callback = function(v) State.toggles[key] = v end,
    })
end
mkToggle("HTTP requests",     "http")
mkToggle("game.HttpGet",      "get")
mkToggle("loadstring",        "load")
mkToggle("string.char",       "char")
mkToggle("table.concat",      "concat")
mkToggle("bit32.bxor",        "bxor")
mkToggle("debug.sethook",     "sethook")
mkToggle("debug.getupvalue",  "upvalue")
mkToggle("string.dump",       "bytedump")

-- ============================================================
-- UTILITY
-- ============================================================
local function fnv1a(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit32.bxor(h, string.byte(s, i))
        h = bit32.band(h * 16777619, 0xFFFFFFFF)
    end
    return string.format("%08x", h)
end

local function push_log(line)
    table.insert(State.log, line)
    if #State.log > CFG.max_log then table.remove(State.log, 1) end
    if not CFG.silent then print(HOOK_TAG, line) end
end

local function refresh_stats()
    local s = State.stats
    local txt = string.format(
        "http: %d\nhttpget: %d\nloadstring: %d\nstring.char: %d\ntable.concat: %d\nbit32.bxor: %d\nstring.dump: %d\nenv ops: %d\ndumps: %d",
        s.http, s.get, s.load, s.char, s.concat, s.bxor, s.dump, s.env, dumped_count
    )
    -- AstraUI label update method may vary; try :Set
    pcall(function() StatsLabel:Set(txt) end)
end

local function save(name, data)
    if type(data) ~= "string" then return end
    if #data < CFG.dump_min then return end
    if dumped_count >= CFG.max_dumps then return end
    local hash = fnv1a(data)
    if CFG.dedup and dumped[hash] then return end
    dumped[hash] = true
    dumped_count = dumped_count + 1
    local fname = ("dump_%s_%s_%d.lua"):format(name, hash, math.floor(tick() * 1000))
    local ok = false
    if writefile then ok = pcall(writefile, fname, data) end
    local preview = data:sub(1, 200):gsub("[%z\1-\8\11\12\14-\31]", ".")
    local entry = {
        file    = fname,
        size    = #data,
        hash    = hash,
        ts      = os.time(),
        preview = preview,
        source  = data,
        label   = ("%s | %d B | %s"):format(name, #data, hash),
    }
    table.insert(State.payloads, entry)
    local opts = {}
    for _, p in ipairs(State.payloads) do opts[#opts + 1] = p.label end
    pcall(function() PayloadDropdown:SetOptions(opts) end)
    push_log(("[DUMP] %s (%d bytes)"):format(fname, #data))
    refresh_stats()
end

local function is_luarmor_url(url)
    url = ts(url or ""):lower()
    return url:find("luarmor%.net")
        or url:find("luarmor")
        or url:find("api%.luarmor")
        or url:find("files/v4")
        or url:find("/bootstrap")
        or url:find("raw%.githubusercontent%.com")
        or url:find("github%.com")
        or url:find("dameungrhub")
end

-- ============================================================
-- HOOKS
-- ============================================================
-- 1. request family
local function wrap_request(fn)
    if type(fn) ~= "function" then return fn end
    return function(args)
        local r = fn(args)
        if State.toggles.http and r and args and args.Url and is_luarmor_url(args.Url) then
            local body = r.Body or r.body or ""
            State.stats.http = State.stats.http + 1
            push_log(("[HTTP] %s -> %d (%d B)"):format(args.Url, r.StatusCode or 0, #body))
            if #body > 0 then save("http", body) end
            refresh_stats()
        end
        return r
    end
end
if syn and syn.request       then syn.request       = wrap_request(syn.request)       end
if http_request              then http_request      = wrap_request(http_request)      end
if request                   then request           = wrap_request(request)           end
if fluxus and fluxus.request then fluxus.request    = wrap_request(fluxus.request)    end
if getgenv then
    local g = getgenv()
    if g.http_request            then g.http_request       = wrap_request(g.http_request)       end
    if g.request                 then g.request            = wrap_request(g.request)            end
    if g.syn and g.syn.request   then g.syn.request        = wrap_request(g.syn.request)        end
    if g.fluxus and g.fluxus.request then g.fluxus.request = wrap_request(g.fluxus.request)     end
end

-- 2. game.HttpGet
local rawHttpGet = game.HttpGet
game.HttpGet = function(self, url, ...)
    local body = rawHttpGet(self, url, ...)
    if State.toggles.get and is_luarmor_url(url) and type(body) == "string" then
        State.stats.get = State.stats.get + 1
        push_log(("[GET] %s (%d B)"):format(url, #body))
        save("get", body)
        refresh_stats()
    end
    return body
end

-- 3. loadstring / load
local function wrap_load(fn, tag)
    if type(fn) ~= "function" then return fn end
    return function(src, chunk)
        if State.toggles.load and type(src) == "string" and #src > CFG.dump_min then
            State.stats.load = State.stats.load + 1
            push_log(("[LOAD/%s] %d B"):format(tag, #src))
            save("load", src)
            refresh_stats()
        end
        return fn(src, chunk)
    end
end
if loadstring then loadstring = wrap_load(loadstring, "ls") end
if load       then load       = wrap_load(load, "load")    end
if getgenv then
    local g = getgenv()
    if g.loadstring then g.loadstring = wrap_load(g.loadstring, "g.ls") end
    if g.load       then g.load       = wrap_load(g.load, "g.load")     end
end

-- 4. debug.getinfo
local hooked_sources = {}
if debug and debug.getinfo then
    local rawGetinfo = debug.getinfo
    debug.getinfo = function(...)
        local r = rawGetinfo(...)
        if type(r) == "table" and r.source then
            local src = r.source
            if src:find("luarmor") or src:find("files/v4") or src:find("bootstrap") then
                if not hooked_sources[src] then
                    hooked_sources[src] = true
                    push_log("[TRACE] " .. src)
                end
            end
        end
        return r
    end
end

-- 5. getfenv / setfenv
if getfenv then
    local rawGetfenv = getfenv
    getfenv = function(f)
        local env = rawGetfenv(f)
        if type(f) == "function" and debug and debug.getinfo then
            local info = debug.getinfo(f, "S")
            if info and info.source and info.source:find("luarmor") then
                State.stats.env = State.stats.env + 1
                push_log("[ENV-GET] " .. info.source)
                refresh_stats()
            end
        end
        return env
    end
    if getgenv then getgenv().getfenv = getfenv end
end
if setfenv then
    local rawSetfenv = setfenv
    setfenv = function(fn, env)
        if type(fn) == "function" and debug and debug.getinfo then
            local info = debug.getinfo(fn, "S")
            if info and info.source and info.source:find("luarmor") then
                State.stats.env = State.stats.env + 1
                push_log("[ENV-SET] " .. info.source)
                refresh_stats()
            end
        end
        return rawSetfenv(fn, env)
    end
    if getgenv then getgenv().setfenv = setfenv end
end

-- 6. string.char
local rawChar = string.char
local char_count = 0
string.char = function(...)
    local n = select("#", ...)
    if State.toggles.char and n > 20 then
        char_count = char_count + 1
        State.stats.char = State.stats.char + 1
        if char_count % 50 == 0 then
            push_log("[DECODE] string.char x" .. char_count)
            refresh_stats()
        end
    end
    return rawChar(...)
end

-- 7. table.concat
local rawConcat = table.concat
table.concat = function(t, sep, i, j)
    local r = rawConcat(t, sep, i, j)
    if State.toggles.concat and type(r) == "string" and #r > 500 then
        if r:find("function") or r:find("local ") or r:find("return") then
            State.stats.concat = State.stats.concat + 1
            save("concat", r)
            refresh_stats()
        end
    end
    return r
end

-- 8. bit32.bxor
if bit32 then
    local rawBxor = bit32.bxor
    local bxor_count = 0
    bit32.bxor = function(...)
        if State.toggles.bxor then
            bxor_count = bxor_count + 1
            State.stats.bxor = State.stats.bxor + 1
            if bxor_count % 500 == 0 then refresh_stats() end
        end
        return rawBxor(...)
    end
end

-- 9. anti-anti-hook spoof
local SPOOFED_FNS = { string.char, table.concat, debug.getinfo, getfenv, setfenv }
local function spoof_check(fn)
    for _, f in ipairs(SPOOFED_FNS) do if fn == f then return true end end
    return false
end
if getgenv and getgenv().isfunctionhooked then
    local raw = getgenv().isfunctionhooked
    getgenv().isfunctionhooked = function(fn)
        if spoof_check(fn) then return false end
        return raw(fn)
    end
end
if isfunctionhooked then
    local raw = isfunctionhooked
    isfunctionhooked = function(fn)
        if spoof_check(fn) then return false end
        return raw(fn)
    end
end

-- 10. debug.sethook
if debug and debug.sethook then
    local rawSethook = debug.sethook
    debug.sethook = function(...)
        if State.toggles.sethook then
            local info = debug.getinfo(2, "S")
            if info and info.source and info.source:sub(1, 1) == "=" then
                push_log("[BLOCK] sethook from C context")
                return
            end
        end
        return rawSethook(...)
    end
end

-- 11. debug.getupvalue
if debug and debug.getupvalue then
    local rawGetUp = debug.getupvalue
    local traced_upvalues = {}
    debug.getupvalue = function(f, n)
        local name, val = rawGetUp(f, n)
        if State.toggles.upvalue and type(val) == "string" and #val > 100 then
            local hash = fnv1a(val)
            if not traced_upvalues[hash] then
                traced_upvalues[hash] = true
                push_log(("[UPVAL] %s (%d B)"):format(name or "?", #val))
                save("upval", val)
                refresh_stats()
            end
        end
        return name, val
    end
end

-- 12. getrawmetatable
if getrawmetatable then
    local rawGetMt = getrawmetatable
    getrawmetatable = function(o) return rawGetMt(o) end
    if getgenv then getgenv().getrawmetatable = getrawmetatable end
end

-- 13. string.dump
if string.dump then
    local rawDump = string.dump
    string.dump = function(fn, ...)
        local bc = rawDump(fn, ...)
        if State.toggles.bytedump and type(bc) == "string" and #bc > CFG.dump_min then
            State.stats.dump = State.stats.dump + 1
            push_log(("[BYTECODE] %d B"):format(#bc))
            save("bytecode", bc)
            refresh_stats()
        end
        return bc
    end
end

-- ============================================================
-- BOOT
-- ============================================================
push_log("[+] Nyx hook monitor active.")
push_log("[+] RightShift = toggle window.")
push_log("[+] Payloads tab -> pilih source, tekan Load Selected.")

pcall(function() LogLabel:Set(table.concat(State.log, "\n")) end)

Library.Notify({
    Title    = "Nyx",
    Text     = "Hook monitor active. RightShift to toggle.",
    Icon     = "check",
    Duration = 4,
})

if not CFG.silent then
    print(HOOK_TAG, "AstraUI installed.")
end
