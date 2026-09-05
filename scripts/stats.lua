-- Display some stats.
--
-- Please consult the readme for information about usage and configuration:
-- https://github.com/Argon-/mpv-stats
--
-- Please note: not every property is always available and therefore not always
-- visible.

local mp = require "mp"
local utils = require "mp.utils"
local input = require "mp.input"

-- Options
local o = {
    -- Default key bindings
    key_page_1 = "1",
    key_page_2 = "2",
    key_page_3 = "3",
    key_page_4 = "4",
    key_page_5 = "5",
    key_page_0 = "0",
    -- For pages which support scrolling
    key_scroll_up = "UP",
    key_scroll_down = "DOWN",
    key_search = "/",
    key_exit = "ESC",
    scroll_lines = 1,

    duration = 4,
    redraw_delay = 1,                -- acts as duration in the toggling case
    ass_formatting = true,
    persistent_overlay = false,      -- whether the stats can be overwritten by other output
    filter_params_max_length = 100,  -- show one filter per line if list exceeds this length
    file_tag_max_length = 128,       -- only show file tags shorter than this length in bytes
    file_tag_max_count = 16,         -- only show the first x file tags
    show_frame_info = false,         -- whether to show the current frame info
    term_clip = true,
    track_info_selected_only = true, -- only show selected track info
    debug = false,

    -- Graph options and style
    plot_perfdata = false,
    plot_vsync_ratio = false,
    plot_vsync_jitter = false,
    plot_cache = true,
    plot_tonemapping_lut = false,
    skip_frames = 5,
    global_max = true,
    flush_graph_data = true, -- clear data buffers when toggling
    plot_bg_border_color = "292521",
    plot_bg_color = "000000",
    plot_color = "6ADAFF",
    plot_bg_border_width = 1.00,

    -- Text style
    font = "",
    font_mono = "monospace", -- monospaced digits are sufficient
    font_size = 20,
    font_padding = 2,
    font_color = "F6DF6E",
    font_highlight_color = "98B775",
    font_secondary_highlight_color = "FEA86E",
    font_alert_color = "8F86EA",
    border_size = 0.50,
    border_color = "",
    shadow_x_offset = math.huge,
    shadow_y_offset = math.huge,
    shadow_color = "",
    alpha = "11",
    vidscale = "auto",

    -- Custom header for ASS tags to style the text output.
    -- Specifying this will ignore the text style values above and just
    -- use this string instead.
    custom_header = "",

    -- Text formatting
    -- With ASS
    ass_nl = "\\N",
    ass_indent = "\\h\\h\\h\\h\\h",
    ass_prefix_sep = "\\h\\h",
    ass_b1 = "{\\b1}",
    ass_b0 = "{\\b0}",
    ass_it1 = "{\\i1}",
    ass_it0 = "{\\i0}",
    -- Without ASS
    no_ass_nl = "\n",
    no_ass_indent = "    ",
    no_ass_prefix_sep = " ",
    no_ass_b1 = "\027[1m",
    no_ass_b0 = "\027[0m",
    no_ass_it1 = "\027[3m",
    no_ass_it0 = "\027[0m",

    bindlist = "no", -- print page 4 to the terminal on startup and quit mpv
}

local update_scale
require "mp.options".read_options(o, nil, function()
    update_scale()
end)

local format = string.format
local max = math.max
local min = math.min

-- Scaled metrics
local font_size = o.font_size
local border_size = o.border_size
local shadow_x_offset = o.shadow_x_offset
local shadow_y_offset = o.shadow_y_offset
local plot_bg_border_width = o.plot_bg_border_width
-- Function used to record performance data
local recorder = nil
-- Timer used for redrawing (toggling) and clearing the screen (oneshot)
local display_timer = nil
-- Timer used to update cache stats.
local cache_recorder_timer
-- Current page and <page key>:<page function> mappings
local curr_page = o.key_page_1
local pages = {}
local scroll_bound = false
local searched_text
local tm_viz_prev = nil
-- Save these sequences locally as we'll need them a lot
local ass_start = mp.get_property_osd("osd-ass-cc/0")
local ass_stop = mp.get_property_osd("osd-ass-cc/1")
-- Ring buffers for the values used to construct a graph.
-- .pos denotes the current position, .len the buffer length
-- .max is the max value in the corresponding buffer
local vsratio_buf, vsjitter_buf
local function init_buffers()
    vsratio_buf = { 0, pos = 1, len = 50, max = 0 }
    vsjitter_buf = { 0, pos = 1, len = 50, max = 0 }
end
local cache_ahead_buf, cache_speed_buf
local perf_buffers = {}
local process_key_binding

local property_cache = {}
local profiles = {}
local profiles_max_length = 0

local function get_property_cached(name, def)
    if property_cache[name] ~= nil then
        return property_cache[name]
    end
    return def
end

local function graph_add_value(graph, value)
    graph.pos = (graph.pos % graph.len) + 1
    graph[graph.pos] = value
    graph.max = max(graph.max, value)
end

local function no_ASS(t)
    if not o.use_ass then
        return t
    elseif not o.persistent_overlay then
        -- mp.osd_message supports ass-escape using osd-ass-cc/{0|1}
        return ass_stop .. t .. ass_start
    else
        return mp.command_native({ "escape-ass", tostring(t) })
    end
end


local function bold(t)
    return o.b1 .. t .. o.b0
end


local function it(t)
    return o.it1 .. t .. o.it0
end


local function text_style()
    if not o.use_ass then
        return ""
    end
    if o.custom_header and o.custom_header ~= "" then
        return o.custom_header
    else
        local style = "{\\r\\an7\\fs" .. font_size .. "\\bord" .. border_size

        if o.font ~= "" then
            style = style .. "\\fn" .. o.font
        end

        if o.font_color ~= "" then
            style = style .. "\\1c&H" .. o.font_color .. "&\\1a&H" .. o.alpha .. "&"
        end

        if o.border_color ~= "" then
            style = style .. "\\3c&H" .. o.border_color .. "&\\3a&H" .. o.alpha .. "&"
        end

        if o.shadow_color ~= "" then
            style = style .. "\\4c&H" .. o.shadow_color .. "&\\4a&H" .. o.alpha .. "&"
        end

        if o.shadow_x_offset < math.huge then
            style = style .. "\\xshad" .. shadow_x_offset
        end

        if o.shadow_y_offset < math.huge then
            style = style .. "\\yshad" .. shadow_y_offset
        end

        return style .. "}"
    end
end


local function has_vo_window()
    return mp.get_property_native("vo-configured") and mp.get_property_native("video-osd")
end


-- Generate a graph from the given values.
-- Returns an ASS formatted vector drawing as string.
--
-- values: Array/table of numbers representing the data. Used like a ring buffer
--         it will get iterated backwards `len` times starting at position `i`.
-- i     : Index of the latest data value in `values`.
-- len   : The length/amount of numbers in `values`.
-- v_max : The maximum number in `values`. It is used to scale all data
--         values to a range of 0 to `v_max`.
-- v_avg : The average number in `values`. It is used to try and center graphs
--         if possible. May be left as nil
-- scale : A value that will be multiplied with all data values.
-- x_tics: Horizontal width multiplier for the steps
local function generate_graph(values, i, len, v_max, v_avg, scale, x_tics, max_values)
    -- Check if at least one value exists
    if not values[i] then
        return ""
    end

    local x_max = (max_values or 50) * x_tics
    local y_max = font_size * 0.66
    local y_offset = plot_bg_border_width * 2
    local x = -x_max


    if v_max > 0 then
        -- try and center the graph if possible, but avoid going above `scale`
        if v_avg and v_avg > 0 then
            scale = min(scale, v_max / (2 * v_avg))
        end
        scale = scale * y_max / v_max
    end -- else if v_max==0 then all values are 0 and scale doesn't matter


    local s = { format("%s{\\rDefault}{\\pbo%f}{\\shad0}", o.prefix_sep, y_offset) }
    s[#s] = s[#s] .. format("{\\bord%f}{\\3c&H%s&}{\\1c&H%s&}{\\1a&H99}{\\p1}m 0 %f l %f %f %f 0 0 0 m 0 %f ",
                            plot_bg_border_width, o.plot_bg_border_color, o.plot_bg_color,
                            y_max, x_max, y_max, x_max, y_max)

    s[#s] = s[#s] .. format("{\\bord0}{\\1a&H00}{\\1c&H%s&}", o.plot_color)
    s[#s] = s[#s] .. format("m 0 0 n %f %f l ", x, y_max - scale * values[i])

    i = ((i - 2) % len) + 1

    for _ = 1, len - 1 do
        if values[i] then
            x = x + x_tics
            s[#s] = s[#s] .. format("%f %f ", x, y_max - scale * values[i])
        end
        i = ((i - 2) % len) + 1
    end

    s[#s] = s[#s] .. format("%f %f %f %f m %f %f{\\p0}", x, y_max, -x_max, y_max, 0, 0)

    return format("%s%s", table.concat(s), text_style())


    --[[
    return format("%s{\\rDefault}{\\bord0}{\\1c&H%s}{\\p1}%s{\\p0}%s",
        o.prefix_sep, o.plot_color, table.concat(s), text_style())
	--]]
end


local function append(s, str, attr)
    if not str then
        return false
    end
    attr.prefix_sep = attr.prefix_sep or o.prefix_sep
    attr.indent = attr.indent or o.indent
    attr.nl = attr.nl or o.nl
    attr.suffix = attr.suffix or ""
    attr.prefix = attr.prefix or ""
    attr.no_prefix_markup = attr.no_prefix_markup or false
    attr.bold = attr.bold or false
    attr.prefix = (attr.no_prefix_markup and attr.no_bold) and attr.prefix or bold(attr.prefix)

    local base_color = format("{\\1c&H%s&}", o.font_color)
    local highlight_color = base_color
    if not attr.no_prefix_markup then
        highlight_color = format("{\\1c&H%s&}", o.font_highlight_color)
    end

    if attr.second_highlight then
        highlight_color = format("{\\1c&H%s&}", o.font_secondary_highlight_color)
    end

    local index = #s + (attr.nl == "" and 0 or 1)
    s[index] = s[index] or ""
    s[index] = s[index] .. format("%s%s%s%s%s%s%s%s", attr.nl, attr.indent,
                                  highlight_color, attr.prefix,
                                  attr.prefix_sep, no_ASS(str), attr.suffix, base_color)
    return true
end


-- Format and append a property.
-- A property whose value is either `nil` or empty (hereafter called "invalid")
-- is skipped and not appended.
-- Returns `false` in case nothing was appended, otherwise `true`.
--
-- s      : Table containing strings.
-- prop   : The property to query and format (based on its OSD representation).
-- attr   : Optional table to overwrite certain (formatting) attributes for
--          this property.
-- exclude: Optional table containing keys which are considered invalid values
--          for this property. Specifying this will replace empty string as
--          default invalid value (nil is always invalid).
-- cached : If true, use get_property_cached instead of get_property_osd
local function append_property(s, prop, attr, excluded, cached)
    excluded = excluded or { [""] = true }
    local ret
    if cached then
        ret = get_property_cached(prop)
    else
        ret = mp.get_property_osd(prop)
    end
    if not ret or excluded[ret] then
        if o.debug then
            print("No value for property: " .. prop)
        end
        return false
    end
    return append(s, ret, attr)
end

local function sorted_keys(t, comp_fn)
    local keys = {}
    for k, _ in pairs(t) do
        keys[#keys + 1] = k
    end
    table.sort(keys, comp_fn)
    return keys
end

local function scroll_hint(search)
    local hint = format("(Hint: Scroll with %s/%s", o.key_scroll_up, o.key_scroll_down)
    if search then
        hint = hint .. " and search with " .. o.key_search
    end
    hint = hint .. ")"
    if not o.use_ass then return " " .. hint end
    return format(" {\\fs%s}%s{\\fs%s}", font_size * 0.8, hint, font_size)
end

local function append_perfdata(header, s, dedicated_page)
    local vo_p = mp.get_property_native("vo-passes")
    if not vo_p then
        return
    end

    local base_color = format("{\\1c&H%s&}", o.font_color)
    local warn_color = format("{\\1c&H%s&}", o.font_highlight_color)
    local alert_color = format("{\\1c&H%s&}", o.font_alert_color)

    -- Sums of all last/avg/peak values
    local last_s, avg_s, peak_s = {}, {}, {}
    for frame, data in pairs(vo_p) do
        last_s[frame], avg_s[frame], peak_s[frame] = 0, 0, 0
        for _, pass in ipairs(data) do
            last_s[frame] = last_s[frame] + pass["last"]
            avg_s[frame] = avg_s[frame] + pass["avg"]
            peak_s[frame] = peak_s[frame] + pass["peak"]
        end
    end

    -- Pretty print measured time
    local function pp(i)
        -- rescale to microseconds for a saner display
        return format("%4d", i / 1000)
    end

    -- Format n/m with a font weight based on the ratio
    local function ratio_styling(n, m)
        local i = 0
        if m > 0 then
            i = tonumber(n) / m
        end

        local p_bold = (i >= 0.3) and 1 or 0
        local p_color = (i >= 0.3) and warn_color or base_color
        p_color = (i >= 0.6) and alert_color or p_color
        return format("%s{\\b%d}", p_color, p_bold)
    end

    local function p(n, m)
        local i = 0
        if m > 0 then
            i = tonumber(n) / m
        end

        return format("%3d%%", i * 100)
    end

    local font_small = o.use_ass and format("{\\fs%s}", font_size * 0.8) or ""
    local font_normal = o.use_ass and format("{\\fs%s}", font_size) or ""
    local font = o.use_ass and format("{\\fn%s}", o.font) or ""

    -- ensure that the fixed title is one element and every scrollable line is
    -- also one single element.
    local h = dedicated_page and header or s
    local f = "%s%s%s%s%s%s%s%s%s%s  %s   %s   %s"

    if dedicated_page then
        h[#h + 1] = format("{\\1c&H%s&}", o.font_highlight_color)
        h[#h + 1] = format("%s", bold("Frame Timings: "))
        h[#h] = h[#h] .. format(f .. "%s%s",
                                " ", " ", " ", o.indent, o.indent, o.indent,
                                o.prefix_sep, o.prefix_sep, o.prefix_sep,
                                "last", " avg", "peak", o.indent, o.indent, scroll_hint())
        h[#h + 1] = format("%s%s%s%s%s%s%s%s%s%s  %s   %s   %s",
                           o.nl, o.indent, o.indent,
                           o.indent, o.indent, o.indent, o.indent, o.prefix_sep, o.prefix_sep, " ",
                           "----", "----", "----")
        h[#h + 1] = format("{\\1c&H%s&}", o.font_color)
    else
        h[#h + 1] = format("%s%s%s%s%s",
                           bold("Frame Timings:"), o.prefix_sep,
                           font_small, "(last | average | peak) in μs", font_normal)
    end

    for _, frame in ipairs(sorted_keys(vo_p)) do -- ensure fixed display order
        local data = vo_p[frame]

        if dedicated_page then
            s[#s + 1] = format("%s%s{\\1c&H%s&}%s:{\\1c&H%s&}%s", o.nl, o.prefix_sep, o.font_highlight_color,
                               bold(frame:gsub("^%l", string.upper)), o.font_color, o.nl)

            for _, pass in ipairs(data) do
                s[#s + 1] = format("%s", o.nl)
                if o.plot_perfdata and o.use_ass then
                    s[#s] = s[#s] .. generate_graph(pass["samples"], pass["count"],
                                                    pass["count"], pass["peak"],
                                                    pass["avg"], 0.8, 0.20, 254)
                end

                s[#s] = s[#s] ..
                    format("%s %s | %s | %s %s%s%s%s%s{\\b0}%s", ratio_styling(pass["last"], last_s[frame]),
                           pp(pass["last"]), pp(pass["avg"]), pp(pass["peak"]),
                           o.prefix_sep, p(pass["last"], last_s[frame]), o.indent, o.prefix_sep,
                           pass["desc"], base_color)
            end

            s[#s + 1] = format("%s%s%s%s%s%s%s%s%s%s  %s   %s   %s",
                               o.nl, o.indent, o.indent,
                               o.indent, o.indent, o.indent, o.indent, o.prefix_sep, o.prefix_sep, " ",
                               "----", "----", "----")

            -- Print sum of timing values as "Total"
            s[#s + 1] = format(
                "%s%s%s%s%s%s%s%s%s%s",
                o.nl, o.indent, o.indent, o.indent, o.indent, o.prefix_sep, o.prefix_sep, "  ",
                bold("Total \u{203A}\u{203A}\u{203A}  "),
                bold(pp(last_s[frame])) .. " | " .. bold(pp(avg_s[frame])) .. " | " .. bold(pp(peak_s[frame]))
            )
        else
            -- for the simplified view, we just print the sum of each pass
            s[#s + 1] = format("%s %s | %s | %s %s%s%s%s", o.nl, "", o.indent, o.indent,
                               pp(last_s[frame]), pp(avg_s[frame]), pp(peak_s[frame]),
                               "", "", font, o.prefix_sep, o.prefix_sep,
                               frame:gsub("^%l", string.upper), o.prefix_sep)
        end
    end
end

-- command prefix tokens to strip - includes generic property commands
local cmd_prefixes = {
    osd_auto = 1,
    no_osd = 1,
    osd_bar = 1,
    osd_msg = 1,
    osd_msg_bar = 1,
    raw = 1,
    sync = 1,
    async = 1,
    expand_properties = 1,
    repeatable = 1,
    nonrepeatable = 1,
    nonscalable = 1,
    set = 1,
    add = 1,
    multiply = 1,
    toggle = 1,
    cycle = 1,
    cycle_values = 1,
    ["!reverse"] = 1,
    change_list = 1,
}
-- commands/writable-properties prefix sub-words (followed by -) to strip
local name_prefixes = {
    define = 1,
    delete = 1,
    enable = 1,
    disable = 1,
    dump = 1,
    write = 1,
    drop = 1,
    revert = 1,
    ab = 1,
    hr = 1,
    secondary = 1,
    current = 1,
}
-- extract a command "subject" from a command string, by removing all
-- generic prefix tokens and then returning the first interesting sub-word
-- of the next token. For target-script name we also check another token.
-- The tokenizer works fine for things we care about - valid mpv commands,
-- properties and script names, possibly quoted, white-space[s]-separated.
-- It's decent in practice, and worst case is "incorrect" subject.
local function cmd_subject(cmd)
    cmd = cmd:gsub(";.*", ""):gsub("%-", "_") -- only first cmd, s/-/_/
    local TOKEN = '^%s*["\']?([%w_!]*)'       -- captures+ends before (maybe) final "
    local tok, sname, subw

    repeat
        tok, cmd = cmd:match(TOKEN .. '["\']?(.*)')
    until not cmd_prefixes[tok]
    -- tok is the 1st non-generic command/property name token, cmd is the rest

    sname = tok == "script_message_to" and cmd:match(TOKEN)
        or tok == "script_binding" and cmd:match(TOKEN .. "/")
    if sname and sname ~= "" then
        return "script: " .. sname
    end

    -- return the first sub-word of tok which is not a useless prefix
    repeat
        subw, tok = tok:match("([^_]*)_?(.*)")
    until tok == "" or not name_prefixes[subw]
    return subw:len() > 1 and subw or "[unknown]"
end

-- key names are valid UTF-8, ascii7 except maybe the last/only codepoint.
-- we count codepoints and ignore wcwidth. no need for grapheme clusters.
-- our error for alignment is at most one cell (if last CP is double-width).
-- (if k was valid but arbitrary: we'd count all bytes <0x80 or >=0xc0)
local function keyname_cells(k)
    local klen = k:len()
    if klen > 1 and k:byte(klen) >= 0x80 then -- last/only CP is not ascii7
        repeat
            klen = klen - 1
        until klen == 1 or k:byte(klen) >= 0xc0 -- last CP begins at klen
    end
    return klen
end

local function get_kbinfo_lines()
    -- active keys: only highest priority of each key, and not our (stats) keys
    local bindings = mp.get_property_native("input-bindings", {})
    local active = {} -- map: key-name -> bind-info
    for _, bind in pairs(bindings) do
        if  bind.priority >= 0 and (
            not active[bind.key] or
            (active[bind.key].is_weak and not bind.is_weak) or
            (bind.is_weak == active[bind.key].is_weak and
                bind.priority > active[bind.key].priority)
        ) and not bind.cmd:find("script-binding stats/__forced_", 1, true)
        and bind.section ~= "input_forced_console"
        and (
            searched_text == nil or
            (bind.key .. bind.cmd .. (bind.comment or "")):lower():find(searched_text, 1, true)
        )
        then
            active[bind.key] = bind
        end
    end

    -- make an array, find max key len, add sort keys (.subject/.mods[_count])
    local ordered = {}
    local kspaces = "" -- as many spaces as the longest key name
    for _, bind in pairs(active) do
        bind.subject = cmd_subject(bind.cmd)
        if bind.subject ~= "ignore" then
            ordered[#ordered + 1] = bind
            _, _, bind.mods = bind.key:find("(.*)%+.")
            _, bind.mods_count = bind.key:gsub("%+.", "")
            if bind.key:len() > kspaces:len() then
                kspaces = string.rep(" ", bind.key:len())
            end
        end
    end

    local function align_right(key)
        return kspaces:sub(keyname_cells(key)) .. key
    end

    -- sort by: subject, mod(ifier)s count, mods, key-len, lowercase-key, key
    table.sort(ordered, function(a, b)
        if a.subject ~= b.subject then
            return a.subject < b.subject
        elseif a.mods_count ~= b.mods_count then
            return a.mods_count < b.mods_count
        elseif a.mods ~= b.mods then
            return a.mods < b.mods
        elseif a.key:len() ~= b.key:len() then
            return a.key:len() < b.key:len()
        elseif a.key:lower() ~= b.key:lower() then
            return a.key:lower() < b.key:lower()
        else
            return a.key > b.key -- only case differs, lowercase first
        end
    end)

    -- key/subject pre/post formatting for terminal/ass.
    -- key/subject alignment uses spaces (with mono font if ass)
    -- word-wrapping is disabled for ass, or cut at 79 for the terminal
    local LTR = string.char(0xE2, 0x80, 0x8E) -- U+200E Left To Right mark
    local term = not o.use_ass
    local kpre = term and "" or format("{\\q2\\fn%s}%s", o.font_mono, LTR)
    local kpost = term and " " or format(" {\\fn%s}", o.font)
    local spre = term and kspaces .. "   "
        or format("{\\q2\\fn%s}%s   {\\fn%s}{\\fs%d\\u1}",
                  o.font_mono, kspaces, o.font, 1.3 * font_size)
    local spost = term and "" or format("{\\u0\\fs%d}%s", font_size, text_style())

    -- create the display lines
    local info_lines = {}
    local subject = nil
    for _, bind in ipairs(ordered) do
        if bind.subject ~= subject then -- new subject (title)
            subject = bind.subject
            append(info_lines, "", {})
            append(info_lines, "",
                   {
                       prefix = spre .. subject .. spost,
                       no_prefix_markup = false,
                       no_bold = false,
                       second_highlight = false
                   }
            )
        end
        if bind.comment then
            bind.cmd = bind.cmd .. "  # " .. bind.comment
        end
        append(info_lines, bind.cmd,
               {
                   prefix = kpre .. no_ASS(align_right(bind.key)) .. kpost,
                   no_prefix_markup = true,
                   no_bold = false,
                   second_highlight = false
               }
        )
    end
    return info_lines
end

local function append_general_perfdata(s)
    for i, data in ipairs(mp.get_property_native("perf-info") or {}) do
        append(s, data.text or data.value, { prefix = "[" .. tostring(i) .. "] " .. data.name .. ":" })

        if o.plot_perfdata and o.use_ass and data.value then
            local buf = perf_buffers[data.name]
            if not buf then
                buf = { 0, pos = 1, len = 50, max = 0 }
                perf_buffers[data.name] = buf
            end
            graph_add_value(buf, data.value)
            s[#s] = s[#s] .. generate_graph(buf, buf.pos, buf.len, buf.max, nil, 0.8, 1)
        end
    end
end

local function append_display_sync(s)
    if not mp.get_property_bool("display-sync-active", false) then
        return
    end

    local vspeed = append_property(
        s,
        "video-speed-correction",
        {
            prefix = "DS:",
            no_prefix_markup = true,
            no_bold = true,
            second_highlight = false
        }
    )
    if vspeed then
        append_property(
            s,
            "audio-speed-correction",
            {
                prefix = "/",
                nl = "",
                indent = " ",
                prefix_sep = " ",
                no_prefix_markup = true,
                no_bold = true,
                second_highlight = false
            }
        )
    else
        append_property(
            s, "audio-speed-correction",
            {
                prefix = "DS:" .. o.prefix_sep .. " - / ",
                prefix_sep = "",
                no_prefix_markup = true,
                no_bold = true,
                second_highlight = false
            }
        )
    end

    append_property(s, "mistimed-frame-count", {
        prefix = "Mistimed:",
        nl = "",
        indent = o.prefix_sep .. o.prefix_sep,
        no_prefix_markup = true,
        no_bold = true,
        second_highlight = false
    })
    append_property(s, "vo-delayed-frame-count", {
        prefix = "Delayed:",
        nl = "",
        indent = o.prefix_sep .. o.prefix_sep,
        no_prefix_markup = true,
        no_bold = true,
        second_highlight = false
    })

    -- As we need to plot some graphs we print jitter and ratio on their own lines
    if display_timer and not display_timer.oneshot and (o.plot_vsync_ratio or o.plot_vsync_jitter) and o.use_ass then
        local ratio_graph = ""
        local jitter_graph = ""
        if o.plot_vsync_ratio then
            ratio_graph = generate_graph(vsratio_buf, vsratio_buf.pos,
                                         vsratio_buf.len, vsratio_buf.max, nil, 0.8, 1)
        end
        if o.plot_vsync_jitter then
            jitter_graph = generate_graph(vsjitter_buf, vsjitter_buf.pos,
                                          vsjitter_buf.len, vsjitter_buf.max, nil, 0.8, 1)
        end
        append_property(s, "vsync-ratio", {
            prefix = "VSync Ratio:",
            suffix = o.prefix_sep .. ratio_graph,
            no_prefix_markup = true,
            no_bold = true,
            second_highlight = false
        })
        append_property(s, "vsync-jitter", {
            prefix = "VSync Jitter:",
            suffix = o.prefix_sep .. jitter_graph,
            no_prefix_markup = true,
            no_bold = true,
            second_highlight = false
        })
    else
        -- Since no graph is needed we can print ratio/jitter on the same line and save some space
        local vr = append_property(s, "vsync-ratio", { prefix = "VSync Ratio:" })
        append_property(s, "vsync-jitter", {
            prefix = "VSync Jitter:",
            nl = vr and "" or o.nl,
            indent = vr and o.prefix_sep .. o.prefix_sep,
            no_prefix_markup = true,
            no_bold = true,
            second_highlight = false
        })
    end
end


local function append_filters(s, prop, prefix)
    local length = 0
    local filters = {}

    for _, f in ipairs(mp.get_property_native(prop, {})) do
        local n = f.name
        if f.enabled ~= nil and not f.enabled then
            n = n .. " (disabled)"
        end

        if f.label ~= nil then
            n = "@" .. f.label .. ": " .. n
        end

        local p = {}
        local ps = ""
        for _, key in ipairs(sorted_keys(f.params)) do
            p[#p + 1] = key .. "=" .. f.params[key]
        end
        if #p > 0 then
            ps = " [" .. table.concat(p, " ") .. "]"
        else
            ps = ""
        end

        length = length + n:len() + ps:len()
        filters[#filters + 1] = no_ASS(n) .. it(no_ASS(ps))
    end
    if #filters > 0 then
        local ret
        if length < o.filter_params_max_length then
            ret = table.concat(filters, ", ")
        else
            local sep = o.nl .. o.indent .. o.indent
            ret = sep .. table.concat(filters, sep)
        end
        s[#s + 1] = o.nl .. o.indent .. bold(prefix) .. o.prefix_sep .. ret
    end
end


local function add_header(s)
    s[#s + 1] = text_style()
end

table.filter = function(array, filterIterator)
    local result = {}

    for key, value in pairs(array) do
        if filterIterator(value, key, array) then
            table.insert(result, value)
        end
    end

    return result
end

local function add_profiles(s)
    append(s, "",
           {
               prefix = "Auto Profiles:",
               nl = o.nl,
               indent = ""
           }
    )


    local template = "%-" .. profiles_max_length .. "s"
    for _, profile in pairs(profiles) do
        if profile.active then
            append(s, profile["profile-desc"],
                   {
                       prefix = format(template .. "   ", profile.name),
                       prefix_sep = "  : ",
                       nl = o.nl,
                       indent = o.indent,
                       no_prefix_markup = true,
                       no_bold = true,
                       second_highlight = false
                   }
            )
            for _, sub_profile in pairs(profile["sub_profiles"]) do
                append(s, profiles[sub_profile]["profile-desc"],
                       {
                           prefix = format(" ↪  " .. template, profiles[sub_profile]["name"]),
                           prefix_sep = "  : ",
                           nl = o.nl,
                           indent = o.indent,
                           no_prefix_markup = true,
                           no_bold = true,
                           second_highlight = false
                       }
                )
            end
        end
    end
end

local function add_displays(s)
    --[[
    append(s, "",
        {
            prefix = "Displays:",
            indent = "",
            nl = o.nl
        }
    )
    ]] --

    local display_list_json = mp.get_property_native("user-data/display-list/full")
    local display_list = utils.parse_json(display_list_json)

    for key, display in ipairs(display_list) do
        local is_inactive = true
        if display["current"] then
            is_inactive = false
        end
        local id = (display["current"] and "* " or "  ")
        id = id .. "[" .. display["name"] .. "]"
        append(
            s,
            "",
            {
                prefix = id,
                prefix_sep = "",
                nl = o.nl,
                indent = "",
                no_prefix_markup = false,
                no_bold = false
            }
        )

        -- First Line
        append(
            s,
            format("%-15s", display["width"] .. " x " .. display["height"]),
            {
                prefix = format("%10s:", "Resolution"),
                prefix_sep = " ",
                nl = o.nl,
                indent = o.indent,
                no_prefix_markup = true,
                no_bold = is_inactive,
                second_highlight = display["current"]
            }
        )
        append(s,
               format("%-13s", display["refresh_rate"]),
               {
                   prefix = format("%12s:", "Refresh Rate"),
                   prefix_sep = " ",
                   nl = "",
                   no_prefix_markup = true,
                   no_bold = is_inactive,
                   second_highlight = display["current"]
               }
        )
        append(s,
               format("%-12s", display["bit_depth"]),
               {
                   prefix = format("%9s:", "Bit Depth"),
                   prefix_sep = " ",
                   nl = "",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        append(s, display["transfer"],
               {
                   prefix = "Transfer:",
                   prefix_sep = " ",
                   nl = "",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        append(s, display["primaries"],
               {
                   prefix = "Primaries:",
                   prefix_sep = " ",
                   nl = "",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )

        -- New Line
        local hdr = display["hdr_supported"] and "Supported" or "Not Supported"
        hdr = (display["hdr_status"] == "on") and "Enabled" or hdr
        append(s,
               format("%-15s", hdr),
               {
                   prefix = format("%10s:", "HDR"),
                   prefix_sep = " ",
                   nl = o.nl,
                   indent = o.indent,
                   no_prefix_markup = true,
                   no_bold = is_inactive,
                   second_highlight = display["current"]
               }
        )
        append(
            s,
            format("%-13s", display["technology"]),
            {
                prefix = format("%12s:", "Connector"),
                prefix_sep = " ",
                nl = "",
                no_prefix_markup = true,
                no_bold = true,
                second_highlight = false
            }
        )
        append(s,
               format("%-3.1f%4s%-3.1f", display["min_luminance"], " to ", display["max_luminance"]),
               {
                   prefix = format("%9s:", "Luminance"),
                   prefix_sep = " ",
                   nl = "",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        append(s, display["max_full_frame_luminance"],
               {
                   prefix = "Max Full Frame Luminance:",
                   prefix_sep = " ",
                   nl = "",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               })

        --[[
		"current": true,
		"hdr_supported": true,
		"hdr_status": "on",
		"width": 3840,
		"height": 2160,
		"refresh_rate": 60.00,
		"bit_depth": 10,
		"primaries": "BT.2020",
		"transfer": "PQ",
		"max_luminance": 1107.00,
		"min_luminance": 0.0108,
		"max_full_frame_luminance": 972.0000,
		"technology": "DisplayPort"
		]] --
    end
end

local function add_file(s, print_cache, print_tags)
    append(s, "",
           {
               prefix = "Media File:",
               nl = o.nl,
               indent = ""
           }
    )
    append_property(s, "path",
                    {
                        prefix = "Path:",
                        prefix_sep = " ",
                        nl = o.nl,
                        indent = o.indent,
                        no_prefix_markup = true,
                        no_bold = false,
                        second_highlight = true
                    }
    )
    if mp.get_property_osd("filename") ~= mp.get_property_osd("media-title") then
        append_property(s, "media-title",
                        {
                            prefix = "Title:",
                            no_prefix_markup = true,
                            no_bold = true,
                            second_highlight = false
                        }
        )
    end
    append_property(s, "duration",
                    {
                        prefix = "Duration:",
                        no_prefix_markup = true,
                        no_bold = true,
                        second_highlight = false
                    }
    )

    if print_tags then
        local tags = mp.get_property_native("display-tags")
        local tags_displayed = 0
        for _, tag in ipairs(tags) do
            local value = mp.get_property("metadata/by-key/" .. tag)
            if  tag ~= "Title" and tags_displayed < o.file_tag_max_count
            and value and value:len() < o.file_tag_max_length then
                append(s, value,
                       {
                           prefix = string.gsub(tag, "_", " ") .. ":",
                           no_prefix_markup = true,
                           no_bold = true,
                           second_highlight = false
                       }
                )
                tags_displayed = tags_displayed + 1
            end
        end
    end

    local editions = mp.get_property_number("editions")
    local edition = mp.get_property_number("current-edition")
    local ed_cond = (edition and editions > 1)
    if ed_cond then
        append_property(s, "edition-list/" .. tostring(edition) .. "/title",
                        { prefix = "Edition:" })
        append_property(s, "edition-list/count",
                        {
                            prefix = "(" .. tostring(edition + 1) .. "/",
                            suffix = ")",
                            nl = "",
                            indent = " ",
                            prefix_sep = " ",
                            no_prefix_markup = true,
                            no_bold = true,
                            second_highlight = false
                        })
    end

    local ch_index = mp.get_property_number("chapter")
    if ch_index and ch_index >= 0 then
        append_property(s, "chapter-list/" .. tostring(ch_index) .. "/title",
                        {
                            prefix = "Chapter:",
                            nl = ed_cond and "" or o.nl,
                            no_prefix_markup = true,
                            no_bold = true,
                            second_highlight = false
                        }
        )
        append_property(s, "chapter-list/count",
                        {
                            prefix = "(" .. tostring(ch_index + 1) .. " /",
                            suffix = ")",
                            nl = "",
                            indent = " ",
                            prefix_sep = " ",
                            no_prefix_markup = true,
                            no_bold = true,
                            second_highlight = false
                        })
    end

    local fs = append_property(s, "file-size",
                               {
                                   prefix = "Size:",
                                   no_prefix_markup = true,
                                   no_bold = true,
                                   second_highlight = false
                               }
    )
    append_property(s, "file-format",
                    {
                        prefix = "Format/Protocol:",
                        nl = o.nl,
                        indent = o.indent,
                        no_prefix_markup = true,
                        no_bold = true,
                        second_highlight = false
                    }
    )

    if not print_cache then
        return
    end

    local demuxer_cache = mp.get_property_native("demuxer-cache-state", {})
    if demuxer_cache["fw-bytes"] then
        demuxer_cache = demuxer_cache["fw-bytes"] -- returns bytes
    else
        demuxer_cache = 0
    end
    local demuxer_secs = mp.get_property_number("demuxer-cache-duration", 0)
    if demuxer_cache + demuxer_secs > 0 then
        append(s, utils.format_bytes_humanized(demuxer_cache),
               {
                   prefix = "Total Cache:",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        append(s, format("%.1f", demuxer_secs),
               {
                   prefix = "(",
                   suffix = " sec)",
                   nl = "",
                   prefix_sep = "",
                   indent = o.prefix_sep,
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
    end
end


local function crop_noop(w, h, r)
    return r["crop-x"] == 0 and r["crop-y"] == 0 and
        r["crop-w"] == w and r["crop-h"] == h
end


local function crop_equal(r, ro)
    return r["crop-x"] == ro["crop-x"] and r["crop-y"] == ro["crop-y"] and
        r["crop-w"] == ro["crop-w"] and r["crop-h"] == ro["crop-h"]
end


local function append_resolution(s, r, prefix, w_prop, h_prop, video_res)
    if not r then
        return
    end
    w_prop = w_prop or "w"
    h_prop = h_prop or "h"
    if append(s, r[w_prop],
              {
                  prefix = prefix,
                  no_prefix_markup = false,
                  no_bold = false,
                  second_highlight = true
              }
    ) then
        append(s, r[h_prop], {
            prefix = "x",
            nl = "",
            indent = " ",
            prefix_sep = " ",
            no_prefix_markup = true,
            no_bold = false,
            second_highlight = true
        })
        if r["aspect"] ~= nil and not video_res then
            append(s, format("%.2f:1", r["aspect"]), {
                prefix = "",
                nl = "",
                indent = "",
                no_prefix_markup = true,
                no_bold = true,
                second_highlight = true
            })
            append(s, r["aspect-name"], {
                prefix = "(",
                suffix = ")",
                nl = "",
                indent = " ",
                prefix_sep = "",
                no_prefix_markup = true,
                no_bold = true,
                second_highlight = true
            })
        end
        if r["sar"] ~= nil and video_res then
            append(s, format("%.2f:1", r["sar"]), {
                prefix = "",
                nl = "",
                indent = "",
                no_prefix_markup = true,
                no_bold = true,
                second_highlight = true
            })
            append(s, r["sar-name"], {
                prefix = "(",
                suffix = ")",
                nl = "",
                indent = " ",
                prefix_sep = "",
                no_prefix_markup = true,
                no_bold = true,
                second_highlight = true
            })
        end
        if r["s"] then
            append(s, format("%.2f", r["s"]), {
                prefix = "(",
                suffix = "x)",
                nl = "",
                indent = o.prefix_sep,
                prefix_sep = "",
                no_prefix_markup = true,
                no_bold = true,
                second_highlight = true
            })
        end
        -- We can skip crop if it is the same as video decoded resolution
        if r["crop-w"] and (not video_res or
            not crop_noop(r[w_prop], r[h_prop], r)) then
            append(s, format("[x: %d, y: %d, w: %d, h: %d]",
                             r["crop-x"], r["crop-y"], r["crop-w"], r["crop-h"]),
                   {
                       prefix = "",
                       nl = "",
                       indent = "",
                       no_prefix_markup = true,
                       no_bold = true,
                       second_highlight = true
                   }
            )
        end
    end
end


local function pq_eotf(x)
    if not x then
        return x;
    end

    local PQ_M1 = 2610.0 / 4096 * 1.0 / 4
    local PQ_M2 = 2523.0 / 4096 * 128
    local PQ_C1 = 3424.0 / 4096
    local PQ_C2 = 2413.0 / 4096 * 32
    local PQ_C3 = 2392.0 / 4096 * 32

    x = x ^ (1.0 / PQ_M2)
    x = max(x - PQ_C1, 0.0) / (PQ_C2 - PQ_C3 * x)
    x = x ^ (1.0 / PQ_M1)
    x = x * 10000.0

    return x
end


local function append_hdr(s, hdr, video_out)
    if not hdr then
        return
    end

    local function has(val, target)
        return val and math.abs(val - target) > 1e-4
    end

    -- If we are printing video out parameters it is just display, not mastering
    local display_prefix = video_out and "Display:" or "Mastering display:"

    local indent = ""
    local has_dml = has(hdr["min-luma"], 0.203) or has(hdr["max-luma"], 203)
    local has_cll = hdr["max-cll"] and hdr["max-cll"] > 0
    local has_fall = hdr["max-fall"] and hdr["max-fall"] > 0

    if has_dml or has_cll or has_fall then
        append(s, "",
               {
                   prefix = video_out and "" or "HDR10:",
                   prefix_sep = video_out and "" or nil,
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        if has_dml then
            -- libplacebo uses close to zero values as "defined zero"
            hdr["min-luma"] = hdr["min-luma"] <= 1e-6 and 0 or hdr["min-luma"]
            append(s, format("%.2g / %.0f", hdr["min-luma"], hdr["max-luma"]),
                   {
                       prefix = display_prefix,
                       suffix = " cd/m²",
                       nl = "",
                       indent = indent,
                       no_prefix_markup = true,
                       no_bold = true,
                       second_highlight = false
                   }
            )
            indent = o.prefix_sep .. o.prefix_sep
        end
        if has_cll then
            append(s, string.format("%.0f", hdr["max-cll"]), {
                prefix = "MaxCLL:",
                suffix = " cd/m²",
                nl = "",
                indent = indent,
                no_prefix_markup = true,
                no_bold = true,
                second_highlight = false
            })
            indent = o.prefix_sep .. o.prefix_sep
        end
        if has_fall then
            append(s, hdr["max-fall"], {
                prefix = "MaxFALL:",
                suffix = " cd/m²",
                nl = "",
                indent = indent,
                no_prefix_markup = true,
                no_bold = true,
                second_highlight = false
            })
        end
    end

    indent = o.prefix_sep .. o.prefix_sep

    if hdr["scene-max-r"] or hdr["scene-max-g"] or
    hdr["scene-max-b"] or hdr["scene-avg"] then
        append(s, "", { prefix = "HDR10+:", no_prefix_markup = true })
        append(s, format("%.1f / %.1f / %.1f", hdr["scene-max-r"] or 0,
                         hdr["scene-max-g"] or 0, hdr["scene-max-b"] or 0),
               {
                   prefix = "MaxRGB:",
                   suffix = " cd/m²",
                   nl = "",
                   indent = "",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        append(s, format("%.1f", hdr["scene-avg"] or 0),
               {
                   prefix = "Avg:",
                   suffix = " cd/m²",
                   nl = "",
                   indent = indent,
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
    end

    if hdr["max-pq-y"] and hdr["avg-pq-y"] then
        append(s, "", { prefix = "PQ(Y):", no_prefix_markup = true })
        append(s, format("%.2f cd/m² (%.2f%% PQ)", pq_eotf(hdr["max-pq-y"]),
                         hdr["max-pq-y"] * 100), {
                   prefix = "Max:",
                   nl = "",
                   indent = "",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               })
        append(s, format("%.2f cd/m² (%.2f%% PQ)", pq_eotf(hdr["avg-pq-y"]),
                         hdr["avg-pq-y"] * 100), {
                   prefix = "Avg:",
                   nl = "",
                   indent = indent,
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               })
    end
end


local function append_img_params(s, r, ro)
    if not r then
        return
    end

    append_resolution(s, r, "Resolution:", "w", "h", true)
    if ro and (r["w"] ~= ro["dw"] or r["h"] ~= ro["dh"]) then
        if ro["crop-w"] and (crop_noop(r["w"], r["h"], ro) or crop_equal(r, ro)) then
            ro["crop-w"] = nil
        end
        append_resolution(s, ro, "Output Resolution:", "dw", "dh")
    end

    local indent = o.prefix_sep .. o.prefix_sep
    r = ro or r

    local pixel_format = r["hw-pixelformat"] or r["pixelformat"]
    append(s, pixel_format,
           {
               prefix = "Format:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(s, r["colorlevels"],
           {
               prefix = "Levels:",
               nl = "",
               indent = indent,
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    if r["chroma-location"] and r["chroma-location"] ~= "unknown" then
        append(s, r["chroma-location"],
               {
                   prefix = "Chroma Loc:",
                   nl = "",
                   indent = indent,
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
    end

    -- Group these together to save vertical space
    append(s, r["colormatrix"],
           {
               prefix = "Colormatrix:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    if r["prim-red-x"] or r["prim-red-y"] or
    r["prim-green-x"] or r["prim-green-y"] or
    r["prim-blue-x"] or r["prim-blue-y"] or
    r["prim-white-x"] or r["prim-white-y"] then
        append(s, string.format("[%.3f %.3f, %.3f %.3f, %.3f %.3f, %.3f %.3f]",
                                r["prim-red-x"] or 0, r["prim-red-y"] or 0,
                                r["prim-green-x"] or 0, r["prim-green-y"] or 0,
                                r["prim-blue-x"] or 0, r["prim-blue-y"] or 0,
                                r["prim-white-x"] or 0, r["prim-white-y"] or 0),
               {
                   prefix = "Primaries:",
                   nl = "",
                   indent = indent,
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        append(s, r["primaries"], {
            prefix = "in",
            nl = "",
            indent = " ",
            prefix_sep = " ",
            no_prefix_markup = true,
            no_bold = true,
            second_highlight = false
        })
    else
        append(s, r["primaries"],
               {
                   prefix = "Primaries:",
                   nl = "",
                   indent = indent,
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
    end
    append(s, r["gamma"],
           {
               prefix = "Transfer:",
               nl = "",
               indent = indent,
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
end


local function append_fps(s, prop, eprop)
    local fps = mp.get_property_osd(prop)
    local efps = mp.get_property_osd(eprop)
    local single = eprop == "" or (fps ~= "" and efps ~= "" and fps == efps)
    local unit = prop == "display-fps" and " Hz" or " fps"
    local suffix = single and "" or " (specified)"
    local esuffix = single and "" or " (estimated)"
    local prefix = prop == "display-fps" and "Refresh Rate:" or "Frame Rate:"
    local nl = o.nl
    local indent = o.indent

    if fps ~= "" and append(s, fps,
                            {
                                prefix = prefix,
                                suffix = unit .. suffix,
                                no_prefix_markup = true,
                                no_bold = true,
                                second_highlight = false
                            }
    ) then
        prefix = ""
        nl = ""
        indent = ""
    end

    if not single and efps ~= "" then
        append(s, efps,
               { prefix = prefix, suffix = unit .. esuffix, nl = nl, indent = indent, no_prefix_markup = true })
    end
end


local function add_video_out(s)
    local vo = mp.get_property_native("current-vo")
    if not vo then
        return
    end

    append(s, "",
           {
               prefix = "Video Out:",
               nl = o.nl,
               indent = ""
           }
    )
    append(s, vo,
           {
               prefix = "Driver:",
               prefix_sep = " ",
               nl = o.nl,
               no_prefix_markup = true,
               no_bold = false,
               second_highlight = true
           }
    )
    append(s, mp.get_property_native("current-gpu-context"),
           {
               prefix = "Context:",
               prefix_sep = " ",
               nl = "",
               indent = o.prefix_sep .. o.prefix_sep,
               no_prefix_markup = true,
               no_bold = false,
               second_highlight = true
           }
    )

    local scale = nil
    if not mp.get_property_native("fullscreen") then
        scale = get_property_cached("current-window-scale")
    end

    local od = mp.get_property_native("osd-dimensions")
    local rt = mp.get_property_native("video-target-params")
    local r = rt or {}

    -- Add window scale
    r["s"] = scale
    r["crop-x"] = od["ml"]
    r["crop-y"] = od["mt"]
    r["crop-w"] = od["w"] - od["ml"] - od["mr"]
    r["crop-h"] = od["h"] - od["mt"] - od["mb"]

    if not rt then
        r["w"] = r["crop-w"]
        r["h"] = r["crop-h"]
        append_resolution(s, r, "Resolution:", "w", "h", true)
        return
    end

    append_img_params(s, r)
    append_hdr(s, r, true)

    append_fps(s, "display-fps", "estimated-display-fps")
    if append_property(s, "decoder-frame-drop-count",
                       {
                           prefix = "Dropped Frames:",
                           suffix = " (decoder)",
                           no_prefix_markup = true,
                           no_bold = true,
                           second_highlight = false
                       }
    ) then
        append_property(s, "frame-drop-count",
                        {
                            suffix = " (output)",
                            nl = "",
                            indent = "",
                            no_prefix_markup = true,
                            no_bold = true,
                            second_highlight = false
                        }
        )
    end
    append_display_sync(s)
    -- append_perfdata(nil, s, false)

    if mp.get_property_native("deinterlace-active") then
        append_property(s, "deinterlace",
                        {
                            prefix = "Deinterlacing:",
                            no_prefix_markup = true,
                            no_bold = true,
                            second_highlight = false
                        }
        )
    end
    append_property(s, "avsync",
                    {
                        prefix = "A-V:",
                        prefix_sep = " ",
                        no_prefix_markup = true,
                        no_bold = true,
                        second_highlight = false
                    }
    )
end


local function add_video(s)
    local r = mp.get_property_native("video-params")
    local ro = mp.get_property_native("video-out-params")
    -- in case of e.g. lavfi-complex there can be no input video, only output
    if not r then
        r = ro
    end
    if not r then
        return
    end

    local track = mp.get_property_native("current-tracks/video")
    local track_type = (track and track.image) and "Image:" or "Video:"
    append(s, "",
           {
               prefix = track_type,
               nl = o.nl,
               indent = "",
               no_prefix_markup = false,
               no_bold = false,
               second_highlight = false
           }
    )
    if track and append(s, track["codec-desc"],
                        {
                            prefix = "Codec:",
                            prefix_sep = " ",
                            nl = o.nl,
                            no_prefix_markup = true,
                            no_bold = true,
                            second_highlight = false
                        }
    ) then
        append(s, track["codec-profile"],
               {
                   prefix = "[",
                   nl = "",
                   indent = " ",
                   prefix_sep = "",
                   suffix = "]",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        if track["codec"] ~= track["decoder"] then
            append(s, track["decoder"],
                   {
                       prefix = "[",
                       nl = "",
                       indent = " ",
                       prefix_sep = "",
                       suffix = "]",
                       no_prefix_markup = true,
                       no_bold = true,
                       second_highlight = false
                   }
            )
        end
        append_property(s, "hwdec-current",
                        {
                            prefix = "HW Decoder:",
                            suffix = "",
                            nl = o.nl,
                            no_prefix_markup = false,
                            no_bold = false,
                            second_highlight = true
                        },
                        {
                            no = true,
                            [""] = true
                        }, true
        )
    end
    append_img_params(s, r, ro)
    local has_prefix = false
    if o.show_frame_info then
        if append_property(s, "estimated-frame-number", { prefix = "Frame:" }) then
            append_property(s, "estimated-frame-count", {
                indent = " / ",
                nl = "",
                prefix_sep = "",
                no_prefix_markup = true
            })
            has_prefix = true
        end
        local frame_info = mp.get_property_native("video-frame-info")
        if frame_info and frame_info["picture-type"] then
            local attrs = has_prefix and {
                    prefix = "(",
                    suffix = ")",
                    indent = " ",
                    nl = "",
                    prefix_sep = "",
                    no_prefix_markup = true
                }
                or { prefix = "Picture Type:", no_prefix_markup = true }
            append(s, frame_info["picture-type"], attrs)
            has_prefix = true
        end
        if frame_info and frame_info["interlaced"] then
            local attrs = has_prefix and { indent = " ", nl = "", prefix_sep = "", no_prefix_markup = true }
                or { prefix = "Picture Type:", no_prefix_markup = true }
            append(s, "Interlaced", attrs)
        end

        local timecodes = {
            ["gop-timecode"] = "GOP",
            ["smpte-timecode"] = "SMPTE",
            ["estimated-smpte-timecode"] = "Estimated SMPTE",
        }
        for prop, name in pairs(timecodes) do
            if frame_info and frame_info[prop] then
                local attrs = has_prefix and {
                        prefix = name .. " Timecode:",
                        indent = o.prefix_sep .. o.prefix_sep,
                        nl = "",
                        no_prefix_markup = true
                    }
                    or { prefix = name .. " Timecode:", no_prefix_markup = true }
                append(s, frame_info[prop], attrs)
                break
            end
        end
    end

    if mp.get_property_native("current-tracks/video/image") == false then
        append_fps(s, "container-fps", "estimated-vf-fps")
    end
    append_hdr(s, ro)
    append_property(s, "video-bitrate",
                    {
                        prefix = "Bitrate:",
                        no_prefix_markup = true,
                        no_bold = true,
                        second_highlight = false
                    }
    )
    append_filters(s, "vf", "Filters:")
end


local function add_audio(s)
    local r = mp.get_property_native("audio-params")
    -- in case of e.g. lavfi-complex there can be no input audio, only output
    local ro = mp.get_property_native("audio-out-params") or r
    r = r or ro
    if not r then
        return
    end

    local merge = function(rr, rro, prop)
        local a = rr[prop] or rro[prop]
        local b = rro[prop] or rr[prop]
        return (a == b or a == nil) and a or (a .. " ➜ " .. b)
    end

    append(s, "",
           {
               prefix = "Audio:",
               nl = o.nl,
               indent = "",
               no_prefix_markup = false,
               no_bold = false,
               second_highlight = false
           }
    )
    local track = mp.get_property_native("current-tracks/audio")
    if track then
        append_property(s, "current-ao", {
            prefix = "Driver:",
            prefix_sep = " ",
            nl = o.nl,
            indent = o.indent,
            no_prefix_markup = false,
            no_bold = false,
            second_highlight = true
        })
        append(s, track["codec-desc"],
               {
                   prefix = "Codec:",
                   prefix_sep = " ",
                   nl = o.nl,
                   indent = o.indent,
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        append(s, track["codec-profile"], {
            prefix = "[",
            nl = "",
            indent = " ",
            prefix_sep = "",
            suffix = "]",
            no_prefix_markup = true,
            no_bold = true,
            second_highlight = false
        })
        if track["codec"] ~= track["decoder"] then
            append(s, track["decoder"], {
                prefix = "[",
                nl = "",
                indent = " ",
                prefix_sep = "",
                suffix = "]",
                no_prefix_markup = true,
                no_bold = true,
                second_highlight = false
            })
        end
    end
    local dev = append_property(s, "audio-device",
                                {
                                    prefix = "Device:",
                                    no_prefix_markup = true,
                                    no_bold = true,
                                    second_highlight = false
                                }
    )
    local ao_mute = mp.get_property_native("ao-mute") and " (Muted)" or ""
    append_property(s, "ao-volume",
                    {
                        prefix = "Device Volume:",
                        suffix = "%" .. ao_mute,
                        nl = o.nl,
                        indent = o.indent,
                        no_prefix_markup = true,
                        no_bold = true,
                        second_highlight = false
                    }
    )
    if math.abs(mp.get_property_native("audio-delay")) > 1e-6 then
        append_property(s, "audio-delay",
                        {
                            prefix = "A-V delay:",
                            no_prefix_markup = true,
                            no_bold = true,
                            second_highlight = false
                        }
        )
    end
    local cc = append(s, merge(r, ro, "channel-count"),
                      {
                          prefix = "Channels:",
                          no_prefix_markup = true,
                          no_bold = true,
                          second_highlight = false
                      }
    )
    append(s, merge(r, ro, "format"), {
        prefix = "Format:",
        nl = o.nl,
        indent = o.indent,
        no_prefix_markup = true,
        no_bold = true,
        second_highlight = false
    })
    append(s, merge(r, ro, "samplerate"),
           {
               prefix = "Sample Rate:",
               suffix = " Hz",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append_property(s, "audio-bitrate",
                    {
                        prefix = "Bitrate:",
                        no_prefix_markup = true,
                        no_bold = true,
                        second_highlight = false
                    }
    )
    append_filters(s, "af", "Filters:")
end


-- Determine whether ASS formatting shall/can be used and set formatting sequences
local function eval_ass_formatting()
    o.use_ass = o.ass_formatting and has_vo_window()
    if o.use_ass then
        o.nl = o.ass_nl
        o.indent = o.ass_indent
        o.prefix_sep = o.ass_prefix_sep
        o.b1 = o.ass_b1
        o.b0 = o.ass_b0
        o.it1 = o.ass_it1
        o.it0 = o.ass_it0
    else
        o.nl = o.no_ass_nl
        o.indent = o.no_ass_indent
        o.prefix_sep = o.no_ass_prefix_sep
        o.b1 = o.no_ass_b1
        o.b0 = o.no_ass_b0
        o.it1 = o.no_ass_it1
        o.it0 = o.no_ass_it0
    end
end

-- split str into a table
-- example: local t = split(s, "\n")
-- plain: whether pat is a plain string (default false - pat is a pattern)
local function split(str, pat, plain)
    local init = 1
    local r, i, find, sub = {}, 1, string.find, string.sub
    repeat
        local f0, f1 = find(str, pat, init, plain)
        r[i], i = sub(str, init, f0 and f0 - 1), i + 1
        init = f0 and f1 + 1
    until f0 == nil
    return r
end

-- Composes the output with header and scrollable content
-- Returns string of the finished page and the actually chosen offset
--
-- header      : table of the header where each entry is one line
-- content     : table of the content where each entry is one line
-- apply_scroll: scroll the content
local function finalize_page(header, content, apply_scroll)
    local term_height = mp.get_property_native("term-size/h", 24)
    local from, to = 1, #content
    if apply_scroll then
        -- Up to 40 lines for libass because it can put a big performance toll on
        -- libass to process many lines which end up outside (below) the screen.
        -- In the terminal reduce height by 2 for the status line (can be more then one line)
        local max_content_lines = (o.use_ass and 30 or term_height - 10) - #header
        -- in the terminal the scrolling should stop once the last line is visible
        local max_offset = o.use_ass and #content or #content - max_content_lines + 1
        from = max(1, min((pages[curr_page].offset or 1), max_offset))
        to = min(#content, from + max_content_lines - 1)
        pages[curr_page].offset = from
    end
    local output = table.concat(header) .. table.concat(content, "", from, to)
    if not o.use_ass and o.term_clip then
        local clip = mp.get_property("term-clip-cc")
        local t = split(output, "\n", true)
        output = clip .. table.concat(t, "\n" .. clip)
    end
    return output, from
end

-- Returns an ASS string with "normal" stats
local function default_stats()
    local header, stats = {}, {}
    local desc = pages[o.key_page_1].desc
    eval_ass_formatting()
    add_header(header)
    append(header, "",
           {
               prefix = format("%s: %s", desc, scroll_hint()),
               nl = "",
               indent = "",
               no_prefix_markup = false,
               no_bold = false,
               second_highlight = false
           }
    )
    append(header, "", { nl = o.nl })
    header = { table.concat(header) }
    add_displays(stats)
    append(stats, "",
           {
               prefix = "",
               nl = o.nl,
               indent = "",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    add_video_out(stats)
    append(stats, "",
           {
               prefix = "",
               nl = o.nl,
               indent = "",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    add_video(stats)
    append(stats, "",
           {
               prefix = "",
               nl = o.nl,
               indent = "",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    add_audio(stats)
    append(stats, "",
           {
               prefix = "",
               nl = o.nl,
               indent = "",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    add_file(stats, true, true)
    append(stats, "",
           {
               prefix = "",
               nl = o.nl,
               indent = "",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    add_profiles(stats)
    return finalize_page(header, stats, true)
end

-- Returns an ASS string with extended VO stats
local function vo_stats()
    local header, content = {}, {}
    eval_ass_formatting()
    add_header(header)
    append_perfdata(header, content, true)
    header = { table.concat(header) }
    return finalize_page(header, content, true)
end

local kbinfo_lines = nil
local function keybinding_info(after_scroll, bindlist)
    local header = {}
    local page = pages[o.key_page_4]
    eval_ass_formatting()
    add_header(header)
    local prefix = bindlist and page.desc or page.desc .. ":" .. scroll_hint(true)
    append(header, "",
           {
               prefix = prefix,
               nl = "",
               indent = "",
               no_prefix_markup = false,
               no_bold = false,
               second_highlight = false
           }
    )
    header = { table.concat(header) }

    if not kbinfo_lines or not after_scroll then
        kbinfo_lines = get_kbinfo_lines()
    end

    return finalize_page(header, kbinfo_lines, not bindlist)
end

local function float2rational(x)
    local max_den = 100000
    local m00, m01, m10, m11 = 1, 0, 0, 1
    local a = math.floor(x)
    local frac = x - a
    while m10 * a + m11 <= max_den do
        local temp = m00 * a + m01
        m01 = m00
        m00 = temp
        temp = m10 * a + m11
        m11 = m10
        m10 = temp

        if frac == 0 then
            break
        end

        x = 1 / frac
        a = math.floor(x)
        frac = x - a
    end
    return m00, m10
end

local function add_track(c, t, i)
    if not t then
        return
    end

    local type = t.image and "Image" or t["type"]:sub(1, 1):upper() .. t["type"]:sub(2)
    append(c, "",
           {
               prefix = type .. ":",
               nl = o.nl .. o.nl,
               indent = "",
               no_prefix_markup = false,
               no_bold = false,
               second_highlight = false
           }
    )
    append(c, t["title"],
           {
               prefix_sep = "",
               nl = "",
               indent = "",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(c, t["id"],
           {
               prefix = "ID:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(c, t["src-id"],
           {
               prefix = "Demuxer ID:",
               nl = "",
               indent = o.prefix_sep .. o.prefix_sep,
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(c, t["program-id"],
           {
               prefix = "Program ID:",
               nl = "",
               indent = o.prefix_sep .. o.prefix_sep,
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(c, t["ff-index"],
           {
               prefix = "FFmpeg Index:",
               nl = "",
               indent = o.prefix_sep .. o.prefix_sep,
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(c, t["external-filename"],
           {
               prefix = "File:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(c, "",
           {
               prefix = "Flags:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    local flags = {
        "default",
        "forced",
        "dependent",
        "visual-impaired",
        "hearing-impaired",
        "original",
        "commentary",
        "image",
        "albumart",
        "external"
    }
    local any = false
    for _, flag in ipairs(flags) do
        if t[flag] then
            append(c, flag,
                   {
                       prefix = any and ", " or "",
                       nl = "",
                       indent = "",
                       prefix_sep = "",
                       no_prefix_markup = true,
                       no_bold = true,
                       second_highlight = false
                   }
            )
            any = true
        end
    end
    if not any then
        table.remove(c)
    end
    if append(c, t["codec-desc"],
              {
                  prefix = "Codec:",
                  no_prefix_markup = true,
                  no_bold = true,
                  second_highlight = false
              }
    ) then
        append(c, t["codec-profile"],
               {
                   prefix = "[",
                   nl = "",
                   indent = " ",
                   prefix_sep = "",
                   suffix = "]",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        if t["codec"] ~= t["decoder"] then
            append(c, t["decoder"],
                   {
                       prefix = "[",
                       nl = "",
                       indent = " ",
                       prefix_sep = "",
                       suffix = "]",
                       no_prefix_markup = true,
                       no_bold = true,
                       second_highlight = false
                   }
            )
        end
    end
    append(c, t["lang"],
           {
               prefix = "Language:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(c, t["demux-channel-count"],
           {
               prefix = "Channels:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(c, t["demux-channels"],
           {
               prefix = "Channel Layout:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(c, t["demux-samplerate"],
           {
               prefix = "Sample Rate:",
               suffix = " Hz",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    local function B(b) return b and string.format("%.2f", b / 1024) end
    local bitrate = append(c, B(t["demux-bitrate"]),
                           {
                               prefix = "Bitrate:",
                               suffix = " kbps",
                               no_prefix_markup = true,
                               no_bold = true,
                               second_highlight = false
                           }
    )
    append(c, B(t["hls-bitrate"]),
           {
               prefix = "HLS Bitrate:",
               suffix = " kbps",
               nl = bitrate and "" or o.nl,
               indent = bitrate and o.prefix_sep .. o.prefix_sep,
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append_resolution(c, {
                          w = t["demux-w"],
                          h = t["demux-h"],
                          ["crop-x"] = t["demux-crop-x"],
                          ["crop-y"] = t["demux-crop-y"],
                          ["crop-w"] = t["demux-crop-w"],
                          ["crop-h"] = t["demux-crop-h"]
                      }, "Resolution:")
    if not t["image"] and t["demux-fps"] then
        append_fps(c, "track-list/" .. i .. "/demux-fps", "")
    end
    append(c, t["format-name"],
           {
               prefix = "Format:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(c, t["demux-rotation"],
           {
               prefix = "Rotation:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    if t["demux-par"] then
        local num, den = float2rational(t["demux-par"])
        append(c, string.format("%d:%d", num, den),
               {
                   prefix = "Pixel Aspect Ratio:",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
    end
    local track_rg = t["replaygain-track-peak"] ~= nil or t["replaygain-track-gain"] ~= nil
    local album_rg = t["replaygain-album-peak"] ~= nil or t["replaygain-album-gain"] ~= nil
    if track_rg or album_rg then
        append(c, "",
               {
                   prefix = "Replay Gain:",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
    end
    if track_rg then
        append(c, "",
               {
                   prefix = "Track:",
                   indent = o.indent .. o.prefix_sep,
                   prefix_sep = "",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        append(c, t["replaygain-track-gain"], {
            prefix = "Gain:",
            suffix = " dB",
            nl = "",
            indent = o.prefix_sep,
            no_prefix_markup = true,
            no_bold = true,
            second_highlight = false
        })
        append(c, t["replaygain-track-peak"], {
            prefix = "Peak:",
            suffix = " dB",
            nl = "",
            indent = o.prefix_sep,
            no_prefix_markup = true,
            no_bold = true,
            second_highlight = false
        })
    end
    if album_rg then
        append(c, "",
               {
                   prefix = "Album:",
                   indent = o.indent .. o.prefix_sep,
                   prefix_sep = "",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        append(c, t["replaygain-album-gain"],
               {
                   prefix = "Gain:",
                   suffix = " dB",
                   nl = "",
                   indent = o.prefix_sep,
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
        append(c, t["replaygain-album-peak"],
               {
                   prefix = "Peak:",
                   suffix = " dB",
                   nl = "",
                   indent = o.prefix_sep,
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
    end
    if t["dolby-vision-profile"] or t["dolby-vision-level"] then
        append(c, "",
               {
                   prefix = "Dolby Vision:"
               }
        )
        append(c, t["dolby-vision-profile"],
               {
                   prefix = "Profile:",
                   nl = "",
                   indent = ""
               }
        )
        append(c, t["dolby-vision-level"],
               {
                   prefix = "Level:",
                   nl = "",
                   indent = t["dolby-vision-profile"] and
                       o.prefix_sep .. o.prefix_sep or "",
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
    end
end

local function track_info()
    local h, c = {}, {}
    eval_ass_formatting()
    add_header(h)
    local desc = pages[o.key_page_5].desc
    append(h, "",
           {
               prefix = format("%s:%s", desc, scroll_hint()),
               nl = "",
               indent = "",
               no_prefix_markup = false,
               no_bold = false,
               second_highlight = false
           }
    )
    h = { table.concat(h) }
    table.insert(c, o.nl .. o.nl)
    add_file(c, false, true)
    for i, track in ipairs(mp.get_property_native("track-list")) do
        if track["selected"] or not o.track_info_selected_only then
            add_track(c, track, i - 1)
        end
    end
    return finalize_page(h, c, true)
end

local function perf_stats()
    local header, content = {}, {}
    eval_ass_formatting()
    add_header(header)
    local page = pages[o.key_page_0]
    append(header, "",
           {
               prefix = format("%s:%s", page.desc, scroll_hint()),
               nl = "",
               indent = "",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append_general_perfdata(content)
    header = { table.concat(header) }
    return finalize_page(header, content, true)
end

local function opt_time(t)
    if type(t) == type(1.1) then
        return mp.format_time(t)
    end
    return "?"
end

-- Returns an ASS string with stats about the demuxer cache etc.
local function cache_stats()
    local stats = {}

    eval_ass_formatting()
    add_header(stats)
    append(stats, "",
           {
               prefix = "Cache Info:",
               nl = "",
               indent = "",
               no_prefix_markup = false,
               no_bold = false,
               second_highlight = false
           }
    )

    local info = mp.get_property_native("demuxer-cache-state")
    if info == nil then
        append(stats, "Unavailable.", {})
        return finalize_page({}, stats, false)
    end

    local a = info["reader-pts"]
    local b = info["cache-end"]

    append(stats, opt_time(a) .. " - " .. opt_time(b),
           {
               prefix = "Packet Queue:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )

    local r = nil
    if a ~= nil and b ~= nil then
        r = b - a
    end

    local r_graph = nil
    if display_timer and not display_timer.oneshot and o.use_ass and o.plot_cache then
        r_graph = generate_graph(cache_ahead_buf, cache_ahead_buf.pos,
                                 cache_ahead_buf.len, cache_ahead_buf.max,
                                 nil, 0.8, 1)
        r_graph = o.prefix_sep .. r_graph
    end
    append(stats, opt_time(r),
           {
               prefix = "Readahead:",
               suffix = r_graph,
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )

    -- These states are not necessarily exclusive. They're about potentially
    -- separate mechanisms, whose states may be decoupled.
    local state = "reading"
    local seek_ts = info["debug-seeking"]
    if seek_ts ~= nil then
        state = "seeking (to " .. mp.format_time(seek_ts) .. ")"
    elseif info["eof"] == true then
        state = "eof"
    elseif info["underrun"] then
        state = "underrun"
    elseif info["idle"] == true then
        state = "inactive"
    end
    append(stats, state,
           {
               prefix = "State:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )

    local speed = info["raw-input-rate"] or 0
    local speed_graph = nil
    if display_timer and not display_timer.oneshot and o.use_ass and o.plot_cache then
        speed_graph = generate_graph(cache_speed_buf, cache_speed_buf.pos,
                                     cache_speed_buf.len, cache_speed_buf.max,
                                     nil, 0.8, 1)
        speed_graph = o.prefix_sep .. speed_graph
    end
    append(stats, utils.format_bytes_humanized(speed) .. "/s",
           {
               prefix = "Speed:",
               suffix = speed_graph,
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )

    append(stats, utils.format_bytes_humanized(info["total-bytes"]),
           {
               prefix = "Total RAM:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(stats, utils.format_bytes_humanized(info["fw-bytes"]),
           {
               prefix = "Forward RAM:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )

    local fc = info["file-cache-bytes"]
    if fc ~= nil then
        fc = utils.format_bytes_humanized(fc)
    else
        fc = "(disabled)"
    end
    append(stats, fc,
           {
               prefix = "Disk Cache:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )

    append(stats, info["debug-low-level-seeks"],
           {
               prefix = "Media Seeks:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(stats, info["debug-byte-level-seeks"],
           {
               prefix = "Stream Seeks:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )

    append(stats, "",
           {
               prefix = "Ranges:",
               nl = o.nl .. o.nl,
               indent = "",
               no_prefix_markup = false,
               no_bold = false,
               second_highlight = false
           }
    )

    append(stats, info["bof-cached"] and "yes" or "no",
           {
               prefix = "Start Cached:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )
    append(stats, info["eof-cached"] and "yes" or "no",
           {
               prefix = "End Cached:",
               no_prefix_markup = true,
               no_bold = true,
               second_highlight = false
           }
    )

    local ranges = info["seekable-ranges"] or {}
    for n, range in ipairs(ranges) do
        append(stats, mp.format_time(range["start"]) .. " - " ..
               mp.format_time(range["end"]),
               {
                   prefix = format("Range %s:", n),
                   no_prefix_markup = true,
                   no_bold = true,
                   second_highlight = false
               }
        )
    end

    return finalize_page({}, stats, false)
end

-- Record 1 sample of cache statistics.
-- (Unlike record_data(), this does not return a function, but runs directly.)
local function record_cache_stats()
    local info = mp.get_property_native("demuxer-cache-state")
    if info == nil then
        return
    end

    local a = info["reader-pts"]
    local b = info["cache-end"]
    if a ~= nil and b ~= nil then
        graph_add_value(cache_ahead_buf, b - a)
    end

    graph_add_value(cache_speed_buf, info["raw-input-rate"] or 0)
end

cache_recorder_timer = mp.add_periodic_timer(0.25, record_cache_stats)
cache_recorder_timer:kill()

-- Current page and <page key>:<page function> mapping
curr_page = o.key_page_1
pages = {
    [o.key_page_1] = { idx = 1, f = default_stats, desc = "General Statistics", scroll = true },
    [o.key_page_2] = { idx = 2, f = vo_stats, desc = "Extended Frame Timings", scroll = true },
    [o.key_page_3] = { idx = 3, f = cache_stats, desc = "Cache Statistics" },
    [o.key_page_4] = { idx = 4, f = keybinding_info, desc = "Active Key Bindings", scroll = true },
    [o.key_page_5] = { idx = 5, f = track_info, desc = "Tracks Info", scroll = true },
    [o.key_page_0] = { idx = 0, f = perf_stats, desc = "Internal Performance Info", scroll = true },
}


-- Returns a function to record vsratio/jitter with the specified `skip` value
local function record_data(skip)
    init_buffers()
    skip = max(skip, 0)
    local i = skip
    return function()
        if i < skip then
            i = i + 1
            return
        else
            i = 0
        end

        if o.plot_vsync_jitter then
            local r = mp.get_property_number("vsync-jitter")
            if r then
                vsjitter_buf.pos = (vsjitter_buf.pos % vsjitter_buf.len) + 1
                vsjitter_buf[vsjitter_buf.pos] = r
                vsjitter_buf.max = max(vsjitter_buf.max, r)
            end
        end

        if o.plot_vsync_ratio then
            local r = mp.get_property_number("vsync-ratio")
            if r then
                vsratio_buf.pos = (vsratio_buf.pos % vsratio_buf.len) + 1
                vsratio_buf[vsratio_buf.pos] = r
                vsratio_buf.max = max(vsratio_buf.max, r)
            end
        end
    end
end

-- Call the function for `page` and print it to OSD
local function print_page(page, after_scroll)
    -- the page functions assume we start in ass-enabled mode.
    -- that's true for mp.set_osd_ass, but not for mp.osd_message.
    local ass_content = pages[page].f(after_scroll)
    if o.persistent_overlay then
        mp.set_osd_ass(0, 0, ass_content)
    else
        mp.osd_message((o.use_ass and ass_start or "") .. ass_content,
                       display_timer and display_timer.oneshot and o.duration or o.redraw_delay + 1)
    end
    mp.set_property_bool("user-data/mpv/stats/open", true)
end

update_scale = function()
    local scale_with_video
    if o.vidscale == "auto" then
        scale_with_video = mp.get_property_native("osd-scale-by-window")
    else
        scale_with_video = o.vidscale == "yes"
    end

    -- Calculate scaled metrics.
    -- Make font_size=n the same size as --osd-font-size=n.
    local scale = 288 / 720
    local osd_height = mp.get_property_native("osd-height")
    if not scale_with_video and osd_height > 0 then
        scale = 288 / osd_height
    end
    font_size = o.font_size * scale
    local font_size_padded = (o.font_size + o.font_padding) * scale
    local line_padding = "{\\fs" .. font_size_padded .. "}\\h {\\fs" .. font_size .. "}"
    o.ass_nl = line_padding .. "\\N" .. line_padding
    border_size = o.border_size * scale
    shadow_x_offset = o.shadow_x_offset * scale
    shadow_y_offset = o.shadow_y_offset * scale
    plot_bg_border_width = o.plot_bg_border_width * scale
    if display_timer and display_timer:is_enabled() then
        print_page(curr_page)
    end
end

local function clear_screen()
    if o.persistent_overlay then mp.set_osd_ass(0, 0, "") else mp.osd_message("", 0) end
    mp.set_property_bool("user-data/mpv/stats/open", false)
end

local function scroll_delta(d)
    if display_timer and display_timer.oneshot then
        display_timer:kill(); display_timer:resume()
    end
    pages[curr_page].offset = (pages[curr_page].offset or 1) + d
    print_page(curr_page, true)
end
local function scroll_up() scroll_delta(-o.scroll_lines) end
local function scroll_down() scroll_delta(o.scroll_lines) end

local function reset_scroll_offsets()
    for _, page in pairs(pages) do
        page.offset = nil
    end
end
local function bind_scroll()
    if not scroll_bound then
        mp.add_forced_key_binding(o.key_scroll_up, "__forced_" .. o.key_scroll_up,
                                  scroll_up, { repeatable = true })
        mp.add_forced_key_binding(o.key_scroll_down, "__forced_" .. o.key_scroll_down,
                                  scroll_down, { repeatable = true })
        scroll_bound = true
    end
end
local function unbind_scroll()
    if scroll_bound then
        mp.remove_key_binding("__forced_" .. o.key_scroll_up)
        mp.remove_key_binding("__forced_" .. o.key_scroll_down)
        scroll_bound = false
    end
end

local add_page_bindings
local remove_page_bindings

local function filter_bindings()
    input.get({
        prompt = "Filter bindings:",
        opened = function()
            -- This is necessary to close the console if the oneshot
            -- display_timer expires without typing anything.
            searched_text = ""

            -- Must be re-bound to override the console.lua bindings.
            remove_page_bindings()
            bind_scroll()
        end,
        edited = function(text)
            reset_scroll_offsets()
            searched_text = text:lower()
            print_page(curr_page)
            if display_timer and display_timer.oneshot then
                display_timer:kill()
                display_timer:resume()
            end
        end,
        closed = function()
            searched_text = nil
            if display_timer and display_timer:is_enabled() then
                add_page_bindings()
                print_page(curr_page)
                if display_timer.oneshot then
                    display_timer:kill()
                    display_timer:resume()
                end
            end
        end,
    })
end

local function bind_search()
    mp.add_forced_key_binding(o.key_search, "__forced_" .. o.key_search, filter_bindings)
end

local function unbind_search()
    mp.remove_key_binding("__forced_" .. o.key_search)
end

local function bind_exit()
    -- Don't bind in oneshot mode because if ESC is pressed right when the stats
    -- stop being displayed, it would unintentionally trigger any user-defined
    -- ESC binding.
    if display_timer and not display_timer.oneshot then
        mp.add_forced_key_binding(o.key_exit, "__forced_" .. o.key_exit, function()
            process_key_binding(false)
        end)
    end
end

local function unbind_exit()
    mp.remove_key_binding("__forced_" .. o.key_exit)
end

local function update_scroll_bindings(k)
    if pages[k].scroll then
        bind_scroll()
    else
        unbind_scroll()
    end

    if k == o.key_page_4 then
        bind_search()
    else
        unbind_search()
    end
end

-- Add keybindings for every page
add_page_bindings = function()
    local function a(k)
        return function()
            reset_scroll_offsets()
            update_scroll_bindings(k)
            curr_page = k
            print_page(k)
            if display_timer and display_timer.oneshot then
                display_timer:kill(); display_timer:resume()
            end
        end
    end
    for k, _ in pairs(pages) do
        mp.add_forced_key_binding(k, "__forced_" .. k, a(k), { repeatable = true })
    end
    update_scroll_bindings(curr_page)
    bind_exit()
end


-- Remove keybindings for every page
remove_page_bindings = function()
    for k, _ in pairs(pages) do
        mp.remove_key_binding("__forced_" .. k)
    end
    unbind_scroll()
    unbind_search()
    unbind_exit()
end


process_key_binding = function(oneshot)
    reset_scroll_offsets()
    if not display_timer then return false end
    -- Stats are already being displayed
    if display_timer:is_enabled() then
        -- Previous and current keys were oneshot -> restart timer
        if display_timer.oneshot and oneshot then
            display_timer:kill()
            print_page(curr_page)
            display_timer:resume()
            -- Previous and current keys were toggling -> end toggling
        elseif not display_timer.oneshot and not oneshot then
            display_timer:kill()
            cache_recorder_timer:stop()
            if tm_viz_prev ~= nil then
                mp.set_property_native("tone-mapping-visualize", tm_viz_prev)
                tm_viz_prev = nil
            end
            clear_screen()
            remove_page_bindings()
            if recorder then
                mp.unobserve_property(recorder)
                recorder = nil
            end
        end
        -- No stats are being displayed yet
    else
        if not oneshot and (o.plot_vsync_jitter or o.plot_vsync_ratio) then
            recorder = record_data(o.skip_frames)
            -- Rely on the fact that "vsync-ratio" is updated at the same time.
            -- Using "none" to get a sample any time, even if it does not change.
            -- Will stop working if "vsync-jitter" property change notification
            -- changes, but it's fine for an internal script.
            mp.observe_property("vsync-jitter", "none", recorder)
        end
        if not oneshot and o.plot_tonemapping_lut then
            tm_viz_prev = mp.get_property_native("tone-mapping-visualize")
            mp.set_property_native("tone-mapping-visualize", true)
        end
        if not oneshot then
            cache_ahead_buf = { 0, pos = 1, len = 50, max = 0 }
            cache_speed_buf = { 0, pos = 1, len = 50, max = 0 }
            cache_recorder_timer:resume()
        end
        display_timer:kill()
        display_timer.oneshot = oneshot
        display_timer.timeout = oneshot and o.duration or o.redraw_delay
        add_page_bindings()
        print_page(curr_page)
        display_timer:resume()
    end
end


-- Create the timer used for redrawing (toggling) or clearing the screen (oneshot)
-- The duration here is not important and always set in process_key_binding()
display_timer = mp.add_periodic_timer(
    o.duration,
    function()
        if display_timer and display_timer.oneshot then
            display_timer:kill(); clear_screen(); remove_page_bindings()
            -- Close the console only if it was opened for searching bindings.
            if searched_text then
                input.terminate()
            end
        else
            print_page(curr_page)
        end
    end
)
display_timer:kill()

-- Single invocation key binding
mp.add_key_binding(
    nil,
    "display-stats",
    function() process_key_binding(true) end,
    { repeatable = true }
)

-- Toggling key binding
mp.add_key_binding(
    nil,
    "display-stats-toggle",
    function() process_key_binding(false) end,
    { repeatable = false }
)

for k, page in pairs(pages) do
    -- Single invocation key bindings for specific pages, e.g.:
    -- "e script-binding stats/display-page-2"
    mp.add_key_binding(
        nil,
        "display-page-" .. page.idx,
        function()
            curr_page = k
            process_key_binding(true)
        end,
        { repeatable = true }
    )

    -- Key bindings to toggle a specific page, e.g.:
    -- "h script-binding stats/display-page-4-toggle".
    mp.add_key_binding(
        nil,
        "display-page-" .. page.idx .. "-toggle",
        function()
            curr_page = k
            process_key_binding(false)
        end,
        { repeatable = false }
    )
end

-- Reprint stats immediately when VO was reconfigured, only when toggled
mp.register_event(
    "video-reconfig",
    function()
        if display_timer:is_enabled() and not display_timer.oneshot then
            print_page(curr_page)
        end
    end
)

if o.bindlist ~= "no" then
    -- This is a special mode to print key bindings to the terminal,
    -- Adjust the print format and level to make it print only the key bindings.
    mp.set_property("msg-level", "all=no,statusline=status")
    mp.set_property("term-osd", "force")
    mp.set_property_bool("msg-module", false)
    mp.set_property_bool("msg-time", false)
    -- wait for all other scripts to finish init
    mp.add_timeout(0, function()
        if o.bindlist:sub(1, 1) == "-" then
            o.no_ass_b0 = ""
            o.no_ass_b1 = ""
        end
        o.ass_formatting = false
        o.no_ass_indent = " "
        mp.osd_message(keybinding_info(false, true))
        -- wait for next tick to print status line and flush it without clearing
        mp.add_timeout(0, function()
            mp.command("flush-status-line no")
            mp.command("quit")
        end)
    end)
end

mp.observe_property("osd-height", "native", update_scale)
mp.observe_property("osd-scale-by-window", "native", update_scale)

local function update_property_cache(name, value)
    property_cache[name] = value
end

local function update_profiles_cache(name, value)
    profiles = {}
    for _, profile in ipairs(value) do
        local max_length = string.len(profile["name"])
        profiles[profile["name"]] = profile
        local sub_profiles = {}
        for _, option in pairs(profile["options"]) do
            if option["key"] == "profile" then
                table.insert(sub_profiles, option["value"])
                if string.len(option["value"]) > max_length then
                    max_length = string.len(option["value"])
                end
            end
        end
        profiles[profile["name"]]["sub_profiles"] = sub_profiles
        profiles[profile["name"]]["max_length"] = max_length
    end
    profiles_max_length = 0
end

local function update_auto_profiles()
    local active_profiles = mp.get_property_native("user-data/custom_auto_profiles/active_profiles")
    if not active_profiles then return end

    profiles_max_length = 0
    for key, profile in pairs(profiles) do
        profiles[key]["active"] = false
        for _, active_profile_name in ipairs(active_profiles) do
            if profile.name == active_profile_name then
                profiles[key]["active"] = true
                if profiles[key]["max_length"] > profiles_max_length then
                    profiles_max_length = profiles[key]["max_length"]
                end
            end
        end
    end
end

mp.observe_property("current-window-scale", "native", update_property_cache)
mp.observe_property("display-names", "string", update_property_cache)
mp.observe_property("hwdec-current", "string", update_property_cache)
mp.observe_property("profile-list", "native", update_profiles_cache)
mp.observe_property("user-data/custom_auto_profiles/active_profiles", "native", update_auto_profiles)
