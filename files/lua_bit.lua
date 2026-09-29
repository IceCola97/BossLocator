-- A small pure Lua implementation of the bit operations the vendored fastlz
-- module needs.
--
-- fastlz/fastlz.lua loads its bit operations with require("bit") (LuaJIT) or
-- require("bit32") (Lua 5.2+).  Noita runs on LuaJIT, so the native library is
-- normally present and is used as is; this file only becomes active when
-- neither is reachable, which keeps the save scanner working in a Lua state
-- that has no package loader at all.  The operations therefore have to be
-- installed where fastlz.lua looks for them (package.loaded), and - if there is
-- no require - a minimal require has to exist as well.
--
-- Values are treated as unsigned 32 bit numbers, which matches every use in
-- fastlz.lua (masks, shifts, offsets).

BossLocatorLuaBit = BossLocatorLuaBit or {}

local floor = math.floor
local UINT32 = 4294967296

local function normalize(value)
    local number = tonumber(value) or 0
    number = floor(number) % UINT32
    if number < 0 then
        number = number + UINT32
    end
    return number
end

local function bitwise(left, right, mode)
    local a = normalize(left)
    local b = normalize(right)
    local result = 0
    local place = 1
    for _ = 1, 32 do
        local abit = a % 2
        local bbit = b % 2
        local keep
        if mode == "and" then
            keep = abit == 1 and bbit == 1
        elseif mode == "or" then
            keep = abit == 1 or bbit == 1
        else
            keep = abit ~= bbit
        end
        if keep then
            result = result + place
        end
        a = floor(a / 2)
        b = floor(b / 2)
        place = place * 2
    end
    return result
end

local shim = {}

function shim.band(a, b)
    if normalize(a) == 0 or normalize(b) == 0 then
        return 0
    end
    return bitwise(a, b, "and")
end

function shim.bor(a, b)
    return bitwise(a, b, "or")
end

function shim.bxor(a, b)
    return bitwise(a, b, "xor")
end

function shim.bnot(a)
    return UINT32 - 1 - normalize(a)
end

function shim.lshift(a, n)
    local value = normalize(a)
    local count = floor(tonumber(n) or 0)
    if count <= 0 then
        return count == 0 and value or BossLocatorLuaBit.rshift(value, -count)
    end
    for _ = 1, count do
        value = normalize(value * 2)
    end
    return value
end

function shim.rshift(a, n)
    local value = normalize(a)
    local count = floor(tonumber(n) or 0)
    if count <= 0 then
        return count == 0 and value or BossLocatorLuaBit.lshift(value, -count)
    end
    if count >= 32 then
        return 0
    end
    return floor(value / 2 ^ count)
end

function shim.arshift(a, n)
    local value = normalize(a)
    local count = floor(tonumber(n) or 0)
    if count <= 0 then
        return count == 0 and value or shim.lshift(value, -count)
    end
    if value >= 2147483648 then
        -- negative as a signed 32 bit number: fill with ones
        return shim.bor(shim.rshift(value, count), shim.lshift(shim.bnot(0), 32 - count))
    end
    return shim.rshift(value, count)
end

function shim.tobit(a)
    local value = normalize(a)
    if value >= 2147483648 then
        return value - UINT32
    end
    return value
end

function shim.tohex(a, digits)
    local value = normalize(a)
    if digits == nil then
        return string.format("%08x", value)
    end
    return string.format("%0" .. tostring(floor(digits)) .. "x", value)
end

local function is_bit_library(value)
    return type(value) == "table" and type(value.band) == "function" and
        type(value.bor) == "function" and type(value.bxor) == "function" and
        type(value.lshift) == "function" and type(value.rshift) == "function"
end

--- Makes sure fastlz.lua can load its bit operations.  Returns true plus the
--- name of the source that is used, or false plus a reason.
function BossLocatorLuaBit.ensure()
    local require_function = nil
    if type(require) == "function" then
        require_function = require
    end

    if require_function ~= nil then
        local ok, library = pcall(require_function, "bit")
        if ok and is_bit_library(library) then
            return true, "LuaJIT bit"
        end
        local ok32, library32 = pcall(require_function, "bit32")
        if ok32 and is_bit_library(library32) then
            return true, "bit32"
        end
    end

    if type(package) ~= "table" then
        -- No package loader: fastlz.lua's require("bit") can only be answered
        -- by a require of our own.
        if require_function == nil then
            _G.require = function(name)
                if name == "bit" or name == "bit32" then
                    return shim
                end
                error("module '" .. tostring(name) .. "' is not available", 2)
            end
            return true, "pure Lua fallback"
        end
        return false, "the package table is not available"
    end

    if type(package.loaded) ~= "table" then
        package.loaded = {}
    end
    if not is_bit_library(package.loaded["bit"]) then
        package.loaded["bit"] = shim
    end
    if not is_bit_library(package.loaded["bit32"]) then
        package.loaded["bit32"] = shim
    end
    if require_function == nil then
        _G.require = function(name)
            local loaded = package.loaded[name]
            if loaded ~= nil then
                return loaded
            end
            error("module '" .. tostring(name) .. "' is not available", 2)
        end
    end
    return true, "pure Lua fallback"
end

BossLocatorLuaBit.implementation = shim
BossLocatorLuaBit.is_bit_library = is_bit_library
