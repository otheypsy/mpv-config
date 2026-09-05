-- MPV Single Instance
--
-- Ensure only single instance of MPV is used for enabled video file extensions
--
--  * Validates video file extensions using MPV native `video-ext` property
--  * Targeted for Windows only
--  * Requires socket connection modification for other platforms
--  * Socket mode must be modified for other platforms to prevent side-effects
--

local msg = require("mp.msg")

local escaped_ipc_server = "\\\\.\\pipe\\mpvsocket"
local video_ext = mp.get_property_native("video-exts") or {}
local is_main_instance = false

local function setup_instance()
    local pipe = io.open(escaped_ipc_server, 'w')
    if pipe then
        pipe:close()
        msg.debug("Existing MPV instance IPC server detected")
        is_main_instance = false
        return true
    end
    msg.info("Creating IPC server --", escaped_ipc_server)
    mp.set_property("input-ipc-server", escaped_ipc_server)
    is_main_instance = true
end

local function escape_json_str(str)
    if not str then return "" end
    return (str:gsub("\\", "\\\\")
        :gsub("\"", "\\\""))
end

local function send_file_to_main(file_path)
    local escaped = escape_json_str(file_path or "")
    local ipc_command = string.format(
        '{\"command\": [\"loadfile\", \"%s\", \"append\"]}',
        escaped
    )

    local pipe = io.open(escaped_ipc_server, "w")
    if not pipe then
        msg.error("Failed to connect to main instance IPC server --", escaped_ipc_server)
        return false
    end

    msg.info("Sending IPC append command to main instance --", ipc_command)
    pipe:write(ipc_command .. "\n")
    pipe:close()
end

function On_Start_File()
    local file_path = mp.get_property("path") or ""
    local file_ext = file_path:match("%.([^%.]+)$")

    if file_ext == "" then
        msg.warn("Failed to parse file extension")
        return false
    end

    if not is_main_instance then
        for key in ipairs(video_ext) do
            if video_ext[key] == file_ext then
                send_file_to_main(file_path)
                msg.info("Closing secondary instance")
                return mp.commandv("quit")
            end
        end
    end

    msg.info("Proceeding to regular operation as main instance")
end

setup_instance()
mp.register_event("start-file", On_Start_File)
