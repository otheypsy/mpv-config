local msg = require "mp.msg"

local platform = mp.get_property("platform")

local function system_open(path)
    local args
    if platform == "windows" then
        args = { "rundll32", "url.dll,FileProtocolHandler", path }
    elseif platform == "darwin" then
        args = { "open", path }
    else
        args = { "gio", "open", path }
    end

    mp.commandv("run", unpack(args))
end

local function open_config_folder()
    if not mp.get_property_bool("config") then
        mp.msg.warn("No config folder for --no-config instances")
        return false
    end
    local path = mp.command_native({ "expand-path", "~~/" })
    msg.info("Opening config dir -- ", path)
    system_open(path)
end

local function on_script_message(arg1, arg2)
    if arg1 == "open" and arg2 == "config-dir" then
        open_config_folder()
    end
end

mp.register_script_message("custom_features", on_script_message)
