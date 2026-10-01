-- RamenCore: 前提MOD本体。共通ライブラリは Mods/shared/RamenCoreLib.lua
local Core = require("RamenCoreLib")

-- 新規起動のときだけ、MOD登録・設定スキーマの記録を空にする (再読込で一部のMODだけ読み直されても、他の登録を消さない)
if not Core.IsReload() then
    Core.ResetLog() -- 起動ごとにログをまっさらにする
    Core.ResetRegistry()
    Core.ResetSettingsSchema()
end
Core.TrackWorld() -- ステージ開始時にゲームの起動時刻を記録 (Core.IsReload() の判定用)
Core.RegisterMod({ name = "RamenCore", version = Core.Version, author = "AIlly",
    description = "全MOD共通の前提ライブラリ（登録・設定・ログ・ゲーム状態取得）",
    keys = { { key = "F6", desc = "ゲーム状態をログに出力" } } })
Core.Config = Core.LoadConfig("RamenCore", { DebugCommands = true, StatusKey = "F6" })
Core.RegisterSettings("RamenCore", {
    { key = "DebugCommands", type = "boolean", default = "true", restart = true, desc = "デバッグ用コンソールコマンドを有効にする（変更は再起動後に反映）" },
    { key = "StatusKey", type = "key", default = "F6", desc = "ゲーム状態をログに出力するキー" },
})

local function registerInfo()
    Core.RegisterMod({ name = "RamenCore", version = Core.Version, author = "AIlly",
        description = "全MOD共通の前提ライブラリ（登録・設定・ログ・ゲーム状態取得）",
        keys = { { key = Core.Config.StatusKey ~= "" and Core.Config.StatusKey or "未割当", desc = "ゲーム状態をログに出力" } } })
end
registerInfo()
Core.BindKey(function() return Core.Config.StatusKey end, function() ExecuteInGameThread(Core.Game.PrintStatus) end)
Core.WatchConfig("RamenCore", Core.Config, registerInfo)

if Core.Config.DebugCommands then
    RegisterConsoleCommandHandler("ramen_mods", function() Core.ListMods() return true end)
    RegisterConsoleCommandHandler("ramen_dump", function(_, params)
        if params[1] then Core.DumpClass(params[1]) end
        return true
    end)
end

Core.Log("RamenCore", "INFO", string.format("RamenCore %s ready (load clock=%.0fs%s)", Core.Version, Core.LoadClock(), Core.IsReload() and ", RELOAD" or ""))
