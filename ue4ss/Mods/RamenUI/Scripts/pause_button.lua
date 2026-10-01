-- RamenUI P5: ポーズメニューに「MOD」ボタンを追加する。
-- ポーズメニュー(WBP_Men_Pause_C)は VerticalBox_74 の中に WBP_Men_PauseButton_C が縦に8個並んでいる。
-- 同じ種類のボタンをもう1つ作って、ラベルを「MOD」にし、入れ物に追加する (InsertChildAt は使えないため末尾)。
-- 押されたら api.open() (RamenUI のパネルを開く) を呼ぶ。
-- ポーズメニューはゲーム本体のステージにしか無い (タイトル画面には無い) ので、見つかるまで1秒ごとに再試行する。
-- 各ステップの直前に必ずログを書く (落ちた場合、ログの最後の行が原因箇所)
return function(Core, log, api)
    local LABEL = "MOD"
    local READY_DELAY_MS = 3000
    local MAX_TRIES = 180            -- 見つからない場合は3分で諦める (ステージ切替でやり直し)
    local function find(path)
        local o = StaticFindObject(path)
        if o and o:IsValid() then return o end
        return nil
    end

    local epoch = 0
    local pauseWidget, btn = nil, nil
    local pressed = false
    local warnedPressed = false
    local tries = 0

    local function textOf(w)
        local okt, t = pcall(function() return Core.GetProp(w, "Label", nil):ToString() end)
        return okt and t or nil
    end

    -- ポーズメニュー(ゲームのステージ中は常駐)に、MODボタンを追加する。既に追加済み(再読込など)なら再利用する。
    -- verbose のときだけ、各ステップをログに出す (再試行のたびにログが増えないように)
    local function inject(verbose)
        local function step(s) if verbose then log.info("PB step: " .. s) end end
        step("find pause widget")
        local pw = Core.FindFirst("MenPauseMenuWidget")
        if not pw then step("pause widget not found (retrying)") return false end
        local ref = Core.GetProp(pw, "Button_Settings", nil)
        if not Core.IsValid(ref) then step("Button_Settings not found") return false end
        local okp, box = pcall(function() return ref:GetParent() end)
        if not (okp and box and box:IsValid()) then step("button container not found") return false end

        step("scan children")
        local n = box:GetChildrenCount()
        for i = 0, n - 1 do
            local c = box:GetChildAt(i)
            if c and c:IsValid() and textOf(c) == LABEL then
                log.info("PB reuse existing button at " .. i)
                pauseWidget, btn = pw, c
                return true
            end
        end

        log.info("PB create button (container children=" .. n .. ")")
        local pc = Core.GetPlayerController()
        local lib = find("/Script/UMG.Default__WidgetBlueprintLibrary")
        local nb = lib:Create(pc, ref:GetClass(), pc)
        if not (nb and nb:IsValid()) then log.warn("PB create failed") return true end -- 失敗は再試行しない (無限ループ防止)

        -- 追加(構築)より前に設定したラベルは、初期化で空に戻されるため、追加した後で設定する
        log.info("PB AddChild")
        box:AddChild(nb)
        local function setLabel()
            pcall(function() nb:SetLabel(FText(LABEL)) end)
            pcall(function() nb.Label = FText(LABEL) end)
            pcall(function() nb.Button_Label:SetText(FText(LABEL)) end)
        end
        log.info("PB SetLabel (after AddChild)")
        setLabel()
        -- 念のため少し後にも設定する (構築が遅れて空に戻された場合の保険)
        ExecuteWithDelay(500, function() ExecuteInGameThread(function() if Core.IsValid(nb) then setLabel() end end) end)
        pauseWidget, btn = pw, nb
        log.info(string.format("PB injected: children=%d visibility=%s", box:GetChildrenCount(), tostring(Core.GetProp(nb, "Visibility", "?"))))
        return true
    end

    -- 追加とクリック監視の連鎖。デリゲートは Lua から束縛できないため IsPressed をポーリングする。
    --   ・未追加の間: 1秒ごとに追加を試す (最大 MAX_TRIES 回)
    --   ・追加後: ポーズメニューが開いている間だけ 0.1 秒間隔、閉じている間は 0.5 秒間隔
    local function tick(my)
        if my ~= epoch then return end
        ExecuteInGameThread(function()
            if my ~= epoch then return end
            local delay = 500
            local keepGoing = true
            local okp, err = pcall(function()
                if not (Core.IsValid(pauseWidget) and Core.IsValid(btn)) then
                    pauseWidget, btn = nil, nil
                    tries = tries + 1
                    if tries > MAX_TRIES then keepGoing = false; log.warn("PB gave up (pause menu not found)") return end
                    delay = 1000
                    inject(tries <= 2)
                    return
                end
                if Core.GetProp(pauseWidget, "bIsActive", false) then
                    delay = 100
                    local okq, now = pcall(function() return btn:IsPressed() end)
                    if not okq then
                        if not warnedPressed then warnedPressed = true; log.warn("PB IsPressed failed: " .. tostring(now)) end
                        return
                    end
                    if now and not pressed then
                        log.info("PB clicked")
                        api.open()
                    end
                    pressed = now
                else
                    pressed = false
                end
            end)
            if not okp then log.error("PB tick error: " .. tostring(err)) end
            if keepGoing then ExecuteWithDelay(delay, function() tick(my) end) end
        end)
    end

    -- ステージ開始(ClientRestart)の数秒後から、追加を試みる。ステージが変わるたびにやり直す。
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
        epoch = epoch + 1
        pauseWidget, btn, pressed, tries = nil, nil, false, 0
    end, function()
        local my = epoch
        ExecuteWithDelay(READY_DELAY_MS, function() tick(my) end)
    end)

    -- 再読込された場合: ステージ開始は来ないので、その場で始める
    if Core.IsReload() then
        local my = epoch
        ExecuteWithDelay(2000, function() tick(my) end)
    end

    log.info("PB ready (pause menu button)")
end
