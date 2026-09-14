-- Enhanced Databank: actions.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: actions, common, config, runtime.
return function(ctx)
    ctx.actions.api = { groups = {}, runtime = ctx.runtime }

    function ctx.actions.api.cancel_group(group, reason)
        local actions = ctx.actions.api.groups[group]
        if actions == nil then return 0 end
        ctx.actions.api.groups[group] = nil

        local cancelled = 0
        local active = 0
        for handle in pairs(actions) do
            local valid = select(1, ctx.common.try_call(function()
                return IsValidDelayedActionHandle(handle)
            end))
            local is_active = select(1, ctx.common.try_call(function()
                return IsDelayedActionActive(handle)
            end))
            if is_active == true then active = active + 1 end
            if valid == true then
                local did_cancel = select(1, ctx.common.try_call(function()
                    return CancelDelayedAction(handle)
                end))
                if did_cancel == true then
                    cancelled = cancelled + 1
                    ctx.runtime:finish_action(handle)
                end
            end
        end

        if cancelled > 0 then
            print(ctx.config.PREFIX .. " Cancelled delayed-action group '" .. tostring(group)
                .. "': cancelled=" .. tostring(cancelled)
                .. " active=" .. tostring(active)
                .. " reason=" .. tostring(reason or "session ended") .. "\n")
        end
        return cancelled
    end

    function ctx.actions.api.cancel_all(reason)
        local groups = {}
        for group in pairs(ctx.actions.api.groups) do
            table.insert(groups, group)
        end
        local cancelled = 0
        for _, group in ipairs(groups) do
            cancelled = cancelled + ctx.actions.api.cancel_group(group, reason)
        end
        return cancelled
    end

    function ctx.actions.api.schedule_after(group, delay_ms, callback, ...)
        local runtime = ctx.runtime
        if not runtime.alive then return nil end
        local captured_count = select("#", ...)
        local captured_uobjects = { ... }
        local handle = MakeActionHandle()
        local actions = nil

        if group ~= nil then
            actions = ctx.actions.api.groups[group] or {}
            ctx.actions.api.groups[group] = actions
            actions[handle] = true
        end

        local function invoke()
            runtime:finish_action(handle)
            if not runtime.alive then return end
            if actions ~= nil then
                actions[handle] = nil
                if next(actions) == nil and ctx.actions.api.groups[group] == actions then
                    ctx.actions.api.groups[group] = nil
                end
            end

            for index = 1, captured_count do
                local captured = captured_uobjects[index]
                if not ctx.common.uobject_is_valid(captured) then
                    print(ctx.config.PREFIX .. " Skipped delayed action: captured UObject #"
                        .. tostring(index) .. " is no longer valid.\n")
                    return
                end
            end
            callback()
        end

        runtime:track_action(handle)
        ExecuteInGameThreadWithDelay(handle, math.max(0, tonumber(delay_ms) or 0), invoke)
        return handle
    end

    function ctx.actions.run_on_game_thread_after(delay_ms, callback, ...)
        return ctx.actions.api.schedule_after(nil, delay_ms, callback, ...)
    end

    function ctx.actions.api.run_group_after(group, delay_ms, callback, ...)
        return ctx.actions.api.schedule_after(group, delay_ms, callback, ...)
    end
end
