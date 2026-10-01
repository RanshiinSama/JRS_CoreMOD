-- RamenUI P2b: MOD 一覧 + 設定編集パネル (要 RamenCore 0.4.0)
--   F5 : パネルの表示/非表示 (表示中はマウスカーソルが出て、視点/移動入力が止まる)
--   一覧の「⚙ MOD名」ボタン → その MOD の設定画面。数値・ON/OFF・色コードを編集して「保存」。
-- 各ステップの直前に必ずログを書く (落ちた場合、ログの最後の行が原因箇所)
local ok, Core = pcall(require, "RamenCoreLib")
if not ok then print("[RamenUI] RamenCoreLib not found\n") return end

local info = { name = "RamenUI", version = "0.7.0", author = "AIlly", requires = { RamenCore = "0.11.0" },
    description = "MOD一覧・有効/無効切替・設定UI",
    keys = { { key = "F5", desc = "MOD一覧・設定パネルの表示/非表示" } } }
local log = Core.RegisterMod(info)
if not Core.CheckDependencies(info) then return end

local titleKeyText = nil -- 「閉じる (キー)」ボタンの文字 (キー変更時に更新)
local cfg = Core.LoadConfig("RamenUI", { PauseMenuButton = true, ToggleKey = "F5" })
local function closeLabel() return cfg.ToggleKey ~= "" and (" 閉じる (" .. cfg.ToggleKey .. ") ") or " 閉じる " end
Core.RegisterSettings("RamenUI", {
    { key = "PauseMenuButton", type = "boolean", default = "true", restart = true,
      desc = "ポーズメニューに「MOD」ボタンを追加する（変更は再読込または再起動後に反映）" },
    { key = "ToggleKey", type = "key", default = "F5", desc = "この MOD 一覧・設定パネルを開閉するキー" },
})
local function registerInfo()
    info.keys = { { key = cfg.ToggleKey ~= "" and cfg.ToggleKey or "未割当", desc = "MOD一覧・設定パネルの表示/非表示" } }
    Core.RegisterMod(info)
end
registerInfo()
Core.WatchConfig("RamenUI", cfg, function()
    registerInfo()
    if titleKeyText then pcall(function() titleKeyText:SetText(FText(closeLabel())) end) end
end)

local function step(s) log.info("UI step: " .. s) end
local function find(path)
    local o = StaticFindObject(path)
    if o and o:IsValid() then return o end
    return nil
end

local WIDGET_CLASS = "/Script/RealRamenSimulator.MenCommonUserWidget"
local PANEL_WIDTH, PANEL_MAX_HEIGHT = 860.0, 760.0

local COLOR = {
    title  = { R = 1.0, G = 0.85, B = 0.3, A = 1.0 },
    name   = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 },
    desc   = { R = 0.75, G = 0.75, B = 0.75, A = 1.0 },
    keys   = { R = 0.5, G = 0.8, B = 1.0, A = 1.0 },
    error  = { R = 1.0, G = 0.3, B = 0.3, A = 1.0 },
    good   = { R = 0.4, G = 1.0, B = 0.5, A = 1.0 },
    footer = { R = 0.6, G = 0.6, B = 0.6, A = 1.0 },
    btn    = { R = 0.15, G = 0.35, B = 0.6, A = 1.0 },
    btnOn  = { R = 0.15, G = 0.55, B = 0.3, A = 1.0 },
    btnOff = { R = 0.35, G = 0.35, B = 0.35, A = 1.0 },
    sel    = { R = 0.6, G = 0.1, B = 0.1, A = 1.0 },
}

-- 状態
local widget, open, failed = nil, false, false
local chain = 0                -- ポーリング連鎖の世代番号
local uid = 0                  -- ウィジェット名の連番
local buttons = {}             -- { btn=, fn=, pressed=false }
local views = {}               -- 画面 (VerticalBox): views.list, views["設定:MOD名"]
local editors = {}             -- editors[mod] = { key = { item=, kind=, edit=/btn=, txt=, value=, err= } }
local statusText = {}          -- statusText[mod]
local setOpen              -- 前方宣言 (後で定義)

------------------------------------------------------------------ ウィジェット生成ヘルパー
local tree
local function nm(prefix) uid = uid + 1; return FName(prefix .. uid) end

local function text(str, color, wrap)
    local tb = StaticConstructObject(find("/Script/UMG.TextBlock"), tree, nm("T"))
    tb:SetText(FText(str))
    if color then pcall(function() tb:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end) end
    if wrap ~= false then pcall(function() tb:SetAutoWrapText(true) end) end
    return tb
end

local function button(parent, label, onClick, bg)
    local b = StaticConstructObject(find("/Script/UMG.Button"), tree, nm("B"))
    local tb = text(label, nil, false)
    b:AddChild(tb)
    pcall(function() b:SetBackgroundColor(bg or COLOR.btn) end)
    parent:AddChild(b)
    buttons[#buttons + 1] = { btn = b, fn = onClick, pressed = false }
    return b, tb
end

local function vbox() return StaticConstructObject(find("/Script/UMG.VerticalBox"), tree, nm("V")) end

local function showView(name)
    for k, v in pairs(views) do
        pcall(function() v:SetVisibility(k == name and 0 or 1) end) -- 0=Visible 1=Collapsed
    end
end

------------------------------------------------------------------ 設定画面
local function rangeHint(it)
    if it.type == "number" then
        local lo = it.min ~= nil and tostring(it.min) or "-"
        local hi = it.max ~= nil and tostring(it.max) or "-"
        return string.format("(範囲 %s ～ %s%s)", lo, hi, it.integer and "・整数" or "")
    elseif it.type == "color" then
        return "(RRGGBB の16進6桁" .. (it.allowEmpty and "・空欄可" or "") .. ")"
    end
    return ""
end

local function setToggle(e, on)
    e.value = on
    pcall(function() e.txt:SetText(FText(on and "  ON  " or "  OFF  ")) end)
    pcall(function() e.btn:SetBackgroundColor(on and COLOR.btnOn or COLOR.btnOff) end)
end

-- 色の項目: 入力欄の下に「プリセット名 / カスタム / ゲーム標準」を表示
local function updateColorLabel(e, hex)
    if not e.presetLabel then return end
    if e.item.type == "key" then
        local k = tostring(hex or ""):upper()
        pcall(function() e.presetLabel:SetText(FText("    選択中: " .. (k == "" and "なし（キー割り当てを解除）" or k))) end)
        return
    end
    hex = tostring(hex or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^#", "")
    local msg
    if hex == "" then msg = "    選択中: 空欄（色を変更しない）"
    elseif e.item.standard and e.item.standard ~= "" and hex:upper() == e.item.standard:upper() then
        msg = "    選択中: ゲーム標準色 (" .. hex:upper() .. ")"
    else
        local name = Core.ColorName(hex)
        msg = name and ("    選択中: プリセット「" .. name .. "」(" .. hex:upper() .. ")") or ("    選択中: カスタム #" .. hex:upper())
    end
    pcall(function() e.presetLabel:SetText(FText(msg)) end)
end

-- 初期値の表示用文字列
local function defaultText(it)
    local d = it.default or ""
    if it.type == "boolean" then return (d == "true" or d == "1") and "ON" or "OFF" end
    if it.type == "key" then return d == "" and "なし" or d end
    if it.type == "color" then
        if d == "" then return "空欄（ゲーム標準）" end
        local name = Core.ColorName(d)
        return name and (d .. "（" .. name .. "）") or d
    end
    return d == "" and "空欄" or d
end

-- 1項目のコントロールに値(文字列)を入れる
local function applyValue(e, val)
    val = tostring(val or "")
    if e.kind == "boolean" then
        setToggle(e, val == "true" or val == "1")
    else
        pcall(function() e.edit:SetText(FText(val)) end)
        if e.kind == "color" or e.kind == "key" then updateColorLabel(e, val) end
    end
    pcall(function() e.err:SetText(FText(" ")) end)
end

-- ini の現在値をコントロールに反映
local function loadValues(mod)
    local vals = Core.GetSettingsValues(mod)
    for key, e in pairs(editors[mod] or {}) do
        local v = vals[key] or ""
        if e.kind == "boolean" then
            setToggle(e, v == "true" or v == "1")
        else
            pcall(function() e.edit:SetText(FText(v)) end)
            if e.kind == "color" or e.kind == "key" then updateColorLabel(e, v) end
        end
        pcall(function() e.err:SetText(FText(" ")) end)
    end
end

local function setStatus(mod, str, color)
    local st = statusText[mod]
    if not st then return end
    pcall(function() st:SetText(FText(str)); st:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 }) end)
end

local function save(mod)
    local vals = {}
    for key, e in pairs(editors[mod]) do
        if e.kind == "boolean" then vals[key] = e.value and "true" or "false"
        else vals[key] = e.edit:GetText():ToString() end
    end
    local okS, errs, restartKeys = Core.SaveSettings(mod, vals)
    for key, e in pairs(editors[mod]) do
        pcall(function() e.err:SetText(FText(errs[key] and ("  ! " .. errs[key]) or " ")) end)
    end
    if okS then
        local msg = "保存しました。1秒以内に反映されます。"
        if #restartKeys > 0 then msg = "保存しました。次の項目は再起動後に反映: " .. table.concat(restartKeys, ", ") end
        setStatus(mod, msg, COLOR.good)
        for key, e in pairs(editors[mod]) do if e.kind == "color" or e.kind == "key" then updateColorLabel(e, vals[key]) end end
        log.info("saved settings for " .. mod)
    else
        setStatus(mod, errs._file or "入力エラーがあります。赤字の項目を直してください。", COLOR.error)
    end
end

-- 設定項目のフォームを v (詳細画面の VerticalBox) に追加する
local function buildSettingsForm(mod, schema, v)
    v:AddChild(text("設定", COLOR.title))
    editors[mod] = {}
    for _, it in ipairs(schema) do
        local label = it.key .. (it.restart and "  [再起動後に反映]" or "")
        v:AddChild(text(label, COLOR.name))
        local hint = it.desc
        local rh = rangeHint(it)
        if rh ~= "" then hint = hint .. "  " .. rh end
        v:AddChild(text("    " .. hint, COLOR.desc))
        v:AddChild(text("    初期値: " .. defaultText(it), COLOR.footer))
        local e = { item = it, kind = it.type }
        if it.type == "boolean" then
            e.btn, e.txt = button(v, "  OFF  ", function() setToggle(e, not e.value) end, COLOR.btnOff)
        else
            if it.type == "key" then
                v:AddChild(text("    入力できるキー: " .. Core.KeyHelp() .. "（空欄=未割り当て）", COLOR.footer))
            end
            if it.type == "color" then
                -- プリセット8色のボタン。4個ずつ2行に並べる (1行だと右端がパネルからはみ出す)。押すと下の入力欄にその色コードが入る
                local function newRow()
                    local hb = StaticConstructObject(find("/Script/UMG.HorizontalBox"), tree, nm("H"))
                    v:AddChild(hb)
                    return hb
                end
                local hb
                for i, p in ipairs(Core.ColorPresets) do
                    if (i - 1) % 4 == 0 then hb = newRow() end
                    local lin = Core.HexToLinear(p.hex)
                    local b, tb = button(hb, " " .. p.name .. " ", function()
                        pcall(function() e.edit:SetText(FText(p.hex)) end)
                        pcall(function() e.err:SetText(FText(" ")) end)
                        updateColorLabel(e, p.hex)
                    end, lin)
                    -- 明るい色は文字を黒に (読みやすさ)
                    if lin and (lin.R * 0.3 + lin.G * 0.6 + lin.B * 0.1) > 0.35 then
                        pcall(function() tb:SetColorAndOpacity({ SpecifiedColor = { R = 0, G = 0, B = 0, A = 1 }, ColorUseRule = 0 }) end)
                    end
                end
                -- 「標準色」: ゲーム本来のアウトライン色の色コードを入れる (標準色が未登録の項目は空欄=変更しない)
                if (it.standard and it.standard ~= "") or it.allowEmpty then
                    local std = it.standard or ""
                    button(hb, (std ~= "" and " ゲーム標準色 " or " 空欄(変更しない) "), function()
                        pcall(function() e.edit:SetText(FText(std)) end)
                        pcall(function() e.err:SetText(FText(" ")) end)
                        updateColorLabel(e, std)
                    end, COLOR.btnOff)
                end
            end
            e.edit = StaticConstructObject(find("/Script/UMG.EditableTextBox"), tree, nm("E"))
            v:AddChild(e.edit)
            if it.type == "color" or it.type == "key" then
                e.presetLabel = text("    選択中: -", COLOR.keys, false)
                v:AddChild(e.presetLabel)
            end
        end
        -- 初期値に戻す (キーは「なし(解除)」も)。保存するまでは ini に反映されない
        local rr = StaticConstructObject(find("/Script/UMG.HorizontalBox"), tree, nm("H"))
        v:AddChild(rr)
        button(rr, "  初期値に戻す  ", function() applyValue(e, it.default) end)
        if it.type == "key" then
            button(rr, "  なし(解除)  ", function() applyValue(e, "") end)
        end
        e.err = text(" ", COLOR.error)
        v:AddChild(e.err)
        editors[mod][it.key] = e
    end
    local row = StaticConstructObject(find("/Script/UMG.HorizontalBox"), tree, nm("H"))
    v:AddChild(row)
    button(row, "  保存  ", function() save(mod) end, COLOR.btnOn)
    button(row, "  元に戻す(再読込)  ", function() loadValues(mod); setStatus(mod, "保存済みの値を読み込みました。", COLOR.footer) end)
    statusText[mod] = text(" ", COLOR.footer)
    v:AddChild(statusText[mod])
end

------------------------------------------------------------------ 一覧画面
local listStatus

-- 有効/無効ボタンを v に追加する。ロック対象のMODはボタンではなくラベル。onChange(want) は切替後に呼ばれる
local function toggleRow(v, name, enabled, loaded, onChange)
    local hb = StaticConstructObject(find("/Script/UMG.HorizontalBox"), tree, nm("H"))
    v:AddChild(hb)
    if Core.LockedMods[name] then
        hb:AddChild(text(" [必須] 無効にできません ", COLOR.footer, false))
        return hb
    end
    local e = { value = enabled }
    local function paint()
        pcall(function() e.txt:SetText(FText(e.value and "  有効  " or "  無効  ")) end)
        pcall(function() e.btn:SetBackgroundColor(e.value and COLOR.btnOn or COLOR.btnOff) end)
    end
    e.btn, e.txt = button(hb, "  有効  ", function()
        local want = not e.value
        if Core.SetModEnabled(name, want) then
            e.value = want
            paint()
            if onChange then pcall(onChange, want) end
            local msg = want and "次回起動から有効になります。" or "無効にしました。ゲーム中は機能を停止し、次回起動から読み込まれません。"
            if not loaded and want then msg = "次回起動から読み込まれます。" end
            pcall(function() listStatus:SetText(FText(name .. ": " .. msg)); listStatus:SetColorAndOpacity({ SpecifiedColor = COLOR.good, ColorUseRule = 0 }) end)
            log.info("mod " .. name .. " enabled=" .. tostring(want))
        else
            pcall(function() listStatus:SetText(FText(name .. ": mods.txt を書き換えられませんでした")); listStatus:SetColorAndOpacity({ SpecifiedColor = COLOR.error, ColorUseRule = 0 }) end)
        end
    end)
    paint()
    return hb
end

-- 「MOD再読込」: パネルを閉じ(入力モードを戻し)、画面から外してから、再読込を要求する。
-- パネルを開いたまま再読込すると、カーソル表示/操作停止のまま持ち主が消えて、操作できなくなるため。
local reloadArmed = false

local function doReload()
    log.info("reload requested from UI")
    setOpen(false)
    pcall(function() if widget and widget:IsValid() then widget:RemoveFromParent() end end)
    widget = nil
    ExecuteWithDelay(800, function()
        if not Core.RequestReload() then log.error("could not write reload stamp") end
    end)
end

-- 2ペインの本体: 左=MOD一覧(選択)、右=選んだMODの詳細と設定。タイトル行に「閉じる」「MOD再読込」。
local LEFT_WIDTH, RIGHT_WIDTH, BODY_HEIGHT = 400.0, 900.0, 600.0
local selectBtns = {}   -- selectBtns[name] = { btn=, base= }
local selected = nil

local function paintSelection()
    for name, s in pairs(selectBtns) do
        pcall(function() s.btn:SetBackgroundColor(name == selected and COLOR.sel or COLOR.btnOff) end)
    end
end

local function selectMod(name)
    selected = name
    -- 入力欄は空で作られるので、選ぶたびに保存済みの値を読み込む (空のまま「保存」すると値が消えるため)
    if editors[name] then
        loadValues(name)
        setStatus(name, " ", COLOR.footer)
    end
    showView("mod:" .. name)
    paintSelection()
end

local function hbox(parent)
    local hb = StaticConstructObject(find("/Script/UMG.HorizontalBox"), tree, nm("H"))
    parent:AddChild(hb)
    return hb
end

local function sized(parent, w, h)
    local sb = StaticConstructObject(find("/Script/UMG.SizeBox"), tree, nm("S"))
    pcall(function() sb:SetWidthOverride(w) end)
    pcall(function() sb:SetHeightOverride(h) end)
    parent:AddChild(sb)
    return sb
end

local function scrollIn(sb)
    local sc = StaticConstructObject(find("/Script/UMG.ScrollBox"), tree, nm("SC"))
    sb:SetContent(sc)
    return sc
end

-- ロゴ画像 (assets/logo.png) を表示する。ゲームの Texture として実行時に読み込み、Image ウィジェットに貼る。
-- 読み込めなかったときは、色データ (logo_data.lua) を小さな四角で並べた代替表示にする
local LOGO_SIZE = 240.0
local LOGO_CELL = 4.0

local function addLogoPixels(parent)
    local okL, data = pcall(require, "logo_data")
    if not (okL and type(data) == "table" and data.rows and data.palette) then return end
    local lin = {}
    for i, hex in ipairs(data.palette) do lin[i - 1] = Core.HexToLinear(hex) end
    local col = vbox()
    parent:AddChild(col)
    for _, row in ipairs(data.rows) do
        local hb = StaticConstructObject(find("/Script/UMG.HorizontalBox"), tree, nm("H"))
        col:AddChild(hb)
        for c, n in row:gmatch("(%d+):(%d+)") do
            local sb = StaticConstructObject(find("/Script/UMG.SizeBox"), tree, nm("S"))
            local bd = StaticConstructObject(find("/Script/UMG.Border"), tree, nm("BD"))
            pcall(function() sb:SetWidthOverride(tonumber(n) * LOGO_CELL) end)
            pcall(function() sb:SetHeightOverride(LOGO_CELL) end)
            pcall(function() bd:SetBrushColor(lin[tonumber(c)]) end)
            sb:SetContent(bd)
            hb:AddChild(sb)
        end
    end
end

-- assets/logo.dat は、画像を単純に XOR で崩したもの (PNG のまま置かないための難読化。暗号ではない)。
-- 元に戻して一時ファイルに書き、ゲームに読み込ませたらすぐ消す
local LOGO_KEY = { 0x5A, 0xC3, 0x17, 0x9E, 0x6B, 0xD1, 0x2F, 0x84, 0x39, 0xE7, 0x4D }
local function decodeLogo(src, dst)
    local f = io.open(src, "rb")
    if not f then return false end
    local s = f:read("*a"); f:close()
    local n, kn = #s, #LOGO_KEY
    local parts, buf, bi = {}, {}, 0
    for i = 1, n do
        bi = bi + 1
        buf[bi] = string.byte(s, i) ~ LOGO_KEY[(i - 1) % kn + 1]
        if bi == 4096 then parts[#parts + 1] = string.char(table.unpack(buf, 1, bi)); bi = 0 end
    end
    if bi > 0 then parts[#parts + 1] = string.char(table.unpack(buf, 1, bi)) end
    local o = io.open(dst, "wb")
    if not o then return false end
    o:write(table.concat(parts)); o:close()
    return true
end

local function addLogo(parent)
    local pc = Core.GetPlayerController()
    local dir = Core.ModsDir .. "/RamenUI/assets/"
    local tmp = dir .. "~logo.tmp.png"
    step("load logo image")
    local tex
    local okI, res = pcall(function()
        if not decodeLogo(dir .. "logo.dat", tmp) then error("logo.dat not readable") end
        local krl = find("/Script/Engine.Default__KismetRenderingLibrary")
        return krl:ImportFileAsTexture2D(pc, tmp)
    end)
    pcall(os.remove, tmp)
    if okI and res and res:IsValid() then tex = res end
    if not tex then
        log.warn("logo image not loaded (" .. tostring(okI and "no texture" or res) .. "); using pixel fallback")
        return addLogoPixels(parent)
    end
    local img = StaticConstructObject(find("/Script/UMG.Image"), tree, nm("IM"))
    pcall(function() img:SetBrushFromTexture(tex, false) end)
    local sb = StaticConstructObject(find("/Script/UMG.SizeBox"), tree, nm("S"))
    pcall(function() sb:SetWidthOverride(LOGO_SIZE) end)
    pcall(function() sb:SetHeightOverride(LOGO_SIZE) end)
    sb:SetContent(img)
    -- 縦並びの入れ物にそのまま入れると横に引き伸ばされる。横並び(HorizontalBox)に入れて、指定サイズのまま表示する
    local hb = StaticConstructObject(find("/Script/UMG.HorizontalBox"), tree, nm("H"))
    parent:AddChild(hb)
    hb:AddChild(sb)
end

local function buildMain(outer, schemaAll)
    -- タイトル行
    local top = hbox(outer)
    top:AddChild(text(" MOD 一覧・設定   ", COLOR.title, false))
    local _, closeTxt = button(top, closeLabel(), function() setOpen(false) end)
    titleKeyText = closeTxt
    local reloadBtn, reloadTxt
    local function setReloadLabel(s, bg)
        pcall(function() reloadTxt:SetText(FText(s)) end)
        pcall(function() reloadBtn:SetBackgroundColor(bg) end)
    end
    reloadBtn, reloadTxt = button(top, "  MOD再読込  ", function()
        if not Core.IsAutoReloadEnabled() then
            pcall(function()
                listStatus:SetText(FText("再読込できません: UE4SS-settings.ini の EnableAutoReloadingLuaMods を 1 にして、ゲームを再起動してください"))
                listStatus:SetColorAndOpacity({ SpecifiedColor = COLOR.error, ColorUseRule = 0 })
            end)
            return
        end
        if not reloadArmed then
            reloadArmed = true
            setReloadLabel("  もう一度押すと全MODを再読込  ", COLOR.error)
            ExecuteWithDelay(5000, function()
                ExecuteInGameThread(function() reloadArmed = false; setReloadLabel("  MOD再読込  ", COLOR.btn) end)
            end)
        else
            reloadArmed = false
            doReload()
        end
    end)
    listStatus = text(" ", COLOR.footer)
    outer:AddChild(listStatus)

    -- 本体
    local body = hbox(outer)
    local left = scrollIn(sized(body, LEFT_WIDTH, BODY_HEIGHT))
    local right = scrollIn(sized(body, RIGHT_WIDTH, BODY_HEIGHT))
    selectBtns, selected = {}, nil

    local list = Core.GetModList()
    local enabledMap, registered = {}, {}
    for _, t in ipairs(Core.GetModsTxt()) do enabledMap[t.name] = t.enabled end
    local first

    local function addLeft(name, label)
        local tb
        local b
        b, tb = button(left, label, function() selectMod(name) end, COLOR.btnOff)
        selectBtns[name] = { btn = b, txt = tb, label = label }
        first = first or name
    end

    for _, m in ipairs(list) do
        registered[m.name] = true
        local en = enabledMap[m.name]
        if en == nil then en = true end
        local base = string.format(" %s  v%s ", m.name, m.version)
        addLeft(m.name, en and base or (base .. "(無効)"))

        local v = vbox()
        v:AddChild(text(string.format("%s   v%s   by %s", m.name, m.version, m.author), COLOR.title))
        if m.description ~= "" then v:AddChild(text(m.description, COLOR.desc)) end
        if #m.keys > 0 then
            for _, k in ipairs(m.keys) do v:AddChild(text(string.format("[%s]  %s", k.key, k.desc), COLOR.keys)) end
        end
        if m.errors ~= "" then v:AddChild(text("! 依存エラー: " .. m.errors, COLOR.error)) end
        v:AddChild(text(" ", nil, false))
        if m.name == "RamenCore" then
            -- 「製作者」ボタン: 押すたびに、ロゴと製作者名の表示/非表示を切り替える
            local credit = vbox()
            pcall(function() credit:SetVisibility(1) end) -- 1=Collapsed
            local shown = false
            button(v, "  製作者  ", function()
                shown = not shown
                pcall(function() credit:SetVisibility(shown and 0 or 1) end)
            end)
            v:AddChild(credit)
            credit:AddChild(text(" ", nil, false))
            pcall(addLogo, credit)
            credit:AddChild(text("製作: " .. m.author, COLOR.title, false))
            v:AddChild(text(" ", nil, false))
        end
        toggleRow(v, m.name, en, true, function(want)
            local s = selectBtns[m.name]
            if s then pcall(function() s.txt:SetText(FText(want and base or (base .. "(無効)"))) end) end
        end)
        v:AddChild(text(" ", nil, false))
        local schema = schemaAll[m.name]
        if schema and #schema > 0 then
            buildSettingsForm(m.name, schema, v)
        else
            v:AddChild(text("この MOD に編集できる設定はありません。", COLOR.footer))
        end
        views["mod:" .. m.name] = v
        right:AddChild(v)
    end

    -- 起動時に無効だった Ramen 系 MOD (未読み込み)。次回起動からの有効化だけできる
    local unloaded = 0
    for _, t in ipairs(Core.GetModsTxt()) do
        if not registered[t.name] and t.name:match("^Ramen") then
            unloaded = unloaded + 1
            addLeft(t.name, " " .. t.name .. "  (未読込) ")
            local v = vbox()
            v:AddChild(text(t.name .. "   (未読み込み)", COLOR.title))
            v:AddChild(text("起動時に無効だったため読み込まれていません。有効にすると、次回起動から読み込まれます。", COLOR.desc))
            v:AddChild(text(" ", nil, false))
            toggleRow(v, t.name, t.enabled, false)
            views["mod:" .. t.name] = v
            right:AddChild(v)
        end
    end
    outer:AddChild(text(string.format("%d 個の MOD が読み込まれています%s", #list,
        unloaded > 0 and string.format("（未読み込み %d 個）", unloaded) or ""), COLOR.footer))
    return first
end

------------------------------------------------------------------ 入力モード (カーソル表示/操作停止)
-- 他のUI(ポーズメニュー等)が既に開いているか。開いている間は、入力モード(カーソル/操作停止)は
-- そのUIが管理しているので、こちらは触らない。(触ると、閉じたときに「ゲーム操作」に戻ってしまい、
-- ポーズメニューが開いたまま視点や移動が効いてしまう)
local function otherUiActive(pc)
    if Core.GetProp(pc, "bShowMouseCursor", false) then return true end
    local pw = Core.FindFirst("MenPauseMenuWidget")
    return pw ~= nil and Core.GetProp(pw, "bIsActive", false) == true
end

local inputApplied = false -- こちらが入力モードを変更したか (閉じるときに元に戻すかどうか)

local function setInputMode(on)
    local pc = Core.GetPlayerController()
    if not pc then return end
    local lib = find("/Script/UMG.Default__WidgetBlueprintLibrary")
    local function try(label, fn)
        local okc, err = pcall(fn)
        if not okc then log.warn("UI " .. label .. " failed: " .. tostring(err)) end
    end
    if on then
        if otherUiActive(pc) then
            inputApplied = false
            step("input mode: unchanged (other UI is active)")
            return
        end
        inputApplied = true
        step("input mode on")
        try("bShowMouseCursor", function() pc.bShowMouseCursor = true end)
        try("SetIgnoreLookInput", function() pc:SetIgnoreLookInput(true) end)
        try("SetIgnoreMoveInput", function() pc:SetIgnoreMoveInput(true) end)
        try("SetInputMode_GameAndUIEx", function() lib:SetInputMode_GameAndUIEx(pc, widget, 0, false, false) end)
    else
        if not inputApplied then step("input mode: unchanged") return end
        inputApplied = false
        step("input mode off")
        try("bShowMouseCursor", function() pc.bShowMouseCursor = false end)
        try("SetIgnoreLookInput", function() pc:SetIgnoreLookInput(false) end)
        try("SetIgnoreMoveInput", function() pc:SetIgnoreMoveInput(false) end)
        try("SetInputMode_GameOnly", function() lib:SetInputMode_GameOnly(pc, false) end)
    end
end

-- ホットリロード(Ctrl+R)で Lua 環境が作り直されると、画面に残った古いパネルは持ち主を失う。
-- ルートの SizeBox 名 "RamenUIRoot" で探して、画面から外す。
local function removeOrphans()
    local removed = 0
    for _, sb in ipairs(FindAllOf("SizeBox") or {}) do
        if sb:IsValid() and sb:GetFName():ToString():find("RamenUIRoot", 1, true) then
            pcall(function()
                local w = sb:GetOuter():GetOuter() -- SizeBox -> WidgetTree -> UserWidget
                if w and w:IsValid() then w:RemoveFromParent(); removed = removed + 1 end
            end)
        end
    end
    if removed > 0 then step("removed orphan panels: " .. removed) end
end

------------------------------------------------------------------ 構築
-- 画面サイズ (UMGの単位 = 画面ピクセル / DPI倍率)。取得できないときは、やや小さめの固定値
local builtAvail = nil -- パネルを作ったときの画面サイズ (変わっていたら作り直す)
local function viewportUnits(pc)
    local availW, availH = 1600.0, 900.0
    pcall(function()
        local wl = find("/Script/UMG.Default__WidgetLayoutLibrary")
        local size = wl:GetViewportSize(pc)
        local scale = wl:GetViewportScale(pc)
        if size and size.X and size.X > 0 and scale and scale > 0 then
            availW, availH = size.X / scale, size.Y / scale
        end
    end)
    return availW, availH
end

local function build()
    local pc = Core.GetPlayerController()
    if not pc then log.warn("no PlayerController") return false end
    local lib = find("/Script/UMG.Default__WidgetBlueprintLibrary")
    local cls = find(WIDGET_CLASS)
    if not (lib and cls) then log.error("library/class not found") return false end

    removeOrphans()
    step("Create widget")
    local w = lib:Create(pc, cls, pc)
    tree = Core.GetProp(w, "WidgetTree", nil)
    if not (w and w:IsValid() and tree and tree:IsValid()) then log.error("create failed") return false end
    buttons, views, editors, statusText, uid = {}, {}, {}, {}, 0

    step("construct SizeBox / Border / VerticalBox")
    local sizeBox = StaticConstructObject(find("/Script/UMG.SizeBox"), tree, FName("RamenUIRoot"))
    local border = StaticConstructObject(find("/Script/UMG.Border"), tree, nm("BD"))
    local outer = vbox()
    pcall(function() border:SetBrushColor({ R = 0.03, G = 0.03, B = 0.03, A = 0.98 }) end)
    pcall(function() border:SetPadding({ Left = 18.0, Top = 14.0, Right = 18.0, Bottom = 14.0 }) end)

    -- 画面サイズに合わせてパネルの大きさを決める (UMGの単位 = 画面ピクセル / DPI倍率)。
    -- 取得できないときは、やや小さめの固定値にする
    local availW, availH = viewportUnits(pc)
    builtAvail = availW .. "x" .. availH
    local panelW = math.max(900.0, math.min(availW - 160.0, 1800.0))
    local panelH = math.max(480.0, math.min(availH - 100.0, 950.0))
    LEFT_WIDTH = 400.0
    RIGHT_WIDTH = panelW - LEFT_WIDTH - 60.0
    BODY_HEIGHT = panelH - 150.0
    log.info(string.format("UI layout: avail=%.0fx%.0f panel=%.0fx%.0f", availW, availH, panelW, panelH))

    step("build main view")
    local first = buildMain(outer, Core.GetSettingsSchema())

    step("assemble")
    border:SetContent(outer)
    sizeBox:SetContent(border)
    Core.SetProp(tree, "RootWidget", sizeBox)
    step("AddToViewport")
    w:AddToViewport(100)
    pcall(function() w:SetPositionInViewport({ X = math.max(10.0, (availW - panelW) / 2), Y = math.max(10.0, (availH - panelH) / 2) }, false) end)
    widget = w
    if first then selectMod(first) end
    step("built (" .. #buttons .. " buttons)")
    return true
end

------------------------------------------------------------------ ボタン押下の監視 (開いている間だけ)
local function poll(my)
    if my ~= chain or not open then return end
    ExecuteInGameThread(function()
        if my ~= chain or not open then return end
        if not (widget and widget:IsValid()) then return end
        local okp, err = pcall(function()
            for _, b in ipairs(buttons) do
                local now = b.btn:IsPressed()
                if now and not b.pressed then
                    local okf, e = pcall(b.fn)
                    if not okf then log.error("button error: " .. tostring(e)) end
                end
                b.pressed = now
            end
        end)
        if not okp then log.error("poll error: " .. tostring(err)) end
        ExecuteWithDelay(50, function() poll(my) end)
    end)
end

setOpen = function(v)
    open = v
    Core.SetUiOpen(v) -- 開いている間は、他MODのキー割り当てを無効にする
    if widget then widget:SetVisibility(open and 0 or 1) end
    setInputMode(open)
    chain = chain + 1
    if open then poll(chain) end
    step("open=" .. tostring(open))
end


local function toggle()
    if failed then log.warn("previous build failed; restart game") return end
    -- ステージ切替などで破棄された古いウィジェットには触らない
    if widget and not widget:IsValid() then
        step("stale widget dropped")
        widget, open = nil, false
    end
    -- 解像度が変わっていたら、パネルを作り直す (大きさは作成時の画面サイズで決めているため)
    if widget and not open then
        local pc = Core.GetPlayerController()
        if pc then
            local w, h = viewportUnits(pc)
            if builtAvail ~= (w .. "x" .. h) then
                step("viewport changed: rebuild")
                pcall(function() widget:RemoveFromParent() end)
                widget = nil
            end
        end
    end
    if not widget then
        local okb, res = pcall(build)
        if not okb or not res then failed = true; log.error("build failed: " .. tostring(res)) return end
    end
    setOpen(not open)
end

-- ステージ(ワールド)が切り替わるとウィジェットは破棄される。参照を捨てて、次の F5 で作り直す。
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
    widget, open = nil, false
    Core.SetUiOpen(false)
    chain = chain + 1
    log.info("world changed: widget reference cleared")
end, function() end)

Core.BindKey(function() return cfg.ToggleKey end, function()
    ExecuteInGameThread(function()
        local okt, e = pcall(toggle)
        if not okt then log.error("toggle error: " .. tostring(e)) end
    end)
end, { always = true }) -- パネルを開いていても閉じられるように

-- P5: ポーズメニューの「MOD」ボタン。失敗しても F5 のパネルには影響しないよう pcall で読み込む
if cfg.PauseMenuButton then
    local okPB, PB = pcall(require, "pause_button")
    if okPB then
        local okI, e = pcall(PB, Core, log, { open = function()
            local okt, err = pcall(toggle) -- 押すたびに開閉
            if not okt then log.error("toggle from pause button failed: " .. tostring(err)) end
        end })
        if not okI then log.warn("pause_button init failed: " .. tostring(e)) end
    else
        log.warn("pause_button load failed: " .. tostring(PB))
    end
end

Core.SetUiOpen(false) -- 前回の異常終了などで「開いている」印が残っていても解除する
log.info("RamenUI ready: " .. (cfg.ToggleKey ~= "" and cfg.ToggleKey or "(no key)") .. " = MOD list / settings")
