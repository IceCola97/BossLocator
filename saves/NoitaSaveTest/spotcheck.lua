-- Print the entity tree of a save, or of a single entity file.
--
--   NoitaSaveTest.exe <save directory> spotcheck.lua       -- first SPOT_LIMIT files
--   NoitaSaveTest.exe <entities_9999.bin> spotcheck.lua    -- that file only
--
-- The save directory is the save<N> folder itself: the scanner looks inside its
-- world/ sub directory.  SPOT_LIMIT (Lua global, default 3) caps how many files
-- are shown.  No environment variables and no shell commands are used: the
-- listing comes from the host through NOITA_LIST_FILES.
local scriptDir = (debug.getinfo(1,"S").source:sub(2):match("^(.*[\\/])") or "")
local support = dofile(scriptDir .. "support.lua")
local parser, scanner, fastlz = support.parser, support.scanner, support.fastlz
local saveDir = support.saveDir

local targets = {}
if support.isFile(saveDir) then
  targets[1] = saveDir
else
  local limit = tonumber(SPOT_LIMIT) or 3
  local files = scanner.list(saveDir)
  for i = 1, math.min(#files, limit) do targets[i] = files[i] end
  if #files > limit then
    print(string.format('spotcheck: showing the first %d of %d entity files', limit, #files))
  end
end

for _, path in ipairs(targets) do
  local handle = assert(io.open(path, 'rb'))
  local data = handle:read('*a'); handle:close()
  local res = parser.parse(data, fastlz)
  local flat = parser.flatten(res.entities)
  print(string.format('\n===== %s decompressed=%d declaredRoots=%d entities=%d (nested=%d) structureValid=%s',
    path:match('[^/\\]+$'), res.compression.decompressedSize, res.header.rootEntityCount,
    res.entityCount, #flat - #res.entities, tostring(res.structureValid)))
  local function walk(records, depth)
    for _, r in ipairs(records) do
      print(string.format('%s- [%6d] cc=%-3d kids=%-3s scale=(%g,%g) rot=%.4f pos=(%.2f,%.2f) tags=%q %s',
        string.rep('   ', depth), r.offset, r.componentCount, tostring(r.childCount),
        r.scaleX, r.scaleY, r.rotation, r.x, r.y, r.tags, r.path))
      walk(r.children or {}, depth + 1)
    end
  end
  if #flat <= 40 then
    walk(res.entities, 0)
  else
    for i = 1, math.min(#flat, 15) do
      local r = flat[i]
      print(string.format('  - [%6d] cc=%-3d scale=(%g,%g) rot=%.4f pos=(%.2f,%.2f) tags=%q %s',
        r.offset, r.componentCount, r.scaleX, r.scaleY, r.rotation, r.x, r.y, r.tags, r.path))
    end
    print(string.format('  ... %d more', #flat - 15))
  end
end
