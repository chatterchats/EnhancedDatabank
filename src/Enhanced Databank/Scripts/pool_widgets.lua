-- Enhanced Databank: pool widgets.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: common, logging, pool_authority, pool_widgets.
return function(ctx)
    function ctx.pool_widgets.invoke_pool_rows(widget, rows, label)
        if widget == nil then return false, "widget unavailable" end
        local arg = {}
        for _, vm in ipairs(rows or {}) do table.insert(arg, vm) end

        -- Native Blueprint row regeneration is one of the few calls in this mod that
        -- can cross deeply through UE4SS while destroying/recreating child widgets.
        -- Log before entering it so a native access violation can be pinned to the
        -- exact pool even when Lua never gets a chance to report an exception.
        ctx.logging.log(tostring(label) .. " row apply begin: requested=" .. tostring(#rows))
        local _, err = ctx.common.try_call(function()
            return widget:BndEvt__WBP_CharacterBank_CreatedCharactersPoolItem_BrunoCharacterPoolViewModel_MDVMNode_ViewModelFieldNotify_1_PoolCharacterViewModels(arg)
        end)
        if err ~= nil then return false, tostring(label) .. " row handler failed: " .. tostring(err) end
        local stack = select(1, ctx.common.read_property(widget, "BitReactorStackBox_25"))
        ctx.logging.log(tostring(label) .. " rows applied: requested=" .. tostring(#rows)
            .. " | renderedChildren=" .. tostring(ctx.common.panel_child_count(stack)))
        return true, nil
    end

    local function row_pool_vm(row)
        if row == nil or not ctx.pool_authority.resolve_mdvm() then return nil, "row/MDViewModel unavailable" end
        local value, err = ctx.common.try_call(function()
            return ctx.common.unwrap(ctx.pool_authority.mdvm_library_cdo:GetViewModel(row, ctx.pool_authority.pool_vm_class, FName("")))
        end)
        return value, err
    end

    local function log_row_tooltip_state(row, expected_pool_vm, label)
        row = ctx.common.unwrap(row)
        if row == nil then
            ctx.logging.log(tostring(label) .. " tooltip diagnostic: row unavailable")
            return
        end
        local tooltip = select(1, ctx.common.read_property(row, "BitReactorTooltipBox_54"))
        local resolved_pool, resolved_err = row_pool_vm(row)
        ctx.logging.log(tostring(label) .. " tooltip diagnostic: tooltip=" .. ctx.common.object_name(tooltip)
            .. " | resolvedPool=" .. ctx.common.object_name(resolved_pool)
            .. " | matchesExpected=" .. tostring(ctx.common.same_object(resolved_pool, expected_pool_vm))
            .. " | GetViewModelErr=" .. tostring(resolved_err)
            .. " | expectedSave='" .. tostring(ctx.pool_authority.pool_save_name(expected_pool_vm)) .. "'")
    end

    local function apply_native_folder_tooltip(row, pool_vm, label)
        row = ctx.common.unwrap(row)
        pool_vm = ctx.common.unwrap(pool_vm)
        if row == nil or pool_vm == nil then return false, "row/pool unavailable" end

        local tooltip = select(1, ctx.common.read_property(row, "BitReactorTooltipBox_54"))
        if tooltip == nil then return false, "BitReactorTooltipBox_54 unavailable" end

        local save_name = ctx.pool_authority.pool_save_name(pool_vm)
        if save_name == nil or save_name == "" then return false, "native pool save filename unavailable" end

        -- Preserve the shipping tooltip widget and presentation. We only supply the
        -- payload entry that the stock Blueprint normally derives from its hidden
        -- BrunoCharacterPoolViewModel assignment. The native TooltipPaylodEntry
        -- fields are HeaderText / BodyText / Icon; omitting Icon leaves its default.
        local payload = {
            HeaderText = FText("FOLDER NAME"),
            BodyText = FText(save_name),
        }

        local _, payload_err = ctx.common.try_call(function()
            return tooltip:SetTooltipPayloadEntry(payload)
        end)
        if payload_err ~= nil then
            return false, "SetTooltipPayloadEntry failed: " .. tostring(payload_err)
        end

        local _, display_err = ctx.common.try_call(function()
            return tooltip:SetDisplayTooltop(true)
        end)
        if display_err ~= nil then
            return false, "SetDisplayTooltop failed: " .. tostring(display_err)
        end

        ctx.logging.log(tostring(label) .. " native tooltip payload applied: body='" .. tostring(save_name) .. "'")
        return true, nil
    end

    local function propagate_pool_context_to_rows(pool_widget, pool_vm, label)
        if pool_widget == nil or pool_vm == nil then return false, "pool widget/viewmodel unavailable" end
        local stack = select(1, ctx.common.read_property(pool_widget, "BitReactorStackBox_25"))
        if stack == nil then return false, "BitReactorStackBox_25 unavailable" end

        local count = ctx.common.panel_child_count(stack) or 0
        local bridge_applied = 0
        local changed_applied = 0
        local failed = 0

        for i = 0, count - 1 do
            local row = ctx.common.panel_child_at(stack, i)
            if row ~= nil and string.find(ctx.common.class_name(row), "WBP_CharacterBank_CreatedCharacterItem_C", 1, true) then
                -- First replay the shipping pool widget's row-created bridge. This is
                -- the native parent -> child pool-ViewModel propagation path.
                local _, bridge_err = ctx.common.try_call(function()
                    return pool_widget:BndEvt__WBP_CharacterBank_CreatedCharactersPoolItem_BitReactorStackBox_25_K2Node_ComponentBoundEvent_0_OnBitReactorStackBoxWidgetCreated__DelegateSignature(row)
                end)
                if bridge_err == nil then
                    bridge_applied = bridge_applied + 1
                else
                    failed = failed + 1
                    ctx.logging.log(tostring(label) .. " row pool-context bridge failed at index " .. tostring(i) .. ": " .. tostring(bridge_err))
                end

                log_row_tooltip_state(row, pool_vm, tostring(label) .. " row[" .. tostring(i) .. "] after pool bridge")

    -- Replaying the row-created bridge alone does not create
                -- the stock FOLDER NAME tooltip. The row Blueprint has a separate
                -- generated BrunoCharacterPoolViewModel ViewModelChanged handler;
                -- its compiled graph calls GetSaveFileNameForPool() and constructs
                -- the TooltipPaylodEntry. Replay that exact shipped handler now.
                local _, changed_err = ctx.common.try_call(function()
                    return row:BndEvt__WBP_CharacterBank_CreatedCharacterItem_BrunoCharacterPoolViewModel_MDVMNode_ViewModelChanged_0_Changed(nil, pool_vm)
                end)
                if changed_err == nil then
                    changed_applied = changed_applied + 1
                else
                    failed = failed + 1
                    ctx.logging.log(tostring(label) .. " row pool ViewModelChanged handler failed at index " .. tostring(i) .. ": " .. tostring(changed_err))
                end

                log_row_tooltip_state(row, pool_vm, tostring(label) .. " row[" .. tostring(i) .. "] after row ViewModelChanged")

                -- The hidden MDViewModel assignment still does not resolve to the
                -- expected pool on dynamically-created rows. Rather than replacing
                -- the tooltip, feed the existing native BitReactorTooltipBox the
                -- same header/body values the stock Blueprint computes.
                local tooltip_ok, tooltip_err = apply_native_folder_tooltip(
                    row, pool_vm, tostring(label) .. " row[" .. tostring(i) .. "]"
                )
                if not tooltip_ok then
                    failed = failed + 1
                    ctx.logging.log(tostring(label) .. " native tooltip payload failed at index " .. tostring(i) .. ": " .. tostring(tooltip_err))
                end
            end
        end

        ctx.logging.log(tostring(label) .. " row pool-context restore: rows=" .. tostring(count)
            .. " | bridgeApplied=" .. tostring(bridge_applied)
            .. " | changedApplied=" .. tostring(changed_applied)
            .. " | failed=" .. tostring(failed))
        return failed == 0, failed == 0 and nil or (tostring(failed) .. " row context/tooltip restore failure(s)")
    end

    function ctx.pool_widgets.create_pool_widget(page)
        local stock = select(1, ctx.common.read_property(page, "CharacterPool"))
        if stock == nil then return nil, "shipping CharacterPool unavailable" end
        local widget_class, class_err = ctx.common.try_call(function() return ctx.common.unwrap(stock:GetClass()) end)
        if class_err ~= nil or widget_class == nil then return nil, "pool widget class unavailable: " .. tostring(class_err) end
        local library_class, library_err = ctx.common.resolve_class("/Script/UMG.WidgetBlueprintLibrary")
        if library_class == nil then return nil, "WidgetBlueprintLibrary unavailable: " .. tostring(library_err) end
        local library, cdo_err = ctx.common.try_call(function() return ctx.common.unwrap(library_class:GetCDO()) end)
        if cdo_err ~= nil or library == nil then return nil, "WidgetBlueprintLibrary CDO unavailable: " .. tostring(cdo_err) end
        local owning_player = nil
        pcall(function() owning_player = ctx.common.unwrap(page:GetOwningPlayer()) end)
        local widget, create_err = ctx.common.try_call(function() return ctx.common.unwrap(library:Create(page, widget_class, owning_player)) end)
        if create_err ~= nil or widget == nil then return nil, "WidgetBlueprintLibrary.Create failed: " .. tostring(create_err) end
        return widget, nil
    end

    function ctx.pool_widgets.bind_pool_widget(widget, pool_vm)
        if not ctx.pool_authority.resolve_mdvm() then return false, "MDViewModel unavailable" end
        local _, err = ctx.common.try_call(function()
            return ctx.common.unwrap(ctx.pool_authority.mdvm_library_cdo:SetViewModel(widget, pool_vm, ctx.pool_authority.pool_vm_class, FName("")))
        end)
        if err ~= nil then return false, "SetViewModel failed: " .. tostring(err) end
        return true, nil
    end

    function ctx.pool_widgets.apply_pool_title(widget, pool_vm)
        local folder = select(1, ctx.common.read_property(widget, "WBP_CharacterBank_PoolName"))
        if folder == nil then return false, "nested folder unavailable" end
        local wanted = ctx.pool_authority.pool_name(pool_vm)
        local label = select(1, ctx.common.read_property(folder, "BitReactorRichTextBlock_73"))
        local localized_ok, localized_err = pcall(function() folder.LocalizedName = FText(wanted) end)
        local text_ok, text_err = false, nil
        if label ~= nil then text_ok, text_err = pcall(function() label:SetText(FText(wanted)) end) end
        if not localized_ok and not text_ok then
            return false, "title write failed: " .. tostring(localized_err or text_err)
        end
        return true, nil
    end

    function ctx.pool_widgets.remove_dynamic_pool_widgets(page)
        local scroll = select(1, ctx.common.read_property(page, "BitReactorScrollBox_0"))
        local stock = select(1, ctx.common.read_property(page, "CharacterPool"))
        if scroll == nil or stock == nil then return 0 end
        local remove = {}
        local count = ctx.common.panel_child_count(scroll) or 0
        for i = 0, count - 1 do
            local child = ctx.common.panel_child_at(scroll, i)
            if child ~= nil and not ctx.common.same_object(child, stock)
                and string.find(ctx.common.class_name(child), "WBP_CharacterBank_CreatedCharactersPoolItem_C", 1, true) then
                table.insert(remove, child)
            end
        end
        for _, child in ipairs(remove) do pcall(function() child:RemoveFromParent() end) end
        return #remove
    end
end
