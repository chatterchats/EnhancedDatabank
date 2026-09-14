-- Enhanced Databank: startup.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: actions, common, config, databank_ui, folder_ui, lifecycle, logging, runtime.
return function(ctx)
    ctx.actions.run_on_game_thread_after(0, function() ctx.runtime:cleanup_ui() end)

    ctx.actions.api.cancel_all("mod script reloaded")

    ctx.folder_ui.install_folder_button_click_hook()

    ctx.folder_ui.install_action_hover_hooks()

    ctx.actions.api.cancel_group(
        "lifecycle_hook_install",
        "lifecycle installer restarted"
    )

    ctx.lifecycle.attempt_install_databank_lifecycle_hooks("initial mod load")

    -- Native CommonUI activation is the fallback that should fire even when a
    -- Blueprint override is skipped/reused. Filter immediately to the actual live
    -- humanoid Character Databank page before doing any Databank work.
    local common_hook_ok, common_pre_id, common_post_id = pcall(function()
        return ctx.runtime:register_hook(
            "/Script/CommonUI.CommonActivatableWidget:ActivateWidget",
            function(context, ...) end,
            function(context, ...)
                local widget = ctx.common.unwrap(context)
                if ctx.lifecycle.page_is_humanoid(widget) then
                    ctx.logging.log("Native CommonUI ActivateWidget observed for humanoid Databank page; scheduling authoritative UI rebuild.")
                    ctx.databank_ui.schedule_refresh("native CommonUI ActivateWidget", 120)
                end
            end
        )
    end)

    if common_hook_ok and common_pre_id ~= nil then
        ctx.logging.log("Hooked native CommonUI ActivateWidget fallback.")
    else
        ctx.logging.log("CommonUI ActivateWidget hook unavailable: " .. tostring(common_pre_id))
    end

    -- Databank-VM mutations still matter for stock game / Character Share paths.
    ctx.lifecycle.hook_native_refresh("/Script/Bruno.BrunoCharacterDatabankViewModel:CreatePool", "DatabankVM.CreatePool")

    ctx.lifecycle.hook_native_refresh("/Script/Bruno.BrunoCharacterDatabankViewModel:RenamePool", "DatabankVM.RenamePool")

    ctx.lifecycle.hook_native_refresh("/Script/Bruno.BrunoCharacterDatabankViewModel:DeletePool", "DatabankVM.DeletePool")

    -- Character deletion does not necessarily delete its containing folder.
    -- Rebuild custom rows after either native deletion surface has unwound.
    ctx.lifecycle.hook_native_refresh("/Script/Bruno.BrunoCharacterDatabankViewModel:DeletePoolCharacter", "DatabankVM.DeletePoolCharacter")

    ctx.lifecycle.hook_native_refresh("/Script/BitReactorGame.BitReactorCharacterPoolManager:RemoveCharacterFromPool", "PoolManager.RemoveCharacterFromPool")

    ctx.lifecycle.hook_native_refresh("/Script/Bruno.BrunoCharacterDatabankViewModel:MovePoolCharacterToPool", "DatabankVM.MovePoolCharacterToPool")

    -- Both mutation surfaces remain observable for stock game paths and other mods.
    -- Enhanced Databank uses the manager-direct move that proved stable, then
    -- performs only a one-row visibility correction if the Default VM stays stale.
    ctx.lifecycle.hook_native_refresh("/Script/BitReactorGame.BitReactorCharacterPoolManager:MoveCharacterToAnotherPool", "PoolManager.MoveCharacterToAnotherPool")

    ctx.lifecycle.hook_native_refresh("/Script/BitReactorGame.BitReactorCharacterPoolManager:RenamePlayerCreatedCharacterPool", "PoolManager.RenamePlayerCreatedCharacterPool")

    ctx.lifecycle.hook_native_refresh("/Script/BitReactorGame.BitReactorCharacterPoolManager:DeletePlayerCreatedCharacterPool", "PoolManager.DeletePlayerCreatedCharacterPool")

    ctx.logging.log("Loaded v" .. ctx.config.VERSION .. ". Deferred work uses UE4SS owned delayed game-thread actions, including a retriggerable refresh handle; no legacy async timers or hover polling remain. MOVE uses the stable manager-direct native mutation and performs at most one targeted Default-row visibility correction. Custom pools render once per native mutation: no ViewModel convergence retry loop and no generated per-row context replay. The selected-row lookup remains click-only; no per-character widgets or manual save writes.")

    ctx.logging.log("On Databank activation and native pool mutations it rebuilds visible folders from authoritative CharacterPoolManager ownership.")

    if ctx.logging.LOG_PATH then ctx.logging.log("Dedicated log: " .. ctx.logging.LOG_PATH) end

    if ctx.logging.source_resolution_note then ctx.logging.log(ctx.logging.source_resolution_note) end

    require("debug_keybinds").install({
        register = function(...) return ctx.runtime:register_keybind(...) end,
        log = ctx.logging.log,
        refresh = function()
            ctx.actions.run_on_game_thread_after(0, function() ctx.databank_ui.refresh_visible_pools("manual Shift+F7") end)
        end,
        restore = function()
            ctx.actions.run_on_game_thread_after(0, ctx.databank_ui.restore_stock_only)
        end,
    })
end
