-- Enhanced Databank: startup.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: actions, common, config, databank_ui, folder_ui, lifecycle, logging, runtime.
return function(ctx)
    ctx.actions.api.cancel_all("mod script reloaded")

    ctx.folder_ui.install_folder_button_click_hook()

    ctx.folder_ui.install_action_hover_hooks()

    -- Native CommonUI is resident at startup; Blueprint hooks are installed only
    -- after a relevant live widget activates. Both sources share one request.
    for _, event in ipairs({ "ActivateWidget", "DeactivateWidget" }) do
        local callback = event == "ActivateWidget" and ctx.lifecycle.on_widget_activated
            or ctx.lifecycle.on_widget_deactivated
        local ok, id = pcall(function()
            return ctx.runtime:register_hook(
                "/Script/CommonUI.CommonActivatableWidget:" .. event,
                function() end,
                function(context) callback(context, "native CommonUI " .. event) end)
        end)
        if ok and id ~= nil then
            ctx.logging.log("Hooked native CommonUI " .. event .. " fallback.")
        else
            ctx.logging.log("CommonUI " .. event .. " hook unavailable: " .. tostring(id))
        end
    end

    ctx.actions.run_on_game_thread_after(0, function()
        ctx.runtime:cleanup_ui()
        ctx.lifecycle.recover_open_databank()
    end)

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
    -- reconciles Default-row visibility if the native VM or widgets stay stale.
    ctx.lifecycle.hook_native_refresh("/Script/BitReactorGame.BitReactorCharacterPoolManager:MoveCharacterToAnotherPool", "PoolManager.MoveCharacterToAnotherPool")

    ctx.lifecycle.hook_native_refresh("/Script/BitReactorGame.BitReactorCharacterPoolManager:RenamePlayerCreatedCharacterPool", "PoolManager.RenamePlayerCreatedCharacterPool")

    ctx.lifecycle.hook_native_refresh("/Script/BitReactorGame.BitReactorCharacterPoolManager:DeletePlayerCreatedCharacterPool", "PoolManager.DeletePlayerCreatedCharacterPool")

    ctx.logging.log("Loaded v" .. ctx.config.VERSION .. ". Deferred work uses UE4SS owned delayed game-thread actions, including a retriggerable refresh handle; no legacy async timers or hover polling remain. MOVE uses the stable manager-direct native mutation. Refreshes reconcile Default rows by authoritative GUID and keep one visible copy; the shipping list is never regenerated. Custom pools render once per native mutation: no ViewModel convergence retry loop and no generated per-row context replay. The selected-row lookup remains click-only; no per-character widgets or manual save writes.")

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
