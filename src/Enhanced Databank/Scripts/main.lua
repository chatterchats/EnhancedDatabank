-- Enhanced Databank v1.0.2
-- Bootstrap only: each factory receives a fresh context for this mod instance.
local VERSION = "1.0.2"
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local directory = assert(source:match("^(.*[/\\])"), "Scripts directory unavailable")
package.path = directory .. "?.lua;" .. package.path

local modules = {
    "common",
    "state",
    "actions",
    "logging",
    "categories",
    "pool_authority",
    "pool_widgets",
    "widget_helpers",
    "folder_icons",
    "folder_ui",
    "popup",
    "pool_mutations",
    "databank_ui",
    "lifecycle",
    "startup",
}
-- Reload factories, but let the hook registry retire the preceding instance.
for _, name in ipairs(modules) do package.loaded[name] = nil end
package.loaded["hook_registry"] = nil
package.loaded["selected_move_button"] = nil
package.loaded["debug_keybinds"] = nil

local runtime = require("hook_registry").start("EnhancedDatabankRuntime", {
    clear_all = EnhancedDatabankClearDelayedActionsOnReload ~= false,
})
local ctx = { runtime = runtime, config = { VERSION = VERSION, MOD = "EnhancedDatabank", PREFIX = "[EnhancedDatabank]" } }
for _, name in ipairs(modules) do ctx[name] = {} end
for _, name in ipairs(modules) do require(name)(ctx) end
EnhancedDatabankActions = ctx.actions.api
return ctx
