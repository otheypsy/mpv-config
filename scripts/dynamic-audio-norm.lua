--[[
mpv dynaudnorm filter with visual feedback.

Copyright 2016 Avi Halachmi ( https://github.com/avih )
Copyright 2020 Paul B Mahol
License: public domain

Needs mpv with very recent FFmpeg build.

Default config:
- Enter/exit drcbox keys mode: ctrl+n
- Toggle dynaudnorm without changing its values: ctrl+N (ctrl+shift+n)
- Reset dynaudnorm values: alt+ctrl+n
--]]
-- ------ config -------

local options             = {
    display_font_size = 26,
    { keys = { 'ALT+1', '!' }, option = { 'framelen', 1, 10, 8000, 500, 500 } },
    { keys = { 'ALT+2', '@' }, option = { 'gausssize', 1, 3, 301, 31, 31 } },
    { keys = { 'ALT+3', '#' }, option = { 'peak', 0.01, 0, 1, 0.95, 0.95 } },
    { keys = { 'ALT+4', '$' }, option = { 'maxgain', 1, 1, 100, 10, 10 } },
    { keys = { 'ALT+5', '%' }, option = { 'targetrms', 0.01, 0, 1, 0, 0 } },
    { keys = { 'ALT+6', '^' }, option = { 'coupling', 1, 0, 1, 1, 1 } },
    { keys = { 'ALT+7', '&' }, option = { 'correctdc', 1, 0, 1, 0, 0 } },
    { keys = { 'ALT+8', '*' }, option = { 'compress', 0.1, 0, 30, 0, 0 } },
}

local start_keys_enabled  = false        -- if true then choose the up/down keys wisely
local key_toggle_bindings = 'CTRL+n'     -- enable/disable drcbox key bindings
local key_toggle_drc_box  = 'CTRL+N'     -- enable/disable drcbox
local key_reset_drc_box   = 'CTRL+ALT+n' -- reset drcbox
local scaled_font_size    = options.display_font_size

local function get_cmd_full()
    f = options[1].option[5]
    g = options[2].option[5]
    p = options[3].option[5]
    m = options[4].option[5]
    r = options[5].option[5]
    n = options[6].option[5]
    c = options[7].option[5]
    s = options[8].option[5]
    return 'no-osd af toggle @dynaudnorm:lavfi=[dynaudnorm=f=' ..
        f ..
        ':g=' .. g .. ':p=' ..
        p ..
        ':m=' .. m .. ':r=' .. r .. ':n=' .. n .. ':c=' .. c .. ':s=' .. s ..
        ']'
end

local function get_cmd(option)
    return 'no-osd af-command dynaudnorm ' .. option[1] .. ' ' .. option[5]
end

-- these two vars are used globally
local bindings_enabled = start_keys_enabled
local drc_box_enabled = false -- but af is not touched before the dynaudnorm is modified

-- ------ OSD handling -------
local function ass(x)
    return x
end

local function font_size(s) -- 100 is the normal font size
    return ass(string.format('{\\fs%s}', s))
end

-- white
local function c_norm()
    return '{\\1c&Hffffff&}'
end

-- grey
local function c_dis()
    return '{\\1c&H909090&}'
end

-- yellow-ish
local function c_eq()
    return drc_box_enabled and '{\\1c&H90ffff&}' or c_dis()
end

-- green-ish
local function c_keys()
    return bindings_enabled and '{\\1c&H90FF90&}' or c_dis()
end

local DUR_DEFAULT = 4
local osd_timer = nil

local function ass_osd(msg, duration)
    duration = duration or DUR_DEFAULT
    if not msg or msg == '' then
        msg = '{}'
        duration = 0
    end
    mp.set_osd_ass(0, 0, msg)
    if osd_timer then
        osd_timer:kill()
        osd_timer = nil
    end
    if duration > 0 then
        osd_timer = mp.add_timeout(duration, ass_osd)
    end
end

local function round(num, numDecimalPlaces)
    return tonumber(string.format("%." .. (numDecimalPlaces or 0) .. "f", num))
end

-- some visual messing about
local function updateOSD()
    local msg1 = font_size(scaled_font_size) ..
        'DynAudNorm: ' .. c_eq() .. (drc_box_enabled and 'On' or 'Off')
        .. ' [' .. key_toggle_drc_box .. ']' .. c_norm()
    local msg2 = 'Key-bindings: ' ..
        c_keys() .. (bindings_enabled and 'On' or 'Off')
        .. ' [' .. key_toggle_bindings .. ']' .. c_norm()
    local msg3 = ''

    for i = 1, #options do
        local option = options[i].option[1]
        local value = round(options[i].option[5], 2)
        local default = options[i].option[6]
        local info =
            c_eq() ..
            font_size(scaled_font_size) ..
            option .. ' ' .. font_size(scaled_font_size)
            .. ((value ~= default and drc_box_enabled) and '' or c_dis()) ..
            value .. c_eq()
            ..
            font_size(scaled_font_size) ..
            c_keys() ..
            ' [' .. options[i].keys[1] .. '/' .. options[i].keys[2] .. ']'
            .. c_eq() .. font_size(scaled_font_size) .. c_norm()

        msg3 = msg3 .. '   ' .. info
    end

    local msg = ass('{\\an7}') .. msg1 .. " \u{22EE} " .. msg2 .. "\n" .. msg3
    local duration = start_keys_enabled
        and ((bindings_enabled and drc_box_enabled) and 5 or nil)
        or (bindings_enabled and 0 or nil)
    ass_osd(msg, duration)
end


local function update_key_binding(enable, key, name, fn)
    if enable then
        mp.add_forced_key_binding(key, name, fn, 'repeatable')
    else
        mp.remove_key_binding(name)
    end
end

local function updateAF()
    mp.command(get_cmd_full())
end

local function updateAF_options()
    if not drc_box_enabled then return end
    for i = 1, #options do
        local o = options[i].option
        mp.command(get_cmd(o))
    end
end

local function getBind(option, delta)
    return function() -- onKey
        option[5] = option[5] + delta
        if option[5] > option[4] then
            option[5] = option[4]
        end
        if option[5] < option[3] then
            option[5] = option[3]
        end
        updateAF_options()
        updateOSD()
    end
end

local function toggle_bindings(explicit, no_osd)
    bindings_enabled = (explicit ~= nil) and explicit or not bindings_enabled
    for i = 1, #options do
        local keys = options[i].keys
        local option = options[i].option[1]
        local delta = options[i].option[2]

        -- up
        update_key_binding(
            bindings_enabled,
            keys[1],
            'eq' .. keys[1],
            getBind(options[i].option, delta)
        )

        -- down
        update_key_binding(
            bindings_enabled,
            keys[2],
            'eq' .. keys[2],
            getBind(options[i].option, -delta)
        )
    end
    if not no_osd then updateOSD() end
end

local function toggle_drc_box()
    drc_box_enabled = not drc_box_enabled
    updateAF()
    updateOSD()
end

local function reset_drc_box()
    for i = 1, #options do
        options[i].option[5] = options[i].option[6]
    end
    updateAF_options()
    updateOSD()
end

local function on_change_osd_height()
    local osd_height = mp.get_property_native("osd-height") or 0
    if osd_height > 720 then
        scaled_font_size = math.ceil(options.display_font_size *
            (720 / osd_height))
    end
end
mp.observe_property("osd-height", "native", on_change_osd_height)


mp.add_forced_key_binding(key_toggle_drc_box, toggle_drc_box)
mp.add_forced_key_binding(key_toggle_bindings, toggle_bindings)
mp.add_forced_key_binding(key_reset_drc_box, reset_drc_box)
if bindings_enabled then
    toggle_bindings(true, true)
end
