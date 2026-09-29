-- Filesystem layer of the save scanner (files/save_fs.lua).
--
-- This test runs against real files, but only reads them: the shared sample
-- save that ships with the repository and the repository's own files are used
-- as the fixture, so nothing is written anywhere.
local support = dofile("tests/save_test_support.lua")
local assert_equal, assert_true = support.assert_equal, support.assert_true

dofile("files/lua_bit.lua")
dofile("files/save_fs.lua")
dofile("files/save_locator.lua")

local fs = BossLocatorSaveFs
local sample = "saves/NoitaSaveTest/sample_save/save00"

-- ------------------------------------------------------------------ platform

local platform = fs.platform()
assert_true(platform == "windows" or platform == "linux" or platform == "osx" or
    platform == "posix", "the platform must be detected: " .. tostring(platform))

local separator = fs.separator()
assert_true(separator == "\\" or separator == "/", "separator must be a path separator")

-- ---------------------------------------------------------------------- paths

assert_equal("a" .. separator .. "b", fs.join("a", "b"), "join keeps the platform separator")
assert_equal("b", fs.join("", "b"), "an empty root keeps the path relative")
assert_equal("a" .. separator .. "b", fs.join("a" .. separator, "b"),
    "a trailing separator must not be doubled")

-- --------------------------------------------------------------------- access

assert_true(fs.available(), "io.open must be available in the test host")
assert_true(fs.exists("tests/save_test_support.lua"), "an existing file must be reported")
assert_true(not fs.exists("tests/does_not_exist.lua"), "a missing file must not be reported")

local data = fs.read("files/config.lua")
assert_true(type(data) == "string" and #data > 1000, "a file must be readable")

-- The sample save is the real binary format of the game.
assert_true(fs.exists(sample .. "/world/entities_2.bin"),
    "the sample save must contain entity chunks")

-- -------------------------------------------------------------------- listing

local names = fs.list(sample .. "/world", "files")
assert_true(names ~= nil, "listing the sample world directory must work (backend: " ..
    tostring(fs.backend()) .. ")")
local listing_backend = fs.backend()

local found_entity_chunk = false
for _, name in ipairs(names) do
    if name == "entities_2.bin" then
        found_entity_chunk = true
    end
end
assert_true(found_entity_chunk, "the listing must contain the sample entity chunk")

local directories = fs.list(sample, "dirs")
assert_true(directories ~= nil, "listing directories must work")
local found_world = false
for _, name in ipairs(directories) do
    if name == "world" then
        found_world = true
    end
end
assert_true(found_world, "the save directory must list its world directory")

local paths = fs.list_paths(sample .. "/world", "files")
assert_true(paths ~= nil and #paths == #names, "list_paths must mirror the listing")

-- ------------------------------------------------------------- modification time

local newest, newest_name = fs.newest_time(sample .. "/world", "files", function(name)
    return BossLocatorSaveLocator.is_entity_file(name)
end)
if fs.mtime(sample .. "/world/entities_2.bin") ~= nil then
    assert_true(newest ~= nil, "a platform that reports times must report the newest chunk")
    assert_true(BossLocatorSaveLocator.is_entity_file(newest_name),
        "the newest entry must be an entity chunk, got " .. tostring(newest_name))
else
    -- A platform whose shell cannot report times is allowed to answer nil; the
    -- locator then falls back to slot order.
    assert_true(newest == nil, "without time support newest_time must return nil")
end

-- ------------------------------------------------------------------- roots

local roots = fs.roots()
assert_true(#roots >= 1, "there must be at least one save root")
assert_equal("", roots[1], "the running game's working directory comes first")
for _, root in ipairs(roots) do
    assert_equal("string", type(root), "every root must be a string")
end

-- ------------------------------------------------------- chunk index probing

-- The probe fallback must find the chunks of a real save without a listing.
local probed = BossLocatorSaveLocator.probe_entity_files(sample)
assert_true(#probed > 0, "probing the chunk grid must find chunks in the sample save")
for _, path in ipairs(probed) do
    assert_true(BossLocatorSaveLocator.is_entity_file(path),
        "probed paths must be entity chunks: " .. tostring(path))
    assert_true(fs.exists(path), "probed paths must exist: " .. tostring(path))
end

local files, source = BossLocatorSaveLocator.entity_files(sample)
assert_true(#files > 0, "entity_files must find the sample chunks")
assert_true(source == "listing" or source == "probe", "the source must be reported")

print(string.format(
    "save_fs_test: ok (platform=%s, backend=%s, chunks=%d via %s, probed=%d)",
    platform, tostring(listing_backend), #files, tostring(source), #probed))
