-- Validation harness: run entity_parser over every entity file that
-- save_scanner finds in <saveDir>/world and check each result against the
-- declared root count and the record layout.  Prints a summary only.
--
--   NoitaSaveTest.exe <save directory> validate.lua
local scriptDir = (debug.getinfo(1,"S").source:sub(2):match("^(.*[\\/])") or "")
local support = dofile(scriptDir .. "support.lua")
local parser, scanner, fastlz = support.parser, support.scanner, support.fastlz
local saveDir = support.saveDir

local files = scanner.list(saveDir)
print(string.format('validate: %d entity files in %s', #files, scanner.worldPath(saveDir)))

local problems, checked, totalEntities, nested = 0, 0, 0, 0
local function check(cond, fmt, ...)
  if not cond then problems = problems + 1; print('  PROBLEM: ' .. string.format(fmt, ...)) end
  return cond
end

for _, path in ipairs(files) do
  local name = path:match('[^/\\]+$')
  local handle = assert(io.open(path, 'rb'))
  local data = handle:read('*a'); handle:close()

  local res = parser.parse(data, fastlz)
  checked = checked + 1
  local flat = parser.flatten(res.entities)
  totalEntities = totalEntities + #flat
  nested = nested + (#flat - #res.entities)

  local bad = false
  if not check(res.structureValid, '%s: structure not validated (%s)', name, res.warnings[1] or '') then bad = true end
  if not check(#res.entities == res.header.rootEntityCount, '%s: %d root entities parsed, %d declared',
      name, #res.entities, res.header.rootEntityCount) then bad = true end
  if not check(res.entityCount == #flat, '%s: entityCount=%d but %d records walked', name, res.entityCount, #flat) then bad = true end
  if not check(res.recordCount == #flat, '%s: recordCount=%d but %d records walked', name, res.recordCount, #flat) then bad = true end

  for _, e in ipairs(flat) do
    if not check(e.path:match('%.xml$'), '%s: entity at %d has path %q', name, e.offset, e.path) then bad = true end
    if not check(e.tags:match('^[%w_,%.%- ]*$'), '%s: entity at %d has tags %q', name, e.offset, e.tags) then bad = true end
    if not check(math.abs(e.scaleX) > 0 and math.abs(e.scaleY) > 0, '%s: entity at %d scale=(%s,%s)',
        name, e.offset, tostring(e.scaleX), tostring(e.scaleY)) then bad = true end
    if not check(e.componentCount >= 1, '%s: entity at %d componentCount=%d', name, e.offset, e.componentCount) then bad = true end
    if not check(type(e.children) == 'table', '%s: entity at %d has no children list', name, e.offset) then bad = true end
  end

  local previous = 0
  for _, e in ipairs(flat) do
    if not check(e.offset > previous, '%s: record offsets not strictly increasing near %d', name, e.offset) then bad = true end
    previous = e.offset
  end

  if not bad then
    print(string.format('OK   %-20s roots=%-3d records=%-3d (+%d nested)',
      name, #res.entities, #flat, #flat - #res.entities))
  end
end

print(string.format('\nchecked=%d problems=%d totalEntities=%d nested=%d', checked, problems, totalEntities, nested))
if problems > 0 then error('validation problems found') end
