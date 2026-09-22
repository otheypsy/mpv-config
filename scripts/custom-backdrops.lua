local assdraw = require "mp.assdraw"
local options = require "mp.options"

local opts = {
    backdrop_opacity = 0.0,
    z_index = -1.0
}
options.read_options(opts, "custom-backdrops", function() end)


local backdrop_overlay = mp.create_osd_overlay("ass-events")
local console_open = false
local stats_open = false


local function draw_backdrop()
    local ass = assdraw.ass_new()
    local w, h, _ = mp.get_osd_size()
    local alpha = math.ceil(255 * (1 - opts.backdrop_opacity))

    ass.text = string.format(
        "{\\pos(0,0)\\rDefault\\an7\\1c&H000000&\\alpha&H%X&}", alpha)
    ass:draw_start()
    ass:rect_cw(0, 0, w, h)
    ass:draw_stop()
    ass:new_event()
    backdrop_overlay.data = ass.text
    backdrop_overlay.z = opts.z_index
    backdrop_overlay:update()
end

local function clear_backdrop()
    backdrop_overlay.data = ""
    backdrop_overlay:remove()
end

local function handle_backdrop()
    if console_open or stats_open then
        draw_backdrop()
    else
        clear_backdrop()
    end
end

local function on_console_change(_, value)
    console_open = value
    mp.commandv("script-binding", "playlist_manager/close-playlist")
    if console_open and stats_open then
        mp.commandv("script-binding", "stats/display-stats-toggle")
    end
    handle_backdrop()
end

local function on_stats_change(_, value)
    stats_open = value
    mp.commandv("script-binding", "playlist_manager/close-playlist")
    handle_backdrop()
end

mp.observe_property("user-data/mpv/console/open", "bool", on_console_change)
mp.observe_property("user-data/mpv/stats/open", "bool", on_stats_change)
mp.observe_property("osd-dimensions", "native", handle_backdrop)
