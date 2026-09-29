-- Scan one Noita save directory for entity files and hand every match to a
-- callback.
--
-- The caller supplies the save<N> directory; the scanner looks inside its
-- world/ folder directly:
--
--   local scanner = require("save_scanner")
--   scanner.enumerate = hostListFiles          -- install once, host side
--   scanner.scan("C:/Noita/save00", function(path, saveId, index)
--     -- path   : C:/Noita/save00/world/entities_12.bin
--     -- saveId : "save00"  (the caller supplied directory)
--     -- index  : 1-based position in the scan order
--     return true                              -- return false to stop the scan
--   end)
--
-- The default matcher is the Lua pattern form of /\/world\/entities_\-?\d+\.bin$/,
-- i.e. '[/\\]world[/\\]entities_%-?%d+%.bin$': a file that sits directly in a
-- world/ directory.  Both separators are accepted and the pattern is tried with
-- a leading separator added, so absolute and relative paths behave the same.
--
-- Platform independence: this module contains no os.execute, no os.getenv and
-- no io.popen, and it never runs a shell command.  Lua 5.1 has no directory
-- API, so directory enumeration is *injected* by the host instead:
--
--   enumerate(directory) -> array of paths, or an iterator function
--
-- The scanner passes the <saveDir>/world directory to that enumerator.  A host
-- that lists files itself can pass { files = { ... } } instead, and a host that
-- wants the bytes handed over can pass { read = true } (see M.scan).  Because
-- both the enumerator and the reader are injectable, the module can be
-- exercised entirely in memory - see tests/save_scanner_test.lua.
local M = {}

-- ---------------------------------------------------------------- matching

-- Name of the sub directory that holds the entity chunks of one save.
M.worldDir = 'world'
-- A file that sits directly inside a world/ directory.
M.pattern = '[/\\]world[/\\]entities_%-?%d+%.bin$'
-- <…>/save00/world/… - used to report which save a path belongs to.
M.idPattern = '[/\\](save%d+)[/\\]world[/\\]'

--- True when the path is one of the entities_*.bin files we care about.
function M.matches(path)
  if type(path) ~= 'string' or path == '' then return false end
  return ('/' .. path):match(M.pattern) ~= nil
end

--- Returns the "save00" style directory name of an entity file path, or nil
--- when the parent directory is not named save<N> (or the path is not an
--- entity file at all).
function M.saveId(path)
  if not M.matches(path) then return nil end
  return ('/' .. path .. '/'):match(M.idPattern)
end

--- Returns the save<N> name of a save directory path, or nil for other names.
function M.saveName(saveDir)
  if type(saveDir) ~= 'string' then return nil end
  return saveDir:gsub('[/\\]+$', ''):match('[/\\]?(save%d+)$')
end

-- ------------------------------------------------------------------- files

--- Default reader: plain core Lua file I/O.  No shell, no environment lookup.
function M.readFile(path)
  local handle, message = io.open(path, 'rb')
  if not handle then return nil, message or ('cannot open ' .. tostring(path)) end
  local data = handle:read('*a')
  handle:close()
  if data == nil then return nil, 'cannot read ' .. tostring(path) end
  return data
end

-- ------------------------------------------------------------- enumerating

local function stripTrailingSeparators(dir)
  local stripped = dir:gsub('[/\\]+$', '')
  if stripped == '' then return dir end
  return stripped
end

-- Keeps the separator style of the caller and appends one path element.
local function joinPath(directory, name)
  local trimmed = stripTrailingSeparators(directory)
  if trimmed == '' then return name end
  local separator = trimmed:find('\\', 1, true) and '\\' or '/'
  return trimmed .. separator .. name
end

--- Directory handed to the host enumerator for a given save directory.
function M.worldPath(saveDir)
  if type(saveDir) ~= 'string' or saveDir == '' then
    error('save_scanner: save directory is required', 2)
  end
  return joinPath(saveDir, M.worldDir)
end

-- Accepts either an array of paths or an iterator function and always returns
-- an iterator function.
local function asIterator(source)
  if type(source) == 'function' then return source end
  if type(source) == 'table' then
    local i = 0
    return function() i = i + 1; return source[i] end
  end
  error('save_scanner: the enumerator must return a list of paths or an iterator', 3)
end

-- ------------------------------------------------------------------- public

--- Collects every matching entity file below <saveDir>/world (sorted).
-- opts.enumerate : enumerator function (falls back to M.enumerate)
-- opts.files     : already listed paths, skips enumeration entirely
-- opts.sort      : false keeps the enumerator order
-- opts.allowEmpty: true tolerates a save that lists no entity files at all
-- Returns the matched paths plus the number of entries that were inspected.
function M.list(saveDir, opts)
  opts = opts or {}
  local matched = {}
  local visited = 0

  local source = opts.files
  if source == nil then
    local worldDir = M.worldPath(saveDir)
    local enumerate = opts.enumerate or M.enumerate
    if type(enumerate) ~= 'function' then
      error('save_scanner.list: no enumerator available; install one with ' ..
        'save_scanner.enumerate = function(directory) ... end or pass opts.enumerate ' ..
        '(Lua 5.1 has no directory API and this module never shells out)', 2)
    end
    source = asIterator(enumerate(worldDir))
  else
    source = asIterator(source)
  end

  for entry in source do
    if type(entry) == 'string' and entry ~= '' then
      visited = visited + 1
      if M.matches(entry) then matched[#matched + 1] = entry end
    end
  end

  if opts.sort ~= false then table.sort(matched) end
  if visited == 0 and not opts.allowEmpty then
    error('save_scanner: nothing listed below ' .. M.worldPath(saveDir) ..
      ' (missing world directory, or the enumerator returned no entries?)', 2)
  end
  return matched, visited
end

--- Iterator over the same paths as M.list.
function M.each(saveDir, opts)
  local list = M.list(saveDir, opts)
  local i = 0
  return function()
    i = i + 1
    return list[i]
  end
end

--- Calls callback(path, saveId, index[, data]) for every matching entity file.
-- saveId is normally the save<N> name of the supplied directory; for a directory
-- with another name it falls back to the save<N> found in the file path (nil if
-- there is none).
-- opts.read     : true (or a reader function) hands the file bytes to the
--                 callback as a 4th argument; unreadable files are reported
--                 through opts.onError and counted in the summary instead
-- opts.onError  : function(path, message) called for read failures
-- other options : forwarded to M.list
-- Returns the number of files handed to the callback, the number of inspected
-- entries, and a summary table
--   { saveDir, saveId, matched, visited, read, failed, stopped, errors = { {path, message} } }.
function M.scan(saveDir, callback, opts)
  if type(callback) ~= 'function' then
    error('save_scanner.scan: callback must be a function', 2)
  end
  opts = opts or {}
  local matched, visited = M.list(saveDir, opts)

  local read
  if opts.read then
    read = type(opts.read) == 'function' and opts.read or M.readFile
  end

  local directoryName = M.saveName(saveDir)
  local summary = {
    saveDir = saveDir,
    saveId = directoryName,
    matched = #matched,
    visited = visited,
    read = 0,
    failed = 0,
    stopped = false,
    errors = {},
  }

  local handled = 0
  for index = 1, #matched do
    local path = matched[index]
    local data
    if read then
      local message
      data, message = read(path)
      if data == nil then
        summary.failed = summary.failed + 1
        summary.errors[#summary.errors + 1] = { path = path, message = tostring(message or 'read failed') }
        if opts.onError then opts.onError(path, message) end
      else
        summary.read = summary.read + 1
      end
    end
    if data ~= nil or not read then
      handled = handled + 1
      if callback(path, directoryName or M.saveId(path), index, data) == false then
        summary.stopped = true
        return handled, visited, summary
      end
    end
  end
  return handled, visited, summary
end

return M
