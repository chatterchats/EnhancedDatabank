-- Native category bindings verified against the game's Databank type dump.
return function(ctx)
    ctx.categories.custom = {
        id = "custom", page = "OtherCharacterList", default_type = 4, custom_type = 5,
        default_vm = "DefaultCustomCharacterPoolViewModel",
        pools_vm = "CustomCharacterPoolViewModels",
    }
    ctx.categories.astromech = {
        id = "astromech", page = "AstromechCharacterList", default_type = 2, custom_type = 3,
        default_vm = "DefaultAstromechCharacterPoolViewModel",
        -- This native array property is singular, unlike CustomCharacterPoolViewModels.
        pools_vm = "AstromechCharacterPoolViewModel",
    }
    local active = ctx.categories.custom

    function ctx.categories.for_page(page)
        if page == nil then return nil end
        local identity = ctx.common.object_name(page)
        for _, category in ipairs({ ctx.categories.custom, ctx.categories.astromech }) do
            if identity:match("[%.:]" .. category.page .. "$") or identity == category.page then
                return category
            end
        end
    end

    function ctx.categories.activate(page)
        local category = ctx.categories.for_page(ctx.common.unwrap(page))
        if category == nil then return false end
        active = category
        return true
    end

    -- Recover the visible tab when reloading while the Databank is already open.
    -- Activation callbacks remain the fallback during native initialization.
    function ctx.categories.sync_active_page(master)
        for _, category in ipairs({ ctx.categories.custom, ctx.categories.astromech }) do
            local page = select(1, ctx.common.read_property(master, category.page))
            if ctx.common.uobject_is_valid(page) then
                local activated = select(1, ctx.common.try_call(function() return page:IsActivated() end))
                if activated == true then
                    active = category
                    return active
                end
            end
        end
        return active
    end

    function ctx.categories.current()
        return active
    end
end
