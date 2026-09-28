local globals = {}
local entities = {}
local frame = 0

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

function EntityGetWithTag(tag)
    local result = {}
    for id, entity in pairs(entities) do
        if entity.alive and entity.tags ~= nil and entity.tags[tag] then
            table.insert(result, id)
        end
    end
    return result
end

function EntityHasTag(entity_id, tag)
    local entity = entities[entity_id]
    return entity ~= nil and entity.tags ~= nil and entity.tags[tag] == true
end

function EntityGetIsAlive(entity_id)
    local entity = entities[entity_id]
    return entity ~= nil and entity.alive == true
end

function EntityGetTransform(entity_id)
    local entity = entities[entity_id]
    return entity.x, entity.y
end

function EntityGetFilename(entity_id)
    return entities[entity_id].filename or ""
end

function EntityGetName(entity_id)
    return entities[entity_id].name or ""
end

function EntityGetFirstComponentIncludingDisabled(entity_id, component_type, tag)
    local entity = entities[entity_id]
    if entity == nil then
        return nil
    end
    if component_type == "DamageModelComponent" then
        return entity_id
    end
    if component_type == "LuaComponent" and tag == "boss_locator_death_hook" then
        return entity.hooked and (10000 + entity_id) or nil
    end
    return nil
end

function EntityGetComponentIncludingDisabled(entity_id, component_type)
    local entity = entities[entity_id]
    if component_type == "LuaComponent" and entity ~= nil and entity.orb_script then
        return { 20000 + entity_id }
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

function EntityAddComponent2(entity_id)
    entities[entity_id].hooked = true
    return 10000 + entity_id
end

function EntitiesGetMaxID()
    local max_id = 0
    for id in pairs(entities) do
        max_id = math.max(max_id, id)
    end
    return max_id
end

function GameGetFrameNum()
    return frame
end

function GameHasFlagRun()
    return false
end

function ModSettingGet()
    return true
end

function GameGetCameraBounds()
    return -200, -100, 400, 200
end

function GuiCreate()
    return 1
end

function GuiStartFrame() end
function GuiGetScreenDimensions()
    return 400, 200
end
function GuiText() end

local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") ..
            ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

dofile("files/config.lua")
dofile("files/world.lua")
dofile("files/state.lua")
dofile("files/locator.lua")

entities[1] = {
    alive = true,
    filename = "data/entities/animals/failed_alchemist_b.xml",
    name = "$animal_failed_alchemist_b",
    tags = { mage = true },
    x = 100,
    y = 200,
    hp = 10,
}

BossLocator.reset()
frame = 1
BossLocator.update()
local record = BossLocatorState.get(0, "epaalkemisti")
assert_equal("alive", record.status, "initial Boss should be alive")
assert_equal(true, entities[1].hooked, "tracked Boss should get a death hook")

entities[1].hp = 0
frame = 2
BossLocator.update()
record = BossLocatorState.get(0, "epaalkemisti")
assert_equal("revive_pending", record.status, "first body death is not final")

entities[1].alive = false
entities[2] = {
    alive = true,
    filename = "data/entities/buildings/failed_alchemist_orb.xml",
    name = "$animal_failed_alchemist_orb",
    tags = {},
    x = 105,
    y = 205,
    hp = 10,
    orb_script = true,
}
frame = 3
BossLocator.update()
record = BossLocatorState.get(0, "epaalkemisti")
assert_equal("revive_pending", record.status, "live orb should remain pending")

entities[2].alive = false
entities[3] = {
    alive = true,
    filename = "data/entities/animals/failed_alchemist_b.xml",
    name = "$animal_failed_alchemist_b",
    tags = { mage = true },
    x = 106,
    y = 206,
    hp = 10,
}
frame = 4
BossLocator.update()
record = BossLocatorState.get(0, "epaalkemisti")
assert_equal("alive", record.status,
    "replacement Boss should win over old orb disappearance")
assert_equal(106, record.last_x, "replacement position should be retained")

entities[3].alive = false
entities[4] = {
    alive = true,
    filename = "unknown",
    name = "unknown",
    tags = {},
    x = 106,
    y = 206,
    hp = 0,
    orb_script = true,
}
frame = 5
BossLocator.update()
record = BossLocatorState.get(0, "epaalkemisti")
assert_equal("dead", record.status, "destroyed orb should be a final death")

print("locator_test: ok")
