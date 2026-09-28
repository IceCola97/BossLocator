local globals = {}

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

function SessionNumbersGetValue(key)
    if key == "NEW_GAME_PLUS_COUNT" then
        return "0"
    end
    return "0"
end

function EntityHasTag()
    return false
end

local function assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") ..
            ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

dofile("files/config.lua")
dofile("files/state.lua")

local revive = BossLocatorConfig.get_by_id("epaalkemisti")
local ordinary = BossLocatorConfig.get_by_id("kolmisilma")
local repeatable = BossLocatorConfig.get_by_id("sauvojen_tuntija")

local record = BossLocatorState.mark_seen(revive, 0, 100, 200, 1)
assert_equal("alive", record.status, "living Boss should be tracked")

BossLocatorState.clear_runtime_cache()
record = BossLocatorState.get(0, revive.id)
assert_equal("alive", record.status, "alive status should persist")
assert_equal(100, record.last_x, "x coordinate should persist")

BossLocatorState.mark_revival_pending(revive, 0, 110, 210, 2)
BossLocatorState.clear_runtime_cache()
record = BossLocatorState.get(0, revive.id)
assert_equal("revive_pending", record.status, "pending status should persist")

BossLocatorState.mark_seen(revive, 0, 120, 220, 3)
record = BossLocatorState.mark_revival_orb_seen(revive, 0, 110, 210, 3, true)
assert_equal("alive", record.status, "old orb must not overwrite a replacement Boss")
assert_equal(120, record.last_x, "replacement Boss position should win")

record = BossLocatorState.mark_revival_orb_seen(revive, 0, 110, 210, 4, false)
assert_equal("revive_pending", record.status, "orb alone should enter pending state")

BossLocatorState.mark_dead(revive, 0, 110, 210, 5)
record = BossLocatorState.mark_seen(revive, 0, 130, 230, 6)
assert_equal("dead", record.status, "confirmed orb destruction should be sticky")

BossLocatorState.mark_seen(repeatable, 0, 300, 400, 7)
BossLocatorState.mark_dead(repeatable, 0, 300, 400, 8)
record = BossLocatorState.mark_seen(repeatable, 0, 320, 420, 9)
assert_equal("alive", record.status, "new repeatable Boss instance should reopen")

BossLocatorState.mark_seen(ordinary, 1, 500, 600, 8)
BossLocatorState.mark_unloaded(ordinary, 1, 510, 610, 9)
record = BossLocatorState.get(1, ordinary.id)
assert_equal("unloaded", record.status, "chunk exit should not count as death")
assert_equal(510, record.last_x, "chunk exit should retain last x")
assert_equal(610, record.last_y, "chunk exit should retain last y")
assert_equal("unknown", BossLocatorState.get(0, ordinary.id).status,
    "parallel-world state must be isolated")

local x, y = BossLocatorState.get_position(ordinary, 0, 0)
assert_equal(nil, x, "unobserved Boss without a default should have no marker")
assert_equal(nil, y, "unobserved Boss without a default should have no marker")

BossLocatorState.mark_seen(ordinary, 0, 700, 800, 10)
BossLocatorState.mark_dead(ordinary, 0, 700, 800, 11)
record = BossLocatorState.mark_seen(ordinary, 0, 710, 810, 12)
assert_equal("dead", record.status, "unique Boss final death should remain sticky")

print("state_test: ok")
