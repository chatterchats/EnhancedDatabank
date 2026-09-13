-- Enhanced Databank v1.0.0
local MOD = "EnhancedDatabank"
local VERSION = "1.0.0"
local PREFIX = "[" .. MOD .. "]"

local function try_call(fn)
    local ok, result = pcall(fn)
    if ok then return result, nil end
    return nil, tostring(result)
end

if type(ExecuteInGameThreadWithDelay) ~= "function"
    or type(RetriggerableExecuteInGameThreadWithDelay) ~= "function"
    or type(MakeActionHandle) ~= "function" then
    error("Enhanced Databank requires the UE4SS delayed game-thread action system")
end

local function run_on_game_thread_after(delay_ms, callback)
    return ExecuteInGameThreadWithDelay(math.max(0, tonumber(delay_ms) or 0), callback)
end

local function unwrap(value)
    if value == nil then return nil end
    local unwrapped, err = try_call(function() return value:get() end)
    if err == nil and unwrapped ~= nil then return unwrapped end
    return value
end

local function uobject_is_valid(value)
    local object = unwrap(value)
    if object == nil then return false end
    local valid, err = try_call(function() return object:IsValid() end)
    -- IsValid is provided by current UE4SS RemoteObject builds. Preserve
    -- compatibility with older builds that do not expose it and retain the
    -- existing non-nil checks in that case.
    if err ~= nil then return true end
    return valid == true
end

local function object_name(object)
    object = unwrap(object)
    if object == nil then return "<nil>" end
    local value, err = try_call(function() return object:GetFullName() end)
    if err == nil and value ~= nil then return tostring(value) end
    return tostring(object)
end

local function class_name(object)
    object = unwrap(object)
    if object == nil then return "<nil>" end
    local class_object, class_err = try_call(function() return object:GetClass() end)
    if class_err ~= nil or class_object == nil then return "<unknown-class>" end
    return object_name(class_object)
end

local function same_object(a, b)
    a = unwrap(a)
    b = unwrap(b)
    if a == nil or b == nil then return false end
    if a == b then return true end
    return object_name(a) == object_name(b)
end

local function read_property(object, name)
    object = unwrap(object)
    if object == nil then return nil, "owner nil" end
    return try_call(function() return unwrap(object[name]) end)
end

local function find_first(class_name_value)
    local value, err = try_call(function() return FindFirstOf(class_name_value) end)
    if err ~= nil then return nil end
    return unwrap(value)
end

local function text_value(value)
    value = unwrap(value)
    if value == nil then return "" end
    local t = type(value)
    if t == "string" or t == "number" or t == "boolean" then return tostring(value) end
    local result, err = try_call(function() return value:ToString() end)
    if err == nil and result ~= nil then return tostring(result) end
    return tostring(value)
end

local source_resolution_note = nil
local function resolve_source_log_path()
    if not debug or type(debug.getinfo) ~= "function" then
        source_resolution_note = "debug.getinfo unavailable"
        return nil
    end
    local ok, info = pcall(debug.getinfo, 1, "S")
    if not ok or not info or type(info.source) ~= "string" then
        source_resolution_note = "debug.getinfo failed or returned no source"
        return nil
    end
    local source = info.source
    source_resolution_note = "debug source=" .. tostring(source)
    if source:sub(1, 1) == "@" then source = source:sub(2) end
    local script_dir = source:match("^(.*)[/\\][^/\\]+$")
    if not script_dir then return nil end
    local mod_dir = script_dir:match("^(.*)[/\\][Ss]cripts$") or script_dir
    local separator = source:find("\\", 1, true) and "\\" or "/"
    return mod_dir .. separator .. "enhanced_databank.log"
end

local function try_open_log(path)
    if type(path) ~= "string" or path == "" then return nil, "empty path" end
    local ok, handle, err = pcall(io.open, path, "a")
    if not ok then return nil, tostring(handle) end
    if not handle then return nil, tostring(err or "io.open returned nil") end
    pcall(function() handle:setvbuf("no") end)
    return handle, nil
end

local LOG_CANDIDATES = {
    "ue4ss\\Mods\\Enhanced_Databank\\enhanced_databank.log",
    "ue4ss/Mods/Enhanced_Databank/enhanced_databank.log",
    "ue4ss\\Mods\\EnhancedDatabank\\enhanced_databank.log",
    "ue4ss/Mods/EnhancedDatabank/enhanced_databank.log",
    "ue4ss\\Mods\\Enhanced Databank\\enhanced_databank.log",
    "ue4ss/Mods/Enhanced Databank/enhanced_databank.log",
    "Mods\\EnhancedDatabank\\enhanced_databank.log",
    "Mods/EnhancedDatabank/enhanced_databank.log",
}
local source_log = resolve_source_log_path()
if source_log then table.insert(LOG_CANDIDATES, source_log) end
table.insert(LOG_CANDIDATES, "enhanced_databank.log")

local log_file = nil
local LOG_PATH = nil
for _, candidate in ipairs(LOG_CANDIDATES) do
    local handle = select(1, try_open_log(candidate))
    if handle ~= nil then
        log_file = handle
        LOG_PATH = candidate
        break
    end
end

local function log(message)
    local line = PREFIX .. " " .. tostring(message)
    print(line .. "\n")
    if log_file then
        pcall(function()
            log_file:write(line .. "\n")
            log_file:flush()
        end)
    end
end

local function section(title)
    log("")
    log("=== " .. tostring(title) .. " ===")
end

local function array_count(array)
    if array == nil then return 0 end
    local count, err = try_call(function() return array:GetArrayNum() end)
    if err == nil and type(count) == "number" then return count end
    local ok, length = pcall(function() return #array end)
    if ok and type(length) == "number" then return length end
    return 0
end

local function array_each(array, callback)
    if array == nil then return end
    -- UE4SS 3.0.1 can hang in reflected TArray:ForEach() when the array is empty.
    if array_count(array) <= 0 then return end
    local used_foreach = false
    pcall(function()
        array:ForEach(function(index, element)
            used_foreach = true
            callback(index, unwrap(element))
        end)
    end)
    if used_foreach then return end
    pcall(function()
        for index, element in ipairs(array) do callback(index, unwrap(element)) end
    end)
end

local function map_count(map)
    if map == nil then return 0 end
    local ok, count = pcall(function() return #map end)
    if ok and type(count) == "number" then return count end
    return 0
end

local function map_each(map, callback)
    if map == nil or map_count(map) <= 0 then return end
    pcall(function()
        map:ForEach(function(key, value)
            callback(unwrap(key), unwrap(value))
        end)
    end)
end

local function panel_child_count(panel)
    panel = unwrap(panel)
    if panel == nil then return nil end
    local count, err = try_call(function() return panel:GetChildrenCount() end)
    if err ~= nil then return nil end
    return tonumber(count)
end

local function panel_child_at(panel, index)
    panel = unwrap(panel)
    if panel == nil then return nil end
    local child, err = try_call(function() return unwrap(panel:GetChildAt(index)) end)
    if err ~= nil then return nil end
    return child
end

local function resolve_class(path)
    local class_object, err = try_call(function() return StaticFindObject(path) end)
    if err ~= nil or class_object == nil then return nil, tostring(err or "not found") end
    return unwrap(class_object), nil
end

local mdvm_library_cdo = nil
local pool_vm_class = nil
local function resolve_mdvm()
    if mdvm_library_cdo and pool_vm_class then return true end
    local library_class, err = resolve_class("/Script/MDViewModel.MDViewModelFunctionLibrary")
    if not library_class then log("MDViewModel library unavailable: " .. tostring(err)); return false end
    local cdo, cdo_err = try_call(function() return unwrap(library_class:GetCDO()) end)
    if cdo_err ~= nil or cdo == nil then log("MDViewModel CDO unavailable: " .. tostring(cdo_err)); return false end
    local pool_class, pool_err = resolve_class("/Script/Bruno.BrunoCharacterPoolViewModel")
    if not pool_class then log("BrunoCharacterPoolViewModel class unavailable: " .. tostring(pool_err)); return false end
    mdvm_library_cdo = cdo
    pool_vm_class = pool_class
    return true
end

local function guid_to_string(guid)
    guid = unwrap(guid)
    if guid == nil then return nil end
    local ok, a, b, c, d = pcall(function() return guid.A, guid.B, guid.C, guid.D end)
    if ok and type(a) == "number" and type(b) == "number" and type(c) == "number" and type(d) == "number" then
        local function u32(n) if n < 0 then return n + 4294967296 end return n end
        return string.format("%08X-%08X-%08X-%08X", u32(a), u32(b), u32(c), u32(d))
    end
    local s = text_value(guid)
    if s == "" or s == "<nil>" then return nil end
    return s
end

local function copy_guid_value(guid)
    guid = unwrap(guid)
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

local function character_guid_string(character_vm)
    local data = select(1, read_property(character_vm, "PoolCharacterData"))
    local guid = data and select(1, read_property(data, "PoolCharacterID")) or nil
    return guid_to_string(guid)
end

local character_full_name_function = nil
local function character_display_name(character_vm)
    character_vm = unwrap(character_vm)
    if character_vm == nil then return "Character" end
    if character_full_name_function == nil then
        character_full_name_function = select(1, try_call(function()
            return StaticFindObject("/Script/Bruno.BrunoCharacterPoolCharacterViewModel:GetFullName")
        end))
    end
    if character_full_name_function ~= nil then
        local value, err = try_call(function() return character_full_name_function(character_vm) end)
        if err == nil and value ~= nil then
            local text = tostring(text_value(value) or "")
            text = text:gsub("^%s+", ""):gsub("%s+$", "")
            if text ~= "" then return text end
        end
    end
    return character_guid_string(character_vm) or "Character"
end

local function find_authoritative_guid_value(wanted_guid)
    wanted_guid = tostring(wanted_guid or "")
    if wanted_guid == "" then return nil, nil, "character GUID unavailable" end
    local manager = find_first("BitReactorCharacterPoolManager")
    if manager == nil then return nil, nil, "BitReactorCharacterPoolManager unavailable" end
    local pools = select(1, read_property(manager, "CharacterPools"))
    if pools == nil then return nil, nil, "CharacterPools unavailable" end
    local found_guid, found_pool = nil, nil
    array_each(pools, function(_, pool_data)
        if found_guid ~= nil or pool_data == nil then return end
        local pool_name_value = text_value(select(1, read_property(pool_data, "CharacterPoolName")))
        local chars = select(1, read_property(pool_data, "Characters"))
        map_each(chars, function(guid, _)
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

local function pool_name(pool_vm)
    return text_value(select(1, read_property(pool_vm, "PoolName")))
end

local function pool_type_number(value)
    value = unwrap(value)
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
    return pool_type_number(select(1, read_property(pool_vm, "PoolType")))
end

local function pool_save_name(pool_vm)
    local value, err = try_call(function() return pool_vm:GetSaveFileNameForPool() end)
    if err ~= nil or value == nil then return "" end
    return text_value(value)
end

local function authoritative_pool_state()
    local manager = find_first("BitReactorCharacterPoolManager")
    if manager == nil then return nil, "BitReactorCharacterPoolManager unavailable" end
    local pools, pools_err = read_property(manager, "CharacterPools")
    if pools_err ~= nil or pools == nil then return nil, "CharacterPools unavailable: " .. tostring(pools_err) end

    local state = { default_custom = nil, custom_by_name = {}, custom_order = {}, manager = manager }
    array_each(pools, function(_, pool_data)
        if pool_data == nil then return end
        local name = text_value(select(1, read_property(pool_data, "CharacterPoolName")))
        local ptype = pool_type_number(select(1, read_property(pool_data, "CharacterPoolType")))
        if ptype ~= 4 and ptype ~= 5 then return end

        local entry = { name = name, pool_type = ptype, guids = {}, guid_order = {}, count = 0 }
        local chars = select(1, read_property(pool_data, "Characters"))
        map_each(chars, function(guid, _)
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

local function collect_extra_pool_vms(databank_vm, authority)
    local pools = select(1, read_property(databank_vm, "CustomCharacterPoolViewModels"))
    local by_name = {}
    local seen_objects = {}
    array_each(pools, function(_, pool_vm)
        if pool_vm == nil then return end
        local identity = object_name(pool_vm)
        if seen_objects[identity] then return end
        seen_objects[identity] = true

        local name = pool_name(pool_vm)
        local ptype = pool_vm_type(pool_vm)
        local authoritative = authority.custom_by_name[name]
        if authoritative == nil or ptype ~= 5 then
            log("Skipping non-authoritative/stale custom pool VM: " .. identity
                .. " | name='" .. tostring(name) .. "' | type=" .. tostring(ptype)
                .. " | save='" .. tostring(pool_save_name(pool_vm)) .. "'")
            return
        end

        local existing = by_name[name]
        if existing == nil then
            by_name[name] = pool_vm
        else
            -- Prefer the VM with a real save filename if duplicate objects surface.
            local existing_save = pool_save_name(existing)
            local candidate_save = pool_save_name(pool_vm)
            if existing_save == "" and candidate_save ~= "" then by_name[name] = pool_vm end
        end
    end)
    return by_name
end

local function collect_raw_vm_index(databank_vm, extra_vms)
    local index = {}
    local function add_pool(pool_vm)
        if pool_vm == nil then return end
        local items = select(1, read_property(pool_vm, "PoolCharacterViewModels"))
        array_each(items, function(_, character_vm)
            local guid = character_guid_string(character_vm)
            if guid ~= nil then
                index[guid] = index[guid] or {}
                table.insert(index[guid], character_vm)
            end
        end)
    end

    add_pool(select(1, read_property(databank_vm, "DefaultCustomCharacterPoolViewModel")))
    for _, pool_vm in pairs(extra_vms) do add_pool(pool_vm) end
    return index
end

local function rows_for_authority(pool_vm, authority_entry, global_index)
    local rows = {}
    local added = {}
    local local_items = pool_vm and select(1, read_property(pool_vm, "PoolCharacterViewModels")) or nil

    array_each(local_items, function(_, character_vm)
        local guid = character_guid_string(character_vm)
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

local function pool_vm_contains_guid(pool_vm, wanted_guid)
    pool_vm = unwrap(pool_vm)
    wanted_guid = tostring(wanted_guid or "")
    if pool_vm == nil or wanted_guid == "" then return false end
    local found = false
    local items = select(1, read_property(pool_vm, "PoolCharacterViewModels"))
    array_each(items, function(_, character_vm)
        if found then return end
        found = character_guid_string(character_vm) == wanted_guid
    end)
    return found
end

-- Forward declaration: invoke_pool_rows() participates in row-generation lifecycle
-- bookkeeping before the Create Folder section initializes the shared state.
-- Without this declaration Lua resolves folder_ui_state as a global inside the
-- earlier function, which is nil at runtime and aborts the entire Databank render.
local folder_ui_state
local show_move_character_dialog
local decorate_current_character_rows

local function invoke_pool_rows(widget, rows, label)
    if widget == nil then return false, "widget unavailable" end
    local arg = {}
    for _, vm in ipairs(rows or {}) do table.insert(arg, vm) end

    -- Native Blueprint row regeneration is one of the few calls in this mod that
    -- can cross deeply through UE4SS while destroying/recreating child widgets.
    -- Log before entering it so a native access violation can be pinned to the
    -- exact pool even when Lua never gets a chance to report an exception.
    log(tostring(label) .. " row apply begin: requested=" .. tostring(#rows))
    local _, err = try_call(function()
        return widget:BndEvt__WBP_CharacterBank_CreatedCharactersPoolItem_BrunoCharacterPoolViewModel_MDVMNode_ViewModelFieldNotify_1_PoolCharacterViewModels(arg)
    end)
    if err ~= nil then return false, tostring(label) .. " row handler failed: " .. tostring(err) end
    local stack = select(1, read_property(widget, "BitReactorStackBox_25"))
    log(tostring(label) .. " rows applied: requested=" .. tostring(#rows)
        .. " | renderedChildren=" .. tostring(panel_child_count(stack)))
    return true, nil
end

local function row_pool_vm(row)
    if row == nil or not resolve_mdvm() then return nil, "row/MDViewModel unavailable" end
    local value, err = try_call(function()
        return unwrap(mdvm_library_cdo:GetViewModel(row, pool_vm_class, FName("")))
    end)
    return value, err
end

local function log_row_tooltip_state(row, expected_pool_vm, label)
    row = unwrap(row)
    if row == nil then
        log(tostring(label) .. " tooltip diagnostic: row unavailable")
        return
    end
    local tooltip = select(1, read_property(row, "BitReactorTooltipBox_54"))
    local resolved_pool, resolved_err = row_pool_vm(row)
    log(tostring(label) .. " tooltip diagnostic: tooltip=" .. object_name(tooltip)
        .. " | resolvedPool=" .. object_name(resolved_pool)
        .. " | matchesExpected=" .. tostring(same_object(resolved_pool, expected_pool_vm))
        .. " | GetViewModelErr=" .. tostring(resolved_err)
        .. " | expectedSave='" .. tostring(pool_save_name(expected_pool_vm)) .. "'")
end

local function apply_native_folder_tooltip(row, pool_vm, label)
    row = unwrap(row)
    pool_vm = unwrap(pool_vm)
    if row == nil or pool_vm == nil then return false, "row/pool unavailable" end

    local tooltip = select(1, read_property(row, "BitReactorTooltipBox_54"))
    if tooltip == nil then return false, "BitReactorTooltipBox_54 unavailable" end

    local save_name = pool_save_name(pool_vm)
    if save_name == nil or save_name == "" then return false, "native pool save filename unavailable" end

    -- Preserve the shipping tooltip widget and presentation. We only supply the
    -- payload entry that the stock Blueprint normally derives from its hidden
    -- BrunoCharacterPoolViewModel assignment. The native TooltipPaylodEntry
    -- fields are HeaderText / BodyText / Icon; omitting Icon leaves its default.
    local payload = {
        HeaderText = FText("FOLDER NAME"),
        BodyText = FText(save_name),
    }

    local _, payload_err = try_call(function()
        return tooltip:SetTooltipPayloadEntry(payload)
    end)
    if payload_err ~= nil then
        return false, "SetTooltipPayloadEntry failed: " .. tostring(payload_err)
    end

    local _, display_err = try_call(function()
        return tooltip:SetDisplayTooltop(true)
    end)
    if display_err ~= nil then
        return false, "SetDisplayTooltop failed: " .. tostring(display_err)
    end

    log(tostring(label) .. " native tooltip payload applied: body='" .. tostring(save_name) .. "'")
    return true, nil
end

local function propagate_pool_context_to_rows(pool_widget, pool_vm, label)
    if pool_widget == nil or pool_vm == nil then return false, "pool widget/viewmodel unavailable" end
    local stack = select(1, read_property(pool_widget, "BitReactorStackBox_25"))
    if stack == nil then return false, "BitReactorStackBox_25 unavailable" end

    local count = panel_child_count(stack) or 0
    local bridge_applied = 0
    local changed_applied = 0
    local failed = 0

    for i = 0, count - 1 do
        local row = panel_child_at(stack, i)
        if row ~= nil and string.find(class_name(row), "WBP_CharacterBank_CreatedCharacterItem_C", 1, true) then
            -- First replay the shipping pool widget's row-created bridge. This is
            -- the native parent -> child pool-ViewModel propagation path.
            local _, bridge_err = try_call(function()
                return pool_widget:BndEvt__WBP_CharacterBank_CreatedCharactersPoolItem_BitReactorStackBox_25_K2Node_ComponentBoundEvent_0_OnBitReactorStackBoxWidgetCreated__DelegateSignature(row)
            end)
            if bridge_err == nil then
                bridge_applied = bridge_applied + 1
            else
                failed = failed + 1
                log(tostring(label) .. " row pool-context bridge failed at index " .. tostring(i) .. ": " .. tostring(bridge_err))
            end

            log_row_tooltip_state(row, pool_vm, tostring(label) .. " row[" .. tostring(i) .. "] after pool bridge")

-- Replaying the row-created bridge alone does not create
            -- the stock FOLDER NAME tooltip. The row Blueprint has a separate
            -- generated BrunoCharacterPoolViewModel ViewModelChanged handler;
            -- its compiled graph calls GetSaveFileNameForPool() and constructs
            -- the TooltipPaylodEntry. Replay that exact shipped handler now.
            local _, changed_err = try_call(function()
                return row:BndEvt__WBP_CharacterBank_CreatedCharacterItem_BrunoCharacterPoolViewModel_MDVMNode_ViewModelChanged_0_Changed(nil, pool_vm)
            end)
            if changed_err == nil then
                changed_applied = changed_applied + 1
            else
                failed = failed + 1
                log(tostring(label) .. " row pool ViewModelChanged handler failed at index " .. tostring(i) .. ": " .. tostring(changed_err))
            end

            log_row_tooltip_state(row, pool_vm, tostring(label) .. " row[" .. tostring(i) .. "] after row ViewModelChanged")

            -- The hidden MDViewModel assignment still does not resolve to the
            -- expected pool on dynamically-created rows. Rather than replacing
            -- the tooltip, feed the existing native BitReactorTooltipBox the
            -- same header/body values the stock Blueprint computes.
            local tooltip_ok, tooltip_err = apply_native_folder_tooltip(
                row, pool_vm, tostring(label) .. " row[" .. tostring(i) .. "]"
            )
            if not tooltip_ok then
                failed = failed + 1
                log(tostring(label) .. " native tooltip payload failed at index " .. tostring(i) .. ": " .. tostring(tooltip_err))
            end
        end
    end

    log(tostring(label) .. " row pool-context restore: rows=" .. tostring(count)
        .. " | bridgeApplied=" .. tostring(bridge_applied)
        .. " | changedApplied=" .. tostring(changed_applied)
        .. " | failed=" .. tostring(failed))
    return failed == 0, failed == 0 and nil or (tostring(failed) .. " row context/tooltip restore failure(s)")
end

local function create_pool_widget(page)
    local stock = select(1, read_property(page, "CharacterPool"))
    if stock == nil then return nil, "shipping CharacterPool unavailable" end
    local widget_class, class_err = try_call(function() return unwrap(stock:GetClass()) end)
    if class_err ~= nil or widget_class == nil then return nil, "pool widget class unavailable: " .. tostring(class_err) end
    local library_class, library_err = resolve_class("/Script/UMG.WidgetBlueprintLibrary")
    if library_class == nil then return nil, "WidgetBlueprintLibrary unavailable: " .. tostring(library_err) end
    local library, cdo_err = try_call(function() return unwrap(library_class:GetCDO()) end)
    if cdo_err ~= nil or library == nil then return nil, "WidgetBlueprintLibrary CDO unavailable: " .. tostring(cdo_err) end
    local owning_player = nil
    pcall(function() owning_player = unwrap(page:GetOwningPlayer()) end)
    local widget, create_err = try_call(function() return unwrap(library:Create(page, widget_class, owning_player)) end)
    if create_err ~= nil or widget == nil then return nil, "WidgetBlueprintLibrary.Create failed: " .. tostring(create_err) end
    return widget, nil
end

local function bind_pool_widget(widget, pool_vm)
    if not resolve_mdvm() then return false, "MDViewModel unavailable" end
    local _, err = try_call(function()
        return unwrap(mdvm_library_cdo:SetViewModel(widget, pool_vm, pool_vm_class, FName("")))
    end)
    if err ~= nil then return false, "SetViewModel failed: " .. tostring(err) end
    return true, nil
end

local function apply_pool_title(widget, pool_vm)
    local folder = select(1, read_property(widget, "WBP_CharacterBank_PoolName"))
    if folder == nil then return false, "nested folder unavailable" end
    local wanted = pool_name(pool_vm)
    local label = select(1, read_property(folder, "BitReactorRichTextBlock_73"))
    local localized_ok, localized_err = pcall(function() folder.LocalizedName = FText(wanted) end)
    local text_ok, text_err = false, nil
    if label ~= nil then text_ok, text_err = pcall(function() label:SetText(FText(wanted)) end) end
    if not localized_ok and not text_ok then
        return false, "title write failed: " .. tostring(localized_err or text_err)
    end
    return true, nil
end

local function remove_dynamic_pool_widgets(page)
    local scroll = select(1, read_property(page, "BitReactorScrollBox_0"))
    local stock = select(1, read_property(page, "CharacterPool"))
    if scroll == nil or stock == nil then return 0 end
    local remove = {}
    local count = panel_child_count(scroll) or 0
    for i = 0, count - 1 do
        local child = panel_child_at(scroll, i)
        if child ~= nil and not same_object(child, stock)
            and string.find(class_name(child), "WBP_CharacterBank_CreatedCharactersPoolItem_C", 1, true) then
            table.insert(remove, child)
        end
    end
    for _, child in ipairs(remove) do pcall(function() child:RemoveFromParent() end) end
    return #remove
end


-- ---------------------------------------------------------------------------
-- Create Folder control
--
-- Restores the native pool creation affordance without inventing a parallel
-- folder model. The control is an icon-only clone of the shipping Create New
-- button, with a Tabler-style folder-plus glyph loaded from this mod's Assets
-- directory. The dialog calls the game's own IsNewPoolNameAvailable/CreatePool
-- functions; persistence and empty-pool lifecycle remain fully native.
-- ---------------------------------------------------------------------------

local CREATE_FOLDER_BUTTON_MARKER = "EnhancedDatabank_CreateFolderButton"
local CREATE_FOLDER_ROW_MARKER = "EnhancedDatabank_CreateFolderRow"
local CREATE_FOLDER_ICON_WIDTH = 64.0
local CREATE_FOLDER_GLYPH_SIZE = 28.0
local CREATE_FOLDER_GAP = 8.0
local RENAME_FOLDER_BUTTON_WIDTH = 48.0
local RENAME_FOLDER_BUTTON_HEIGHT = 44.0
local RENAME_FOLDER_GLYPH_SCALE = 1.5
local RENAME_FOLDER_GLYPH_SIZE = 22.0 * RENAME_FOLDER_GLYPH_SCALE
local RENAME_FOLDER_BUTTON_MARKER = "EnhancedDatabank_RenameFolderButton_"
local DELETE_FOLDER_BUTTON_MARKER = "EnhancedDatabank_DeleteFolderButton_"
local MOVE_CHARACTER_BUTTON_MARKER = "EnhancedDatabank_MoveCharacterButton_"
local MOVE_CHARACTER_BUTTON_WIDTH = 48.0
local MOVE_CHARACTER_BUTTON_HEIGHT = 44.0
local MOVE_CHARACTER_RIGHT_PADDING = 54.0
local ENTRY_TEXT_CLASS_PATH =
    "/Game/Game/UI/Strategy/Customization/Widgets/CustomCharacter/"
    .. "WBP_CustomCharacter_EntryText.WBP_CustomCharacter_EntryText_C"
local GENERIC_POPUP_CLASS_PATH =
    "/Game/Game/UI/Common/WBP_GenericPopupMessage_Small."
    .. "WBP_GenericPopupMessage_Small_C"
local GENERIC_POPUP_FALLBACK_CLASS_PATH =
    "/Game/Game/UI/Common/WBP_GenericPopupMessage."
    .. "WBP_GenericPopupMessage_C"
local DIALOG_RESULT_PRIMARY = "br.Customization.Slot.Character.Info"
local DIALOG_RESULT_SECONDARY = "br.Customization.Slot.Character.Class"

folder_ui_state = {
    pageIdentity = nil,
    page = nil,
    row = nil,
    button = nil,
    buttons = {},
    iconCanvas = nil,
    iconOverlay = nil,
    renameButtons = {},
    deleteButtons = {},
    moveButtons = {},
    moveRowActions = {},
    moveDestinationButtons = {},
    renderedPools = {},
    moveClickScheduled = false,
    pendingMove = nil,
}

local folder_popup_state = {
    widget = nil,
    mode = nil,
    textBox = nil,
    resultActions = {},
    suppressResult = false,
    initialText = "",
    targetPoolVM = nil,
    targetPoolName = nil,
    targetCharacterGuid = nil,
    targetCharacterName = nil,
    sourcePoolName = nil,
}

local folder_dialog_result_hook_registered = false
local folder_button_click_hook_registered = false
local action_hover_hooks_registered = false
local FOLDER_ICON_COLOR_NORMAL = { R = 0.78, G = 0.74, B = 0.76, A = 1.0 }
local FOLDER_ICON_COLOR_HOVER = { R = 0.10, G = 0.075, B = 0.085, A = 1.0 }
local FOLDER_ICON_COLOR = FOLDER_ICON_COLOR_NORMAL
local default_move_decor_generation = 0

local function trim_string(value)
    local s = tostring(value or "")
    s = s:gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

local function load_class(path)
    local class_object, err = resolve_class(path)
    if class_object ~= nil then return class_object, nil end
    local package_path = tostring(path):match("^([^%.]+)")
    if package_path ~= nil then
        pcall(function() LoadAsset(package_path) end)
        class_object, err = resolve_class(path)
    end
    if class_object == nil then
        return nil, tostring(err or ("class unavailable: " .. tostring(path)))
    end
    return class_object, nil
end

local function create_user_widget(world_context, widget_class)
    if world_context == nil or widget_class == nil then
        return nil, "missing world context/class"
    end
    local library_class, class_err = load_class("/Script/UMG.WidgetBlueprintLibrary")
    if library_class == nil then return nil, class_err end
    local library, cdo_err = try_call(function() return unwrap(library_class:GetCDO()) end)
    if cdo_err ~= nil or library == nil then
        return nil, "WidgetBlueprintLibrary CDO unavailable"
    end
    local owning_player = nil
    pcall(function() owning_player = unwrap(world_context:GetOwningPlayer()) end)
    local widget, create_err = try_call(function()
        return unwrap(library:Create(world_context, widget_class, owning_player))
    end)
    if create_err ~= nil or widget == nil then
        return nil, tostring(create_err or "Create returned nil")
    end
    return widget, nil
end

local function construct_widget(owner, class_path, name)
    local tree = select(1, read_property(owner, "WidgetTree"))
    if tree == nil then return nil, "WidgetTree unavailable" end
    local widget_class, class_err = load_class(class_path)
    if widget_class == nil then return nil, class_err end
    local widget, err = try_call(function()
        return unwrap(StaticConstructObject(widget_class, tree, FName(name), 0, 0, false, false, nil))
    end)
    if err ~= nil or widget == nil then
        return nil, tostring(err or "StaticConstructObject returned nil")
    end
    return widget, nil
end

local function collect_widget_tree(user_widget)
    local widgets = {}
    user_widget = unwrap(user_widget)
    if user_widget == nil then return widgets end

    local tree = select(1, read_property(user_widget, "WidgetTree"))
    if tree == nil then return widgets end

    local root = select(1, read_property(tree, "RootWidget"))
    root = unwrap(root)
    if root == nil then return widgets end

    local function visit(widget)
        widget = unwrap(widget)
        if widget == nil then return end
        table.insert(widgets, widget)

        local count = nil
        pcall(function() count = tonumber(widget:GetChildrenCount()) end)
        if count == nil or count <= 0 then return end

        for index = 0, count - 1 do
            local child = nil
            pcall(function() child = unwrap(widget:GetChildAt(index)) end)
            if child ~= nil then visit(child) end
        end
    end

    visit(root)
    return widgets
end

local function find_tree_widget(user_widget, needle)
    needle = tostring(needle or "")
    if needle == "" then return nil end

    for _, widget in ipairs(collect_widget_tree(user_widget)) do
        local identity = object_name(widget)
        local klass = class_name(widget)
        if string.find(identity, needle, 1, true) ~= nil
            or string.find(klass, needle, 1, true) ~= nil then
            return widget
        end
    end
    return nil
end

local function panel_child_index(parent, child)
    local count = panel_child_count(parent) or 0
    for i = 0, count - 1 do
        if same_object(panel_child_at(parent, i), child) then return i end
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
    local transform = select(1, read_property(widget, "RenderTransform"))
    local translation = transform and select(1, read_property(transform, "Translation")) or nil
    if translation == nil then return 0.0, 0.0 end
    return numeric_struct_field(translation, "X"), numeric_struct_field(translation, "Y")
end

local function set_widget_render_translation(widget, x, y)
    local _, err = try_call(function()
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
    local slot = select(1, read_property(widget, "Slot"))
    local padding = slot and select(1, read_property(slot, "Padding")) or nil
    if padding ~= nil then
        if axis == "vertical" then
            extent = extent + numeric_struct_field(padding, "Top") + numeric_struct_field(padding, "Bottom")
        else
            extent = extent + numeric_struct_field(padding, "Left") + numeric_struct_field(padding, "Right")
        end
    end
    return math.max(0.0, extent)
end

local function visually_move_appended_child_to_index(parent, child, target_index, axis)
    pcall(function() parent:ForceLayoutPrepass() end)
    local count = panel_child_count(parent)
    if count == nil or count <= 0 then return false, "parent child count unavailable" end
    local appended_index = panel_child_index(parent, child)
    if appended_index ~= count - 1 then return false, "child is not final appended child" end
    if target_index < 0 or target_index > appended_index then return false, "invalid target index" end
    if target_index == appended_index then return true, nil end

    local shifted, shifted_extent = {}, 0.0
    for i = target_index, appended_index - 1 do
        local sibling = panel_child_at(parent, i)
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

local function capture_box_slot_layout(child)
    local layout = {}
    local slot = select(1, read_property(child, "Slot"))
    if slot == nil then return layout end
    local specs = {
        { "Padding", "GetPadding" }, { "Size", "GetSize" },
        { "HorizontalAlignment", "GetHorizontalAlignment" },
        { "VerticalAlignment", "GetVerticalAlignment" },
    }
    for _, spec in ipairs(specs) do
        local value = nil
        pcall(function() value = slot[spec[2]](slot) end)
        if value == nil then value = select(1, read_property(slot, spec[1])) end
        if value ~= nil then layout[spec[1]] = value end
    end
    return layout
end

local function apply_box_slot_layout(slot, layout)
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

local function widget_local_width(widget)
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

local function make_width_wrapper(owner, child, name, width)
    local wrapper, err = construct_widget(owner, "/Script/UMG.SizeBox", name)
    if wrapper == nil then return nil, nil, err end
    if width ~= nil then pcall(function() wrapper:SetWidthOverride(width) end) end
    local slot = select(1, try_call(function() return unwrap(wrapper:AddChild(child)) end))
    if slot == nil then return nil, nil, "could not add child to SizeBox" end
    pcall(function()
        slot:SetHorizontalAlignment(3)
        slot:SetVerticalAlignment(3)
    end)
    return wrapper, slot, nil
end

local function configure_row_slot(slot, left_padding)
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

local function clone_widget_like(page, template, name)
    local widget_class = select(1, try_call(function() return unwrap(template:GetClass()) end))
    if widget_class == nil then return nil, "template class unavailable" end
    local widget, err = create_user_widget(page, widget_class)
    if widget == nil then return nil, err end
    pcall(function() widget:Rename(FName(name), page) end)
    return widget, nil
end

local function image_dimensions(widget)
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

local function style_create_folder_icon_button(page, button)
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
    for _, widget in ipairs(collect_widget_tree(button)) do
        local cn = class_name(widget)
        if string.find(cn, "RichTextBlock", 1, true) or string.find(cn, "TextBlock", 1, true) then
            pcall(function() widget:SetText(FText("")); text_changed = text_changed + 1 end)
            pcall(function() widget:SetTextEx(FText("")); text_changed = text_changed + 1 end)
        elseif string.find(cn, "Image", 1, true) then
            local w, h = image_dimensions(widget)
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

    log("Create Folder icon button styled: textChanges=" .. tostring(text_changed)
        .. " images=" .. tostring(#images)
        .. " inheritedGlyphImagesHidden=" .. tostring(hidden_glyph_images)
        .. " nativeVectorIcon=" .. tostring(folder_ui_state.iconCanvas ~= nil))
    return true
end

local function add_icon_rect(page, canvas, name, x, y, w, h)
    local rect, rect_err = construct_widget(page, "/Script/UMG.Border", name)
    if rect == nil then return nil, rect_err end
    pcall(function()
        rect:SetBrushColor(FOLDER_ICON_COLOR)
        rect:SetVisibility(4)
    end)
    local slot, slot_err = try_call(function() return unwrap(canvas:AddChildToCanvas(rect)) end)
    if slot_err ~= nil or slot == nil then return nil, tostring(slot_err or "AddChildToCanvas returned nil") end
    pcall(function()
        slot:SetPosition({ X = x, Y = y })
        slot:SetSize({ X = w, Y = h })
        slot:SetAutoSize(false)
    end)
    return rect, nil
end

local function set_folder_icon_color(color, state_name)
    local canvas = folder_ui_state.iconCanvas
    if canvas == nil or color == nil then return false end

    local count = panel_child_count(canvas) or 0
    local changed = 0
    for i = 0, count - 1 do
        local child = panel_child_at(canvas, i)
        if child ~= nil and string.find(class_name(child), "Border", 1, true) ~= nil then
            local ok = pcall(function() child:SetBrushColor(color) end)
            if ok then changed = changed + 1 end
        end
    end

    folder_ui_state.iconVisualState = state_name or folder_ui_state.iconVisualState
    return changed > 0
end

local function build_native_folder_plus_icon(page)
    local size_box, size_err = construct_widget(page, "/Script/UMG.SizeBox",
        "EnhancedDatabank_FolderPlusSize")
    if size_box == nil then return nil, nil, size_err end
    pcall(function()
        size_box:SetWidthOverride(CREATE_FOLDER_GLYPH_SIZE)
        size_box:SetHeightOverride(CREATE_FOLDER_GLYPH_SIZE)
        size_box:SetVisibility(4)
    end)

    local canvas, canvas_err = construct_widget(page, "/Script/UMG.CanvasPanel",
        "EnhancedDatabank_FolderPlusCanvas")
    if canvas == nil then return nil, nil, canvas_err end
    pcall(function() canvas:SetVisibility(4) end)

    local canvas_slot = select(1, try_call(function() return unwrap(size_box:AddChild(canvas)) end))
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

local function make_create_folder_icon_overlay(page, button)
    local overlay, overlay_err = construct_widget(page, "/Script/UMG.Overlay",
        "EnhancedDatabank_CreateFolderOverlay")
    if overlay == nil then return nil, overlay_err end
    pcall(function() overlay:SetVisibility(4) end)

    local button_slot = select(1, try_call(function() return unwrap(overlay:AddChild(button)) end))
    if button_slot == nil then return nil, "could not add cloned button to icon overlay" end
    pcall(function()
        button_slot:SetHorizontalAlignment(3)
        button_slot:SetVerticalAlignment(3)
    end)

    local icon_size, icon_canvas, icon_err = build_native_folder_plus_icon(page)
    if icon_size == nil then return nil, icon_err end

    local icon_slot = select(1, try_call(function() return unwrap(overlay:AddChild(icon_size)) end))
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

    folder_ui_state.iconCanvas = icon_canvas
    folder_ui_state.iconOverlay = overlay
    return overlay, nil
end

local function set_icon_canvas_color(canvas, color)
    canvas = unwrap(canvas)
    if canvas == nil or color == nil then return false end
    local count = panel_child_count(canvas) or 0
    local changed = 0
    for i = 0, count - 1 do
        local child = panel_child_at(canvas, i)
        if child ~= nil and string.find(class_name(child), "Border", 1, true) ~= nil then
            if pcall(function() child:SetBrushColor(color) end) then changed = changed + 1 end
        end
    end
    return changed > 0
end

local function add_edit_icon_rect(owner, canvas, name, x, y, w, h, angle)
    -- Rename/Delete icons share a 22x22 design grid. Scale the entire
    -- geometry uniformly while keeping the surrounding button and hitbox fixed.
    x = x * RENAME_FOLDER_GLYPH_SCALE
    y = y * RENAME_FOLDER_GLYPH_SCALE
    w = w * RENAME_FOLDER_GLYPH_SCALE
    h = h * RENAME_FOLDER_GLYPH_SCALE

    local rect, rect_err = construct_widget(owner, "/Script/UMG.Border", name)
    if rect == nil then return nil, rect_err end
    pcall(function()
        rect:SetBrushColor(FOLDER_ICON_COLOR_NORMAL)
        rect:SetVisibility(4)
        if angle ~= nil and math.abs(angle) > 0.01 then rect:SetRenderTransformAngle(angle) end
    end)
    local slot, slot_err = try_call(function() return unwrap(canvas:AddChildToCanvas(rect)) end)
    if slot_err ~= nil or slot == nil then return nil, tostring(slot_err or "AddChildToCanvas returned nil") end
    pcall(function()
        slot:SetPosition({ X = x, Y = y })
        slot:SetSize({ X = w, Y = h })
        slot:SetAutoSize(false)
    end)
    return rect, nil
end

local function build_native_edit_icon(owner, suffix)
    local size_box, size_err = construct_widget(owner, "/Script/UMG.SizeBox",
        "EnhancedDatabank_EditSize_" .. tostring(suffix))
    if size_box == nil then return nil, nil, size_err end
    pcall(function()
        size_box:SetWidthOverride(RENAME_FOLDER_GLYPH_SIZE)
        size_box:SetHeightOverride(RENAME_FOLDER_GLYPH_SIZE)
        size_box:SetVisibility(4)
    end)

    local canvas, canvas_err = construct_widget(owner, "/Script/UMG.CanvasPanel",
        "EnhancedDatabank_EditCanvas_" .. tostring(suffix))
    if canvas == nil then return nil, nil, canvas_err end
    pcall(function() canvas:SetVisibility(4) end)
    local canvas_slot = select(1, try_call(function() return unwrap(size_box:AddChild(canvas)) end))
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
    local size_box, size_err = construct_widget(owner, "/Script/UMG.SizeBox",
        "EnhancedDatabank_TrashSize_" .. tostring(suffix))
    if size_box == nil then return nil, nil, size_err end
    pcall(function()
        size_box:SetWidthOverride(RENAME_FOLDER_GLYPH_SIZE)
        size_box:SetHeightOverride(RENAME_FOLDER_GLYPH_SIZE)
        size_box:SetVisibility(4)
    end)

    local canvas, canvas_err = construct_widget(owner, "/Script/UMG.CanvasPanel",
        "EnhancedDatabank_TrashCanvas_" .. tostring(suffix))
    if canvas == nil then return nil, nil, canvas_err end
    pcall(function() canvas:SetVisibility(4) end)
    local canvas_slot = select(1, try_call(function() return unwrap(size_box:AddChild(canvas)) end))
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

local function build_native_transfer_icon(owner, suffix)
    local size_box, size_err = construct_widget(owner, "/Script/UMG.SizeBox",
        "EnhancedDatabank_TransferSize_" .. tostring(suffix))
    if size_box == nil then return nil, nil, size_err end
    pcall(function()
        size_box:SetWidthOverride(RENAME_FOLDER_GLYPH_SIZE)
        size_box:SetHeightOverride(RENAME_FOLDER_GLYPH_SIZE)
        size_box:SetVisibility(4)
    end)

    local canvas, canvas_err = construct_widget(owner, "/Script/UMG.CanvasPanel",
        "EnhancedDatabank_TransferCanvas_" .. tostring(suffix))
    if canvas == nil then return nil, nil, canvas_err end
    pcall(function() canvas:SetVisibility(4) end)
    local canvas_slot = select(1, try_call(function() return unwrap(size_box:AddChild(canvas)) end))
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

local function style_folder_action_button(button, tooltip)
    button = unwrap(button)
    if button == nil then return false end
    pcall(function()
        button:SetButtonInteractionEnabled(true)
        button:SetIsInteractionEnabled(true)
        button:SetIsFocusable(true)
        button:SetIsSelectable(false)
        button:SetToolTipText(FText(tostring(tooltip or "")))
    end)
    for _, widget in ipairs(collect_widget_tree(button)) do
        local cn = class_name(widget)
        if string.find(cn, "RichTextBlock", 1, true) or string.find(cn, "TextBlock", 1, true) then
            pcall(function() widget:SetText(FText("")) end)
            pcall(function() widget:SetTextEx(FText("")) end)
        elseif string.find(cn, "Image", 1, true) then
            local w, h = image_dimensions(widget)
            if w >= 4.0 and h >= 4.0 and w <= 56.0 and h <= 56.0 then
                pcall(function() widget:SetRenderOpacity(0.0); widget:SetVisibility(3) end)
            end
        end
    end
    pcall(function() button:UpdateText(FText("")); button:SetButtonText(FText("")); button:SetText(FText("")) end)
    return true
end

local function style_rename_folder_button(button)
    return style_folder_action_button(button, "RENAME FOLDER")
end

local function make_rename_folder_icon_overlay(owner, button, suffix)
    local overlay, overlay_err = construct_widget(owner, "/Script/UMG.Overlay",
        "EnhancedDatabank_RenameButtonOverlay_" .. tostring(suffix))
    if overlay == nil then return nil, nil, overlay_err end
    pcall(function() overlay:SetVisibility(4) end)

    local button_slot = select(1, try_call(function() return unwrap(overlay:AddChild(button)) end))
    if button_slot == nil then return nil, nil, "could not add rename button to overlay" end
    pcall(function() button_slot:SetHorizontalAlignment(0); button_slot:SetVerticalAlignment(0) end)

    local icon_size, icon_canvas, icon_err = build_native_edit_icon(owner, suffix)
    if icon_size == nil then return nil, nil, icon_err end
    local icon_slot = select(1, try_call(function() return unwrap(overlay:AddChild(icon_size)) end))
    if icon_slot == nil then return nil, nil, "could not add edit icon to rename overlay" end
    pcall(function() icon_slot:SetHorizontalAlignment(2); icon_slot:SetVerticalAlignment(2) end)
    return overlay, icon_canvas, nil
end

local function make_delete_folder_icon_overlay(owner, button, suffix)
    local overlay, overlay_err = construct_widget(owner, "/Script/UMG.Overlay",
        "EnhancedDatabank_DeleteButtonOverlay_" .. tostring(suffix))
    if overlay == nil then return nil, nil, overlay_err end
    pcall(function() overlay:SetVisibility(4) end)

    local button_slot = select(1, try_call(function() return unwrap(overlay:AddChild(button)) end))
    if button_slot == nil then return nil, nil, "could not add delete button to overlay" end
    pcall(function() button_slot:SetHorizontalAlignment(0); button_slot:SetVerticalAlignment(0) end)

    local icon_size, icon_canvas, icon_err = build_native_trash_icon(owner, suffix)
    if icon_size == nil then return nil, nil, icon_err end
    local icon_slot = select(1, try_call(function() return unwrap(overlay:AddChild(icon_size)) end))
    if icon_slot == nil then return nil, nil, "could not add trash icon to delete overlay" end
    pcall(function() icon_slot:SetHorizontalAlignment(2); icon_slot:SetVerticalAlignment(2) end)
    return overlay, icon_canvas, nil
end

local function make_move_character_icon_overlay(owner, button, suffix)
    local overlay, overlay_err = construct_widget(owner, "/Script/UMG.Overlay",
        "EnhancedDatabank_MoveCharacterButtonOverlay_" .. tostring(suffix))
    if overlay == nil then return nil, nil, overlay_err end
    pcall(function() overlay:SetVisibility(4) end)

    local button_slot = select(1, try_call(function() return unwrap(overlay:AddChild(button)) end))
    if button_slot == nil then return nil, nil, "could not add move button to overlay" end
    pcall(function() button_slot:SetHorizontalAlignment(0); button_slot:SetVerticalAlignment(0) end)

    local icon_size, icon_canvas, icon_err = build_native_transfer_icon(owner, suffix)
    if icon_size == nil then return nil, nil, icon_err end
    local icon_slot = select(1, try_call(function() return unwrap(overlay:AddChild(icon_size)) end))
    if icon_slot == nil then return nil, nil, "could not add transfer icon to move overlay" end
    pcall(function() icon_slot:SetHorizontalAlignment(2); icon_slot:SetVerticalAlignment(2) end)
    return overlay, icon_canvas, nil
end

local function register_rename_folder_button(button, pool_vm, name, icon_canvas)
    button = unwrap(button)
    pool_vm = unwrap(pool_vm)
    if button == nil or pool_vm == nil then return false end
    local identity = object_name(button)
    folder_ui_state.renameButtons[identity] = {
        button = button,
        poolVM = pool_vm,
        name = tostring(name or pool_name(pool_vm)),
        iconCanvas = icon_canvas,
        visualState = nil,
    }
    return true
end

local function register_delete_folder_button(button, pool_vm, name, character_count, icon_canvas)
    button = unwrap(button)
    pool_vm = unwrap(pool_vm)
    if button == nil or pool_vm == nil then return false end
    local identity = object_name(button)
    folder_ui_state.deleteButtons[identity] = {
        button = button,
        poolVM = pool_vm,
        name = tostring(name or pool_name(pool_vm)),
        characterCount = tonumber(character_count) or 0,
        iconCanvas = icon_canvas,
        visualState = nil,
    }
    return true
end

local function register_move_character_button(button, character_vm, source_pool_name, icon_canvas)
    button = unwrap(button)
    character_vm = unwrap(character_vm)
    if button == nil or character_vm == nil then return false end
    local guid = character_guid_string(character_vm)
    if guid == nil then return false end
    local identity = object_name(button)
    folder_ui_state.moveButtons[identity] = {
        button = button,
        guid = tostring(guid),
        name = character_display_name(character_vm),
        sourcePoolName = tostring(source_pool_name or ""),
        iconCanvas = icon_canvas,
        visualState = nil,
    }
    return true
end

local function restore_panel_order_with_replacement(parent, captured, old_child, replacement)
    parent = unwrap(parent)
    old_child = unwrap(old_child)
    replacement = unwrap(replacement)
    if parent == nil or replacement == nil or type(captured) ~= "table" then
        return nil, "replacement order prerequisites unavailable"
    end

    -- Prefer the engine's real child insertion API. This preserves layout order
    -- instead of merely translating an appended widget over its siblings.
    local target_index = -1
    local replacement_layout = nil
    for index, entry in ipairs(captured) do
        if entry.child ~= nil and same_object(entry.child, old_child) then
            target_index = index - 1
            replacement_layout = entry.layout
            break
        end
    end
    if target_index < 0 then return nil, "original child missing from captured order" end

    local inserted, insert_err = try_call(function()
        return unwrap(parent:InsertChildAt(target_index, replacement))
    end)
    if insert_err == nil and inserted ~= nil and panel_child_index(parent, replacement) == target_index then
        apply_box_slot_layout(inserted, replacement_layout)
        return inserted, nil
    end

    -- Some shipping panels expose InsertChildAt but do not actually rebuild at
    -- runtime. Fall back to a deterministic detach/re-add pass using the exact
    -- pre-edit child order and slot metadata.
    pcall(function() parent:RemoveChild(replacement) end)
    local current = {}
    local current_count = panel_child_count(parent) or 0
    for i = 0, current_count - 1 do
        local child = panel_child_at(parent, i)
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
            if same_object(child, old_child) then child = replacement end
            local slot, add_err = try_call(function() return unwrap(parent:AddChild(child)) end)
            if add_err ~= nil or slot == nil then
                return nil, "failed rebuilding parent child order: " .. tostring(add_err)
            end
            apply_box_slot_layout(slot, layout)
            if same_object(child, replacement) then replacement_slot = slot end
        end
    end

    if replacement_slot == nil then return nil, "replacement slot missing after rebuild" end
    return replacement_slot, nil
end

local function install_rename_button_on_folder(page, pool_widget, folder_header, pool_vm, name, ordinal, character_count)
    page = unwrap(page)
    pool_widget = unwrap(pool_widget)
    folder_header = unwrap(folder_header)
    pool_vm = unwrap(pool_vm)
    if page == nil or pool_widget == nil or folder_header == nil or pool_vm == nil then
        return false, "folder action prerequisites unavailable"
    end

-- Custom folders are already created by our authoritative renderer, so
    -- decorate the folder header at construction time instead of detaching and
    -- wrapping the shipping header after it is live. The shipped header owns a
    -- root Overlay_0 specifically suited to right-aligned adjunct controls.
    local host = find_tree_widget(folder_header, "Overlay_0")
    if host == nil or string.find(class_name(host), "Overlay", 1, true) == nil then
        return false, "folder header Overlay_0 unavailable"
    end

    if find_tree_widget(folder_header, "EnhancedDatabank_FolderActions_") ~= nil then
        return true, nil
    end

    local create_new = select(1, read_property(page, "WBP_CharacterBankCreateNewBtn"))
    if create_new == nil then create_new = find_tree_widget(page, "WBP_CharacterBankCreateNewBtn_C") end
    if create_new == nil then return false, "native compact button template unavailable" end

    local suffix = tostring(ordinal or 0)

    -- Own every injected object by the folder header itself. When the dynamic
    -- folder widget is removed during an authoritative rebuild, its controls die
    -- with it; no persistent row/header UObject references are required.
    local rename_button, rename_clone_err = clone_widget_like(folder_header, create_new,
        RENAME_FOLDER_BUTTON_MARKER .. suffix)
    if rename_button == nil then return false, rename_clone_err end
    style_folder_action_button(rename_button, "RENAME FOLDER")
    local rename_overlay, rename_canvas, rename_overlay_err =
        make_rename_folder_icon_overlay(folder_header, rename_button, suffix)
    if rename_overlay == nil then return false, rename_overlay_err end

    local delete_button, delete_clone_err = clone_widget_like(folder_header, create_new,
        DELETE_FOLDER_BUTTON_MARKER .. suffix)
    if delete_button == nil then return false, delete_clone_err end
    style_folder_action_button(delete_button, "DELETE FOLDER")
    local delete_overlay, delete_canvas, delete_overlay_err =
        make_delete_folder_icon_overlay(folder_header, delete_button, suffix)
    if delete_overlay == nil then return false, delete_overlay_err end

    local function boxed_action(overlay, marker)
        local box, box_err = construct_widget(folder_header, "/Script/UMG.SizeBox", marker .. suffix)
        if box == nil then return nil, box_err end
        pcall(function()
            box:SetWidthOverride(RENAME_FOLDER_BUTTON_WIDTH)
            box:SetHeightOverride(RENAME_FOLDER_BUTTON_HEIGHT)
            box:SetVisibility(4)
        end)
        local slot = select(1, try_call(function() return unwrap(box:AddChild(overlay)) end))
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

    local actions, actions_err = construct_widget(folder_header, "/Script/UMG.HorizontalBox",
        "EnhancedDatabank_FolderActions_" .. suffix)
    if actions == nil then return false, actions_err end
    pcall(function() actions:SetVisibility(4) end)

    local rename_action_slot = select(1, try_call(function() return unwrap(actions:AddChild(rename_box)) end))
    local delete_action_slot = select(1, try_call(function() return unwrap(actions:AddChild(delete_box)) end))
    if rename_action_slot == nil or delete_action_slot == nil then
        return false, "could not compose folder action row"
    end
    pcall(function()
        rename_action_slot:SetPadding({ Left = 0.0, Top = 0.0, Right = 2.0, Bottom = 0.0 })
        delete_action_slot:SetPadding({ Left = 2.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
    end)

    local actions_slot, attach_err = try_call(function() return unwrap(host:AddChild(actions)) end)
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
    style_folder_action_button(rename_button, "RENAME FOLDER")
    style_folder_action_button(delete_button, "DELETE FOLDER")
    run_on_game_thread_after(80, function()
        local rename_info = folder_ui_state.renameButtons and
            folder_ui_state.renameButtons[object_name(rename_button)] or nil
        if rename_info ~= nil and same_object(rename_info.button, rename_button) then
            style_folder_action_button(rename_button, "RENAME FOLDER")
        end
        local delete_info = folder_ui_state.deleteButtons and
            folder_ui_state.deleteButtons[object_name(delete_button)] or nil
        if delete_info ~= nil and same_object(delete_info.button, delete_button) then
            style_folder_action_button(delete_button, "DELETE FOLDER")
        end
    end)

    log("Folder action buttons installed at generation: pool='" .. tostring(name)
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
    row = unwrap(row)
    if row == nil then return nil, "character row unavailable" end

    local tree = select(1, read_property(row, "WidgetTree"))
    local root = tree and select(1, read_property(tree, "RootWidget")) or nil
    root = unwrap(root)

    -- Prefer the row's native root Overlay so adding the action never changes
    -- BitReactorStackBox_25 ownership or ordering.
    if root ~= nil and string.find(class_name(root), "Overlay", 1, true) ~= nil
        and string.find(object_name(root), "Tooltip", 1, true) == nil then
        return root, nil
    end

    local best, best_score = nil, -1.0
    for _, widget in ipairs(collect_widget_tree(row)) do
        local cn = class_name(widget)
        local identity = object_name(widget)
        if string.find(cn, "Overlay", 1, true) ~= nil
            and string.find(identity, "Tooltip", 1, true) == nil
            and string.find(identity, "EnhancedDatabank", 1, true) == nil then
            local w, h = image_dimensions(widget)
            local score = math.max(0.0, w) * math.max(1.0, h)
            if score > best_score then best, best_score = widget, score end
        end
    end
    if best == nil then return nil, "no safe existing row Overlay found" end
    return best, nil
end

local function pool_widget_view_model(pool_widget)
    pool_widget = unwrap(pool_widget)
    if pool_widget == nil or not resolve_mdvm() then
        return nil, "pool widget/MDViewModel unavailable"
    end
    local pool_vm, err = try_call(function()
        return unwrap(mdvm_library_cdo:GetViewModel(pool_widget, pool_vm_class, FName("")))
    end)
    if err ~= nil or pool_vm == nil then
        return nil, tostring(err or "pool ViewModel unresolved")
    end
    return pool_vm, nil
end

local function install_move_hit_zone_on_row(pool_widget, row, character_vm, source_entry_override, compact_visual)
    pool_widget = unwrap(pool_widget)
    row = unwrap(row)
    character_vm = unwrap(character_vm)
    if pool_widget == nil or row == nil or character_vm == nil then
        return false, "row/pool/character unavailable"
    end
    if string.find(class_name(row), "WBP_CharacterBank_CreatedCharacterItem_C", 1, true) == nil then
        return false, "not a Character Databank row"
    end

    local authority, authority_err = authoritative_pool_state()
    if authority == nil then return false, authority_err end
    local guid = character_guid_string(character_vm)
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
        source_pool_name = pool_name(pool_vm)
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

    local row_identity = object_name(row)
    local existing = folder_ui_state.moveRowActions and folder_ui_state.moveRowActions[row_identity] or nil
    if existing ~= nil and unwrap(existing.hitbox) ~= nil then return true, nil end

    local safe_guid = tostring(guid):gsub("[^%w_]", "_")
    -- Re-renders must adopt any action that is already physically attached to the
    -- shipping row. The state table is intentionally rebuilt every render, but the
    -- stock row itself survives, so blindly constructing another action would leak
    -- duplicate children into that WidgetTree.
    local attached = find_tree_widget(row, "EnhancedDatabank_MoveHitZone_" .. safe_guid)
    if attached ~= nil then
        local adopted = {
            row = row, hitbox = attached, button = row,
            guid = tostring(guid),
            name = character_display_name(character_vm),
            sourcePoolName = tostring(source_pool_name or ""),
            iconCanvas = nil, visualState = nil,
        }
        folder_ui_state.moveRowActions[row_identity] = adopted
        return true, nil
    end

    local host, host_err = find_character_row_action_host(row)
    if host == nil then return false, host_err end

-- An earlier implementation placed a raw UMG Button inside this visual and bound its
    -- multicast OnClicked delegate through UE4SS. Cold Databank entry then
    -- access-violated while installing the first custom-folder row, before this
    -- function could return. Keep the proven-stable row-owned SizeBox visual;
    -- never construct or bind a raw Button in the activation/render call stack.
    local hitbox, hitbox_err = construct_widget(row, "/Script/UMG.SizeBox",
        "EnhancedDatabank_MoveHitZone_" .. safe_guid)
    if hitbox == nil then return false, hitbox_err end
    pcall(function()
        hitbox:SetWidthOverride(MOVE_CHARACTER_BUTTON_WIDTH)
        hitbox:SetHeightOverride(MOVE_CHARACTER_BUTTON_HEIGHT)
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
        local glyph, glyph_err = construct_widget(row, "/Script/UMG.TextBlock",
            "EnhancedDatabank_MoveGlyph_" .. safe_guid)
        if glyph == nil then return false, glyph_err end
        pcall(function()
            glyph:SetText(FText("⇅"))
            glyph:SetJustification(2)
            glyph:SetVisibility(4)
            glyph:SetColorAndOpacity(FOLDER_ICON_COLOR_NORMAL)
        end)
        local glyph_slot = select(1, try_call(function() return unwrap(hitbox:AddChild(glyph)) end))
        if glyph_slot == nil then return false, "could not attach compact transfer glyph to hitbox" end
        pcall(function() glyph_slot:SetHorizontalAlignment(2); glyph_slot:SetVerticalAlignment(2) end)
    else
        local overlay, overlay_err = construct_widget(row, "/Script/UMG.Overlay",
            "EnhancedDatabank_MoveHitOverlay_" .. safe_guid)
        if overlay == nil then return false, overlay_err end
        pcall(function() overlay:SetVisibility(4) end)
        local overlay_slot = select(1, try_call(function() return unwrap(hitbox:AddChild(overlay)) end))
        if overlay_slot == nil then return false, "could not attach transfer overlay to hitbox" end
        pcall(function() overlay_slot:SetHorizontalAlignment(0); overlay_slot:SetVerticalAlignment(0) end)

        -- Mod-created custom folders are small, so retain the richer native
        -- transfer glyph there. They have already proven stable in this path.
        local background, bg_err = construct_widget(row, "/Script/UMG.Border",
            "EnhancedDatabank_MoveHitBackground_" .. safe_guid)
        if background == nil then return false, bg_err end
        pcall(function()
            background:SetBrushColor({ R = 0.055, G = 0.050, B = 0.055, A = 0.92 })
            background:SetVisibility(4)
        end)
        local bg_slot = select(1, try_call(function() return unwrap(overlay:AddChild(background)) end))
        if bg_slot ~= nil then
            pcall(function() bg_slot:SetHorizontalAlignment(0); bg_slot:SetVerticalAlignment(0) end)
        end

        local icon_size, rich_canvas, icon_err = build_native_transfer_icon(row, safe_guid)
        if icon_size == nil then return false, icon_err end
        icon_canvas = rich_canvas
        local icon_slot = select(1, try_call(function() return unwrap(overlay:AddChild(icon_size)) end))
        if icon_slot == nil then return false, "could not attach transfer icon to hitbox" end
        pcall(function() icon_slot:SetHorizontalAlignment(2); icon_slot:SetVerticalAlignment(2) end)
    end

    local action_slot, add_err = try_call(function() return unwrap(host:AddChild(hitbox)) end)
    if add_err ~= nil or action_slot == nil then
        return false, "could not attach transfer hit-zone: " .. tostring(add_err)
    end
    pcall(function()
        action_slot:SetHorizontalAlignment(3)
        action_slot:SetVerticalAlignment(2)
        action_slot:SetPadding({
            Left = 0.0, Top = 0.0,
            Right = MOVE_CHARACTER_RIGHT_PADDING, Bottom = 0.0
        })
    end)

    local action_info = {
        row = row,
        hitbox = hitbox,
        button = row,
        guid = tostring(guid),
        name = character_display_name(character_vm),
        sourcePoolName = tostring(source_pool_name or ""),
        iconCanvas = icon_canvas,
        visualState = nil,
    }
    folder_ui_state.moveRowActions[row_identity] = action_info
    if icon_canvas ~= nil then set_icon_canvas_color(icon_canvas, FOLDER_ICON_COLOR_NORMAL) end
    log("Move Character stable visual installed: '" .. tostring(character_display_name(character_vm))
        .. "' source='" .. tostring(source_pool_name) .. "' guid=" .. tostring(guid)
        .. " visual=" .. tostring(compact_visual == true and "compact" or "rich"))
    return true, nil
end

local function decorate_pool_rows(pool_widget, rows, label, source_entry, compact_visual)
    pool_widget = unwrap(pool_widget)
    if pool_widget == nil then return 0, 0 end
    local stack = select(1, read_property(pool_widget, "BitReactorStackBox_25"))
    if stack == nil then return 0, 0 end
    local installed, failed = 0, 0
    for index, character_vm in ipairs(rows or {}) do
        local row = panel_child_at(stack, index - 1)
        if row ~= nil then
            local ok, err = install_move_hit_zone_on_row(pool_widget, row, character_vm, source_entry, compact_visual)
            if ok then
                installed = installed + 1
            else
                failed = failed + 1
                if err ~= nil and string.find(tostring(err), "ownership has not converged", 1, true) == nil then
                    log("Move Character hit-zone decoration skipped: " .. tostring(label)
                        .. " row=" .. tostring(index - 1) .. " err=" .. tostring(err))
                end
            end
        end
    end
    return installed, failed
end

local function schedule_default_pool_row_decoration(pool_widget, rows, source_entry)
    pool_widget = unwrap(pool_widget)
    if pool_widget == nil then return false end
    local generation = default_move_decor_generation
    local pool_identity = object_name(pool_widget)
    local total = #(rows or {})
    log("Default move decoration scheduled: rows=" .. tostring(total)
        .. " generation=" .. tostring(generation))

    local function step(index)
        run_on_game_thread_after(index == 1 and 30 or 18, function()
                if generation ~= default_move_decor_generation then
                    log("Default move decoration cancelled: stale generation=" .. tostring(generation))
                    return
                end
                local live_pool = unwrap(pool_widget)
                if live_pool == nil or object_name(live_pool) ~= pool_identity then
                    log("Default move decoration cancelled: shipping pool widget changed")
                    return
                end
                if index > total then
                    log("Default move decoration complete: rows=" .. tostring(total))
                    return
                end

                local stack = select(1, read_property(live_pool, "BitReactorStackBox_25"))
                local row = stack and panel_child_at(stack, index - 1) or nil
                local character_vm = unwrap(rows[index])
                local name = character_vm and character_display_name(character_vm) or "<nil>"
                local guid = character_vm and character_guid_string(character_vm) or nil
                log("Default move decoration begin: row=" .. tostring(index - 1)
                    .. " name='" .. tostring(name) .. "' guid=" .. tostring(guid))

                if row == nil or character_vm == nil then
                    log("Default move decoration skipped: row=" .. tostring(index - 1)
                        .. " rowAvailable=" .. tostring(row ~= nil)
                        .. " vmAvailable=" .. tostring(character_vm ~= nil))
                else
                    local ok, err = install_move_hit_zone_on_row(
                        live_pool, row, character_vm, source_entry, true)
                    if not ok then
                        log("Default move decoration failed: row=" .. tostring(index - 1)
                            .. " name='" .. tostring(name) .. "' err=" .. tostring(err))
                    end
                end

                if index < total then
                    step(index + 1)
                else
                    log("Default move decoration complete: rows=" .. tostring(total))
                end
        end)
    end

    if total > 0 then step(1) end
    return true
end


local function cleanup_move_row_wrappers(pool_widget)
-- The release implementation never wraps, reparents, polls, or shares controls between character
    -- rows. Each action is owned by the row that generated it.
    return 0
end

local function clear_named_slot_content(widget, property_name)
    local slot = select(1, read_property(widget, property_name))
    if slot == nil then return end
    pcall(function() slot:ClearChildren() end)
    pcall(function() slot:SetContent(nil) end)
end

local function reset_folder_popup_state()
    folder_popup_state.widget = nil
    folder_popup_state.mode = nil
    folder_popup_state.textBox = nil
    folder_popup_state.resultActions = {}
    folder_popup_state.suppressResult = false
    folder_popup_state.initialText = ""
    folder_popup_state.targetPoolVM = nil
    folder_popup_state.targetPoolName = nil
    folder_popup_state.targetCharacterGuid = nil
    folder_popup_state.targetCharacterName = nil
    folder_popup_state.sourcePoolName = nil
end

local function gameplay_tag_value(tag)
    tag = unwrap(tag)
    if tag == nil then return nil end
    local tag_name = select(1, read_property(tag, "TagName"))
    if tag_name ~= nil then return text_value(tag_name) end
    return nil
end

local function get_messaging_subsystem(world_context)
    local lib_class, lib_err = load_class("/Script/Engine.SubsystemBlueprintLibrary")
    if lib_class == nil then return nil, lib_err end
    local lib = select(1, try_call(function() return unwrap(lib_class:GetCDO()) end))
    local msg_class, msg_err = load_class("/Script/BitReactorGame.BitReactorMessagingSubsystem")
    if lib == nil or msg_class == nil then return nil, tostring(msg_err or "messaging classes unavailable") end
    local subsystem, err = try_call(function() return unwrap(lib:GetLocalPlayerSubsystem(world_context, msg_class)) end)
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
    if folder_dialog_result_hook_registered then return true end
    local ok, hook_id = pcall(function()
        return RegisterHook(
            "/Game/Game/UI/Common/WBP_GenericPopupMessage.WBP_GenericPopupMessage_C:BP_OnHideDialog",
            function(self, result)
                if handle_folder_dialog_result ~= nil then handle_folder_dialog_result(self, result) end
            end
        )
    end)
    if ok and hook_id ~= nil then
        folder_dialog_result_hook_registered = true
        log("Create Folder native dialog result hook registered.")
        return true
    end
    log("Create Folder dialog result hook unavailable: " .. tostring(hook_id))
    return false
end

local function create_folder_entry(popup, initial_text)
    local entry_class, class_err = load_class(ENTRY_TEXT_CLASS_PATH)
    if entry_class == nil then return nil, nil, class_err end
    local entry, entry_err = create_user_widget(popup, entry_class)
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
    local editable = select(1, read_property(entry, "EditableText"))
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
    run_on_game_thread_after(1, apply)
    return entry, editable, nil
end

local function show_folder_dialog(mode, title, body, actions, want_entry, initial_text, target_pool_vm, target_pool_name)
    if folder_popup_state.widget ~= nil then
        local old = folder_popup_state.widget
        folder_popup_state.suppressResult = true
        pcall(function() old:OnCloseWindow() end)
        reset_folder_popup_state()
    end

    local host = find_first("WBP_CharacterBank_Master_C")
    if host == nil then log("Create Folder dialog failed: Databank host unavailable"); return false end
    local descriptor_class, descriptor_err = load_class("/Script/BitReactorGame.BitReactorGameDialogDescriptor")
    if descriptor_class == nil then log("Create Folder dialog failed: " .. tostring(descriptor_err)); return false end
    local descriptor_cdo = select(1, try_call(function() return unwrap(descriptor_class:GetCDO()) end))
    if descriptor_cdo == nil then return false end
    local message_class = select(1, load_class(GENERIC_POPUP_CLASS_PATH))
    if message_class == nil then message_class = select(1, load_class(GENERIC_POPUP_FALLBACK_CLASS_PATH)) end
    if message_class == nil then log("Create Folder dialog failed: popup class unavailable"); return false end

    local action_structs, result_actions = {}, {}
    local result_tags = { DIALOG_RESULT_PRIMARY, DIALOG_RESULT_SECONDARY }
    for i, action in ipairs(actions or {}) do
        local result_tag = result_tags[i]
        table.insert(action_structs, make_dialog_action(result_tag, action.label))
        result_actions[result_tag] = action.id
    end
    local descriptor, make_err = try_call(function()
        return unwrap(descriptor_cdo:MakeGameDialogDescriptor(
            descriptor_class, FText(title), FText(body), action_structs, message_class))
    end)
    if make_err ~= nil or descriptor == nil then log("Create Folder descriptor failed: " .. tostring(make_err)); return false end
    local subsystem, subsystem_err = get_messaging_subsystem(host)
    if subsystem == nil then log("Create Folder dialog failed: " .. tostring(subsystem_err)); return false end
    local popup, popup_err = try_call(function() return unwrap(subsystem:BP_ShowMessageBox(descriptor, nil)) end)
    if popup_err ~= nil or popup == nil then log("Create Folder BP_ShowMessageBox failed: " .. tostring(popup_err)); return false end
    if not ensure_folder_dialog_result_hook() then return false end

    clear_named_slot_content(popup, "AboveText")
    clear_named_slot_content(popup, "Belowtext")
    folder_popup_state.widget = popup
    folder_popup_state.mode = mode
    folder_popup_state.resultActions = result_actions
    folder_popup_state.suppressResult = false
    folder_popup_state.initialText = tostring(initial_text or "")
    folder_popup_state.targetPoolVM = target_pool_vm
    folder_popup_state.targetPoolName = target_pool_name
    pcall(function() popup["Modal Short"] = true; popup.HideBackground = false; popup:SetVisibility(0) end)

    if want_entry then
        local entry, editable, entry_err = create_folder_entry(popup, folder_popup_state.initialText)
        if entry == nil or editable == nil then
            log("Create Folder entry failed: " .. tostring(entry_err)); return false
        end
        local below = select(1, read_property(popup, "Belowtext"))
        if below == nil then return false end
        local _, set_err = try_call(function() below:SetContent(entry) end)
        if set_err ~= nil then return false end
        folder_popup_state.textBox = editable
        run_on_game_thread_after(1, function()
            if folder_popup_state.widget == popup then pcall(function() editable:SetKeyboardFocus() end) end
        end)
    end

    run_on_game_thread_after(1, function()
        if folder_popup_state.widget == popup then
            pcall(function() popup:SetVisibility(0); popup:ActivateWidget() end)
        end
    end)
    log("Create Folder native dialog opened: mode=" .. tostring(mode))
    return true
end

local function show_folder_notice(title, body)
    return show_folder_dialog("notice", title, body, { { id = "ok", label = "OK" } }, false)
end

local function style_move_destination_button(button, label)
    button = unwrap(button)
    if button == nil then return false end
    local text = tostring(label or "")
    pcall(function()
        button:SetButtonInteractionEnabled(true)
        button:SetIsInteractionEnabled(true)
        button:SetIsFocusable(true)
        button:SetIsSelectable(false)
        button:SetToolTipText(FText("MOVE TO " .. text))
    end)
    for _, widget in ipairs(collect_widget_tree(button)) do
        local cn = class_name(widget)
        if string.find(cn, "RichTextBlock", 1, true) or string.find(cn, "TextBlock", 1, true) then
            pcall(function() widget:SetText(FText(text)) end)
            pcall(function() widget:SetTextEx(FText(text)) end)
        elseif string.find(cn, "Image", 1, true) then
            local w, h = image_dimensions(widget)
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

local function perform_move_character(guid_string, target_pool_name, character_name)
    guid_string = tostring(guid_string or "")
    target_pool_name = trim_string(target_pool_name)
    character_name = trim_string(character_name)
    log("Move Character deferred move begin: guid=" .. tostring(guid_string)
        .. " target='" .. tostring(target_pool_name) .. "'")
    if guid_string == "" or target_pool_name == "" then
        show_folder_notice("MOVE CHARACTER FAILED", "The selected character or destination is no longer available.")
        return
    end

    local authority, authority_err = authoritative_pool_state()
    if authority == nil then
        log("Move Character authority failed: " .. tostring(authority_err))
        show_folder_notice("MOVE CHARACTER FAILED", "The Character Databank state could not be verified.")
        return
    end
    local target_exists = tostring(authority.default_custom.name or "") == target_pool_name
        or (authority.custom_by_name and authority.custom_by_name[target_pool_name] ~= nil)
    if not target_exists then
        show_folder_notice("MOVE CHARACTER FAILED", "That destination folder no longer exists.")
        return
    end

    local guid_value, current_pool_name, guid_err = find_authoritative_guid_value(guid_string)
    if guid_value == nil then
        log("Move Character GUID lookup failed: " .. tostring(guid_err))
        show_folder_notice("MOVE CHARACTER FAILED", "The character could not be found in the current Databank state.")
        return
    end
    if tostring(current_pool_name or "") == target_pool_name then
        return
    end

    local source_is_default = tostring(current_pool_name or "")
        == tostring(authority.default_custom.name or "")
    local target_is_default = target_pool_name == tostring(authority.default_custom.name or "")

    -- Manager-direct moves are the stable persistence path, but the shipping
    -- Default pool can retain the moved character in its live ViewModel array.
    -- Never regenerate or reparent that pool. Instead, after the move, change
    -- only the matching native row's visibility. Its slot remains in place, so
    -- the stale typed-array position continues to line up with later selections.
    local function set_default_row_visibility(visibility, reason)
        local databank_vm = find_first("BrunoCharacterDatabankViewModel")
        local default_vm = databank_vm and select(1, read_property(
            databank_vm, "DefaultCustomCharacterPoolViewModel")) or nil
        local wanted_index, ordinal = nil, 0
        local items = default_vm and select(1, read_property(
            default_vm, "PoolCharacterViewModels")) or nil
        array_each(items, function(_, candidate)
            if wanted_index == nil and character_guid_string(candidate) == guid_string then
                wanted_index = ordinal
            end
            ordinal = ordinal + 1
        end)
        if wanted_index == nil then
            log("Default row visibility reconcile deferred/unavailable: guid="
                .. tostring(guid_string) .. " reason=" .. tostring(reason))
            return false
        end

        local master = find_first("WBP_CharacterBank_Master_C")
        local page = master and select(1, read_property(master, "OtherCharacterList")) or nil
        local stock_widget = page and select(1, read_property(page, "CharacterPool")) or nil
        local stack = stock_widget and select(1, read_property(
            stock_widget, "BitReactorStackBox_25")) or nil
        local row = stack and panel_child_at(stack, wanted_index) or nil
        if row == nil then
            log("Default row visibility reconcile could not find row index="
                .. tostring(wanted_index) .. " guid=" .. tostring(guid_string))
            return false
        end
        local ok, visibility_err = pcall(function() row:SetVisibility(visibility) end)
        log("Default row visibility reconciled: index=" .. tostring(wanted_index)
            .. " guid=" .. tostring(guid_string) .. " visibility="
            .. tostring(visibility) .. " reason=" .. tostring(reason)
            .. " ok=" .. tostring(ok) .. " err=" .. tostring(visibility_err))
        return ok
    end

    local manager = authority.manager or find_first("BitReactorCharacterPoolManager")
    if manager == nil then
        show_folder_notice("MOVE CHARACTER FAILED", "The Character Pool Manager is not ready.")
        return
    end

    folder_ui_state.pendingMove = {
        guid = tostring(guid_string),
        sourcePoolName = tostring(current_pool_name or ""),
        targetPoolName = tostring(target_pool_name),
        attempts = 0,
    }

-- The manager-direct mutation is stable. Default-pool visual
    -- reconciliation is handled below without replaying its generated handler.
    log("Move Character invoking CharacterPoolManager.MoveCharacterToAnotherPool: source='"
        .. tostring(current_pool_name) .. "' target='" .. tostring(target_pool_name) .. "'")
    local moved, move_err = try_call(function()
        return manager:MoveCharacterToAnotherPool(guid_value, FText(target_pool_name))
    end)
    log("Move Character manager call returned: result=" .. tostring(moved)
        .. " err=" .. tostring(move_err))
    if move_err ~= nil or moved ~= true then
        folder_ui_state.pendingMove = nil
        log("MoveCharacterToAnotherPool failed: guid=" .. tostring(guid_string)
            .. " source='" .. tostring(current_pool_name)
            .. "' target='" .. tostring(target_pool_name)
            .. "' result=" .. tostring(moved) .. " err=" .. tostring(move_err))
        show_folder_notice("MOVE CHARACTER FAILED", "Zero Company did not move the character.")
        return
    end

    if source_is_default then
        set_default_row_visibility(1, "moved out of Default")
    elseif target_is_default then
        local visible_now = set_default_row_visibility(0, "moved into Default")
        if not visible_now then
            run_on_game_thread_after(160, function()
                set_default_row_visibility(0, "moved into Default delayed")
            end)
        end
    end

    log("MOVE CHARACTER SUCCESS: '" .. tostring(character_name ~= "" and character_name or guid_string)
        .. "' guid=" .. tostring(guid_string)
        .. " source='" .. tostring(current_pool_name)
        .. "' target='" .. tostring(target_pool_name) .. "'")
    -- The manager refresh hook rebuilds the generated custom-folder rows.
end

local function close_move_destination_picker()
    local popup = unwrap(folder_popup_state.widget)
    if popup ~= nil then
        folder_popup_state.suppressResult = true
        clear_named_slot_content(popup, "AboveText")
        clear_named_slot_content(popup, "Belowtext")
        pcall(function() popup:OnCloseWindow() end)
    end
    reset_folder_popup_state()
    folder_ui_state.moveDestinationButtons = {}
end

show_move_character_dialog = function(move_info)
    if move_info == nil then return false end
    local guid_string = tostring(move_info.guid or "")
    local source_pool_name = tostring(move_info.sourcePoolName or "")
    local character_name = tostring(move_info.name or "Character")

    local authority, authority_err = authoritative_pool_state()
    if authority == nil then
        log("Move Character picker authority failed: " .. tostring(authority_err))
        return show_folder_notice("MOVE CHARACTER FAILED", "The Character Databank state could not be verified.")
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
        return show_folder_notice("NO DESTINATION FOLDERS",
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
    if not opened or folder_popup_state.widget == nil then return false end

    folder_popup_state.targetCharacterGuid = guid_string
    folder_popup_state.targetCharacterName = character_name
    folder_popup_state.sourcePoolName = source_pool_name
    folder_ui_state.moveDestinationButtons = {}

    local popup = unwrap(folder_popup_state.widget)
    local below = select(1, read_property(popup, "Belowtext"))
    if below == nil then return false end

    local list, list_err = construct_widget(popup, "/Script/UMG.VerticalBox",
        "EnhancedDatabank_MoveDestinationList")
    if list == nil then
        log("Move Character destination list failed: " .. tostring(list_err))
        return false
    end
    pcall(function() list:SetVisibility(4) end)

    local page = unwrap(folder_ui_state.page)
    local create_new = page and select(1, read_property(page, "WBP_CharacterBankCreateNewBtn")) or nil
    if create_new == nil and page ~= nil then
        create_new = find_tree_widget(page, "WBP_CharacterBankCreateNewBtn_C")
    end
    if create_new == nil then
        log("Move Character picker missing native button template")
        return false
    end

    for index, destination in ipairs(destinations) do
        local button, clone_err = clone_widget_like(page, create_new,
            "EnhancedDatabank_MoveDestination_" .. tostring(index))
        if button == nil then
            log("Move Character destination button clone failed: " .. tostring(clone_err))
        else
            style_move_destination_button(button, destination.label)
            local box, box_err = construct_widget(popup, "/Script/UMG.SizeBox",
                "EnhancedDatabank_MoveDestinationSize_" .. tostring(index))
            if box == nil then
                log("Move Character destination SizeBox failed: " .. tostring(box_err))
            else
                pcall(function()
                    box:SetHeightOverride(48.0)
                    box:SetVisibility(4)
                end)
                local box_slot = select(1, try_call(function() return unwrap(box:AddChild(button)) end))
                if box_slot ~= nil then
                    pcall(function()
                        box_slot:SetHorizontalAlignment(3)
                        box_slot:SetVerticalAlignment(3)
                    end)
                    local list_slot = select(1, try_call(function() return unwrap(list:AddChild(box)) end))
                    if list_slot ~= nil then
                        pcall(function()
                            list_slot:SetPadding({ Left = 0.0, Top = 3.0, Right = 0.0, Bottom = 3.0 })
                        end)
                        folder_ui_state.moveDestinationButtons[object_name(button)] = {
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
    run_on_game_thread_after(80, function()
        if folder_popup_state.widget == nil or not same_object(folder_popup_state.widget, popup) then return end
        for _, info in pairs(folder_ui_state.moveDestinationButtons or {}) do
            if info.popup ~= nil and same_object(info.popup, popup) then
                style_move_destination_button(info.button, info.targetLabel)
            end
        end
    end)

    local _, set_err = try_call(function() return below:SetContent(list) end)
    if set_err ~= nil then
        log("Move Character destination list attach failed: " .. tostring(set_err))
        return false
    end
    return true
end

local function perform_create_folder(name)
    name = trim_string(name)
    if name == "" then
        show_folder_notice("INVALID FOLDER NAME", "Enter a folder name before choosing Create.")
        return
    end
    local vm = find_first("BrunoCharacterDatabankViewModel")
    if vm == nil then show_folder_notice("CREATE FOLDER FAILED", "The Character Databank is not ready."); return end
    local available, available_err = try_call(function() return vm:IsNewPoolNameAvailable(FText(name)) end)
    if available_err ~= nil then
        log("Create Folder availability check failed: " .. tostring(available_err))
        show_folder_notice("CREATE FOLDER FAILED", "The folder name could not be validated.")
        return
    end
    if available ~= true then
        show_folder_notice("FOLDER NAME UNAVAILABLE", "A folder with that name already exists. Choose another name.")
        return
    end
    local pool, create_err = try_call(function() return unwrap(vm:CreatePool(FText(name), 5)) end)
    if create_err ~= nil or pool == nil then
        log("CreatePool failed for '" .. tostring(name) .. "': " .. tostring(create_err))
        show_folder_notice("CREATE FOLDER FAILED", "Zero Company did not create the folder.")
        return
    end
    log("CREATE FOLDER SUCCESS: name='" .. tostring(name) .. "' pool=" .. object_name(pool))
    -- CreatePool's native refresh hook schedules the authoritative renderer.
end

local function perform_rename_folder(pool_vm, old_name, new_name)
    pool_vm = unwrap(pool_vm)
    old_name = trim_string(old_name)
    new_name = trim_string(new_name)

    if pool_vm == nil or old_name == "" then
        show_folder_notice("RENAME FOLDER FAILED", "The selected folder is no longer available.")
        return
    end
    if new_name == "" then
        show_folder_notice("INVALID FOLDER NAME", "Enter a folder name before choosing Rename.")
        return
    end
    if new_name == old_name then
        log("Rename Folder no-op: name unchanged ('" .. tostring(old_name) .. "').")
        return
    end

    local vm = find_first("BrunoCharacterDatabankViewModel")
    if vm == nil then
        show_folder_notice("RENAME FOLDER FAILED", "The Character Databank is not ready.")
        return
    end

    local available, available_err = try_call(function()
        return vm:IsNewPoolNameAvailable(FText(new_name))
    end)
    if available_err ~= nil then
        log("Rename Folder availability check failed: " .. tostring(available_err))
        show_folder_notice("RENAME FOLDER FAILED", "The folder name could not be validated.")
        return
    end
    if available ~= true then
        show_folder_notice("FOLDER NAME UNAVAILABLE", "A folder with that name already exists. Choose another name.")
        return
    end

    local _, rename_err = try_call(function()
        return vm:RenamePool(pool_vm, FText(new_name))
    end)
    if rename_err ~= nil then
        log("RenamePool failed: '" .. tostring(old_name) .. "' -> '" .. tostring(new_name)
            .. "': " .. tostring(rename_err))
        show_folder_notice("RENAME FOLDER FAILED", "Zero Company did not rename the folder.")
        return
    end

    log("RENAME FOLDER SUCCESS: '" .. tostring(old_name) .. "' -> '" .. tostring(new_name) .. "'")
end

local function show_rename_folder_dialog(pool_vm, old_name)
    pool_vm = unwrap(pool_vm)
    old_name = trim_string(old_name)
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

local function current_custom_pool_count(name)
    local authority, err = authoritative_pool_state()
    if authority == nil then return nil, err end
    local entry = authority.custom_by_name and authority.custom_by_name[tostring(name or "")] or nil
    if entry == nil then return nil, "folder is no longer authoritative" end
    return tonumber(entry.count) or 0, nil
end

local function perform_delete_folder(pool_vm, name)
    pool_vm = unwrap(pool_vm)
    name = trim_string(name)
    if pool_vm == nil or name == "" then
        show_folder_notice("DELETE FOLDER FAILED", "The selected folder is no longer available.")
        return
    end

    -- Re-check authoritative ownership at the moment of deletion instead of
    -- trusting the count captured when the button was rendered.
    local count, count_err = current_custom_pool_count(name)
    if count == nil then
        log("Delete Folder authority check failed for '" .. tostring(name) .. "': " .. tostring(count_err))
        show_folder_notice("DELETE FOLDER FAILED", "The folder state could not be verified.")
        return
    end
    if count > 0 then
        show_folder_notice(
            "FOLDER NOT EMPTY",
            "Move the " .. tostring(count) .. " character" .. (count == 1 and "" or "s")
                .. " out of '" .. tostring(name) .. "' before deleting it."
        )
        return
    end

    local vm = find_first("BrunoCharacterDatabankViewModel")
    if vm == nil then
        show_folder_notice("DELETE FOLDER FAILED", "The Character Databank is not ready.")
        return
    end

    local _, delete_err = try_call(function() return vm:DeletePool(pool_vm) end)
    if delete_err ~= nil then
        log("DeletePool failed for '" .. tostring(name) .. "': " .. tostring(delete_err))
        show_folder_notice("DELETE FOLDER FAILED", "Zero Company did not delete the folder.")
        return
    end
    log("DELETE FOLDER SUCCESS: '" .. tostring(name) .. "'")
end

local function show_delete_folder_dialog(pool_vm, name, captured_count)
    pool_vm = unwrap(pool_vm)
    name = trim_string(name)
    if pool_vm == nil or name == "" then return false end

    local count, count_err = current_custom_pool_count(name)
    if count == nil then
        log("Delete Folder preflight failed for '" .. tostring(name) .. "': " .. tostring(count_err))
        return show_folder_notice("DELETE FOLDER FAILED", "The folder state could not be verified.")
    end
    if count > 0 then
        return show_folder_notice(
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
    local widget = unwrap(widget_value)
    local result = unwrap(result_value)
    if widget == nil or folder_popup_state.widget == nil or not same_object(widget, folder_popup_state.widget) then return end
    if folder_popup_state.suppressResult then return end

    local captured_text = ""
    if folder_popup_state.textBox ~= nil then
        local value = select(1, try_call(function() return folder_popup_state.textBox:GetText() end))
        captured_text = text_value(value)
    end
    local result_tag = gameplay_tag_value(result)
    local action = result_tag and folder_popup_state.resultActions[result_tag] or nil
    local mode = folder_popup_state.mode
    local target_pool_vm = folder_popup_state.targetPoolVM
    local target_pool_name = folder_popup_state.targetPoolName
    clear_named_slot_content(widget, "AboveText")
    clear_named_slot_content(widget, "Belowtext")
    reset_folder_popup_state()
    if mode == "move_character" then folder_ui_state.moveDestinationButtons = {} end

    if action == nil then log("Databank dialog closed with unmapped result: " .. tostring(result_tag)); return end
    log("Databank dialog result: mode=" .. tostring(mode) .. " action=" .. tostring(action) .. " name='" .. tostring(captured_text) .. "'")
    if mode == "create_folder" and action == "create" then
        run_on_game_thread_after(120, function() perform_create_folder(captured_text) end)
    elseif mode == "rename_folder" and action == "rename" then
        run_on_game_thread_after(120, function()
            perform_rename_folder(target_pool_vm, target_pool_name, captured_text)
        end)
    elseif mode == "delete_folder" and action == "delete" then
        run_on_game_thread_after(120, function()
            perform_delete_folder(target_pool_vm, target_pool_name)
        end)
    end
end

local function show_create_folder_dialog()
    return show_folder_dialog(
        "create_folder",
        "CREATE FOLDER",
        "Enter a name for the new Character Databank folder.",
        { { id = "create", label = "CREATE" }, { id = "cancel", label = "CANCEL" } },
        true
    )
end

local function button_identity(widget)
    return object_name(widget)
end

local function register_folder_button(button)
    local identity = button_identity(button)
    folder_ui_state.buttons[identity] = true
    folder_ui_state.button = button
    log("Create Folder button registered: " .. tostring(identity))
end

local function hovered_move_row_action()
    for _, info in pairs(folder_ui_state.moveRowActions or {}) do
        local hitbox = info and unwrap(info.hitbox) or nil
        if hitbox ~= nil then
            local hovered = false
            pcall(function() hovered = hitbox:IsHovered() == true end)
            if hovered then return info end
        end
    end
    return nil
end

local function schedule_move_character_dialog(move_info, source)
    if move_info == nil or folder_ui_state.moveClickScheduled then return false end
    folder_ui_state.moveClickScheduled = true
    log("Move Character transfer hit-zone clicked via " .. tostring(source or "unknown")
        .. ": '" .. tostring(move_info.name) .. "' source='" .. tostring(move_info.sourcePoolName) .. "'")
    run_on_game_thread_after(1, function()
        folder_ui_state.moveClickScheduled = false
        show_move_character_dialog(move_info)
    end)
    return true
end

local function install_folder_button_click_hook()
    if folder_button_click_hook_registered then return true end
    local ok, hook_id = pcall(function()
        return RegisterHook(
            "/Script/CommonUI.CommonButtonBase:HandleButtonClicked",
            function(self)
                local button = unwrap(self)
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
                    schedule_move_character_dialog(hovered_move, "CommonUI.HandleButtonClicked")
                    return
                end

                local destination_info = folder_ui_state.moveDestinationButtons
                    and folder_ui_state.moveDestinationButtons[identity] or nil
                if destination_info ~= nil then
                    log("Move Character destination clicked: '" .. tostring(destination_info.characterName)
                        .. "' -> '" .. tostring(destination_info.targetLabel) .. "'")
                    local guid = tostring(destination_info.guid or "")
                    local target = tostring(destination_info.targetPoolName or "")
                    local character_name = tostring(destination_info.characterName or "Character")

                    -- Do not tear down the popup from inside the destination
                    -- button's HandleButtonClicked call stack. Doing so destroys
                    -- widgets while CommonUI/UE4SS are still dispatching that exact
-- widget's native click, which caused an earlier crash. Mark the
                    -- click consumed, let the native callback return, then close on
                    -- a later game-thread turn and only move after the outro starts.
                    folder_popup_state.suppressResult = true
                    folder_ui_state.moveDestinationButtons = {}
                    run_on_game_thread_after(75, function()
                        log("Move Character deferred picker close begin")
                        close_move_destination_picker()
                        log("Move Character deferred picker close complete")
                        run_on_game_thread_after(125, function()
                            perform_move_character(guid, target, character_name)
                        end)
                    end)
                    return
                end

                local move_info = folder_ui_state.moveButtons and folder_ui_state.moveButtons[identity] or nil
                if move_info ~= nil then
                    if move_info.selectedDetail == true then
                        local resolved, resolve_err = require("selected_move_button").resolve_move_info({
                            unwrap = unwrap,
                            tryCall = try_call,
                            objectName = object_name,
                            log = log,
                            findFirst = find_first,
                            readProperty = read_property,
                            findMembership = function(selected_row)
                                local authority, authority_err = authoritative_pool_state()
                                if authority == nil then return nil, authority_err end
                                local databank_vm = find_first("BrunoCharacterDatabankViewModel")
                                local master = find_first("WBP_CharacterBank_Master_C")
                                local page = master and select(1, read_property(
                                    master, "OtherCharacterList")) or nil
                                local stock_widget = page and select(1, read_property(
                                    page, "CharacterPool")) or nil
                                local default_vm = databank_vm and select(1, read_property(
                                    databank_vm, "DefaultCustomCharacterPoolViewModel")) or nil
                                if page == nil or databank_vm == nil
                                    or stock_widget == nil or default_vm == nil then
                                    return nil, "Character Databank page/ViewModels unavailable."
                                end

                                local function result_for(pool_widget, rows, entry, is_default)
                                    pool_widget = unwrap(pool_widget)
                                    if pool_widget == nil or entry == nil then return nil end
                                    local stack = select(1, read_property(
                                        pool_widget, "BitReactorStackBox_25"))
                                    local row_index = stack and panel_child_index(stack, selected_row) or -1
                                    if row_index < 0 then return nil end

                                    local candidate = nil
                                    if rows ~= nil then
                                        candidate = unwrap(rows[row_index + 1])
                                    else
                                        local ordinal = 0
                                        local items = select(1, read_property(
                                            default_vm, "PoolCharacterViewModels"))
                                        array_each(items, function(_, item)
                                            if candidate == nil and ordinal == row_index then
                                                candidate = unwrap(item)
                                            end
                                            ordinal = ordinal + 1
                                        end)
                                    end

                                    local guid = candidate and character_guid_string(candidate) or nil
                                    log("Selected-character row-position candidate: pool='"
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
                                        name = character_display_name(candidate),
                                        sourcePoolName = tostring(entry.name or ""),
                                    }, nil
                                end

                                -- The shipping pool remains wholly native. Touch
                                -- only its selected row, and only after MOVE is
                                -- clicked; there is no activation-time row scan.
                                local found, found_err = result_for(
                                    stock_widget, nil, authority.default_custom, true)
                                if found ~= nil or found_err ~= nil then return found, found_err end

                                -- Dynamic records contain the exact ordered VM
                                -- list used to construct each visible pool.
                                for _, rendered_pool in ipairs(folder_ui_state.renderedPools or {}) do
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
                            log("Selected-character Move unavailable: " .. tostring(resolve_err))
                            show_folder_notice("MOVE CHARACTER UNAVAILABLE", tostring(resolve_err))
                            return
                        end
                        move_info = resolved
                    end
                    log("Move Character detail action clicked: '" .. tostring(move_info.name)
                        .. "' source='" .. tostring(move_info.sourcePoolName) .. "'")
                    schedule_move_character_dialog(move_info, "selected-character detail button")
                    return
                end

                local rename_info = folder_ui_state.renameButtons and folder_ui_state.renameButtons[identity] or nil
                if rename_info ~= nil then
                    log("Rename Folder edit icon clicked: '" .. tostring(rename_info.name) .. "'")
                    run_on_game_thread_after(1, function()
                        show_rename_folder_dialog(rename_info.poolVM, rename_info.name)
                    end)
                    return
                end

                local delete_info = folder_ui_state.deleteButtons and folder_ui_state.deleteButtons[identity] or nil
                if delete_info ~= nil then
                    log("Delete Folder trash icon clicked: '" .. tostring(delete_info.name)
                        .. "' capturedCount=" .. tostring(delete_info.characterCount))
                    run_on_game_thread_after(1, function()
                        show_delete_folder_dialog(delete_info.poolVM, delete_info.name,
                            delete_info.characterCount)
                    end)
                    return
                end

                if not folder_ui_state.buttons[identity] then return end
                log("Create Folder icon clicked; deferring dialog until native click unwinds.")
                run_on_game_thread_after(1, show_create_folder_dialog)
            end
        )
    end)
    if ok and hook_id ~= nil then
        folder_button_click_hook_registered = true
        log("Create Folder button click hook registered.")
        return true
    end
    log("Create Folder click hook failed: " .. tostring(hook_id))
    return false
end

local function set_registered_action_icon_state(button, hovered)
    button = unwrap(button)
    if button == nil then return end
    local identity = button_identity(button)
    if folder_ui_state.button ~= nil and same_object(folder_ui_state.button, button) then
        set_folder_icon_color(
            hovered and FOLDER_ICON_COLOR_HOVER or FOLDER_ICON_COLOR_NORMAL,
            hovered and "hover" or "normal"
        )
        return
    end
    local info = (folder_ui_state.moveRowActions and folder_ui_state.moveRowActions[identity])
        or (folder_ui_state.moveButtons and folder_ui_state.moveButtons[identity])
        or (folder_ui_state.renameButtons and folder_ui_state.renameButtons[identity])
        or (folder_ui_state.deleteButtons and folder_ui_state.deleteButtons[identity])
    if info == nil then return end
    if info.button ~= nil and not same_object(info.button, button) then return end
    if info.row ~= nil and not same_object(info.row, button) then return end
    local canvas = unwrap(info.iconCanvas)
    if canvas == nil then return end
    set_icon_canvas_color(canvas, hovered and FOLDER_ICON_COLOR_HOVER or FOLDER_ICON_COLOR_NORMAL)
    info.visualState = hovered and "hover" or "normal"
end

local function install_action_hover_hooks()
    if action_hover_hooks_registered then return true end
    local ok_hover, hover_id = pcall(function()
        return RegisterHook("/Script/CommonUI.CommonButtonBase:BP_OnHovered", function(context, ...)
            set_registered_action_icon_state(context, true)
        end)
    end)
    local ok_unhover, unhover_id = pcall(function()
        return RegisterHook("/Script/CommonUI.CommonButtonBase:BP_OnUnhovered", function(context, ...)
            set_registered_action_icon_state(context, false)
        end)
    end)
    if ok_hover and hover_id ~= nil and ok_unhover and unhover_id ~= nil then
        action_hover_hooks_registered = true
        log("Registered event-driven hover tint hooks for Databank action icons.")
        return true
    end
    log("Databank action hover hook unavailable: hover=" .. tostring(hover_id)
        .. " unhover=" .. tostring(unhover_id))
    return false
end

local function ensure_create_folder_control(page)
    if page == nil then return false end
    page = unwrap(page)
    folder_ui_state.page = page
    local page_id = object_name(page)
    if folder_ui_state.pageIdentity ~= page_id then
        folder_ui_state.pageIdentity = page_id
        folder_ui_state.row = nil
        folder_ui_state.button = nil
        folder_ui_state.buttons = {}
        folder_ui_state.iconCanvas = nil
        folder_ui_state.iconOverlay = nil
        folder_ui_state.iconVisualState = nil
        folder_ui_state.moveButtons = {}
        folder_ui_state.moveRowActions = {}
        folder_ui_state.moveDestinationButtons = {}
        folder_ui_state.moveClickScheduled = false
    end

    if folder_ui_state.button ~= nil then
        local parent = select(1, try_call(function() return unwrap(folder_ui_state.button:GetParent()) end))
        if parent ~= nil then return true end
    end

    local adopted = find_tree_widget(page, CREATE_FOLDER_BUTTON_MARKER)
    if adopted ~= nil then
        register_folder_button(adopted)
        folder_ui_state.row = select(1, try_call(function() return unwrap(adopted:GetParent()) end))
        return true
    end

    local create_new = select(1, read_property(page, "WBP_CharacterBankCreateNewBtn"))
    if create_new == nil then create_new = find_tree_widget(page, "WBP_CharacterBankCreateNewBtn_C") end
    if create_new == nil then log("Create Folder UI pending: native Create New widget unavailable"); return false end
    local parent = select(1, try_call(function() return unwrap(create_new:GetParent()) end))
    if parent == nil then log("Create Folder UI pending: native Create New parent unavailable"); return false end
    local create_index = panel_child_index(parent, create_new)
    if create_index < 0 then return false end
    local create_layout = capture_box_slot_layout(create_new)

    local icon_button, clone_err = clone_widget_like(page, create_new, CREATE_FOLDER_BUTTON_MARKER)
    if icon_button == nil then log("Create Folder clone failed: " .. tostring(clone_err)); return false end

    -- Character Share may already have replaced the native Create New slot
    -- with its cooperative action row. Join that flat row rather than nesting
    -- another HorizontalBox inside its Create New SizeBox. This keeps the
    -- result at Create New | Import | Create Folder regardless of load order.
    local character_share_row = find_tree_widget(page, "CharacterShare_CreateImportRow")
    local character_share_create_wrapper = find_tree_widget(page, "CharacterShare_CreateNewWidth")
    if character_share_create_wrapper == nil then
        -- Compatibility with Character Share 1.0.1's old half-width wrapper.
        character_share_create_wrapper = find_tree_widget(page, "CharacterShare_CreateNewHalf")
    end
    if character_share_row ~= nil and character_share_create_wrapper ~= nil
        and panel_child_index(character_share_row, character_share_create_wrapper) >= 0 then
        local wrapper_width = widget_local_width(character_share_create_wrapper)
        if wrapper_width == nil or wrapper_width < 120.0 then wrapper_width = 628.0 end
        local resized_width = math.max(120.0,
            wrapper_width - CREATE_FOLDER_ICON_WIDTH - CREATE_FOLDER_GAP)
        pcall(function() character_share_create_wrapper:SetWidthOverride(resized_width) end)

        local icon_overlay, overlay_err = make_create_folder_icon_overlay(page, icon_button)
        local icon_wrapper = nil
        if icon_overlay ~= nil then
            icon_wrapper = select(1, make_width_wrapper(page, icon_overlay,
                "EnhancedDatabank_CreateFolderWidth", CREATE_FOLDER_ICON_WIDTH))
        end
        if icon_wrapper == nil then
            log("Create Folder could not join Character Share row: " .. tostring(overlay_err))
            return false
        end

        local icon_slot = select(1, try_call(function()
            return unwrap(character_share_row:AddChild(icon_wrapper))
        end))
        if icon_slot == nil then
            log("Create Folder could not append to Character Share row")
            return false
        end
        configure_row_slot(icon_slot, CREATE_FOLDER_GAP)

        register_folder_button(icon_button)
        folder_ui_state.row = character_share_row
        style_create_folder_icon_button(page, icon_button)
        set_folder_icon_color(FOLDER_ICON_COLOR_NORMAL, "normal")
        run_on_game_thread_after(80, function()
            if same_object(folder_ui_state.button, icon_button) then
                style_create_folder_icon_button(page, icon_button)
            end
        end)
        log(string.format(
            "Create Folder joined Character Share action row: previousCreateWidth=%.1f createWidth=%.1f iconWidth=%.1f",
            wrapper_width, resized_width, CREATE_FOLDER_ICON_WIDTH))
        return true
    end

    local row, row_err = construct_widget(page, "/Script/UMG.HorizontalBox", CREATE_FOLDER_ROW_MARKER)
    if row == nil then log("Create Folder row failed: " .. tostring(row_err)); return false end

    local original_width = widget_local_width(create_new)
    if original_width == nil or original_width < 200.0 then original_width = 700.0 end
    local create_width = math.max(120.0, original_width - CREATE_FOLDER_ICON_WIDTH - CREATE_FOLDER_GAP)

    local removed = select(1, try_call(function() return parent:RemoveChild(create_new) end))
    if removed ~= true then log("Create Folder UI could not detach Create New safely"); return false end

    local create_wrapper = select(1, make_width_wrapper(page, create_new, "EnhancedDatabank_CreateNewWidth", create_width))
    local icon_overlay, overlay_err = make_create_folder_icon_overlay(page, icon_button)
    local icon_wrapper = nil
    if icon_overlay ~= nil then
        icon_wrapper = select(1, make_width_wrapper(page, icon_overlay,
            "EnhancedDatabank_CreateFolderWidth", CREATE_FOLDER_ICON_WIDTH))
    end
    if create_wrapper == nil or icon_wrapper == nil then
        pcall(function() parent:AddChild(create_new) end)
        log("Create Folder width/icon overlay failed; Create New restored: " .. tostring(overlay_err))
        return false
    end
    local create_slot = select(1, try_call(function() return unwrap(row:AddChild(create_wrapper)) end))
    local icon_slot = select(1, try_call(function() return unwrap(row:AddChild(icon_wrapper)) end))
    if create_slot == nil or icon_slot == nil then return false end
    configure_row_slot(create_slot, 0.0)
    configure_row_slot(icon_slot, CREATE_FOLDER_GAP)

    local row_slot, add_err = try_call(function() return unwrap(parent:AddChild(row)) end)
    if add_err ~= nil or row_slot == nil then log("Create Folder row attach failed: " .. tostring(add_err)); return false end
    apply_box_slot_layout(row_slot, create_layout)
    local moved, move_err = visually_move_appended_child_to_index(parent, row, create_index, "vertical")
    if not moved then log("Create Folder row visual ordering failed: " .. tostring(move_err)) end

    register_folder_button(icon_button)
    folder_ui_state.row = row
    style_create_folder_icon_button(page, icon_button)
    set_folder_icon_color(FOLDER_ICON_COLOR_NORMAL, "normal")
    run_on_game_thread_after(80, function()
        if same_object(folder_ui_state.button, icon_button) then style_create_folder_icon_button(page, icon_button) end
    end)
    log(string.format("Create Folder icon installed beside Create New: originalWidth=%.1f createWidth=%.1f iconWidth=%.1f",
        original_width, create_width, CREATE_FOLDER_ICON_WIDTH))
    return true
end

install_folder_button_click_hook()
install_action_hover_hooks()

-- Folder management uses explicit per-folder edit/delete buttons; no hidden gestures.

local refresh_in_progress = false
local refresh_generation = 0
local refresh_again = false
local refresh_action_handle = MakeActionHandle()

local function resolve_live_humanoid_page()
    local master = find_first("WBP_CharacterBank_Master_C")
    local databank_vm = find_first("BrunoCharacterDatabankViewModel")
    if not uobject_is_valid(master) or not uobject_is_valid(databank_vm) then
        return nil, nil, "Databank master/viewmodel unavailable"
    end
    local page = select(1, read_property(master, "OtherCharacterList"))
    if not uobject_is_valid(page) then return nil, nil, "OtherCharacterList unavailable" end
    local stock_widget = select(1, read_property(page, "CharacterPool"))
    local scroll = select(1, read_property(page, "BitReactorScrollBox_0"))
    local default_vm = select(1, read_property(databank_vm, "DefaultCustomCharacterPoolViewModel"))
    if not uobject_is_valid(stock_widget) or not uobject_is_valid(scroll)
        or not uobject_is_valid(default_vm) then
        return nil, nil, "humanoid Databank widget tree/viewmodels not ready"
    end
    -- Return the objects already resolved during the readiness check. Re-reading
    -- these reflected properties later in the same cold-activation callback was
    -- a repeatable UE4SS access-violation boundary.
    return page, databank_vm, nil, stock_widget, default_vm, scroll
end

local schedule_refresh

local function schedule_default_pool_reconciliation(expected_page_identity)
    -- An earlier approach still crashed after four compact stock-row visuals had been
    -- installed. Do not inspect, decorate, or retain any shipping character row
    -- in the stability baseline. The native Default pool remains wholly owned by
    -- the game.
    log("Default Custom untouched: stock row reconciliation/decoration disabled for stability; page="
        .. tostring(expected_page_identity))
end

local function refresh_visible_pools(reason)
    if refresh_in_progress then
        refresh_again = true
        log("Refresh already in progress; coalescing request: " .. tostring(reason))
        return
    end
    refresh_in_progress = true
    section("AUTO DATABANK POOL RENDER")
    log("reason=" .. tostring(reason))

    local page, databank_vm, state_err, stock_widget, default_vm, scroll =
        resolve_live_humanoid_page()
    if page == nil or databank_vm == nil then
        log("NO-OP: " .. tostring(state_err))
        refresh_in_progress = false
        return
    end

    ensure_create_folder_control(page)

    local authority, auth_err = authoritative_pool_state()
    if authority == nil then
        log("ABORT: " .. tostring(auth_err))
        refresh_in_progress = false
        return
    end

    log("Authoritative Default Custom characters=" .. tostring(authority.default_custom.count))
    log("Authoritative player-created custom pools=" .. tostring(#authority.custom_order))
    for _, name in ipairs(authority.custom_order) do
        local entry = authority.custom_by_name[name]
        log("  pool='" .. tostring(name) .. "' characters=" .. tostring(entry and entry.count or 0))
    end

    local extra_vms = collect_extra_pool_vms(databank_vm, authority)

    -- ViewModel arrays may lag or remain stale after a manager mutation. Record
    -- one diagnostic snapshot, then render once from pool-local typed entries.
        -- An earlier implementation retried this entire native widget rebuild every 100 ms; when the
    -- destination VM never converged, nine rapid passes produced both log spam
    -- and a repeatable UE4SS GameThread access violation.
    local pending = folder_ui_state.pendingMove
    if pending ~= nil then
        local default_vm_for_move = default_vm
        local function vm_for_pool_name(pool_name_value)
            if tostring(pool_name_value or "") == tostring(authority.default_custom.name or "") then
                return default_vm_for_move
            end
            return extra_vms[tostring(pool_name_value or "")]
        end

        local source_vm = vm_for_pool_name(pending.sourcePoolName)
        local target_vm = vm_for_pool_name(pending.targetPoolName)
        local source_has = source_vm ~= nil and pool_vm_contains_guid(source_vm, pending.guid) or false
        local target_has = target_vm ~= nil and pool_vm_contains_guid(target_vm, pending.guid) or false
        if source_has or not target_has then
            log("Move Character VM ownership incomplete after native move: guid="
                .. tostring(pending.guid) .. " sourceHas=" .. tostring(source_has)
                .. " targetHas=" .. tostring(target_has)
                .. "; no automatic retry/rebuild will run")
        else
            log("Move Character Databank VM ownership converged: guid=" .. tostring(pending.guid)
                .. " source='" .. tostring(pending.sourcePoolName)
                .. "' target='" .. tostring(pending.targetPoolName) .. "'")
            folder_ui_state.pendingMove = nil
        end
        folder_ui_state.pendingMove = nil
    end

    local global_index = collect_raw_vm_index(databank_vm, extra_vms)
    local removed = remove_dynamic_pool_widgets(page)
    folder_ui_state.renameButtons = {}
    folder_ui_state.deleteButtons = {}
    folder_ui_state.moveButtons = {}
    folder_ui_state.moveRowActions = {}
    folder_ui_state.moveDestinationButtons = {}
    folder_ui_state.renderedPools = {}
    default_move_decor_generation = default_move_decor_generation + 1
    log("Removed prior dynamic pool widgets=" .. tostring(removed))

    -- The shipping Default Custom widget is already bound and populated by the
    -- game. Preserve it, and defer even its read-only reconciliation until the
            -- current activation callback has unwound. Deferring per-row widget
    -- construction but still re-read DefaultCustomCharacterPoolViewModel here;
    -- two cold-entry runs crashed at that exact UE4SS/native boundary.
    schedule_default_pool_reconciliation(object_name(page))

    if scroll == nil then
        log("ABORT: BitReactorScrollBox_0 unavailable")
        refresh_in_progress = false
        return
    end

    local rendered = 0
    for _, name in ipairs(authority.custom_order) do
        local entry = authority.custom_by_name[name]
        local pool_vm = extra_vms[name]
        if pool_vm == nil then
            log("Cannot render authoritative pool '" .. tostring(name) .. "': matching BrunoCharacterPoolViewModel unavailable")
        else
            local widget, create_err = create_pool_widget(page)
            if widget == nil then
                log("Create widget failed for '" .. tostring(name) .. "': " .. tostring(create_err))
            else
                local slot, add_err = try_call(function() return unwrap(scroll:AddChild(widget)) end)
                if add_err ~= nil or slot == nil then
                    log("Attach failed for '" .. tostring(name) .. "': " .. tostring(add_err))
                    pcall(function() widget:RemoveFromParent() end)
                else
                    pcall(function() widget.HideIfEmpty = false end)
                    local bind_ok, bind_err = bind_pool_widget(widget, pool_vm)
                    if not bind_ok then log("SetViewModel failed for '" .. tostring(name) .. "': " .. tostring(bind_err)) end
                    local title_ok, title_err = apply_pool_title(widget, pool_vm)
                    if not title_ok then
                        log("Title presentation failed for '" .. tostring(name) .. "': " .. tostring(title_err))
                    else
                        local folder_header = select(1, read_property(widget, "WBP_CharacterBank_PoolName"))
                        local rename_ok, rename_err = install_rename_button_on_folder(
                            page, widget, folder_header, pool_vm, name, rendered + 1,
                            entry and entry.count or 0)
                        if not rename_ok then
                            log("Folder action button install failed for '" .. tostring(name) .. "': " .. tostring(rename_err))
                        end
                    end
                    local rows = rows_for_authority(pool_vm, entry, global_index)
                    local rows_ok, rows_err = invoke_pool_rows(widget, rows, "Extra pool '" .. tostring(name) .. "'")
                    if not rows_ok then
                        log("Row population failed for '" .. tostring(name) .. "': " .. tostring(rows_err))
                    else
                        -- Keep only a pool-level record of the exact typed rows
                        -- supplied to this widget. MOVE consumes it on click to
                        -- translate the selected row position back to its VM;
                        -- rendering still does not inspect or retain row widgets.
                        table.insert(folder_ui_state.renderedPools, {
                            widget = widget,
                            rows = rows,
                            entry = entry,
                            name = tostring(name),
                        })
                        -- Do not replay generated row-created/ViewModelChanged
                        -- handlers here. Their MDViewModel binding never matched
            -- the expected pool in diagnostics, and the related crash
                        -- dumps end in the same UE4SS GameThread stack while this
                        -- per-row bridge was being repeated. Native selection is
                        -- already supplied by invoke_pool_rows().
                        log("Extra pool row-context replay disabled for stability: pool='"
                            .. tostring(name) .. "' rows=" .. tostring(#rows))
                        log("Move Character row decoration disabled for stability: pool='"
                            .. tostring(name) .. "' rows=" .. tostring(#rows))
                    end
                    rendered = rendered + 1
                end
            end
        end
    end

    local move_button_ok, move_button_err = require("selected_move_button").ensure(page, {
        unwrap = unwrap,
        objectName = object_name,
        className = class_name,
        tryCall = try_call,
        readProperty = read_property,
        panelChildCount = panel_child_count,
        panelChildAt = panel_child_at,
        findTreeWidget = find_tree_widget,
        cloneWidgetLike = clone_widget_like,
        constructWidget = construct_widget,
        captureSlotLayout = capture_box_slot_layout,
        applySlotLayout = apply_box_slot_layout,
        register = function(button)
            folder_ui_state.moveButtons[object_name(button)] = {
                button = button,
                selectedDetail = true,
            }
        end,
        log = log,
    })
    if not move_button_ok then
        log("Selected-character Move button pending: " .. tostring(move_button_err))
    end

    install_action_hover_hooks()
    log("AUTO RENDER COMPLETE: scroll children=" .. tostring(panel_child_count(scroll))
        .. " | extra rendered=" .. tostring(rendered))
    section("END AUTO DATABANK POOL RENDER")
    refresh_in_progress = false

    if refresh_again then
        refresh_again = false
        schedule_refresh("coalesced follow-up", 80)
    end
end

schedule_refresh = function(reason, delay_ms)
    -- Lifecycle hooks can finish installing while an activation-triggered render
    -- is already running. Coalesce immediately instead of arming another timer
    -- that may fire while the current renderer is inside a native Blueprint call.
    if refresh_in_progress then
        refresh_again = true
        log("Refresh requested during active render; coalescing: " .. tostring(reason))
        return
    end

    refresh_generation = refresh_generation + 1
    local generation = refresh_generation
    RetriggerableExecuteInGameThreadWithDelay(refresh_action_handle, delay_ms or 100, function()
        if generation ~= refresh_generation then return end
        refresh_visible_pools(reason)
    end)
end

local function restore_stock_only()
    section("AUTO UI CLEANUP")
    local page, databank_vm, err = resolve_live_humanoid_page()
    if page == nil or databank_vm == nil then log("NO-OP: " .. tostring(err)); return end
    log("Removed dynamic pool widgets=" .. tostring(remove_dynamic_pool_widgets(page)))

    -- Do not manually replay the shipping Default pool's generated row handler.
    -- The game owns that widget and keeps it synchronized with its ViewModel;
    -- forcing a second regeneration causes a cold-entry crash.
    folder_ui_state.moveRowActions = {}
    folder_ui_state.moveClickScheduled = false
    log("Stock Default pool left untouched; native game binding remains authoritative.")
    section("END AUTO UI CLEANUP")
end

local function page_is_humanoid(page)
    page = unwrap(page)
    if page == nil then return false end
    local identity = object_name(page)
    return string.find(identity, "OtherCharacterList", 1, true) ~= nil
end

-- The CharacterBank Blueprint packages are not necessarily loaded when UE4SS
-- starts on a cold game launch. RegisterHook cannot hook a Blueprint UFunction
-- before that UFunction exists, so install these lifecycle hooks lazily once the
-- cooked CharacterBank functions appear. This is intentionally a lightweight
-- object-existence poll and shuts itself off once both hooks are installed.
decorate_current_character_rows = function(reason)
    log("Move Character row rescan suppressed for stability: reason=" .. tostring(reason))
    return false
end

local MASTER_ACTIVATED_PATH = "/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/WBP_CharacterBank_Master.WBP_CharacterBank_Master_C:BP_OnActivated"
local PAGE_ACTIVATED_PATH = "/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/WBP_CharacterBank_Page_CharacterList.WBP_CharacterBank_Page_CharacterList_C:BP_OnActivated"
local CHARACTER_CLICKED_PATH = "/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/WBP_CharacterBank_CreatedCharacterItem.WBP_CharacterBank_CreatedCharacterItem_C:BP_OnClicked"
local FOLDER_CLICKED_PATH = "/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/WBP_CharacterBank_CreatedCharacterFolder.WBP_CharacterBank_CreatedCharacterFolder_C:BP_OnClicked"

local master_hook_installed = false
local page_hook_installed = false
-- The release exposes no per-row Move controls, so their click/rescan hooks are
-- intentionally treated as satisfied and are never registered.
local character_click_hook_installed = true
local folder_click_hook_installed = true
local lifecycle_retry_active = true
local lifecycle_retry_count = 0

local function live_master_available()
    local master = find_first("WBP_CharacterBank_Master_C")
    if master == nil then return false end
    local identity = object_name(master)
    return string.find(identity, "/Engine/Transient", 1, true) ~= nil
end

local function live_humanoid_page_available()
    local master = find_first("WBP_CharacterBank_Master_C")
    if master == nil then return false end
    local page = select(1, read_property(master, "OtherCharacterList"))
    if page == nil then return false end
    return page_is_humanoid(page)
end

local function install_master_activation_hook()
    if master_hook_installed then return true, nil end
    -- RegisterHook on a not-yet-loaded Blueprint UFunction causes UE4SS to print
    -- a full exception/stack trace even when pcall catches it. Avoid calling it
    -- at all until a live CharacterBank master exists; by then the generated
    -- Blueprint class/UFunction is resident and hook registration is safe.
    if not live_master_available() then
        return false, "live master not loaded"
    end

    local ok, hook_id = pcall(function()
        return RegisterHook(MASTER_ACTIVATED_PATH, function(context, ...)
            local master = unwrap(context)
            local identity = object_name(master)
            if string.find(identity, "/Engine/Transient", 1, true) then
                log("Character Databank master activated; scheduling authoritative UI rebuild.")
                schedule_refresh("Databank master BP_OnActivated", 140)
            end
        end)
    end)

    if ok and hook_id ~= nil then
        master_hook_installed = true
        log("Hooked Character Databank master BP_OnActivated (lazy-safe installer).")
        return true, nil
    end
    return false, tostring(hook_id)
end

local function install_page_activation_hook()
    if page_hook_installed then return true, nil end
    -- Same rationale as the master hook: require the live humanoid page before
    -- asking UE4SS to register the Blueprint override hook. This keeps cold-start
    -- lazy installation silent instead of generating an expected stack trace.
    if not live_humanoid_page_available() then
        return false, "live humanoid page not loaded"
    end

    local ok, hook_id = pcall(function()
        return RegisterHook(PAGE_ACTIVATED_PATH, function(context, ...)
            local page = unwrap(context)
            if page_is_humanoid(page) then
                log("Humanoid Character Databank page BP_OnActivated; scheduling authoritative UI rebuild.")
                schedule_refresh("humanoid page BP_OnActivated", 120)
            end
        end)
    end)

    if ok and hook_id ~= nil then
        page_hook_installed = true
        log("Hooked humanoid page BP_OnActivated (lazy-safe installer).")
        return true, nil
    end
    return false, tostring(hook_id)
end

local function live_pool_item_available()
    local page, databank_vm = resolve_live_humanoid_page()
    if page == nil or databank_vm == nil then return false end
    local stock_widget = select(1, read_property(page, "CharacterPool"))
    return stock_widget ~= nil
end

local function live_character_row_available()
    local page = select(1, resolve_live_humanoid_page())
    if page == nil then return false end
    local stock_widget = select(1, read_property(page, "CharacterPool"))
    if stock_widget == nil then return false end
    local stack = select(1, read_property(stock_widget, "BitReactorStackBox_25"))
    return panel_child_at(stack, 0) ~= nil
end

local function install_character_clicked_hook()
    if character_click_hook_installed then return true, nil end
    if not live_character_row_available() then
        return false, "live Character row not loaded"
    end
    local ok, hook_id = pcall(function()
        return RegisterHook(CHARACTER_CLICKED_PATH, function(context, ...)
            local row = unwrap(context)
            if row == nil then return end
            local info = folder_ui_state.moveRowActions
                and folder_ui_state.moveRowActions[object_name(row)] or nil
            if info == nil then return end

            -- The transfer affordance is intentionally a lightweight row-owned
            -- hit zone instead of a nested CommonUI UserWidget. This avoids the
                    -- 20+ Blueprint button constructions that previously crashed while still
            -- letting every row show its action persistently.
            local over_transfer = false
            local hitbox = unwrap(info.hitbox)
            if hitbox ~= nil then
                pcall(function() over_transfer = hitbox:IsHovered() == true end)
            end
            if not over_transfer then return end

            schedule_move_character_dialog(info, "row BP_OnClicked fallback")
        end)
    end)
    if ok and hook_id ~= nil then
        character_click_hook_installed = true
        log("Hooked Character Databank row BP_OnClicked for lightweight transfer hit-zones.")
        return true, nil
    end
    return false, tostring(hook_id)
end

local function install_folder_clicked_hook()
    if folder_click_hook_installed then return true, nil end
    if not live_pool_item_available() then
        return false, "live Character Pool widget not loaded"
    end
    local ok, hook_id = pcall(function()
        return RegisterHook(FOLDER_CLICKED_PATH, function(context, ...)
            -- Re-scan only after the native collapse/expand click has unwound.
            -- This does not rebuild folders or rows; it merely decorates any row
            -- UObjects the native folder regenerated while expanding.
            run_on_game_thread_after(80, function()
                if decorate_current_character_rows ~= nil then
                    decorate_current_character_rows("folder expand/collapse")
                end
            end)
        end)
    end)
    if ok and hook_id ~= nil then
        folder_click_hook_installed = true
        log("Hooked Character Databank folder BP_OnClicked for post-expand transfer decoration.")
        return true, nil
    end
    return false, tostring(hook_id)
end

local attempt_install_databank_lifecycle_hooks
attempt_install_databank_lifecycle_hooks = function(reason)
    if not lifecycle_retry_active then return end
    lifecycle_retry_count = lifecycle_retry_count + 1

    local had_master = master_hook_installed
    local had_page = page_hook_installed
    local had_character_click = character_click_hook_installed
    local had_folder_click = folder_click_hook_installed
    local master_ok, master_err = install_master_activation_hook()
    local page_ok, page_err = install_page_activation_hook()
    local character_ok, character_err = install_character_clicked_hook()
    local folder_ok, folder_err = install_folder_clicked_hook()

    if lifecycle_retry_count == 1 then
        if not master_ok then log("Master BP_OnActivated deferred: " .. tostring(master_err)) end
        if not page_ok then log("Page BP_OnActivated deferred: " .. tostring(page_err)) end
        if not character_ok then log("Character row click hook deferred: " .. tostring(character_err)) end
        if not folder_ok then log("Folder click hook deferred: " .. tostring(folder_err)) end
    end

    local installed_now = (not had_master and master_hook_installed)
        or (not had_page and page_hook_installed)
        or (not had_character_click and character_click_hook_installed)
        or (not had_folder_click and folder_click_hook_installed)

    if installed_now then
        log("Databank lifecycle hook(s) became available during " .. tostring(reason)
            .. "; waiting for a fully initialized live Databank page before catch-up render.")
        local catchup_attempts = 0
        local function try_catchup()
            catchup_attempts = catchup_attempts + 1
            -- If BP_OnActivated or the native CommonUI fallback already queued a
            -- render, a second catch-up pass would destroy/recreate every custom
            -- pool immediately after the first. Earlier logs showed exactly that
            -- duplicate cold-entry render. Let the activation-owned request win.
            if refresh_generation > 0 then
                log("Late-hook catch-up suppressed: activation render already scheduled.")
                return
            end
            local page, databank_vm = resolve_live_humanoid_page()
            if page ~= nil and databank_vm ~= nil then
                local stock_widget = select(1, read_property(page, "CharacterPool"))
                local stock_stack = stock_widget and select(1, read_property(stock_widget, "BitReactorStackBox_25")) or nil
                local stock_children = panel_child_count(stock_stack)
                local authority = authoritative_pool_state()
                local extra_vms = authority and collect_extra_pool_vms(databank_vm, authority) or nil
                local custom_ready = true
                if authority and extra_vms then
                    for _, pool_name_value in ipairs(authority.custom_order or {}) do
                        if extra_vms[pool_name_value] == nil then custom_ready = false; break end
                    end
                end

                -- On a cold load the page UObject can exist before its stock
                -- CharacterPool has finished native/MDViewModel initialization.
                -- Wait until stock rows exist and all authoritative custom pool
                -- VMs are discoverable before the first catch-up render.
                if stock_stack ~= nil and stock_children ~= nil and stock_children > 0
                    and authority ~= nil and custom_ready then
                    log("Late-hook catch-up page ready after " .. tostring(catchup_attempts)
                        .. " attempt(s); stockRows=" .. tostring(stock_children)
                        .. "; scheduling authoritative render.")
                    schedule_refresh("late lifecycle hook install", 120)
                    return
                end
            end
            if catchup_attempts < 20 then
                run_on_game_thread_after(100, try_catchup)
            else
                log("Late-hook catch-up skipped: live Databank page was not fully initialized; normal BP_OnActivated hook will render on entry.")
            end
        end
        run_on_game_thread_after(100, try_catchup)
    end

    if master_hook_installed and page_hook_installed and character_click_hook_installed and folder_click_hook_installed then
        lifecycle_retry_active = false
        log("Databank lifecycle hooks fully installed after " .. tostring(lifecycle_retry_count)
            .. " attempt(s); stopping late-hook retry loop.")
        return
    end

    run_on_game_thread_after(400, function()
        if lifecycle_retry_active then
            attempt_install_databank_lifecycle_hooks("deferred Blueprint load")
        end
    end)
end

attempt_install_databank_lifecycle_hooks("initial mod load")

-- Native CommonUI activation is the fallback that should fire even when a
-- Blueprint override is skipped/reused. Filter immediately to the actual live
-- humanoid Character Databank page before doing any Databank work.
local common_hook_ok, common_pre_id, common_post_id = pcall(function()
    return RegisterHook(
        "/Script/CommonUI.CommonActivatableWidget:ActivateWidget",
        function(context, ...) end,
        function(context, ...)
            local widget = unwrap(context)
            if page_is_humanoid(widget) then
                log("Native CommonUI ActivateWidget observed for humanoid Databank page; scheduling authoritative UI rebuild.")
                schedule_refresh("native CommonUI ActivateWidget", 120)
            end
        end
    )
end)
if common_hook_ok and common_pre_id ~= nil then
    log("Hooked native CommonUI ActivateWidget fallback.")
else
    log("CommonUI ActivateWidget hook unavailable: " .. tostring(common_pre_id))
end

local function hook_native_refresh(path, label)
    local ok, pre_id, post_id = pcall(function()
        return RegisterHook(path,
            function(context, ...) end,
            function(context, ...)
                log(label .. " completed; scheduling authoritative UI rebuild.")
                schedule_refresh(label, 120)
            end)
    end)
    if ok and pre_id ~= nil then
        log("Hooked native refresh source: " .. label)
    else
        log("Native refresh hook unavailable for " .. label .. ": " .. tostring(pre_id))
    end
end

-- Databank-VM mutations still matter for stock game / Character Share paths.
hook_native_refresh("/Script/Bruno.BrunoCharacterDatabankViewModel:CreatePool", "DatabankVM.CreatePool")
hook_native_refresh("/Script/Bruno.BrunoCharacterDatabankViewModel:RenamePool", "DatabankVM.RenamePool")
hook_native_refresh("/Script/Bruno.BrunoCharacterDatabankViewModel:DeletePool", "DatabankVM.DeletePool")
hook_native_refresh("/Script/Bruno.BrunoCharacterDatabankViewModel:MovePoolCharacterToPool", "DatabankVM.MovePoolCharacterToPool")

-- Both mutation surfaces remain observable for stock game paths and other mods.
-- Enhanced Databank uses the manager-direct move that proved stable, then
-- performs only a one-row visibility correction if the Default VM stays stale.
hook_native_refresh("/Script/BitReactorGame.BitReactorCharacterPoolManager:MoveCharacterToAnotherPool", "PoolManager.MoveCharacterToAnotherPool")
hook_native_refresh("/Script/BitReactorGame.BitReactorCharacterPoolManager:RenamePlayerCreatedCharacterPool", "PoolManager.RenamePlayerCreatedCharacterPool")
hook_native_refresh("/Script/BitReactorGame.BitReactorCharacterPoolManager:DeletePlayerCreatedCharacterPool", "PoolManager.DeletePlayerCreatedCharacterPool")

log("Loaded v" .. VERSION .. ". Deferred work uses UE4SS owned delayed game-thread actions, including a retriggerable refresh handle; no legacy async timers or hover polling remain. MOVE uses the stable manager-direct native mutation and performs at most one targeted Default-row visibility correction. Custom pools render once per native mutation: no ViewModel convergence retry loop and no generated per-row context replay. The selected-row lookup remains click-only; no per-character widgets or manual save writes.")
log("On Databank activation and native pool mutations it rebuilds visible folders from authoritative CharacterPoolManager ownership.")
if LOG_PATH then log("Dedicated log: " .. LOG_PATH) end
if source_resolution_note then log(source_resolution_note) end

require("debug_keybinds").install({
    log = log,
    refresh = function()
        run_on_game_thread_after(0, function() refresh_visible_pools("manual Shift+F7") end)
    end,
    restore = function()
        run_on_game_thread_after(0, restore_stock_only)
    end,
})
