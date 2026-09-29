-- Locates the save directory the running game is using.
--
-- Noita stores its runs in save00, save01, ...  The engine documents the range
-- save00 - save06, and mods such as "Save Slots Enabler" expose the whole
-- range instead of only save00.  The active slot is therefore never hard coded
-- here; it is discovered at runtime like this:
--
--   1. every candidate root (see save_fs.roots) is searched for save<N>
--      directories that actually contain entity chunks,
--   2. a slot reported by the game itself (the WorldStateComponent's session
--      statistic path, or a slot name kept in the session numbers) wins over
--      an inferred one,
--   3. otherwise the most recently written slot wins: the game keeps writing
--      chunks into the slot it is playing,
--   4. "save00" - and with it the plain engine default - is simply the best
--      candidate when nothing indicates otherwise, because candidates are
--      ordered by slot number after freshness,
--   5. an explicit user override always wins over the automatic result.

BossLocatorSaveLocator = BossLocatorSaveLocator or {}

local SLOT_PATTERN = "^save%d+$"
local ENTITY_FILE_PATTERN = "^entities_%-?%d+%.bin$"

-- Entity chunks are named entities_<index>.bin, where the index is built from
-- the chunk coordinates with a stride of 2000:
--
--   index = chunk_x + chunk_y * 2000      (chunk = 512 world pixels)
--
-- verified against a real save: chunk 1999 stores the chunk (-1, 1), chunk
-- 2000 the chunk (0, 1) and chunk -2000 the chunk (0, -1).  The probe fallback
-- walks that grid when the platform cannot list a directory at all, so reading
-- a save never depends on a directory listing being available.  The window
-- covers the whole main world (70 chunks wide) plus the sky and the parallel
-- worlds; a chunk that was never visited has no file and is skipped by the
-- existence probe anyway.
local PROBE_STRIDE = 2000
local PROBE_X_FROM, PROBE_X_TO = -16, 96
local PROBE_Y_FROM, PROBE_Y_TO = -12, 64
local PROBE_SLOT_FROM, PROBE_SLOT_TO = 0, 20
local PROBE_LIMIT = 12000

local function lower(value)
    return string.lower(value or "")
end

local function entity_file_name(name)
    -- accepts a plain file name as well as a path, like save_scanner.matches
    local base = tostring(name or ""):match("[^/\\]*$") or ""
    return lower(base):match(ENTITY_FILE_PATTERN) ~= nil
end

function BossLocatorSaveLocator.is_entity_file(name)
    return entity_file_name(name)
end

local function slot_number(slot)
    return tonumber((slot or ""):match("^save(%d+)$")) or math.huge
end

--- Normalises a user supplied slot ("1", "01", "save1", "save01").
function BossLocatorSaveLocator.normalize_slot(value)
    if value == nil then
        return nil
    end
    local text = tostring(value):gsub("%s", "")
    if text == "" then
        return nil
    end
    local digits = text:match("^save(%d+)$") or text:match("^(%d+)$")
    if digits == nil then
        return nil
    end
    -- The engine names its slots save00 - save06, so a bare number is padded.
    local number = tonumber(digits)
    if number ~= nil and number < 100 then
        return string.format("save%02d", number)
    end
    return "save" .. digits
end

-- ------------------------------------------------------------ entity chunks

--- Lists the entity chunks of one save directory.  Falls back to probing the
--- chunk name grid with io.open when the platform cannot list directories.
function BossLocatorSaveLocator.entity_files(save_dir)
    local world = BossLocatorSaveFs.join(save_dir, "world")

    local paths = BossLocatorSaveFs.list_paths(world, "files")
    if paths ~= nil then
        local files = {}
        for _, path in ipairs(paths) do
            local name = path:match("[^/\\]+$") or path
            if entity_file_name(name) then
                files[#files + 1] = path
            end
        end
        return files, "listing"
    end

    local probed = BossLocatorSaveLocator.probe_entity_files(save_dir)
    if #probed > 0 then
        return probed, "probe"
    end
    return {}, "unavailable"
end

--- Generates the candidate chunk names and keeps the ones that exist.
function BossLocatorSaveLocator.probe_entity_files(save_dir)
    local world = BossLocatorSaveFs.join(save_dir, "world")
    local separator = BossLocatorSaveFs.separator()
    local found = {}
    local seen = {}

    local function probe(index)
        if seen[index] then
            return
        end
        seen[index] = true
        local name = "entities_" .. tostring(index) .. ".bin"
        local path = world .. separator .. name
        if BossLocatorSaveFs.exists(path) then
            found[#found + 1] = path
        end
    end

    local probes = 0
    local stop = false
    for chunk_y = PROBE_Y_FROM, PROBE_Y_TO do
        for chunk_x = PROBE_X_FROM, PROBE_X_TO do
            probes = probes + 1
            if probes > PROBE_LIMIT then
                stop = true
                break
            end
            probe(chunk_x + chunk_y * PROBE_STRIDE)
        end
        if stop then
            break
        end
    end

    table.sort(found)
    return found
end

-- -------------------------------------------------------------- candidates

local function collect_candidates()
    local candidates = {}
    local roots = BossLocatorSaveFs.roots()

    for root_index, root in ipairs(roots) do
        local slots = BossLocatorSaveFs.list(root, "dirs")
        if slots == nil then
            -- No listing: probe the documented slot range instead.
            slots = {}
            for index = PROBE_SLOT_FROM, PROBE_SLOT_TO do
                slots[#slots + 1] = string.format("save%02d", index)
            end
        end

        for _, name in ipairs(slots) do
            if lower(name):match(SLOT_PATTERN) ~= nil then
                local save_dir = BossLocatorSaveFs.join(root, name)
                local files, source = BossLocatorSaveLocator.entity_files(save_dir)
                if #files > 0 then
                    local world = BossLocatorSaveFs.join(save_dir, "world")
                    local score = BossLocatorSaveFs.newest_time(world, "files", entity_file_name)
                    if score == nil and files[1] ~= nil then
                        score = BossLocatorSaveFs.mtime(files[1])
                    end
                    candidates[#candidates + 1] = {
                        root = root,
                        root_index = root_index,
                        slot = name,
                        slot_number = slot_number(name),
                        dir = save_dir,
                        world = world,
                        files = files,
                        file_source = source,
                        score = score,
                    }
                end
            end
        end
    end

    return candidates, roots
end

-- Prefers the freshest slot; without timestamps the first root (the running
-- game's working directory) and then the lowest slot number win, which makes
-- save00 the default exactly as the engine does.
local function preferred(a, b)
    if a.score ~= nil and b.score ~= nil and a.score ~= b.score then
        return a.score > b.score
    end
    if a.score ~= nil and b.score == nil then
        return true
    end
    if a.score == nil and b.score ~= nil then
        return false
    end
    if a.root_index ~= b.root_index then
        return a.root_index < b.root_index
    end
    return a.slot_number < b.slot_number
end

local function file_count(candidate)
    return #candidate.files
end

local function best(candidates)
    local winner = nil
    for _, candidate in ipairs(candidates) do
        if winner == nil or preferred(candidate, winner) then
            winner = candidate
        end
    end
    return winner
end

--- Resolves the save directory to scan.
-- options.slot  : explicit slot name or number (wins over everything else)
-- options.hint  : slot reported by the game itself
-- Returns a table:
--   ok        true when a directory with entity chunks was found
--   dir, root, slot, files, score, source
--   reason    why this directory was chosen
--   message   a human readable explanation (also set when ok is false)
--   candidates, roots
function BossLocatorSaveLocator.resolve(options)
    options = options or {}
    local candidates, roots = collect_candidates()
    local result = {
        ok = false,
        candidates = candidates,
        roots = roots,
        message = nil,
        reason = nil,
    }

    if #candidates > 0 then
        local override = BossLocatorSaveLocator.normalize_slot(options.slot)
        local hint = BossLocatorSaveLocator.normalize_slot(options.hint)
        local chosen = nil
        local reason = nil

        if override ~= nil then
            local matching = {}
            for _, candidate in ipairs(candidates) do
                if candidate.slot == override then
                    matching[#matching + 1] = candidate
                end
            end
            chosen = best(matching)
            if chosen ~= nil then
                reason = "settings override " .. override
            else
                reason = "settings override " .. override ..
                    " has no entity chunks; using the detected slot"
            end
        end

        if chosen == nil and hint ~= nil then
            local matching = {}
            for _, candidate in ipairs(candidates) do
                if candidate.slot == hint then
                    matching[#matching + 1] = candidate
                end
            end
            chosen = best(matching)
            if chosen ~= nil then
                reason = "reported by the game (" .. hint .. ")"
            end
        end

        if chosen == nil then
            chosen = best(candidates)
            local detected
            if chosen.score ~= nil then
                detected = "most recently written save slot"
            else
                detected = "first save slot with entity chunks"
            end
            if reason ~= nil then
                -- keep the note about the override that could not be used
                reason = reason .. " (" .. detected .. ")"
            else
                reason = detected
            end
        end

        result.ok = true
        result.dir = chosen.dir
        result.root = chosen.root
        result.slot = chosen.slot
        result.world = chosen.world
        result.files = chosen.files
        result.file_source = chosen.file_source
        result.score = chosen.score
        result.reason = reason
        result.message = string.format("%s (%s, %d entity chunks)",
            chosen.slot, reason, file_count(chosen))
        return result
    end

    local roots_text = {}
    for _, root in ipairs(roots) do
        roots_text[#roots_text + 1] = root == "" and "." or root
    end
    result.message = "no save directory with entity chunks was found below: " ..
        table.concat(roots_text, ", ")
    return result
end

--- Minimal description of the discovery, for diagnostics in the settings UI.
function BossLocatorSaveLocator.describe(resolved)
    if resolved == nil or resolved.ok ~= true then
        return resolved ~= nil and resolved.message or "the save directory was not resolved"
    end
    local root = resolved.root
    if root == "" then
        root = "."
    end
    return string.format("%s%ssave: %s, %d entity chunks (%s, %s)",
        root, BossLocatorSaveFs.separator(), resolved.slot, #resolved.files,
        tostring(resolved.file_source), BossLocatorSaveFs.backend())
end
