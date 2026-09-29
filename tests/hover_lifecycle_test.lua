-- Run: luajit tests/hover_lifecycle_test.lua "src/Enhanced Databank/Scripts"
-- Use the real identity helpers: pointer-only mocks hide stale GetFullName calls.
local scripts = assert(arg[1])
local function noop() end
ExecuteInGameThreadWithDelay, RetriggerableExecuteInGameThreadWithDelay = noop, noop
MakeActionHandle, CancelDelayedAction = noop, noop
IsValidDelayedActionHandle, IsDelayedActionActive = noop, noop
local hooks, paints, stale_reads = {}, {}, 0
local ctx = {
    common = {}, state = {}, folder_ui = {}, folder_icons = {},
    runtime = { register_hook = function(_, path, callback) hooks[path] = callback; return 1 end },
    logging = { log = noop },
}
for _, module in ipairs({ "common", "state", "folder_ui" }) do
    assert(loadfile(scripts .. "/" .. module .. ".lua"))()(ctx)
end
local function widget(identity)
    return {
        valid = true,
        IsValid = function(self) return self.valid end,
        GetFullName = function(self)
            if not self.valid then
                stale_reads = stale_reads + 1
                error("native access to retired widget")
            end
            return identity
        end,
    }
end
local state = ctx.state.folder_ui_state
ctx.folder_icons.set_folder_icon_color = function(_, mode)
    paints[#paints + 1] = { canvas = state.iconCanvas, mode = mode }
end
ctx.folder_icons.set_icon_canvas_color = function(canvas, color)
    paints[#paints + 1] = { canvas = canvas, color = color }
end
assert(ctx.folder_ui.install_action_hover_hooks())
local function hover(button, entering)
    hooks["/Script/CommonUI.CommonButtonBase:" .. (entering and "BP_OnHovered" or "BP_OnUnhovered")](
        { get = function() return button end })
end
local function register_create(identity)
    local button, canvas = widget(identity), widget(identity .. ".Canvas")
    state.button, state.iconCanvas = button, canvas
    state.buttons = { [identity] = true }
    return button, canvas
end

-- Install a Databank control, destroy its screen during travel, then hover a
-- completely unrelated menu button. Neither hover callback may read old widgets.
local old, old_canvas = register_create("OldDatabank.Create")
old.valid, old_canvas.valid = false, false
local menu = widget("MainMenu.Databank")
hover(menu, true); hover(menu, false)
assert(stale_reads == 0, "unrelated hover dereferenced the destroyed Create Folder button")
assert(#paints == 0, "unrelated hover painted the retired screen")

-- A late invalid event must be rejected before even requesting its full name.
hover(old, false)
assert(stale_reads == 0 and #paints == 0, "invalid hover context was dereferenced")

-- Reentry adopts a fresh control; the callback may carry another Lua wrapper
-- for that same native object, so dispatch must work by its registered identity.
local fresh, canvas = register_create("NewDatabank.Create")
hover(widget("NewDatabank.Create"), true); hover(fresh, false)
assert(#paints == 2 and paints[1].canvas == canvas and paints[1].mode == "hover")
assert(paints[2].mode == "normal")
canvas.valid = false
hover(fresh, true)
assert(#paints == 2, "destroyed Create Folder glyph was painted")

-- Other registered action types retain their hover colors and ignore dead glyphs.
for _, registry in ipairs({ "renameButtons", "deleteButtons", "moveButtons", "moveRowActions" }) do
    local identity = "NewDatabank." .. registry
    local button, glyph = widget(identity), widget(identity .. ".Canvas")
    state[registry][identity] = { button = button, iconCanvas = glyph }
    local count = #paints
    hover(button, true); hover(button, false)
    assert(#paints == count + 2 and paints[count + 1].canvas == glyph)
    assert(paints[count + 1].color == ctx.state.FOLDER_ICON_COLOR_HOVER)
    assert(paints[count + 2].color == ctx.state.FOLDER_ICON_COLOR_NORMAL)
    glyph.valid = false
    hover(button, true)
    assert(#paints == count + 2, "destroyed action glyph was painted")
end
assert(stale_reads == 0)
print("hover lifecycle: retired screens, unrelated events, invalid contexts, reentry and action tints passed")
