-- Reusable parser for Noita "entities_*.bin" files.
--
-- Scope: entity base data only (name, file path, tags, position, scale,
-- rotation, component count, parent/child layout).  Component payloads are
-- *never* decoded - the parser only needs to know where the next entity
-- record starts, so every component body is skipped wholesale.
--
-- Layout (all scalars big endian, strings are u32 length + raw bytes):
--
--   file    : u32 flags | string schemaHash | u32 rootEntityCount | record...
--   record  : string name | u8 version | string path | string tags
--             | f32 x | f32 y | f32 scaleX | f32 scaleY | f32 rotation
--             | u32 componentCount | <component payloads, skipped>
--             | u32 childCount | <childCount nested records>
--
-- Children are serialized as nested records, so the record that immediately
-- follows a record's component payload is either its first child (when
-- childCount > 0) or its next sibling / the next top level entity.  The u32
-- that sits directly in front of a record is therefore always the childCount
-- of the preceding record, which is what makes it possible to rebuild the
-- nesting without decoding a single component.
--
-- Component payloads carry no length field and their layout is driven by the
-- game's component schema, so a payload cannot be walked without implementing
-- every component type.  Instead each record head is located by its exact byte
-- signature and the result is validated against the declared rootEntityCount:
-- a parse is accepted only when it consumes every located record and yields
-- exactly that many top level entities.  Component bytes are never interpreted.
--
-- The parser never writes to stdout/stderr and never touches the filesystem,
-- so it can be embedded into other modules directly.
local M = {}

local byte, sub = string.byte, string.sub
local floor = math.floor

-- ---------------------------------------------------------------- primitives

local function read_u32(s, p)
  local a, b, c, d = byte(s, p, p + 3)
  if not d then return nil end
  return a * 16777216 + b * 65536 + c * 256 + d, p + 4
end

local function read_f32(s, p)
  local b1, b2, b3, b4 = byte(s, p, p + 3)
  if not b4 then return nil end
  local sign = b1 >= 128 and -1 or 1
  local e = (b1 % 128) * 2 + floor(b2 / 128)
  local m = (b2 % 128) * 65536 + b3 * 256 + b4
  if e == 0 then return sign * (m / 8388608) * 2 ^ -126, p + 4 end
  if e == 255 then return nil end -- inf / nan: never valid entity data
  return sign * (1 + m / 8388608) * 2 ^ (e - 127), p + 4
end

local function read_str(s, p, maxLen)
  local n, q = read_u32(s, p)
  if not n or n > maxLen or n > #s - q + 1 then return nil end
  return sub(s, q, q + n - 1), q + n
end

-- ------------------------------------------------------------- record probe

local VERSION_MAX = 8
local CC_MAX = 512
local PATH_MAX = 512
local TAGS_MAX = 512
local NAME_MAX = 128
local POS_MAX = 1e6

-- entity file paths are always XML: vanilla ships them under data/, mods add
-- their own under mods/<mod name>/.
local function path_ok(path, level)
  if #path == 0 or path:find('[%z\1-\31]') then return false end
  if not path:match('%.xml$') then return false end
  if path:find('[^%w_%./%-]') then return false end
  if level == 1 then return path:match('^data/') ~= nil or path:match('^mods/') ~= nil end
  return path:match('^%w') ~= nil
end

local function tags_ok(tags)
  if tags:find('[%z\1-\31]') then return false end
  return tags:find('[^%w_,%.%- ]') == nil
end

-- rule levels: 1 = strict (verified against every sample save file),
-- 2 = relaxed fallback, used only when the strict pass cannot reproduce the
-- declared root entity count.
local function head_at(raw, p, level)
  local name, q = read_str(raw, p, NAME_MAX)
  if not name then return nil end
  if name:find('[%z\1-\31]') then return nil end -- rejects 4-byte shifted false hits

  local version = byte(raw, q)
  if not version then return nil end
  q = q + 1
  if level == 1 then
    if version ~= 0 then return nil end
  elseif version > VERSION_MAX then
    return nil
  end

  local path; path, q = read_str(raw, q, PATH_MAX)
  if not path or not path_ok(path, level) then return nil end

  local tags; tags, q = read_str(raw, q, TAGS_MAX)
  if not tags or not tags_ok(tags) then return nil end

  local x; x, q = read_f32(raw, q)
  local y; y, q = read_f32(raw, q)
  local sx; sx, q = read_f32(raw, q)
  local sy; sy, q = read_f32(raw, q)
  local rotation; rotation, q = read_f32(raw, q)
  if not (x and y and sx and sy and rotation) then return nil end
  local posMax = level == 1 and POS_MAX or POS_MAX * 10
  if math.abs(x) > posMax or math.abs(y) > posMax then return nil end
  -- scale may be negative: mirrored/flipped entities store -x / -y scale
  local ax, ay = math.abs(sx), math.abs(sy)
  if level == 1 then
    if ax <= 0.0001 or ax > 1e3 or ay <= 0.0001 or ay > 1e3 then return nil end
  elseif ax <= 0 or ay <= 0 or ax > 1e6 or ay > 1e6 then
    return nil
  end

  local components; components, q = read_u32(raw, q)
  if not components or components < 1 or components > CC_MAX then return nil end

  -- the record is only credible when a component name really starts here
  local payload = q
  local cname = read_str(raw, payload, 128)
  if not cname or not cname:match('^[%a_][%w_]*Component$') then return nil end

  return {
    offset = p,
    name = name,
    version = version,
    path = path,
    tags = tags,
    x = x, y = y,
    scaleX = sx, scaleY = sy,
    rotation = rotation,
    componentCount = components,
    payloadOffset = payload,
  }
end

local function scan(raw, first, level)
  local recs = {}
  local n = #raw - 4
  for p = first, n do
    local rec = head_at(raw, p, level)
    if rec then recs[#recs + 1] = rec end
  end
  return recs
end

-- -------------------------------------------------------------- tree rebuild
--
-- Child counts are recovered from the u32 in front of the following record
-- (or, for the last record of the buffer, from the trailing u32).  A parse is
-- accepted only when it consumes exactly the scanned records and produces
-- exactly the declared number of top level entities.
local function rebuild(raw, recs, tail, roots)
  local n = #recs
  for i = 1, n do
    local nextStart = recs[i + 1] and recs[i + 1].offset or tail
    local children = read_u32(raw, nextStart - 4) or 0
    if children > n then children = -1 end -- implausible: force a rejected parse
    recs[i].childCount = children
    recs[i].children = {}
  end

  local index, ok = 0, true
  local function take(count, parent)
    for _ = 1, count do
      if index >= n then ok = false; return end
      index = index + 1
      local rec = recs[index]
      if parent then
        local kids = parent.children
        kids[#kids + 1] = rec
        rec.parent = parent
      end
      if rec.childCount > 0 then take(rec.childCount, rec) end
    end
  end
  take(roots, nil)
  return ok and index == n, recs
end

local function collect_roots(recs, raw, tail, roots)
  local ok, parsed = rebuild(raw, recs, tail, roots)
  if not ok then return nil end
  local out = {}
  for _, rec in ipairs(parsed) do
    if not rec.parent then out[#out + 1] = rec end
  end
  for _, rec in ipairs(parsed) do rec.parent = nil end -- parent is build-time only
  if #out ~= roots then return nil end
  return out
end

local function flatten(recs, out)
  out = out or {}
  for _, rec in ipairs(recs) do
    out[#out + 1] = rec
    if rec.children and #rec.children > 0 then flatten(rec.children, out) end
  end
  return out
end
M.flatten = flatten

-- ------------------------------------------------------------------ public

-- data    : raw bytes of a entities_*.bin file (fastlz header included)
-- fastlz  : table exposing fastlz.decompress (as in fastlz.lua)
-- returns : result table; raises on a structurally impossible file
function M.parse(data, fastlz)
  if type(data) ~= 'string' or #data < 8 then error('file shorter than compression header') end

  local c1, c2, c3, c4 = byte(data, 1, 4)
  local compressed = c1 + c2 * 256 + c3 * 65536 + c4 * 16777216
  local d1, d2, d3, d4 = byte(data, 5, 8)
  local decompressed = d1 + d2 * 256 + d3 * 65536 + d4 * 16777216
  if compressed > #data - 8 then error('compressed size exceeds file payload') end

  local raw
  if compressed == decompressed then
    raw = sub(data, 9, 8 + compressed) -- stored uncompressed
  else
    if type(fastlz) ~= 'table' or type(fastlz.decompress) ~= 'function' then
      error('fastlz.decompress is required for compressed blocks')
    end
    local be = string.char(
      floor(decompressed / 16777216) % 256, floor(decompressed / 65536) % 256,
      floor(decompressed / 256) % 256, decompressed % 256)
    raw = fastlz.decompress(be .. sub(data, 9, 8 + compressed))
    if not raw then error('fastlz.decompress returned nil') end
    if #raw > decompressed then raw = sub(raw, 1, decompressed) end
  end

  local flags, p = read_u32(raw, 1)
  if not flags then error('truncated body header') end
  local schemaHash; schemaHash, p = read_str(raw, p, 256)
  if not schemaHash then error('truncated schema hash') end
  local rootCount; rootCount, p = read_u32(raw, p)
  if not rootCount then error('truncated root entity count') end

  local result = {
    compression = { compressedSize = compressed, decompressedSize = decompressed },
    header = { flags = flags, schemaHash = schemaHash, rootEntityCount = rootCount },
    entityCount = 0,
    entities = {},
    warnings = {},
  }

  local tail = #raw + 1
  local recs = scan(raw, p, 1)
  local entities = collect_roots(recs, raw, tail, rootCount)
  local relaxed = false
  if not entities then
    -- fall back to a relaxed probe (odd versions / paths / transforms)
    local recs2 = scan(raw, p, 2)
    entities = collect_roots(recs2, raw, tail, rootCount)
    if entities then
      recs = recs2
      relaxed = true
    end
  end

  if entities then
    for _, rec in ipairs(recs) do rec.parent = nil end
    result.entities = entities
    result.entityCount = #flatten(entities)
    result.recordCount = #recs
    result.structureValid = true
    result.relaxedRules = relaxed or nil
  else
    -- Nesting could not be proven (unknown file variant): keep every entity
    -- whose base data is certain and report the mismatch instead of guessing.
    for i, rec in ipairs(recs) do
      local nextStart = recs[i + 1] and recs[i + 1].offset or tail
      rec.childCount = read_u32(raw, nextStart - 4)
      rec.children = {}
      rec.parent = nil
    end
    result.structureValid = false
    result.entities = recs
    result.entityCount = #recs
    result.recordCount = #recs
    result.warnings[#result.warnings + 1] =
      string.format('entity nesting not validated: %d entities scanned, %d root entities declared',
        #recs, rootCount)
  end

  return result
end

-- Convenience helper for consumers that want a flat list: returns every
-- entity (roots first, then their children) in file order.
function M.flatten(entities, out)
  return flatten(entities, out)
end

return M
