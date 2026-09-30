local options = require "mp.options"
local assdraw = require "mp.assdraw"
local msg = require "mp.msg"
local utils = require "mp.utils"

local opts = {
    alignment = 3,
    refresh_interval = 30,
    display_font_size = 40,
    z_index = 1.0
}
options.read_options(opts, "custom-features")

local platform = mp.get_property("platform")
local overlay = mp.create_osd_overlay("ass-events")
local draw_ui_timer = nil
local scaled_font_size = opts.display_font_size

local function set_style(ass)
    ass:an(opts.alignment)
    ass:append(string.format("{\\fs%s}{\\1c&FFFFFF&}", scaled_font_size))
    ass:append("{\\4c&111111&}{\\4a&H66}{\\xshad8}{\\yshad4}")
end

local function append_date_time(ass)
    local time_string = os.date("%I:%M %p \u{22EE} %A \u{22EE} %B %d, %Y")
    if not time_string then
        return false
    end

    ass:append(time_string)
end

local function append_profiles(ass)
    local active_profiles = mp.get_property_native(
        "user-data/custom_auto_profiles/active_profiles"
    )
    if not active_profiles then
        return false
    end

    ass:append(table.concat(active_profiles, " \u{22EE} "))
end

local function draw_ui()
    local default_osd_border_style = mp.get_property("osd-border-style") or
        "outline-and-shadow"
    mp.set_property("osd-border-style", "background-box")
    local ass = assdraw.ass_new()

    set_style(ass)
    append_date_time(ass)
    ass:append("\\N")
    append_profiles(ass)

    overlay.data = ass.text
    overlay.z = opts.z_index
    overlay:update()
    mp.set_property("osd-border-style", default_osd_border_style)
end

local function on_change_osd_height()
    local osd_height = mp.get_property_native("osd-height") or 0
    if osd_height > 0 then
        scaled_font_size = math.ceil(opts.display_font_size * 720 / osd_height)
    end
    draw_ui()
end
mp.observe_property("osd-height", "native", on_change_osd_height)

local function on_change_active_profiles()
    draw_ui()
    if not draw_ui_timer then
        draw_ui_timer = mp.add_periodic_timer(
            opts.refresh_interval,
            draw_ui
        )
    end
    if not draw_ui_timer:is_enabled() then
        draw_ui_timer:resume()
    end
end
mp.observe_property(
    "user-data/custom_auto_profiles/active_profiles",
    "native",
    on_change_active_profiles
)

local function system_open(path)
    local args
    if platform == "windows" then
        args = { "rundll32", "url.dll,FileProtocolHandler", path }
    elseif platform == "darwin" then
        args = { "open", path }
    else
        args = { "gio", "open", path }
    end

    mp.commandv("run", table.unpack(args))
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

    if arg1 == "toggle-footer" then
        if arg2 == "show" then
            draw_ui()
        end

        if arg2 == "hide" then
            if draw_ui_timer then
                draw_ui_timer:stop()
            end
            overlay:remove()
        end
    end
end
mp.register_script_message("custom-features", on_script_message)
