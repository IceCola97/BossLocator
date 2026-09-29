-- End to end test of the save scan (files/save_sync.lua).
--
-- A save tree is built in memory from real binary entity chunks (compressed
-- with the vendored fastlz module), the game API is stubbed, and the scan is
-- expected to record exactly the Boss entities that are really Bosses - not
-- their helper entities, and not unrelated files whose name merely contains the
-- same word.
local support = dofile("tests/save_test_support.lua")
local assert_equal, assert_true = support.assert_equal, support.assert_true

local state = support.install_game_stubs({ frame = 500 })
local sync = support.load_runtime_modules()
local scanner, parser, fastlz = support.install_scanner_modules()

-- ------------------------------------------------------------------ fixtures

local function boss(name, path, tags, x, y, children)
    return {
        name = name,
        path = path,
        tags = tags,
        x = x,
        y = y,
        children = children,
    }
end

local chunk_one = support.entity_body({
    boss("$animal_boss_centipede", "data/entities/animals/boss_centipede/boss_centipede.xml",
        "enemy,mortal,hittable,boss,boss_centipede", -1000, 500, {
            -- a helper entity of the Boss: same folder, similar name, and a name
            -- that starts with the Boss' own name
            boss("$animal_boss_centipede_minion",
                "data/entities/animals/boss_centipede/boss_centipede_minion.xml",
                "boss_centipede_minion", -1020, 520),
        }),
    -- files that contain the pattern but are not the Boss
    boss("$animal_boss_dragon_endcrystal",
        "data/entities/projectiles/orb_green_boss_dragon.xml", "projectile", -900, 600),
    boss("$animal_damage_friendly", "data/entities/misc/custom_cards/damage_friendly.xml",
        "card", -800, 700),
    boss("$animal_zombie", "data/entities/animals/zombie.xml", "enemy,mortal", -700, 800),
})

local chunk_two = support.entity_body({
    -- a Boss in a parallel world (world index 1)
    boss("$animal_boss_dragon", "data/entities/animals/boss_dragon.xml",
        "enemy,mortal,hittable,boss_dragon", 36840, 500),
    -- the parallel copy of the Alchemist, which is its own entity
    boss("$animal_parallel_alchemist",
        "data/entities/animals/parallel/alchemist/parallel_alchemist.xml",
        "touchmagic_immunity,polymorphable_NOT", 36840, 1200),
    -- its sprite is not an entity at all, but a stored record of the same
    -- folder must not be mistaken for the Boss either
    boss("sprite", "data/entities/animals/parallel/alchemist/sprite.xml", "", 36840, 1210),
    -- the death orb of a resurrection aware Boss
    boss("$animal_failed_alchemist_orb",
        "data/entities/animals/failed_alchemist_orb.xml", "item", 200, 300),
})

local files = {
    ["save00/world/entities_2.bin"] = support.chunk_file(chunk_one, fastlz, true),
    ["save00/world/entities_2001.bin"] = support.chunk_file(chunk_two, fastlz, true),
    -- a stored (uncompressed) chunk must work as well
    ["save00/world/entities_-1.bin"] = support.chunk_file(
        support.entity_body({ boss("$animal_zombie", "data/entities/animals/zombie.xml",
            "enemy,mortal", 10, 10) }), fastlz, false),
    -- a slot that is not used
    ["save01/world/entities_2.bin"] = support.chunk_file(
        support.entity_body({ boss("$animal_zombie", "data/entities/animals/zombie.xml",
            "enemy,mortal", 20, 20) }), fastlz, true),
}

local times = {
    ["save00/world/entities_2.bin"] = 1700000000,
    ["save00/world/entities_2001.bin"] = 1700000100,
    ["save00/world/entities_-1.bin"] = 1699999900,
    ["save01/world/entities_2.bin"] = 1600000000, -- older than save00
}

local tree = support.virtual_fs(files, times)
local restore_fs = support.install_virtual_fs(tree, { "" })

-- ------------------------------------------------------------------ the scan

assert_true(sync.capability(false).can_scan, "the scan must be offered inside a run")

local result = sync.scan({ in_main_menu = false })
assert_true(result.ok, "the scan must succeed: " .. tostring(result.message))
assert_equal("save00", result.slot, "the most recent slot must be scanned")
assert_equal(3, result.files, "every chunk of the slot must be read")
assert_equal(0, result.parse_failed, "no chunk may fail to parse")
assert_equal(0, result.read_failed, "no chunk may fail to read")
assert_equal(4, result.matched_bosses, "exactly four Boss records must be matched")
assert_equal(4, result.updated, "all four Boss positions must be recorded")

-- Kolmisilmä: world 0, position from the save file.
local kolmisilma = BossLocatorConfig.get_by_id("kolmisilma")
local record = BossLocatorState.get(0, kolmisilma.id)
assert_equal("unloaded", record.status, "a stored Boss is known but not proven loaded")
assert_equal(-1000, record.last_x, "the stored x coordinate must be recorded")
assert_equal(500, record.last_y, "the stored y coordinate must be recorded")

-- The Dragon sits in a parallel world, so it is a different record.
local dragon = BossLocatorConfig.get_by_id("suomuhauki")
local dragon_record = BossLocatorState.get(1, dragon.id)
assert_equal(36840, dragon_record.last_x, "the parallel world copy must be recorded there")
assert_equal("unknown", BossLocatorState.get(0, dragon.id).status,
    "a Boss in another world must not appear in world 0")

-- The parallel copy of the Alchemist is its own entity, and must be attributed
-- to the shadow rather than to the main Alchemist.
local shadow = BossLocatorConfig.get_by_id("alkemistin_varjo")
local shadow_record = BossLocatorState.get(1, shadow.id)
assert_equal(36840, shadow_record.last_x, "the shadow of the Alchemist must be recorded")
assert_equal(1200, shadow_record.last_y, "the shadow position must come from the save")
local high_alchemist = BossLocatorConfig.get_by_id("ylialkemisti")
assert_equal("unknown", BossLocatorState.get(1, high_alchemist.id).status,
    "the parallel copy is not the main Alchemist")

-- The death orb of the Non-alchemist is a resurrection, not a death.
local revive = BossLocatorConfig.get_by_id("epaalkemisti")
local revive_record = BossLocatorState.get(0, revive.id)
assert_equal("revive_pending", revive_record.status, "an orb must be a pending resurrection")
assert_equal(200, revive_record.last_x, "the orb position must be recorded")

-- Helper entities and look-alike files must not be mistaken for Bosses.
local toveri = BossLocatorConfig.get_by_id("toveri")
assert_equal("unknown", BossLocatorState.get(0, toveri.id).status,
    "damage_friendly.xml is not Toveri")
assert_equal("unknown", BossLocatorState.get(1, toveri.id).status,
    "damage_friendly.xml is not Toveri in any world")

-- A second scan of the same save must be idempotent.
local again = sync.scan({ in_main_menu = false })
assert_true(again.ok, "a repeated scan must succeed")
assert_equal(0, again.updated, "a repeated scan must not change anything")
assert_equal(4, again.unchanged, "a repeated scan must report the records as unchanged")

-- ------------------------------------------------------- confirmed deaths

BossLocatorState.mark_dead(kolmisilma, 0, -1000, 500, 600)
local after_death = sync.scan({ in_main_menu = false })
assert_true(after_death.ok, "a scan after a death must succeed")
assert_equal(1, after_death.skipped, "the dead Boss must be skipped")
assert_equal("dead", BossLocatorState.get(0, kolmisilma.id).status,
    "a stored entity must not resurrect a confirmed death")

-- ------------------------------------------------ cross context invalidation

-- The tracker caches records per Lua context; a scan runs in the settings
-- context, so the persisted revision has to invalidate that cache.
BossLocatorState.clear_runtime_cache()
local cached = BossLocatorState.get(1, dragon.id)
assert_equal(36840, cached.last_x, "the cache must be primed")

local moved = support.virtual_fs({
    ["save00/world/entities_2.bin"] = support.chunk_file(support.entity_body({
        boss("$animal_boss_dragon", "data/entities/animals/boss_dragon.xml",
            "enemy,mortal,hittable,boss_dragon", 36840, 900),
    }), fastlz, true),
}, { ["save00/world/entities_2.bin"] = 1700010000 })
local restore_moved = support.install_virtual_fs(moved, { "" })
local moved_scan = sync.scan({ in_main_menu = false })
assert_true(moved_scan.ok, "the second save tree must scan")
assert_equal(900, BossLocatorState.get(1, dragon.id).last_y,
    "a scan must invalidate the cached position of the tracker")
restore_moved()

-- --------------------------------------------------- slice by slice scanning

-- The settings screen and the runtime process a scan in slices; the result must
-- be the same as a scan that runs in one go.
BossLocatorState.clear_runtime_cache()
local job, failure = sync.begin_scan({ in_main_menu = false })
assert_true(job ~= nil, "a scan job must be created: " ..
    tostring(failure and failure.message))
assert_equal(3, #job.files, "the job must know every chunk of the slot")

local steps = 0
local progress = nil
repeat
    progress = sync.step_scan(job, { max_files = 1, max_bytes = 1 })
    steps = steps + 1
until progress.running ~= true or steps > 20
assert_true(steps >= 3, "a one file budget must need one step per chunk, got " .. steps)
assert_true(progress.done == progress.total, "the job must report full progress")
assert_true(progress.result ~= nil and progress.result.ok == true,
    "the finished job must carry a result")
assert_equal(3, progress.result.files, "every chunk must have been read")

-- A finished job must not be scanned twice.
local repeated = sync.step_scan(job)
assert_true(repeated.running == false and repeated.result == progress.result,
    "a finished job must stay finished")

-- ------------------------------------------------------------- gating rules

local in_menu = sync.scan({ in_main_menu = true })
assert_true(not in_menu.ok, "the scan must be refused in the main menu")
assert_equal("in_game", in_menu.stage, "the reason must be that a run is needed")

local saved_available = BossLocatorSaveFs.available
BossLocatorSaveFs.available = function()
    return false, "io.open is not available"
end
local ability = sync.capability(false)
assert_true(not ability.can_scan, "a restricted Lua state must not offer the scan")
assert_equal("unsafe_api", ability.stage, "the reason must be the missing permission")
assert_true(sync.scan({ in_main_menu = false }).stage == "unsafe_api",
    "the scan itself must refuse a restricted Lua state")
BossLocatorSaveFs.available = saved_available

-- -------------------------------------------------------------- auto syncing

state.settings["boss_locator.save_scan_on_load"] = true
sync.on_world_initialized()
for _ = 1, 121 do
    sync.tick()
end
local automatic = sync.last_result()
assert_true(automatic ~= nil and automatic.ok == true and automatic.reason == "auto",
    "the automatic scan must run once after the world is loaded")
assert_true(state.printed ~= nil and state.printed:find("Boss Locator") ~= nil,
    "the automatic scan must be logged")

state.settings["boss_locator.save_scan_on_load"] = false
sync.on_world_initialized()
for _ = 1, 121 do
    sync.tick()
end

-- ------------------------------------------------------- slot override setting

state.settings["boss_locator.save_slot_override"] = "save01"
local overridden = sync.scan({ in_main_menu = false })
assert_true(overridden.ok, "an override scan must succeed")
assert_equal("save01", overridden.slot, "the override setting must be used")
state.settings["boss_locator.save_slot_override"] = ""

restore_fs()

print("save_sync_test: ok")
