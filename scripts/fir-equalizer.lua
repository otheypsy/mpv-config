--[[
Linear Phase 15-Bands Equalizer
Key:
   - toggle equalizer control: ctrl+e
   - prev/next gain control: UP / DOWN
   - decrease/increase gain: LEFT / RIGHT
   - copy gain value from prev gain control: [
   - copy gain value from next gain control: ]
Note that ~~/lua-settings directory should exist to save gain values.
--]]

local assdraw = require "mp.assdraw"
local options = require "mp.options"
local msg     = require "mp.msg"

local opts    = {
    alignment          = 7,
    normal_color       = "B1ACA7",
    selected_color     = "DD78C6",
    font_family        = "monospace",
    font_size          = 40,

    key_toggle_control = "ctrl+e",
    key_prev_entry     = "UP",
    key_next_entry     = "DOWN",
    key_decrease       = "LEFT",
    key_increase       = "RIGHT",
    key_copy_prev      = "[",
    key_copy_next      = "]",
    key_close_eq       = "ESC",
}

options.read_options(opts, "fir-equalizer")

local control_enabled       = false
local num_entry             = 15
local selected_entry        = 0
local min_val               = -360
local max_val               = 120
local scaled_font_size      = opts.font_size
local stale_gain_entry      = ""
local gain_table            = {}
local saved_gain_table_file = "fir-equalizer-presets/default"
local overlay               = mp.create_osd_overlay("ass-events")
local db_icon               = "{\\fscy75}\u{33C8}{\\fscx100}{\\fscy100}"
local hz_icon               = "{\\alpha&H66&}Hz{\\alpha&H00&}"
local right_arrow           = "   {\\fscx150}{\\fscy130}\u{27FF}{\\fscx100}{\\fscy100}   "

-- local hz_icon  = "{\\fscy75}\u{3390}{\\fscx100}{\\fscy100}"
-- local khz_icon = "{\\fscx115}{\\fscy75}\u{3391}{\\fscx100}{\\fscy100}"
-- local double_arrow = "{\\fscx200}{\\fscy130}\u{21AD}{\\fscx100}{\\fscy100}"

local function eq(x)
    return "eq" .. x
end

local freq_label = {
    "0", "65", "157", "288", "472", "733", "1001", "1006",
    "2004", "3004", "4009", "7000", "10000", "14000", "20000"
}

local function init_gain_table()
    for index = 0, num_entry - 1 do
        gain_table["eq" .. index] = 0
    end
end
init_gain_table()

if saved_gain_table_file then
    options.read_options(gain_table, saved_gain_table_file)
end

local function set_styles(ass, isSelected)
    ass:an(opts.alignment)
    ass:append(
        string.format(
            "{\\fn%s}{\\fs%d}{\\1c&H%s&}",
            opts.font_family,
            scaled_font_size,
            isSelected and opts.selected_color or opts.normal_color
        )
    )
end

--[[
local function gain_line(x)
    local val = gain_table[eq(x)] - min_val;
    local str =
    "\u{2770}\u{2770}\u{2985}{\\fscx120}{\\fscy120}\u{2756}\u{229B}\u{29F3}{\\fscx100}{\\fscy100}\u{29BF}\u{2771}\u{2771}\u{2771}"
    local x = 5
    while x <= val do
        str = str .. "\u{2771}"
        x = x + 20
    end
    return str
end
]]
local function gain_line(x)
    local val = gain_table[eq(x)] * 0.1;

    local zero = " \u{23FA} "
    zero = (val < 0) and " \u{25D0} " or zero
    zero = (val > 0) and " \u{25D1} " or zero

    local below = ""
    local above = ""

    for step = (min_val * 0.1), -1 do
        below = below .. (
            (step <= val)
            and "{\\alpha&HDD&}\u{2770}{\\alpha&H00&}"
            or "\u{2770}"
        )
    end

    for step = 1, (max_val * 0.1) do
        above = above .. (
            (step >= val)
            and "{\\alpha&HDD&}\u{2771}{\\alpha&H00&}"
            or "\u{2771}"
        )
    end

    return below .. zero .. above
end

local function draw_backdrop(ass)
    local w, h, _ = mp.get_osd_size()
    local alpha = math.ceil(255 * 0.2)

    ass.text = ass.text .. string.format(
        "{\\pos(0,0)\\rDefault\\an7\\1c&H000000&\\alpha&H%X&}", alpha)
    ass:draw_start()
    ass:rect_cw(0, 0, w, h)
    ass:draw_stop()
end

local function draw_equalizer(ass)
    set_styles(ass, false)
    ass:append(
        "{\\fscx150}{\\fscy150}Linear Phase 15-Bands Equalizer{\\fscx100}{\\fscy100}")

    ass:append("\\N\\N")
    for x = 0, num_entry - 1 do
        ass:new_event()
        set_styles(ass, (selected_entry == x))

        ass:append(
            string.format(
                " \u{1D742} \u{22EE} %5s %2s \u{22EE} %s ",
                freq_label[x + 1],
                hz_icon,
                right_arrow
            )
        )
        ass:append(
            string.format(
                "\u{22EE} %5.1f %s \u{22EE}  %s  %-48s \n",
                gain_table[eq(x)] * 0.1,
                db_icon,
                right_arrow,
                gain_line(x)
            )

        )
    end
end

local function gen_gain_entry()
    local str = string.format("entry(0,%.1f)", gain_table[eq(0)] * 0.1)
    for x = 1, num_entry - 1 do
        str = str .. string.format(";entry(%d,%.1f)", x, gain_table[eq(x)] * 0.1)
    end
    return str
end

local function insert_filter(gain_entry)
    local graph = "firequalizer = " ..
        "wfunc      = tukey:" ..
        "delay      = 0.028:" ..
        "scale      = linlog:" ..
        "zero_phase = on:" ..
        "gain_entry = '" .. gain_entry .. "':" ..
        "gain       = 'cubic_interpolate(2.8853900817779269*log(f/157.48+1))'"
    mp.commandv(
        "af", "add",
        "@" .. mp.get_script_name() .. ":lavfi=graph=[" .. graph .. "]"
    )
end

local function send_command()
    mp.commandv(
        "af-command",
        mp.get_script_name(),
        "gain_entry",
        gen_gain_entry()
    )
end

local function save_gain_table()
    local path = mp.command_native({
        "expand-path",
        "~~/script-opts/" .. saved_gain_table_file .. ".conf"
    }) or ""
    local fp = path and
        io.open(path, "w")
    if fp == nil then
        msg.warn("Cannot save gain table.")
    else
        for x = 0, num_entry - 1 do
            fp:write(eq(x) .. "=" .. gain_table[eq(x)] .. "\n")
        end
        fp:close()
    end
end

local function binding_name(name)
    return mp.get_script_name() .. "-" .. name
end

local function show_equalizer()
    local ass = assdraw.ass_new()
    draw_backdrop(ass)
    ass:new_event()
    draw_equalizer(ass)
    overlay.data = ass.text
    overlay.z = -1
    overlay:update()
    control_enabled = true
end

local function remove_temp_keybinds()
    mp.remove_key_binding(binding_name("prev"))
    mp.remove_key_binding(binding_name("next"))
    mp.remove_key_binding(binding_name("decrease"))
    mp.remove_key_binding(binding_name("increase"))
    mp.remove_key_binding(binding_name("copy_prev"))
    mp.remove_key_binding(binding_name("copy_next"))
    mp.remove_key_binding(binding_name("close_eq"))
end

local function hide_equalizer()
    remove_temp_keybinds()
    overlay.data = ""
    overlay:remove()
    control_enabled = false
end

local function prev_entry()
    selected_entry = math.max(selected_entry - 1, 0)
    show_equalizer()
end

local function next_entry()
    selected_entry = math.min(
        selected_entry + 1,
        num_entry - 1
    )
    show_equalizer()
end

local function decrease_gain()
    gain_table[eq(selected_entry)] = math.max(
        gain_table[eq(selected_entry)] - 1,
        min_val
    )
    send_command()
    show_equalizer()
    save_gain_table()
end

local function increase_gain()
    gain_table[eq(selected_entry)] = math.min(
        gain_table[eq(selected_entry)] + 1,
        max_val
    )
    send_command()
    show_equalizer()
    save_gain_table()
end

local function copy_prev()
    gain_table[eq(selected_entry)] = gain_table
        [eq(math.max(selected_entry - 1, 0))]
    send_command()
    show_equalizer()
    save_gain_table()
end

local function copy_next()
    gain_table[eq(selected_entry)] = gain_table
        [eq(math.min(selected_entry + 1, num_entry - 1))]
    send_command()
    show_equalizer()
    save_gain_table()
end

local function add_temp_keybinds()
    mp.add_forced_key_binding(
        opts.key_prev_entry,
        binding_name("prev"),
        prev_entry,
        { repeatable = true }
    )
    mp.add_forced_key_binding(
        opts.key_next_entry,
        binding_name("next"),
        next_entry,
        { repeatable = true }
    )
    mp.add_forced_key_binding(
        opts.key_decrease,
        binding_name("decrease"),
        decrease_gain,
        { repeatable = true }
    )
    mp.add_forced_key_binding(
        opts.key_increase,
        binding_name("increase"),
        increase_gain,
        { repeatable = true }
    )
    mp.add_forced_key_binding(
        opts.key_copy_prev,
        binding_name("copy_prev"),
        copy_prev
    )
    mp.add_forced_key_binding(
        opts.key_copy_next,
        binding_name("copy_next"),
        copy_next
    )
    mp.add_forced_key_binding(
        opts.key_close_eq,
        binding_name("close_eq"),
        hide_equalizer
    )
end


local function toggle_control()
    if not control_enabled then
        add_temp_keybinds()
        show_equalizer()
    else
        remove_temp_keybinds()
        hide_equalizer()
    end
end

mp.add_forced_key_binding(
    opts.key_toggle_control,
    binding_name("toggle_control"),
    toggle_control
)

local function On_Playback_Restart()
    local gain_entry = gen_gain_entry()
    if not (stale_gain_entry == gain_entry) then
        insert_filter(gain_entry)
        stale_gain_entry = gain_entry
    end
end

On_Playback_Restart()
mp.register_event("playback-restart", On_Playback_Restart)

local function on_change_osd_height()
    local osd_height = mp.get_property_native("osd-height") or 0
    if osd_height > 720 then
        scaled_font_size = math.ceil(opts.font_size * (720 / osd_height))
    end
    if control_enabled then
        show_equalizer()
    end
end
mp.observe_property("osd-height", "native", on_change_osd_height)
on_change_osd_height()
