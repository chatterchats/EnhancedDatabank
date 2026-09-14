-- Enhanced Databank: folder icons.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: common, folder_icons, logging, state, widget_helpers.
return function(ctx)
    function ctx.folder_icons.image_dimensions(widget)
        pcall(function() widget:ForceLayoutPrepass() end)
        local w, h = nil, nil
        pcall(function()
            local g = widget:GetCachedGeometry(); local size = g and g:GetLocalSize() or nil
            if size ~= nil then w, h = tonumber(size.X), tonumber(size.Y) end
        end)
        if w == nil or h == nil or w <= 0.5 or h <= 0.5 then
            pcall(function()
                local size = widget:GetDesiredSize(); if size ~= nil then w, h = tonumber(size.X), tonumber(size.Y) end
            end)
        end
        return w or 0.0, h or 0.0
    end

    function ctx.folder_icons.style_create_folder_icon_button(page, button)
        pcall(function()
            button:SetButtonInteractionEnabled(true)
            button:SetIsInteractionEnabled(true)
            button:SetIsFocusable(true)
            button:SetIsSelectable(false)
            button:SetToolTipText(FText("CREATE FOLDER"))
        end)

        -- The shipping Create New widget rebuilds its own + glyph during Construct.
        -- Keep its native button/background interaction, but hide compact image
        -- descendants that can plausibly be that inherited glyph. The replacement
        -- folder-plus mark is built entirely from native UMG Borders, avoiding the
        -- runtime external-texture path that rendered as a solid white square.
        local images = {}
        local text_changed = 0
        local hidden_glyph_images = 0
        for _, widget in ipairs(ctx.widget_helpers.collect_widget_tree(button)) do
            local cn = ctx.common.class_name(widget)
            if string.find(cn, "RichTextBlock", 1, true) or string.find(cn, "TextBlock", 1, true) then
                pcall(function() widget:SetText(FText("")); text_changed = text_changed + 1 end)
                pcall(function() widget:SetTextEx(FText("")); text_changed = text_changed + 1 end)
            elseif string.find(cn, "Image", 1, true) then
                local w, h = ctx.folder_icons.image_dimensions(widget)
                table.insert(images, { widget = widget, w = w, h = h })
                if w >= 4.0 and h >= 4.0 and w <= 56.0 and h <= 56.0 then
                    local ok = pcall(function()
                        widget:SetRenderOpacity(0.0)
                        widget:SetVisibility(3)
                    end)
                    if ok then hidden_glyph_images = hidden_glyph_images + 1 end
                end
            end
        end
        pcall(function() button:UpdateText(FText("")); button:SetButtonText(FText("")); button:SetText(FText("")) end)

        ctx.logging.log("Create Folder icon button styled: textChanges=" .. tostring(text_changed)
            .. " images=" .. tostring(#images)
            .. " inheritedGlyphImagesHidden=" .. tostring(hidden_glyph_images)
            .. " nativeVectorIcon=" .. tostring(ctx.state.folder_ui_state.iconCanvas ~= nil))
        return true
    end

    local function add_icon_rect(page, canvas, name, x, y, w, h)
        local rect, rect_err = ctx.widget_helpers.construct_widget(page, "/Script/UMG.Border", name)
        if rect == nil then return nil, rect_err end
        pcall(function()
            rect:SetBrushColor(ctx.state.FOLDER_ICON_COLOR)
            rect:SetVisibility(4)
        end)
        local slot, slot_err = ctx.common.try_call(function() return ctx.common.unwrap(canvas:AddChildToCanvas(rect)) end)
        if slot_err ~= nil or slot == nil then return nil, tostring(slot_err or "AddChildToCanvas returned nil") end
        pcall(function()
            slot:SetPosition({ X = x, Y = y })
            slot:SetSize({ X = w, Y = h })
            slot:SetAutoSize(false)
        end)
        return rect, nil
    end

    function ctx.folder_icons.set_folder_icon_color(color, state_name)
        local canvas = ctx.state.folder_ui_state.iconCanvas
        if canvas == nil or color == nil then return false end

        local count = ctx.common.panel_child_count(canvas) or 0
        local changed = 0
        for i = 0, count - 1 do
            local child = ctx.common.panel_child_at(canvas, i)
            if child ~= nil and string.find(ctx.common.class_name(child), "Border", 1, true) ~= nil then
                local ok = pcall(function() child:SetBrushColor(color) end)
                if ok then changed = changed + 1 end
            end
        end

        ctx.state.folder_ui_state.iconVisualState = state_name or ctx.state.folder_ui_state.iconVisualState
        return changed > 0
    end

    local function build_native_folder_plus_icon(page)
        local size_box, size_err = ctx.widget_helpers.construct_widget(page, "/Script/UMG.SizeBox",
            "EnhancedDatabank_FolderPlusSize")
        if size_box == nil then return nil, nil, size_err end
        pcall(function()
            size_box:SetWidthOverride(ctx.state.CREATE_FOLDER_GLYPH_SIZE)
            size_box:SetHeightOverride(ctx.state.CREATE_FOLDER_GLYPH_SIZE)
            size_box:SetVisibility(4)
        end)

        local canvas, canvas_err = ctx.widget_helpers.construct_widget(page, "/Script/UMG.CanvasPanel",
            "EnhancedDatabank_FolderPlusCanvas")
        if canvas == nil then return nil, nil, canvas_err end
        pcall(function() canvas:SetVisibility(4) end)

        local canvas_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(size_box:AddChild(canvas)) end))
        if canvas_slot == nil then return nil, nil, "could not add folder-plus CanvasPanel to SizeBox" end
        pcall(function() canvas_slot:SetHorizontalAlignment(3); canvas_slot:SetVerticalAlignment(3) end)

        -- 28x28, Tabler-inspired folder-plus silhouette made from native rectangles.
        -- Folder body: tab/top, left/right walls, bottom.
        local rects = {
            { "L", 3.0, 8.0, 2.4, 15.5 },
            { "TabTop", 4.8, 5.0, 8.3, 2.4 },
            { "TabRise", 11.5, 6.5, 2.4, 3.1 },
            { "Top", 4.5, 8.0, 16.8, 2.4 },
            { "Right", 20.0, 8.5, 2.4, 10.2 },
            { "Bottom", 4.0, 21.0, 14.8, 2.4 },
            -- Plus sign in lower-right, slightly outside the folder body.
            { "PlusH", 17.0, 18.2, 9.0, 2.4 },
            { "PlusV", 20.3, 14.9, 2.4, 9.0 },
        }
        for _, spec in ipairs(rects) do
            local _, err = add_icon_rect(page, canvas,
                "EnhancedDatabank_FolderPlus_" .. spec[1],
                spec[2], spec[3], spec[4], spec[5])
            if err ~= nil then return nil, nil, err end
        end

        return size_box, canvas, nil
    end

    function ctx.folder_icons.make_create_folder_icon_overlay(page, button)
        local overlay, overlay_err = ctx.widget_helpers.construct_widget(page, "/Script/UMG.Overlay",
            "EnhancedDatabank_CreateFolderOverlay")
        if overlay == nil then return nil, overlay_err end
        pcall(function() overlay:SetVisibility(4) end)

        local button_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(overlay:AddChild(button)) end))
        if button_slot == nil then return nil, "could not add cloned button to icon overlay" end
        pcall(function()
            button_slot:SetHorizontalAlignment(3)
            button_slot:SetVerticalAlignment(3)
        end)

        local icon_size, icon_canvas, icon_err = build_native_folder_plus_icon(page)
        if icon_size == nil then return nil, icon_err end

        local icon_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(overlay:AddChild(icon_size)) end))
        if icon_slot == nil then return nil, "could not add native folder-plus icon to overlay" end
        pcall(function()
            icon_slot:SetHorizontalAlignment(2)
            icon_slot:SetVerticalAlignment(2)
        end)

        -- The native Create New clone's visual center sits a touch left/up of the
        -- raw Overlay center. Nudge only our glyph so the button hitbox/layout
        -- remains identical while the folder-plus reads optically centered.
        pcall(function()
            icon_size:SetRenderTranslation({ X = -4.0, Y = -4.0 })
        end)

        ctx.state.folder_ui_state.iconCanvas = icon_canvas
        ctx.state.folder_ui_state.iconOverlay = overlay
        return overlay, nil
    end

    function ctx.folder_icons.set_icon_canvas_color(canvas, color)
        canvas = ctx.common.unwrap(canvas)
        if canvas == nil or color == nil then return false end
        local count = ctx.common.panel_child_count(canvas) or 0
        local changed = 0
        for i = 0, count - 1 do
            local child = ctx.common.panel_child_at(canvas, i)
            if child ~= nil and string.find(ctx.common.class_name(child), "Border", 1, true) ~= nil then
                if pcall(function() child:SetBrushColor(color) end) then changed = changed + 1 end
            end
        end
        return changed > 0
    end

    local function add_edit_icon_rect(owner, canvas, name, x, y, w, h, angle)
        -- Rename/Delete icons share a 22x22 design grid. Scale the entire
        -- geometry uniformly while keeping the surrounding button and hitbox fixed.
        x = x * ctx.state.RENAME_FOLDER_GLYPH_SCALE
        y = y * ctx.state.RENAME_FOLDER_GLYPH_SCALE
        w = w * ctx.state.RENAME_FOLDER_GLYPH_SCALE
        h = h * ctx.state.RENAME_FOLDER_GLYPH_SCALE

        local rect, rect_err = ctx.widget_helpers.construct_widget(owner, "/Script/UMG.Border", name)
        if rect == nil then return nil, rect_err end
        pcall(function()
            rect:SetBrushColor(ctx.state.FOLDER_ICON_COLOR_NORMAL)
            rect:SetVisibility(4)
            if angle ~= nil and math.abs(angle) > 0.01 then rect:SetRenderTransformAngle(angle) end
        end)
        local slot, slot_err = ctx.common.try_call(function() return ctx.common.unwrap(canvas:AddChildToCanvas(rect)) end)
        if slot_err ~= nil or slot == nil then return nil, tostring(slot_err or "AddChildToCanvas returned nil") end
        pcall(function()
            slot:SetPosition({ X = x, Y = y })
            slot:SetSize({ X = w, Y = h })
            slot:SetAutoSize(false)
        end)
        return rect, nil
    end

    local function build_native_edit_icon(owner, suffix)
        local size_box, size_err = ctx.widget_helpers.construct_widget(owner, "/Script/UMG.SizeBox",
            "EnhancedDatabank_EditSize_" .. tostring(suffix))
        if size_box == nil then return nil, nil, size_err end
        pcall(function()
            size_box:SetWidthOverride(ctx.state.RENAME_FOLDER_GLYPH_SIZE)
            size_box:SetHeightOverride(ctx.state.RENAME_FOLDER_GLYPH_SIZE)
            size_box:SetVisibility(4)
        end)

        local canvas, canvas_err = ctx.widget_helpers.construct_widget(owner, "/Script/UMG.CanvasPanel",
            "EnhancedDatabank_EditCanvas_" .. tostring(suffix))
        if canvas == nil then return nil, nil, canvas_err end
        pcall(function() canvas:SetVisibility(4) end)
        local canvas_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(size_box:AddChild(canvas)) end))
        if canvas_slot == nil then return nil, nil, "could not add edit CanvasPanel to SizeBox" end
        pcall(function() canvas_slot:SetHorizontalAlignment(0); canvas_slot:SetVerticalAlignment(0) end)

        -- Tabler-inspired Edit silhouette. The incomplete square gives the familiar
        -- "edit" context while the diagonal stroke reads as the pencil.
        local rects = {
            { "Left",      3.0,  5.5, 2.0, 13.5,  0.0 },
            { "Bottom",    3.0, 17.0, 12.0, 2.0,  0.0 },
            { "TopLeft",   3.0,  5.5, 8.0,  2.0,  0.0 },
            { "RightLow", 13.0, 14.0, 2.0,  5.0,  0.0 },
            { "Pencil",    8.1,  9.9, 12.5, 2.2, -45.0 },
            { "Eraser",   15.4,  4.8, 4.3,  2.2, -45.0 },
            { "Tip",       5.3, 14.6, 4.0,  2.2, -45.0 },
        }
        for _, spec in ipairs(rects) do
            local _, err = add_edit_icon_rect(owner, canvas,
                "EnhancedDatabank_Edit_" .. tostring(suffix) .. "_" .. spec[1],
                spec[2], spec[3], spec[4], spec[5], spec[6])
            if err ~= nil then return nil, nil, err end
        end
        return size_box, canvas, nil
    end

    local function build_native_trash_icon(owner, suffix)
        local size_box, size_err = ctx.widget_helpers.construct_widget(owner, "/Script/UMG.SizeBox",
            "EnhancedDatabank_TrashSize_" .. tostring(suffix))
        if size_box == nil then return nil, nil, size_err end
        pcall(function()
            size_box:SetWidthOverride(ctx.state.RENAME_FOLDER_GLYPH_SIZE)
            size_box:SetHeightOverride(ctx.state.RENAME_FOLDER_GLYPH_SIZE)
            size_box:SetVisibility(4)
        end)

        local canvas, canvas_err = ctx.widget_helpers.construct_widget(owner, "/Script/UMG.CanvasPanel",
            "EnhancedDatabank_TrashCanvas_" .. tostring(suffix))
        if canvas == nil then return nil, nil, canvas_err end
        pcall(function() canvas:SetVisibility(4) end)
        local canvas_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(size_box:AddChild(canvas)) end))
        if canvas_slot == nil then return nil, nil, "could not add trash CanvasPanel to SizeBox" end
        pcall(function() canvas_slot:SetHorizontalAlignment(0); canvas_slot:SetVerticalAlignment(0) end)

        -- Tabler-inspired trash outline made from the same native rectangles used
        -- by the other header controls. Keeping it native avoids texture-loading
        -- differences under UE4SS/Wine.
        local rects = {
            { "Lid",       4.0,  5.0, 14.0, 2.0 },
            { "Handle",    8.0,  2.8,  6.0, 2.0 },
            { "Left",      5.5,  7.5,  2.0, 10.5 },
            { "Right",    14.5,  7.5,  2.0, 10.5 },
            { "Bottom",    6.0, 17.0, 10.0, 2.0 },
            { "InnerL",    9.0,  9.0,  1.6,  6.0 },
            { "InnerR",   12.0,  9.0,  1.6,  6.0 },
        }
        for _, spec in ipairs(rects) do
            local _, err = add_edit_icon_rect(owner, canvas,
                "EnhancedDatabank_Trash_" .. tostring(suffix) .. "_" .. spec[1],
                spec[2], spec[3], spec[4], spec[5], 0.0)
            if err ~= nil then return nil, nil, err end
        end
        return size_box, canvas, nil
    end

    function ctx.folder_icons.build_native_transfer_icon(owner, suffix)
        local size_box, size_err = ctx.widget_helpers.construct_widget(owner, "/Script/UMG.SizeBox",
            "EnhancedDatabank_TransferSize_" .. tostring(suffix))
        if size_box == nil then return nil, nil, size_err end
        pcall(function()
            size_box:SetWidthOverride(ctx.state.RENAME_FOLDER_GLYPH_SIZE)
            size_box:SetHeightOverride(ctx.state.RENAME_FOLDER_GLYPH_SIZE)
            size_box:SetVisibility(4)
        end)

        local canvas, canvas_err = ctx.widget_helpers.construct_widget(owner, "/Script/UMG.CanvasPanel",
            "EnhancedDatabank_TransferCanvas_" .. tostring(suffix))
        if canvas == nil then return nil, nil, canvas_err end
        pcall(function() canvas:SetVisibility(4) end)
        local canvas_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(size_box:AddChild(canvas)) end))
        if canvas_slot == nil then return nil, nil, "could not add transfer CanvasPanel to SizeBox" end
        pcall(function() canvas_slot:SetHorizontalAlignment(0); canvas_slot:SetVerticalAlignment(0) end)

        -- Tabler transfer-vertical visual language: one arrow travels upward on the
        -- left, the other downward on the right.
        local rects = {
            { "UpShaft",    6.0,  5.0, 2.0, 13.0,   0.0 },
            { "UpHeadL",    3.9,  4.7, 5.5, 2.0, -45.0 },
            { "UpHeadR",    6.7,  4.7, 5.5, 2.0,  45.0 },
            { "DownShaft", 14.0,  4.0, 2.0, 13.0,   0.0 },
            { "DownHeadL", 10.7, 16.2, 5.5, 2.0,  45.0 },
            { "DownHeadR", 13.6, 16.2, 5.5, 2.0, -45.0 },
        }
        for _, spec in ipairs(rects) do
            local _, err = add_edit_icon_rect(owner, canvas,
                "EnhancedDatabank_Transfer_" .. tostring(suffix) .. "_" .. spec[1],
                spec[2], spec[3], spec[4], spec[5], spec[6])
            if err ~= nil then return nil, nil, err end
        end
        return size_box, canvas, nil
    end

    function ctx.folder_icons.style_folder_action_button(button, tooltip)
        button = ctx.common.unwrap(button)
        if button == nil then return false end
        pcall(function()
            button:SetButtonInteractionEnabled(true)
            button:SetIsInteractionEnabled(true)
            button:SetIsFocusable(true)
            button:SetIsSelectable(false)
            button:SetToolTipText(FText(tostring(tooltip or "")))
        end)
        for _, widget in ipairs(ctx.widget_helpers.collect_widget_tree(button)) do
            local cn = ctx.common.class_name(widget)
            if string.find(cn, "RichTextBlock", 1, true) or string.find(cn, "TextBlock", 1, true) then
                pcall(function() widget:SetText(FText("")) end)
                pcall(function() widget:SetTextEx(FText("")) end)
            elseif string.find(cn, "Image", 1, true) then
                local w, h = ctx.folder_icons.image_dimensions(widget)
                if w >= 4.0 and h >= 4.0 and w <= 56.0 and h <= 56.0 then
                    pcall(function() widget:SetRenderOpacity(0.0); widget:SetVisibility(3) end)
                end
            end
        end
        pcall(function() button:UpdateText(FText("")); button:SetButtonText(FText("")); button:SetText(FText("")) end)
        return true
    end

    local function style_rename_folder_button(button)
        return ctx.folder_icons.style_folder_action_button(button, "RENAME FOLDER")
    end

    function ctx.folder_icons.make_rename_folder_icon_overlay(owner, button, suffix)
        local overlay, overlay_err = ctx.widget_helpers.construct_widget(owner, "/Script/UMG.Overlay",
            "EnhancedDatabank_RenameButtonOverlay_" .. tostring(suffix))
        if overlay == nil then return nil, nil, overlay_err end
        pcall(function() overlay:SetVisibility(4) end)

        local button_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(overlay:AddChild(button)) end))
        if button_slot == nil then return nil, nil, "could not add rename button to overlay" end
        pcall(function() button_slot:SetHorizontalAlignment(0); button_slot:SetVerticalAlignment(0) end)

        local icon_size, icon_canvas, icon_err = build_native_edit_icon(owner, suffix)
        if icon_size == nil then return nil, nil, icon_err end
        local icon_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(overlay:AddChild(icon_size)) end))
        if icon_slot == nil then return nil, nil, "could not add edit icon to rename overlay" end
        pcall(function() icon_slot:SetHorizontalAlignment(2); icon_slot:SetVerticalAlignment(2) end)
        return overlay, icon_canvas, nil
    end

    function ctx.folder_icons.make_delete_folder_icon_overlay(owner, button, suffix)
        local overlay, overlay_err = ctx.widget_helpers.construct_widget(owner, "/Script/UMG.Overlay",
            "EnhancedDatabank_DeleteButtonOverlay_" .. tostring(suffix))
        if overlay == nil then return nil, nil, overlay_err end
        pcall(function() overlay:SetVisibility(4) end)

        local button_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(overlay:AddChild(button)) end))
        if button_slot == nil then return nil, nil, "could not add delete button to overlay" end
        pcall(function() button_slot:SetHorizontalAlignment(0); button_slot:SetVerticalAlignment(0) end)

        local icon_size, icon_canvas, icon_err = build_native_trash_icon(owner, suffix)
        if icon_size == nil then return nil, nil, icon_err end
        local icon_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(overlay:AddChild(icon_size)) end))
        if icon_slot == nil then return nil, nil, "could not add trash icon to delete overlay" end
        pcall(function() icon_slot:SetHorizontalAlignment(2); icon_slot:SetVerticalAlignment(2) end)
        return overlay, icon_canvas, nil
    end

    local function make_move_character_icon_overlay(owner, button, suffix)
        local overlay, overlay_err = ctx.widget_helpers.construct_widget(owner, "/Script/UMG.Overlay",
            "EnhancedDatabank_MoveCharacterButtonOverlay_" .. tostring(suffix))
        if overlay == nil then return nil, nil, overlay_err end
        pcall(function() overlay:SetVisibility(4) end)

        local button_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(overlay:AddChild(button)) end))
        if button_slot == nil then return nil, nil, "could not add move button to overlay" end
        pcall(function() button_slot:SetHorizontalAlignment(0); button_slot:SetVerticalAlignment(0) end)

        local icon_size, icon_canvas, icon_err = ctx.folder_icons.build_native_transfer_icon(owner, suffix)
        if icon_size == nil then return nil, nil, icon_err end
        local icon_slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(overlay:AddChild(icon_size)) end))
        if icon_slot == nil then return nil, nil, "could not add transfer icon to move overlay" end
        pcall(function() icon_slot:SetHorizontalAlignment(2); icon_slot:SetVerticalAlignment(2) end)
        return overlay, icon_canvas, nil
    end
end
