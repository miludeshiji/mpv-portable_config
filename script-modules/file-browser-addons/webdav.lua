local mp = require "mp"
local msg = require "mp.msg"
local utils = require "mp.utils"
local input = require "mp.input"
local fb = require "file-browser"

local function expand(path)
    return mp.command_native({"expand-path", path})
end

local config_path = expand("~~/script-opts/webdav-libraries.json")
local python = expand("~~/../python.exe")
local list_script = expand("~~/script-modules/webdav_list.py")
local dialog_script = expand("~~/script-modules/webdav_dialog.ps1")
local libraries_directory = "webdav-libraries://"
local adding_library = false

local function read_libraries()
    local file = io.open(config_path, "rb")
    if not file then return {} end

    local entries = utils.parse_json(file:read("*a"))
    file:close()
    if type(entries) ~= "table" then
        msg.error("无法读取 WebDAV 库配置")
        return {}
    end

    local libraries = {}
    for _, entry in ipairs(entries) do
        if type(entry) == "table" and type(entry.name) == "string"
            and type(entry.url) == "string" and entry.url:match("^https?://.+/$") then
            libraries[#libraries + 1] = entry
        end
    end
    return libraries
end

local function find_library(url)
    if not url or not url:match("^https?://") then return end
    local match
    for _, library in ipairs(read_libraries()) do
        if url:sub(1, #library.url) == library.url and (not match or #library.url > #match.url) then
            match = library
        end
    end
    return match
end

local function request_directory(directory, playback_only, callback)
    return mp.command_native_async({
        name = "subprocess",
        args = {python, "-I", "-B", list_script, config_path, directory},
        playback_only = playback_only,
        capture_stdout = true,
        capture_stderr = true,
    }, function(success, result)
        local reply
        if success and result.status == 0 then
            reply = utils.parse_json(result.stdout)
        elseif not (result and result.killed_by_us) then
            msg.error("WebDAV 目录查询进程失败", result and (result.stderr or result.error_string) or "")
        end
        callback(reply and reply.entries, reply and reply.error or "WebDAV 目录查询失败")
    end)
end

local function decode_url_component(value)
    return (value:gsub("%%(%x%x)", function(byte) return string.char(tonumber(byte, 16)) end))
end

local subtitle_flags = { default = true, forced = true, sdh = true, hi = true, cc = true }

local function subtitle_language(stem)
    while true do
        local base, tag = stem:match("^(.-)%s*%[([^%[%]]+)%]$")
        if not tag then base, tag = stem:match("^(.-)%s*%(([^()]+)%)$") end
        if not tag then base, tag = stem:match("^(.*)%.([^.]+)$") end
        if not tag then return end
        if not subtitle_flags[tag] then
            if tag:match("^%a%a%a?$") or tag:match("^%a%a%a?%-%a[%a%d%-]*$") then
                return base, tag
            end
            return
        end
        stem = base
    end
end

local function matching_subtitles(entries, movie_name, mode)
    local movie = movie_name:gsub("%.[^.]+$", ""):lower()
    if movie == "" then return {} end

    local extensions, candidates, indexes = {}, {}, {}
    for _, ext in ipairs(mp.get_property_native("options/sub-auto-exts", {})) do
        extensions[ext:lower()] = true
    end
    local languages = mp.get_property_native("options/slang", {})
    for _, item in ipairs(entries) do
        local ext = fb.get_extension(item.name, "")
        if item.type == "file" and extensions[ext] then
            local stem = item.name:gsub("%.[^.]+$", ""):lower()
            local base, lang = subtitle_language(stem)
            local exact = stem == movie or base == movie
            if exact or mode == "all" or (mode == "fuzzy" and stem:find(movie, 1, true)) then
                local priority = #languages + 1
                for index, preferred in ipairs(languages) do
                    preferred = preferred:lower()
                    if lang and (lang == preferred or lang:sub(1, #preferred + 1) == preferred .. "-") then
                        priority = index
                        break
                    end
                end
                candidates[#candidates + 1] = {
                    path = item.path, stem = stem, extension = ext, priority = priority, exact = exact,
                }
                if ext == "idx" then indexes[stem] = true end
            end
        end
    end
    table.sort(candidates, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        if a.exact ~= b.exact then return a.exact end
        return a.path < b.path
    end)

    local paths = {}
    for _, subtitle in ipairs(candidates) do
        if subtitle.extension ~= "sub" or not indexes[subtitle.stem] then
            paths[#paths + 1] = subtitle.path
        end
    end
    return paths
end

local function set_playback_authentication(library)
    if type(library.authorization) ~= "string" or not library.authorization:match("^Basic [%w+/=]+$") then
        return
    end

    local headers = {}
    for _, header in ipairs(mp.get_property_native("file-local-options/http-header-fields", {})) do
        if not header:lower():match("^authorization%s*:") then
            headers[#headers + 1] = header
        end
    end
    headers[#headers + 1] = "Authorization: " .. library.authorization
    mp.set_property_native("file-local-options/http-header-fields", headers)
end

local function prepare_playback(hook)
    local url = mp.get_property("path")
    local library = find_library(url)
    if not library then return end

    mp.set_property_bool("file-local-options/ytdl", false)
    set_playback_authentication(library)

    local mode = mp.get_property("options/sub-auto", "no")
    if mode == "no" or not mp.get_property_native("options/autoload-files", true) then return end

    local directory, filename = utils.split_path((url:gsub("[?#].*$", "")))
    if filename == "" or not find_library(directory) then return end

    hook:defer()
    request_directory(directory, true, function(entries, err)
        if entries then
            local paths = mp.get_property_native("file-local-options/sub-files", {})
            local seen = {}
            for _, path in ipairs(paths) do seen[path] = true end
            local previous_count = #paths
            for _, path in ipairs(matching_subtitles(entries, decode_url_component(filename), mode)) do
                if not seen[path] then paths[#paths + 1] = path end
            end
            if #paths > previous_count then mp.set_property_native("file-local-options/sub-files", paths) end
        else
            msg.verbose("WebDAV 自动查找字幕失败", err)
        end
        hook:cont()
    end)
end

local function add_library()
    if adding_library then return end
    adding_library = true
    local program_files = os.getenv("ProgramFiles") or "C:/Program Files"
    local pwsh = utils.join_path(program_files, "PowerShell/7/pwsh.exe")
    if not utils.file_info(pwsh) then pwsh = "pwsh.exe" end
    mp.command_native_async({
        name = "subprocess",
        args = {pwsh, "-NoLogo", "-NoProfile", "-NonInteractive", "-Sta", "-File", dialog_script, config_path},
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
    }, function(success, result)
        adding_library = false
        if not success or result.status ~= 0 then
            msg.error("添加 WebDAV 库的窗口启动失败", result and result.stderr or "")
            mp.osd_message("无法打开 WebDAV 配置窗口，请检查本机 PowerShell 7。")
            return
        end

        local url = utils.parse_json(result.stdout)
        if type(url) == "string" then
            fb.browse_directory(url)
        end
    end)
end

local function playlist_title(entry)
    if entry.title and entry.title ~= "" then return entry.title end
    local path = entry.filename
    local _, name = utils.split_path(path)
    if name == "" then return path end
    if path:match("^https?://") then
        name = decode_url_component(name)
    end
    return name
end

local function play_entry(id)
    for index, entry in ipairs(mp.get_property_native("playlist", {})) do
        if entry.id == id then
            mp.commandv("playlist-play-index", index - 1)
            return
        end
    end
    mp.osd_message("该条目已从播放列表移除")
end

local function show_playlist()
    if adding_library then return end
    fb.close()
    mp.commandv("script-message-to", "playlistmanager", "playlistmanager", "close")

    local items, actions = {}, {}
    local function add_item(title, action)
        items[#items + 1] = title
        actions[#actions + 1] = action
    end

    add_item("＋ 添加 WebDAV 库…", add_library)
    add_item("＋ 导入本地播放列表…", function()
        mp.commandv("script-message-to", "dialog", "open", "append-playlist")
    end)
    local playlist = mp.get_property_native("playlist", {})
    if #playlist > 0 then
        add_item("保存当前播放列表…", function()
            mp.commandv("script-message-to", "dialog", "save", "playlist")
        end)
    end
    for _, library in ipairs(read_libraries()) do
        add_item("WebDAV · " .. library.name, function() fb.browse_directory(library.url) end)
    end
    for index, entry in ipairs(playlist) do
        local prefix = entry.current and "▶ " or ""
        add_item(("%s%d. %s"):format(prefix, index, playlist_title(entry)), function() play_entry(entry.id) end)
    end

    input.select({
        prompt = ("播放列表 [%d]"):format(#playlist),
        items = items,
        submit = function(index) actions[index]() end,
    })
end

local webdav = {
    name = "webdav",
    version = "1.4.0",
    priority = 20,
}

function webdav:setup()
    self:register_root_item({ name = libraries_directory, path = libraries_directory, label = "WebDAV" })
    mp.add_hook("on_load", 5, prepare_playback)
    mp.register_script_message("playlist-library", show_playlist)
end

function webdav:can_parse(directory)
    return directory == libraries_directory or find_library(directory) ~= nil
end

function webdav:parse(directory, parse_state)
    if directory == libraries_directory then
        local list = {}
        for _, library in ipairs(read_libraries()) do
            list[#list + 1] = {name = library.name .. "/", path = library.url, type = "dir"}
        end
        return list, {
            directory_label = "WebDAV/",
            empty_text = "点击播放列表按钮添加 WebDAV 库",
        }
    end

    request_directory(directory, false, fb.coroutine.callback())
    local entries, err = parse_state:yield()
    if entries then return entries end
    if parse_state.source == "browser" then mp.osd_message(err, 4) end
    return {}, { empty_text = err }
end

webdav.keybinds = {
    {
        key = "ENTER",
        name = "open_webdav_directory",
        command = function(_, state)
            local item = state.list[state.selected]
            if not item or item.type ~= "dir" then return false end
            if item.path ~= libraries_directory and not find_library(item.path) then return false end
            fb.browse_directory(item.path)
        end,
    },
    {
        key = "LEFT",
        name = "back_to_webdav_libraries",
        command = function(_, state)
            local library = find_library(state.directory)
            if not library or state.directory ~= library.url then return false end
            fb.browse_directory(libraries_directory)
        end,
    },
    {
        key = "Shift+ENTER",
        name = "append_webdav_file",
        command = function(_, state)
            if not find_library(state.directory) then
                mp.commandv("script-binding", "playlistmanager/showplaylist")
                return
            end
            local item = state.list[state.selected]
            if not item or item.type ~= "file" then return end
            if fb.get_sub_extensions()[fb.get_extension(item.name, "")] then return end
            if mp.commandv("loadfile", item.path, "append-play") then
                mp.osd_message("已加入播放列表 · " .. item.name)
            end
        end,
    },
}

return webdav
