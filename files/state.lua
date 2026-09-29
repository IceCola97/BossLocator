-- Per-save, per-world state.
--
-- GlobalsSetValue/GlobalsGetValue are used instead of the user's mod settings:
-- Globals live in the current world save, while the checkboxes in settings.lua
-- are user preferences.  Every key contains the NG+ namespace and the
-- parallel-world index so a death in one world cannot hide a copy elsewhere.
-- The revive_pending status is intentionally persisted without a mod-owned
-- countdown; the vanilla entity/orb decides when the next transition occurs.

BossLocatorState = BossLocatorState or {}

local PREFIX = "boss_locator.v1."
local REVISION_KEY = PREFIX .. "sync_revision"
local cache = {}
local cache_revision = nil

local function can_read_globals()
    return type(GlobalsGetValue) == "function"
end

local function can_write_globals()
    return type(GlobalsSetValue) == "function"
end

local function current_revision()
    if not can_read_globals() then
        return 0
    end
    return tonumber(GlobalsGetValue(REVISION_KEY, "0")) or 0
end

--- Persisted counter that is bumped whenever a save scan rewrites positions.
-- A scan runs in the settings context while the tracker keeps its own cache in
-- the world context, so the counter is what tells the tracker that its records
-- are stale.  Positions alone would not do: an unchanged status keeps the cache
-- valid.
local function bump_revision()
    if not can_write_globals() then
        return
    end
    GlobalsSetValue(REVISION_KEY, tostring(current_revision() + 1))
end

local function current_namespace()
    if type(SessionNumbersGetValue) ~= "function" then
        return "ng0"
    end
    local count = tonumber(SessionNumbersGetValue("NEW_GAME_PLUS_COUNT")) or 0
    if count < 0 then
        count = 0
    end
    return "ng" .. tostring(math.floor(count))
end

local function record_key(world_index, boss_id)
    return current_namespace() .. ".w" .. tostring(world_index) .. ".b" .. boss_id
end

local function global_key(key, field)
    return PREFIX .. key .. "." .. field
end

local function read(key, field, default_value)
    if not can_read_globals() then
        return default_value
    end
    return GlobalsGetValue(global_key(key, field), default_value)
end

local function write(key, field, value)
    if not can_write_globals() then
        return
    end
    GlobalsSetValue(global_key(key, field), tostring(value))
end

local function number_or_nil(value)
    if value == nil or value == "" then
        return nil
    end
    return tonumber(value)
end

local function bool_from_string(value)
    return value == true or value == "1" or value == "true"
end

local function load_record(world_index, boss_id)
    local key = record_key(world_index, boss_id)
    local record = {
        key = key,
        world_index = world_index,
        boss_id = boss_id,
        status = read(key, "status", "unknown"),
        observed = bool_from_string(read(key, "observed", "0")),
        last_x = number_or_nil(read(key, "last_x", "")),
        last_y = number_or_nil(read(key, "last_y", "")),
        last_seen_frame = number_or_nil(read(key, "last_seen_frame", "")),
        death_x = number_or_nil(read(key, "death_x", "")),
        death_y = number_or_nil(read(key, "death_y", "")),
        death_frame = number_or_nil(read(key, "death_frame", "")),
        last_persist_frame = nil,
    }
    cache[key] = record
    return record
end

function BossLocatorState.get(world_index, boss_id)
    if can_read_globals() then
        local revision = current_revision()
        if cache_revision ~= revision then
            -- Another Lua context (the save scanner) rewrote the records.
            cache_revision = revision
            cache = {}
        end
    end

    local key = record_key(world_index, boss_id)
    local record = cache[key]
    if record == nil then
        return load_record(world_index, boss_id)
    end

    -- LuaComponents execute in separate Lua contexts.  A death hook can write
    -- the same Globals while this runtime still has a cached record, so reload
    -- when another context changed the persisted status.
    if can_read_globals() then
        local persisted_status = read(key, "status", record.status)
        if persisted_status ~= record.status then
            return load_record(world_index, boss_id)
        end
    end
    return record
end

function BossLocatorState.clear_runtime_cache()
    cache = {}
    cache_revision = nil
end

local function persist_record(record)
    write(record.key, "status", record.status)
    write(record.key, "observed", record.observed and "1" or "0")
    if record.last_x ~= nil then
        write(record.key, "last_x", record.last_x)
    end
    if record.last_y ~= nil then
        write(record.key, "last_y", record.last_y)
    end
    if record.last_seen_frame ~= nil then
        write(record.key, "last_seen_frame", record.last_seen_frame)
    end
    if record.death_x ~= nil then
        write(record.key, "death_x", record.death_x)
    end
    if record.death_y ~= nil then
        write(record.key, "death_y", record.death_y)
    end
    if record.death_frame ~= nil then
        write(record.key, "death_frame", record.death_frame)
    end
end

local function should_persist_position(record, frame, force)
    if force or record.last_persist_frame == nil then
        return true
    end
    local interval = 15
    if BossLocatorConfig ~= nil and BossLocatorConfig.POSITION_SAVE_INTERVAL ~= nil then
        interval = BossLocatorConfig.POSITION_SAVE_INTERVAL
    end
    return frame - record.last_persist_frame >= interval
end

function BossLocatorState.mark_seen(config, world_index, x, y, frame)
    local record = BossLocatorState.get(world_index, config.id)
    -- A confirmed death is sticky for this run/world.  Resurrection-aware
    -- entries reopen from revive_pending, while explicitly repeatable types
    -- reopen from defeated when a genuinely new entity is observed.
    if record.status == "dead" then
        return record
    end

    local status_changed = record.status ~= "alive"
    record.status = "alive"
    record.observed = true
    record.last_x = x
    record.last_y = y
    record.last_seen_frame = frame

    if should_persist_position(record, frame, status_changed) then
        record.last_persist_frame = frame
        persist_record(record)
    end
    return record
end

function BossLocatorState.mark_revival_pending(config, world_index, x, y, frame)
    local record = BossLocatorState.get(world_index, config.id)
    if record.status == "dead" then
        return record
    end

    record.status = "revive_pending"
    record.observed = true
    if x ~= nil then
        record.last_x = x
    end
    if y ~= nil then
        record.last_y = y
    end
    record.last_seen_frame = frame
    record.last_persist_frame = frame
    persist_record(record)
    return record
end

function BossLocatorState.mark_revival_orb_seen(config, world_index, x, y, frame, preserve_alive)
    local record = BossLocatorState.get(world_index, config.id)
    if record.status == "dead" then
        return record
    end

    -- A replacement living Boss can be observed in the same frame as the old
    -- orb is streamed out.  Do not let the old orb move the record backwards
    -- from alive to revive_pending.
    if record.status == "alive" and preserve_alive then
        return record
    end

    -- Seeing the orb confirms the intermediate state, but does not make the
    -- Boss alive and does not start a new death record.
    record.status = "revive_pending"
    record.observed = true
    if x ~= nil then
        record.last_x = x
    end
    if y ~= nil then
        record.last_y = y
    end
    record.last_seen_frame = frame
    if should_persist_position(record, frame, false) then
        record.last_persist_frame = frame
        persist_record(record)
    end
    return record
end

function BossLocatorState.mark_revival_orb_unloaded(config, world_index, x, y, frame, preserve_alive)
    -- Chunk streaming must not turn the pending orb into a permanent death or
    -- reset its position.  The game's own entity state is authoritative when
    -- the area is loaded again.
    local record = BossLocatorState.get(world_index, config.id)
    if record.status == "alive" and preserve_alive then
        return record
    end
    return BossLocatorState.mark_revival_pending(config, world_index, x, y, frame)
end

function BossLocatorState.mark_unloaded(config, world_index, x, y, frame)
    local record = BossLocatorState.get(world_index, config.id)
    if record.status == "dead" or record.status == "defeated" then
        return record
    end

    record.status = "unloaded"
    record.observed = record.observed or x ~= nil or y ~= nil
    if x ~= nil then
        record.last_x = x
    end
    if y ~= nil then
        record.last_y = y
    end
    record.last_seen_frame = frame
    record.last_persist_frame = frame
    persist_record(record)
    return record
end

--- Records a position recovered from a save file scan (see files/save_sync.lua).
--
-- A stored entity proves where a Boss was when the game last wrote the chunk,
-- but not that it is alive: corpses are stored as entities too.  A confirmed
-- death therefore stays sticky, a Boss that is currently tracked keeps its
-- live status, the death orb of a resurrection-aware Boss becomes
-- "revive_pending", and every other record becomes "unloaded" - the position is
-- known, the current load state is not.
-- Returns record, changed, dead.
function BossLocatorState.sync_saved_position(config, world_index, x, y, frame, role)
    local record = BossLocatorState.get(world_index, config.id)
    if record.status == "dead" or record.status == "defeated" then
        return record, false, true
    end

    local changed = record.last_x ~= x or record.last_y ~= y
    record.last_x = x
    record.last_y = y
    record.observed = true
    record.last_seen_frame = frame

    local target = "unloaded"
    if role == "revival_orb" then
        target = "revive_pending"
    end
    if record.status ~= "alive" and record.status ~= target then
        record.status = target
        changed = true
    end

    record.last_persist_frame = frame
    persist_record(record)
    bump_revision()
    return record, changed, false
end

function BossLocatorState.mark_dead(config, world_index, x, y, frame)
    local record = BossLocatorState.get(world_index, config.id)
    local final_status = config.repeatable and "defeated" or "dead"
    if record.status == final_status and record.death_frame ~= nil then
        return record
    end
    record.status = final_status
    record.observed = true
    if x ~= nil then
        record.last_x = x
        record.death_x = x
    end
    if y ~= nil then
        record.last_y = y
        record.death_y = y
    end
    record.last_seen_frame = frame
    record.death_frame = frame
    record.last_persist_frame = frame
    persist_record(record)
    return record
end

function BossLocatorState.is_dead(world_index, boss_id)
    return BossLocatorState.get(world_index, boss_id).status == "dead"
end

function BossLocatorState.get_position(config, world_index, world_offset)
    local record = BossLocatorState.get(world_index, config.id)
    if record.status == "dead" or record.status == "defeated" then
        return nil, nil, record
    end
    if record.last_x ~= nil and record.last_y ~= nil then
        return record.last_x, record.last_y, record
    end
    if config.default_position ~= nil then
        local offset = 0
        if config.world_policy ~= "main" then
            offset = world_offset or 0
        end
        return config.default_position.x + offset,
            config.default_position.y,
            record
    end
    return nil, nil, record
end

function BossLocatorState.status_text(config, world_index, world_offset)
    if not BossLocatorConfig.is_visible_in_world(config, world_index) then
        return "Not present in the current world."
    end

    local record = BossLocatorState.get(world_index, config.id)
    if record.status == "dead" then
        return "Dead in this world; marker hidden."
    end
    if record.status == "defeated" then
        return "Last observed instance was defeated; another instance can spawn."
    end
    if record.status == "alive" then
        return "Alive; position is being tracked."
    end
    if record.status == "unloaded" then
        return "Area unloaded; last known position is retained."
    end
    if record.status == "revive_pending" then
        return "Resurrection pending; last known position is retained."
    end
    if record.last_x ~= nil and record.last_y ~= nil then
        return "Not currently loaded; last known position is retained."
    end
    if config.default_position ~= nil then
        return "Not observed yet; using configured default position."
    end
    return "Not observed yet; no marker until this Boss is loaded."
end

function BossLocatorState.namespace()
    return current_namespace()
end
