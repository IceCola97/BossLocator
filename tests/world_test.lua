local player_x = 40000
local player_y = 100
local engine_world = 1

function EntityGetWithTag(tag)
    if tag == "player_unit" then
        return { 1 }
    end
    return {}
end

function EntityGetIsAlive(entity_id)
    return entity_id == 1
end

function EntityGetTransform()
    return player_x, player_y
end

function SessionNumbersGetValue()
    return "0"
end

function GameHasFlagRun()
    return false
end

function GetParallelWorldPosition(x, y)
    if x == player_x and y == player_y then
        return engine_world, 0
    end
    return 0, 0
end

local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") ..
            ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

dofile("files/config.lua")
dofile("files/world.lua")

local current = BossLocatorWorld.current()
assert_equal(1, current.index, "engine world index should be authoritative")
assert_equal(35840, current.offset, "world offset should match the normal width")

GetParallelWorldPosition = nil
assert_equal(1, BossLocatorWorld.index_for_position(35840, 0),
    "normal-width fallback should find East 1")
assert_equal(-1, BossLocatorWorld.index_for_position(-35840, 0),
    "normal-width fallback should find West 1")

function SessionNumbersGetValue()
    return "2"
end

assert_equal(32768, BossLocatorWorld.width(), "NG+ should use compact world width")
assert_equal(1, BossLocatorWorld.index_for_position(32768, 0),
    "NG+ fallback should find East 1")

print("world_test: ok")
