local obs = obslua
local ffi = require("ffi")
local search_replace_list = {}  -- populated from script_update; array of user-entered search & replace pairs

function script_description()
    return "Simple Replay Sorter (SRS) - automatically organizes replay recordings."
end

function script_load(settings)
    obs.obs_frontend_add_event_callback(on_event)
    script_update(settings)
end

function script_properties()
    local props = obs.obs_properties_create()

    obs.obs_properties_add_text(props, "search_replace_list", "Search & Replace List\n\nSee README for more information.", obs.OBS_TEXT_MULTILINE)

    return props
end

function script_update(settings)
    local raw_search_replace_list = obs.obs_data_get_string(settings, "search_replace_list")
    search_replace_list = parse_search_replace_list(raw_search_replace_list)

    log_info("updated search & replace list: %s", format_search_replace_list(search_replace_list))
end

function on_event(event)
    if event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_SAVED then
        sort_replay()
    end
end

function sort_replay()
    local full_replay_path = get_last_replay_path()
    if full_replay_path == nil or full_replay_path == "" then
        log_error("couldn't get last replay path")
        return
    end

    local dest_dir, dest_path = get_replay_destination(full_replay_path)

    local mkdir_result = obs.os_mkdirs(dest_dir)
    if mkdir_result == obs.MKDIR_ERROR then
        log_error("failed to create folder %s", dest_dir)
        return
    end

    local move_ok = obs.os_rename(full_replay_path, dest_path)
    if not move_ok then
        log_error("failed to move replay to %s", dest_path)
    end

    log_info("moved replay from %s to %s", full_replay_path, dest_path)
end

function get_last_replay_path()
    local replay_buffer = obs.obs_frontend_get_replay_buffer_output()
    if replay_buffer == nil then
        log_error("replay buffer output is nil")
        return nil
    end

    local calldata = obs.calldata_create()
    local prochandler = obs.obs_output_get_proc_handler(replay_buffer)
    obs.proc_handler_call(prochandler, "get_last_replay", calldata)
    local path = obs.calldata_string(calldata, "path")

    obs.calldata_destroy(calldata)
    obs.obs_output_release(replay_buffer)

    return path
end

--------------- C defs ---------------
ffi.cdef[[
typedef void* HWND;
typedef unsigned long DWORD;
typedef int BOOL;

HWND GetForegroundWindow(void);
DWORD GetWindowThreadProcessId(HWND hWnd, DWORD *lpdwProcessId);
void *OpenProcess(DWORD dwDesiredAccess, BOOL bInheritHandle, DWORD dwProcessId);
BOOL QueryFullProcessImageNameA(void *hProcess, DWORD dwFlags, char *lpExeName, DWORD *lpdwSize);
BOOL CloseHandle(void *hObject);
]]
--------------- C defs ---------------

local user32 = ffi.load("user32")
local kernel32 = ffi.load("kernel32")

local PROCESS_QUERY_LIMITED_INFORMATION = 0x1000 -- Minimal access right required to query process information

function get_focused_window_name()
    local fallback_name = "Unknown"

    local hwnd = user32.GetForegroundWindow()
    if hwnd == nil then
        log_error("couldn't get handle for focused window")
        return fallback_name
    end

    local pid = ffi.new("DWORD[1]")
    user32.GetWindowThreadProcessId(hwnd, pid)

    local hProcess = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid[0])
    if hProcess == nil then
        log_error("couldn't open process for focused window")
        return fallback_name
    end

    local buffer = ffi.new("char[260]")
    local size = ffi.new("DWORD[1]", 260)
    local ok = kernel32.QueryFullProcessImageNameA(hProcess, 0, buffer, size)
    kernel32.CloseHandle(hProcess)

    if ok == 0 then
        log_error("couldn't query process image name for focused window")
        return fallback_name
    end

    local full_exe_path = ffi.string(buffer, size[0])
    local exe_name = full_exe_path:match("([^/\\]+)$")

    return exe_name and exe_name:gsub("%.[eE][xX][eE]$", "") or fallback_name
end

function get_filename(path)
    return path:match("([^/\\]+)$")
end

function get_dir(path)
    return path:match("(.+)[/\\][^/\\]+$")
end

function to_title_case(str)
    str = str:gsub("[_%-]+", " ")
    str = str:lower()
    str = str:gsub("(%a)([%w']*)", function(first, rest)
        return first:upper() .. rest
    end)

    return str
end

function parse_search_replace_list(raw_list)
    local matches = {}

    for line in raw_list:gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")

        if trimmed ~= "" then
            local search_str, replace_str = trimmed:match("^(.-)%s*=%s*(.-)$")

            if search_str and replace_str ~= "" then
                -- "deadlock = DEADLOCK" form, with a replacement given
                table.insert(matches, { search = search_str, replace = replace_str })
            elseif search_str then
                -- "deadlock =" form: '=' present but nothing after it
                table.insert(matches, { search = search_str, replace = search_str })
            else
                -- no "=" found at all: the whole line is both search and replacement
                table.insert(matches, { search = trimmed, replace = trimmed })
            end
        end
    end

    return matches
end

function format_search_replace_list(list)
    local parts = {}
    for _, entry in ipairs(list) do
        table.insert(parts, "[" .. entry.search .. " -> " .. entry.replace .. "]")
    end
    
    return table.concat(parts, " ")
end

function search_replace_list_lookup(raw_name)
    local lower_name = raw_name:lower()

    for _, entry in ipairs(search_replace_list) do
        if lower_name:find(entry.search:lower(), 1, true) then
            return entry.replace
        end
    end

    return nil
end

local SYSTEM_PROCESS_NAMES_OVERRIDE = {
    ["explorer"] = "Desktop",
    ["dwm"] = "Desktop",
    ["searchhost"] = "Desktop",
    ["shellexperiencehost"] = "Desktop",
    ["lockapp"] = "Desktop"
}

function get_final_folder_name()
    local raw_name = get_focused_window_name()
    local system_override = SYSTEM_PROCESS_NAMES_OVERRIDE[raw_name:lower()]
    local user_override = search_replace_list_lookup(raw_name)

    local final = system_override or user_override or to_title_case(raw_name)

    log_debug(
        "raw window name: %s, system override: %s, user override: %s, final: %s",
        raw_name, system_override, user_override, final
    )

    return final
end

function get_replay_destination(full_replay_path)
    local replay_dir = get_dir(full_replay_path)
    local replay_filename = get_filename(full_replay_path)
    
    local dest_folder_name = get_final_folder_name()

    local dest_dir = replay_dir .. "/" .. dest_folder_name
    local dest_path = dest_dir .. "/" .. replay_filename

    log_debug(
        "replay dir: %s, replay filename: %s, dest dir: %s, dest path: %s",
        replay_dir, replay_filename, dest_dir, dest_path
    )

    return dest_dir, dest_path
end

function log_debug(fmt, ...)
    obs.script_log(obs.LOG_DEBUG, string.format(fmt, ...))
end

function log_info(fmt, ...)
    obs.script_log(obs.LOG_INFO, string.format(fmt, ...))
end

function log_error(fmt, ...)
    obs.script_log(obs.LOG_ERROR, string.format(fmt, ...))
end