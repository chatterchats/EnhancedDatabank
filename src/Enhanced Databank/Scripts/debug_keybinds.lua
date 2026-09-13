local keybinds = {}

function keybinds.install(deps)
    local ok_f7, f7_err = pcall(function()
        deps.register(Key.F7, {ModifierKey.SHIFT}, deps.refresh)
    end)
    if ok_f7 then
        deps.log("Manual authoritative refresh: Shift+F7")
    else
        deps.log("Shift+F7 registration failed: " .. tostring(f7_err))
    end

    local ok_f8, f8_err = pcall(function()
        deps.register(Key.F8, {ModifierKey.SHIFT}, deps.restore)
    end)
    if ok_f8 then
        deps.log("UI-only cleanup/raw restore: Shift+F8")
    else
        deps.log("Shift+F8 registration failed: " .. tostring(f8_err))
    end
end

return keybinds
