-- RamenMoney: 所持金の追加と設定 (要 RamenCore)
--  F7 : 所持金を AddAmount だけ増やす
--  F8 : 所持金を SetAmount に変更する (増減どちらも可)
local ok, Core = pcall(require, "RamenCoreLib")
if not ok then print("[RamenMoney] RamenCoreLib not found\n") return end

local info = { name = "RamenMoney", version = "0.5.0", author = "AIlly", requires = { RamenCore = "0.11.0" },
    description = "所持金の追加と、指定額への変更",
    keys = { { key = "F7", desc = "所持金を追加 (AddAmount)" }, { key = "F8", desc = "所持金を指定額に変更 (SetAmount)" } } }
local log = Core.RegisterMod(info)
if not Core.CheckDependencies(info) then return end

local MAX_MONEY = 9999999

local cfg = Core.LoadConfig("RamenMoney", {
    AddAmount = 10000,   -- AddKey (初期 F7) で増える額
    SetAmount = 100000,  -- SetKey (初期 F8) で設定する所持金
    AddKey = "F7",
    SetKey = "F8",
})

-- 一覧に表示するキー説明を、現在の割り当てで登録し直す
local function registerInfo()
    local function kn(k) return k ~= "" and k or "未割当" end
    info.keys = { { key = kn(cfg.AddKey), desc = "所持金を追加 (AddAmount)" }, { key = kn(cfg.SetKey), desc = "所持金を指定額に変更 (SetAmount)" } }
    Core.RegisterMod(info)
end
registerInfo()

-- 範囲外(手動でiniを編集した場合など)でも安全な値にする
local function clampMoney(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > MAX_MONEY then return MAX_MONEY end
    return v
end

Core.BindKey(function() return cfg.AddKey end, function()
    ExecuteInGameThread(function()
        if not Core.IsEnabled("RamenMoney") then log.info("RamenMoney is disabled") return end
        local amount = clampMoney(cfg.AddAmount)
        if Core.Game.AddMoney(amount) then
            log.info("Money +" .. amount .. " -> " .. tostring(Core.Game.GetMoney()))
        else
            log.warn("AddMoney failed (GameState not found or function call error)")
        end
    end)
end)

Core.BindKey(function() return cfg.SetKey end, function()
    ExecuteInGameThread(function()
        if not Core.IsEnabled("RamenMoney") then log.info("RamenMoney is disabled") return end
        local amount = clampMoney(cfg.SetAmount)
        if Core.Game.SetMoney(amount) then
            log.info("Money set to " .. amount .. " -> " .. tostring(Core.Game.GetMoney()))
        else
            log.warn("SetMoney failed (GameState not found or function call error)")
        end
    end)
end)

-- 設定UI用のスキーマと、ini変更の監視 (cfg は in-place で更新されるので、使う側は毎回 cfg.X を読めば最新)
Core.RegisterSettings("RamenMoney", {
    { key = "AddAmount", type = "number", integer = true, min = 0, max = MAX_MONEY, default = "10000",
      desc = "お金追加キーで増えるお金の額" },
    { key = "SetAmount", type = "number", integer = true, min = 0, max = MAX_MONEY, default = "100000",
      desc = "所持金変更キーで設定する所持金の額（今の所持金をこの値に変更する）" },
    { key = "AddKey", type = "key", default = "F7", desc = "所持金を追加するキー" },
    { key = "SetKey", type = "key", default = "F8", desc = "所持金を指定額に変更するキー" },
})
Core.WatchConfig("RamenMoney", cfg, registerInfo)

log.info("RamenMoney ready: " .. cfg.AddKey .. "=add, " .. cfg.SetKey .. "=set")
