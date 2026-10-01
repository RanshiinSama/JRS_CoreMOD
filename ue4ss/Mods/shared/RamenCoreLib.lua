-- RamenCoreLib: Japanese Ramen Simulator 共通ライブラリ
-- UE4SS は MOD ごとに Lua 環境が別なので、各MODは require("RamenCoreLib") で読み込む。
-- 配置: Mods/shared/RamenCoreLib.lua  (Mods/shared は package.path に含まれる)

local VERSION = "0.11.0"

-- Mods/ ディレクトリ (このファイルは Mods/shared/ にある)
local src = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local MODS = src:match("^(.*)/shared/[^/]*$") or "."
local ROOT = MODS .. "/RamenCore" -- ログ・Config の保存先
local Core = {}
Core.ModsDir = MODS -- Mods フォルダのパス

-- ホットリロード(UI再読込 / Ctrl+R)の判定。
-- 「すでにステージ(ClientRestart)が始まった後に、MODが読み込まれたか」で判定する。
--   ・新規起動: MODは最初のステージ開始より前に読み込まれる → 再読込ではない
--   ・再読込  : 既にステージが始まっている → ClientRestart を待っても来ないので、MODはその場で動き始める必要がある
-- ステージ開始時に RamenCore が Core.TrackWorld() のフックで「ゲームの起動時刻」を world.txt に書く。
-- Windows では os.clock() は「プロセス起動からの経過秒」なので、(現在時刻 - os.clock()) が起動時刻になる。
-- world.txt の起動時刻が今のプロセスと一致すれば、このプロセスでステージは始まっている(=再読込)。
local LOAD_CLOCK = os.clock()
local worldPath = ROOT .. "/world.txt"

local function processStart() return os.time() - os.clock() end

function Core.LoadClock() return LOAD_CLOCK end

function Core.TrackWorld()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function() end, function()
        local w = io.open(worldPath, "w")
        if w then w:write(string.format("%.0f", processStart()), "\n"); w:close() end
    end)
end

function Core.IsReload()
    local f = io.open(worldPath, "r")
    if not f then return false end
    local saved = tonumber(f:read("*l")); f:close()
    return saved ~= nil and math.abs(saved - processStart()) <= 3
end

Core.Version = VERSION

------------------------------------------------------------------ Logging
local logPath = ROOT .. "/RamenCore.log"

-- ログを空にする (新規起動のときだけ呼ぶ。再読込のときは呼ばず、続きに書く)
function Core.ResetLog()
    local f = io.open(logPath, "w"); if f then f:close() end
end

function Core.Log(modName, level, msg)
    local line = string.format("[%s][%s][%s] %s", os.date("%H:%M:%S"), level, modName, tostring(msg))
    print(line .. "\n")
    local f = io.open(logPath, "a")
    if f then f:write(line, "\n"); f:close() end
end

function Core.GetLogger(modName)
    return {
        info  = function(m) Core.Log(modName, "INFO",  m) end,
        warn  = function(m) Core.Log(modName, "WARN",  m) end,
        error = function(m) Core.Log(modName, "ERROR", m) end,
    }
end

------------------------------------------------------------------ Version
local function parseVer(v)
    local a, b, c = tostring(v):match("^(%d+)%.?(%d*)%.?(%d*)")
    return { tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0 }
end

function Core.CompareVersion(a, b)
    local x, y = parseVer(a), parseVer(b)
    for i = 1, 3 do
        if x[i] ~= y[i] then return x[i] < y[i] and -1 or 1 end
    end
    return 0
end

------------------------------------------------------------------ Mod registry
-- レジストリは MOD 間共有のため、ファイル (Mods/RamenCore/registry.txt) に 1 MOD 1 行で保存する。
--   name|version|author|description|keys|requires|errors
--   keys     = "F7=説明;F8=説明"   requires = "RamenCore=0.2.0,Other=1.0.0"   errors = 依存エラー文(空なら正常)
-- 各MODはゲーム起動ごとに RegisterMod する。起動時の最初に RamenCore が ResetRegistry() で空にする。
local regPath = ROOT .. "/registry.txt"

local function clean(s) return (tostring(s or ""):gsub("[|\r\n]", " ")) end

local function encodeKeys(keys)
    local t = {}
    for _, k in ipairs(keys or {}) do t[#t + 1] = clean(k.key):gsub("[;=]", "") .. "=" .. clean(k.desc):gsub(";", ",") end
    return table.concat(t, ";")
end

local function decodeKeys(s)
    local res = {}
    for item in (s or ""):gmatch("[^;]+") do
        local k, d = item:match("^([^=]*)=(.*)$")
        if k then res[#res + 1] = { key = k, desc = d } end
    end
    return res
end

local function encodeReq(req)
    local t = {}
    for dep, v in pairs(req or {}) do t[#t + 1] = dep .. "=" .. tostring(v) end
    table.sort(t)
    return table.concat(t, ",")
end

local function decodeReq(s)
    local res = {}
    for item in (s or ""):gmatch("[^,]+") do
        local d, v = item:match("^([^=]*)=(.*)$")
        if d then res[d] = v end
    end
    return res
end

-- 登録順 (=読み込み順) の配列と、名前引きの表を返す
local function readRegistry()
    local list, map = {}, {}
    local f = io.open(regPath, "r")
    if f then
        for line in f:lines() do
            local n, v, a, d, k, r, e = line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
            if n then
                local m = { name = n, version = v, author = a, description = d,
                            keys = decodeKeys(k), requires = decodeReq(r), errors = e }
                list[#list + 1] = m
                map[n] = m
            end
        end
        f:close()
    end
    return list, map
end

function Core.ResetRegistry()
    local f = io.open(regPath, "w"); if f then f:close() end
end

-- info = { name=, version=, author=, description=, keys = { {key="F7", desc="..."} }, requires = { RamenCore="0.3.0" } }
local function encodeEntry(m)
    return table.concat({
        clean(m.name), clean(m.version or "?"), clean(m.author or "?"), clean(m.description),
        encodeKeys(m.keys), encodeReq(m.requires), clean(m.errors),
    }, "|")
end

-- 同じ名前の行があれば、その位置で差し替える。無ければ末尾に追加する。
-- (1つのMODだけが再読込されても、他のMODの登録が消えないようにする)
function Core.RegisterMod(info)
    assert(type(info) == "table" and info.name, "RegisterMod: name is required")
    local _, missing = Core.CheckDependencies(info)
    local entry = { name = info.name, version = info.version, author = info.author, description = info.description,
                    keys = info.keys, requires = info.requires, errors = table.concat(missing or {}, ", ") }
    local list = readRegistry()
    local replaced = false
    for i, m in ipairs(list) do
        if m.name == info.name then list[i] = entry; replaced = true; break end
    end
    if not replaced then list[#list + 1] = entry end
    local f = io.open(regPath, "w")
    if f then
        for _, m in ipairs(list) do f:write(encodeEntry(m), "\n") end
        f:close()
    end
    Core.Log("RamenCore", "INFO", string.format("Registered %s v%s", info.name, info.version or "?"))
    return Core.GetLogger(info.name)
end

function Core.GetModList() local list = readRegistry(); return list end
function Core.GetMods() local _, map = readRegistry(); return map end
function Core.IsModLoaded(name) local _, map = readRegistry(); return map[name] ~= nil end

-- 依存チェック。満たせば true, {} / 不足があれば false, { "説明", ... }
function Core.CheckDependencies(info)
    local missing = {}
    local _, mods = readRegistry()
    for dep, minVer in pairs(info.requires or {}) do
        local d = mods[dep]
        if not d then
            missing[#missing + 1] = dep .. " (not loaded)"
        elseif Core.CompareVersion(d.version, minVer) < 0 then
            missing[#missing + 1] = string.format("%s (need >= %s, have %s)", dep, minVer, d.version)
        end
    end
    if #missing > 0 then
        Core.Log(info.name, "ERROR", "Missing dependencies: " .. table.concat(missing, ", "))
    end
    return #missing == 0, missing
end

function Core.ListMods()
    for _, m in ipairs(Core.GetModList()) do
        Core.Log("RamenCore", "INFO", string.format("  %s v%s by %s", m.name, m.version, m.author))
    end
end

------------------------------------------------------------------ mods.txt (有効/無効)
-- UE4SS は起動時にだけ mods.txt を読む。ここでの書き換えは「次回起動から有効/無効」になる。
-- ゲーム中は、各MODが Core.IsEnabled(自分の名前) を見て機能を止める(ソフト無効)。
local modsTxtPath = MODS .. "/mods.txt"
local LOCKED_MODS = { RamenCore = true, RamenUI = true } -- 無効にできないMOD
Core.LockedMods = LOCKED_MODS

-- mods.txt の { { name=, enabled= }, ... } (ファイル順)
function Core.GetModsTxt()
    local list = {}
    local f = io.open(modsTxtPath, "r")
    if f then
        for line in f:lines() do
            local n, v = line:match("^%s*([%w_%-%.]+)%s*:%s*([01])")
            if n and not line:match("^%s*;") then list[#list + 1] = { name = n, enabled = (v == "1") } end
        end
        f:close()
    end
    return list
end

function Core.IsEnabled(name)
    if LOCKED_MODS[name] then return true end
    for _, m in ipairs(Core.GetModsTxt()) do
        if m.name == name then return m.enabled end
    end
    return true -- mods.txt に無いMOD(enabled.txt 等で起動したもの)は有効扱い
end

-- mods.txt の name の行を書き換える (コメント・順序は保持)。成功で true
function Core.SetModEnabled(name, on)
    if LOCKED_MODS[name] then return false end
    local lines, found = {}, false
    local f = io.open(modsTxtPath, "r")
    if not f then return false end
    for line in f:lines() do
        local n = line:match("^%s*([%w_%-%.]+)%s*:%s*[01]")
        if n == name and not line:match("^%s*;") then
            lines[#lines + 1] = name .. " : " .. (on and "1" or "0")
            found = true
        else
            lines[#lines + 1] = line
        end
    end
    f:close()
    if not found then lines[#lines + 1] = name .. " : " .. (on and "1" or "0") end
    local w = io.open(modsTxtPath, "w")
    if not w then return false end
    w:write(table.concat(lines, "\n"), "\n")
    w:close()
    return true
end

------------------------------------------------------------------ 再読込 (UE4SS の EnableAutoReloadingLuaMods を利用)
-- UE4SS は、有効にすると「Scripts フォルダ内のファイルの変更」を検知して全MODを再読込する。
-- Lua から再読込を直接呼ぶ手段は無いので、Scripts 内の目印ファイルを書き換えて再読込を起こす。
local ue4ssIni = MODS .. "/../UE4SS-settings.ini"

function Core.IsAutoReloadEnabled()
    local f = io.open(ue4ssIni, "r")
    if not f then return false end
    local on = false
    for line in f:lines() do
        local v = line:match("^%s*EnableAutoReloadingLuaMods%s*=%s*(%d)")
        if v then on = (v == "1") end
    end
    f:close()
    return on
end

-- 再読込を要求する (成功=目印ファイルを書けた)。実際の再読込は UE4SS が数秒以内に行う。
function Core.RequestReload()
    -- UE4SS の自動再読込は「変更のあった Scripts を持つMODだけ」を再読込する。
    -- 全MODを再読込するため、有効な Ramen 系MOD(mods.txt で : 1 のもの)すべてに目印を書く。
    local stamp = "-- reload requested: " .. os.date("%Y-%m-%d %H:%M:%S") .. " clock=" .. tostring(os.clock()) .. "\n"
    local count = 0
    for _, m in ipairs(Core.GetModsTxt()) do
        if m.enabled and m.name:match("^Ramen") then
            local f = io.open(MODS .. "/" .. m.name .. "/Scripts/reload_stamp.lua", "w")
            if f then f:write(stamp); f:close(); count = count + 1 end
        end
    end
    return count > 0, count
end

------------------------------------------------------------------ Config (key=value ini)
local function configPath(modName) return ROOT .. "/Configs/" .. modName .. ".ini" end

function Core.LoadConfig(modName, defaults)
    local cfg, path = {}, configPath(modName)
    local f = io.open(path, "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^%s*([%w_%.]+)%s*=%s*(.-)%s*$")
            if k and not line:match("^%s*[;#]") then cfg[k] = v end
        end
        f:close()
    end
    local out = {}
    for k, d in pairs(defaults) do
        local v = cfg[k]
        if v == nil then out[k] = d
        elseif type(d) == "number" then out[k] = tonumber(v) or d
        elseif type(d) == "boolean" then out[k] = (v == "true" or v == "1")
        else out[k] = v end
    end
    Core.SaveConfig(modName, out)
    return out
end

function Core.SaveConfig(modName, cfg)
    local f = io.open(configPath(modName), "w")
    if not f then return false end
    local keys = {}
    for k in pairs(cfg) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do f:write(k, " = ", tostring(cfg[k]), "\n") end
    f:close()
    return true
end

------------------------------------------------------------------ Settings schema / validation / watch
-- UI は別の Lua 環境で動くため、スキーマはファイル (Mods/RamenCore/settings.txt) で共有する。
--   mod|key|type|default|min|max|restart|integer|allowEmpty|standard|desc
local schemaPath = ROOT .. "/settings.txt"

function Core.ResetSettingsSchema()
    local f = io.open(schemaPath, "w"); if f then f:close() end
end

local function b2s(b) return b and "1" or "0" end

-- items: { { key=, type="number"|"boolean"|"color"|"string", default=, min=, max=, desc=,
--            restart=bool(反映に再起動が必要), integer=bool, allowEmpty=bool }, ... }
function Core.RegisterSettings(modName, items)
    -- 再読込のとき二重にならないよう、このMODの既存の行を取り除いてから書き直す
    local keep = {}
    local rf = io.open(schemaPath, "r")
    if rf then
        for line in rf:lines() do
            if line:sub(1, #modName + 1) ~= clean(modName) .. "|" then keep[#keep + 1] = line end
        end
        rf:close()
    end
    local f = io.open(schemaPath, "w")
    if not f then return false end
    for _, line in ipairs(keep) do f:write(line, "\n") end
    for _, it in ipairs(items) do
        f:write(table.concat({
            clean(modName), clean(it.key), clean(it.type or "string"), clean(it.default),
            clean(it.min), clean(it.max), b2s(it.restart), b2s(it.integer), b2s(it.allowEmpty), clean(it.standard), clean(it.desc),
        }, "|"), "\n")
    end
    f:close()
    return true
end

-- modName の設定項目 (配列)。modName が nil なら { [mod]=配列 } を返す
function Core.GetSettingsSchema(modName)
    local all = {}
    local f = io.open(schemaPath, "r")
    if f then
        for line in f:lines() do
            local m, k, t, d, mn, mx, r, i, e, std, desc =
                line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
            if m then
                all[m] = all[m] or {}
                table.insert(all[m], { key = k, type = t, default = d, min = tonumber(mn), max = tonumber(mx),
                    restart = r == "1", integer = i == "1", allowEmpty = e == "1", standard = std, desc = desc })
            end
        end
        f:close()
    end
    if modName then return all[modName] or {} end
    return all
end

local function readIni(modName)
    local map = {}
    local f = io.open(configPath(modName), "r")
    if f then
        for line in f:lines() do
            local k, v = line:match("^%s*([%w_%.]+)%s*=%s*(.-)%s*$")
            if k and not line:match("^%s*[;#]") then map[k] = v end
        end
        f:close()
    end
    return map
end

local function writeIni(modName, map)
    local f = io.open(configPath(modName), "w")
    if not f then return false end
    local keys = {}
    for k in pairs(map) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do f:write(k, " = ", tostring(map[k]), "\n") end
    f:close()
    return true
end

-- 現在値 (文字列)。ini に無い項目はスキーマの既定値
function Core.GetSettingsValues(modName)
    local ini = readIni(modName)
    local vals = {}
    for _, it in ipairs(Core.GetSettingsSchema(modName)) do
        vals[it.key] = ini[it.key] ~= nil and ini[it.key] or it.default
    end
    return vals
end

-- 1項目の検証。成功: true, 正規化した文字列 / 失敗: false, エラー文
function Core.ValidateSetting(item, str)
    str = tostring(str or ""):match("^%s*(.-)%s*$")
    local t = item.type
    if t == "boolean" then
        local l = str:lower()
        if l == "true" or l == "1" or l == "on" then return true, "true" end
        if l == "false" or l == "0" or l == "off" then return true, "false" end
        return false, "ON か OFF を指定してください"
    elseif t == "number" then
        local n = tonumber(str)
        if not n then return false, "数値を入力してください" end
        if item.integer and n ~= math.floor(n) then return false, "整数を入力してください" end
        if item.min and n < item.min then return false, string.format("%s 以上にしてください", tostring(item.min)) end
        if item.max and n > item.max then return false, string.format("%s 以下にしてください", tostring(item.max)) end
        return true, item.integer and string.format("%d", n) or tostring(n)
    elseif t == "key" then
        if str == "" then return true, "" end -- 空欄 = 割り当て解除
        if Core.IsValidKey(str) then return true, str:upper() end
        return false, "使えないキーです。使えるキー: " .. Core.KeyHelp()
    elseif t == "color" then
        if str == "" then
            if item.allowEmpty then return true, "" end
            return false, "色コード (RRGGBB) を入力してください"
        end
        local hex = str:gsub("^#", "")
        if not hex:match("^%x%x%x%x%x%x$") then return false, "色は RRGGBB の16進6桁で入力してください" end
        return true, hex:upper()
    end
    if str == "" and not item.allowEmpty then return false, "空欄にはできません" end
    return true, str
end

-- 全項目を検証して ini に保存。strValues = { key = "文字列" }
-- 戻り値: ok, { key = エラー文 }, 再起動が必要な項目名の配列
function Core.SaveSettings(modName, strValues)
    local errs, restartKeys, norm = {}, {}, {}
    local schema = Core.GetSettingsSchema(modName)
    local ini = readIni(modName)
    for _, it in ipairs(schema) do
        local raw = strValues[it.key]
        if raw ~= nil then
            local okv, res = Core.ValidateSetting(it, raw)
            if okv then
                norm[it.key] = res
                if it.restart and res ~= (ini[it.key] or it.default) then restartKeys[#restartKeys + 1] = it.key end
            else
                errs[it.key] = res
            end
        end
    end
    if next(errs) then return false, errs, {} end
    -- キー割り当ての重複チェック (全MODの type="key" の現在値と、保存しようとしている値を突き合わせる)
    local used = {} -- used[キー] = "MOD.項目"
    for mod, items in pairs(Core.GetSettingsSchema()) do
        local values = (mod == modName) and nil or readIni(mod)
        for _, it in ipairs(items) do
            if it.type == "key" and mod ~= modName then
                local v = (values[it.key] or it.default):upper()
                if v ~= "" then used[v] = used[v] or (mod .. "." .. it.key) end
            end
        end
    end
    for _, it in ipairs(schema) do
        if it.type == "key" and norm[it.key] and norm[it.key] ~= "" then
            local v = norm[it.key]
            if used[v] then errs[it.key] = v .. " は " .. used[v] .. " が使用中です"
            else used[v] = modName .. "." .. it.key end
        end
    end
    if next(errs) then return false, errs, {} end
    for k, v in pairs(norm) do ini[k] = v end
    if not writeIni(modName, ini) then return false, { _file = "ファイルに書き込めません" }, {} end
    return true, {}, restartKeys
end

-- ini の変更を監視して cfg (テーブル) に反映する。変更時に onChange(cfg) をゲームスレッドで呼ぶ。
-- ロード中に動かないよう、プレイヤー出現(ClientRestart)の5秒後から1秒間隔で確認する。
function Core.WatchConfig(modName, cfg, onChange)
    local last = nil
    local function snapshot()
        local f = io.open(configPath(modName), "r")
        if not f then return "" end
        local s = f:read("*a"); f:close()
        return s
    end
    local epoch = 0
    local function tick(my)
        if my ~= epoch then return end
        ExecuteWithDelay(1000, function()
            if my ~= epoch then return end
            local cur = snapshot()
            if last ~= nil and cur ~= last then
                last = cur
                ExecuteInGameThread(function()
                    local ini = readIni(modName)
                    for k, old in pairs(cfg) do
                        local v = ini[k]
                        if v ~= nil then
                            if type(old) == "number" then cfg[k] = tonumber(v) or old
                            elseif type(old) == "boolean" then cfg[k] = (v == "true" or v == "1")
                            else cfg[k] = v end
                        end
                    end
                    local okc, e = pcall(onChange, cfg)
                    if not okc then Core.Log(modName, "ERROR", "onChange: " .. tostring(e)) end
                    Core.Log(modName, "INFO", "settings reloaded")
                end)
            end
            last = last or cur
            tick(my)
        end)
    end
    if Core.IsReload() then -- ホットリロード: ステージ切替が起きないので、すぐ監視を始める
        ExecuteWithDelay(2000, function() last = snapshot(); tick(epoch) end)
    end
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function() epoch = epoch + 1 end, function()
        local my = epoch
        ExecuteWithDelay(5000, function() if my == epoch then last = snapshot(); tick(my) end end)
    end)
end

------------------------------------------------------------------ キー割り当て
-- 選べるキー (保存する名前 -> UE4SS の Key 列挙名の候補)。
-- F11 はゲームがフルスクリーン切替、F12 は Steam のスクリーンショットに使うので除外。
-- ゲーム本来の操作キー (WASD など) とも重なりうる。重なっても許可する (ユーザー判断)
local KEY_DEFS = {}
local function addKey(name, ...) KEY_DEFS[#KEY_DEFS + 1] = { name = name, enums = { ... } } end
for i = 1, 10 do addKey("F" .. i, "F" .. i) end
for c = 65, 90 do local ch = string.char(c); addKey(ch, ch) end
local DIGITS = { "ZERO", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE" }
for i = 0, 9 do addKey(tostring(i), DIGITS[i + 1]) end
for i = 0, 9 do addKey("NUM" .. i, "NUM_" .. DIGITS[i + 1]) end
addKey("INS", "INS", "INSERT"); addKey("DEL", "DEL", "DELETE")
addKey("HOME", "HOME"); addKey("END", "END")
addKey("PGUP", "PAGE_UP", "PAGEUP"); addKey("PGDN", "PAGE_DOWN", "PAGEDOWN")

Core.KeyChoices = {}
local KEY_SET = {}
for _, d in ipairs(KEY_DEFS) do Core.KeyChoices[#Core.KeyChoices + 1] = d.name; KEY_SET[d.name] = true end
function Core.IsValidKey(name) return KEY_SET[tostring(name):upper()] == true end
function Core.KeyHelp() return "A～Z  0～9  NUM0～NUM9  F1～F10  INS DEL HOME END PGUP PGDN" end

-- 設定パネルを開いている間は、割り当てたキーを反応させない (入力欄に文字を打つと誤作動するため)。
-- UI と各MODは別の Lua 環境なので、ファイルで共有する
local uiOpenPath = ROOT .. "/ui_open.txt"
function Core.SetUiOpen(on)
    local f = io.open(uiOpenPath, "w")
    if f then f:write(on and "1" or "0"); f:close() end
end
function Core.IsUiOpen()
    local f = io.open(uiOpenPath, "r")
    if not f then return false end
    local s = f:read("*a"); f:close()
    return s == "1"
end

-- UE4SS の RegisterKeyBind は後から解除できないため、候補のキー全部にハンドラーを登録しておき、
-- 押されたキーが getKey() (設定値) と一致したときだけ fn を呼ぶ。設定を変えれば再起動なしで割り当てが変わる。
-- getKey() が空文字なら割り当て解除。opts.always=true なら、パネルを開いていても反応する (パネルの開閉キー用)
function Core.BindKey(getKey, fn, opts)
    local always = opts and opts.always
    local missing = {}
    for _, d in ipairs(KEY_DEFS) do
        local code
        for _, en in ipairs(d.enums) do
            code = Key[en]
            if code then break end
        end
        if code then
            RegisterKeyBind(code, function()
                local okk, want = pcall(getKey)
                if not okk or tostring(want or ""):upper() ~= d.name then return end
                if not always and Core.IsUiOpen() then return end
                fn()
            end)
        else
            missing[#missing + 1] = d.name
        end
    end
    if #missing > 0 then Core.Log("RamenCore", "WARN", "keys unavailable in this UE4SS: " .. table.concat(missing, ",")) end
end

------------------------------------------------------------------ 色プリセット (設定UIの色選択用)
Core.ColorPresets = {
    { name = "赤",     hex = "FF0000" },
    { name = "青",     hex = "1E64FF" },
    { name = "水色",   hex = "00FFFF" },
    { name = "緑",     hex = "00FF00" },
    { name = "白",     hex = "FFFFFF" },
    { name = "黄色",   hex = "FFFF00" },
    { name = "紫",     hex = "8000FF" },
    { name = "ピンク", hex = "FF69B4" },
}

-- 色コードに一致するプリセット名 (無ければ nil)
function Core.ColorName(hex)
    hex = tostring(hex or ""):gsub("^#", ""):upper()
    for _, p in ipairs(Core.ColorPresets) do
        if p.hex == hex then return p.name end
    end
    return nil
end

-- "RRGGBB" (sRGB) -> リニア {R,G,B,A}。不正なら nil
function Core.HexToLinear(hex)
    hex = tostring(hex or ""):gsub("^#", "")
    if not hex:match("^%x%x%x%x%x%x$") then return nil end
    local function lin(c) c = c / 255; if c <= 0.04045 then return c / 12.92 end return ((c + 0.055) / 1.055) ^ 2.4 end
    return { R = lin(tonumber(hex:sub(1, 2), 16)), G = lin(tonumber(hex:sub(3, 4), 16)), B = lin(tonumber(hex:sub(5, 6), 16)), A = 1.0 }
end

------------------------------------------------------------------ Object search API
local function valid(o) return o ~= nil and o:IsValid() end
Core.IsValid = valid

function Core.FindFirst(className)
    local o = FindFirstOf(className)
    return valid(o) and o or nil
end

function Core.FindAll(className)
    local res = {}
    for _, o in ipairs(FindAllOf(className) or {}) do
        if valid(o) and not o:GetFullName():find("Default__", 1, true) then
            res[#res + 1] = o
        end
    end
    return res
end

function Core.FindByName(className, substr)
    local res = {}
    for _, o in ipairs(Core.FindAll(className)) do
        if o:GetFullName():find(substr, 1, true) then res[#res + 1] = o end
    end
    return res
end

function Core.GetPlayerController() return Core.FindFirst("PlayerController") end

function Core.GetPlayerPawn()
    local pc = Core.GetPlayerController()
    if not pc then return nil end
    local ok, pawn = pcall(function() return pc.Pawn end)
    return (ok and valid(pawn)) and pawn or nil
end

function Core.GetProp(obj, name, default)
    if not valid(obj) then return default end
    local ok, v = pcall(function() return obj[name] end)
    if ok and v ~= nil then return v end
    return default
end

function Core.SetProp(obj, name, value)
    if not valid(obj) then return false end
    return (pcall(function() obj[name] = value end))
end

-- obj:fn(...) を安全に呼ぶ。成功時 true, 戻り値 / 失敗時 false, エラー
function Core.Call(obj, fn, ...)
    if not valid(obj) then return false, "invalid object" end
    local args = { ... }
    return pcall(function() return obj[fn](obj, table.unpack(args)) end)
end

function Core.DumpClass(className)
    for _, o in ipairs(Core.FindAll(className)) do
        Core.Log("RamenCore", "INFO", o:GetFullName())
    end
end

function Core.OnNewObject(className, fn) NotifyOnNewObject(className, fn) end

------------------------------------------------------------------ Game API (RealRamenSimulator)
local Game = {}
Core.Game = Game

function Game.GetState() return Core.FindFirst("MenGameState") end
function Game.GetPlayerState() return Core.FindFirst("MenPlayerState") end
function Game.GetPlayer() return Core.FindFirst("MenPlayerCharacter") end
function Game.GetBusinessDay() return Core.FindFirst("MenBusinessDaySubsystem") end

function Game.GetMoney() return Core.GetProp(Game.GetState(), "Money", nil) end

-- お金を delta 増減 (ゲームの ApplyMoneyDelta 経由なので UI にも反映される)
function Game.AddMoney(delta)
    local gs = Game.GetState()
    if not gs then return false end
    local ok = Core.Call(gs, "ApplyMoneyDelta", delta + 0.0)
    if not ok then ok = Core.Call(gs, "DebugAddMoney", delta + 0.0) end
    return ok
end

function Game.SetMoney(v)
    local m = Game.GetMoney()
    if m == nil then return false end
    return Game.AddMoney(v - m)
end

function Game.TrySpendMoney(cost)
    local ok, r = Core.Call(Game.GetState(), "TrySpendMoney", cost + 0.0)
    return ok and r or false
end

function Game.GetShopLevel() return Core.GetProp(Game.GetState(), "ShopLevel", nil) end
function Game.GetDay()
    local ok, r = Core.Call(Game.GetState(), "GetDisplayDayNumber")
    return ok and r or nil
end
function Game.IsOpenForBusiness()
    local ok, r = Core.Call(Game.GetBusinessDay(), "IsOpenForBusiness")
    return ok and r or nil
end
function Game.GetCustomers() return Core.FindAll("MenCustomerCharacter") end

function Game.PrintStatus()
    Core.Log("RamenCore", "INFO", string.format("Money=%s ShopLevel=%s Day=%s Open=%s Customers=%d",
        tostring(Game.GetMoney()), tostring(Game.GetShopLevel()), tostring(Game.GetDay()),
        tostring(Game.IsOpenForBusiness()), #Game.GetCustomers()))
end

return Core
