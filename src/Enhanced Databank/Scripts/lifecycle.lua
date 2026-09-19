-- Enhanced Databank: activation-owned lifecycle initialization.
-- Context: actions, categories, common, databank_ui, lifecycle, logging, pool_authority, runtime, state.
return function(ctx)
    local MASTER_CLASS = "WBP_CharacterBank_Master_C"
    local PAGE_CLASS = "WBP_CharacterBank_Page_CharacterList_C"
    local MASTER_PATH = "/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/WBP_CharacterBank_Master.WBP_CharacterBank_Master_C:BP_OnActivated"
    local PAGE_PATH = "/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/WBP_CharacterBank_Page_CharacterList.WBP_CharacterBank_Page_CharacterList_C:BP_OnActivated"
    local MASTER_DEACTIVATED_PATH = MASTER_PATH:gsub(":BP_OnActivated$", ":BP_OnDeactivated")
    local PAGE_DEACTIVATED_PATH = PAGE_PATH:gsub(":BP_OnActivated$", ":BP_OnDeactivated")
    local GROUP = "lifecycle_hook_install"
    local MAX_ATTEMPTS = 20
    local MAX_ENTRY_ATTEMPTS = 6
    local master_hook_installed, page_hook_installed = false, false
    local installed = {}
    local request = nil

    ctx.state.decorate_current_character_rows = function(reason)
        ctx.logging.log("Move Character row rescan suppressed for stability: reason=" .. tostring(reason))
        return false
    end

    -- CommonUI fires for every menu. Inspect only its supplied context here: no
    -- global searches, reflected widget-tree reads, or timers for unrelated UI/CDOs.
    local function widget_kind(widget)
        if not ctx.common.uobject_is_valid(widget) then return nil end
        local identity = ctx.common.object_name(widget)
        if not identity:find(" /Engine/Transient.", 1, true) then return nil end
        if identity:sub(1, #MASTER_CLASS + 1) == MASTER_CLASS .. " " then
            return "master"
        end
        if identity:sub(1, #PAGE_CLASS + 1) == PAGE_CLASS .. " " then
            local category = ctx.categories.for_page(widget)
            if category then return "page", category end
        end
    end

    local function master_is_visible(master)
        if not ctx.common.uobject_is_valid(master) then return false, "master unavailable/invalid" end
        if widget_kind(master) ~= "master" then
            return false, "not a runtime master: " .. ctx.common.object_name(master)
        end
        -- CommonUI stacks derive from UWidget, not UPanelWidget. Their displayed
        -- content need not have a panel parent or be directly in the viewport.
        -- Neither GetParent():IsValid() nor IsInViewport() is an entry prerequisite.
        -- Avoid master:IsActivated() too: Character Share observed native AVs
        -- during transition. Stable identity plus page/tree/VM readiness follows.
        local visible, err = ctx.common.try_call(function() return master:IsVisible() end)
        if err ~= nil then return false, "master visibility unavailable: " .. tostring(err) end
        if visible ~= true then return false, "master not visible: " .. tostring(visible) end
        return true
    end

    local function is_active(widget)
        if widget_kind(widget) == "master" then return master_is_visible(widget) end
        return ctx.common.uobject_is_valid(widget)
            and select(1, ctx.common.try_call(function() return widget:IsActivated() end)) == true
    end

    local function retire_request(reason)
        request = nil -- Dispatched callbacks must fail ownership even if cancel loses a race.
        ctx.actions.api.cancel_group(GROUP, reason)
    end

    local function install_hook(path, label, callback)
        if installed[path] then return true end
        local ok, id = pcall(function()
            return ctx.runtime:register_hook(path, function(context)
                callback(context, label)
            end)
        end)
        if ok and id ~= nil then
            installed[path] = true
            ctx.logging.log("Hooked " .. label .. " on Databank activation.")
            return true
        end
        return false
    end

    local function install_hooks(master, page)
        -- Live instances prove their Blueprint functions are resident. RegisterHook
        -- on an unloaded Blueprint logs an exception even when wrapped in pcall.
        if not master_hook_installed and widget_kind(master) == "master" then
            master_hook_installed = install_hook(MASTER_PATH, "Databank master BP_OnActivated",
                ctx.lifecycle.on_widget_activated)
                and install_hook(MASTER_DEACTIVATED_PATH, "Databank master BP_OnDeactivated",
                    ctx.lifecycle.on_widget_deactivated)
        end
        if not page_hook_installed and widget_kind(page) == "page" then
            page_hook_installed = install_hook(PAGE_PATH, "supported page BP_OnActivated",
                ctx.lifecycle.on_widget_activated)
                and install_hook(PAGE_DEACTIVATED_PATH, "supported page BP_OnDeactivated",
                    ctx.lifecycle.on_widget_deactivated)
        end
    end

    local function render_ready(current)
        local page, vm, resolve_err, stock, _, _, category =
            ctx.databank_ui.resolve_live_page(current.category)
        if page == nil or vm == nil then return false, tostring(resolve_err) end
        if not ctx.common.same_object(page, current.page) then return false, "resolved page changed" end
        local stack = select(1, ctx.common.read_property(stock, "BitReactorStackBox_25"))
        local children = ctx.common.panel_child_count(stack)
        if children == nil then return false, "stock row stack unavailable" end
        local authority, authority_err = ctx.pool_authority.authoritative_pool_state(category)
        if authority == nil then return false, tostring(authority_err) end
        -- An empty Default pool is ready too (especially on a fresh Astromech tab).
        if authority.default_custom.count > 0 and children == 0 then return false, "stock rows not ready" end
        local extras = ctx.pool_authority.collect_extra_pool_vms(vm, authority)
        for _, name in ipairs(authority.custom_order or {}) do
            if extras[name] == nil then return false, "custom pool VM unavailable: " .. tostring(name) end
        end
        return true
    end

    local attempt
    local function log_wait(current, reason)
        if current.last_wait_reason == reason then return end
        current.last_wait_reason = reason
        ctx.logging.log("Databank initialization waiting (attempt " .. current.attempts .. "): " .. reason)
    end

    local function schedule_attempt(current, delay)
        ctx.actions.api.run_group_after(GROUP, delay, function()
            if request == current and ctx.runtime.alive then attempt(current) end
        end)
    end

    attempt = function(current)
        current.attempts = current.attempts + 1
        if current.entering then
            current.entry_attempts = current.entry_attempts + 1
            local master = current.master or ctx.common.find_first(MASTER_CLASS)
            local visible, visibility_reason = master_is_visible(master)
            local identity = visible and ctx.common.object_name(master) or nil
            if identity ~= nil and identity == current.candidate_identity then
                current.entering = false
                current.anchor, current.master = master, master
                ctx.logging.log("Databank submenu entry stabilized; initializing lifecycle hooks and pools.")
            else
                current.candidate_identity = identity
                log_wait(current, visibility_reason or "confirming stable master: " .. identity)
                if current.entry_attempts < MAX_ENTRY_ATTEMPTS then
                    local delays = { 150, 150, 200, 300, 450, 650 }
                    schedule_attempt(current, delays[current.entry_attempts + 1])
                else
                    ctx.logging.log("Databank submenu entry check expired: " .. current.last_wait_reason
                        .. "; waiting for another entry event.")
                    retire_request("Databank submenu did not open a stable master")
                end
                return
            end
        end
        -- These checks run only after activation unwinds, on an owned game-thread
        -- action. Never retain the RemoteUnrealParam supplied to a native hook.
        if not is_active(current.anchor) then
            retire_request("Databank activation ended")
            return
        end
        local master = current.master
        if master == nil then master = ctx.common.find_first(MASTER_CLASS) end
        if widget_kind(master) == "master" then current.master = master end

        local live_page = current.page
        if current.master ~= nil then
            if not is_active(current.master) then
                retire_request("Databank master closed")
                return
            end
            -- Check both categories independently: a missing/not-ready Custom page
            -- must not prevent installing the shared page hook for Astromechs.
            for _, category in ipairs({ ctx.categories.custom, ctx.categories.astromech }) do
                local page = select(1, ctx.common.read_property(current.master, category.page))
                if widget_kind(page) == "page" then
                    live_page = page
                    if current.page == nil and is_active(page) then
                        current.page, current.category = page, category
                    end
                end
            end
        end
        install_hooks(current.master, live_page)
        if not current.render_queued then
            local ready, reason = false, "no active supported page"
            if current.page ~= nil and is_active(current.page) then
                ready, reason = render_ready(current)
            end
            if ready then
                ctx.categories.activate(current.page)
                current.render_queued = true
                -- One shared refresh handle coalesces native mutations with activation.
                -- Keep ownership through dispatch so close/tab-switch cannot rebuild an
                -- old page after this readiness action has finished.
                ctx.databank_ui.schedule_refresh(current.reason, 0, function()
                    return request == current and is_active(current.anchor)
                        and is_active(current.master) and is_active(current.page)
                end)
            else
                log_wait(current, reason)
            end
        end
        if current.render_queued and master_hook_installed and page_hook_installed then return end
        if current.attempts < MAX_ATTEMPTS then
            schedule_attempt(current, 100)
        else
            ctx.logging.log("Databank activation initialization exhausted after " .. MAX_ATTEMPTS
                .. " attempts; waiting for the next activation.")
        end
    end

    function ctx.lifecycle.handle_strategy_submenu_click(button)
        if not ctx.common.uobject_is_valid(button) then return false end
        local identity = ctx.common.object_name(button)
        if not identity:find(" /Engine/Transient.", 1, true)
            or identity:sub(1, #"WBP_AnimatedSubMenuListButton_C ") ~= "WBP_AnimatedSubMenuListButton_C " then
            return false
        end
        -- Strategy navigation retires pending entry/render work even when the
        -- engine bypasses CommonUI's exposed DeactivateWidget UFunction.
        retire_request("Strategy submenu navigation")
        local label_widget = select(1, ctx.common.read_property(button, "ButtonTextBlock"))
        local text = select(1, ctx.common.try_call(function() return label_widget:GetText() end))
        local label = string.upper(ctx.common.text_value(text))
        if not label:find("DATABANK", 1, true) then return true end

        request = {
            entering = true, entry_attempts = 0, attempts = 0,
            render_queued = false, reason = "Character Databank submenu click",
        }
        ctx.logging.log("Character Databank submenu click detected; starting bounded entry check.")
        schedule_attempt(request, 150)
        return true
    end

    function ctx.lifecycle.on_widget_activated(context, reason)
        local widget = ctx.common.unwrap(context)
        local kind, category = widget_kind(widget)
        if kind == nil then return end
        -- Blueprint and CommonUI callbacks describe the same activation. Merge
        -- master/page notifications without resetting the budget or queuing work.
        if request ~= nil then
            if kind == "master" and (request.master == nil or ctx.common.same_object(request.master, widget)) then
                request.master = widget
                return
            elseif kind == "page" and (request.page == nil or ctx.common.same_object(request.page, widget))
                and not (request.page == nil and request.attempts >= MAX_ATTEMPTS) then
                request.page, request.category = widget, category
                return
            end
            retire_request("Databank activation superseded")
        end
        request = {
            anchor = widget, master = kind == "master" and widget or nil,
            page = kind == "page" and widget or nil, category = category,
            attempts = 0, render_queued = false, reason = reason,
        }
        -- Even when functions are resident, defer registration and readiness reads
        -- until the native activation has returned and its widget tree can settle.
        schedule_attempt(request, 120)
    end

    function ctx.lifecycle.on_widget_deactivated(context)
        local widget = ctx.common.unwrap(context)
        if widget_kind(widget) == nil or request == nil then return end
        if ctx.common.same_object(widget, request.anchor)
            or ctx.common.same_object(widget, request.master)
            or ctx.common.same_object(widget, request.page) then
            retire_request("Databank widget deactivated")
        end
    end

    function ctx.lifecycle.recover_open_databank()
        if request ~= nil then return end
        -- Exactly one probe per script load recovers an already-open screen even
        -- after a full Lua-state reload. Absence/closed widgets never arm retries.
        local master = ctx.common.find_first(MASTER_CLASS)
        if widget_kind(master) == "master" and master_is_visible(master) then
            -- Visibility alone may survive while a reusable screen is closed.
            -- Recovery needs an active supported tab, not a panel-parent test.
            for _, category in ipairs({ ctx.categories.custom, ctx.categories.astromech }) do
                local page = select(1, ctx.common.read_property(master, category.page))
                if widget_kind(page) == "page" and is_active(page) then
                    ctx.lifecycle.on_widget_activated(master, "Databank open during script load")
                    ctx.lifecycle.on_widget_activated(page, "Databank open during script load")
                    return
                end
            end
        end
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
