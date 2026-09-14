-- Enhanced Databank: common.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: common.
return function(ctx)
    function ctx.common.try_call(fn)
        local ok, result = pcall(fn)
        if ok then return result, nil end
        return nil, tostring(result)
    end

    if type(ExecuteInGameThreadWithDelay) ~= "function"
        or type(RetriggerableExecuteInGameThreadWithDelay) ~= "function"
        or type(MakeActionHandle) ~= "function"
        or type(CancelDelayedAction) ~= "function"
        or type(IsValidDelayedActionHandle) ~= "function"
        or type(IsDelayedActionActive) ~= "function" then
        error("Enhanced Databank requires the UE4SS delayed game-thread action system")
    end

    function ctx.common.unwrap(value)
        if value == nil then return nil end
        local unwrapped, err = ctx.common.try_call(function() return value:get() end)
        if err == nil and unwrapped ~= nil then return unwrapped end
        return value
    end

    function ctx.common.uobject_is_valid(value)
        local object = ctx.common.unwrap(value)
        if object == nil then return false end
        local valid, err = ctx.common.try_call(function() return object:IsValid() end)
        return err == nil and valid == true
    end

    function ctx.common.object_name(object)
        object = ctx.common.unwrap(object)
        if object == nil then return "<nil>" end
        local value, err = ctx.common.try_call(function() return object:GetFullName() end)
        if err == nil and value ~= nil then return tostring(value) end
        return tostring(object)
    end

    function ctx.common.class_name(object)
        object = ctx.common.unwrap(object)
        if object == nil then return "<nil>" end
        local class_object, class_err = ctx.common.try_call(function() return object:GetClass() end)
        if class_err ~= nil or class_object == nil then return "<unknown-class>" end
        return ctx.common.object_name(class_object)
    end

    function ctx.common.same_object(a, b)
        a = ctx.common.unwrap(a)
        b = ctx.common.unwrap(b)
        if a == nil or b == nil then return false end
        if a == b then return true end
        return ctx.common.object_name(a) == ctx.common.object_name(b)
    end

    function ctx.common.read_property(object, name)
        object = ctx.common.unwrap(object)
        if object == nil then return nil, "owner nil" end
        return ctx.common.try_call(function() return ctx.common.unwrap(object[name]) end)
    end

    function ctx.common.find_first(class_name_value)
        local value, err = ctx.common.try_call(function() return FindFirstOf(class_name_value) end)
        if err ~= nil then return nil end
        return ctx.common.unwrap(value)
    end

    function ctx.common.text_value(value)
        value = ctx.common.unwrap(value)
        if value == nil then return "" end
        local t = type(value)
        if t == "string" or t == "number" or t == "boolean" then return tostring(value) end
        local result, err = ctx.common.try_call(function() return value:ToString() end)
        if err == nil and result ~= nil then return tostring(result) end
        return tostring(value)
    end

    local function array_count(array)
        if array == nil then return 0 end
        local count, err = ctx.common.try_call(function() return array:GetArrayNum() end)
        if err == nil and type(count) == "number" then return count end
        local ok, length = pcall(function() return #array end)
        if ok and type(length) == "number" then return length end
        return 0
    end

    function ctx.common.array_each(array, callback)
        if array == nil then return end
        -- UE4SS 3.0.1 can hang in reflected TArray:ForEach() when the array is empty.
        if array_count(array) <= 0 then return end
        local used_foreach = false
        pcall(function()
            array:ForEach(function(index, element)
                used_foreach = true
                callback(index, ctx.common.unwrap(element))
            end)
        end)
        if used_foreach then return end
        pcall(function()
            for index, element in ipairs(array) do callback(index, ctx.common.unwrap(element)) end
        end)
    end

    local function map_count(map)
        if map == nil then return 0 end
        local ok, count = pcall(function() return #map end)
        if ok and type(count) == "number" then return count end
        return 0
    end

    function ctx.common.map_each(map, callback)
        if map == nil or map_count(map) <= 0 then return end
        pcall(function()
            map:ForEach(function(key, value)
                callback(ctx.common.unwrap(key), ctx.common.unwrap(value))
            end)
        end)
    end

    function ctx.common.panel_child_count(panel)
        panel = ctx.common.unwrap(panel)
        if panel == nil then return nil end
        local count, err = ctx.common.try_call(function() return panel:GetChildrenCount() end)
        if err ~= nil then return nil end
        return tonumber(count)
    end

    function ctx.common.panel_child_at(panel, index)
        panel = ctx.common.unwrap(panel)
        if panel == nil then return nil end
        local child, err = ctx.common.try_call(function() return ctx.common.unwrap(panel:GetChildAt(index)) end)
        if err ~= nil then return nil end
        return child
    end

    function ctx.common.resolve_class(path)
        local class_object, err = ctx.common.try_call(function() return StaticFindObject(path) end)
        if err ~= nil or class_object == nil then return nil, tostring(err or "not found") end
        return ctx.common.unwrap(class_object), nil
    end
end
