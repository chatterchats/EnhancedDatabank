-- Exercise native category boundaries and deferred operations with mock UObjects.
-- Run: luajit tests/astromech_test.lua "src/Enhanced Databank/Scripts"
local scripts = assert(arg[1])
local objects, deferred, notices, created, moved, renamed, deleted = {}, {}, {}, {}, {}, {}, {}
local ctx = { common = {}, categories = {}, state = {}, pool_authority = {}, pool_mutations = {},
    databank_ui = {}, popup = {}, widget_helpers = {}, runtime = {}, actions = {},
    logging = { log = function() end, section = function() end } }
local c = ctx.common
c.unwrap = function(v) return v end
c.read_property = function(v, key) return v and v[key] end
c.find_first = function(name) return objects[name] end
c.object_name = function(v) return v and v.identity or "nil" end
c.same_object = function(a, b) return a == b end
c.text_value = function(v) return tostring(v or "") end
c.uobject_is_valid = function(v) return v ~= nil end
c.array_each = function(a, fn) for i, v in ipairs(a or {}) do fn(i, v) end end
c.map_each = function(a, fn) for k, v in pairs(a or {}) do fn(k, v) end end
c.panel_child_count = function(p) return p and #p end
c.panel_child_at = function(p, i) return p[i + 1] end
c.try_call = function(fn) local ok, v = pcall(fn); if ok then return v end; return nil, v end
ctx.actions.run_on_game_thread_after = function(_, fn) deferred[#deferred + 1] = fn end
ctx.widget_helpers.trim_string = function(v) return tostring(v or ""):match("^%s*(.-)%s*$") end
function MakeActionHandle() return 1 end
function FText(v) return v end
function FName(v) return v end
local function load(name) assert(loadfile(scripts .. "/" .. name .. ".lua"))()(ctx) end
load("state"); load("categories"); load("pool_authority"); load("pool_mutations"); load("databank_ui")
ctx.popup.show_folder_notice = function(title) notices[#notices + 1] = title end
local human, astro = ctx.categories.custom, ctx.categories.astromech
local function page(name)
    return { identity = "WBP_Page /Engine/Transient.Master.WidgetTree." .. name,
        CharacterPool = {}, BitReactorScrollBox_0 = {}, IsActivated = function(self) return self.active end }
end
local hp, ap = page(human.page), page(astro.page)
local master = { OtherCharacterList = hp, AstromechCharacterList = ap }
objects.WBP_CharacterBank_Master_C = master
assert(ctx.categories.activate(ap) and ctx.categories.current() == astro)
assert(not ctx.categories.activate({ identity = ap.identity .. ".WidgetTree.Button" }))
assert(not ctx.categories.activate(page("HawksCharacterList")))
local function pool(name, kind, id)
    local guid = id and { A = id, B = 0, C = 0, D = 1 }
    local char = guid and { PoolCharacterData = { PoolCharacterID = guid } }
    return { CharacterPoolName = name, CharacterPoolType = kind, Characters = guid and { [guid] = {} } or {} },
        { identity = "VM." .. name, PoolName = name, PoolType = kind,
          PoolCharacterViewModels = char and { char } or {} }, char
end
local hd, hdvm, hc = pool("Humans", 4, 1)
local ad, advm, ac = pool("Droids", 2, 2)
local hf, hfvm = pool("Human Folder", 5)
local af, afvm = pool("Droid Folder", 3)
local other = pool("Hawks", 0, 3)
local manager = { CharacterPools = { hd, ad, hf, af, other } }
objects.BitReactorCharacterPoolManager = manager
local vm = { DefaultCustomCharacterPoolViewModel = hdvm, CustomCharacterPoolViewModels = { hfvm },
    DefaultAstromechCharacterPoolViewModel = advm, AstromechCharacterPoolViewModel = { afvm } }
objects.BrunoCharacterDatabankViewModel = vm
function vm:IsNewPoolNameAvailable() return true end
function vm:CreatePool(name, kind) created[#created + 1] = { name, kind }; return {} end
function vm:RenamePool(p, name) renamed[#renamed + 1] = { p, name } end
function vm:DeletePool(p) deleted[#deleted + 1] = p end
function manager:MoveCharacterToAnotherPool(guid, name) moved[#moved + 1] = { guid, name }; return true end
for _, cat in ipairs({ human, astro }) do
    local a = assert(ctx.pool_authority.authoritative_pool_state(cat))
    assert(a.default_custom.pool_type == cat.default_type and #a.custom_order == 1)
    local extras = ctx.pool_authority.collect_extra_pool_vms(vm, a)
    assert(extras[a.custom_order[1]].PoolType == cat.custom_type)
    local index = ctx.pool_authority.collect_raw_vm_index(vm, extras, cat)
    assert(index[ctx.pool_authority.character_guid_string(cat == human and hc or ac)])
    assert(not index[ctx.pool_authority.character_guid_string(cat == human and ac or hc)])
end
-- A tab already active at reload is recovered without a new activation event.
hp.active, ap.active = false, true
ctx.categories.activate(hp)
local resolved, _, err, stock, default, scroll, category = ctx.databank_ui.resolve_live_page()
assert(not err and resolved == ap and stock == ap.CharacterPool and default == advm)
assert(scroll == ap.BitReactorScrollBox_0 and category == astro)
-- Explicit resolution for a pending action must not follow the visible tab.
assert(ctx.databank_ui.resolve_live_page(human) == hp)
ctx.categories.activate(hp)
ctx.pool_mutations.perform_create_folder("Droid New", astro)
ctx.pool_mutations.perform_create_folder("Human New", human)
assert(created[1][2] == 3 and created[2][2] == 5)
local hg, ag = ctx.pool_authority.character_guid_string(hc), ctx.pool_authority.character_guid_string(ac)
ctx.pool_mutations.perform_move_character(ag, "Droid Folder", "R2", astro)
assert(#moved == 1 and moved[1][1].A == 2 and moved[1][2] == "Droid Folder")
ctx.pool_mutations.perform_move_character(ag, "Human Folder", "R2", human)
ctx.pool_mutations.perform_move_character(hg, "Droid Folder", "Human", astro)
ctx.pool_mutations.perform_move_character(ag, "Human Folder", "R2", astro)
assert(#moved == 1, "cross-category move reached the native manager")
ctx.pool_mutations.perform_move_character(hg, "Human Folder", "Human", human)
assert(#moved == 2 and moved[2][1].A == 1)
ctx.pool_mutations.perform_rename_folder(afvm, "Droid Folder", "Renamed", astro)
assert(#renamed == 1 and renamed[1][1] == afvm)
ctx.pool_mutations.perform_rename_folder(afvm, "Droid Folder", "Wrong category", human)
ctx.pool_mutations.perform_rename_folder(advm, "Droids", "Default", astro)
assert(#renamed == 1, "protected or foreign folder renamed")
ctx.pool_mutations.perform_delete_folder(afvm, "Droid Folder", astro)
assert(#deleted == 1 and deleted[1] == afvm)
af.Characters = ad.Characters
ctx.pool_mutations.perform_delete_folder(afvm, "Droid Folder", astro)
ctx.pool_mutations.perform_delete_folder(advm, "Droids", astro)
assert(#deleted == 1, "non-empty or default pool deleted")
af.Characters = {}
vm.AstromechCharacterPoolViewModel = {}
ctx.pool_mutations.perform_delete_folder(afvm, "Droid Folder", astro)
ctx.pool_mutations.perform_rename_folder(afvm, "Droid Folder", "Stale", astro)
assert(#deleted == 1 and #renamed == 1, "stale folder VM mutated")
vm.AstromechCharacterPoolViewModel = { afvm }
-- The production renderer switches pages and only supplies that category's pools.
ctx.folder_ui = {
    ensure_create_folder_control = function(p) ctx.state.folder_ui_state.page = p end,
    install_rename_button_on_folder = function(p, _, _, pool_vm)
        assert(pool_vm.PoolType == (p == ap and 3 or 5)); return true
    end,
    install_action_hover_hooks = function() end,
}
ctx.pool_widgets = {
    remove_dynamic_pool_widgets = function(p)
        for i = #p.BitReactorScrollBox_0, 1, -1 do p.BitReactorScrollBox_0[i] = nil end
        return 0
    end,
    create_pool_widget = function(p) return { owner = p } end,
    bind_pool_widget = function(w, pool_vm) w.vm = pool_vm; return true end,
    apply_pool_title = function() return true end,
    invoke_pool_rows = function() return true end,
}
for _, p in ipairs({ hp, ap }) do
    p.BitReactorScrollBox_0.AddChild = function(self, widget)
        self[#self + 1] = widget; return {}
    end
end
package.loaded.selected_move_button = { ensure = function(p, deps)
    deps.register({ identity = p.identity .. ".Move" }); return true
end }
for _, p in ipairs({ ap, hp, ap }) do
    hp.active, ap.active = p == hp, p == ap
    ctx.categories.activate(p)
    ctx.databank_ui.refresh_visible_pools("tab switch")
    local records = ctx.state.folder_ui_state.renderedPools
    assert(#records == 1 and records[1].widget.owner == p)
    assert(records[1].entry.pool_type == (p == ap and 3 or 5))
    assert(#p.BitReactorScrollBox_0 == 1, "returning to a tab duplicated folders")
end
-- Exercise the real create-dialog result hook and its delayed mutation.
local result_hook
function ctx.runtime:register_hook(_, fn) result_hook = fn; return 1 end
local popup = { Belowtext = { SetContent = function() end } }
local editable = { GetText = function() return "Deferred Droid Folder" end }
local subsystem = { BP_ShowMessageBox = function() return popup end }
local cdo = { MakeGameDialogDescriptor = function() return {} end,
    GetLocalPlayerSubsystem = function() return subsystem end }
ctx.widget_helpers.load_class = function() return { GetCDO = function() return cdo end } end
ctx.widget_helpers.create_user_widget = function() return { EditableText = editable } end
load("popup")
ctx.categories.activate(ap)
assert(ctx.popup.show_create_folder_dialog(astro))
ctx.categories.activate(hp)
result_hook(popup, { TagName = ctx.state.DIALOG_RESULT_PRIMARY })
local pending = deferred; deferred = {}
for _, fn in ipairs(pending) do fn() end
assert(created[#created][1] == "Deferred Droid Folder" and created[#created][2] == 3,
    "switching tabs redirected the deferred create operation")
-- Reproduce empty Default -> move back through the real mutation path in both
-- categories. Native ownership changes but old typed wrappers/widgets survive.
ctx.pool_authority.character_display_name = function(char) return char.name end
hc.name, ac.name = "Human", "Droid"
local function character_row(char)
    return {
        BitReactorRichTextBlock_73 = { GetText = function() return char.name end },
        visibility = 0,
        GetVisibility = function(self) return self.visibility end,
        SetVisibility = function(self, value) self.visibility = value end,
    }
end
for _, spec in ipairs({ { human, hp, hd, hdvm, hf, hc }, { astro, ap, ad, advm, af, ac } }) do
    local cat, p, default_pool, default_vm, custom_pool, char =
        spec[1], spec[2], spec[3], spec[4], spec[5], spec[6]
    hp.active, ap.active = p == hp, p == ap
    ctx.categories.activate(p)
    local guid_value = char.PoolCharacterData.PoolCharacterID
    local guid = ctx.pool_authority.character_guid_string(char)
    local stock_rows = { character_row(char) }
    p.CharacterPool.BitReactorStackBox_25 = stock_rows
    default_vm.PoolCharacterViewModels = { char }
    default_pool.Characters = { [guid_value] = {} }
    custom_pool.Characters = {}
    function manager:MoveCharacterToAnotherPool(value, target)
        assert(value.A == guid_value.A)
        default_pool.Characters[guid_value] = nil
        custom_pool.Characters[guid_value] = nil
        if target == default_pool.CharacterPoolName then
            default_pool.Characters[guid_value] = {}
            table.insert(default_vm.PoolCharacterViewModels, char)
            stock_rows[#stock_rows + 1] = character_row(char)
        else
            assert(target == custom_pool.CharacterPoolName)
            custom_pool.Characters[guid_value] = {}
        end
        return true
    end
    local function visible_rows()
        local count = 0
        for _, row in ipairs(stock_rows) do if row.visibility == 0 then count = count + 1 end end
        return count
    end
    for cycle = 1, 3 do
        ctx.pool_mutations.perform_move_character(guid, custom_pool.CharacterPoolName, char.name, cat)
        assert(visible_rows() == 0, "moving out must hide every stale copy: " .. cat.id)
        ctx.pool_mutations.perform_move_character(guid, default_pool.CharacterPoolName, char.name, cat)
        assert(visible_rows() == 1, "move-back exposed duplicate rows before refresh: " .. cat.id)
        assert(stock_rows[#stock_rows].visibility == 0, "the fresh native row must stay visible")
        ctx.databank_ui.refresh_visible_pools("return to emptied Default")
        assert(visible_rows() == 1, "refresh exposed duplicate rows: " .. cat.id)
    end
    -- Delayed recovery must recheck ownership if another move runs first.
    ctx.pool_mutations.perform_move_character(guid, custom_pool.CharacterPoolName, char.name, cat)
    local read_property = c.read_property
    c.read_property = function(object, property)
        if object == default_vm and property == "PoolCharacterViewModels" then return nil end
        return read_property(object, property)
    end
    deferred = {}
    ctx.pool_mutations.perform_move_character(guid, default_pool.CharacterPoolName, char.name, cat)
    assert(#deferred == 1, "missing native rows should schedule one visibility recovery")
    c.read_property = read_property
    ctx.pool_mutations.perform_move_character(guid, custom_pool.CharacterPoolName, char.name, cat)
    assert(visible_rows() == 0)
    for _, fn in ipairs(deferred) do fn() end
    assert(visible_rows() == 0, "delayed recovery resurrected a character moved out again")
end
print("Astromech category, page routing, mutation isolation, deferred dialog, and duplicate move-back tests passed")
