-- Run: luajit tests/page_actions_test.lua "src/Enhanced Databank/Scripts"
local scripts = assert(arg[1])
local hooks, logs = {}, {}
local ctx = { page_actions = {}, state = { folder_ui_state = {} },
    categories = {}, pool_authority = {}, runtime = {}, common = {},
    logging = { log = function(message) logs[#logs + 1] = message end } }
ctx.common.unwrap = function(value) return value end
ctx.common.uobject_is_valid = function(value) return value ~= nil and value.valid ~= false end
ctx.common.same_object = function(a, b) return a ~= nil and a == b end
ctx.common.object_name = function(value) return value.name end
ctx.common.read_property = function(value, key) return value[key] end
ctx.common.panel_child_count = function(value) return #value end
ctx.common.panel_child_at = function(value, index) return value[index + 1] end
ctx.common.try_call = function(callback)
    local ok, value = pcall(callback)
    if ok then return value end
    return nil, value
end
ctx.categories.for_page = function(page) return page.category end
local authority
ctx.pool_authority.authoritative_pool_state = function(category)
    assert(category == ctx.state.folder_ui_state.page.category)
    return authority
end
ctx.pool_authority.character_guid_string = function(vm) return vm.guid end
function ctx.runtime:register_hook(path, callback)
    assert(not hooks[path], "duplicate hook")
    hooks[path] = callback
end
assert(loadfile(scripts .. "/page_actions.lua"))()(ctx)

for _, category in ipairs({ "custom", "astromech" }) do
    local controls = { visibility = 1, writes = 0 }
    function controls:SetVisibility(value) self.visibility = value; self.writes = self.writes + 1 end
    local page = { name = category, category = { id = category }, ControlButtons = controls,
        isPoolNotEmpty = false }
    local stack = {}
    local row = { GetParent = function() return stack end }
    stack[1] = row
    local pool = { name = "Folder", widget = { BitReactorStackBox_25 = stack }, rows = { { guid = "A" } } }
    ctx.state.folder_ui_state = { page = page, renderedPools = { pool } }
    authority = { default_custom = { count = 0 }, custom_order = { "Folder" },
        custom_by_name = { Folder = { count = 1, guids = { A = true } } } }

    -- Cold entry: a custom character exists but no selection has been made yet.
    ctx.page_actions.ensure(page)
    assert(page.isPoolNotEmpty and controls.visibility == 1)
    page["Selected Character Button"] = row
    for path, callback in pairs(hooks) do
        if path:find("SelectedCharacterButton", 1, true) then callback(page) end
    end
    assert(controls.visibility == 0, "folder selection did not restore actions")

    -- Native Default-only check runs again; the post hook repairs its result.
    page.isPoolNotEmpty, controls.visibility = false, 1
    for path, callback in pairs(hooks) do
        if path:match(":CheckForPool$") then callback(page) end
    end
    assert(page.isPoolNotEmpty and controls.visibility == 0)

    -- A different tab/old screen must not change this page's gate.
    ctx.page_actions.reconcile({ name = "unrelated", category = page.category })
    assert(controls.visibility == 0)

    -- Rebuilding the folder detaches the previously selected row.
    stack[1] = { GetParent = function() return stack end }
    ctx.page_actions.reconcile(page)
    assert(controls.visibility == 1, "detached selection kept actions visible")
    stack[1] = row
    ctx.page_actions.reconcile(page)
    assert(controls.visibility == 0)

    -- Deleted character's stale widget is not enough to authorize actions.
    authority.custom_by_name.Folder.guids = { B = true }
    ctx.page_actions.reconcile(page)
    assert(controls.visibility == 1)
    authority.custom_by_name.Folder.guids = { A = true }
    page["Selected Character Button"] = nil
    ctx.page_actions.reconcile(page)
    assert(controls.visibility == 1, "clearing selection must hide actions")

    page["Selected Character Button"] = row
    ctx.page_actions.reconcile(page)
    authority.custom_by_name.Folder.count = 0
    authority.custom_by_name.Folder.guids = {}
    ctx.page_actions.reconcile(page)
    assert(not page.isPoolNotEmpty and controls.visibility == 1, "last deletion left actions visible")

    -- Default populated: native visibility (including Hidden) is untouched.
    authority.default_custom.count = 1
    controls.visibility = 2
    local writes = controls.writes
    ctx.page_actions.reconcile(page)
    assert(controls.visibility == 2 and controls.writes == writes)
    authority = nil
    ctx.page_actions.reconcile(page)
    assert(controls.writes == writes, "unavailable authority must not alter UI")
    page.valid = false
    ctx.page_actions.reconcile(page)
end
local count = 0
for _ in pairs(hooks) do count = count + 1 end
assert(count == 2, "shared Blueprint hooks must install only once")
print("page_actions_test: ok")
