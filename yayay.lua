-- luarmor_advanced_hook_with_ui.lua (v4-fix)
-- tempel di executor SEBELUM load bootstrap Luarmor

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ts          = tostring

-- ============================================================
-- LOAD SIRIUS UI
-- ============================================================
local Sirius = loadstring(game:HttpGet("https://sirius.menu/gen2"))()

-- ============================================================
-- CONFIG
-- ============================================================
local CFG = {
    silent    = true,
    dump_min  = 40,
    dedup     = true,
    max_dumps = 200,
    max_log   = 500,
    sandbox   = false,
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
-- UI
-- ============================================================
local Window = Sirius:Window({
    Title       = "Nyx // Luarmor Hook Monitor",
    Subtitle    = "live hook trace + payload capture + reload",
    Size        = UDim2.fromOffset(680, 520),
    Theme       = "Dark",
    Acrylic     = true,
    Minimizable = true,
    ToggleKey   = Enum.KeyCode.RightShift,
})

local LogTab     = Window:Tab({ Title = "Live Log",   Icon = "scroll-text" })
local PayloadTab = Window:Tab({ Title = "Payloads",   Icon = "package" })
local ReloadTab  = Window:Tab({ Title = "Reload",     Icon = "play-circle" })
local StatsTab   = Window:Tab({ Title = "Stats",      Icon = "activity" })
local CfgTab     = Window:Tab({ Title = "Controls",   Icon = "settings" })

-- forward declarations (biar bisa saling refer)
local ReloadBox
local push_log
local refresh_stats

-- ---------- LOG TAB ----------
local LogSection = LogTab:Section({ Title = "hook stream" })
local LogPara    = LogSection:Paragraph({
    Title      = "activity",
    Desc       = "waiting for hook events...",
    Color      = Color3.fromRGB(180, 180, 190),
    MaxHeight  = 320,
    Autoscroll = true,
})
LogSection:Button({
    Title = "clear log",
    Callback = function()
        State.log = {}
        LogPara:SetDesc("cleared.\nwaiting for hook events...")
    end,
})

-- ---------- PAYLOAD TAB ----------
local PayloadSection = PayloadTab:Section({ Title = "captured payloads" })
local PayloadMeta
local PayloadPreview

local PayloadList = PayloadSection:Dropdown({
    Title  = "select payload",
    Values = {},
    Value  = nil,
    Callback = function(v)
        if not v then return end
        for _, p in ipairs(State.payloads) do
            if p.label == v then
                State.selected = p
                if PayloadPreview then PayloadPreview:SetDesc(p.preview) end
                if PayloadMeta then
                    PayloadMeta:SetDesc(
                        "file: " .. p.file .. "\n"
                        .. "size: " .. p.size .. " bytes\n"
                        .. "hash: " .. p.hash .. "\n"
                        .. "time: " .. os.date("%H:%M:%S", p.ts)
                    )
                end
                if ReloadBox then pcall(function() ReloadBox:Set(p.source) end) end
                break
            end
        end
    end,
})

PayloadMeta = PayloadSection:Paragraph({
    Title = "metadata",
    Desc  = "no payload selected",
    Color = Color3.fromRGB(160, 200, 255),
})

PayloadPreview = PayloadSection:Paragraph({
    Title     = "preview (first 500 chars)",
    Desc      = "",
    Color     = Color3.fromRGB(200, 200, 200),
    MaxHeight = 200,
})

-- ---------- RELOAD TAB ----------
local ReloadSection = ReloadTab:Section({ Title = "load / execute payload" })

ReloadBox = ReloadSection:TextBox({
    Title       = "source",
    Desc        = "edit atau paste source di sini, lalu tekan Load",
    Placeholder = "-- paste luarmor source atau pilih dari Payloads tab",
    Value       = "",
    Multiline   = true,
    Height      = 260,
    Callback    = function(v) end,
})

local ReloadStatus = ReloadSection:Paragraph({
    Title = "status",
    Desc  = "idle",
    Color = Color3.fromRGB(200, 200, 200),
})

push_log = function(line)
    table.insert(State.log, line)
    if #State.log > CFG.max_log then table.remove(State.log, 1) end
    local text = table.concat(State.log, "\n")
    pcall(function() LogPara:SetDesc(text) end)
    if not CFG.silent then print(HOOK_TAG, line) end
end

refresh_stats = function()
    local s = State.stats
    local txt = string.format(
        "http: %d\nhttpget: %d\nloadstring: %d\nstring.char: %d\ntable.concat: %d\nbit32.bxor: %d\nstring.dump: %d\nenv ops: %d",
        s.http, s.get, s.load, s.char, s.concat, s.bxor, s.dump, s.env
    )
    pcall(function() StatsPara:SetDesc(txt) end)
    pcall(function() DumpCountLabel:SetDesc(dumped_count .. " / " .. CFG.max_dumps) end)
    pcall(function() ExecLabel:SetDesc(tostring(State.exec_count)) end)
end

local function run_source(src, tag)
    if type(src) ~= "string" or #src < 10 then
        ReloadStatus:SetDesc("[!] source kosong / terlalu pendek")
        return
    end

    local chunk, err
    if loadstring then
        chunk, err = loadstring(src, "@nyx_reload_" .. tostring(State.exec_count))
    elseif load then
        chunk, err = load(src, "@nyx_reload_" .. tostring(State.exec_count))
    else
        ReloadStatus:SetDesc("[!] loadstring tidak tersedia di executor ini")
        return
    end

    if not chunk then
        ReloadStatus:SetDesc("[ERR compile] " .. ts(err))
        push_log("[RELOAD-ERR] " .. ts(err))
        return
    end

    State.exec_count = State.exec_count + 1
    local id = State.exec_count

    task.spawn(function()
        local env
        if CFG.sandbox and setfenv and getfenv then
            env = setmetatable({}, { __index = getfenv(0) })
            pcall(setfenv, chunk, env)
        end

        local ok, err2 = pcall(chunk)
        if ok then
            ReloadStatus:SetDesc(("[ok #%d] %s — %d bytes"):format(id, tag or "manual", #src))
            push_log(("[RELOAD-OK #%d] %d bytes"):format(id, #src))
        else
            ReloadStatus:SetDesc(("[ERR runtime #%d] %s"):format(id, ts(err2)))
            push_log(("[RELOAD-ERR #%d] %s"):format(id, ts(err2)))
        end
    end)
end

ReloadSection:Button({
    Title    = "load",
    Callback = function()
        local src
        pcall(function() src = ReloadBox:Get() end)
        if type(src) ~= "string" or src == "" then
            if State.selected then src = State.selected.source end
        end
        run_source(src, "reload-tab")
    end,
})

ReloadSection:Button({
    Title    = "load selected payload",
    Callback = function()
        if not State.selected then
            ReloadStatus:SetDesc("[!] belum ada payload dipilih")
            return
        end
        run_source(State.selected.source, "payload:" .. State.selected.hash)
    end,
})

ReloadSection:Button({
    Title    = "clear box",
    Callback = function()
        pcall(function() ReloadBox:Set("") end)
        ReloadStatus:SetDesc("cleared")
    end,
})

-- ---------- STATS TAB ----------
local StatsSection = StatsTab:Section({ Title = "counters" })
local StatsPara    = StatsSection:Paragraph({
    Title = "hook hit count",
    Desc  = "loading...",
    Color = Color3.fromRGB(180, 255, 180),
})
local DumpCountLabel = StatsSection:Paragraph({
    Title = "total dumps",
    Desc  = "0 / " .. CFG.max_dumps,
    Color = Color3.fromRGB(255, 200, 120),
})
local ExecLabel = StatsSection:Paragraph({
    Title = "reload executions",
    Desc  = "0",
    Color = Color3.fromRGB(200, 180, 255),
})

-- ---------- CONTROLS TAB ----------
local CtrlSection = CfgTab:Section({ Title = "hook toggles" })
local function mkToggle(name, key)
    CtrlSection:Toggle({
        Title    = name,
        Desc     = "enable/disable " .. key .. " hook",
        Value    = State.toggles[key],
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

CtrlSection:Toggle({
    Title    = "sandbox reload (isolated env)",
    Desc     = "run source di env kosong, __index ke getfenv(0)",
    Value    = CFG.sandbox,
    Callback = function(v) CFG.sandbox = v end,
})
CtrlSection:Toggle({
    Title    = "silent mode (hide [N-HOOK] prints)",
    Value    = CFG.silent,
    Callback = function(v) CFG.silent = v end,
})

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

local function save(name, data)
    if type(data) ~= "string" then return end
    if #data < CFG.dump_min then return end
    if dumped_count >= CFG.max_dumps then
        push_log("[!] dump limit reached")
        return
    end

    local hash = fnv1a(data)
    if CFG.dedup and dumped[hash] then return end
    dumped[hash] = true
    dumped_count = dumped_count + 1

    local ts_ms = math.floor(tick() * 1000)
    local fname = ("dump_%s_%s_%d.lua"):format(name, hash, ts_ms)
    local ok = false
    if writefile then ok = pcall(writefile, fname, data) end

    local preview = data:sub(1, 500)
    preview = preview:gsub("[%z\1-\8\11\12\14-\31]", ".")

    local entry = {
        file    = fname,
        size    = #data,
        hash    = hash,
        ts      = os.time(),
        preview = preview .. (#data > 500 and "\n... [truncated]" or ""),
        source  = data,
        label   = ("%s | %d B | %s"):format(name, #data, hash),
    }
    table.insert(State.payloads, entry)

    local values = {}
    for _, p in ipairs(State.payloads) do values[#values + 1] = p.label end
    pcall(function() PayloadList:SetValues(values) end)

    push_log(("[DUMP] %s (%d bytes) %s"):format(fname, #data, ok and "ok" or "no-writefile"))
    refresh_stats()
end

-- FIXED: cuma satu fungsi, gak ada nested duplikat
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
-- 1. request family
-- ============================================================
local function wrap_request(fn)
    if type(fn) ~= "function" then return fn end
    return function(args)
        local r = fn(args)
        if State.toggles.http and r and args and args.Url and is_luarmor_url(args.Url) then
            local body   = r.Body or r.body or ""
            local status = r.StatusCode or r.status_code or 0
            State.stats.http = State.stats.http + 1
            push_log(("[HTTP] %s -> %d (%d B)"):format(args.Url, status, #body))
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

-- ============================================================
-- 2. game.HttpGet
-- ============================================================
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

-- ============================================================
-- 3. loadstring / load
-- ============================================================
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

-- ============================================================
-- 4. debug.getinfo
-- ============================================================
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

-- ============================================================
-- 5. getfenv / setfenv
-- ============================================================
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

-- ============================================================
-- 6. string.char
-- ============================================================
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

-- ============================================================
-- 7. table.concat
-- ============================================================
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

-- ============================================================
-- 8. bit32.bxor
-- ============================================================
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

-- ============================================================
-- 9. anti-anti-hook spoof
-- ============================================================
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

-- ============================================================
-- 10. debug.sethook
-- ============================================================
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

-- ============================================================
-- 11. debug.getupvalue
-- ============================================================
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

-- ============================================================
-- 12. getrawmetatable
-- ============================================================
if getrawmetatable then
    local rawGetMt = getrawmetatable
    getrawmetatable = function(o) return rawGetMt(o) end
    if getgenv then getgenv().getrawmetatable = getrawmetatable end
end

-- ============================================================
-- 13. string.dump
-- ============================================================
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
push_log("[+] Payloads tab -> pilih source, Reload tab -> tekan Load.")
refresh_stats()

if not CFG.silent then
    print(HOOK_TAG, "UI installed. RightShift to toggle.")
end