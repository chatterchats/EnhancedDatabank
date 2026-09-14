-- Enhanced Databank: pool mutations.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: actions, common, logging, pool_authority, pool_mutations, popup, state, widget_helpers.
return function(ctx)
    function ctx.pool_mutations.perform_move_character(guid_string, target_pool_name, character_name)
        guid_string = tostring(guid_string or "")
        target_pool_name = ctx.widget_helpers.trim_string(target_pool_name)
        character_name = ctx.widget_helpers.trim_string(character_name)
        ctx.logging.log("Move Character deferred move begin: guid=" .. tostring(guid_string)
            .. " target='" .. tostring(target_pool_name) .. "'")
        if guid_string == "" or target_pool_name == "" then
            ctx.popup.show_folder_notice("MOVE CHARACTER FAILED", "The selected character or destination is no longer available.")
            return
        end

        local authority, authority_err = ctx.pool_authority.authoritative_pool_state()
        if authority == nil then
            ctx.logging.log("Move Character authority failed: " .. tostring(authority_err))
            ctx.popup.show_folder_notice("MOVE CHARACTER FAILED", "The Character Databank state could not be verified.")
            return
        end
        local target_exists = tostring(authority.default_custom.name or "") == target_pool_name
            or (authority.custom_by_name and authority.custom_by_name[target_pool_name] ~= nil)
        if not target_exists then
            ctx.popup.show_folder_notice("MOVE CHARACTER FAILED", "That destination folder no longer exists.")
            return
        end

        local guid_value, current_pool_name, guid_err = ctx.pool_authority.find_authoritative_guid_value(guid_string)
        if guid_value == nil then
            ctx.logging.log("Move Character GUID lookup failed: " .. tostring(guid_err))
            ctx.popup.show_folder_notice("MOVE CHARACTER FAILED", "The character could not be found in the current Databank state.")
            return
        end
        if tostring(current_pool_name or "") == target_pool_name then
            return
        end

        local source_is_default = tostring(current_pool_name or "")
            == tostring(authority.default_custom.name or "")
        local target_is_default = target_pool_name == tostring(authority.default_custom.name or "")

        -- Manager-direct moves are the stable persistence path, but the shipping
        -- Default pool can retain the moved character in its live ViewModel array.
        -- Never regenerate or reparent that pool. Resolve the physical row through
        -- its rendered identity; the typed array and widget stack can diverge after
        -- a new character is inserted.
        local function set_default_row_visibility(visibility, reason)
            local databank_vm = ctx.common.find_first("BrunoCharacterDatabankViewModel")
            local default_vm = databank_vm and select(1, ctx.common.read_property(
                databank_vm, "DefaultCustomCharacterPoolViewModel")) or nil
            local items = default_vm and select(1, ctx.common.read_property(
                default_vm, "PoolCharacterViewModels")) or nil
            local master = ctx.common.find_first("WBP_CharacterBank_Master_C")
            local page = master and select(1, ctx.common.read_property(master, "OtherCharacterList")) or nil
            local stock_widget = page and select(1, ctx.common.read_property(page, "CharacterPool")) or nil
            local stack = stock_widget and select(1, ctx.common.read_property(
                stock_widget, "BitReactorStackBox_25")) or nil
            local row_count = stack and ctx.common.panel_child_count(stack) or nil
            if items == nil or stack == nil or row_count == nil then
                ctx.logging.log("Default row visibility reconcile deferred/unavailable: guid="
                    .. tostring(guid_string) .. " reason=" .. tostring(reason))
                return false
            end

            local display_index = ctx.pool_authority.character_display_index(items)
            local row, wanted_index = nil, nil
            for index = 0, row_count - 1 do
                local candidate_row = ctx.common.panel_child_at(stack, index)
                local _, candidate_guid = ctx.pool_authority.character_for_row(
                    candidate_row, display_index)
                if candidate_guid == guid_string then
                    row, wanted_index = candidate_row, index
                    break
                end
            end
            if row == nil then
                ctx.logging.log("Default row visibility reconcile could not resolve row: guid="
                    .. tostring(guid_string) .. " reason=" .. tostring(reason))
                return false
            end
            local ok, visibility_err = pcall(function() row:SetVisibility(visibility) end)
            ctx.logging.log("Default row visibility reconciled: index=" .. tostring(wanted_index)
                .. " guid=" .. tostring(guid_string) .. " visibility="
                .. tostring(visibility) .. " reason=" .. tostring(reason)
                .. " ok=" .. tostring(ok) .. " err=" .. tostring(visibility_err))
            return ok
        end

        local manager = authority.manager or ctx.common.find_first("BitReactorCharacterPoolManager")
        if manager == nil then
            ctx.popup.show_folder_notice("MOVE CHARACTER FAILED", "The Character Pool Manager is not ready.")
            return
        end

        ctx.state.folder_ui_state.pendingMove = {
            guid = tostring(guid_string),
            sourcePoolName = tostring(current_pool_name or ""),
            targetPoolName = tostring(target_pool_name),
            attempts = 0,
        }

    -- The manager-direct mutation is stable. Default-pool visual
        -- reconciliation is handled below without replaying its generated handler.
        ctx.logging.log("Move Character invoking CharacterPoolManager.MoveCharacterToAnotherPool: source='"
            .. tostring(current_pool_name) .. "' target='" .. tostring(target_pool_name) .. "'")
        local moved, move_err = ctx.common.try_call(function()
            return manager:MoveCharacterToAnotherPool(guid_value, FText(target_pool_name))
        end)
        ctx.logging.log("Move Character manager call returned: result=" .. tostring(moved)
            .. " err=" .. tostring(move_err))
        if move_err ~= nil or moved ~= true then
            ctx.state.folder_ui_state.pendingMove = nil
            ctx.logging.log("MoveCharacterToAnotherPool failed: guid=" .. tostring(guid_string)
                .. " source='" .. tostring(current_pool_name)
                .. "' target='" .. tostring(target_pool_name)
                .. "' result=" .. tostring(moved) .. " err=" .. tostring(move_err))
            ctx.popup.show_folder_notice("MOVE CHARACTER FAILED", "Zero Company did not move the character.")
            return
        end

        if source_is_default then
            set_default_row_visibility(1, "moved out of Default")
        elseif target_is_default then
            local visible_now = set_default_row_visibility(0, "moved into Default")
            if not visible_now then
                ctx.actions.run_on_game_thread_after(160, function()
                    set_default_row_visibility(0, "moved into Default delayed")
                end)
            end
        end

        ctx.logging.log("MOVE CHARACTER SUCCESS: '" .. tostring(character_name ~= "" and character_name or guid_string)
            .. "' guid=" .. tostring(guid_string)
            .. " source='" .. tostring(current_pool_name)
            .. "' target='" .. tostring(target_pool_name) .. "'")
        -- The manager refresh hook rebuilds the generated custom-folder rows.
    end

    function ctx.pool_mutations.perform_create_folder(name)
        name = ctx.widget_helpers.trim_string(name)
        if name == "" then
            ctx.popup.show_folder_notice("INVALID FOLDER NAME", "Enter a folder name before choosing Create.")
            return
        end
        local vm = ctx.common.find_first("BrunoCharacterDatabankViewModel")
        if vm == nil then ctx.popup.show_folder_notice("CREATE FOLDER FAILED", "The Character Databank is not ready."); return end
        local available, available_err = ctx.common.try_call(function() return vm:IsNewPoolNameAvailable(FText(name)) end)
        if available_err ~= nil then
            ctx.logging.log("Create Folder availability check failed: " .. tostring(available_err))
            ctx.popup.show_folder_notice("CREATE FOLDER FAILED", "The folder name could not be validated.")
            return
        end
        if available ~= true then
            ctx.popup.show_folder_notice("FOLDER NAME UNAVAILABLE", "A folder with that name already exists. Choose another name.")
            return
        end
        local pool, create_err = ctx.common.try_call(function() return ctx.common.unwrap(vm:CreatePool(FText(name), 5)) end)
        if create_err ~= nil or pool == nil then
            ctx.logging.log("CreatePool failed for '" .. tostring(name) .. "': " .. tostring(create_err))
            ctx.popup.show_folder_notice("CREATE FOLDER FAILED", "Zero Company did not create the folder.")
            return
        end
        ctx.logging.log("CREATE FOLDER SUCCESS: name='" .. tostring(name) .. "' pool=" .. ctx.common.object_name(pool))
        -- CreatePool's native refresh hook schedules the authoritative renderer.
    end

    function ctx.pool_mutations.perform_rename_folder(pool_vm, old_name, new_name)
        pool_vm = ctx.common.unwrap(pool_vm)
        old_name = ctx.widget_helpers.trim_string(old_name)
        new_name = ctx.widget_helpers.trim_string(new_name)

        if pool_vm == nil or old_name == "" then
            ctx.popup.show_folder_notice("RENAME FOLDER FAILED", "The selected folder is no longer available.")
            return
        end
        if new_name == "" then
            ctx.popup.show_folder_notice("INVALID FOLDER NAME", "Enter a folder name before choosing Rename.")
            return
        end
        if new_name == old_name then
            ctx.logging.log("Rename Folder no-op: name unchanged ('" .. tostring(old_name) .. "').")
            return
        end

        local vm = ctx.common.find_first("BrunoCharacterDatabankViewModel")
        if vm == nil then
            ctx.popup.show_folder_notice("RENAME FOLDER FAILED", "The Character Databank is not ready.")
            return
        end

        local available, available_err = ctx.common.try_call(function()
            return vm:IsNewPoolNameAvailable(FText(new_name))
        end)
        if available_err ~= nil then
            ctx.logging.log("Rename Folder availability check failed: " .. tostring(available_err))
            ctx.popup.show_folder_notice("RENAME FOLDER FAILED", "The folder name could not be validated.")
            return
        end
        if available ~= true then
            ctx.popup.show_folder_notice("FOLDER NAME UNAVAILABLE", "A folder with that name already exists. Choose another name.")
            return
        end

        local _, rename_err = ctx.common.try_call(function()
            return vm:RenamePool(pool_vm, FText(new_name))
        end)
        if rename_err ~= nil then
            ctx.logging.log("RenamePool failed: '" .. tostring(old_name) .. "' -> '" .. tostring(new_name)
                .. "': " .. tostring(rename_err))
            ctx.popup.show_folder_notice("RENAME FOLDER FAILED", "Zero Company did not rename the folder.")
            return
        end

        ctx.logging.log("RENAME FOLDER SUCCESS: '" .. tostring(old_name) .. "' -> '" .. tostring(new_name) .. "'")
    end

    function ctx.pool_mutations.perform_delete_folder(pool_vm, name)
        pool_vm = ctx.common.unwrap(pool_vm)
        name = ctx.widget_helpers.trim_string(name)
        if pool_vm == nil or name == "" then
            ctx.popup.show_folder_notice("DELETE FOLDER FAILED", "The selected folder is no longer available.")
            return
        end

        -- Re-check authoritative ownership at the moment of deletion instead of
        -- trusting the count captured when the button was rendered.
        local count, count_err = ctx.popup.current_custom_pool_count(name)
        if count == nil then
            ctx.logging.log("Delete Folder authority check failed for '" .. tostring(name) .. "': " .. tostring(count_err))
            ctx.popup.show_folder_notice("DELETE FOLDER FAILED", "The folder state could not be verified.")
            return
        end
        if count > 0 then
            ctx.popup.show_folder_notice(
                "FOLDER NOT EMPTY",
                "Move the " .. tostring(count) .. " character" .. (count == 1 and "" or "s")
                    .. " out of '" .. tostring(name) .. "' before deleting it."
            )
            return
        end

        local vm = ctx.common.find_first("BrunoCharacterDatabankViewModel")
        if vm == nil then
            ctx.popup.show_folder_notice("DELETE FOLDER FAILED", "The Character Databank is not ready.")
            return
        end

        local _, delete_err = ctx.common.try_call(function() return vm:DeletePool(pool_vm) end)
        if delete_err ~= nil then
            ctx.logging.log("DeletePool failed for '" .. tostring(name) .. "': " .. tostring(delete_err))
            ctx.popup.show_folder_notice("DELETE FOLDER FAILED", "Zero Company did not delete the folder.")
            return
        end
        ctx.logging.log("DELETE FOLDER SUCCESS: '" .. tostring(name) .. "'")
    end
end
