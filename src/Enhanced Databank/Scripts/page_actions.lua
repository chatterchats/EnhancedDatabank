-- Extend the shipping page's Default-only empty-pool gate to rendered folders.
-- No row reconstruction, synthetic characters, or replacement action handlers.
return function(ctx)
    local base = "/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/"
        .. "WBP_CharacterBank_Page_CharacterList.WBP_CharacterBank_Page_CharacterList_C:"
    local installed = {}
    local repaired_page = nil

    function ctx.page_actions.reconcile(page)
        page = ctx.common.unwrap(page)
        local state = ctx.state.folder_ui_state
        if not ctx.common.uobject_is_valid(page) or state == nil
            or not ctx.common.same_object(page, state.page) then return end
        local category = ctx.categories.for_page(page)
        if category == nil then return end
        local authority = ctx.pool_authority.authoritative_pool_state(category)
        if authority == nil then return end
        -- A populated Default pool already has the shipping behavior we want.
        if authority.default_custom.count > 0 then
            repaired_page = nil
            return
        end

        local has_characters = false
        for _, name in ipairs(authority.custom_order) do
            local entry = authority.custom_by_name[name]
            if entry and entry.count > 0 then has_characters = true; break end
        end
        if not has_characters and repaired_page ~= ctx.common.object_name(page) then return end

        -- Use the page's selection, not a global AuxVM which can belong to the
        -- other tab. Verify it is a current rendered row and still manager-owned.
        local selected = select(1, ctx.common.read_property(page, "Selected Character Button"))
        local selected_is_current = false
        if has_characters and ctx.common.uobject_is_valid(selected) then
            local parent = select(1, ctx.common.try_call(function() return selected:GetParent() end))
            for _, pool in ipairs(state.renderedPools or {}) do
                local entry = authority.custom_by_name[pool.name]
                if entry and ctx.common.uobject_is_valid(pool.widget) then
                    local stack = select(1, ctx.common.read_property(pool.widget, "BitReactorStackBox_25"))
                    if ctx.common.uobject_is_valid(stack) and ctx.common.same_object(parent, stack) then
                        for index = 0, (ctx.common.panel_child_count(stack) or 0) - 1 do
                            if ctx.common.same_object(ctx.common.panel_child_at(stack, index), selected) then
                                local vm = pool.rows[index + 1]
                                local guid = vm and ctx.pool_authority.character_guid_string(vm)
                                selected_is_current = guid ~= nil and entry.guids[guid] == true
                                break
                            end
                        end
                        break
                    end
                end
            end
        end

        local controls = select(1, ctx.common.read_property(page, "ControlButtons"))
        if not ctx.common.uobject_is_valid(controls) then return end
        local _, err = ctx.common.try_call(function()
            page.isPoolNotEmpty = has_characters
            -- ESlateVisibility: Visible=0, Collapsed=1, as used by stock-row reconciliation.
            controls:SetVisibility(selected_is_current and 0 or 1)
        end)
        if err ~= nil then
            ctx.logging.log("Empty-Default action reconciliation failed: " .. tostring(err))
            return
        end
        repaired_page = ctx.common.object_name(page)
        ctx.logging.log("Empty-Default action reconciliation: category=" .. category.id
            .. " hasCharacters=" .. tostring(has_characters)
            .. " selected=" .. tostring(selected_is_current))
    end

    function ctx.page_actions.ensure(page)
        -- Called only after a live page has rendered, so these Blueprint functions
        -- are resident. For /Game functions UE4SS's second argument is a POST hook.
        for _, name in ipairs({
            "CheckForPool",
            "BndEvt__WBP_CharacterBank_Page_CharacterList_CharacterBankAuxVM_C_MDVMNode_ViewModelFieldNotify_7_SelectedCharacterButton",
        }) do
            if not installed[name] then
                local ok, err = pcall(function()
                    ctx.runtime:register_hook(base .. name, function(context)
                        ctx.page_actions.reconcile(context)
                    end)
                end)
                if ok then installed[name] = true
                else ctx.logging.log("Empty-Default action hook pending: " .. tostring(err)) end
            end
        end
        ctx.page_actions.reconcile(page)
    end
end
