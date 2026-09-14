-- Enhanced Databank: widget helpers.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: common, widget_helpers.
return function(ctx)
    function ctx.widget_helpers.trim_string(value)
        local s = tostring(value or "")
        s = s:gsub("^%s+", "")
        s = s:gsub("%s+$", "")
        return s
    end

    function ctx.widget_helpers.load_class(path)
        local class_object, err = ctx.common.resolve_class(path)
        if class_object ~= nil then return class_object, nil end
        local package_path = tostring(path):match("^([^%.]+)")
        if package_path ~= nil then
            pcall(function() LoadAsset(package_path) end)
            class_object, err = ctx.common.resolve_class(path)
        end
        if class_object == nil then
            return nil, tostring(err or ("class unavailable: " .. tostring(path)))
        end
        return class_object, nil
    end

    function ctx.widget_helpers.create_user_widget(world_context, widget_class)
        if world_context == nil or widget_class == nil then
            return nil, "missing world context/class"
        end
        local library_class, class_err = ctx.widget_helpers.load_class("/Script/UMG.WidgetBlueprintLibrary")
        if library_class == nil then return nil, class_err end
        local library, cdo_err = ctx.common.try_call(function() return ctx.common.unwrap(library_class:GetCDO()) end)
        if cdo_err ~= nil or library == nil then
            return nil, "WidgetBlueprintLibrary CDO unavailable"
        end
        local owning_player = nil
        pcall(function() owning_player = ctx.common.unwrap(world_context:GetOwningPlayer()) end)
        local widget, create_err = ctx.common.try_call(function()
            return ctx.common.unwrap(library:Create(world_context, widget_class, owning_player))
        end)
        if create_err ~= nil or widget == nil then
            return nil, tostring(create_err or "Create returned nil")
        end
        return widget, nil
    end

    function ctx.widget_helpers.construct_widget(owner, class_path, name)
        local tree = select(1, ctx.common.read_property(owner, "WidgetTree"))
        if tree == nil then return nil, "WidgetTree unavailable" end
        local widget_class, class_err = ctx.widget_helpers.load_class(class_path)
        if widget_class == nil then return nil, class_err end
        local widget, err = ctx.common.try_call(function()
            return ctx.common.unwrap(StaticConstructObject(widget_class, tree, FName(name), 0, 0, false, false, nil))
        end)
        if err ~= nil or widget == nil then
            return nil, tostring(err or "StaticConstructObject returned nil")
        end
        return widget, nil
    end

    function ctx.widget_helpers.collect_widget_tree(user_widget)
        local widgets = {}
        user_widget = ctx.common.unwrap(user_widget)
        if user_widget == nil then return widgets end

        local tree = select(1, ctx.common.read_property(user_widget, "WidgetTree"))
        if tree == nil then return widgets end

        local root = select(1, ctx.common.read_property(tree, "RootWidget"))
        root = ctx.common.unwrap(root)
        if root == nil then return widgets end

        local function visit(widget)
            widget = ctx.common.unwrap(widget)
            if widget == nil then return end
            table.insert(widgets, widget)

            local count = nil
            pcall(function() count = tonumber(widget:GetChildrenCount()) end)
            if count == nil or count <= 0 then return end

            for index = 0, count - 1 do
                local child = nil
                pcall(function() child = ctx.common.unwrap(widget:GetChildAt(index)) end)
                if child ~= nil then visit(child) end
            end
        end

        visit(root)
        return widgets
    end

    function ctx.widget_helpers.find_tree_widget(user_widget, needle)
        needle = tostring(needle or "")
        if needle == "" then return nil end

        for _, widget in ipairs(ctx.widget_helpers.collect_widget_tree(user_widget)) do
            local identity = ctx.common.object_name(widget)
            local klass = ctx.common.class_name(widget)
            if string.find(identity, needle, 1, true) ~= nil
                or string.find(klass, needle, 1, true) ~= nil then
                return widget
            end
        end
        return nil
    end

    function ctx.widget_helpers.panel_child_index(parent, child)
        local count = ctx.common.panel_child_count(parent) or 0
        for i = 0, count - 1 do
            if ctx.common.same_object(ctx.common.panel_child_at(parent, i), child) then return i end
        end
        return -1
    end

    local function numeric_struct_field(value, field_name)
        if value == nil then return 0.0 end
        local field = nil
        pcall(function() field = value[field_name] end)
        return tonumber(field) or 0.0
    end

    local function widget_render_translation(widget)
        local transform = select(1, ctx.common.read_property(widget, "RenderTransform"))
        local translation = transform and select(1, ctx.common.read_property(transform, "Translation")) or nil
        if translation == nil then return 0.0, 0.0 end
        return numeric_struct_field(translation, "X"), numeric_struct_field(translation, "Y")
    end

    local function set_widget_render_translation(widget, x, y)
        local _, err = ctx.common.try_call(function()
            widget:SetRenderTranslation({ X = x or 0.0, Y = y or 0.0 })
        end)
        return err == nil
    end

    local function widget_axis_extent(widget, axis)
        if widget == nil then return 0.0 end
        pcall(function() widget:ForceLayoutPrepass() end)
        local extent = nil
        pcall(function()
            local geometry = widget:GetCachedGeometry()
            local size = geometry and geometry:GetLocalSize() or nil
            if size ~= nil then extent = tonumber(axis == "vertical" and size.Y or size.X) end
        end)
        if extent == nil or extent <= 0.5 then
            pcall(function()
                local desired = widget:GetDesiredSize()
                if desired ~= nil then extent = tonumber(axis == "vertical" and desired.Y or desired.X) end
            end)
        end
        extent = extent or 0.0
        local slot = select(1, ctx.common.read_property(widget, "Slot"))
        local padding = slot and select(1, ctx.common.read_property(slot, "Padding")) or nil
        if padding ~= nil then
            if axis == "vertical" then
                extent = extent + numeric_struct_field(padding, "Top") + numeric_struct_field(padding, "Bottom")
            else
                extent = extent + numeric_struct_field(padding, "Left") + numeric_struct_field(padding, "Right")
            end
        end
        return math.max(0.0, extent)
    end

    function ctx.widget_helpers.visually_move_appended_child_to_index(parent, child, target_index, axis)
        pcall(function() parent:ForceLayoutPrepass() end)
        local count = ctx.common.panel_child_count(parent)
        if count == nil or count <= 0 then return false, "parent child count unavailable" end
        local appended_index = ctx.widget_helpers.panel_child_index(parent, child)
        if appended_index ~= count - 1 then return false, "child is not final appended child" end
        if target_index < 0 or target_index > appended_index then return false, "invalid target index" end
        if target_index == appended_index then return true, nil end

        local shifted, shifted_extent = {}, 0.0
        for i = target_index, appended_index - 1 do
            local sibling = ctx.common.panel_child_at(parent, i)
            local extent = widget_axis_extent(sibling, axis)
            if sibling == nil or extent <= 0.5 then
                return false, "could not measure sibling " .. tostring(i)
            end
            local x, y = widget_render_translation(sibling)
            table.insert(shifted, { widget = sibling, extent = extent, x = x, y = y })
            shifted_extent = shifted_extent + extent
        end
        local child_extent = widget_axis_extent(child, axis)
        if child_extent <= 0.5 then return false, "could not measure appended child" end
        local cx, cy = widget_render_translation(child)
        for _, entry in ipairs(shifted) do
            local nx, ny = entry.x, entry.y
            if axis == "vertical" then ny = ny + child_extent else nx = nx + child_extent end
            if not set_widget_render_translation(entry.widget, nx, ny) then
                return false, "sibling translation failed"
            end
        end
        if axis == "vertical" then cy = cy - shifted_extent else cx = cx - shifted_extent end
        if not set_widget_render_translation(child, cx, cy) then return false, "child translation failed" end
        return true, nil
    end

    function ctx.widget_helpers.capture_box_slot_layout(child)
        local layout = {}
        local slot = select(1, ctx.common.read_property(child, "Slot"))
        if slot == nil then return layout end
        local specs = {
            { "Padding", "GetPadding" }, { "Size", "GetSize" },
            { "HorizontalAlignment", "GetHorizontalAlignment" },
            { "VerticalAlignment", "GetVerticalAlignment" },
        }
        for _, spec in ipairs(specs) do
            local value = nil
            pcall(function() value = slot[spec[2]](slot) end)
            if value == nil then value = select(1, ctx.common.read_property(slot, spec[1])) end
            if value ~= nil then layout[spec[1]] = value end
        end
        return layout
    end

    function ctx.widget_helpers.apply_box_slot_layout(slot, layout)
        if slot == nil or layout == nil then return end
        if layout.Padding ~= nil then pcall(function() slot:SetPadding(layout.Padding) end) end
        if layout.Size ~= nil then pcall(function() slot:SetSize(layout.Size) end) end
        if layout.HorizontalAlignment ~= nil then
            pcall(function() slot:SetHorizontalAlignment(layout.HorizontalAlignment) end)
        end
        if layout.VerticalAlignment ~= nil then
            pcall(function() slot:SetVerticalAlignment(layout.VerticalAlignment) end)
        end
    end

    function ctx.widget_helpers.widget_local_width(widget)
        pcall(function() widget:ForceLayoutPrepass() end)
        local width = nil
        pcall(function()
            local g = widget:GetCachedGeometry()
            local size = g and g:GetLocalSize() or nil
            if size ~= nil then width = tonumber(size.X) end
        end)
        if width ~= nil and width > 1.0 then return width end
        pcall(function()
            local size = widget:GetDesiredSize()
            if size ~= nil then width = tonumber(size.X) end
        end)
        if width ~= nil and width > 1.0 then return width end
        return nil
    end

    function ctx.widget_helpers.make_width_wrapper(owner, child, name, width)
        local wrapper, err = ctx.widget_helpers.construct_widget(owner, "/Script/UMG.SizeBox", name)
        if wrapper == nil then return nil, nil, err end
        if width ~= nil then pcall(function() wrapper:SetWidthOverride(width) end) end
        local slot = select(1, ctx.common.try_call(function() return ctx.common.unwrap(wrapper:AddChild(child)) end))
        if slot == nil then return nil, nil, "could not add child to SizeBox" end
        pcall(function()
            slot:SetHorizontalAlignment(3)
            slot:SetVerticalAlignment(3)
        end)
        return wrapper, slot, nil
    end

    function ctx.widget_helpers.configure_row_slot(slot, left_padding)
        if slot == nil then return end
        pcall(function() slot:SetSize({ Value = 1.0, SizeRule = 0 }) end)
        pcall(function()
            slot:SetPadding({ Left = left_padding or 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
        end)
        pcall(function()
            slot:SetHorizontalAlignment(3)
            slot:SetVerticalAlignment(2)
        end)
    end

    function ctx.widget_helpers.clone_widget_like(page, template, name)
        local widget_class = select(1, ctx.common.try_call(function() return ctx.common.unwrap(template:GetClass()) end))
        if widget_class == nil then return nil, "template class unavailable" end
        local widget, err = ctx.widget_helpers.create_user_widget(page, widget_class)
        if widget == nil then return nil, err end
        pcall(function() widget:Rename(FName(name), page) end)
        return widget, nil
    end
end
