-- Enhanced Databank: logging.
-- Initialized once per mod instance; shared references use explicit ctx fields.
-- Context: config, logging, runtime.
return function(ctx)
    ctx.logging.source_resolution_note = nil

    local function resolve_source_log_path()
        if not debug or type(debug.getinfo) ~= "function" then
            ctx.logging.source_resolution_note = "debug.getinfo unavailable"
            return nil
        end
        local ok, info = pcall(debug.getinfo, 1, "S")
        if not ok or not info or type(info.source) ~= "string" then
            ctx.logging.source_resolution_note = "debug.getinfo failed or returned no source"
            return nil
        end
        local source = info.source
        ctx.logging.source_resolution_note = "debug source=" .. tostring(source)
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

    ctx.logging.LOG_PATH = nil

    for _, candidate in ipairs(LOG_CANDIDATES) do
        local handle = select(1, try_open_log(candidate))
        if handle ~= nil then
            log_file = handle
            ctx.logging.LOG_PATH = candidate
            break
        end
    end

    function ctx.logging.log(message)
        local line = ctx.config.PREFIX .. " " .. tostring(message)
        print(line .. "\n")
        if log_file then
            pcall(function()
                log_file:write(line .. "\n")
                log_file:flush()
            end)
        end
    end

    ctx.runtime.on_teardown = function()
        if log_file then
            log_file:close()
            log_file = nil
        end
    end

    function ctx.logging.section(title)
        ctx.logging.log("")
        ctx.logging.log("=== " .. tostring(title) .. " ===")
    end
end
