-- The pure Lua bit fallback of files/lua_bit.lua.
--
-- fastlz/fastlz.lua normally gets its bit operations from LuaJIT's "bit"
-- library.  The fallback is what keeps compressed entity chunks readable when
-- that library is unreachable, so it has to agree with the native one and it
-- has to be able to decompress a real fastlz stream.
local support = dofile("tests/save_test_support.lua")
local assert_equal, assert_true = support.assert_equal, support.assert_true

dofile("files/lua_bit.lua")
local fallback = BossLocatorLuaBit.implementation
local fastlz = dofile("fastlz/fastlz.lua")

local MODULO = 4294967296
local function unsigned(value)
    return value % MODULO
end

-- ------------------------------------------------------ agreement with native

local native_ok, native = pcall(require, "bit")
if not native_ok or type(native) ~= "table" then
    native_ok, native = pcall(require, "bit32")
end

if native_ok and type(native) == "table" and type(native.band) == "function" then
    local samples = {
        0, 1, 2, 7, 31, 32, 255, 256, 8191, 8192, 65535, 65536,
        123456, 16777215, 2147483647, 2147483648, 4294967295 - 1,
    }
    for _, left in ipairs(samples) do
        for _, right in ipairs(samples) do
            -- the native library returns signed 32 bit values, so compare the
            -- unsigned representation
            assert_equal(unsigned(native.band(left, right)), unsigned(fallback.band(left, right)),
                "band differs for " .. left .. " and " .. right)
            assert_equal(unsigned(native.bor(left, right)), unsigned(fallback.bor(left, right)),
                "bor differs for " .. left .. " and " .. right)
            assert_equal(unsigned(native.bxor(left, right)), unsigned(fallback.bxor(left, right)),
                "bxor differs for " .. left .. " and " .. right)
        end
        for _, shift in ipairs({ 0, 1, 7, 8, 16, 24, 31 }) do
            assert_equal(unsigned(native.lshift(left, shift)), unsigned(fallback.lshift(left, shift)),
                "lshift differs for " .. left .. " by " .. shift)
            assert_equal(unsigned(native.rshift(left, shift)), unsigned(fallback.rshift(left, shift)),
                "rshift differs for " .. left .. " by " .. shift)
        end
    end
    print("lua_bit_test: compared against the native bit library")
else
    print("lua_bit_test: no native bit library, only checking the results")
end

-- ------------------------------------------------------------- self checks

assert_equal(0, fallback.band(0, 4294967295), "anding with zero")
assert_equal(4294967295, unsigned(fallback.band(4294967295, 4294967295)), "anding with itself")
assert_equal(255, fallback.band(65280 + 255, 255), "masking the low byte")
assert_equal(0, fallback.rshift(4, 3), "shifting everything out")
assert_equal(4294967295, fallback.bnot(0), "not zero")
assert_equal(4294967280, unsigned(fallback.bnot(15)), "not fifteen")

-- ------------------------------------------------- fastlz with the fallback

-- A compressed chunk has to decompress identically through the fallback and
-- through the native library, so build one and round trip it.
local body = support.entity_body({
    {
        name = "$animal_boss_centipede",
        path = "data/entities/animals/boss_centipede/boss_centipede.xml",
        tags = "enemy,mortal,hoss,boss_centipede",
        x = -1234,
        y = 5678,
    },
})
local compressed = fastlz.compress(body)
assert_true(compressed ~= nil, "the compressor must produce a stream")
assert_equal(body, fastlz.decompress(compressed), "the native round trip must work")

-- Force the fallback: package.loaded["bit"] is what fastlz.lua looks up.
local previous = package.loaded["bit"]
package.loaded["bit"] = fallback
local shimmed = dofile("fastlz/fastlz.lua")
package.loaded["bit"] = previous

assert_equal(body, shimmed.decompress(compressed),
    "the pure Lua fallback must decompress the same stream")
assert_equal(compressed, shimmed.compress(body),
    "the pure Lua fallback must compress identically")

print("lua_bit_test: ok")
