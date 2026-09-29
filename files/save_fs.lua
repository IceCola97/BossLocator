-- Filesystem helpers used by the save scanner.
--
-- Noita only exposes the full Lua standard library to a mod that asks for it
-- in mod.xml (request_no_api_restrictions="1"); io.* and os.* are then
-- available exactly as in vanilla Lua 5.1, and because the game runs on LuaJIT
-- its ffi library is available as well.  Everything in this file goes through
-- those APIs.  No path is ever hard coded: the save location is derived from
-- the running game's working directory (a relative path resolves there) and
-- from the directories the operating system reports through os.getenv().
--
-- Directory listing backends, tried in order:
--
--   1. LuaJIT ffi     FindFirstFileA() on Windows.  Only Windows uses the ffi
--                     backend: the POSIX backend would have to depend on the
--                     platform specific layout of struct dirent, while a shell
--                     is guaranteed to be present on Linux and macOS.
--   2. io.popen       "dir /b" on Windows, "ls -1p" elsewhere.
--
-- Every backend is probed before it is used, so a Lua state without any of
-- them degrades into "no listing" instead of failing: the caller can then fall
-- back to probing known file names with io.open().
--
-- Paths are passed to the operating system exactly as the game's own Lua does
-- (the ANSI code page on Windows), so a path that io.open() can read is also a
-- path that can be listed.

BossLocatorSaveFs = BossLocatorSaveFs or {}

local ffi_ok, ffi = pcall(require, "ffi")
if not ffi_ok or type(ffi) ~= "table" or ffi.os == nil then
    ffi = nil
end

local MAX_ENTRIES = 200000

-- ------------------------------------------------------------------ platform

local platform = nil

local function detect_platform()
    if ffi ~= nil then
        local name = tostring(ffi.os or "")
        if name == "Windows" then
            return "windows"
        end
        if name == "OSX" then
            return "osx"
        end
        if name == "Linux" then
            return "linux"
        end
        if name == "" then
            return "posix"
        end
        return string.lower(name)
    end

    if type(package) == "table" and type(package.config) == "string" and
        package.config:sub(1, 1) == "\\" then
        return "windows"
    end
    if type(os) == "table" and type(os.getenv) == "function" then
        if os.getenv("WINDIR") ~= nil or os.getenv("SystemRoot") ~= nil then
            return "windows"
        end
    end
    return "posix"
end

function BossLocatorSaveFs.platform()
    if platform == nil then
        platform = detect_platform()
    end
    return platform
end

function BossLocatorSaveFs.separator()
    if BossLocatorSaveFs.platform() == "windows" then
        return "\\"
    end
    return "/"
end

--- Joins a directory and a name.  An empty directory keeps the path relative,
--- which makes the running game's working directory addressable without ever
--- naming it.
function BossLocatorSaveFs.join(directory, name)
    if directory == nil or directory == "" then
        return tostring(name)
    end
    local separator = BossLocatorSaveFs.separator()
    local trimmed = directory:gsub("[/\\]+$", "")
    if trimmed == "" then
        -- the path was only separators (a drive root or "/")
        return directory .. tostring(name)
    end
    return trimmed .. separator .. tostring(name)
end

function BossLocatorSaveFs.available()
    if type(io) ~= "table" then
        return false, "io library is not available"
    end
    if type(io.open) ~= "function" then
        return false, "io.open is not available"
    end
    return true, nil
end

function BossLocatorSaveFs.exists(path)
    local ok, data = BossLocatorSaveFs.available()
    if not ok then
        return false
    end
    local handle = io.open(path, "rb")
    if handle == nil then
        return false
    end
    handle:close()
    return true
end

function BossLocatorSaveFs.read(path)
    local ok, reason = BossLocatorSaveFs.available()
    if not ok then
        return nil, reason
    end
    local handle, message = io.open(path, "rb")
    if handle == nil then
        return nil, message or ("cannot open " .. tostring(path))
    end
    local data = handle:read("*a")
    handle:close()
    if data == nil then
        return nil, "cannot read " .. tostring(path)
    end
    return data
end

-- ---------------------------------------------------------------- popen shell

local function popen_lines(command)
    if type(io) ~= "table" or type(io.popen) ~= "function" then
        return nil, "io.popen is not available"
    end
    local ok, handle = pcall(io.popen, command, "r")
    if not ok or handle == nil then
        return nil, "io.popen failed"
    end

    local lines = {}
    local count = 0
    for line in handle:lines() do
        count = count + 1
        if count > MAX_ENTRIES then
            break
        end
        if line ~= "" then
            lines[#lines + 1] = line
        end
    end
    handle:close()
    return lines, nil
end

local function quote_posix(value)
    -- single quotes protect every character except a single quote itself
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function quote_windows(value)
    local text = tostring(value)
    if text:find('"', 1, true) ~= nil then
        return nil
    end
    return '"' .. text .. '"'
end

-- ------------------------------------------------------------------ ffi layer

local windows_api = nil
local windows_api_failed = false

local WINDOWS_CDEF = [[
typedef struct { uint32_t dwLowDateTime; uint32_t dwHighDateTime; } BOSS_FILETIME;
typedef struct {
    uint32_t dwFileAttributes;
    BOSS_FILETIME ftCreationTime;
    BOSS_FILETIME ftLastAccessTime;
    BOSS_FILETIME ftLastWriteTime;
    uint32_t nFileSizeHigh;
    uint32_t nFileSizeLow;
    uint32_t dwReserved0;
    uint32_t dwReserved1;
    char cFileName[260];
    char cAlternateFileName[14];
} BOSS_WIN32_FIND_DATAA;
typedef struct {
    uint32_t dwFileAttributes;
    BOSS_FILETIME ftCreationTime;
    BOSS_FILETIME ftLastAccessTime;
    BOSS_FILETIME ftLastWriteTime;
    uint32_t nFileSizeHigh;
    uint32_t nFileSizeLow;
} BOSS_WIN32_FILE_ATTRIBUTE_DATA;
void *FindFirstFileA(const char *lpFileName, BOSS_WIN32_FIND_DATAA *lpFindFileData);
int FindNextFileA(void *hFindFile, BOSS_WIN32_FIND_DATAA *lpFindFileData);
int FindClose(void *hFindFile);
int GetFileAttributesExA(const char *lpFileName, int fInfoLevelId, void *lpFileInformation);
]]

local FILE_ATTRIBUTE_DIRECTORY = 0x10
local FILETIME_EPOCH_DELTA = 11644473600 -- seconds between 1601-01-01 and 1970-01-01

local function filetime_to_seconds(filetime)
    local high = tonumber(filetime.dwHighDateTime) or 0
    local low = tonumber(filetime.dwLowDateTime) or 0
    if high == 0 and low == 0 then
        return nil
    end
    return (high * 4294967296 + low) / 10000000 - FILETIME_EPOCH_DELTA
end

local function windows_ffi()
    if windows_api ~= nil or windows_api_failed then
        return windows_api
    end
    windows_api_failed = true
    if ffi == nil then
        return nil
    end
    -- A redefinition is harmless here: the names are module private, and a
    -- state that already declared them keeps working.
    pcall(ffi.cdef, WINDOWS_CDEF)
    local ok, library = pcall(ffi.load, "kernel32")
    if not ok or library == nil then
        return nil
    end
    local probe_ok = pcall(function()
        return library.FindFirstFileA
    end)
    if not probe_ok then
        return nil
    end
    windows_api = library
    return windows_api
end

local INVALID_HANDLE = nil

local function is_invalid_handle(handle)
    if handle == nil then
        return true
    end
    if INVALID_HANDLE == nil then
        INVALID_HANDLE = ffi.cast("void *", -1)
    end
    return handle == INVALID_HANDLE
end

-- Returns { {name = ..., mtime = ...}, ... } or nil, reason.
local function windows_ffi_entries(directory, kind)
    local library = windows_ffi()
    if library == nil then
        return nil, "the ffi backend is not available"
    end

    local target = directory
    if target == nil or target == "" then
        target = "."
    end
    local pattern = target .. "\\*"

    local data = ffi.new("BOSS_WIN32_FIND_DATAA[1]")
    local handle = library.FindFirstFileA(pattern, data[0])
    if is_invalid_handle(handle) then
        -- A missing directory and an empty directory answer the same way; both
        -- are reported as "no entries".
        return {}, nil
    end

    local entries = {}
    local guard = 0
    repeat
        guard = guard + 1
        local name = ffi.string(data[0].cFileName)
        if name ~= "." and name ~= ".." then
            local attributes = tonumber(data[0].dwFileAttributes) or 0
            local is_directory = math.floor(attributes / FILE_ATTRIBUTE_DIRECTORY) % 2 == 1
            if kind == nil or (kind == "dirs") == is_directory then
                entries[#entries + 1] = {
                    name = name,
                    mtime = filetime_to_seconds(data[0].ftLastWriteTime),
                    directory = is_directory,
                }
            end
        end
    until library.FindNextFileA(handle, data[0]) == 0 or guard >= MAX_ENTRIES
    library.FindClose(handle)
    return entries, nil
end

-- ----------------------------------------------------------- popen backends

local function windows_popen_entries(directory, kind, by_time)
    local target = directory
    if target == nil or target == "" then
        target = "."
    end
    local quoted = quote_windows(target)
    if quoted == nil then
        return nil, "the path cannot be passed to the shell"
    end

    local filter = ""
    if kind == "dirs" then
        filter = "/ad "
    elseif kind == "files" then
        filter = "/a-d "
    end
    local order = by_time and "/o-d " or ""
    local command = "dir /b " .. filter .. order .. quoted .. " 2>nul"

    local lines, reason = popen_lines(command)
    if lines == nil then
        return nil, reason
    end

    local entries = {}
    for _, line in ipairs(lines) do
        entries[#entries + 1] = { name = line, mtime = nil }
    end
    return entries, nil
end

local function posix_popen_entries(directory, kind, by_time)
    local target = directory
    if target == nil or target == "" then
        target = "."
    end
    -- -p marks directories with a trailing slash, -t sorts by modification
    -- time (newest first).
    local flags = "-1p"
    if by_time then
        flags = flags .. "t"
    end
    local command = "ls " .. flags .. " " .. quote_posix(target) .. " 2>/dev/null"

    local lines, reason = popen_lines(command)
    if lines == nil then
        return nil, reason
    end

    local entries = {}
    for _, line in ipairs(lines) do
        local is_directory = line:sub(-1) == "/"
        local name = line
        if is_directory then
            name = line:sub(1, -2)
        end
        if name ~= "" and name ~= "." and name ~= ".." then
            if kind == nil or (kind == "dirs") == is_directory then
                entries[#entries + 1] = {
                    name = name,
                    mtime = nil,
                    directory = is_directory,
                }
            end
        end
    end
    return entries, nil
end

-- --------------------------------------------------------------- public API

local backend_cache = nil

--- Lists the entries of a directory.  Returns an array of
--- { name, mtime, directory } tables, or nil plus a reason.  'by_time' asks
--- the backend for a newest-first order, which is used when the platform
--- cannot report modification times directly.
function BossLocatorSaveFs.entries(directory, kind, by_time)
    local ok, reason = BossLocatorSaveFs.available()
    if not ok then
        return nil, reason
    end

    local order = {}
    if backend_cache == nil then
        if BossLocatorSaveFs.platform() == "windows" then
            order = { windows_ffi_entries, windows_popen_entries }
        else
            order = { posix_popen_entries }
        end
    else
        order = { backend_cache }
    end

    local last_reason = nil
    for _, backend in ipairs(order) do
        local entries, backend_reason = backend(directory, kind, by_time)
        if entries ~= nil then
            backend_cache = backend
            return entries, nil
        end
        last_reason = backend_reason
    end
    return nil, last_reason or "no directory listing backend is available"
end

local function backend_name()
    if backend_cache == windows_ffi_entries then
        return "ffi (FindFirstFileA)"
    end
    if backend_cache == windows_popen_entries then
        return "io.popen (dir)"
    end
    if backend_cache == posix_popen_entries then
        return "io.popen (ls)"
    end
    return "none"
end

function BossLocatorSaveFs.backend()
    return backend_name()
end

--- True when the caller can rely on directory listings.
function BossLocatorSaveFs.can_list()
    local entries = BossLocatorSaveFs.entries(".", "files")
    return entries ~= nil
end

--- Lists names only, keeping the caller free of the backend details.
function BossLocatorSaveFs.list(directory, kind)
    local entries, reason = BossLocatorSaveFs.entries(directory, kind)
    if entries == nil then
        return nil, reason
    end
    local names = {}
    for _, entry in ipairs(entries) do
        names[#names + 1] = entry.name
    end
    return names
end

function BossLocatorSaveFs.list_paths(directory, kind)
    local names, reason = BossLocatorSaveFs.list(directory, kind)
    if names == nil then
        return nil, reason
    end
    local paths = {}
    for _, name in ipairs(names) do
        paths[#paths + 1] = BossLocatorSaveFs.join(directory, name)
    end
    return paths
end

local stat_variant = nil

local function posix_mtime(path)
    local formats = { "-c %Y", "-f %m" }
    if stat_variant ~= nil then
        formats = { stat_variant }
    end
    for _, format in ipairs(formats) do
        local lines = popen_lines("stat " .. format .. " " .. quote_posix(path) .. " 2>/dev/null")
        if lines ~= nil and lines[1] ~= nil then
            local value = tonumber(lines[1])
            if value ~= nil then
                stat_variant = format
                return value
            end
        end
    end
    return nil
end

local function windows_mtime(path)
    local library = windows_ffi()
    if library == nil then
        return nil
    end
    local data = ffi.new("BOSS_WIN32_FILE_ATTRIBUTE_DATA[1]")
    if library.GetFileAttributesExA(path, 0, data) == 0 then
        return nil
    end
    return filetime_to_seconds(data[0].ftLastWriteTime)
end

--- Modification time of a path in seconds, or nil when the platform cannot
--- report it.
function BossLocatorSaveFs.mtime(path)
    if BossLocatorSaveFs.platform() == "windows" then
        return windows_mtime(path)
    end
    return posix_mtime(path)
end

--- Newest modification time among the entries of a directory that satisfy
--- 'accept' (a function taking a name and returning a boolean).  Returns nil
--- when the platform cannot report times.
function BossLocatorSaveFs.newest_time(directory, kind, accept)
    local entries, _ = BossLocatorSaveFs.entries(directory, kind)
    if entries == nil then
        return nil
    end

    local with_times = false
    for _, entry in ipairs(entries) do
        if entry.mtime ~= nil then
            with_times = true
            break
        end
    end

    if not with_times then
        -- The backend cannot report times (a shell listing).  Ask for a
        -- newest-first order instead and only ask the platform about the
        -- first accepted entry, which keeps the number of shell calls low.
        local ordered = BossLocatorSaveFs.entries(directory, kind, true)
        if ordered == nil then
            return nil
        end
        for _, entry in ipairs(ordered) do
            if accept == nil or accept(entry.name) then
                local mtime = BossLocatorSaveFs.mtime(
                    BossLocatorSaveFs.join(directory, entry.name))
                if mtime ~= nil then
                    return mtime, entry.name
                end
            end
        end
        return nil
    end

    local newest, newest_name = nil, nil
    for _, entry in ipairs(entries) do
        if accept == nil or accept(entry.name) then
            local mtime = entry.mtime
            if mtime ~= nil and (newest == nil or mtime > newest) then
                newest = mtime
                newest_name = entry.name
            end
        end
    end
    return newest, newest_name
end

-- ----------------------------------------------------------------- save roots

local ROOT_SUBDIRECTORY = "Nolla_Games_Noita"

--- Candidate save roots.  The first entry is the running game's working
--- directory: Noita keeps save<N> folders next to the executable, and a
--- relative path therefore points at the installation that is actually
--- running.  The remaining entries are the per-user data directories the
--- operating system reports, which some installations and cloud setups use
--- instead.
function BossLocatorSaveFs.roots()
    local roots = {}
    local seen = {}

    local function add(path)
        if path == nil or seen[path] then
            return
        end
        seen[path] = true
        roots[#roots + 1] = path
    end

    -- "" is the running game's working directory: paths are kept relative, so
    -- the installation that is actually running is addressed without naming it.
    add("")

    local getenv = nil
    if type(os) == "table" and type(os.getenv) == "function" then
        getenv = os.getenv
    end
    if getenv ~= nil then
        local separator = BossLocatorSaveFs.separator()
        local profile = getenv("USERPROFILE")
        if profile ~= nil and profile ~= "" then
            add(profile .. separator .. "AppData" .. separator .. "LocalLow" ..
                separator .. ROOT_SUBDIRECTORY)
        end
        local appdata = getenv("APPDATA")
        if appdata ~= nil and appdata ~= "" then
            add((appdata:gsub("[/\\]Roaming[/\\]?$", "")) .. separator .. "AppData" ..
                separator .. "LocalLow" .. separator .. ROOT_SUBDIRECTORY)
        end

        local home = getenv("HOME")
        if home ~= nil and home ~= "" then
            local slash = "/"
            add(home .. slash .. ".local" .. slash .. "share" .. slash .. ROOT_SUBDIRECTORY)
            add(home .. slash .. "Library" .. slash .. "Application Support" ..
                slash .. ROOT_SUBDIRECTORY)
        end
        local xdg = getenv("XDG_DATA_HOME")
        if xdg ~= nil and xdg ~= "" then
            add(xdg .. "/" .. ROOT_SUBDIRECTORY)
        end
    end

    return roots
end
