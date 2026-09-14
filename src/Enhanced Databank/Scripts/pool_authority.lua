-- Enhanced Databank: pool authority.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: common, logging, pool_authority.
return function(ctx)
    ctx.pool_authority.mdvm_library_cdo = nil

    ctx.pool_authority.pool_vm_class = nil

    function ctx.pool_authority.resolve_mdvm()
        if ctx.pool_authority.mdvm_library_cdo and ctx.pool_authority.pool_vm_class then return true end
        local library_class, err = ctx.common.resolve_class("/Script/MDViewModel.MDViewModelFunctionLibrary")
        if not library_class then ctx.logging.log("MDViewModel library unavailable: " .. tostring(err)); return false end
        local cdo, cdo_err = ctx.common.try_call(function() return ctx.common.unwrap(library_class:GetCDO()) end)
        if cdo_err ~= nil or cdo == nil then ctx.logging.log("MDViewModel CDO unavailable: " .. tostring(cdo_err)); return false end
        local pool_class, pool_err = ctx.common.resolve_class("/Script/Bruno.BrunoCharacterPoolViewModel")
        if not pool_class then ctx.logging.log("BrunoCharacterPoolViewModel class unavailable: " .. tostring(pool_err)); return false end
        ctx.pool_authority.mdvm_library_cdo = cdo
        ctx.pool_authority.pool_vm_class = pool_class
        return true
    end

    local function guid_to_string(guid)
        guid = ctx.common.unwrap(guid)
        if guid == nil then return nil end
        local ok, a, b, c, d = pcall(function() return guid.A, guid.B, guid.C, guid.D end)
        if ok and type(a) == "number" and type(b) == "number" and type(c) == "number" and type(d) == "number" then
            local function u32(n) if n < 0 then return n + 4294967296 end return n end
            return string.format("%08X-%08X-%08X-%08X", u32(a), u32(b), u32(c), u32(d))
        end
        local s = ctx.common.text_value(guid)
        if s == "" or s == "<nil>" then return nil end
        return s
    end

    local function copy_guid_value(guid)
        guid = ctx.common.unwrap(guid)
        if guid == nil then return nil end
        local ok, a, b, c, d = pcall(function() return guid.A, guid.B, guid.C, guid.D end)
        if not ok or type(a) ~= "number" or type(b) ~= "number"
            or type(c) ~= "number" or type(d) ~= "number" then
            return nil
        end
        -- Never retain the userdata wrapper supplied by TMap iteration. Build a
        -- standalone FGuid-shaped value so a later delayed UFunction call cannot
        -- dereference iterator-backed memory that is no longer valid.
        return { A = a, B = b, C = c, D = d }
    end

    function ctx.pool_authority.character_guid_string(character_vm)
        local data = select(1, ctx.common.read_property(character_vm, "PoolCharacterData"))
        local guid = data and select(1, ctx.common.read_property(data, "PoolCharacterID")) or nil
        return guid_to_string(guid)
    end

    local character_full_name_function = nil

    function ctx.pool_authority.character_display_name(character_vm)
        character_vm = ctx.common.unwrap(character_vm)
        if character_vm == nil then return "Character" end
        if character_full_name_function == nil then
            character_full_name_function = select(1, ctx.common.try_call(function()
                return StaticFindObject("/Script/Bruno.BrunoCharacterPoolCharacterViewModel:GetFullName")
            end))
        end
        if character_full_name_function ~= nil then
            local value, err = ctx.common.try_call(function() return character_full_name_function(character_vm) end)
            if err == nil and value ~= nil then
                local text = tostring(ctx.common.text_value(value) or "")
                text = text:gsub("^%s+", ""):gsub("%s+$", "")
                if text ~= "" then return text end
            end
        end
        return ctx.pool_authority.character_guid_string(character_vm) or "Character"
    end

    local function trim(value)
        return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
    end

    function ctx.pool_authority.character_display_index(items)
        local index = { by_name = {}, ambiguous = {}, count = 0 }
        ctx.common.array_each(items, function(_, candidate)
            candidate = ctx.common.unwrap(candidate)
            local guid = candidate and ctx.pool_authority.character_guid_string(candidate) or nil
            local name = candidate and trim(ctx.pool_authority.character_display_name(candidate)) or ""
            if guid == nil or name == "" then return end

            index.count = index.count + 1
            local existing = index.by_name[name]
            if existing ~= nil and existing.guid ~= guid then
                index.by_name[name] = nil
                index.ambiguous[name] = true
            elseif existing ~= nil then
                -- Native moves can leave two transient typed wrappers for the
                -- same character. The name is still unambiguous when both
                -- wrappers carry the identical authoritative GUID.
            elseif not index.ambiguous[name] then
                index.by_name[name] = { vm = candidate, guid = guid }
            end
        end)
        return index
    end

    function ctx.pool_authority.character_for_row(row, display_index)
        row = ctx.common.unwrap(row)
        if row == nil then return nil, nil, "row unavailable" end

        -- The compiled Character Databank row exposes its bound full name through
        -- this native rich-text child. UE4SS does not expose a dependable typed
        -- character-ViewModel identity on the row itself, so use the rendered name
        -- only as a unique join back to the typed pool array. Ambiguous names fail
        -- open: callers must not hide or mutate a row they cannot identify exactly.
        local label = select(1, ctx.common.read_property(row, "BitReactorRichTextBlock_73"))
        if label == nil then return nil, nil, "row name label unavailable" end
        local value, text_err = ctx.common.try_call(function() return label:GetText() end)
        if text_err ~= nil or value == nil then
            return nil, nil, "row name unavailable: " .. tostring(text_err)
        end

        local name = trim(ctx.common.text_value(value))
        if name == "" then return nil, nil, "row name empty" end
        if display_index == nil then return nil, nil, "character display index unavailable" end
        if display_index.ambiguous[name] then
            return nil, nil, "row name is not unique: '" .. name .. "'"
        end

        local entry = display_index.by_name[name]
        if entry == nil then
            return nil, nil, "row name has no typed ViewModel match: '" .. name .. "'"
        end
        return entry.vm, entry.guid, nil
    end

    function ctx.pool_authority.find_authoritative_guid_value(wanted_guid)
        wanted_guid = tostring(wanted_guid or "")
        if wanted_guid == "" then return nil, nil, "character GUID unavailable" end
        local manager = ctx.common.find_first("BitReactorCharacterPoolManager")
        if manager == nil then return nil, nil, "BitReactorCharacterPoolManager unavailable" end
        local pools = select(1, ctx.common.read_property(manager, "CharacterPools"))
        if pools == nil then return nil, nil, "CharacterPools unavailable" end
        local found_guid, found_pool = nil, nil
        ctx.common.array_each(pools, function(_, pool_data)
            if found_guid ~= nil or pool_data == nil then return end
            local pool_name_value = ctx.common.text_value(select(1, ctx.common.read_property(pool_data, "CharacterPoolName")))
            local chars = select(1, ctx.common.read_property(pool_data, "Characters"))
            ctx.common.map_each(chars, function(guid, _)
                if found_guid ~= nil then return end
                if guid_to_string(guid) == wanted_guid then
                    found_guid = copy_guid_value(guid)
                    found_pool = pool_name_value
                end
            end)
        end)
        if found_guid == nil then return nil, nil, "character GUID no longer authoritative" end
        return found_guid, found_pool, nil
    end

    function ctx.pool_authority.pool_name(pool_vm)
        return ctx.common.text_value(select(1, ctx.common.read_property(pool_vm, "PoolName")))
    end

    local function pool_type_number(value)
        value = ctx.common.unwrap(value)
        if type(value) == "number" then return value end
        local n = tonumber(value)
        if n ~= nil then return n end
        local s = tostring(value or "")
        if string.find(s, "Default_CustomCharacters", 1, true) then return 4 end
        if string.find(s, "PlayerCreated_CustomCharacters", 1, true) then return 5 end
        if string.find(s, "Default_AstromechCharacters", 1, true) then return 2 end
        if string.find(s, "PlayerCreated_AstromechCharacters", 1, true) then return 3 end
        if string.find(s, "Default_HawksCharacters", 1, true) then return 0 end
        if string.find(s, "PlayerCreated_HawksCharacters", 1, true) then return 1 end
        return nil
    end

    local function pool_vm_type(pool_vm)
        return pool_type_number(select(1, ctx.common.read_property(pool_vm, "PoolType")))
    end

    function ctx.pool_authority.pool_save_name(pool_vm)
        local value, err = ctx.common.try_call(function() return pool_vm:GetSaveFileNameForPool() end)
        if err ~= nil or value == nil then return "" end
        return ctx.common.text_value(value)
    end

    function ctx.pool_authority.authoritative_pool_state()
        local manager = ctx.common.find_first("BitReactorCharacterPoolManager")
        if manager == nil then return nil, "BitReactorCharacterPoolManager unavailable" end
        local pools, pools_err = ctx.common.read_property(manager, "CharacterPools")
        if pools_err ~= nil or pools == nil then return nil, "CharacterPools unavailable: " .. tostring(pools_err) end

        local state = { default_custom = nil, custom_by_name = {}, custom_order = {}, manager = manager }
        ctx.common.array_each(pools, function(_, pool_data)
            if pool_data == nil then return end
            local name = ctx.common.text_value(select(1, ctx.common.read_property(pool_data, "CharacterPoolName")))
            local ptype = pool_type_number(select(1, ctx.common.read_property(pool_data, "CharacterPoolType")))
            if ptype ~= 4 and ptype ~= 5 then return end

            local entry = { name = name, pool_type = ptype, guids = {}, guid_order = {}, count = 0 }
            local chars = select(1, ctx.common.read_property(pool_data, "Characters"))
            ctx.common.map_each(chars, function(guid, _)
                local key = guid_to_string(guid)
                if key ~= nil and not entry.guids[key] then
                    entry.guids[key] = true
                    table.insert(entry.guid_order, key)
                    entry.count = entry.count + 1
                end
            end)

            if ptype == 4 then
                state.default_custom = entry
            else
                state.custom_by_name[name] = entry
                table.insert(state.custom_order, name)
            end
        end)

        if state.default_custom == nil then return nil, "authoritative Default_CustomCharacters pool not found" end
        return state, nil
    end

    function ctx.pool_authority.collect_extra_pool_vms(databank_vm, authority)
        local pools = select(1, ctx.common.read_property(databank_vm, "CustomCharacterPoolViewModels"))
        local by_name = {}
        local seen_objects = {}
        ctx.common.array_each(pools, function(_, pool_vm)
            if pool_vm == nil then return end
            local identity = ctx.common.object_name(pool_vm)
            if seen_objects[identity] then return end
            seen_objects[identity] = true

            local name = ctx.pool_authority.pool_name(pool_vm)
            local ptype = pool_vm_type(pool_vm)
            local authoritative = authority.custom_by_name[name]
            if authoritative == nil or ptype ~= 5 then
                ctx.logging.log("Skipping non-authoritative/stale custom pool VM: " .. identity
                    .. " | name='" .. tostring(name) .. "' | type=" .. tostring(ptype)
                    .. " | save='" .. tostring(ctx.pool_authority.pool_save_name(pool_vm)) .. "'")
                return
            end

            local existing = by_name[name]
            if existing == nil then
                by_name[name] = pool_vm
            else
                -- Prefer the VM with a real save filename if duplicate objects surface.
                local existing_save = ctx.pool_authority.pool_save_name(existing)
                local candidate_save = ctx.pool_authority.pool_save_name(pool_vm)
                if existing_save == "" and candidate_save ~= "" then by_name[name] = pool_vm end
            end
        end)
        return by_name
    end

    function ctx.pool_authority.collect_raw_vm_index(databank_vm, extra_vms)
        local index = {}
        local function add_pool(pool_vm)
            if pool_vm == nil then return end
            local items = select(1, ctx.common.read_property(pool_vm, "PoolCharacterViewModels"))
            ctx.common.array_each(items, function(_, character_vm)
                local guid = ctx.pool_authority.character_guid_string(character_vm)
                if guid ~= nil then
                    index[guid] = index[guid] or {}
                    table.insert(index[guid], character_vm)
                end
            end)
        end

        add_pool(select(1, ctx.common.read_property(databank_vm, "DefaultCustomCharacterPoolViewModel")))
        for _, pool_vm in pairs(extra_vms) do add_pool(pool_vm) end
        return index
    end

    function ctx.pool_authority.rows_for_authority(pool_vm, authority_entry, global_index)
        local rows = {}
        local added = {}
        local local_items = pool_vm and select(1, ctx.common.read_property(pool_vm, "PoolCharacterViewModels")) or nil

        ctx.common.array_each(local_items, function(_, character_vm)
            local guid = ctx.pool_authority.character_guid_string(character_vm)
            if guid ~= nil and authority_entry.guids[guid] and not added[guid] then
                table.insert(rows, character_vm)
                added[guid] = true
            end
        end)

        -- Never borrow a CharacterPoolCharacterViewModel from a different pool.
    -- Manager ownership can update before the Databank VM arrays do.
        -- showed that borrowing the old source-pool VM makes the moved character
        -- appear in the correct folder while leaving native selection state stale;
        -- selecting that row can then crash.
        local missing = {}
        for _, guid in ipairs(authority_entry.guid_order or {}) do
            if not added[guid] then table.insert(missing, guid) end
        end

        return rows, missing
    end

    function ctx.pool_authority.pool_vm_contains_guid(pool_vm, wanted_guid)
        pool_vm = ctx.common.unwrap(pool_vm)
        wanted_guid = tostring(wanted_guid or "")
        if pool_vm == nil or wanted_guid == "" then return false end
        local found = false
        local items = select(1, ctx.common.read_property(pool_vm, "PoolCharacterViewModels"))
        ctx.common.array_each(items, function(_, character_vm)
            if found then return end
            found = ctx.pool_authority.character_guid_string(character_vm) == wanted_guid
        end)
        return found
    end
end
