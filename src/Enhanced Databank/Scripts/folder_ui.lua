-- Enhanced Databank: folder ui.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: categories, actions, common, folder_icons, folder_ui, logging, pool_authority, pool_mutations, popup, runtime, state, widget_helpers.
return function(ctx)
    local function register_rename_folder_button(button, pool_vm, name, icon_canvas)
        button = ctx.common.unwrap(button)
        pool_vm = ctx.common.unwrap(pool_vm)
        if button == nil or pool_vm == nil then return false end
        local identity = ctx.common.object_name(button)
        ctx.state.folder_ui_state.renameButtons[identity] = {
            button = button,
            poolVM = pool_vm,
            name = tostring(name or ctx.pool_authority.pool_name(pool_vm)),
            iconCanvas = icon_canvas,
            visualState = nil,
        }
        return true
    end

    local function register_delete_folder_button(button, pool_vm, name, character_count, icon_canvas)
        button = ctx.common.unwrap(button)
        pool_vm = ctx.common.unwrap(pool_vm)
        if button == nil or pool_vm == nil then return false end
        local identity = ctx.common.object_name(button)
        ctx.state.folder_ui_state.deleteButtons[identity] = {
            button = button,
            poolVM = pool_vm,
            name = tostring(name or ctx.pool_authority.pool_name(pool_vm)),
            characterCount = tonumber(character_count) or 0,
            iconCanvas = icon_canvas,
            visualState = nil,
        }
        return true
    end

    local function register_move_character_button(button, character_vm, source_pool_name, icon_canvas)
        button = ctx.common.unwrap(button)
        character_vm = ctx.common.unwrap(character_vm)
        if button == nil or character_vm == nil then return false end
        local guid = ctx.pool_authority.character_guid_string(character_vm)
        if guid == nil then return false end
        local identity = ctx.common.object_name(button)
        ctx.state.folder_ui_state.moveButtons[identity] = {
            button = button,
            guid = tostring(guid),
            name = ctx.pool_authority.character_display_name(character_vm),
            sourcePoolName = tostring(source_pool_name or ""),
            iconCanvas = icon_canvas,
            visualState = nil,
        }
        return true
    end

    local function restore_panel_order_with_replacement(parent, captured, old_child, replacement)
        parent = ctx.common.unwrap(parent)
        old_child = ctx.common.unwrap(old_child)
        replacement = ctx.common.unwrap(replacement)
        if parent == nil or replacement == nil or type(captured) ~= "table" then
            return nil, "replacement order prerequisites unavailable"
        end

        -- Prefer the engine's real child insertion API. This preserves layout order
        -- instead of merely translating an appended widget over its siblings.
        local target_index = -1
        local replacement_layout = nil
        for index, entry in ipairs(captured) do
            if entry.child ~= nil and ctx.common.same_object(entry.child, old_child) then
                target_index = index - 1
                replacement_layout = entry.layout
                break
            end
        end
        if target_index < 0 then return nil, "original child missing from captured order" end

        local inserted, insert_err = ctx.common.try_call(function()
            return ctx.common.unwrap(parent:InsertChildAt(target_index, replacement))
        end)
        if insert_err == nil and inserted ~= nil and ctx.widget_helpers.panel_child_index(parent, replacement) == target_index then
            ctx.widget_helpers.apply_box_slot_layout(inserted, replacement_layout)
            return inserted, nil
        end

        -- Some shipping panels expose InsertChildAt but do not actually rebuild at
        -- runtime. Fall back to a deterministic detach/re-add pass using the exact
        -- pre-edit child order and slot metadata.
        pcall(function() parent:RemoveChild(replacement) end)
        local current = {}
        local current_count = ctx.common.panel_child_count(parent) or 0
        for i = 0, current_count - 1 do
            local child = ctx.common.panel_child_at(parent, i)
            if child ~= nil then table.insert(current, child) end
        end
        for i = #current, 1, -1 do
            pcall(function() parent:RemoveChild(current[i]) end)
        end

        local replacement_slot = nil
        for _, entry in ipairs(captured) do
            local child = entry.child
            local layout = entry.layout
            if child ~= nil then
                if ctx.common.same_object(child, old_child) then child = replacement end
                local slot, add_err = ctx.common.try_call(function() return ctx.common.unwrap(parent:AddChild(child)) end)
                if add_err ~= nil or slot == nil then
                    return nil, "failed rebuilding parent child order: " .. tostring(add_err)
                end
                ctx.widget_helpers.apply_box_slot_layout(slot, layout)
                if ctx.common.same_object(child, replacement) then replacement_slot = slot end
            end
        end

        if replacement_slot == nil then return nil, "replacement slot missing after rebuild" end
        return replacement_slot, nil
    end

    function ctx.folder_ui.install_rename_button_on_folder(page, pool_widget, folder_header, pool_vm, name, ordinal, character_count)
        page = ctx.common.unwrap(page)
        pool_widget = ctx.common.unwrap(pool_widget)
        folder_header = ctx.common.unwrap(folder_header)
        pool_vm = ctx.common.unwrap(pool_vm)
        if page == nil or pool_widget == nil or folder_header == nil or pool_vm == nil then
            return false, "folder action prerequisites unavailable"
        end

    -- Custom folders are already created by our authoritative renderer, so
        -- decorate the folder header at construction time instead of detaching and
        -- wrapping the shipping header after it is live. The shipped header owns a
        -- root Overlay_0 specifically suited to right-aligned adjunct controls.
        local host = ctx.widget_helpers.find_tree_widget(folder_header, "Overlay_0")
        if host == nil or string.find(ctx.common.class_name(host), "Overlay", 1, true) == nil then
            return false, "folder header Overlay_0 unavailable"
        end

        if ctx.widget_helpers.find_tree_widget(folder_header, "EnhancedDatabank_FolderActions_") ~= nil then
            return true, nil
        end

        local create_new = select(1, ctx.common.read_property(page, "WBP_CharacterBankCreateNewBtn"))
        if create_new == nil then create_new = ctx.widget_helpers.find_tree_widget(page, "WBP_CharacterBankCreateNewBtn_C") end
        if create_new == nil then return false, "native compact button template unavailable" end

        local suffix = tostring(ordinal or 0)

        -- Own every injected object by the folder header itself. When the dynamic
        -- folder widget is removed during an authoritative rebuild, its controls die
        -- with it; no persistent row/header UObject references are required.
        local rename_button, rename_clone_err = ctx.widget_helpers.clone_widget_like(folder_header, create_new,
            ctx.state.RENAME_FOLDER_BUTTON_MARKER .. suffix)
        if rename_button == nil then return false, rename_clone_err end
        ctx.folder_icons.style_folder_action_button(rename_button, "RENAME FOLDER")
        local rename_overlay, rename_canvas, rename_overlay_err =
            ctx.folder_icons.make_rename_folder_icon_overlay(folder_header, rename_button, suffix)
        if rename_overlay == nil then return false, rename_overlay_err end

        local delete_button, delete_clone_err = ctx.widget_helpers.clone_widget_like(folder_header, create_new,
            ctx.state.DELETE_FOLDER_BUTTON_MARKER .. suffix)
        if delete_button == nil then return false, delete_clone_err end
        ctx.folder_icons.style_folder_action_button(delete_button, "DELETE FOLDER")
        local delete_overlay, delete_canvas, delete_overlay_err =
            ctx.folder_icons.make_delete_folder_icon_overlay(folder_header, delete_button, suffix)
        if delete_overlay == nil then return false, delete_overlay_err end

        local function boxed_action(overlay, marker)
            local box, box_err = ctx.widget_helpers.construct_widget(folder_header, "/Script/UMG.SizeBox", marker .. suffix)
            if box == nil then return nil, box_err end
            pcall(function()
                box:SetWidthOverride(ctx.state.RENAME_FOLDER_BUTTON_WIDTH)
                box:SetHeightOverride(ctx.state.RENAME_FOLDER_BUTTON_HEIGHT)
                box:SetVisibility(4)
            end)
            local slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(box:AddChild(overlay)) end))
            if slot == nil then return nil, "could not add action overlay to SizeBox" end
            pcall(function() slot:SetHorizontalAlignment(0); slot:SetVerticalAlignment(0) end)
            return box, nil
        end

        local rename_box, rename_box_err = boxed_action(rename_overlay,
            "EnhancedDatabank_RenameButtonSize_")
        if rename_box == nil then return false, rename_box_err end
        local delete_box, delete_box_err = boxed_action(delete_overlay,
            "EnhancedDatabank_DeleteButtonSize_")
        if delete_box == nil then return false, delete_box_err end

        local actions, actions_err = ctx.widget_helpers.construct_widget(folder_header, "/Script/UMG.HorizontalBox",
            "EnhancedDatabank_FolderActions_" .. suffix)
        if actions == nil then return false, actions_err end
        pcall(function() actions:SetVisibility(4) end)

        local rename_action_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(actions:AddChild(rename_box)) end))
        local delete_action_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(actions:AddChild(delete_box)) end))
        if rename_action_slot == nil or delete_action_slot == nil then
            return false, "could not compose folder action row"
        end
        pcall(function()
            rename_action_slot:SetPadding({ Left = 0.0, Top = 0.0, Right = 2.0, Bottom = 0.0 })
            delete_action_slot:SetPadding({ Left = 2.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
        end)

        local actions_slot, attach_err = ctx.common.try_call(function() return ctx.common.unwrap(host:AddChild(actions)) end)
        if attach_err ~= nil or actions_slot == nil then
            return false, "could not attach folder actions to native header overlay: " .. tostring(attach_err)
        end
        pcall(function()
            actions_slot:SetHorizontalAlignment(3)
            actions_slot:SetVerticalAlignment(2)
            actions_slot:SetPadding({ Left = 0.0, Top = 0.0, Right = 4.0, Bottom = 0.0 })
        end)

        register_rename_folder_button(rename_button, pool_vm, name, rename_canvas)
        register_delete_folder_button(delete_button, pool_vm, name, character_count, delete_canvas)

        -- Create-New-derived controls can repaint their inherited '+' shortly after
        -- Construct. Strip it once immediately and once after the folder settles.
        ctx.folder_icons.style_folder_action_button(rename_button, "RENAME FOLDER")
        ctx.folder_icons.style_folder_action_button(delete_button, "DELETE FOLDER")
        ctx.actions.run_on_game_thread_after(80, function()
            local rename_info = ctx.state.folder_ui_state.renameButtons and
                ctx.state.folder_ui_state.renameButtons[ctx.common.object_name(rename_button)] or nil
            if rename_info ~= nil and ctx.common.same_object(rename_info.button, rename_button) then
                ctx.folder_icons.style_folder_action_button(rename_button, "RENAME FOLDER")
            end
            local delete_info = ctx.state.folder_ui_state.deleteButtons and
                ctx.state.folder_ui_state.deleteButtons[ctx.common.object_name(delete_button)] or nil
            if delete_info ~= nil and ctx.common.same_object(delete_info.button, delete_button) then
                ctx.folder_icons.style_folder_action_button(delete_button, "DELETE FOLDER")
            end
        end, rename_button, delete_button)

        ctx.logging.log("Folder action buttons installed at generation: pool='" .. tostring(name)
            .. "' characters=" .. tostring(tonumber(character_count) or 0))
        return true, nil
    end

    local function row_has_move_destination(source_pool_name, authority)
        if authority == nil or authority.default_custom == nil then return false end
        if tostring(source_pool_name or "") ~= tostring(authority.default_custom.name or "") then
            return true
        end
        return #(authority.custom_order or {}) > 0
    end

    local function find_character_row_action_host(row)
        row = ctx.common.unwrap(row)
        if row == nil then return nil, "character row unavailable" end

        local tree = select(1, ctx.common.read_property(row, "WidgetTree"))
        local root = tree and select(1, ctx.common.read_property(tree, "RootWidget")) or nil
        root = ctx.common.unwrap(root)

        -- Prefer the row's native root Overlay so adding the action never changes
        -- BitReactorStackBox_25 ownership or ordering.
        if root ~= nil and string.find(ctx.common.class_name(root), "Overlay", 1, true) ~= nil
            and string.find(ctx.common.object_name(root), "Tooltip", 1, true) == nil then
            return root, nil
        end

        local best, best_score = nil, -1.0
        for _, widget in ipairs(ctx.widget_helpers.collect_widget_tree(row)) do
            local cn = ctx.common.class_name(widget)
            local identity = ctx.common.object_name(widget)
            if string.find(cn, "Overlay", 1, true) ~= nil
                and string.find(identity, "Tooltip", 1, true) == nil
                and string.find(identity, "EnhancedDatabank", 1, true) == nil then
                local w, h = ctx.folder_icons.image_dimensions(widget)
                local score = math.max(0.0, w) * math.max(1.0, h)
                if score > best_score then best, best_score = widget, score end
            end
        end
        if best == nil then return nil, "no safe existing row Overlay found" end
        return best, nil
    end

    local function pool_widget_view_model(pool_widget)
        pool_widget = ctx.common.unwrap(pool_widget)
        if pool_widget == nil or not ctx.pool_authority.resolve_mdvm() then
            return nil, "pool widget/MDViewModel unavailable"
        end
        local pool_vm, err = ctx.common.try_call(function()
            return ctx.common.unwrap(ctx.pool_authority.mdvm_library_cdo:GetViewModel(pool_widget, ctx.pool_authority.pool_vm_class, FName("")))
        end)
        if err ~= nil or pool_vm == nil then
            return nil, tostring(err or "pool ViewModel unresolved")
        end
        return pool_vm, nil
    end

    local function install_move_hit_zone_on_row(pool_widget, row, character_vm, source_entry_override, compact_visual)
        pool_widget = ctx.common.unwrap(pool_widget)
        row = ctx.common.unwrap(row)
        character_vm = ctx.common.unwrap(character_vm)
        if pool_widget == nil or row == nil or character_vm == nil then
            return false, "row/pool/character unavailable"
        end
        if string.find(ctx.common.class_name(row), "WBP_CharacterBank_CreatedCharacterItem_C", 1, true) == nil then
            return false, "not a Character Databank row"
        end

        local authority, authority_err = ctx.pool_authority.authoritative_pool_state()
        if authority == nil then return false, authority_err end
        local guid = ctx.pool_authority.character_guid_string(character_vm)
        if guid == nil then return false, "character GUID unavailable" end

        -- The shipping Default pool widget does not always report the same display/save
        -- name through MDViewModel that CharacterPoolManager uses for the authoritative
    -- Default_CustomCharacters entry. Earlier implementations skipped all stock rows even
        -- though their CharacterViewModels were valid. Callers that already know the
        -- authoritative pool entry pass it directly and avoid that name round-trip.
        local source_entry = source_entry_override
        local source_pool_name = source_entry and tostring(source_entry.name or "") or nil
        if source_entry == nil then
            local pool_vm, pool_err = pool_widget_view_model(pool_widget)
            if pool_vm == nil then return false, pool_err end
            source_pool_name = ctx.pool_authority.pool_name(pool_vm)
            if tostring(authority.default_custom.name or "") == tostring(source_pool_name) then
                source_entry = authority.default_custom
            else
                source_entry = authority.custom_by_name[tostring(source_pool_name)]
            end
        end
        if source_entry == nil or not source_entry.guids[guid] then
            return false, "row ownership has not converged for " .. tostring(guid)
        end
        if not row_has_move_destination(source_pool_name, authority) then return true, nil end

        local row_identity = ctx.common.object_name(row)
        local existing = ctx.state.folder_ui_state.moveRowActions and ctx.state.folder_ui_state.moveRowActions[row_identity] or nil
        if existing ~= nil and ctx.common.unwrap(existing.hitbox) ~= nil then return true, nil end

        local safe_guid = tostring(guid):gsub("[^%w_]", "_")
        -- Re-renders must adopt any action that is already physically attached to the
        -- shipping row. The state table is intentionally rebuilt every render, but the
        -- stock row itself survives, so blindly constructing another action would leak
        -- duplicate children into that WidgetTree.
        local attached = ctx.widget_helpers.find_tree_widget(row, "EnhancedDatabank_MoveHitZone_" .. safe_guid)
        if attached ~= nil then
            local adopted = {
                row = row, hitbox = attached, button = row,
                guid = tostring(guid),
                name = ctx.pool_authority.character_display_name(character_vm),
                sourcePoolName = tostring(source_pool_name or ""),
                iconCanvas = nil, visualState = nil,
            }
            ctx.state.folder_ui_state.moveRowActions[row_identity] = adopted
            return true, nil
        end

        local host, host_err = find_character_row_action_host(row)
        if host == nil then return false, host_err end

    -- An earlier implementation placed a raw UMG Button inside this visual and bound its
        -- multicast OnClicked delegate through UE4SS. Cold Databank entry then
        -- access-violated while installing the first custom-folder row, before this
        -- function could return. Keep the proven-stable row-owned SizeBox visual;
        -- never construct or bind a raw Button in the activation/render call stack.
        local hitbox, hitbox_err = ctx.widget_helpers.construct_widget(row, "/Script/UMG.SizeBox",
            "EnhancedDatabank_MoveHitZone_" .. safe_guid)
        if hitbox == nil then return false, hitbox_err end
        pcall(function()
            hitbox:SetWidthOverride(ctx.state.MOVE_CHARACTER_BUTTON_WIDTH)
            hitbox:SetHeightOverride(ctx.state.MOVE_CHARACTER_BUTTON_HEIGHT)
            hitbox:SetVisibility(0)
            hitbox:SetToolTipText(FText("MOVE CHARACTER"))
        end)

        local icon_canvas = nil
        if compact_visual == true then
            -- Shipping rows are long-lived native widgets. Constructing the previous
            -- 11-object vector icon into each of 24 stock WidgetTrees in one render
            -- caused a native UE4SS access violation after only two rows. Keep stock
            -- decoration intentionally tiny: one SizeBox and one TextBlock rather
            -- than a cloned Blueprint/CommonUI widget tree.
            local glyph, glyph_err = ctx.widget_helpers.construct_widget(row, "/Script/UMG.TextBlock",
                "EnhancedDatabank_MoveGlyph_" .. safe_guid)
            if glyph == nil then return false, glyph_err end
            pcall(function()
                glyph:SetText(FText("⇅"))
                glyph:SetJustification(2)
                glyph:SetVisibility(4)
                glyph:SetColorAndOpacity(ctx.state.FOLDER_ICON_COLOR_NORMAL)
            end)
            local glyph_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(hitbox:AddChild(glyph)) end))
            if glyph_slot == nil then return false, "could not attach compact transfer glyph to hitbox" end
            pcall(function() glyph_slot:SetHorizontalAlignment(2); glyph_slot:SetVerticalAlignment(2) end)
        else
            local overlay, overlay_err = ctx.widget_helpers.construct_widget(row, "/Script/UMG.Overlay",
                "EnhancedDatabank_MoveHitOverlay_" .. safe_guid)
            if overlay == nil then return false, overlay_err end
            pcall(function() overlay:SetVisibility(4) end)
            local overlay_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(hitbox:AddChild(overlay)) end))
            if overlay_slot == nil then return false, "could not attach transfer overlay to hitbox" end
            pcall(function() overlay_slot:SetHorizontalAlignment(0); overlay_slot:SetVerticalAlignment(0) end)

            -- Mod-created custom folders are small, so retain the richer native
            -- transfer glyph there. They have already proven stable in this path.
            local background, bg_err = ctx.widget_helpers.construct_widget(row, "/Script/UMG.Border",
                "EnhancedDatabank_MoveHitBackground_" .. safe_guid)
            if background == nil then return false, bg_err end
            pcall(function()
                background:SetBrushColor({ R = 0.055, G = 0.050, B = 0.055, A = 0.92 })
                background:SetVisibility(4)
            end)
            local bg_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(overlay:AddChild(background)) end))
            if bg_slot ~= nil then
                pcall(function() bg_slot:SetHorizontalAlignment(0); bg_slot:SetVerticalAlignment(0) end)
            end

            local icon_size, rich_canvas, icon_err = ctx.folder_icons.build_native_transfer_icon(row, safe_guid)
            if icon_size == nil then return false, icon_err end
            icon_canvas = rich_canvas
            local icon_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(overlay:AddChild(icon_size)) end))
            if icon_slot == nil then return false, "could not attach transfer icon to hitbox" end
            pcall(function() icon_slot:SetHorizontalAlignment(2); icon_slot:SetVerticalAlignment(2) end)
        end

        local action_slot, add_err = ctx.common.try_call(function() return ctx.common.unwrap(host:AddChild(hitbox)) end)
        if add_err ~= nil or action_slot == nil then
            return false, "could not attach transfer hit-zone: " .. tostring(add_err)
        end
        pcall(function()
            action_slot:SetHorizontalAlignment(3)
            action_slot:SetVerticalAlignment(2)
            action_slot:SetPadding({
                Left = 0.0, Top = 0.0,
                Right = ctx.state.MOVE_CHARACTER_RIGHT_PADDING, Bottom = 0.0
            })
        end)

        local action_info = {
            row = row,
            hitbox = hitbox,
            button = row,
            guid = tostring(guid),
            name = ctx.pool_authority.character_display_name(character_vm),
            sourcePoolName = tostring(source_pool_name or ""),
            iconCanvas = icon_canvas,
            visualState = nil,
        }
        ctx.state.folder_ui_state.moveRowActions[row_identity] = action_info
        if icon_canvas ~= nil then ctx.folder_icons.set_icon_canvas_color(icon_canvas, ctx.state.FOLDER_ICON_COLOR_NORMAL) end
        ctx.logging.log("Move Character stable visual installed: '" .. tostring(ctx.pool_authority.character_display_name(character_vm))
            .. "' source='" .. tostring(source_pool_name) .. "' guid=" .. tostring(guid)
            .. " visual=" .. tostring(compact_visual == true and "compact" or "rich"))
        return true, nil
    end

    local function decorate_pool_rows(pool_widget, rows, label, source_entry, compact_visual)
        pool_widget = ctx.common.unwrap(pool_widget)
        if pool_widget == nil then return 0, 0 end
        local stack = select(1, ctx.common.read_property(pool_widget, "BitReactorStackBox_25"))
        if stack == nil then return 0, 0 end
        local installed, failed = 0, 0
        for index, character_vm in ipairs(rows or {}) do
            local row = ctx.common.panel_child_at(stack, index - 1)
            if row ~= nil then
                local ok, err = install_move_hit_zone_on_row(pool_widget, row, character_vm, source_entry, compact_visual)
                if ok then
                    installed = installed + 1
                else
                    failed = failed + 1
                    if err ~= nil and string.find(tostring(err), "ownership has not converged", 1, true) == nil then
                        ctx.logging.log("Move Character hit-zone decoration skipped: " .. tostring(label)
                            .. " row=" .. tostring(index - 1) .. " err=" .. tostring(err))
                    end
                end
            end
        end
        return installed, failed
    end

    local function schedule_default_pool_row_decoration(pool_widget, rows, source_entry)
        pool_widget = ctx.common.unwrap(pool_widget)
        if pool_widget == nil then return false end
        local generation = ctx.state.default_move_decor_generation
        local pool_identity = ctx.common.object_name(pool_widget)
        local total = #(rows or {})
        ctx.logging.log("Default move decoration scheduled: rows=" .. tostring(total)
            .. " generation=" .. tostring(generation))

        local function step(index)
            ctx.actions.run_on_game_thread_after(index == 1 and 30 or 18, function()
                    if generation ~= ctx.state.default_move_decor_generation then
                        ctx.logging.log("Default move decoration cancelled: stale generation=" .. tostring(generation))
                        return
                    end
                    local live_pool = ctx.common.unwrap(pool_widget)
                    if live_pool == nil or ctx.common.object_name(live_pool) ~= pool_identity then
                        ctx.logging.log("Default move decoration cancelled: shipping pool widget changed")
                        return
                    end
                    if index > total then
                        ctx.logging.log("Default move decoration complete: rows=" .. tostring(total))
                        return
                    end

                    local stack = select(1, ctx.common.read_property(live_pool, "BitReactorStackBox_25"))
                    local row = stack and ctx.common.panel_child_at(stack, index - 1) or nil
                    local character_vm = ctx.common.unwrap(rows[index])
                    if character_vm ~= nil and not ctx.common.uobject_is_valid(character_vm) then
                        ctx.logging.log("Default move decoration skipped: captured character ViewModel expired at row="
                            .. tostring(index - 1))
                        step(index + 1)
                        return
                    end
                    local name = character_vm and ctx.pool_authority.character_display_name(character_vm) or "<nil>"
                    local guid = character_vm and ctx.pool_authority.character_guid_string(character_vm) or nil
                    ctx.logging.log("Default move decoration begin: row=" .. tostring(index - 1)
                        .. " name='" .. tostring(name) .. "' guid=" .. tostring(guid))

                    if row == nil or character_vm == nil then
                        ctx.logging.log("Default move decoration skipped: row=" .. tostring(index - 1)
                            .. " rowAvailable=" .. tostring(row ~= nil)
                            .. " vmAvailable=" .. tostring(character_vm ~= nil))
                    else
                        local ok, err = install_move_hit_zone_on_row(
                            live_pool, row, character_vm, source_entry, true)
                        if not ok then
                            ctx.logging.log("Default move decoration failed: row=" .. tostring(index - 1)
                                .. " name='" .. tostring(name) .. "' err=" .. tostring(err))
                        end
                    end

                    if index < total then
                        step(index + 1)
                    else
                        ctx.logging.log("Default move decoration complete: rows=" .. tostring(total))
                    end
            end, pool_widget)
        end

        if total > 0 then step(1) end
        return true
    end

    local function cleanup_move_row_wrappers(pool_widget)
    -- The release implementation never wraps, reparents, polls, or shares controls between character
        -- rows. Each action is owned by the row that generated it.
        return 0
    end

    local function button_identity(widget)
        return ctx.common.object_name(widget)
    end

    local function register_folder_button(button)
        local identity = button_identity(button)
        ctx.state.folder_ui_state.buttons[identity] = true
        ctx.state.folder_ui_state.button = button
        ctx.logging.log("Create Folder button registered: " .. tostring(identity))
    end

    local function hovered_move_row_action()
        for _, info in pairs(ctx.state.folder_ui_state.moveRowActions or {}) do
            local hitbox = info and ctx.common.unwrap(info.hitbox) or nil
            if hitbox ~= nil then
                local hovered = false
                pcall(function() hovered = hitbox:IsHovered() == true end)
                if hovered then return info end
            end
        end
        return nil
    end

    function ctx.folder_ui.schedule_move_character_dialog(move_info, source)
        if move_info == nil or ctx.state.folder_ui_state.moveClickScheduled then return false end
        local delayed_move_info = {
            guid = tostring(move_info.guid or ""),
            name = tostring(move_info.name or "Character"),
            sourcePoolName = tostring(move_info.sourcePoolName or ""),
            category = move_info.category or ctx.state.folder_ui_state.category,
        }
        ctx.state.folder_ui_state.moveClickScheduled = true
        ctx.logging.log("Move Character transfer hit-zone clicked via " .. tostring(source or "unknown")
            .. ": '" .. tostring(move_info.name) .. "' source='" .. tostring(move_info.sourcePoolName) .. "'")
        ctx.actions.run_on_game_thread_after(1, function()
            ctx.state.folder_ui_state.moveClickScheduled = false
            ctx.state.show_move_character_dialog(delayed_move_info)
        end)
        return true
    end

    function ctx.folder_ui.install_folder_button_click_hook()
        if ctx.state.folder_button_click_hook_registered then return true end
        local ok, hook_id = pcall(function()
            return ctx.runtime:register_hook(
                "/Script/CommonUI.CommonButtonBase:HandleButtonClicked",
                function(self)
                    local button = ctx.common.unwrap(self)
                    local identity = button and button_identity(button) or nil
                    if identity == nil then return end

                    -- Character rows still own the native CommonUI click surface. The
                    -- lightweight transfer SizeBox can receive hover/tooltip state but
                    -- does not consume mouse clicks. Route any CommonUI click occurring
                    -- while a transfer hit-zone is hovered before handling the ordinary
                    -- row selection. This is the same native click stream already used
                    -- reliably by Create/Rename/Delete and avoids constructing 20+ extra
                    -- Blueprint buttons on the Default pool.
                    local hovered_move = hovered_move_row_action()
                    if hovered_move ~= nil then
                        ctx.folder_ui.schedule_move_character_dialog(hovered_move, "CommonUI.HandleButtonClicked")
                        return
                    end

                    local destination_info = ctx.state.folder_ui_state.moveDestinationButtons
                        and ctx.state.folder_ui_state.moveDestinationButtons[identity] or nil
                    if destination_info ~= nil then
                        ctx.logging.log("Move Character destination clicked: '" .. tostring(destination_info.characterName)
                            .. "' -> '" .. tostring(destination_info.targetLabel) .. "'")
                        local guid = tostring(destination_info.guid or "")
                        local target = tostring(destination_info.targetPoolName or "")
                        local character_name = tostring(destination_info.characterName or "Character")
                        local category = destination_info.category

                        -- Do not tear down the popup from inside the destination
                        -- button's HandleButtonClicked call stack. Doing so destroys
                        -- widgets while CommonUI/UE4SS are still dispatching that exact
    -- widget's native click, which caused an earlier crash. Mark the
                        -- click consumed, let the native callback return, then close on
                        -- a later game-thread turn and only move after the outro starts.
                        ctx.state.folder_popup_state.suppressResult = true
                        ctx.state.folder_ui_state.moveDestinationButtons = {}
                        ctx.actions.run_on_game_thread_after(75, function()
                            ctx.logging.log("Move Character deferred picker close begin")
                            ctx.popup.close_move_destination_picker()
                            ctx.logging.log("Move Character deferred picker close complete")
                            ctx.actions.run_on_game_thread_after(125, function()
                                ctx.pool_mutations.perform_move_character(guid, target, character_name, category)
                            end)
                        end, destination_info.popup)
                        return
                    end

                    if ctx.state.folder_ui_state.category ~= ctx.categories.current() then return end

                    local move_info = ctx.state.folder_ui_state.moveButtons and ctx.state.folder_ui_state.moveButtons[identity] or nil
                    if move_info ~= nil then
                        if move_info.selectedDetail == true then
                            local resolved, resolve_err = require("selected_move_button").resolve_move_info({
                                unwrap = ctx.common.unwrap,
                                tryCall = ctx.common.try_call,
                                objectName = ctx.common.object_name,
                                log = ctx.logging.log,
                                findFirst = ctx.common.find_first,
                                readProperty = ctx.common.read_property,
                                findMembership = function(selected_row)
                                    local category = ctx.state.folder_ui_state.category
                                    local authority, authority_err = ctx.pool_authority.authoritative_pool_state(category)
                                    if authority == nil then return nil, authority_err end
                                    local page, databank_vm, _, stock_widget, default_vm =
                                        ctx.databank_ui.resolve_live_page(category)
                                    if page == nil or databank_vm == nil
                                        or stock_widget == nil or default_vm == nil then
                                        return nil, "Character Databank page/ViewModels unavailable."
                                    end

                                    local function result_for(pool_widget, rows, entry, is_default)
                                        pool_widget = ctx.common.unwrap(pool_widget)
                                        if pool_widget == nil or entry == nil then return nil end
                                        local stack = select(1, ctx.common.read_property(
                                            pool_widget, "BitReactorStackBox_25"))
                                        local row_index = stack and ctx.widget_helpers.panel_child_index(stack, selected_row) or -1
                                        if row_index < 0 then return nil end

                                        local candidate, guid = nil, nil
                                        if rows ~= nil then
                                            candidate = ctx.common.unwrap(rows[row_index + 1])
                                        else
                                            local items = select(1, ctx.common.read_property(
                                                default_vm, "PoolCharacterViewModels"))
                                            local display_index =
                                                ctx.pool_authority.character_display_index(items)
                                            candidate, guid = ctx.pool_authority.character_for_row(
                                                selected_row, display_index)
                                        end

                                        guid = guid or (candidate and
                                            ctx.pool_authority.character_guid_string(candidate) or nil)
                                        ctx.logging.log("Selected-character row-identity candidate: pool='"
                                            .. tostring(entry.name or "") .. "' rowIndex="
                                            .. tostring(row_index) .. " guid=" .. tostring(guid))
                                        if guid == nil or not entry.guids[guid] then
                                            return nil, "The selected row no longer matches its authoritative pool."
                                        end
                                        if is_default and #(authority.custom_order or {}) == 0 then
                                            return nil, "Create another Character folder before moving this character."
                                        end
                                        return {
                                            guid = tostring(guid),
                                            name = ctx.pool_authority.character_display_name(candidate),
                                            sourcePoolName = tostring(entry.name or ""),
                                            category = category,
                                        }, nil
                                    end

                                    -- The shipping pool remains wholly native. Resolve
                                    -- the selected row by its rendered identity instead
                                    -- of assuming its current stack index matches the
                                    -- stale typed ViewModel array.
                                    local found, found_err = result_for(
                                        stock_widget, nil, authority.default_custom, true)
                                    if found ~= nil or found_err ~= nil then return found, found_err end

                                    -- Dynamic records contain the exact ordered VM
                                    -- list used to construct each visible pool.
                                    for _, rendered_pool in ipairs(ctx.state.folder_ui_state.renderedPools or {}) do
                                        found, found_err = result_for(
                                            rendered_pool.widget,
                                            rendered_pool.rows,
                                            rendered_pool.entry,
                                            false)
                                        if found ~= nil or found_err ~= nil then return found, found_err end
                                    end
                                    return nil, "The selected character is not in a movable custom-character pool."
                                end,
                            })
                            if resolved == nil then
                                ctx.logging.log("Selected-character Move unavailable: " .. tostring(resolve_err))
                                ctx.popup.show_folder_notice("MOVE CHARACTER UNAVAILABLE", tostring(resolve_err))
                                return
                            end
                            move_info = resolved
                        end
                        ctx.logging.log("Move Character detail action clicked: '" .. tostring(move_info.name)
                            .. "' source='" .. tostring(move_info.sourcePoolName) .. "'")
                        ctx.folder_ui.schedule_move_character_dialog(move_info, "selected-character detail button")
                        return
                    end

                    local rename_info = ctx.state.folder_ui_state.renameButtons and ctx.state.folder_ui_state.renameButtons[identity] or nil
                    if rename_info ~= nil then
                        ctx.logging.log("Rename Folder edit icon clicked: '" .. tostring(rename_info.name) .. "'")
                        local target_pool_vm = rename_info.poolVM
                        local target_pool_name = tostring(rename_info.name or "")
                        ctx.actions.run_on_game_thread_after(1, function()
                            ctx.popup.show_rename_folder_dialog(target_pool_vm, target_pool_name)
                        end, target_pool_vm)
                        return
                    end

                    local delete_info = ctx.state.folder_ui_state.deleteButtons and ctx.state.folder_ui_state.deleteButtons[identity] or nil
                    if delete_info ~= nil then
                        ctx.logging.log("Delete Folder trash icon clicked: '" .. tostring(delete_info.name)
                            .. "' capturedCount=" .. tostring(delete_info.characterCount))
                        local target_pool_vm = delete_info.poolVM
                        local target_pool_name = tostring(delete_info.name or "")
                        local character_count = tonumber(delete_info.characterCount) or 0
                        ctx.actions.run_on_game_thread_after(1, function()
                            ctx.popup.show_delete_folder_dialog(target_pool_vm, target_pool_name, character_count)
                        end, target_pool_vm)
                        return
                    end

                    if not ctx.state.folder_ui_state.buttons[identity] then return end
                    ctx.logging.log("Create Folder icon clicked; deferring dialog until native click unwinds.")
                    local category = ctx.state.folder_ui_state.category
                    ctx.actions.run_on_game_thread_after(1, function()
                        ctx.popup.show_create_folder_dialog(category)
                    end)
                end
            )
        end)
        if ok and hook_id ~= nil then
            ctx.state.folder_button_click_hook_registered = true
            ctx.logging.log("Create Folder button click hook registered.")
            return true
        end
        ctx.logging.log("Create Folder click hook failed: " .. tostring(hook_id))
        return false
    end

    local function set_registered_action_icon_state(button, hovered)
        button = ctx.common.unwrap(button)
        if button == nil then return end
        local identity = button_identity(button)
        if ctx.state.folder_ui_state.button ~= nil and ctx.common.same_object(ctx.state.folder_ui_state.button, button) then
            ctx.folder_icons.set_folder_icon_color(
                hovered and ctx.state.FOLDER_ICON_COLOR_HOVER or ctx.state.FOLDER_ICON_COLOR_NORMAL,
                hovered and "hover" or "normal"
            )
            return
        end
        local info = (ctx.state.folder_ui_state.moveRowActions and ctx.state.folder_ui_state.moveRowActions[identity])
            or (ctx.state.folder_ui_state.moveButtons and ctx.state.folder_ui_state.moveButtons[identity])
            or (ctx.state.folder_ui_state.renameButtons and ctx.state.folder_ui_state.renameButtons[identity])
            or (ctx.state.folder_ui_state.deleteButtons and ctx.state.folder_ui_state.deleteButtons[identity])
        if info == nil then return end
        if info.button ~= nil and not ctx.common.same_object(info.button, button) then return end
        if info.row ~= nil and not ctx.common.same_object(info.row, button) then return end
        local canvas = ctx.common.unwrap(info.iconCanvas)
        if canvas == nil then return end
        ctx.folder_icons.set_icon_canvas_color(canvas, hovered and ctx.state.FOLDER_ICON_COLOR_HOVER or ctx.state.FOLDER_ICON_COLOR_NORMAL)
        info.visualState = hovered and "hover" or "normal"
    end

    function ctx.folder_ui.install_action_hover_hooks()
        if ctx.state.action_hover_hooks_registered then return true end
        local ok_hover, hover_id = pcall(function()
            return ctx.runtime:register_hook("/Script/CommonUI.CommonButtonBase:BP_OnHovered", function(context, ...)
                set_registered_action_icon_state(context, true)
            end)
        end)
        local ok_unhover, unhover_id = pcall(function()
            return ctx.runtime:register_hook("/Script/CommonUI.CommonButtonBase:BP_OnUnhovered", function(context, ...)
                set_registered_action_icon_state(context, false)
            end)
        end)
        if ok_hover and hover_id ~= nil and ok_unhover and unhover_id ~= nil then
            ctx.state.action_hover_hooks_registered = true
            ctx.logging.log("Registered event-driven hover tint hooks for Databank action icons.")
            return true
        end
        ctx.logging.log("Databank action hover hook unavailable: hover=" .. tostring(hover_id)
            .. " unhover=" .. tostring(unhover_id))
        return false
    end

    function ctx.folder_ui.ensure_create_folder_control(page)
        if page == nil then return false end
        page = ctx.common.unwrap(page)
        ctx.state.folder_ui_state.page = page
        local page_id = ctx.common.object_name(page)
        if ctx.state.folder_ui_state.pageIdentity ~= page_id then
            ctx.state.folder_ui_state.pageIdentity = page_id
            ctx.state.folder_ui_state.row = nil
            ctx.state.folder_ui_state.button = nil
            ctx.state.folder_ui_state.buttons = {}
            ctx.state.folder_ui_state.iconCanvas = nil
            ctx.state.folder_ui_state.iconOverlay = nil
            ctx.state.folder_ui_state.iconVisualState = nil
            ctx.state.folder_ui_state.moveButtons = {}
            ctx.state.folder_ui_state.moveRowActions = {}
            ctx.state.folder_ui_state.moveDestinationButtons = {}
            ctx.state.folder_ui_state.moveClickScheduled = false
        end

        if ctx.common.uobject_is_valid(ctx.state.folder_ui_state.button) then
            local parent = select(1, ctx.common.try_call(function() return ctx.common.unwrap(ctx.state.folder_ui_state.button:GetParent()) end))
            if parent ~= nil then return true end
        end

        local adopted = ctx.widget_helpers.find_tree_widget(page, ctx.state.CREATE_FOLDER_BUTTON_MARKER)
        if not ctx.common.uobject_is_valid(adopted) then
            -- Blueprint clones can keep their generated UObject name when Rename
            -- is unavailable. Tab switches clear our registry, but leave the old
            -- controls attached. Recover the button from our named native overlay
            -- so returning to a page does not append another control/shrink its row.
            local overlay = ctx.widget_helpers.find_tree_widget(page, "EnhancedDatabank_CreateFolderOverlay")
            local count = overlay and ctx.common.panel_child_count(overlay) or 0
            for index = 0, (count or 0) - 1 do
                local child = ctx.common.panel_child_at(overlay, index)
                if ctx.common.uobject_is_valid(child)
                    and string.find(ctx.common.class_name(child), "WBP_CharacterBankCreateNewBtn_C", 1, true) ~= nil then
                    adopted = child
                    break
                end
            end
        end
        if ctx.common.uobject_is_valid(adopted) then
            register_folder_button(adopted)
            ctx.state.folder_ui_state.row = select(1, ctx.common.try_call(function() return ctx.common.unwrap(adopted:GetParent()) end))
            ctx.state.folder_ui_state.iconCanvas = ctx.widget_helpers.find_tree_widget(page, "EnhancedDatabank_FolderPlusCanvas")
            ctx.state.folder_ui_state.iconOverlay = ctx.widget_helpers.find_tree_widget(page, "EnhancedDatabank_CreateFolderOverlay")
            ctx.folder_icons.style_create_folder_icon_button(page, adopted)
            ctx.folder_icons.set_folder_icon_color(ctx.state.FOLDER_ICON_COLOR_NORMAL, "normal")
            return true
        end

        local create_new = select(1, ctx.common.read_property(page, "WBP_CharacterBankCreateNewBtn"))
        if create_new == nil then create_new = ctx.widget_helpers.find_tree_widget(page, "WBP_CharacterBankCreateNewBtn_C") end
        if create_new == nil then ctx.logging.log("Create Folder UI pending: native Create New widget unavailable"); return false end
        local parent = select(1, ctx.common.try_call(function() return ctx.common.unwrap(create_new:GetParent()) end))
        if parent == nil then ctx.logging.log("Create Folder UI pending: native Create New parent unavailable"); return false end
        local create_index = ctx.widget_helpers.panel_child_index(parent, create_new)
        if create_index < 0 then return false end
        local create_layout = ctx.widget_helpers.capture_box_slot_layout(create_new)

        local icon_button, clone_err = ctx.widget_helpers.clone_widget_like(page, create_new, ctx.state.CREATE_FOLDER_BUTTON_MARKER)
        if icon_button == nil then ctx.logging.log("Create Folder clone failed: " .. tostring(clone_err)); return false end

        -- Character Share may already have replaced the native Create New slot
        -- with its cooperative action row. Join that flat row rather than nesting
        -- another HorizontalBox inside its Create New SizeBox. This keeps the
        -- result at Create New | Import | Create Folder regardless of load order.
        local character_share_row = ctx.widget_helpers.find_tree_widget(page, "CharacterShare_CreateImportRow")
        local character_share_create_wrapper = ctx.widget_helpers.find_tree_widget(page, "CharacterShare_CreateNewWidth")
        if character_share_create_wrapper == nil then
            -- Compatibility with Character Share 1.0.1's old half-width wrapper.
            character_share_create_wrapper = ctx.widget_helpers.find_tree_widget(page, "CharacterShare_CreateNewHalf")
        end
        if character_share_row ~= nil and character_share_create_wrapper ~= nil
            and ctx.widget_helpers.panel_child_index(character_share_row, character_share_create_wrapper) >= 0 then
            local wrapper_width = ctx.widget_helpers.widget_local_width(character_share_create_wrapper)
            if wrapper_width == nil or wrapper_width < 120.0 then wrapper_width = 628.0 end
            local resized_width = math.max(120.0,
                wrapper_width - ctx.state.CREATE_FOLDER_ICON_WIDTH - ctx.state.CREATE_FOLDER_GAP)

            local icon_overlay, overlay_err = ctx.folder_icons.make_create_folder_icon_overlay(page, icon_button)
            local icon_wrapper = nil
            if icon_overlay ~= nil then
                icon_wrapper = select(1, ctx.widget_helpers.make_width_wrapper(page, icon_overlay,
                    "EnhancedDatabank_CreateFolderWidth", ctx.state.CREATE_FOLDER_ICON_WIDTH))
            end
            if icon_wrapper == nil then
                ctx.logging.log("Create Folder could not join Character Share row: " .. tostring(overlay_err))
                return false
            end

            local icon_slot = select(1, ctx.common.try_call(function()
                return ctx.common.unwrap(character_share_row:AddChild(icon_wrapper))
            end))
            if icon_slot == nil then
                ctx.logging.log("Create Folder could not append to Character Share row")
                return false
            end
            ctx.widget_helpers.configure_row_slot(icon_slot, ctx.state.CREATE_FOLDER_GAP)
            pcall(function() character_share_create_wrapper:SetWidthOverride(resized_width) end)

            register_folder_button(icon_button)
            ctx.state.folder_ui_state.row = character_share_row
            ctx.folder_icons.style_create_folder_icon_button(page, icon_button)
            ctx.folder_icons.set_folder_icon_color(ctx.state.FOLDER_ICON_COLOR_NORMAL, "normal")
            ctx.actions.run_on_game_thread_after(80, function()
                if ctx.common.same_object(ctx.state.folder_ui_state.button, icon_button) then
                    ctx.folder_icons.style_create_folder_icon_button(page, icon_button)
                end
            end, page, icon_button)
            ctx.logging.log(string.format(
                "Create Folder joined Character Share action row: previousCreateWidth=%.1f createWidth=%.1f iconWidth=%.1f",
                wrapper_width, resized_width, ctx.state.CREATE_FOLDER_ICON_WIDTH))
            return true
        end

        local row, row_err = ctx.widget_helpers.construct_widget(page, "/Script/UMG.HorizontalBox", ctx.state.CREATE_FOLDER_ROW_MARKER)
        if row == nil then ctx.logging.log("Create Folder row failed: " .. tostring(row_err)); return false end

        local original_width = ctx.widget_helpers.widget_local_width(create_new)
        if original_width == nil or original_width < 200.0 then original_width = 700.0 end
        local create_width = math.max(120.0, original_width - ctx.state.CREATE_FOLDER_ICON_WIDTH - ctx.state.CREATE_FOLDER_GAP)

        local removed = select(1, ctx.common.try_call(function() return parent:RemoveChild(create_new) end))
        if removed ~= true then ctx.logging.log("Create Folder UI could not detach Create New safely"); return false end

        local create_wrapper = select(1, ctx.widget_helpers.make_width_wrapper(page, create_new, "EnhancedDatabank_CreateNewWidth", create_width))
        local icon_overlay, overlay_err = ctx.folder_icons.make_create_folder_icon_overlay(page, icon_button)
        local icon_wrapper = nil
        if icon_overlay ~= nil then
            icon_wrapper = select(1, ctx.widget_helpers.make_width_wrapper(page, icon_overlay,
                "EnhancedDatabank_CreateFolderWidth", ctx.state.CREATE_FOLDER_ICON_WIDTH))
        end
        if create_wrapper == nil or icon_wrapper == nil then
            pcall(function() parent:AddChild(create_new) end)
            ctx.logging.log("Create Folder width/icon overlay failed; Create New restored: " .. tostring(overlay_err))
            return false
        end
        local create_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(row:AddChild(create_wrapper)) end))
        local icon_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(row:AddChild(icon_wrapper)) end))
        if create_slot == nil or icon_slot == nil then return false end
        ctx.widget_helpers.configure_row_slot(create_slot, 0.0)
        ctx.widget_helpers.configure_row_slot(icon_slot, ctx.state.CREATE_FOLDER_GAP)

        local row_slot, add_err = ctx.common.try_call(function() return ctx.common.unwrap(parent:AddChild(row)) end)
        if add_err ~= nil or row_slot == nil then ctx.logging.log("Create Folder row attach failed: " .. tostring(add_err)); return false end
        ctx.widget_helpers.apply_box_slot_layout(row_slot, create_layout)
        local moved, move_err = ctx.widget_helpers.visually_move_appended_child_to_index(parent, row, create_index, "vertical")
        if not moved then ctx.logging.log("Create Folder row visual ordering failed: " .. tostring(move_err)) end

        register_folder_button(icon_button)
        ctx.state.folder_ui_state.row = row
        ctx.folder_icons.style_create_folder_icon_button(page, icon_button)
        ctx.folder_icons.set_folder_icon_color(ctx.state.FOLDER_ICON_COLOR_NORMAL, "normal")
        ctx.actions.run_on_game_thread_after(80, function()
            if ctx.common.same_object(ctx.state.folder_ui_state.button, icon_button) then ctx.folder_icons.style_create_folder_icon_button(page, icon_button) end
        end, page, icon_button)
        ctx.logging.log(string.format("Create Folder icon installed beside Create New: originalWidth=%.1f createWidth=%.1f iconWidth=%.1f",
            original_width, create_width, ctx.state.CREATE_FOLDER_ICON_WIDTH))
        return true
    end
end
