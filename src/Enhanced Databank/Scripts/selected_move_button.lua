local M = {}

local BUTTON_MARKER = "EnhancedDatabank_SelectedMoveButton"
local SPACER_MARKER = "EnhancedDatabank_SelectedMoveSpacer"
local pages = {}

local function set_button_label(button, deps)
    if button == nil then return end
    pcall(function() button:UpdateText(FText("MOVE")) end)
    pcall(function() button:SetButtonText(FText("MOVE")) end)
    pcall(function() button:SetText(FText("MOVE")) end)

    local text = deps.findTreeWidget(button, "BitReactorRichTextBlock_74")
    if text ~= nil then
        pcall(function() text:SetTextEx(FText("MOVE")) end)
        pcall(function() text:SetText(FText("MOVE")) end)
    end
end

local function parent_of(widget, deps)
    local parent, err = deps.tryCall(function() return deps.unwrap(widget:GetParent()) end)
    if err ~= nil then return nil end
    return parent
end

local function find_native_spacer(parent, deps)
    local count = deps.panelChildCount(parent) or 0
    for index = 0, count - 1 do
        local child = deps.panelChildAt(parent, index)
        if child ~= nil and string.find(deps.className(child), "Spacer", 1, true) ~= nil then
            return child
        end
    end
    return nil
end

local function register(button, deps)
    deps.register(button)
    set_button_label(button, deps)
    deps.log("Selected-character Move button attached+registered: " .. deps.objectName(button))
end

local function copy_native_button_style(template, button, deps)
    -- Do not guess enum ordinals. An earlier build hard-coded the values
    -- used by an older Character Share revision and this game build rendered
    -- the clone as INVALID BUTTON TYPE. Copy the live, already-valid Edit
    -- button's scalar style inputs before asking the clone to ApplyStyle.
    for _, property_name in ipairs({ "ButtonOrientation", "ButtonSize", "ButtonType" }) do
        local value = select(1, deps.readProperty(template, property_name))
        if value ~= nil then pcall(function() button[property_name] = value end) end
    end
    pcall(function() button:ApplyStyle() end)
end

function M.ensure(page, deps)
    page = deps.unwrap(page)
    if page == nil then return false, "humanoid page unavailable" end

    local page_identity = deps.objectName(page)
    local prior = pages[page_identity]
    local prior_button = prior and deps.unwrap(prior.button) or nil
    if prior_button ~= nil and parent_of(prior_button, deps) ~= nil then
        register(prior_button, deps)
        return true, nil
    end

    local attached = deps.findTreeWidget(page, BUTTON_MARKER)
    if attached ~= nil and parent_of(attached, deps) ~= nil then
        pages[page_identity] = { button = attached }
        register(attached, deps)
        return true, nil
    end

    local edit = select(1, deps.readProperty(page, "Button_Edit"))
    if edit == nil then return false, "native Button_Edit unavailable" end
    local parent = parent_of(edit, deps)
    if parent == nil then return false, "native character action row unavailable" end

    local edit_layout = deps.captureSlotLayout(edit)
    local button, clone_err = deps.cloneWidgetLike(page, edit, BUTTON_MARKER)
    if button == nil then return false, "native Edit-button clone failed: " .. tostring(clone_err) end

    pcall(function()
        button:SetButtonInteractionEnabled(true)
        button:SetIsInteractionEnabled(true)
        button:SetIsFocusable(true)
        button:SetIsSelectable(false)
        button:SetToolTipText(FText("MOVE CHARACTER"))
    end)
    copy_native_button_style(edit, button, deps)
    set_button_label(button, deps)

    -- Character Share proved this action row uses explicit native Spacer
    -- children. Copy the first spacer's size/layout, but leave every shipping
    -- child attached and append our two screen-owned objects at the far right.
    local spacer = nil
    local native_spacer = find_native_spacer(parent, deps)
    if native_spacer ~= nil then
        local candidate, spacer_err = deps.constructWidget(page, "/Script/UMG.Spacer", SPACER_MARKER)
        if candidate ~= nil then
            local native_size = select(1, deps.readProperty(native_spacer, "Size"))
            if native_size ~= nil then pcall(function() candidate:SetSize(native_size) end) end
            local spacer_slot, add_err = deps.tryCall(function()
                return deps.unwrap(parent:AddChild(candidate))
            end)
            if add_err == nil and spacer_slot ~= nil then
                deps.applySlotLayout(spacer_slot, deps.captureSlotLayout(native_spacer))
                spacer = candidate
            else
                pcall(function() candidate:RemoveFromParent() end)
            end
        else
            deps.log("Selected-character Move spacer skipped: " .. tostring(spacer_err))
        end
    end

    local slot, add_err = deps.tryCall(function() return deps.unwrap(parent:AddChild(button)) end)
    if add_err ~= nil or slot == nil then
        pcall(function() button:RemoveFromParent() end)
        if spacer ~= nil then pcall(function() spacer:RemoveFromParent() end) end
        return false, "native action button append failed: " .. tostring(add_err)
    end
    deps.applySlotLayout(slot, edit_layout)

    pages[page_identity] = { button = button, spacer = spacer }
    register(button, deps)
    deps.log("Selected-character Move button installed beside native character actions.")
    return true, nil
end

function M.resolve_move_info(deps)
    local aux = deps.findFirst("CharacterBankAuxVM_C")
    if aux == nil then return nil, "Select a saved Custom Character first." end
    local detail_vm = deps.unwrap(select(1, deps.readProperty(aux, "CharacterVM")))
    local selected_row = deps.unwrap(select(1, deps.readProperty(aux, "SelectedCharacterButton")))
    if detail_vm == nil or selected_row == nil then
        return nil, "Select a saved Custom Character first."
    end

    -- The generic MDViewModel binding for this row is an opaque proxy with a
    -- different UObject identity from the same entry in the typed pool array.
    -- Pass the concrete selected row instead. The caller finds its owning pool
    -- and index, then reads the typed VM used to render that position.
    local membership, membership_err = deps.findMembership(selected_row)
    if membership == nil then
        deps.log("Selected-character row-position lookup failed: row="
            .. deps.objectName(selected_row))
        return nil, tostring(membership_err or
            "The selected character is not in a movable custom-character pool.")
    end

    deps.log("Selected-character ownership resolved by row position: row="
        .. deps.objectName(selected_row) .. " guid=" .. tostring(membership.guid)
        .. " source='" .. tostring(membership.sourcePoolName) .. "'")
    return membership, nil
end

return M
