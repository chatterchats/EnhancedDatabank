-- Enhanced Databank: popup.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: actions, common, folder_icons, logging, pool_authority, pool_mutations, popup, runtime, state, widget_helpers.
return function(ctx)
    local function clear_named_slot_content(widget, property_name)
        local slot = select(1, ctx.common.read_property(widget, property_name))
        if slot == nil then return end
        pcall(function() slot:ClearChildren() end)
        pcall(function() slot:SetContent(nil) end)
    end

    local function reset_folder_popup_state()
        ctx.state.folder_popup_state.widget = nil
        ctx.state.folder_popup_state.mode = nil
        ctx.state.folder_popup_state.textBox = nil
        ctx.state.folder_popup_state.resultActions = {}
        ctx.state.folder_popup_state.suppressResult = false
        ctx.state.folder_popup_state.initialText = ""
        ctx.state.folder_popup_state.targetPoolVM = nil
        ctx.state.folder_popup_state.targetPoolName = nil
        ctx.state.folder_popup_state.targetCharacterGuid = nil
        ctx.state.folder_popup_state.targetCharacterName = nil
        ctx.state.folder_popup_state.sourcePoolName = nil
    end

    ctx.runtime.ui_cleanup = function()
        local popup = ctx.common.unwrap(ctx.state.folder_popup_state.widget)
        ctx.state.folder_popup_state.suppressResult = true
        if ctx.common.uobject_is_valid(popup) then
            clear_named_slot_content(popup, "AboveText")
            clear_named_slot_content(popup, "Belowtext")
            pcall(function() popup:OnCloseWindow() end)
        end
        reset_folder_popup_state()
    end

    local function gameplay_tag_value(tag)
        tag = ctx.common.unwrap(tag)
        if tag == nil then return nil end
        local tag_name = select(1, ctx.common.read_property(tag, "TagName"))
        if tag_name ~= nil then return ctx.common.text_value(tag_name) end
        return nil
    end

    local function get_messaging_subsystem(world_context)
        local lib_class, lib_err = ctx.widget_helpers.load_class("/Script/Engine.SubsystemBlueprintLibrary")
        if lib_class == nil then return nil, lib_err end
        local lib = select(1, ctx.common.try_call(function() return ctx.common.unwrap(lib_class:GetCDO()) end))
        local msg_class, msg_err = ctx.widget_helpers.load_class("/Script/BitReactorGame.BitReactorMessagingSubsystem")
        if lib == nil or msg_class == nil then return nil, tostring(msg_err or "messaging classes unavailable") end
        local subsystem, err = ctx.common.try_call(function() return ctx.common.unwrap(lib:GetLocalPlayerSubsystem(world_context, msg_class)) end)
        if err ~= nil or subsystem == nil then return nil, tostring(err or "messaging subsystem unavailable") end
        return subsystem, nil
    end

    local function make_dialog_action(result_tag, label)
        return {
            Result = { TagName = FName(result_tag) },
            OptionalDisplayText = FText(label),
            OptionalInputAction = nil,
        }
    end

    local handle_folder_dialog_result

    local function ensure_folder_dialog_result_hook()
        if ctx.state.folder_dialog_result_hook_registered then return true end
        local ok, hook_id = pcall(function()
            return ctx.runtime:register_hook(
                "/Game/Game/UI/Common/WBP_GenericPopupMessage.WBP_GenericPopupMessage_C:BP_OnHideDialog",
                function(self, result)
                    if handle_folder_dialog_result ~= nil then handle_folder_dialog_result(self, result) end
                end
            )
        end)
        if ok and hook_id ~= nil then
            ctx.state.folder_dialog_result_hook_registered = true
            ctx.logging.log("Create Folder native dialog result hook registered.")
            return true
        end
        ctx.logging.log("Create Folder dialog result hook unavailable: " .. tostring(hook_id))
        return false
    end

    local function create_folder_entry(popup, initial_text)
        local entry_class, class_err = ctx.widget_helpers.load_class(ctx.state.ENTRY_TEXT_CLASS_PATH)
        if entry_class == nil then return nil, nil, class_err end
        local entry, entry_err = ctx.widget_helpers.create_user_widget(popup, entry_class)
        if entry == nil then return nil, nil, entry_err end
        local initial_value = tostring(initial_text or "")
        pcall(function()
            entry:Rename(FName("EnhancedDatabank_FolderNameEntry"), popup)
            entry.MaxCharacterCountSingleLine = 64
            entry.MaxCharacterCountMultiline = 64
            entry:SetIsMultiline(false)
            entry:SetTextboxHeight(42.0)
            entry:UpdateCharacterLimitsSingleLine()
            entry:SetText(FText(initial_value), true)
        end)
        local editable = select(1, ctx.common.read_property(entry, "EditableText"))
        if editable == nil then return nil, nil, "EntryText.EditableText unavailable" end
        local function apply()
            pcall(function()
                entry.MaxCharacterCountSingleLine = 64
                entry.MaxCharacterCountMultiline = 64
                entry:SetIsMultiline(false)
                entry:UpdateCharacterLimitsSingleLine()
                entry:SetText(FText(initial_value), true)
                editable:SetText(FText(initial_value))
                editable:SetHintText(FText("Folder name"))
                editable:SetMinimumDesiredWidth(440.0)
                editable:SetIsReadOnly(false)
                editable.SelectAllTextWhenFocused = true
                editable.ClearKeyboardFocusOnCommit = false
                editable.AllowContextMenu = true
            end)
        end
        apply()
        ctx.actions.run_on_game_thread_after(1, apply, entry, editable)
        return entry, editable, nil
    end

    local function show_folder_dialog(mode, title, body, actions, want_entry, initial_text, target_pool_vm, target_pool_name)
        if ctx.state.folder_popup_state.widget ~= nil then
            local old = ctx.state.folder_popup_state.widget
            ctx.state.folder_popup_state.suppressResult = true
            pcall(function() old:OnCloseWindow() end)
            reset_folder_popup_state()
        end

        local host = ctx.common.find_first("WBP_CharacterBank_Master_C")
        if host == nil then ctx.logging.log("Create Folder dialog failed: Databank host unavailable"); return false end
        local descriptor_class, descriptor_err = ctx.widget_helpers.load_class("/Script/BitReactorGame.BitReactorGameDialogDescriptor")
        if descriptor_class == nil then ctx.logging.log("Create Folder dialog failed: " .. tostring(descriptor_err)); return false end
        local descriptor_cdo = select(1, ctx.common.try_call(function() return ctx.common.unwrap(descriptor_class:GetCDO()) end))
        if descriptor_cdo == nil then return false end
        local message_class = select(1, ctx.widget_helpers.load_class(ctx.state.GENERIC_POPUP_CLASS_PATH))
        if message_class == nil then message_class = select(1, ctx.widget_helpers.load_class(ctx.state.GENERIC_POPUP_FALLBACK_CLASS_PATH)) end
        if message_class == nil then ctx.logging.log("Create Folder dialog failed: popup class unavailable"); return false end

        local action_structs, result_actions = {}, {}
        local result_tags = { ctx.state.DIALOG_RESULT_PRIMARY, ctx.state.DIALOG_RESULT_SECONDARY }
        for i, action in ipairs(actions or {}) do
            local result_tag = result_tags[i]
            table.insert(action_structs, make_dialog_action(result_tag, action.label))
            result_actions[result_tag] = action.id
        end
        local descriptor, make_err = ctx.common.try_call(function()
            return ctx.common.unwrap(descriptor_cdo:MakeGameDialogDescriptor(
                descriptor_class, FText(title), FText(body), action_structs, message_class))
        end)
        if make_err ~= nil or descriptor == nil then ctx.logging.log("Create Folder descriptor failed: " .. tostring(make_err)); return false end
        local subsystem, subsystem_err = get_messaging_subsystem(host)
        if subsystem == nil then ctx.logging.log("Create Folder dialog failed: " .. tostring(subsystem_err)); return false end
        local popup, popup_err = ctx.common.try_call(function() return ctx.common.unwrap(subsystem:BP_ShowMessageBox(descriptor, nil)) end)
        if popup_err ~= nil or popup == nil then ctx.logging.log("Create Folder BP_ShowMessageBox failed: " .. tostring(popup_err)); return false end
        if not ensure_folder_dialog_result_hook() then return false end

        clear_named_slot_content(popup, "AboveText")
        clear_named_slot_content(popup, "Belowtext")
        ctx.state.folder_popup_state.widget = popup
        ctx.state.folder_popup_state.mode = mode
        ctx.state.folder_popup_state.resultActions = result_actions
        ctx.state.folder_popup_state.suppressResult = false
        ctx.state.folder_popup_state.initialText = tostring(initial_text or "")
        ctx.state.folder_popup_state.targetPoolVM = target_pool_vm
        ctx.state.folder_popup_state.targetPoolName = target_pool_name
        pcall(function() popup["Modal Short"] = true; popup.HideBackground = false; popup:SetVisibility(0) end)

        if want_entry then
            local entry, editable, entry_err = create_folder_entry(popup, ctx.state.folder_popup_state.initialText)
            if entry == nil or editable == nil then
                ctx.logging.log("Create Folder entry failed: " .. tostring(entry_err)); return false
            end
            local below = select(1, ctx.common.read_property(popup, "Belowtext"))
            if below == nil then return false end
            local _, set_err = ctx.common.try_call(function() below:SetContent(entry) end)
            if set_err ~= nil then return false end
            ctx.state.folder_popup_state.textBox = editable
            ctx.actions.run_on_game_thread_after(1, function()
                if ctx.state.folder_popup_state.widget == popup then pcall(function() editable:SetKeyboardFocus() end) end
            end, popup, editable)
        end

        ctx.actions.run_on_game_thread_after(1, function()
            if ctx.state.folder_popup_state.widget == popup then
                pcall(function() popup:SetVisibility(0); popup:ActivateWidget() end)
            end
        end, popup)
        ctx.logging.log("Create Folder native dialog opened: mode=" .. tostring(mode))
        return true
    end

    function ctx.popup.show_folder_notice(title, body)
        return show_folder_dialog("notice", title, body, { { id = "ok", label = "OK" } }, false)
    end

    local function style_move_destination_button(button, label)
        button = ctx.common.unwrap(button)
        if button == nil then return false end
        local text = tostring(label or "")
        pcall(function()
            button:SetButtonInteractionEnabled(true)
            button:SetIsInteractionEnabled(true)
            button:SetIsFocusable(true)
            button:SetIsSelectable(false)
            button:SetToolTipText(FText("MOVE TO " .. text))
        end)
        for _, widget in ipairs(ctx.widget_helpers.collect_widget_tree(button)) do
            local cn = ctx.common.class_name(widget)
            if string.find(cn, "RichTextBlock", 1, true) or string.find(cn, "TextBlock", 1, true) then
                pcall(function() widget:SetText(FText(text)) end)
                pcall(function() widget:SetTextEx(FText(text)) end)
            elseif string.find(cn, "Image", 1, true) then
                local w, h = ctx.folder_icons.image_dimensions(widget)
                if w >= 4.0 and h >= 4.0 and w <= 56.0 and h <= 56.0 then
                    pcall(function() widget:SetRenderOpacity(0.0); widget:SetVisibility(3) end)
                end
            end
        end
        pcall(function()
            button:UpdateText(FText(text))
            button:SetButtonText(FText(text))
            button:SetText(FText(text))
        end)
        return true
    end

    function ctx.popup.close_move_destination_picker()
        local popup = ctx.common.unwrap(ctx.state.folder_popup_state.widget)
        if popup ~= nil then
            ctx.state.folder_popup_state.suppressResult = true
            clear_named_slot_content(popup, "AboveText")
            clear_named_slot_content(popup, "Belowtext")
            pcall(function() popup:OnCloseWindow() end)
        end
        reset_folder_popup_state()
        ctx.state.folder_ui_state.moveDestinationButtons = {}
    end

    ctx.state.show_move_character_dialog = function(move_info)
        if move_info == nil then return false end
        local guid_string = tostring(move_info.guid or "")
        local source_pool_name = tostring(move_info.sourcePoolName or "")
        local character_name = tostring(move_info.name or "Character")

        local authority, authority_err = ctx.pool_authority.authoritative_pool_state()
        if authority == nil then
            ctx.logging.log("Move Character picker authority failed: " .. tostring(authority_err))
            return ctx.popup.show_folder_notice("MOVE CHARACTER FAILED", "The Character Databank state could not be verified.")
        end

        local destinations = {}
        if source_pool_name ~= tostring(authority.default_custom.name or "") then
            table.insert(destinations, {
                label = "Player Created",
                name = tostring(authority.default_custom.name or ""),
            })
        end
        for _, name in ipairs(authority.custom_order or {}) do
            if tostring(name) ~= source_pool_name then
                table.insert(destinations, { label = tostring(name), name = tostring(name) })
            end
        end

        if #destinations == 0 then
            return ctx.popup.show_folder_notice("NO DESTINATION FOLDERS",
                "Create another folder before moving '" .. character_name .. "'.")
        end

        local opened = show_folder_dialog(
            "move_character",
            "MOVE CHARACTER",
            "Move '" .. character_name .. "' to:",
            { { id = "cancel", label = "CANCEL" } },
            false,
            "",
            nil,
            nil
        )
        if not opened or ctx.state.folder_popup_state.widget == nil then return false end

        ctx.state.folder_popup_state.targetCharacterGuid = guid_string
        ctx.state.folder_popup_state.targetCharacterName = character_name
        ctx.state.folder_popup_state.sourcePoolName = source_pool_name
        ctx.state.folder_ui_state.moveDestinationButtons = {}

        local popup = ctx.common.unwrap(ctx.state.folder_popup_state.widget)
        local below = select(1, ctx.common.read_property(popup, "Belowtext"))
        if below == nil then return false end

        local list, list_err = ctx.widget_helpers.construct_widget(popup, "/Script/UMG.VerticalBox",
            "EnhancedDatabank_MoveDestinationList")
        if list == nil then
            ctx.logging.log("Move Character destination list failed: " .. tostring(list_err))
            return false
        end
        pcall(function() list:SetVisibility(4) end)

        local page = ctx.common.unwrap(ctx.state.folder_ui_state.page)
        local create_new = page and select(1, ctx.common.read_property(page, "WBP_CharacterBankCreateNewBtn")) or nil
        if create_new == nil and page ~= nil then
            create_new = ctx.widget_helpers.find_tree_widget(page, "WBP_CharacterBankCreateNewBtn_C")
        end
        if create_new == nil then
            ctx.logging.log("Move Character picker missing native button template")
            return false
        end

        for index, destination in ipairs(destinations) do
            local button, clone_err = ctx.widget_helpers.clone_widget_like(page, create_new,
                "EnhancedDatabank_MoveDestination_" .. tostring(index))
            if button == nil then
                ctx.logging.log("Move Character destination button clone failed: " .. tostring(clone_err))
            else
                style_move_destination_button(button, destination.label)
                local box, box_err = ctx.widget_helpers.construct_widget(popup, "/Script/UMG.SizeBox",
                    "EnhancedDatabank_MoveDestinationSize_" .. tostring(index))
                if box == nil then
                    ctx.logging.log("Move Character destination SizeBox failed: " .. tostring(box_err))
                else
                    pcall(function()
                        box:SetHeightOverride(48.0)
                        box:SetVisibility(4)
                    end)
                    local box_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(box:AddChild(button)) end))
                    if box_slot ~= nil then
                        pcall(function()
                            box_slot:SetHorizontalAlignment(3)
                            box_slot:SetVerticalAlignment(3)
                        end)
                        local list_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(list:AddChild(box)) end))
                        if list_slot ~= nil then
                            pcall(function()
                                list_slot:SetPadding({ Left = 0.0, Top = 3.0, Right = 0.0, Bottom = 3.0 })
                            end)
                            ctx.state.folder_ui_state.moveDestinationButtons[ctx.common.object_name(button)] = {
                                button = button,
                                guid = guid_string,
                                characterName = character_name,
                                targetPoolName = destination.name,
                                targetLabel = destination.label,
                                popup = popup,
                            }
                        end
                    end
                end
            end
        end

        -- Repaint every cloned destination control in one owned game-thread action.
        -- The old path queued one async callback per button and was the final work
        -- scheduled before the repeated-move Lua registry crash.
        ctx.actions.run_on_game_thread_after(80, function()
            if ctx.state.folder_popup_state.widget == nil or not ctx.common.same_object(ctx.state.folder_popup_state.widget, popup) then return end
            for _, info in pairs(ctx.state.folder_ui_state.moveDestinationButtons or {}) do
                if info.popup ~= nil and ctx.common.same_object(info.popup, popup)
                    and ctx.common.uobject_is_valid(info.button) then
                    style_move_destination_button(info.button, info.targetLabel)
                end
            end
        end, popup)

        local _, set_err = ctx.common.try_call(function() return below:SetContent(list) end)
        if set_err ~= nil then
            ctx.logging.log("Move Character destination list attach failed: " .. tostring(set_err))
            return false
        end
        return true
    end

    function ctx.popup.show_rename_folder_dialog(pool_vm, old_name)
        pool_vm = ctx.common.unwrap(pool_vm)
        old_name = ctx.widget_helpers.trim_string(old_name)
        if pool_vm == nil or old_name == "" then return false end
        return show_folder_dialog(
            "rename_folder",
            "RENAME FOLDER",
            "Enter a new name for '" .. tostring(old_name) .. "'.",
            { { id = "rename", label = "RENAME" }, { id = "cancel", label = "CANCEL" } },
            true,
            old_name,
            pool_vm,
            old_name
        )
    end

    function ctx.popup.current_custom_pool_count(name)
        local authority, err = ctx.pool_authority.authoritative_pool_state()
        if authority == nil then return nil, err end
        local entry = authority.custom_by_name and authority.custom_by_name[tostring(name or "")] or nil
        if entry == nil then return nil, "folder is no longer authoritative" end
        return tonumber(entry.count) or 0, nil
    end

    function ctx.popup.show_delete_folder_dialog(pool_vm, name, captured_count)
        pool_vm = ctx.common.unwrap(pool_vm)
        name = ctx.widget_helpers.trim_string(name)
        if pool_vm == nil or name == "" then return false end

        local count, count_err = ctx.popup.current_custom_pool_count(name)
        if count == nil then
            ctx.logging.log("Delete Folder preflight failed for '" .. tostring(name) .. "': " .. tostring(count_err))
            return ctx.popup.show_folder_notice("DELETE FOLDER FAILED", "The folder state could not be verified.")
        end
        if count > 0 then
            return ctx.popup.show_folder_notice(
                "FOLDER NOT EMPTY",
                "Move the " .. tostring(count) .. " character" .. (count == 1 and "" or "s")
                    .. " out of '" .. tostring(name) .. "' before deleting it."
            )
        end

        return show_folder_dialog(
            "delete_folder",
            "DELETE FOLDER",
            "Delete the empty folder '" .. tostring(name) .. "'?",
            { { id = "delete", label = "DELETE" }, { id = "cancel", label = "CANCEL" } },
            false,
            "",
            pool_vm,
            name
        )
    end

    handle_folder_dialog_result = function(widget_value, result_value)
        local widget = ctx.common.unwrap(widget_value)
        local result = ctx.common.unwrap(result_value)
        if widget == nil or ctx.state.folder_popup_state.widget == nil or not ctx.common.same_object(widget, ctx.state.folder_popup_state.widget) then return end
        if ctx.state.folder_popup_state.suppressResult then return end

        local captured_text = ""
        if ctx.state.folder_popup_state.textBox ~= nil then
            local value = select(1, ctx.common.try_call(function() return ctx.state.folder_popup_state.textBox:GetText() end))
            captured_text = ctx.common.text_value(value)
        end
        local result_tag = gameplay_tag_value(result)
        local action = result_tag and ctx.state.folder_popup_state.resultActions[result_tag] or nil
        local mode = ctx.state.folder_popup_state.mode
        local target_pool_vm = ctx.state.folder_popup_state.targetPoolVM
        local target_pool_name = ctx.state.folder_popup_state.targetPoolName
        clear_named_slot_content(widget, "AboveText")
        clear_named_slot_content(widget, "Belowtext")
        reset_folder_popup_state()
        if mode == "move_character" then ctx.state.folder_ui_state.moveDestinationButtons = {} end

        if action == nil then ctx.logging.log("Databank dialog closed with unmapped result: " .. tostring(result_tag)); return end
        ctx.logging.log("Databank dialog result: mode=" .. tostring(mode) .. " action=" .. tostring(action) .. " name='" .. tostring(captured_text) .. "'")
        if mode == "create_folder" and action == "create" then
            ctx.actions.run_on_game_thread_after(120, function() ctx.pool_mutations.perform_create_folder(captured_text) end)
        elseif mode == "rename_folder" and action == "rename" then
            ctx.actions.run_on_game_thread_after(120, function()
                ctx.pool_mutations.perform_rename_folder(target_pool_vm, target_pool_name, captured_text)
            end, target_pool_vm)
        elseif mode == "delete_folder" and action == "delete" then
            ctx.actions.run_on_game_thread_after(120, function()
                ctx.pool_mutations.perform_delete_folder(target_pool_vm, target_pool_name)
            end, target_pool_vm)
        end
    end

    function ctx.popup.show_create_folder_dialog()
        return show_folder_dialog(
            "create_folder",
            "CREATE FOLDER",
            "Enter a name for the new Character Databank folder.",
            { { id = "create", label = "CREATE" }, { id = "cancel", label = "CANCEL" } },
            true
        )
    end
end
