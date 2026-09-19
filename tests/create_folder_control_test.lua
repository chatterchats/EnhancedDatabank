-- Exercise the real installer and widget traversal with unnamed Blueprint clones.
-- Run: luajit tests/create_folder_control_test.lua "<Scripts directory>"
local scripts = assert(arg[1])
local function noop() end
FName = function(value) return value end
FText = function(value) return value end
local serial = 0
local function widget(name, class)
    local w = { name = name, class = class, children = {}, width = 792 }
    function w:IsValid() return true end
    function w:GetParent() return self.parent end
    function w:GetClass() return self.class end
    function w:GetChildrenCount() return #self.children end
    function w:GetChildAt(index) return self.children[index + 1] end
    function w:RemoveChild(child)
        for index, value in ipairs(self.children) do
            if value == child then
                table.remove(self.children, index)
                child.parent = nil
                return true
            end
        end
        return false
    end
    function w:AddChild(child)
        if self.failAttach then return nil end
        if child.parent then child.parent:RemoveChild(child) end
        table.insert(self.children, child)
        child.parent = self
        child.Slot = setmetatable({}, { __index = function() return noop end })
        return child.Slot
    end
    w.AddChildToCanvas = w.AddChild
    function w:SetWidthOverride(width) self.width = width end
    function w:GetCachedGeometry()
        return { GetLocalSize = function() return { X = self.width, Y = 64 } end }
    end
    w.ForceLayoutPrepass = noop
    w.SetHeightOverride = noop
    w.SetVisibility = noop
    w.SetBrushColor = noop
    w.SetRenderTranslation = noop
    function w:Rename() error("Rename is unavailable through reflection") end
    return w
end

local clones, scheduled, clicked, styled, tint = 0, {}, {}, nil, nil
local activeCategory
local function context()
    local ctx = {
        state = {}, common = {}, widget_helpers = {}, folder_icons = {}, folder_ui = {},
        logging = { log = noop }, actions = {}, runtime = {}, categories = {}, popup = {},
        lifecycle = { handle_strategy_submenu_click = function() return false end },
    }
    local common = ctx.common
    common.unwrap = function(value) return value end
    common.try_call = function(callback)
        local ok, value = pcall(callback)
        if ok then return value end
        return nil, value
    end
    common.read_property = function(value, key) return value and value[key] end
    common.uobject_is_valid = function(value) return value ~= nil and value:IsValid() end
    common.object_name = function(value) return value and value.name or "<nil>" end
    common.class_name = function(value) return value.class end
    common.same_object = function(a, b) return a ~= nil and a == b end
    common.panel_child_count = function(value) return value:GetChildrenCount() end
    common.panel_child_at = function(value, index) return value:GetChildAt(index) end
    ctx.actions.run_on_game_thread_after = function(_, callback) table.insert(scheduled, callback) end
    ctx.categories.current = function() return activeCategory end
    ctx.popup.show_create_folder_dialog = function(category) table.insert(clicked, category) end
    ctx.runtime.register_hook = function(_, path, callback)
        if path:find("HandleButtonClicked", 1, true) then ctx.click = callback end
        if path:find("BP_OnHovered", 1, true) then ctx.hover = callback end
        return 1
    end
    for _, module in ipairs({ "state", "widget_helpers", "folder_icons", "folder_ui" }) do
        assert(loadfile(scripts .. "/" .. module .. ".lua"))()(ctx)
    end
    -- Only engine construction and visual styling are mocked. Keep the real
    -- clone helper, failed Rename, overlay composition, traversal and installer.
    ctx.widget_helpers.construct_widget = function(_, class, name)
        serial = serial + 1
        return widget(name .. "_" .. serial, class)
    end
    ctx.widget_helpers.create_user_widget = function(_, class)
        clones = clones + 1
        return widget("WBP_CharacterBankCreateNewBtn_C_" .. clones, class)
    end
    ctx.folder_icons.style_create_folder_icon_button = function(_, button) styled = button end
    ctx.folder_icons.set_folder_icon_color = function() tint = ctx.state.folder_ui_state.iconCanvas end
    assert(ctx.folder_ui.install_folder_button_click_hook())
    assert(ctx.folder_ui.install_action_hover_hooks())
    return ctx
end

local function page(name, shared)
    local p = widget(name, "Page")
    local root = widget(name .. "_Root", "VerticalBox")
    p.WidgetTree = { RootWidget = root }
    p.WBP_CharacterBankCreateNewBtn = widget(name .. "_CreateNew", "WBP_CharacterBankCreateNewBtn_C")
    if shared then
        p.row = widget("CharacterShare_CreateImportRow", "HorizontalBox")
        p.createWidth = widget("CharacterShare_CreateNewWidth", "SizeBox")
        p.createWidth:AddChild(p.WBP_CharacterBankCreateNewBtn)
        p.row:AddChild(p.createWidth)
        p.import = widget("CharacterShare_ImportWidth", "SizeBox")
        p.row:AddChild(p.import)
        root:AddChild(p.row)
    else
        root:AddChild(p.WBP_CharacterBankCreateNewBtn)
    end
    return p
end

local function drain()
    local pending = scheduled
    scheduled = {}
    for _, callback in ipairs(pending) do callback() end
end

for _, shared in ipairs({ true, false }) do
    local ctx = context()
    local pages = { page("Characters", shared), page("Astromechs", shared) }
    local installed = {}
    local before = clones
    for cycle = 1, 5 do
        for index, p in ipairs(pages) do
            activeCategory = p.name
            ctx.state.folder_ui_state.category = activeCategory
            assert(ctx.folder_ui.ensure_create_folder_control(p))
            drain()
            local state = ctx.state.folder_ui_state
            if cycle == 1 then
                installed[index] = { button = state.button, canvas = state.iconCanvas,
                    overlay = state.iconOverlay, row = state.row }
            end
            local saved = installed[index]
            assert(state.button == saved.button, "tab return cloned another Create Folder button")
            assert(state.iconCanvas == saved.canvas and state.iconOverlay == saved.overlay,
                "tab return adopted another page's icon")
            assert(styled == saved.button)
            local width = p.createWidth or ctx.widget_helpers.find_tree_widget(p, "EnhancedDatabank_CreateNewWidth")
            assert(width.width == 720, "Create New width shrank again")
            assert(saved.row:GetChildrenCount() == (shared and 3 or 2), "action row gained extra children")
            if shared then assert(p.row:GetChildAt(1) == p.import, "Import was moved or removed") end
            ctx.click(saved.button)
            drain()
            assert(clicked[#clicked] == p.name, "adopted button routes to the wrong category")
            local count = #clicked
            if installed[3 - index] then ctx.click(installed[3 - index].button) end
            drain()
            assert(#clicked == count, "inactive page's button is still registered")
            tint = nil
            ctx.hover(saved.button)
            assert(tint == saved.canvas, "hover did not target the adopted glyph")
        end
        -- Fresh Lua state must also rediscover the same physical controls.
        if cycle == 3 then ctx = context() end
    end
    assert(clones == before + 2, "each page should clone exactly once across switches and reload")
end

-- A failed Character Share append must not consume width on every retry.
local ctx = context()
local p = page("Retry", true)
p.row.failAttach = true
assert(not ctx.folder_ui.ensure_create_folder_control(p))
assert(p.createWidth.width == 792, "failed installation consumed Create New width")
p.row.failAttach = false
assert(ctx.folder_ui.ensure_create_folder_control(p))
assert(p.createWidth.width == 720 and p.row:GetChildrenCount() == 3)
print("create-folder tab switching, reload, routing, hover, and retry tests passed")
