local options = require "mp.options"
local msg = require "mp.msg"
local utils = require "mp.utils"
local ass_start = mp.get_property_osd("osd-ass-cc/0")
local ass_stop = mp.get_property_osd("osd-ass-cc/1")

local function bind_each_relative_seek(key, click_delta, repeat_delta)
    local click_data = {
        click = "script-message playback-controls seek " .. click_delta,
        ["repeat"] = "script-message playback-controls seek " .. repeat_delta,
    }
    local json, err = utils.format_json(click_data)
<<<<<<< HEAD
    if json then
        mp.commandv('script-message-to', 'inputevent', 'bind', key, json)
    else
        mp.error('Failed to parse json', err)
    end
=======
    mp.commandv('script-message-to', 'inputevent', 'bind', key, json)
>>>>>>> 2acee3ce159775c21cc37da99c7ce0fc1aa24bc9
end

local function bind_relative_seek()
    local relative_seek_keys = {
<<<<<<< HEAD
        [{ "z", "x" }] = { 1, 1 },
=======
        [{ "z", "x" }] = { 2, 1 },
>>>>>>> 2acee3ce159775c21cc37da99c7ce0fc1aa24bc9
        [{ "LEFT", "RIGHT" }] = { 2, 1 },
        [{ "a", "s" }] = { 10, 5 },
        [{ "q", "w" }] = { 20, 10 }
    }

    for keys, delta in pairs(relative_seek_keys) do
        repeat
            if delta[1] < 1 or delta[2] < 1 then
                do break end -- simulate continue
            end
            for index, key in ipairs(keys) do
                local remainder = math.fmod(index + 2, 2)
                if remainder == 0 then
<<<<<<< HEAD
                    bind_each_relative_seek(key, delta[1], delta[2])   -- Remainder 0 - Seek Forward - Keep value positive
                else
                    bind_each_relative_seek(key, -delta[1], -delta[2]) -- Remainder 1 - Seek Reverse - Make value positive
                end
=======
                    bind_each_relative_seek(key, delta[1], delta[2]) -- Remainder 0 - Seek Forward - Keep value positive
                else
                    bind_each_relative_seek(key, -delta[1], -delta[2])
                end -- Remainder 1 - Seek Reverse - Make value positive
>>>>>>> 2acee3ce159775c21cc37da99c7ce0fc1aa24bc9
            end
        until true
    end
end

local function bind_absolute_seek()
    for key = 0, 9 do
        local base = key * 10
        local click_data = {
            click = "seek  " ..
                base + 0 .. " absolute-percent+exact ; show-text '${osd-ass-cc/0}{\\an5}{\\fs20}" .. base + 0 .. "%'",
            double_click = "seek  " ..
                base + 2 .. " absolute-percent+exact ; show-text '${osd-ass-cc/0}{\\an5}{\\fs20}" .. base + 2 .. "%'",
            triple_click = "seek  " ..
                base + 4 .. " absolute-percent+exact ; show-text '${osd-ass-cc/0}{\\an5}{\\fs20}" .. base + 4 .. "%'",
            quatra_click = "seek  " ..
                base + 6 .. " absolute-percent+exact ; show-text '${osd-ass-cc/0}{\\an5}{\\fs20}" .. base + 6 .. "%'",
            penta_click = "seek  " ..
                base + 8 .. " absolute-percent+exact ; show-text '${osd-ass-cc/0}{\\an5}{\\fs20}" .. base + 8 .. "%'",
        }
        local json, err = utils.format_json(click_data)
<<<<<<< HEAD
        if json then
            mp.commandv('script-message-to', 'inputevent', 'bind', key, json)
        else
            mp.error('Failed to parse json', err)
        end
    end
end

local function on_seek(seek_delta_string, msg_delay_string)
    local seek_delta = tonumber(seek_delta_string)
    local msg_delay = tonumber(msg_delay_string) or 2

    if seek_delta == nil or seek_delta == 0 then return end

    local osd_text = ass_start

    if seek_delta > 0 then
        osd_text = osd_text ..
            "{\\an6}{\\fs20}" ..
            math.abs(seek_delta) .. "s{\\fs10}{\\fnmodernz-icons} material_fast_forward_filled {\\fnosd-font}"
    else
        osd_text = osd_text ..
            "{\\an4}{\\fs10}{\\fnmodernz-icons} material_fast_rewind_filled {\\fnosd-font}{\\fs20}" ..
            math.abs(seek_delta) .. "s"
=======
        mp.commandv('script-message-to', 'inputevent', 'bind', key, json)
    end
end

local function on_seek(delta_string, delay_string)
    local delta = tonumber(delta_string)
    local delay = tonumber(delay_string) or 2

    if delta == nil or delta == 0 then return end

    local osd_text = ass_start

    if delta > 0 then
        osd_text = osd_text ..
            "{\\an6}{\\fs20}" ..
            math.abs(delta) .. "s{\\fs10}{\\fnmodernz-icons} material_fast_forward_filled {\\fnosd-font}"
    else
        osd_text = osd_text ..
            "{\\an4}{\\fs10}{\\fnmodernz-icons} material_fast_rewind_filled {\\fnosd-font}{\\fs20}" ..
            math.abs(delta) .. "s"
>>>>>>> 2acee3ce159775c21cc37da99c7ce0fc1aa24bc9
    end

    osd_text = osd_text .. ass_stop

<<<<<<< HEAD
    mp.commandv("seek", seek_delta, "exact")
    mp.osd_message(osd_text, msg_delay)
end

local function handle_message(arg1, arg2, arg3)
    if arg1 == "seek" then
        on_seek(arg2, arg3)
=======
    mp.commandv("seek", delta, "exact")
    mp.osd_message(osd_text, delay)
end

local function handle_message(command, value_1, value_2)
    if command == "seek" then
        on_seek(value_1, value_2)
>>>>>>> 2acee3ce159775c21cc37da99c7ce0fc1aa24bc9
    end
end

local function custom_seek(value)
    msg.info("Custom Seek", value)
end

<<<<<<< HEAD
mp.register_script_message("playback-controls", handle_message)
=======
mp.register_script_message("playback-controls", handle_message, command, value_1, value_2)
>>>>>>> 2acee3ce159775c21cc37da99c7ce0fc1aa24bc9
mp.add_key_binding(nil, "custom_seek", custom_seek)
bind_absolute_seek()
bind_relative_seek()
