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
    try_call = function(callback)
        local ok, value = pcall(callback)
        if ok then return value end
        return nil, value
    end,
}
ctx.pool_authority = {}
assert(loadfile(scripts .. "/pool_authority.lua"))()(ctx)
local function character(id) return { PoolCharacterData = { PoolCharacterID = { A = id, B = 0, C = 0, D = 1 } } } end
local kept, removed = character(1), character(2)
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
local function row(visibility)
    return {
        visibility = visibility,
        GetVisibility = function(self) return self.visibility end,
        SetVisibility = function(self, value)
            self.visibility = value
            self.writes = (self.writes or 0) + 1
        end,
    }
end
local kept_row, stale_row = row(0), row(0)
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
print("refresh coalescing, retirement, and deleted-row filtering tests passed")
