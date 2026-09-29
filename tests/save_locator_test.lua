-- Save slot discovery (files/save_locator.lua).
--
-- The file system is replaced by an in memory tree so that several roots and
-- slots can be described exactly: save00 and save01 in the game directory, a
-- second copy below a per-user data directory, an empty slot and a directory
-- that is not a slot at all.
local support = dofile("tests/save_test_support.lua")
local assert_equal, assert_true = support.assert_equal, support.assert_true

dofile("files/lua_bit.lua")
dofile("files/save_fs.lua")
dofile("files/save_locator.lua")

local locator = BossLocatorSaveLocator
local fs = BossLocatorSaveFs

local chunk = "\1\2\3\4" -- the bytes of a chunk do not matter for discovery

local files = {
    ["save00/world/entities_2.bin"] = chunk,
    ["save00/world/entities_2001.bin"] = chunk,
    ["save00/world/world_sim.bin"] = "not a chunk",
    ["save00/mod_config.xml"] = "<xml/>",
    ["save01/world/entities_2.bin"] = chunk,
    ["save02/world/steam_autocloud.vdf"] = "", -- a slot without entity chunks
    ["save_rec/world/entities_2.bin"] = chunk, -- not a slot
    ["save_shared/config.xml"] = "<Config/>",
    ["userdata/Nolla_Games_Noita/save00/world/entities_2.bin"] = chunk,
}

local times = {
    ["save00/world/entities_2.bin"] = 1700000000,
    ["save00/world/entities_2001.bin"] = 1700000100,
    ["save01/world/entities_2.bin"] = 1700005000, -- the most recent save
    ["save_rec/world/entities_2.bin"] = 1700009000,
}

local tree = support.virtual_fs(files, times)
local roots = { "", "userdata/Nolla_Games_Noita" }
local restore = support.install_virtual_fs(tree, roots)

-- ------------------------------------------------------------------- helpers

assert_equal("save01", locator.normalize_slot("1"), "a bare number is padded like the engine")
assert_equal("save01", locator.normalize_slot("01"), "a padded number is kept")
assert_equal("save01", locator.normalize_slot("save1"), "the save prefix is accepted")
assert_equal("save01", locator.normalize_slot(" save01 "), "whitespace is ignored")
assert_equal(nil, locator.normalize_slot(""), "an empty override means automatic")
assert_equal(nil, locator.normalize_slot(nil), "a missing override means automatic")
assert_equal(nil, locator.normalize_slot("save_shared"), "a non slot name is rejected")

-- --------------------------------------------------------------- discovery

local resolved = locator.resolve({})
assert_true(resolved.ok, "a save directory must be discovered: " .. tostring(resolved.message))
assert_equal("save01", resolved.slot, "the most recently written slot wins")
assert_equal("", resolved.root, "the newest slot lives in the game directory")
assert_equal(1, #resolved.files, "only the entity chunks of the chosen slot are listed")
assert_true(resolved.reason:find("recent") ~= nil,
    "the reason must name the freshness rule, got " .. tostring(resolved.reason))

-- A directory that only holds other files is not a slot candidate.
for _, candidate in ipairs(resolved.candidates) do
    assert_true(candidate.slot ~= "save02", "a slot without chunks must be skipped")
    assert_true(candidate.slot ~= "save_rec", "a directory that is not a slot must be skipped")
end

-- ------------------------------------------------------ slot override

local overridden = locator.resolve({ slot = "save00" })
assert_true(overridden.ok, "an override must resolve")
assert_equal("save00", overridden.slot, "the override wins over freshness")
assert_equal(2, #overridden.files, "every chunk of the overridden slot is listed")
assert_true(overridden.reason:find("save00") ~= nil, "the reason must mention the override")

-- An override for a slot that does not exist falls back to the detection.
local missing = locator.resolve({ slot = "save05" })
assert_true(missing.ok, "a missing override must still produce a result")
assert_equal("save01", missing.slot, "a missing override falls back to the detected slot")
assert_true(missing.reason:find("save05") ~= nil, "the reason must mention the override")

-- The override can also select a slot that only exists below the user data root.
local user_slot = locator.resolve({ slot = "save00", hint = nil })
assert_equal("", user_slot.root,
    "the game directory copy of save00 is preferred on a tie")
assert_true(#user_slot.candidates >= 2, "both copies of save00 must be candidates")

-- ------------------------------------------------------- game reported hint

local hinted = locator.resolve({ hint = "save00" })
assert_equal("save00", hinted.slot, "the slot reported by the game wins over freshness")
assert_true(hinted.reason:find("game") ~= nil, "the reason must name the game hint")

local unknown_hint = locator.resolve({ hint = "save04" })
assert_equal("save01", unknown_hint.slot, "an unknown hint must not break the detection")

-- ------------------------------------------- no times, no listing: fallbacks

local no_times = support.virtual_fs(files, {})
local restore_no_times = support.install_virtual_fs(no_times, roots)
local ordered = locator.resolve({})
assert_true(ordered.ok, "discovery without modification times must work")
assert_equal("save00", ordered.slot,
    "without times the first root and the lowest slot number win, like the engine default")
restore_no_times()

local restore_probe = support.install_virtual_fs(tree, roots)
-- Pretend the platform cannot list directories at all.
BossLocatorSaveFs.list = function()
    return nil, "no directory listing backend"
end
BossLocatorSaveFs.list_paths = function()
    return nil, "no directory listing backend"
end
BossLocatorSaveFs.newest_time = function()
    return nil
end

local probed = locator.resolve({ slot = "save00" })
assert_true(probed.ok, "the chunk index probe must replace a missing listing")
assert_equal("save00", probed.slot, "the override is honoured by the probe fallback")
assert_equal(2, #probed.files, "the probe must find every existing chunk of the slot")
assert_equal("probe", probed.file_source, "the fallback must be reported as a probe")
restore_probe()

-- ------------------------------------------------------------- diagnostics

local described = locator.describe(ordered)
assert_true(type(described) == "string" and #described > 0, "describe must produce text")

local empty_tree = support.virtual_fs({}, {})
local restore_empty = support.install_virtual_fs(empty_tree, roots)
local empty = locator.resolve({})
restore_empty()
assert_true(not empty.ok, "an empty file system must not resolve to a save directory")
assert_true(empty.message:find("no save directory") ~= nil,
    "the failure must explain what was searched: " .. tostring(empty.message))

restore()

print("save_locator_test: ok")
