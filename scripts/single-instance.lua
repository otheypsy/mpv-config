local mp = require 'mp'
local msg = require 'mp.msg'
local options = require "mp.options"

local opts = {
    loadfile_action_suffix = "append"
}
options.read_options(opts, "single-instance", function() end)

-- IPC socket path
local ipc_socket_path
if package.config:sub(1, 1) == "\\" then
    ipc_socket_path = "\\\\.\\pipe\\mpvsocket"
else
    local runtime_dir = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
    ipc_socket_path = runtime_dir .. "/mpvsocket"
end

-- Escape JSON special chars
local function escape_json_str(str)
    if not str then return "" end
    return (str:gsub("\\", "\\\\")
        :gsub("\"", "\\\""))
end

-- Get full absolute path for the current file
local function get_full_path()
    local path = mp.get_property("path") or ""
    if path == "" then return "" end
    return path
end

-- Try open IPC pipe in write mode to check if main instance is running
local function try_connect_pipe(path)
    local f = io.open(path, "w")
    if f then
        f:close()
        return true
    end
    return false
end

-- Send loadfile command with 'replace' to main instance or use 'append' to ADD to PLAYLIST instead
local function send_file_to_main(path, filepath)
    local escaped_path = escape_json_str(filepath or "")
    local json = string.format(
        '{"command": ["loadfile", "%s", "%s"]}',
        escaped_path,
        opts.loadfile_action_suffix
    )

    local f = io.open(path, "w")
    if not f then
        msg.error("Could not connect to IPC pipe: " .. path)
        return false
    end
    f:write(json .. "\n")
    f:close()
    msg.info("Sent file to main MPV: " .. filepath)
    return true
end

-- Create IPC server pipe for main instance
local function create_ipc_server(path)
    mp.set_property("input-ipc-server", path)
    msg.info("Created IPC server pipe: " .. path)
end

-- Determine instance mode on script load
local is_main_instance = false
if try_connect_pipe(ipc_socket_path) then
    is_main_instance = false
    msg.info("Detected existing MPV instance. This is a secondary instance.")
else
    create_ipc_server(ipc_socket_path)
    is_main_instance = true
    msg.info("No MPV instance detected. This is the main instance.")
end

function On_Start_File()
    local filepath = get_full_path()

    if filepath == "" then
        msg.warn("No valid file path detected. Continuing standby.")
        return
    end

    msg.info("Playing file: " .. filepath)

    if is_main_instance then
        msg.info("Main instance: playing file normally.")
    -- normal playback behavior
    else
        msg.info("Secondary instance: sending file and quitting.")
        if send_file_to_main(ipc_socket_path, filepath) then
            -- Delay quit to ensure IPC pipe flushes properly
            mp.add_timeout(0.5, function() mp.commandv("quit") end)
        else
            msg.error("Failed to send file; continuing as standalone.")
            create_ipc_server(ipc_socket_path)
            is_main_instance = true
        end
    end
end

-- Handle file start events
mp.register_event("start-file", On_Start_File)
