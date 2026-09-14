-- Enhanced Databank: databank ui.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: common, databank_ui, folder_ui, logging, pool_authority, pool_widgets, runtime, state, widget_helpers.
return function(ctx)
    -- Folder management uses explicit per-folder edit/delete buttons; no hidden gestures.

    local refresh_in_progress = false

    ctx.databank_ui.refresh_generation = 0

    local refresh_again = false

    local refresh_action_handle = MakeActionHandle()

    function ctx.databank_ui.resolve_live_humanoid_page()
        local master = ctx.common.find_first("WBP_CharacterBank_Master_C")
        local databank_vm = ctx.common.find_first("BrunoCharacterDatabankViewModel")
        if not ctx.common.uobject_is_valid(master) or not ctx.common.uobject_is_valid(databank_vm) then
            return nil, nil, "Databank master/viewmodel unavailable"
        end
        local page = select(1, ctx.common.read_property(master, "OtherCharacterList"))
        if not ctx.common.uobject_is_valid(page) then return nil, nil, "OtherCharacterList unavailable" end
        local stock_widget = select(1, ctx.common.read_property(page, "CharacterPool"))
        local scroll = select(1, ctx.common.read_property(page, "BitReactorScrollBox_0"))
        local default_vm = select(1, ctx.common.read_property(databank_vm, "DefaultCustomCharacterPoolViewModel"))
        if not ctx.common.uobject_is_valid(stock_widget) or not ctx.common.uobject_is_valid(scroll)
            or not ctx.common.uobject_is_valid(default_vm) then
            return nil, nil, "humanoid Databank widget tree/viewmodels not ready"
        end
        -- Return the objects already resolved during the readiness check. Re-reading
        -- these reflected properties later in the same cold-activation callback was
        -- a repeatable UE4SS access-violation boundary.
        return page, databank_vm, nil, stock_widget, default_vm, scroll
    end

    ctx.databank_ui.schedule_refresh = nil

    local function schedule_default_pool_reconciliation(expected_page_identity)
        -- An earlier approach still crashed after four compact stock-row visuals had been
        -- installed. Do not inspect, decorate, or retain any shipping character row
        -- in the stability baseline. The native Default pool remains wholly owned by
        -- the game.
        ctx.logging.log("Default Custom untouched: stock row reconciliation/decoration disabled for stability; page="
            .. tostring(expected_page_identity))
    end

    function ctx.databank_ui.refresh_visible_pools(reason)
        if refresh_in_progress then
            refresh_again = true
            ctx.logging.log("Refresh already in progress; coalescing request: " .. tostring(reason))
            return
        end
        refresh_in_progress = true
        ctx.logging.section("AUTO DATABANK POOL RENDER")
        ctx.logging.log("reason=" .. tostring(reason))

        local page, databank_vm, state_err, stock_widget, default_vm, scroll =
            ctx.databank_ui.resolve_live_humanoid_page()
        if page == nil or databank_vm == nil then
            ctx.logging.log("NO-OP: " .. tostring(state_err))
            refresh_in_progress = false
            return
        end

        ctx.folder_ui.ensure_create_folder_control(page)

        local authority, auth_err = ctx.pool_authority.authoritative_pool_state()
        if authority == nil then
            ctx.logging.log("ABORT: " .. tostring(auth_err))
            refresh_in_progress = false
            return
        end

        ctx.logging.log("Authoritative Default Custom characters=" .. tostring(authority.default_custom.count))
        ctx.logging.log("Authoritative player-created custom pools=" .. tostring(#authority.custom_order))
        for _, name in ipairs(authority.custom_order) do
            local entry = authority.custom_by_name[name]
            ctx.logging.log("  pool='" .. tostring(name) .. "' characters=" .. tostring(entry and entry.count or 0))
        end

        local extra_vms = ctx.pool_authority.collect_extra_pool_vms(databank_vm, authority)

        -- ViewModel arrays may lag or remain stale after a manager mutation. Record
        -- one diagnostic snapshot, then render once from pool-local typed entries.
            -- An earlier implementation retried this entire native widget rebuild every 100 ms; when the
        -- destination VM never converged, nine rapid passes produced both log spam
        -- and a repeatable UE4SS GameThread access violation.
        local pending = ctx.state.folder_ui_state.pendingMove
        if pending ~= nil then
            local default_vm_for_move = default_vm
            local function vm_for_pool_name(pool_name_value)
                if tostring(pool_name_value or "") == tostring(authority.default_custom.name or "") then
                    return default_vm_for_move
                end
                return extra_vms[tostring(pool_name_value or "")]
            end

            local source_vm = vm_for_pool_name(pending.sourcePoolName)
            local target_vm = vm_for_pool_name(pending.targetPoolName)
            local source_has = source_vm ~= nil and ctx.pool_authority.pool_vm_contains_guid(source_vm, pending.guid) or false
            local target_has = target_vm ~= nil and ctx.pool_authority.pool_vm_contains_guid(target_vm, pending.guid) or false
            if source_has or not target_has then
                ctx.logging.log("Move Character VM ownership incomplete after native move: guid="
                    .. tostring(pending.guid) .. " sourceHas=" .. tostring(source_has)
                    .. " targetHas=" .. tostring(target_has)
                    .. "; no automatic retry/rebuild will run")
            else
                ctx.logging.log("Move Character Databank VM ownership converged: guid=" .. tostring(pending.guid)
                    .. " source='" .. tostring(pending.sourcePoolName)
                    .. "' target='" .. tostring(pending.targetPoolName) .. "'")
                ctx.state.folder_ui_state.pendingMove = nil
            end
            ctx.state.folder_ui_state.pendingMove = nil
        end

        local global_index = ctx.pool_authority.collect_raw_vm_index(databank_vm, extra_vms)
        local removed = ctx.pool_widgets.remove_dynamic_pool_widgets(page)
        ctx.state.folder_ui_state.renameButtons = {}
        ctx.state.folder_ui_state.deleteButtons = {}
        ctx.state.folder_ui_state.moveButtons = {}
        ctx.state.folder_ui_state.moveRowActions = {}
        ctx.state.folder_ui_state.moveDestinationButtons = {}
        ctx.state.folder_ui_state.renderedPools = {}
        ctx.state.default_move_decor_generation = ctx.state.default_move_decor_generation + 1
        ctx.logging.log("Removed prior dynamic pool widgets=" .. tostring(removed))

        -- The shipping Default Custom widget is already bound and populated by the
        -- game. Preserve it, and defer even its read-only reconciliation until the
                -- current activation callback has unwound. Deferring per-row widget
        -- construction but still re-read DefaultCustomCharacterPoolViewModel here;
        -- two cold-entry runs crashed at that exact UE4SS/native boundary.
        schedule_default_pool_reconciliation(ctx.common.object_name(page))

        if scroll == nil then
            ctx.logging.log("ABORT: BitReactorScrollBox_0 unavailable")
            refresh_in_progress = false
            return
        end

        local rendered = 0
        for _, name in ipairs(authority.custom_order) do
            local entry = authority.custom_by_name[name]
            local pool_vm = extra_vms[name]
            if pool_vm == nil then
                ctx.logging.log("Cannot render authoritative pool '" .. tostring(name) .. "': matching BrunoCharacterPoolViewModel unavailable")
            else
                local widget, create_err = ctx.pool_widgets.create_pool_widget(page)
                if widget == nil then
                    ctx.logging.log("Create widget failed for '" .. tostring(name) .. "': " .. tostring(create_err))
                else
                    local slot, add_err = ctx.common.try_call(function() return ctx.common.unwrap(scroll:AddChild(widget)) end)
                    if add_err ~= nil or slot == nil then
                        ctx.logging.log("Attach failed for '" .. tostring(name) .. "': " .. tostring(add_err))
                        pcall(function() widget:RemoveFromParent() end)
                    else
                        pcall(function() widget.HideIfEmpty = false end)
                        local bind_ok, bind_err = ctx.pool_widgets.bind_pool_widget(widget, pool_vm)
                        if not bind_ok then ctx.logging.log("SetViewModel failed for '" .. tostring(name) .. "': " .. tostring(bind_err)) end
                        local title_ok, title_err = ctx.pool_widgets.apply_pool_title(widget, pool_vm)
                        if not title_ok then
                            ctx.logging.log("Title presentation failed for '" .. tostring(name) .. "': " .. tostring(title_err))
                        else
                            local folder_header = select(1, ctx.common.read_property(widget, "WBP_CharacterBank_PoolName"))
                            local rename_ok, rename_err = ctx.folder_ui.install_rename_button_on_folder(
                                page, widget, folder_header, pool_vm, name, rendered + 1,
                                entry and entry.count or 0)
                            if not rename_ok then
                                ctx.logging.log("Folder action button install failed for '" .. tostring(name) .. "': " .. tostring(rename_err))
                            end
                        end
                        local rows = ctx.pool_authority.rows_for_authority(pool_vm, entry, global_index)
                        local rows_ok, rows_err = ctx.pool_widgets.invoke_pool_rows(widget, rows, "Extra pool '" .. tostring(name) .. "'")
                        if not rows_ok then
                            ctx.logging.log("Row population failed for '" .. tostring(name) .. "': " .. tostring(rows_err))
                        else
                            -- Keep only a pool-level record of the exact typed rows
                            -- supplied to this widget. MOVE consumes it on click to
                            -- translate the selected row position back to its VM;
                            -- rendering still does not inspect or retain row widgets.
                            table.insert(ctx.state.folder_ui_state.renderedPools, {
                                widget = widget,
                                rows = rows,
                                entry = entry,
                                name = tostring(name),
                            })
                            -- Do not replay generated row-created/ViewModelChanged
                            -- handlers here. Their MDViewModel binding never matched
                -- the expected pool in diagnostics, and the related crash
                            -- dumps end in the same UE4SS GameThread stack while this
                            -- per-row bridge was being repeated. Native selection is
                            -- already supplied by invoke_pool_rows().
                            ctx.logging.log("Extra pool row-context replay disabled for stability: pool='"
                                .. tostring(name) .. "' rows=" .. tostring(#rows))
                            ctx.logging.log("Move Character row decoration disabled for stability: pool='"
                                .. tostring(name) .. "' rows=" .. tostring(#rows))
                        end
                        rendered = rendered + 1
                    end
                end
            end
        end

        local move_button_ok, move_button_err = require("selected_move_button").ensure(page, {
            unwrap = ctx.common.unwrap,
            objectName = ctx.common.object_name,
            className = ctx.common.class_name,
            tryCall = ctx.common.try_call,
            readProperty = ctx.common.read_property,
            panelChildCount = ctx.common.panel_child_count,
            panelChildAt = ctx.common.panel_child_at,
            findTreeWidget = ctx.widget_helpers.find_tree_widget,
            cloneWidgetLike = ctx.widget_helpers.clone_widget_like,
            constructWidget = ctx.widget_helpers.construct_widget,
            captureSlotLayout = ctx.widget_helpers.capture_box_slot_layout,
            applySlotLayout = ctx.widget_helpers.apply_box_slot_layout,
            register = function(button)
                ctx.state.folder_ui_state.moveButtons[ctx.common.object_name(button)] = {
                    button = button,
                    selectedDetail = true,
                }
            end,
            log = ctx.logging.log,
        })
        if not move_button_ok then
            ctx.logging.log("Selected-character Move button pending: " .. tostring(move_button_err))
        end

        ctx.folder_ui.install_action_hover_hooks()
        ctx.logging.log("AUTO RENDER COMPLETE: scroll children=" .. tostring(ctx.common.panel_child_count(scroll))
            .. " | extra rendered=" .. tostring(rendered))
        ctx.logging.section("END AUTO DATABANK POOL RENDER")
        refresh_in_progress = false

        if refresh_again then
            refresh_again = false
            ctx.databank_ui.schedule_refresh("coalesced follow-up", 80)
        end
    end

    ctx.databank_ui.schedule_refresh = function(reason, delay_ms)
        -- Lifecycle hooks can finish installing while an activation-triggered render
        -- is already running. Coalesce immediately instead of arming another timer
        -- that may fire while the current renderer is inside a native Blueprint call.
        if refresh_in_progress then
            refresh_again = true
            ctx.logging.log("Refresh requested during active render; coalescing: " .. tostring(reason))
            return
        end

        ctx.databank_ui.refresh_generation = ctx.databank_ui.refresh_generation + 1
        local generation = ctx.databank_ui.refresh_generation
        local runtime = ctx.runtime
        runtime:track_action(refresh_action_handle)
        RetriggerableExecuteInGameThreadWithDelay(refresh_action_handle, delay_ms or 100, function()
            runtime:finish_action(refresh_action_handle)
            if not runtime.alive then return end
            if generation ~= ctx.databank_ui.refresh_generation then return end
            ctx.databank_ui.refresh_visible_pools(reason)
        end)
    end

    function ctx.databank_ui.restore_stock_only()
        ctx.logging.section("AUTO UI CLEANUP")
        local page, databank_vm, err = ctx.databank_ui.resolve_live_humanoid_page()
        if page == nil or databank_vm == nil then ctx.logging.log("NO-OP: " .. tostring(err)); return end
        ctx.logging.log("Removed dynamic pool widgets=" .. tostring(ctx.pool_widgets.remove_dynamic_pool_widgets(page)))

        -- Do not manually replay the shipping Default pool's generated row handler.
        -- The game owns that widget and keeps it synchronized with its ViewModel;
        -- forcing a second regeneration causes a cold-entry crash.
        ctx.state.folder_ui_state.moveRowActions = {}
        ctx.state.folder_ui_state.moveClickScheduled = false
        ctx.logging.log("Stock Default pool left untouched; native game binding remains authoritative.")
        ctx.logging.section("END AUTO UI CLEANUP")
    end
end
