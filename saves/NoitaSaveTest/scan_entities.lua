-- Test front-end: scan <saveDir>/world/entities_*.bin with
-- saves/save_scanner.lua, parse each one with saves/entity_parser.lua and dump
-- the entity base data as JSON next to the input file.
--
--   NoitaSaveTest.exe <save directory> scan_entities.lua
--
-- The host performs the directory listing (NOITA_LIST_FILES) and the scanner
-- reads the files, so this script only describes what to do per file.
local scriptDir = (debug.getinfo(1,"S").source:sub(2):match("^(.*[\\/])") or "")
local support = dofile(scriptDir .. "support.lua")
local parser, scanner, fastlz = support.parser, support.scanner, support.fastlz
local saveDir = support.saveDir

local function json_escape(s) return (tostring(s):gsub('[%z\1-\31\\"]', function(c) local n=c:byte(); if c=='\\' then return '\\\\' elseif c=='"' then return '\\"' elseif n==8 then return '\\b' elseif n==12 then return '\\f' elseif n==10 then return '\\n' elseif n==13 then return '\\r' elseif n==9 then return '\\t' else return string.format('\\u%04X',n) end end)) end
local function json(v, seen)
  local t=type(v); if t=='nil' then return 'null' elseif t=='boolean' then return v and 'true' or 'false' elseif t=='number' then if v~=v or v==math.huge or v==-math.huge then return 'null' end; return string.format('%.9g',v) elseif t=='string' then return '"'..json_escape(v)..'"' elseif t=='table' then seen=seen or {}; if seen[v] then return 'null' end; seen[v]=true; local arr=true; local n=0; for k in pairs(v) do if type(k)~='number' then arr=false break end; n=math.max(n,k) end; local a={}; if arr then for i=1,n do a[#a+1]=json(v[i],seen) end; seen[v]=nil; return '['..table.concat(a,',')..']' else for k,x in pairs(v) do a[#a+1]=json(tostring(k))..':'..json(x,seen) end; table.sort(a); seen[v]=nil; return '{'..table.concat(a,',')..'}' end end; return 'null' end

print(string.format("[Lua] scanning %s", scanner.worldPath(saveDir)))
local pass, fail, unvalidated, entities = 0, 0, 0, 0
local handled, visited, summary = scanner.scan(saveDir, function(path, saveId, index, data)
  local ok, res = pcall(parser.parse, data, fastlz)
  local out = path:gsub('%.bin$', '.json')
  local w, message = io.open(out, 'wb')
  local label = string.format('%s/%s', tostring(saveId), path:match('[^/\\]+$'))
  if not w then
    fail = fail + 1
    print(string.format('[Lua] [%d] %-28s FAIL: %s', index, label, tostring(message)))
    return true
  end
  if ok then
    w:write(json(res)); pass = pass + 1; entities = entities + res.entityCount
    if res.structureValid then
      print(string.format('[Lua] [%d] %-28s roots=%d entities=%d decompressed=%d bytes',
        index, label, res.header.rootEntityCount, res.entityCount, res.compression.decompressedSize))
    else
      unvalidated = unvalidated + 1
      print(string.format('[Lua] [%d] %-28s WARNING %s', index, label, res.warnings[1] or 'structure not validated'))
    end
  else
    w:write(json({error=tostring(res), source=path})); fail = fail + 1
    print(string.format('[Lua] [%d] %-28s FAIL: %s', index, label, tostring(res)))
  end
  w:close()
  return true
end, { read = true })

for _, failure in ipairs(summary.errors) do
  fail = fail + 1
  print(string.format('[Lua] unreadable: %s (%s)', failure.path, failure.message))
end
print(string.format('[Lua] SUMMARY files=%d pass=%d fail=%d unvalidated=%d entities=%d (dir entries=%d, read=%d)',
  handled, pass, fail, unvalidated, entities, visited, summary.read))
if fail > 0 then error('one or more entity files failed') end
