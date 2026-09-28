local globals = {}
local current_entity = 1
local frame = 10
local entities = {
    [1] = {
        filename = "data/entities/buildings/failed_alchemist_orb.xml",
        name = "$animal_failed_alchemist_orb",
        x = 100,
        y = 200,
        hp = 0,
    },
    [2] = {
        filename = "unknown",
        name = "unknown",
        x = 35850,
        y = 210,
        hp = 10,
    },
    [3] = {
        filename = "data/entities/animals/boss_centipede/boss_centipede.xml",
        name = "$animal_boss_centipede",
        x = 300,
        y = 400,
        hp = 0,
    },
}

function GlobalsGetValue(key, default_value)
    local value = globals[key]
    if value == nil then
        return default_value
    end
    return value
end

function GlobalsSetValue(key, value)
    globals[key] = tostring(value)
end

function SessionNumbersGetValue()
    return "0"
end

function GetParallelWorldPosition(x)
    return math.floor((x / 35840) + 0.5), 0
end

function GetUpdatedEntityID()
    return current_entity
end

function EntityGetFilename(entity_id)
    return entities[entity_id].filename
end

function EntityGetName(entity_id)
    return entities[entity_id].name
end

function EntityGetTransform(entity_id)
    local entity = entities[entity_id]
    return entity.x, entity.y
end

function EntityGetFirstComponentIncludingDisabled(entity_id, component_type)
    if component_type == "DamageModelComponent" then
        return entity_id
    end
    return nil
end

function EntityGetComponentIncludingDisabled(entity_id, component_type)
    if component_type == "LuaComponent" and entity_id == 2 then
        return { 1000 + entity_id }
    end
    return {}
end

function ComponentGetValue2(component_id, field)
    if field == "hp" then
        return entities[component_id].hp
    end
    if field == "script_source_file" then
        return "data/scripts/buildings/failed_alchemist_orb.lua"
    end
    return nil
end

function EntityHasTag()
    return false
end

function GameGetFrameNum()
    return frame
end

local loaded = {}
function dofile_once(path)
    if loaded[path] then
        return
    end
    loaded[path] = true
    local local_path = string.gsub(path, "^mods/boss_locator/", "")
    dofile(local_path)
end

local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") ..
            ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

dofile("files/death_hook.lua")
death(0, "", 0, false)
assert_equal("dead", BossLocatorState.get(0, "epaalkemisti").status,
    "zero-health orb should confirm final death")

current_entity = 2
frame = 11
dofile("files/death_hook.lua")
death(0, "", 0, false)
assert_equal("revive_pending", BossLocatorState.get(1, "epaalkemisti").status,
    "healthy expiring orb should remain pending")

current_entity = 3
frame = 12
dofile("files/death_hook.lua")
death(0, "", 0, false)
assert_equal("dead", BossLocatorState.get(0, "kolmisilma").status,
    "ordinary Boss death should be final")

print("death_hook_test: ok")
