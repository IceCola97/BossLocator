-- Shared bootstrap for the NoitaSaveTest scripts.
--
-- Locates the shared modules (saves/entity_parser.lua, saves/save_scanner.lua)
-- and the fastlz module in both supported layouts:
--
--   * running the scripts straight from the source directory
--     (…/saves/NoitaSaveTest/, modules one level up in …/saves/)
--   * running the copies that the build drops next to NoitaSaveTest.exe
--     (the csproj copies the modules and fastlz.lua into the output directory)
--
--   local support = dofile(scriptDir .. "support.lua")
--   support.parser, support.scanner, support.fastlz, support.saveDir, support.list
--
-- Everything the host can provide comes from Lua globals set by Program.cs
-- (NOITA_SAVE_DIR_ARG, NOITA_SAVES_DIR, NOITA_FASTLZ_SCRIPT_ARG and the
-- NOITA_LIST_FILES enumerator) - this file contains no os.getenv and no shell
-- calls, so the scripts behave the same on every platform.
local M = {}

local scriptDir = (debug.getinfo(1, "S").source:sub(2):match("^(.*[\\/])") or "./"):gsub("\\", "/")

local function existing(path)
  if type(path) ~= 'string' or path == '' then return nil end
  local handle = io.open(path, 'rb')
  if not handle then return nil end
  handle:close()
  return path
end

local function firstExisting(candidates)
  for _, candidate in ipairs(candidates) do
    local found = existing(candidate)
    if found then return found end
  end
end

-- ------------------------------------------------------------ module paths

local savesDir
if type(NOITA_SAVES_DIR) == 'string' and NOITA_SAVES_DIR ~= '' then
  local candidate = NOITA_SAVES_DIR:gsub("\\", "/")
  if existing(candidate .. "/save_scanner.lua") then savesDir = candidate end
end
if not savesDir and existing(scriptDir .. "../save_scanner.lua") then
  savesDir = scriptDir .. ".."
end
if not savesDir and existing(scriptDir .. "save_scanner.lua") then
  savesDir = scriptDir
end
if not savesDir then
  error("support.lua: saves/save_scanner.lua not found; expected it next to the " ..
    "scripts or one directory up (set NOITA_SAVES_DIR to override)")
end

package.path = package.path .. ";" .. savesDir .. "/?.lua;" .. scriptDir .. "?.lua"

M.scriptDir = scriptDir
M.savesDir = savesDir
M.parser = require("entity_parser")
M.scanner = require("save_scanner")

-- ------------------------------------------------------------------ fastlz

local hostFastlz
if type(NOITA_FASTLZ_SCRIPT_ARG) == 'string' and NOITA_FASTLZ_SCRIPT_ARG ~= '' then
  hostFastlz = NOITA_FASTLZ_SCRIPT_ARG:gsub("\\", "/")
end

local fastlzPath = firstExisting({
  hostFastlz,
  scriptDir .. "fastlz.lua",
  savesDir .. "/fastlz.lua",
  savesDir .. "/../fastlz/fastlz.lua",
})
if not fastlzPath then
  error("support.lua: fastlz.lua not found; expected it next to the scripts, in " ..
    savesDir .. " or in fastlz/ (set NOITA_FASTLZ_SCRIPT_ARG to override)")
end
M.fastlzPath = fastlzPath
M.fastlz = assert(dofile(fastlzPath))

-- ----------------------------------------------------------- host services

-- Save directory handed over by the host: the save<N> folder itself (the
-- scanner looks inside its world/ sub directory), or a single entities_*.bin.
M.saveDir = (type(NOITA_SAVE_DIR_ARG) == 'string' and NOITA_SAVE_DIR_ARG ~= '' and NOITA_SAVE_DIR_ARG) or "."

-- Program.cs exposes a recursive file listing as NOITA_LIST_FILES.  Installing
-- it on the scanner keeps the requested call shape - scanner.scan(root, callback)
-- with nothing but a root and a callback - while the module itself stays free of
-- platform specific code.
if type(NOITA_LIST_FILES) == 'function' then
  M.list = NOITA_LIST_FILES
  M.scanner.enumerate = NOITA_LIST_FILES
else
  M.list = nil
end

--- True when the path can be opened as a file (used by the single-file tools).
function M.isFile(path)
  return existing(path) ~= nil
end

return M
