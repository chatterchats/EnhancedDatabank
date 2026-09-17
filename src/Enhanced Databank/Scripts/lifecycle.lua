-- Enhanced Databank: lifecycle.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: categories, actions, common, databank_ui, folder_ui, lifecycle, logging, pool_authority, runtime, state.
return function(ctx)
    function ctx.lifecycle.activate_supported_page(page)
        return ctx.categories.activate(page)
    end

    -- The CharacterBank Blueprint packages are not necessarily loaded when UE4SS
    -- starts on a cold game launch. RegisterHook cannot hook a Blueprint UFunction
    -- before that UFunction exists, so install these lifecycle hooks lazily once the
    -- cooked CharacterBank functions appear. This is intentionally a lightweight
    -- object-existence poll and shuts itself off once both hooks are installed.
    ctx.state.decorate_current_character_rows = function(reason)
        ctx.logging.log("Move Character row rescan suppressed for stability: reason=" .. tostring(reason))
        return false
    end

    local MASTER_ACTIVATED_PATH = "/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/WBP_CharacterBank_Master.WBP_CharacterBank_Master_C:BP_OnActivated"

    local PAGE_ACTIVATED_PATH = "/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/WBP_CharacterBank_Page_CharacterList.WBP_CharacterBank_Page_CharacterList_C:BP_OnActivated"

    local CHARACTER_CLICKED_PATH = "/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/WBP_CharacterBank_CreatedCharacterItem.WBP_CharacterBank_CreatedCharacterItem_C:BP_OnClicked"

    local FOLDER_CLICKED_PATH = "/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/WBP_CharacterBank_CreatedCharacterFolder.WBP_CharacterBank_CreatedCharacterFolder_C:BP_OnClicked"

    local master_hook_installed = false

    local page_hook_installed = false

    -- The release exposes no per-row Move controls, so their click/rescan hooks are
    -- intentionally treated as satisfied and are never registered.
    local character_click_hook_installed = true

    local folder_click_hook_installed = true

    local lifecycle_retry_active = true

    local lifecycle_retry_count = 0

    local function live_master_available()
        local master = ctx.common.find_first("WBP_CharacterBank_Master_C")
        if master == nil then return false end
        local identity = ctx.common.object_name(master)
        return string.find(identity, "/Engine/Transient", 1, true) ~= nil
    end

    local function live_supported_page_available()
        local master = ctx.common.find_first("WBP_CharacterBank_Master_C")
        if master == nil then return false end
        local page = select(1, ctx.common.read_property(master, "OtherCharacterList"))
        if page == nil then
            page = select(1, ctx.common.read_property(master, "AstromechCharacterList"))
        end
        return ctx.categories.for_page(page) ~= nil
    end

    local function install_master_activation_hook()
        if master_hook_installed then return true, nil end
        -- RegisterHook on a not-yet-loaded Blueprint UFunction causes UE4SS to print
        -- a full exception/stack trace even when pcall catches it. Avoid calling it
        -- at all until a live CharacterBank master exists; by then the generated
        -- Blueprint class/UFunction is resident and hook registration is safe.
        if not live_master_available() then
            return false, "live master not loaded"
        end

        local ok, hook_id = pcall(function()
            return ctx.runtime:register_hook(MASTER_ACTIVATED_PATH, function(context, ...)
                local master = ctx.common.unwrap(context)
                local identity = ctx.common.object_name(master)
                if string.find(identity, "/Engine/Transient", 1, true) then
                    ctx.logging.log("Character Databank master activated; scheduling authoritative UI rebuild.")
                    ctx.databank_ui.schedule_refresh("Databank master BP_OnActivated", 140)
                end
            end)
        end)

        if ok and hook_id ~= nil then
            master_hook_installed = true
            ctx.logging.log("Hooked Character Databank master BP_OnActivated (lazy-safe installer).")
            return true, nil
        end
        return false, tostring(hook_id)
    end

    local function install_page_activation_hook()
        if page_hook_installed then return true, nil end
        -- Same rationale as the master hook: require the live supported page before
        -- asking UE4SS to register the Blueprint override hook. This keeps cold-start
        -- lazy installation silent instead of generating an expected stack trace.
        if not live_supported_page_available() then
            return false, "live supported page not loaded"
        end

        local ok, hook_id = pcall(function()
            return ctx.runtime:register_hook(PAGE_ACTIVATED_PATH, function(context, ...)
                local page = ctx.common.unwrap(context)
                if ctx.lifecycle.activate_supported_page(page) then
                    ctx.logging.log("Character Databank page BP_OnActivated; scheduling authoritative UI rebuild.")
                    ctx.databank_ui.schedule_refresh("supported page BP_OnActivated", 120)
                end
            end)
        end)

        if ok and hook_id ~= nil then
            page_hook_installed = true
            ctx.logging.log("Hooked supported page BP_OnActivated (lazy-safe installer).")
            return true, nil
        end
        return false, tostring(hook_id)
    end

    local function live_pool_item_available()
        local page, databank_vm = ctx.databank_ui.resolve_live_page()
        if page == nil or databank_vm == nil then return false end
        local stock_widget = select(1, ctx.common.read_property(page, "CharacterPool"))
        return stock_widget ~= nil
    end

    local function live_character_row_available()
        local page = select(1, ctx.databank_ui.resolve_live_page())
        if page == nil then return false end
        local stock_widget = select(1, ctx.common.read_property(page, "CharacterPool"))
        if stock_widget == nil then return false end
        local stack = select(1, ctx.common.read_property(stock_widget, "BitReactorStackBox_25"))
        return ctx.common.panel_child_at(stack, 0) ~= nil
    end

    local function install_character_clicked_hook()
        if character_click_hook_installed then return true, nil end
        if not live_character_row_available() then
            return false, "live Character row not loaded"
        end
        local ok, hook_id = pcall(function()
            return ctx.runtime:register_hook(CHARACTER_CLICKED_PATH, function(context, ...)
                local row = ctx.common.unwrap(context)
                if row == nil then return end
                local info = ctx.state.folder_ui_state.moveRowActions
                    and ctx.state.folder_ui_state.moveRowActions[ctx.common.object_name(row)] or nil
                if info == nil then return end

                -- The transfer affordance is intentionally a lightweight row-owned
                -- hit zone instead of a nested CommonUI UserWidget. This avoids the
                        -- 20+ Blueprint button constructions that previously crashed while still
                -- letting every row show its action persistently.
                local over_transfer = false
                local hitbox = ctx.common.unwrap(info.hitbox)
                if hitbox ~= nil then
                    pcall(function() over_transfer = hitbox:IsHovered() == true end)
                end
                if not over_transfer then return end

                ctx.folder_ui.schedule_move_character_dialog(info, "row BP_OnClicked fallback")
            end)
        end)
        if ok and hook_id ~= nil then
            character_click_hook_installed = true
            ctx.logging.log("Hooked Character Databank row BP_OnClicked for lightweight transfer hit-zones.")
            return true, nil
        end
        return false, tostring(hook_id)
    end

    local function install_folder_clicked_hook()
        if folder_click_hook_installed then return true, nil end
        if not live_pool_item_available() then
            return false, "live Character Pool widget not loaded"
        end
        local ok, hook_id = pcall(function()
            return ctx.runtime:register_hook(FOLDER_CLICKED_PATH, function(context, ...)
                -- Re-scan only after the native collapse/expand click has unwound.
                -- This does not rebuild folders or rows; it merely decorates any row
                -- UObjects the native folder regenerated while expanding.
                ctx.actions.run_on_game_thread_after(80, function()
                    if ctx.state.decorate_current_character_rows ~= nil then
                        ctx.state.decorate_current_character_rows("folder expand/collapse")
                    end
                end)
            end)
        end)
        if ok and hook_id ~= nil then
            folder_click_hook_installed = true
            ctx.logging.log("Hooked Character Databank folder BP_OnClicked for post-expand transfer decoration.")
            return true, nil
        end
        return false, tostring(hook_id)
    end

    ctx.lifecycle.attempt_install_databank_lifecycle_hooks = nil

    ctx.lifecycle.attempt_install_databank_lifecycle_hooks = function(reason)
        if not lifecycle_retry_active then return end
        lifecycle_retry_count = lifecycle_retry_count + 1

        local had_master = master_hook_installed
        local had_page = page_hook_installed
        local had_character_click = character_click_hook_installed
        local had_folder_click = folder_click_hook_installed
        local master_ok, master_err = install_master_activation_hook()
        local page_ok, page_err = install_page_activation_hook()
        local character_ok, character_err = install_character_clicked_hook()
        local folder_ok, folder_err = install_folder_clicked_hook()

        if lifecycle_retry_count == 1 then
            if not master_ok then ctx.logging.log("Master BP_OnActivated deferred: " .. tostring(master_err)) end
            if not page_ok then ctx.logging.log("Page BP_OnActivated deferred: " .. tostring(page_err)) end
            if not character_ok then ctx.logging.log("Character row click hook deferred: " .. tostring(character_err)) end
            if not folder_ok then ctx.logging.log("Folder click hook deferred: " .. tostring(folder_err)) end
        end

        local installed_now = (not had_master and master_hook_installed)
            or (not had_page and page_hook_installed)
            or (not had_character_click and character_click_hook_installed)
            or (not had_folder_click and folder_click_hook_installed)

        if installed_now then
            ctx.logging.log("Databank lifecycle hook(s) became available during " .. tostring(reason)
                .. "; waiting for a fully initialized live Databank page before catch-up render.")
            local catchup_attempts = 0
            local function try_catchup()
                catchup_attempts = catchup_attempts + 1
                -- If BP_OnActivated or the native CommonUI fallback already queued a
                -- render, a second catch-up pass would destroy/recreate every custom
                -- pool immediately after the first. Earlier logs showed exactly that
                -- duplicate cold-entry render. Let the activation-owned request win.
                if ctx.databank_ui.refresh_generation > 0 then
                    ctx.logging.log("Late-hook catch-up suppressed: activation render already scheduled.")
                    ctx.actions.api.cancel_group(
                        "lifecycle_hook_install",
                        "activation render already scheduled"
                    )
                    return
                end
                local page, databank_vm = ctx.databank_ui.resolve_live_page()
                if page ~= nil and databank_vm ~= nil then
                    local stock_widget = select(1, ctx.common.read_property(page, "CharacterPool"))
                    local stock_stack = stock_widget and select(1, ctx.common.read_property(stock_widget, "BitReactorStackBox_25")) or nil
                    local stock_children = ctx.common.panel_child_count(stock_stack)
                    local authority = ctx.pool_authority.authoritative_pool_state()
                    local extra_vms = authority and ctx.pool_authority.collect_extra_pool_vms(databank_vm, authority) or nil
                    local custom_ready = true
                    if authority and extra_vms then
                        for _, pool_name_value in ipairs(authority.custom_order or {}) do
                            if extra_vms[pool_name_value] == nil then custom_ready = false; break end
                        end
                    end

                    -- On a cold load the page UObject can exist before its stock
                    -- CharacterPool has finished native/MDViewModel initialization.
                    -- Wait until stock rows exist and all authoritative custom pool
                    -- VMs are discoverable before the first catch-up render.
                    if stock_stack ~= nil and stock_children ~= nil and stock_children > 0
                        and authority ~= nil and custom_ready then
                        ctx.logging.log("Late-hook catch-up page ready after " .. tostring(catchup_attempts)
                            .. " attempt(s); stockRows=" .. tostring(stock_children)
                            .. "; scheduling authoritative render.")
                        ctx.databank_ui.schedule_refresh("late lifecycle hook install", 120)
                        return
                    end
                end
                if catchup_attempts < 20 then
                    ctx.actions.api.run_group_after(
                        "lifecycle_hook_install",
                        100,
                        try_catchup
                    )
                else
                    ctx.logging.log("Late-hook catch-up skipped: live Databank page was not fully initialized; normal BP_OnActivated hook will render on entry.")
                end
            end
            ctx.actions.api.run_group_after(
                "lifecycle_hook_install",
                100,
                try_catchup
            )
        end

        if master_hook_installed and page_hook_installed and character_click_hook_installed and folder_click_hook_installed then
            lifecycle_retry_active = false
            ctx.logging.log("Databank lifecycle hooks fully installed after " .. tostring(lifecycle_retry_count)
                .. " attempt(s); stopping late-hook retry loop.")
            return
        end

        ctx.actions.api.run_group_after("lifecycle_hook_install", 400, function()
            if lifecycle_retry_active then
                ctx.lifecycle.attempt_install_databank_lifecycle_hooks("deferred Blueprint load")
            end
        end)
    end

    function ctx.lifecycle.hook_native_refresh(path, label)
        local ok, pre_id, post_id = pcall(function()
            return ctx.runtime:register_hook(path,
                function(context, ...) end,
                function(context, ...)
                    ctx.logging.log(label .. " completed; scheduling authoritative UI rebuild.")
                    ctx.databank_ui.schedule_refresh(label, 120)
                end)
        end)
        if ok and pre_id ~= nil then
            ctx.logging.log("Hooked native refresh source: " .. label)
        else
            ctx.logging.log("Native refresh hook unavailable for " .. label .. ": " .. tostring(pre_id))
        end
    end
end
