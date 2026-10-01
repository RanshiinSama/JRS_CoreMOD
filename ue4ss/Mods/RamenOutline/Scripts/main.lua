-- RamenOutline: フォーカス時アウトラインの色/太さ変更 + コップの常時アウトライン (要 RamenCore)
-- 設定: Mods/RamenCore/Configs/RamenOutline.ini
--   OutlineColor        アウトライン色 (16進 RRGGBB, 空欄=ゲーム標準)
--   BuildOutlineColor   建築モード時の色 (空欄=ゲーム標準)
--   OutlineThickness    太さ (0=ゲーム標準の 4.0)
--   CupAlwaysOutline    常時アウトライン全体の ON/OFF (切替キーでも変更)
--   IncludeCup          コップに常時アウトラインを付ける
--   IncludeBeerMug      ビールジョッキに常時アウトラインを付ける
--   IncludeWaterBottle  ウォーターボトルに常時アウトラインを付ける
--   ToggleKey は F9 で 常時アウトライン(コップ) の ON/OFF
local ok, Core = pcall(require, "RamenCoreLib")
if not ok then print("[RamenOutline] RamenCoreLib not found\n") return end

local info = { name = "RamenOutline", version = "0.4.0", author = "AIlly", requires = { RamenCore = "0.11.0" },
    description = "アウトラインの色・太さ変更とコップの常時アウトライン",
    keys = { { key = "F9", desc = "コップの常時アウトライン ON/OFF" } } }
local log = Core.RegisterMod(info)
if not Core.CheckDependencies(info) then return end

local cfg = Core.LoadConfig("RamenOutline", {
    OutlineColor = "71FF51",
    BuildOutlineColor = "FAFF51",
    OutlineThickness = 4.0,
    CupAlwaysOutline = true,
    IncludeCup = true,
    IncludeBeerMug = false,
    IncludeWaterBottle = false,
    ApplyIntervalMs = 1000,
    ToggleKey = "F9",
})

-- 一覧に表示するキー説明を、現在の割り当てで登録し直す
local function registerInfo()
    info.keys = { { key = cfg.ToggleKey ~= "" and cfg.ToggleKey or "未割当", desc = "コップの常時アウトライン ON/OFF" } }
    Core.RegisterMod(info)
end
registerInfo()

-- sRGB(16進) -> リニアRGB (マテリアルのベクターパラメータはリニア)
local function srgbToLinear(c)
    if c <= 0.04045 then return c / 12.92 end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function parseColor(hex)
    hex = tostring(hex or ""):gsub("^#", "")
    if not hex:match("^%x%x%x%x%x%x$") then return nil end
    local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
    return { R = srgbToLinear(r / 255), G = srgbToLinear(g / 255), B = srgbToLinear(b / 255), A = 1.0 }
end

local color = parseColor(cfg.OutlineColor)
local buildColor = parseColor(cfg.BuildOutlineColor)
if cfg.OutlineColor ~= "" and not color then log.warn("OutlineColor is invalid (use RRGGBB): " .. cfg.OutlineColor) end

-- アウトライン用のマテリアルインスタンス (パラメータを持つもの) にパラメータを反映
local dbgTicks = 0
local function step(s) if dbgTicks <= 2 then log.info("step: " .. s) end end

-- 1つのMIDにアウトラインのパラメータを反映 (パラメータ名は FName で渡す。文字列だとクラッシュする)
local function applyToMid(mid, label)
    if cfg.OutlineThickness > 0 then
        Core.Call(mid, "SetScalarParameterValue", FName("OutlineThickness"), cfg.OutlineThickness)
    end
    if color then Core.Call(mid, "SetVectorParameterValue", FName("OutlineColor"), color) end
    if buildColor then Core.Call(mid, "SetVectorParameterValue", FName("OutlineColorBuilding"), buildColor) end
    pcall(function()
        mid.VectorParameterValues:ForEach(function(i, e)
            local x = e:get()
            if x.ParameterInfo.Name:ToString() == "OutlineColor" then
                step(string.format("%s readback OutlineColor R=%.3f G=%.3f B=%.3f", label,
                    x.ParameterValue.R, x.ParameterValue.G, x.ParameterValue.B))
            end
        end)
    end)
end

local function applyOutline()
    -- (1) 名前の分かっているトランジェントのMID
    local mid = StaticFindObject("/Engine/Transient.MID_M_PP_Men_InteractOutline1_0")
    if mid and mid:IsValid() then applyToMid(mid, "transient") end
    -- (2) ゲームがフォーカスアウトラインとして保持しているMID (MenBuildModeComponent)
    local bm = Core.FindFirst("MenBuildModeComponent")
    local mid2 = Core.GetProp(bm, "FocusOutlineDynamicMaterial", nil)
    if Core.IsValid(mid2) then applyToMid(mid2, "buildmode") end
end

local cupOutline = cfg.CupAlwaysOutline
local cupClasses
local function buildCupClasses()
    cupClasses = {}
    if cfg.IncludeCup then cupClasses[#cupClasses + 1] = "MenWaterCupActor" end
    if cfg.IncludeBeerMug then cupClasses[#cupClasses + 1] = "MenBeerMugActor" end
    if cfg.IncludeWaterBottle then cupClasses[#cupClasses + 1] = "MenWaterBottleActor" end
end
buildCupClasses()

-- アクターが持つ全ての描画コンポーネント (PrimitiveComponent: 静的/スケルタル/インスタンス等) を返す
local primClass
local function getMeshes(actor)
    primClass = primClass or StaticFindObject("/Script/Engine.PrimitiveComponent")
    local list = {}
    if primClass and primClass:IsValid() then
        local okc, comps = pcall(function() return actor:K2_GetComponentsByClass(primClass) end)
        if okc and comps then
            pcall(function()
                comps:ForEach(function(_, e)
                    local c = e:get()
                    if c and c:IsValid() then list[#list + 1] = c end
                end)
            end)
        end
    end
    if #list == 0 then
        local m = Core.GetProp(actor, "MeshComponent", nil)
        if Core.IsValid(m) then list[1] = m end
    end
    return list
end

-- 積み重ね(MenActorStackComponent.Stack.Entries)のメンバーアクターを返す
local function getStackMembers(actor)
    local res = {}
    pcall(function()
        local comp = actor.ActorStackComponent
        if not (comp and comp:IsValid()) then return end
        comp.Stack.Entries:ForEach(function(_, e)
            local a = e:get().Actor
            if a and a:IsValid() then res[#res + 1] = a end
        end)
    end)
    return res
end

local function outlineActor(a, tag)
    local meshes = getMeshes(a)
    local kinds = {}
    for _, mesh in ipairs(meshes) do
        kinds[#kinds + 1] = mesh:GetClass():GetFName():ToString()
        if not Core.GetProp(mesh, "bRenderCustomDepth", false) then
            Core.Call(mesh, "SetCustomDepthStencilValue", 1)
            Core.Call(mesh, "SetRenderCustomDepth", true)
        end
    end
    step(string.format("%s %s comps=%d [%s]", tag, a:GetFName():ToString(), #meshes, table.concat(kinds, ",")))
end

-- コップ(と積み重ねメンバー)にカスタムデプス(ステンシル1)を設定 = フォーカス時と同じアウトラインが常時出る
local function applyCups()
    if not cupOutline then return end
    for _, cn in ipairs(cupClasses) do
        for _, cup in ipairs(Core.FindAll(cn)) do
            outlineActor(cup, "cup")
            local members = getStackMembers(cup)
            if #members > 0 then step("stack members=" .. #members) end
            for _, m in ipairs(members) do outlineActor(m, "member") end
        end
    end
end

-- 常時アウトラインを切る時は元に戻す(フォーカス中のものはゲーム側が再設定する)
local function clearCups(classes)
    for _, cn in ipairs(classes or cupClasses) do
        for _, cup in ipairs(Core.FindAll(cn)) do
            local all = { cup }
            for _, m in ipairs(getStackMembers(cup)) do all[#all + 1] = m end
            for _, a in ipairs(all) do
                for _, mesh in ipairs(getMeshes(a)) do Core.Call(mesh, "SetRenderCustomDepth", false) end
            end
        end
    end
end

-- タイトル/ロード中は一切動かない。常駐スレッド(LoopAsync)も使わない。
-- プレイヤー出現(ClientRestart)の READY_DELAY_MS 後から、ExecuteWithDelay の連鎖で ApplyIntervalMs ごとに処理する。
-- ステージが変わる(epoch が変わる)と古い連鎖は自然に止まる。
local READY_DELAY_MS = 5000
local active, epoch = false, 0

local wasEnabled = true
local function tick(my)
    if my ~= epoch then return end -- 古い連鎖は終了
    ExecuteInGameThread(function()
        if my ~= epoch then return end
        dbgTicks = dbgTicks + 1
        local enabled = Core.IsEnabled("RamenOutline")
        local okp, e = pcall(function()
            if enabled then step("outline"); applyOutline(); step("cups"); applyCups(); step("done")
            elseif wasEnabled then clearCups() end -- 無効化された瞬間に、コップの常時アウトラインを外す
        end)
        wasEnabled = enabled
        if not okp then log.error(e) end
        ExecuteWithDelay(cfg.ApplyIntervalMs, function() tick(my) end)
    end)
end

RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    active = false
    epoch = epoch + 1
    log.info("hook: ClientRestart pre")
end, function()
    local my = epoch
    log.info("hook: ClientRestart post")
    ExecuteWithDelay(READY_DELAY_MS, function()
        if my == epoch then active = true; log.info("active=true"); tick(my) end
    end)
end)

-- ホットリロード(Ctrl+R)された場合: ステージ切替(ClientRestart)が起きないので、その場で動き始める
if Core.IsReload() then
    ExecuteWithDelay(2000, function()
        active = true
        log.info("reload detected (clock=" .. string.format("%.0f", Core.LoadClock()) .. "s): active=true")
        tick(epoch)
    end)
end

Core.BindKey(function() return cfg.ToggleKey end, function()
    if not Core.IsEnabled("RamenOutline") then log.info("RamenOutline is disabled") return end
    cupOutline = not cupOutline
    log.info("Cup outline: " .. (cupOutline and "ON" or "OFF"))
    if active and not cupOutline then ExecuteInGameThread(clearCups) end
end)

-- 設定UI用のスキーマと、ini変更の監視 (UIが保存すると1秒以内に反映される)
Core.RegisterSettings("RamenOutline", {
    { key = "OutlineColor", type = "color", allowEmpty = true, default = "71FF51", standard = "71FF51",
      desc = "アウトライン色。下のボタンで選ぶか、RRGGBB を直接入力 (空欄=ゲーム標準。空欄への変更は再起動後に反映)" },
    { key = "BuildOutlineColor", type = "color", allowEmpty = true, default = "FAFF51", standard = "FAFF51",
      desc = "建築モードのアウトライン色。ボタンで選ぶか、RRGGBB を直接入力 (空欄=ゲーム標準)" },
    { key = "OutlineThickness", type = "number", min = 0, max = 20, default = "4.0",
      desc = "アウトラインの太さ (0=変更しない。ゲーム標準は4)" },
    { key = "CupAlwaysOutline", type = "boolean", default = "true",
      desc = "常時アウトライン全体のON/OFF（切替キーでも変更可）。ONのとき、下の各項目で選んだものに付く" },
    { key = "IncludeCup", type = "boolean", default = "true", desc = "コップに常時アウトラインを付ける" },
    { key = "IncludeBeerMug", type = "boolean", default = "false", desc = "ビールジョッキに常時アウトラインを付ける" },
    { key = "IncludeWaterBottle", type = "boolean", default = "false", desc = "ウォーターボトルに常時アウトラインを付ける" },
    { key = "ApplyIntervalMs", type = "number", integer = true, min = 200, max = 5000, default = "1000",
      desc = "反映処理の間隔 (ミリ秒)" },
    { key = "ToggleKey", type = "key", default = "F9", desc = "コップの常時アウトラインを ON/OFF するキー" },
})
Core.WatchConfig("RamenOutline", cfg, function()
    registerInfo()
    color = parseColor(cfg.OutlineColor)
    buildColor = parseColor(cfg.BuildOutlineColor)
    local wasOutline = cupOutline
    local prev = cupClasses
    cupOutline = cfg.CupAlwaysOutline
    buildCupClasses()
    if not active then return end
    -- 常時アウトラインを切った場合は、これまでの全対象から外す。
    -- 一部の対象だけ外した場合(ジョッキ/ボトルのオフ)は、外れたクラスだけ元に戻す。
    local removed = {}
    if wasOutline and not cupOutline then
        removed = prev
    else
        local now = {}
        for _, c in ipairs(cupClasses) do now[c] = true end
        for _, c in ipairs(prev) do if not now[c] then removed[#removed + 1] = c end end
    end
    if #removed > 0 then clearCups(removed) end
end)

log.info("RamenOutline ready: color=" .. tostring(cfg.OutlineColor) .. " thickness=" .. cfg.OutlineThickness ..
    " cupAlways=" .. tostring(cupOutline) .. " (" .. cfg.ToggleKey .. " toggles cup outline)")
