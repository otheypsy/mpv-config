--=============================================================================
-->>    SUBLIMINAL PATH:
--=============================================================================
--          This script uses Subliminal to download subtitles,
--          so make sure to specify your system's Subliminal location below:
local subliminal =
'C:\\Users\\omkar\\AppData\\Local\\Programs\\Python\\Python314\\Scripts\\subliminal.exe'
--=============================================================================
-->>    SUBTITLE LANGUAGE:
--=============================================================================
--          Specify languages in this order:
--          { 'language name', 'ISO-639-1', 'ISO-639-2' } !
--          (See: https://en.wikipedia.org/wiki/List_of_ISO_639-1_codes)
local languages = {
    --          If subtitles are found for the first language,
    --          other languages will NOT be downloaded,
    --          so put your preferred language first:
    { 'English', 'en', 'eng' }
}
--=============================================================================
-->>    PROVIDER LOGINS:
--=============================================================================
--          These are completely optional and not required
--          for the functioning of the script!
--          If you use any of these services, simply uncomment it
--          and replace 'USERNAME' and 'PASSWORD' with your own:
local logins = {
    --          { '--addic7ed', 'USERNAME', 'PASSWORD' },
    --          { '--legendastv', 'USERNAME', 'PASSWORD' },
    --          { '--opensubtitles', 'USERNAME', 'PASSWORD' },
    --          { '--subscenter', 'USERNAME', 'PASSWORD' },
}
--=============================================================================
-->>    ADDITIONAL OPTIONS:
--=============================================================================
local bools = {
    auto = false,  -- Automatically download subtitles, no hotkeys required
    debug = false, -- Use `--debug` in subliminal command for debug output
    force = false, -- Force download; will overwrite existing subtitle files
    utf8 = true,   -- Save all subtitle files as UTF-8
}
local excludes = {
    -- Movies with a path containing any of these strings/paths
    -- will be excluded from auto-downloading subtitles.
    -- Full paths are also allowed, e.g.:
    -- '/home/david/Videos',
    'no-subs-dl',
}
local includes = {
    -- If anything is defined here, only the movies with a path
    -- containing any of these strings/paths will auto-download subtitles.
    -- Full paths are also allowed, e.g.:
    -- '/home/david/Videos',
}
--=============================================================================
local msg = require "mp.msg"
local utils = require "mp.utils"

local directory = ""
local filename = ""
local sub_tracks = {}


-- Check if subtitles should be auto-downloaded:
local function auto_sub_allowed()
    local duration = tonumber(mp.get_property('duration'))
    local active_format = mp.get_property('file-format')

    if not bools.auto then
        msg.debug('Automatic downloading disabled!')
        return false
    elseif duration < 900 then
        msg.warn('Skip subtitle auto-download for video less than 15 minutes')
        return false
    elseif directory:find('^http') then
        msg.warn('Skip subtitle auto-download for web streaming')
        return false
    elseif active_format:find('^cue') then
        msg.warn('Skip subtitle auto-download for cue files')
        return false
    else
        local not_allowed = { 'aiff', 'ape', 'flac', 'mp3', 'ogg', 'wav', 'wv',
            'tta' }

        for _, file_format in pairs(not_allowed) do
            if file_format == active_format then
                msg.warn('Skip subtitle auto-download for audio files')
                return false
            end
        end

        for _, exclude in pairs(excludes) do
            local escaped_exclude = exclude:gsub('%W', '%%%0')
            local excluded = directory:find(escaped_exclude)

            if excluded then
                msg.warn('Path is excluded for auto-download')
                return false
            end
        end

        for i, include in ipairs(includes) do
            local escaped_include = include:gsub('%W', '%%%0')
            local included = directory:find(escaped_include)

            if included then
                break
            elseif i == #includes then
                msg.warn(
                    'Path must be included if the `includes` configuration is set')
                return false
            end
        end
    end

    return true
end

-- Check if subtitles should be downloaded in this language:

local function should_download_subs_in(language)
    for i, track in ipairs(sub_tracks) do
        local subtitles = track['external'] and
            'subtitle file' or 'embedded subtitles'

        if     not track['lang']
        and    (track['external']
            or not track['title'])
        and    i == #sub_tracks then
            return false -- Don't download if 'lang' key is absent
        elseif track['lang'] == language[3] or track['lang'] == language[2] or
               (track['title'] and track['title']:lower():find(language[3])) then
            return false -- The right subtitles are already present
        end
    end
    return true
end

-- Download function: download the best subtitles in most preferred language
function Download_Subs(language)
    language = language or languages[1]
    if #language == 0 then
        msg.debug('No Language found\n')
        return false
    end

    msg.info('Searching ' .. language[1] .. ' subtitles ...')
    mp.osd_message('Searching ' .. language[1] .. ' subtitles ...', 10)

    -- Build the `subliminal` command, starting with the executable:
    local table = { args = { subliminal } }
    local a = table.args

    for _, login in ipairs(logins) do
        a[#a+1] = login[1]
        a[#a+1] = login[2]
        a[#a+1] = login[3]
    end
    if bools.debug then
        -- To see `--debug` output start MPV from the terminal!
        a[#a+1] = '--debug'
    end

    a[#a+1] = 'download'
    if bools.force then
        a[#a+1] = '-f'
    end
    if bools.utf8 then
        a[#a+1] = '-e'
        a[#a+1] = 'utf-8'
    end

    a[#a+1] = '-l'
    a[#a+1] = language[2]
    a[#a+1] = '-d'
    a[#a+1] = directory
    a[#a+1] = filename --> Subliminal command ends with the movie filename.

    local result = utils.subprocess(table)

    if result and string.find(result.stdout, 'Downloaded 1 subtitle') then
        -- When multiple external files are present,
        -- always activate the most recently downloaded:
        mp.set_property('slang', language[2])
        -- Subtitles are downloaded successfully, so rescan to activate them:
        mp.commandv('rescan_external_files')
        msg.info(language[1] .. ' subtitles ready!')
        mp.osd_message(language[1] .. ' subtitles ready!', 10)
        return true
    else
        msg.info('No ' .. language[1] .. ' subtitles found')
        mp.osd_message('No ' .. language[1] .. ' subtitles found', 10)
        return false
    end
end

function On_File_Loaded()
    mp.set_property('sub-auto', 'fuzzy')
    mp.set_property('slang', languages[1][2])
    local found_local_subs = false
    local path = utils.split_path(mp.get_property("path") or "")
    directory = path[0] or ""
    filename = path[1] or ""
    local dir_files = utils.readdir(directory, "files")

    if not directory or not filename or not dir_files then
        return false
    end

    local dir_files = utils.readdir(directory, "files")

    if not dir_files then
        return false
    end

    for _, name in ipairs(dir_files) do
        if string.find(name, "%.srt$") then
            local search_string = name
                :gsub("%.srt$", "")
                :gsub("%.en$", "")
                :gsub("%-en$", "")
                :gsub("%-", "%%-")

            if string.find(filename, search_string) and string.find(name, "%.srt") then
                local sub_file = utils.join_path(directory, name)
                mp.commandv("sub-add", sub_file)
                found_local_subs = true
                local notification = "Found subtitle file " .. sub_file
                msg.info(notification)
                mp.commandv('show-text', notification)
            end
        end
    end

    if found_local_subs or not auto_sub_allowed() then
        return true
    end

    local track_list = mp.get_property_native('track-list')
    if not track_list then
        return false
    end

    sub_tracks = {}
    for _, track in ipairs(track_list) do
        if track['type'] == 'sub' then
            sub_tracks[#sub_tracks+1] = track
        end
    end
    if bools.debug then -- Log subtitle properties to terminal:
        msg.debug(utils.format_json(sub_tracks))
    end

    for _, language in ipairs(languages) do
        if should_download_subs_in(language) then
            if Download_Subs(language) then
                return true
            end
        else
            return true
        end -- No need to download!
    end
    msg.info('No subtitles found')
end

function Download_Secondary_Subs()
    Download_Subs(languages[2])
end

mp.add_key_binding('b', 'download_subs', Download_Subs)
mp.add_key_binding('n', 'download_subs2', Download_Secondary_Subs)
mp.register_event('file-loaded', On_File_Loaded)
