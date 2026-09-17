-- Enhanced Databank: pool mutations.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: categories, actions, common, databank_ui, logging, pool_authority, pool_mutations, popup, state, widget_helpers.
return function(ctx)
    function ctx.pool_mutations.perform_move_character(guid_string, target_pool_name, character_name, category)
        category = category or ctx.categories.current()
        guid_string = tostring(guid_string or "")
        target_pool_name = ctx.widget_helpers.trim_string(target_pool_name)
        character_name = ctx.widget_helpers.trim_string(character_name)
        ctx.logging.log("Move Character deferred move begin: guid=" .. tostring(guid_string)
            .. " target='" .. tostring(target_pool_name) .. "'")
        if guid_string == "" or target_pool_name == "" then
            ctx.popup.show_folder_notice("MOVE CHARACTER FAILED", "The selected character or destination is no longer available.")
            return
        end

        local authority, authority_err = ctx.pool_authority.authoritative_pool_state(category)
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
        local source_entry = authority.custom_by_name[tostring(current_pool_name or "")]
        if tostring(current_pool_name or "") == tostring(authority.default_custom.name) then
            source_entry = authority.default_custom
        end
        if source_entry == nil or not source_entry.guids[guid_string] then
            ctx.popup.show_folder_notice("MOVE CHARACTER FAILED", "The character is no longer in this Databank category.")
            return
        end
        if tostring(current_pool_name or "") == target_pool_name then
            return
        end

        local source_is_default = tostring(current_pool_name or "")
            == tostring(authority.default_custom.name or "")
        local target_is_default = target_pool_name == tostring(authority.default_custom.name or "")

        local manager = authority.manager or ctx.common.find_first("BitReactorCharacterPoolManager")
        if manager == nil then
            ctx.popup.show_folder_notice("MOVE CHARACTER FAILED", "The Character Pool Manager is not ready.")
            return
        end

        ctx.state.folder_ui_state.pendingMove = {
            category = category,
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

        if source_is_default or target_is_default then
            local reason = source_is_default and "moved out of Default" or "moved into Default"
            local _, reconcile_err, visible = ctx.databank_ui.reconcile_default_pool(category, reason)
            if reconcile_err ~= nil then
                ctx.logging.log("Default row reconciliation deferred/unavailable: " .. tostring(reconcile_err))
            end
            if target_is_default and not (visible and visible[guid_string]) then
                ctx.actions.run_on_game_thread_after(160, function()
                    -- Re-read ownership as well as widgets. A subsequent move may
                    -- have taken this character out again before the callback runs.
                    ctx.databank_ui.reconcile_default_pool(category, "moved into Default delayed")
                end)
            end
        end

        ctx.logging.log("MOVE CHARACTER SUCCESS: '" .. tostring(character_name ~= "" and character_name or guid_string)
            .. "' guid=" .. tostring(guid_string)
            .. " source='" .. tostring(current_pool_name)
            .. "' target='" .. tostring(target_pool_name) .. "'")
        -- The manager refresh hook rebuilds the generated custom-folder rows.
    end

    function ctx.pool_mutations.perform_create_folder(name, category)
        category = category or ctx.categories.current()
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
        local pool, create_err = ctx.common.try_call(function() return ctx.common.unwrap(vm:CreatePool(FText(name), category.custom_type)) end)
        if create_err ~= nil or pool == nil then
            ctx.logging.log("CreatePool failed for '" .. tostring(name) .. "': " .. tostring(create_err))
            ctx.popup.show_folder_notice("CREATE FOLDER FAILED", "Zero Company did not create the folder.")
            return
        end
        ctx.logging.log("CREATE FOLDER SUCCESS: name='" .. tostring(name) .. "' pool=" .. ctx.common.object_name(pool))
        -- CreatePool's native refresh hook schedules the authoritative renderer.
    end

    function ctx.pool_mutations.perform_rename_folder(pool_vm, old_name, new_name, category)
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
        local entry, entry_err = ctx.pool_authority.validate_custom_pool(pool_vm, old_name, category)
        if entry == nil then
            ctx.logging.log("Rename Folder authority check failed: " .. tostring(entry_err))
            ctx.popup.show_folder_notice("RENAME FOLDER FAILED", "The selected folder is no longer available.")
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

    function ctx.pool_mutations.perform_delete_folder(pool_vm, name, category)
        pool_vm = ctx.common.unwrap(pool_vm)
        name = ctx.widget_helpers.trim_string(name)
        if pool_vm == nil or name == "" then
            ctx.popup.show_folder_notice("DELETE FOLDER FAILED", "The selected folder is no longer available.")
            return
        end

        -- Re-check authoritative ownership at the moment of deletion instead of
        -- trusting the count captured when the button was rendered.
        local entry, count_err = ctx.pool_authority.validate_custom_pool(pool_vm, name, category)
        local count = entry and entry.count
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
