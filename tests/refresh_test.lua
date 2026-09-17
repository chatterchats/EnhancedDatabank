-- Run: luajit tests/refresh_test.lua "src/Enhanced Databank/Scripts"
local scripts = assert(arg[1])
local queue, handles, calls = {}, 0, {}
function MakeActionHandle() handles = handles + 1; return handles end
function RetriggerableExecuteInGameThreadWithDelay(handle, delay, callback)
    -- Match UE4SS: the callback is NOT replaced on retrigger.
    queue[handle] = queue[handle] or { callback = callback }
    queue[handle].delay = delay
end
local runtime = { alive = true, actions = {} }
function runtime:track_action(handle) self.actions[handle] = true end
function runtime:finish_action(handle) self.actions[handle] = nil end
local ctx = { databank_ui = {}, runtime = runtime }
assert(loadfile(scripts .. "/databank_ui.lua"))()(ctx)
ctx.databank_ui.refresh_visible_pools = function(reason) calls[#calls + 1] = reason end
local function flush()
    local pending = queue
    queue = {}
    for _, action in pairs(pending) do action.callback() end
end
ctx.databank_ui.schedule_refresh("single move", 120)
flush()
assert(#calls == 1 and calls[1] == "single move")
ctx.databank_ui.schedule_refresh("master activation", 100)
local first_callback = queue[1].callback
ctx.databank_ui.schedule_refresh("page activation", 120)
assert(queue[1].callback == first_callback and queue[1].delay == 120)
flush()
assert(#calls == 2 and calls[2] == "page activation", "coalesced refresh was lost")
for i = 1, 10 do ctx.databank_ui.schedule_refresh("burst " .. i, 80) end
flush()
assert(#calls == 3 and calls[3] == "burst 10")
assert(handles == 1 and next(runtime.actions) == nil)
ctx.databank_ui.schedule_refresh("retired", 120)
runtime.alive = false
flush()
assert(#calls == 3, "retired runtime rendered")

-- A rebuild filters stale typed rows using the manager's current GUID set.
ctx.common = {
    array_each = function(array, callback)
        for i, value in ipairs(array or {}) do callback(i, value) end
    end,
    read_property = function(value, name) return value[name] end,
    unwrap = function(value) return value end,
    uobject_is_valid = function(value) return value ~= nil and value.valid ~= false end,
    panel_child_at = function(panel, index) return panel[index + 1] end,
    panel_child_count = function(panel) return #panel end,
    text_value = function(value) return tostring(value or "") end,
    try_call = function(callback)
        local ok, value = pcall(callback)
        if ok then return value end
        return nil, value
    end,
}
ctx.pool_authority = {}
assert(loadfile(scripts .. "/pool_authority.lua"))()(ctx)
local function character(id, name)
    return { name = name, PoolCharacterData = { PoolCharacterID = { A = id, B = 0, C = 0, D = 1 } } }
end
local kept, removed = character(1, "Kept"), character(2, "Removed")
local vm = { PoolCharacterViewModels = { kept, removed } }
local key = ctx.pool_authority.character_guid_string(kept)
local rows = ctx.pool_authority.rows_for_authority(vm, { guids = { [key] = true }, guid_order = { key } }, {})
assert(#rows == 1 and rows[1] == kept, "deleted character survived authority filtering")
rows = ctx.pool_authority.rows_for_authority(vm, { guids = {}, guid_order = {} }, {})
assert(#rows == 0, "deleting the last character must leave no custom rows")

-- The shipping Default pool may retain and re-show stale VM rows. Reconcile
-- only visibility; never regenerate, remove, or retain the stock row widgets.
ctx.state = { folder_ui_state = { hiddenDefaultRows = {} } }
ctx.logging = { log = function() end }
ctx.pool_authority.character_display_name = function(value) return value.name end
local function row(name, visibility)
    return {
        BitReactorRichTextBlock_73 = { GetText = function() return name end },
        visibility = visibility,
        GetVisibility = function(self) return self.visibility end,
        SetVisibility = function(self, value)
            self.visibility = value
            self.writes = (self.writes or 0) + 1
        end,
    }
end
local kept_row, stale_row = row("Kept", 0), row("Removed", 0)
local stock = { BitReactorStackBox_25 = { kept_row, stale_row } }
local ok = ctx.databank_ui.reconcile_default_row_visibility(
    vm, stock, { guids = { [key] = true }, count = 1 }, "delete")
assert(ok and kept_row.visibility == 0 and kept_row.writes == nil)
assert(stale_row.visibility == 1 and stale_row.writes == 1)
local stale_key = ctx.pool_authority.character_guid_string(removed)
assert(ctx.state.folder_ui_state.hiddenDefaultRows[stale_key])
ctx.databank_ui.reconcile_default_row_visibility(
    vm, stock, { guids = { [key] = true }, count = 1 }, "activation")
assert(stale_row.writes == 1, "an already-hidden stale row was rewritten")
ctx.databank_ui.reconcile_default_row_visibility(
    vm, stock, { guids = { [key] = true, [stale_key] = true }, count = 2 }, "move back")
assert(stale_row.visibility == 0 and stale_row.writes == 2)
assert(ctx.state.folder_ui_state.hiddenDefaultRows[stale_key] == nil)

-- Creating the first new character after emptying Default can prepend its typed
-- ViewModel while appending its physical widget. Identity reconciliation must
-- keep the new row visible instead of applying a stale VM's GUID by ordinal.
local created = character(3, "New Character")
local created_key = ctx.pool_authority.character_guid_string(created)
-- The stack box can reuse a row that is still Collapsed from its previous stale
-- occupant. The new authoritative GUID was never recorded in hiddenDefaultRows.
local created_row = row("New Character", 1)
vm.PoolCharacterViewModels = { created, kept, removed }
stock.BitReactorStackBox_25 = { kept_row, stale_row, created_row }
ctx.databank_ui.reconcile_default_row_visibility(
    vm, stock, { guids = { [created_key] = true }, count = 1 }, "created after empty")
assert(created_row.visibility == 0 and created_row.writes == 1,
    "newly-created authoritative row was not made visible")
assert(kept_row.visibility == 1 and stale_row.visibility == 1,
    "stale rows were not kept hidden after typed/widget order diverged")

ctx.databank_ui.reconcile_default_row_visibility(
    vm, stock, { guids = { [created_key] = true, [key] = true }, count = 2 },
    "move existing character back")
assert(created_row.visibility == 0,
    "moving another character back hid the newly-created row")
assert(kept_row.visibility == 0,
    "the returning authoritative character was not restored by row identity")

-- A native move may leave multiple typed wrappers for the same character.
-- Identical names remain safe when every wrapper carries the same GUID.
local kept_wrapper = character(1, "Kept")
vm.PoolCharacterViewModels = { created, kept, kept_wrapper, removed }
local kept_index = ctx.pool_authority.character_display_index(vm.PoolCharacterViewModels)
local _, repeated_guid = ctx.pool_authority.character_for_row(kept_row, kept_index)
assert(repeated_guid == key,
    "same-name wrappers for one GUID were treated as different characters")

-- Emptying Default leaves collapsed widgets behind. Returning a character can
-- append another typed wrapper AND another physical widget for the same GUID.
local old_kept_row, returned_row = row("Kept", 1), row("Kept", 0)
local still_away_row = row("Removed", 1)
vm.PoolCharacterViewModels = { kept_wrapper, kept, removed }
stock.BitReactorStackBox_25 = { old_kept_row, still_away_row, returned_row }
local returning_authority = { guids = { [key] = true }, count = 1 }
ctx.databank_ui.reconcile_default_row_visibility(vm, stock, returning_authority, "return to empty Default")
assert(old_kept_row.visibility == 1 and returned_row.visibility == 0,
    "returning to empty Default revealed the stale copy beside the native new row")
assert(old_kept_row.writes == nil, "the old collapsed copy should remain untouched")
assert(still_away_row.visibility == 1)
-- Repair duplicates already visible from an earlier refresh/move-back.
old_kept_row.visibility = 0
ctx.databank_ui.reconcile_default_row_visibility(vm, stock, returning_authority, "repair duplicates")
assert(old_kept_row.visibility == 1 and returned_row.visibility == 0)
-- If every copy is collapsed, restore just one; repeating a refresh is stable.
returned_row.visibility = 1
ctx.databank_ui.reconcile_default_row_visibility(vm, stock, returning_authority, "all copies collapsed")
local visible = 0
for _, r in ipairs(stock.BitReactorStackBox_25) do if r.visibility == 0 then visible = visible + 1 end end
assert(visible == 1, "exactly one authoritative character should be visible")
local writes = (old_kept_row.writes or 0) + (returned_row.writes or 0)
ctx.databank_ui.reconcile_default_row_visibility(vm, stock, returning_authority, "repeat")
assert(writes == (old_kept_row.writes or 0) + (returned_row.writes or 0))
ctx.databank_ui.reconcile_default_row_visibility(vm, stock, { guids = {}, count = 0 }, "move out again")
assert(old_kept_row.visibility == 1 and returned_row.visibility == 1)

-- Duplicate display names cannot establish a unique row identity. Fail open
-- instead of hiding either potentially authoritative row.
local duplicate_a = character(4, "Duplicate")
local duplicate_b = character(5, "Duplicate")
local duplicate_row = row("Duplicate", 1)
vm.PoolCharacterViewModels = { duplicate_a, duplicate_b }
stock.BitReactorStackBox_25 = { duplicate_row }
ctx.databank_ui.reconcile_default_row_visibility(
    vm, stock, { guids = {}, count = 0 }, "ambiguous names")
assert(duplicate_row.visibility == 1 and duplicate_row.writes == nil,
    "ambiguous row identity must fail open")
print("refresh coalescing, retirement, and deleted-row filtering tests passed")
