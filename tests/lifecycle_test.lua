-- Run: luajit tests/lifecycle_test.lua "src/Enhanced Databank/Scripts"
-- Real bootstrap, registry, scheduler, categories, readiness, authority and
-- renderer; only engine/native widget construction boundaries are mocked.
local scripts = assert(arg[1])
local hooks, registrations, failures, queue, objects = {}, {}, {}, {}, {}
local now, next_id, searches, builds = 0, 0, 0, 0
local ACTIVATE = "/Script/CommonUI.CommonActivatableWidget:ActivateWidget"
local DEACTIVATE = "/Script/CommonUI.CommonActivatableWidget:DeactivateWidget"
local CLICK = "/Script/CommonUI.CommonButtonBase:HandleButtonClicked"
local PREFIX = "/Game/Game/UI/Strategy/Customization/Widgets/CharacterDatabank/"
local MASTER = PREFIX .. "WBP_CharacterBank_Master.WBP_CharacterBank_Master_C:BP_OnActivated"
local PAGE = PREFIX .. "WBP_CharacterBank_Page_CharacterList.WBP_CharacterBank_Page_CharacterList_C:BP_OnActivated"
function RegisterHook(path, pre, post)
    registrations[path] = (registrations[path] or 0) + 1
    if (failures[path] or 0) > 0 then failures[path] = failures[path] - 1; error("not ready") end
    assert(not hooks[path], "duplicate hook: " .. path)
    next_id = next_id + 2
    hooks[path] = { pre = pre, post = post, pre_id = next_id - 1, post_id = next_id }
    return next_id - 1, next_id
end
function UnregisterHook(path, pre, post)
    assert(hooks[path].pre_id == pre and hooks[path].post_id == post)
    hooks[path] = nil
end
function MakeActionHandle() next_id = next_id + 1; return next_id end
function ExecuteInGameThreadWithDelay(handle, delay, callback)
    assert(not queue[handle], "overlapping owned action")
    queue[handle] = { due = now + delay, callback = callback }
end
function RetriggerableExecuteInGameThreadWithDelay(handle, delay, callback)
    queue[handle] = queue[handle] or { callback = callback }
    queue[handle].due = now + delay -- Engine retains the FIRST callback.
end
function CancelDelayedAction(handle) local found = queue[handle] ~= nil; queue[handle] = nil; return found end
function ClearAllDelayedActions() queue = {}; return 0 end
function IsValidDelayedActionHandle(handle) return type(handle) == "number" end
function IsDelayedActionActive(handle) return queue[handle] ~= nil end
function RegisterKeyBind() end
Key, ModifierKey = {}, {}
function FindFirstOf(name) searches = searches + 1; return objects[name] end
function StaticFindObject() return nil end
function FText(v) return v end
function FName(v) return v end
local function size(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function step()
    local id, action
    for handle, entry in pairs(queue) do
        if not action or entry.due < action.due then id, action = handle, entry end
    end
    assert(action, "no queued action")
    now, queue[id] = action.due, nil
    action.callback()
end
local function drain(limit)
    local steps = 0
    while next(queue) do
        steps = steps + 1
        assert(steps <= (limit or 30), "unbounded initialization loop")
        step()
    end
    return steps
end
local function object(identity)
    return { identity = identity, valid = true, active = false,
        IsValid = function(self) return self.valid end,
        GetParent = function(self) return self.active and self or nil end,
        IsInViewport = function() return false end,
        IsVisible = function(self) return self.active end,
        GetFullName = function(self) assert(self.valid, "stale UObject accessed"); return self.identity end,
        IsActivated = function(self) assert(self.valid, "stale UObject accessed"); return self.active end }
end
local function panel()
    local p = object("Panel")
    function p:GetChildrenCount() return #self end
    function p:GetChildAt(i) return self[i + 1] end
    function p:AddChild(child) self[#self + 1] = child; return {} end
    return p
end
local function page(name)
    local p = object("WBP_CharacterBank_Page_CharacterList_C /Engine/Transient.Master.WidgetTree." .. name)
    p.CharacterPool = object("Stock")
    p.CharacterPool.BitReactorStackBox_25 = panel()
    p.BitReactorScrollBox_0 = panel()
    return p
end
local function world()
    local master = object("WBP_CharacterBank_Master_C /Engine/Transient.GameEngine.Master")
    -- CommonUI stack content is not a UPanelWidget child or a direct viewport
    -- widget. UE4SS can return a non-nil null wrapper for GetParent().
    master.GetParent = function() return { IsValid = function() return false end } end
    master.IsInViewport = function() return false end
    local human, astro = page("OtherCharacterList"), page("AstromechCharacterList")
    master.OtherCharacterList, master.AstromechCharacterList = human, astro
    objects.WBP_CharacterBank_Master_C = master
    local vm = object("DatabankVM")
    local pools = {}
    local function pool(name, kind, populated)
        local guid = { A = kind, B = 0, C = 0, D = 1 }
        local chars = populated and { { guid, {} } } or {}
        function chars:ForEach(fn) for _, pair in ipairs(self) do fn(pair[1], pair[2]) end end
        pools[#pools + 1] = { CharacterPoolName = name, CharacterPoolType = kind, Characters = chars }
        local value = object("PoolVM." .. name)
        value.PoolName, value.PoolType = name, kind
        value.PoolCharacterViewModels = populated and { { PoolCharacterData = { PoolCharacterID = guid } } } or {}
        return value
    end
    vm.DefaultCustomCharacterPoolViewModel = pool("Humans", 4)
    vm.DefaultAstromechCharacterPoolViewModel = pool("Droids", 2)
    vm.CustomCharacterPoolViewModels = { pool("Human Folder", 5, true) }
    vm.AstromechCharacterPoolViewModel = { pool("Droid Folder", 3, true) }
    objects.BrunoCharacterDatabankViewModel = vm
    objects.BitReactorCharacterPoolManager = { CharacterPools = pools }
    return master, human, astro, vm
end
local original_open, original_print = io.open, print
io.open = function() return nil end
local logs = {}
print = function(v) logs[#logs + 1] = tostring(v) end
local function boot()
    local ctx = assert(loadfile(scripts .. "/main.lua"))()
    -- Exercise the real renderer down to its native widget construction boundary.
    ctx.folder_ui.ensure_create_folder_control = function(p) ctx.state.folder_ui_state.page = p end
    ctx.folder_ui.install_rename_button_on_folder = function() return true end
    ctx.pool_widgets.remove_dynamic_pool_widgets = function(p)
        builds = builds + 1
        for i = #p.BitReactorScrollBox_0, 1, -1 do p.BitReactorScrollBox_0[i] = nil end
        return 0
    end
    ctx.pool_widgets.create_pool_widget = function(p) return { owner = p } end
    ctx.pool_widgets.bind_pool_widget = function(w, value) w.vm = value; return true end
    ctx.pool_widgets.apply_pool_title = function() return true end
    ctx.pool_widgets.invoke_pool_rows = function(w, rows) w.rows = rows; return true end
    package.loaded.selected_move_button = { ensure = function() return true end }
    return ctx
end
local function event(path, widget)
    -- RemoteUnrealParam is callback-scoped. Never retain it for a delayed action.
    local live = true
    local context = { get = function() assert(live, "retained RemoteUnrealParam"); return widget end }
    local hook = assert(hooks[path], path)
    local callback = hook.post or hook.pre
    callback(context)
    live = false
end
local function activate(widget) widget.active = true; event(ACTIVATE, widget) end
local function deactivate(widget) widget.active = false; event(DEACTIVATE, widget) end
local function rendered(ctx, p, kind)
    local records = ctx.state.folder_ui_state.renderedPools
    assert(#records == 1 and records[1].widget.owner == p)
    assert(records[1].entry.pool_type == kind and #records[1].rows == 1)
    assert(#p.BitReactorScrollBox_0 == 1, "duplicate UI rebuild/attachment")
end

-- Idle startup does one reload-recovery probe, then has no timers or searches.
local ctx = boot()
assert(searches == 0 and not hooks[MASTER] and not hooks[PAGE])
assert(drain() == 1 and searches == 1 and next(ctx.runtime.actions) == nil)
local baseline = searches
for i = 1, 100 do
    activate(object("WBP_Menu_C /Engine/Transient.Menu"))
    activate(object("WBP_CharacterBank_Master_C /Game/UI.Default__Master"))
    activate(page("HawksCharacterList"))
    activate(object("Unrelated_C /Engine/Transient.OtherCharacterList"))
end
assert(next(queue) == nil and searches == baseline, "unrelated CommonUI caused discovery")

-- Cold page-first activation: VM comes later; hooks install once and a single
-- real render populates the right category, even with an empty Default pool.
local master, human, astro, vm = world()
objects.BrunoCharacterDatabankViewModel = nil
activate(human); activate(master)
assert(searches == baseline and size(queue) == 1)
step()
assert(hooks[MASTER] and hooks[PAGE] and builds == 0 and size(queue) == 1)
for i = 1, 10 do event(MASTER, master); event(PAGE, human); event(ACTIVATE, human) end
assert(size(queue) == 1)
objects.BrunoCharacterDatabankViewModel = vm
local stack, extras = human.CharacterPool.BitReactorStackBox_25, vm.CustomCharacterPoolViewModels
human.CharacterPool.BitReactorStackBox_25 = nil
step(); assert(builds == 0 and size(queue) == 1, "rendered before stock tree was ready")
human.CharacterPool.BitReactorStackBox_25 = stack
vm.CustomCharacterPoolViewModels = {}
step(); assert(builds == 0 and size(queue) == 1, "rendered before custom pool VMs were ready")
vm.CustomCharacterPoolViewModels = extras
assert(drain() == 2 and builds == 1)
rendered(ctx, human, 5)
assert(registrations[MASTER] == 1 and registrations[PAGE] == 1)
event(MASTER, master); event(PAGE, human); event(ACTIVATE, human)
assert(next(queue) == nil and builds == 1, "duplicate activation rendered again")

-- Both Blueprint deactivation overrides are installed as well: the game can
-- bypass the native CommonUI UFunction when closing/reusing widgets from C++.
human.active, master.active = false, false
event(PAGE:gsub(":BP_OnActivated$", ":BP_OnDeactivated"), human)
event(MASTER:gsub(":BP_OnActivated$", ":BP_OnDeactivated"), master)
-- Subsequent entry, Blueprint-only delivery, and native fallback reuse hooks.
master.active, human.active = true, true
event(MASTER, master); event(PAGE, human)
drain(); assert(builds == 2); rendered(ctx, human, 5)
assert(registrations[MASTER] == 1 and registrations[PAGE] == 1)

-- A tab switch supersedes pending work. Dispatched stale callbacks cannot search
-- or render; late deactivation of the old tab cannot cancel the new request.
deactivate(human); activate(human)
local stale = select(2, next(queue)).callback
activate(astro); human.active = false
event(DEACTIVATE, human)
baseline = searches; stale(); assert(searches == baseline)
drain(); assert(builds == 3); rendered(ctx, astro, 3)

-- Closing after readiness but before the shared refresh dispatch suppresses UI.
deactivate(astro); activate(astro)
step(); assert(size(queue) == 1)
deactivate(master); deactivate(astro)
drain(); assert(builds == 3)

-- UObject destruction stops the request before any global discovery.
activate(master); activate(human)
human.valid, master.valid = false, false
baseline = searches; drain(); assert(searches == baseline and builds == 3)
master.valid, human.valid = true, true
master.active, human.active = false, false

-- Partial hook failure is bounded and does not rebuild an already-rendered page.
ctx.runtime:teardown("new scenario")
rawset(_G, "EnhancedDatabankRuntime", nil)
registrations, failures = {}, { [PAGE] = 2 }
ctx = boot(); drain()
activate(master); activate(human)
drain(); assert(builds == 4); rendered(ctx, human, 5)
assert(registrations[MASTER] == 1 and registrations[PAGE] == 3)

-- Missing VMs exhaust a finite budget. Event bursts cannot extend it; closing
-- and reopening gets a new budget and works with already-installed hooks.
deactivate(human); deactivate(master)
objects.BrunoCharacterDatabankViewModel = nil
activate(master); activate(human)
local attempts = 0
while next(queue) do
    event(MASTER, master); event(PAGE, human); event(ACTIVATE, human)
    assert(size(queue) == 1)
    step(); attempts = attempts + 1
    assert(attempts <= 20, "activation retries never stopped")
end
assert(attempts == 20 and builds == 4 and next(ctx.runtime.actions) == nil)
objects.BrunoCharacterDatabankViewModel = vm
deactivate(human); deactivate(master); activate(master); activate(human)
drain(); assert(builds == 5)

-- A later page activation can initialize after the master budget expires.
deactivate(human); deactivate(master); activate(master)
assert(drain() == 20 and builds == 5)
activate(astro); drain(); assert(builds == 6); rendered(ctx, astro, 3)

-- Pending retries and old hooks are inert after same-state reload. The single
-- startup probe recovers the already-open Astromech tab without another event.
deactivate(astro); objects.BrunoCharacterDatabankViewModel = nil; activate(astro)
stale = select(2, next(queue)).callback
local stale_hook = hooks[PAGE].pre
local old = ctx
ctx = boot()
assert(not old.runtime.alive)
baseline = searches; stale(); stale_hook(astro); assert(searches == baseline)
objects.BrunoCharacterDatabankViewModel = vm
drain(); assert(builds == 7); rendered(ctx, astro, 3)

-- Fresh Lua-state equivalent: no prior runtime marker, but widgets survive.
ctx.runtime:teardown("Lua state destroyed")
rawset(_G, "EnhancedDatabankRuntime", nil)
ctx = boot(); drain(); assert(builds == 8); rendered(ctx, astro, 3)

-- A surviving, closed master at reload must not begin initialization retries.
deactivate(astro); deactivate(master)
ctx = boot()
baseline = searches
assert(drain() == 1 and searches == baseline + 1 and builds == 8)
assert(not hooks[MASTER] and not hooks[PAGE])

-- Astromech-first entry works even if the Custom page is absent.
master.OtherCharacterList = nil
activate(master); activate(astro)
drain(); assert(builds == 9); rendered(ctx, astro, 3)
assert(hooks[MASTER] and hooks[PAGE])
ctx.runtime:teardown("click-only cold entry scenario")
rawset(_G, "EnhancedDatabankRuntime", nil)
objects, registrations = {}, {}
ctx = boot(); drain()
local function click_menu(label)
    local button = object("WBP_AnimatedSubMenuListButton_C /Engine/Transient.Menu.Button")
    button.ButtonTextBlock = { GetText = function() return label end }
    event(CLICK, button)
end
baseline = searches
for _, label in ipairs({ "Settings", "Squad", "Inventory", "" }) do click_menu(label) end
assert(searches == baseline and next(queue) == nil, "unrelated menu click started discovery")

-- Reproduce the reported regression: no CommonUI activation events at all.
-- The only event is the actual menu click, before the Databank even exists.
click_menu("Character Databank")
assert(searches == baseline and size(queue) == 1)
step(); assert(not hooks[MASTER] and size(queue) == 1)
master, human, astro, vm = world()
master.active, human.active = true, true
local master_activation_reads = 0
master.IsActivated = function() master_activation_reads = master_activation_reads + 1; return true end
master.IsVisible = function() return false end
step(); assert(not hooks[MASTER], "hidden master accepted")
master.IsVisible = function(self) return self.active end
step(); assert(not hooks[MASTER], "entry did not wait for a second stable observation")
step(); assert(hooks[MASTER] and hooks[PAGE])
drain(); assert(builds == 10); rendered(ctx, human, 5)
assert(master_activation_reads == 0, "transitional master IsActivated was called")
assert(registrations[CLICK] == 1, "entry path registered a duplicate button hook")

-- Reused master, again with neither activation nor deactivation event delivery.
master.active, human.active = false, false
click_menu("DATABANK")
master.active, astro.active = true, true
drain(); assert(builds == 11); rendered(ctx, astro, 3)
assert(registrations[MASTER] == 1 and registrations[PAGE] == 1)

-- Other navigation cancels even an already-dispatched entry probe.
click_menu("DATABANK")
stale = select(2, next(queue)).callback
click_menu("Settings")
baseline = searches; stale()
assert(searches == baseline and next(queue) == nil and builds == 11)

-- A click that never produces a master gets six probes, then leaves no work.
objects.WBP_CharacterBank_Master_C = nil
click_menu("DATABANK")
assert(drain() == 6 and builds == 11 and next(ctx.runtime.actions) == nil)

-- CommonUI/Blueprint events may also arrive during a click-owned request. They
-- must merge, keep the stability check and produce one render, not two chains.
objects.WBP_CharacterBank_Master_C = master
click_menu("DATABANK"); activate(master); activate(astro)
assert(size(queue) == 1)
step(); assert(builds == 11 and size(queue) == 1)
event(MASTER, master); event(PAGE, astro)
drain(); assert(builds == 12); rendered(ctx, astro, 3)

-- A literal nil parent is equally valid for stack-managed content. Neither
-- direct viewport membership nor a panel parent should gate a click-owned entry.
master.GetParent = function() return nil end
click_menu("DATABANK")
drain(); assert(builds == 13); rendered(ctx, astro, 3)

-- Rejections identify the failed readiness condition within the finite budget.
master.IsVisible = function() error("mock visibility unavailable") end
click_menu("DATABANK")
assert(drain() == 6 and builds == 13)
local diagnosed = false
for _, line in ipairs(logs) do
    if line:find("entry check expired: master visibility unavailable:", 1, true) then diagnosed = true end
end
assert(diagnosed, "entry failure did not identify its rejected readiness check")
master.IsVisible = function(self) return self.active end

-- Visibility can survive when a reusable screen is closed. A fresh startup
-- probe must also see an active supported page before arming recovery retries.
human.active, astro.active = false, false
ctx = boot()
baseline = searches
assert(drain() == 1 and searches == baseline + 1 and builds == 13)
assert(not hooks[MASTER] and not hooks[PAGE])
ctx.runtime:teardown("test complete")
for _, line in ipairs(logs) do assert(not line:find("attempt to", 1, true), line) end
io.open, print = original_open, original_print
print("activation lifecycle: idle startup, filtering, cold/warm render, categories, bounded retries, cancellation and reload passed")
