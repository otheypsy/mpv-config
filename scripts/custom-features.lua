local options = require "mp.options"
local assdraw = require "mp.assdraw"
local msg = require "mp.msg"
local utils = require "mp.utils"

local opts = {
    alignment          = 3,
    refresh_interval   = 30,
    display_font_size  = 40,
    display_font_color = "FFFFFF",
    backdrop_opacity   = 0.8,
    backdrop_x_pad     = 10,
    backdrop_y_pad     = 5,
    backdrop_color     = 000000,
    z_index            = 1.0
}
options.read_options(opts, "custom-features")

local platform = mp.get_property("platform")
local overlay = mp.create_osd_overlay("ass-events")
local draw_ui_timer = nil
local scaled_font_size = opts.display_font_size

local function set_style(ass)
    local backdrop_alpha = math.ceil(255 * (1 - opts.backdrop_opacity))
    ass:an(opts.alignment)
    ass:append(
        string.format(
            "{\\fs%s}{\\1c&H%s&}" ..
            "{\\4c&H%s&}{\\4a&H%X&}" ..
            "{\\xshad8}{\\yshad4}",
            scaled_font_size, opts.display_font_color,
            opts.backdrop_color, backdrop_alpha,
            opts.backdrop_x_pad, opts.backdrop_y_pad
        )
    )
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
    local ass = assdraw.ass_new()

    set_style(ass)
    append_date_time(ass)
    ass:append("\\N")
    append_profiles(ass)

    overlay.data = ass.text
    overlay.z = opts.z_index
    local osd_border = mp.get_property("osd-border-style")

    mp.set_property("osd-border-style", "background-box")
    overlay:update()
    mp.set_property("osd-border-style", osd_border or "outline-and-shadow")
end

local function check_draw_ui_timer()
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

local function on_change_osd_height()
    local osd_height = mp.get_property_native("osd-height") or 0
    if osd_height > 720 then
        scaled_font_size = math.ceil(opts.display_font_size * (720 / osd_height))
    end
    check_draw_ui_timer()
    draw_ui()
end
mp.observe_property("osd-height", "native", on_change_osd_height)

local function on_change_active_profiles()
    check_draw_ui_timer()
    draw_ui()
end
mp.observe_property(
    "user-data/custom_auto_profiles/active_profiles",
    "native",
    on_change_active_profiles
)

local function windows_explorer_open(path)
    local path_info = utils.file_info(path)

    if not path_info.is_dir then
        msg.error("Derived path is not a directory", utils.format_json(path_info))
        return false
    end

    if platform ~= "windows" then
        msg.error("Feature only available on Windows")
        return false
    end

    mp.commandv("run", "explorer.exe", path)
end

local function open_config_folder()
    if not mp.get_property_bool("config") then
        mp.msg.warn("No config folder for --no-config instances")
        return false
    end
    local path = mp.command_native({ "expand-path", "~~/" })
    windows_explorer_open(path)
end

local function open_content_folder()
    local path = mp.get_property_native("path") or ""
    path = path:match("(.*[/\\])")
    if not path then
        mp.msg.warn("Could not get file's parent directory")
        return false
    end
    msg.info(path)
    windows_explorer_open(path)
end

local function on_script_message(arg1, arg2)
    if arg1 == "open" and arg2 == "config-dir" then
        open_config_folder()
    end

    if arg1 == "open" and arg2 == "content-dir" then
        open_content_folder()
    end

    if arg1 == "toggle-footer" then
        if arg2 == "show" then
            check_draw_ui_timer()
            draw_ui()
        end

        if arg2 == "hide" then
            if draw_ui_timer then
                draw_ui_timer:stop()
            end
            overlay:remove()
        end
    end

    if arg1 == "toggle-shaders" then
        if mp.get_property_bool("user-data/shaders/active") then
            mp.set_property_bool("user-data/shaders/active", false)
        else
            mp.set_property_bool("user-data/shaders/active", true)
        end
    end
end

mp.register_script_message("custom-features", on_script_message)
