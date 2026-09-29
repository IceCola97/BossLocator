-- Shared helpers for the save scanner tests.
--
-- The tests run under the same Lua 5.1 / LuaJIT runtime the game uses
-- (tests/Lua51Runner.cs loads Noita's lua51.dll), but they exercise the save
-- scanner without a game and without touching a real save:
--
--   * the game API is stubbed exactly like tests/state_test.lua does it,
--   * the file system below files/save_fs.lua is replaced by an in memory tree,
--     so the discovery logic can be tested with several roots and slots, and
--   * entity chunks are written in the real binary format (big endian body,
--     little endian size header, fastlz compression) by the helpers below, so
--     saves/save_scanner.lua and saves/entity_parser.lua see real input.
--
-- Files of the repository itself are used read only for the cases that need
-- real data (saves/NoitaSaveTest/sample_save/save00).

local M = {}

local floor = math.floor

-- ------------------------------------------------------------ binary writing

function M.le_u32(value)
    local number = floor(tonumber(value) or 0)
    return string.char(number % 256, floor(number / 256) % 256,
        floor(number / 65536) % 256, floor(number / 16777216) % 256)
end

function M.be_u32(value)
    local number = floor(tonumber(value) or 0)
    return string.char(floor(number / 16777216) % 256, floor(number / 65536) % 256,
        floor(number / 256) % 256, number % 256)
end

--- Big endian IEEE 754 single precision, matching entity_parser.read_f32.
function M.be_f32(value)
    local number = tonumber(value) or 0
    if number == 0 then
        return string.char(0, 0, 0, 0)
    end
    local sign = 0
    if number < 0 then
        sign = 128
        number = -number
    end
    local mantissa, exponent = math.frexp(number)
    local exponent_field = exponent - 1 + 127
    local fraction = floor((mantissa * 2 - 1) * 8388608 + 0.5)
    if fraction >= 8388608 then
        fraction = 0
        exponent_field = exponent_field + 1
    end
    return string.char(sign + floor(exponent_field / 2),
        (exponent_field % 2) * 128 + floor(fraction / 65536),
        floor(fraction / 256) % 256, fraction % 256)
end

function M.be_str(text)
    local value = tostring(text or "")
    return M.be_u32(#value) .. value
end

-- --------------------------------------------------------- entity chunk files

local function record_bytes(record)
    local parts = {}
    parts[#parts + 1] = M.be_str(record.name or "unknown")
    parts[#parts + 1] = string.char(0) -- version
    parts[#parts + 1] = M.be_str(record.path or "data/entities/misc/unknown.xml")
    parts[#parts + 1] = M.be_str(record.tags or "")
    parts[#parts + 1] = M.be_f32(record.x or 0) .. M.be_f32(record.y or 0)
    parts[#parts + 1] = M.be_f32(record.scaleX or 1) .. M.be_f32(record.scaleY or 1) ..
        M.be_f32(record.rotation or 0)
    parts[#parts + 1] = M.be_u32(record.componentCount or 1)
    parts[#parts + 1] = M.be_str(record.component or "SpriteComponent")
    -- component payload: never decoded, only skipped, and it must not look
    -- like another record head
    parts[#parts + 1] = "\1\2\3\4\5\6\7\8"
    parts[#parts + 1] = M.be_u32(#(record.children or {}))
    for _, child in ipairs(record.children or {}) do
        parts[#parts + 1] = record_bytes(child)
    end
    return table.concat(parts)
end

--- Body of an entities_*.bin file: u32 flags, schema hash, root count, records.
function M.entity_body(records)
    local parts = {
        M.be_u32(0),
        M.be_str("test_schema"),
        M.be_u32(#records),
    }
    for _, record in ipairs(records) do
        parts[#parts + 1] = record_bytes(record)
    end
    return table.concat(parts)
end

--- Complete file bytes.  'fastlz' is the module under fastlz/fastlz.lua;
--- compressed = false writes a stored (uncompressed) block instead.
function M.chunk_file(body, fastlz, compressed)
    if compressed == false then
        return M.le_u32(#body) .. M.le_u32(#body) .. body
    end
    local packed = fastlz.compress(body)
    if packed == nil then
        error("the fastlz compressor returned nil")
    end
    local payload = packed:sub(5) -- drop the module's own big endian length header
    return M.le_u32(#payload) .. M.le_u32(#body) .. payload
end

-- ---------------------------------------------------------------- virtual fs

local function normalize(path)
    local text = tostring(path or ""):gsub("\\", "/")
    text = text:gsub("^%./", "")
    text = text:gsub("/+", "/")
    if #text > 1 then
        text = text:gsub("/+$", "")
    end
    return text
end

M.normalize = normalize

local function parent_of(path)
    return normalize(path):match("^(.*)/[^/]*$") or ""
end

local function base_of(path)
    return normalize(path):match("([^/]*)$") or ""
end

--- Builds an in memory file system.
-- files : { ["save00/world/entities_2.bin"] = "<bytes>", ... }
-- times : { ["save00/world/entities_2.bin"] = 1700000000, ... } (optional)
-- Returns a table with the tree plus helpers used by the stubs.
function M.virtual_fs(files, times)
    local tree = {
        files = {},
        times = times or {},
        directories = {},
    }

    for path, data in pairs(files) do
        local key = normalize(path)
        tree.files[key] = data
        local directory = parent_of(key)
        while directory ~= "" do
            tree.directories[directory] = true
            directory = parent_of(directory)
        end
        tree.directories[""] = true
    end

    local normalized_times = {}
    for path, value in pairs(tree.times) do
        normalized_times[normalize(path)] = value
    end
    tree.times = normalized_times

    return tree
end

local function entries_of(tree, directory, kind)
    local target = normalize(directory)
    local prefix = target == "" and "" or (target .. "/")
    local seen = {}
    local entries = {}

    for key in pairs(tree.files) do
        if prefix == "" or key:sub(1, #prefix) == prefix then
            local rest = key:sub(#prefix + 1)
            local name = rest:match("^([^/]+)")
            if name ~= nil and not seen[name] then
                seen[name] = true
                local is_directory = rest:find("/", 1, true) ~= nil
                if kind == nil or (kind == "dirs") == is_directory then
                    entries[#entries + 1] = {
                        name = name,
                        mtime = is_directory and nil or tree.times[key],
                        directory = is_directory,
                    }
                end
            end
        end
    end

    table.sort(entries, function(left, right)
        return left.name < right.name
    end)
    return entries
end

--- Replaces the file system below BossLocatorSaveFs with the given tree.
-- Returns a function that restores the original implementation.
function M.install_virtual_fs(tree, roots)
    local fs = BossLocatorSaveFs
    local saved = {
        entries = fs.entries,
        list = fs.list,
        list_paths = fs.list_paths,
        exists = fs.exists,
        read = fs.read,
        newest_time = fs.newest_time,
        mtime = fs.mtime,
        roots = fs.roots,
        platform = fs.platform,
    }

    fs.entries = function(directory, kind)
        return entries_of(tree, directory, kind), nil
    end

    fs.list = function(directory, kind)
        local entries = entries_of(tree, directory, kind)
        local names = {}
        for _, entry in ipairs(entries) do
            names[#names + 1] = entry.name
        end
        return names, nil
    end

    fs.list_paths = function(directory, kind)
        local names = select(1, fs.list(directory, kind)) or {}
        local paths = {}
        for _, name in ipairs(names) do
            paths[#paths + 1] = fs.join(directory, name)
        end
        return paths, nil
    end

    fs.exists = function(path)
        return tree.files[normalize(path)] ~= nil
    end

    fs.read = function(path)
        local data = tree.files[normalize(path)]
        if data == nil then
            return nil, "cannot open " .. tostring(path)
        end
        return data
    end

    fs.mtime = function(path)
        return tree.times[normalize(path)]
    end

    fs.newest_time = function(directory, kind, accept)
        local entries = entries_of(tree, directory, kind)
        local prefix = normalize(directory)
        prefix = prefix == "" and "" or (prefix .. "/")
        local newest, newest_name = nil, nil
        for _, entry in ipairs(entries) do
            local mtime = entry.mtime
            if mtime == nil and not entry.directory then
                mtime = tree.times[prefix .. entry.name]
            end
            if mtime ~= nil and (accept == nil or accept(entry.name)) then
                if newest == nil or mtime > newest then
                    newest = mtime
                    newest_name = entry.name
                end
            end
        end
        return newest, newest_name
    end

    fs.roots = function()
        return roots or { "" }
    end

    fs.platform = function()
        return "windows"
    end

    return function()
        for name, value in pairs(saved) do
            fs[name] = value
        end
    end
end

-- ------------------------------------------------------------- module loading

--- Loads the runtime modules in dependency order (dofile, so that the tests do
--- not depend on the game's dofile_once extension).
function M.load_runtime_modules()
    dofile("files/config.lua")
    dofile("files/lua_bit.lua")
    dofile("files/save_fs.lua")
    dofile("files/save_locator.lua")
    dofile("files/world.lua")
    dofile("files/state.lua")
    dofile("files/save_sync.lua")
    return BossLocatorSaveSync
end

--- Loads the shared scanner modules the way the game does, and injects them.
function M.install_scanner_modules()
    local scanner = dofile("saves/save_scanner.lua")
    local parser = dofile("saves/entity_parser.lua")
    local fastlz = dofile("fastlz/fastlz.lua")
    BossLocatorSaveSync.inject_modules(scanner, parser, fastlz)
    return scanner, parser, fastlz
end

--- The game API stubs the runtime expects, with a write through Globals store.
function M.install_game_stubs(state)
    state.globals = state.globals or {}
    state.settings = state.settings or {}
    state.flags = state.flags or {}
    state.in_main_menu = state.in_main_menu
    state.frame = state.frame or 100

    GlobalsGetValue = function(key, default_value)
        local value = state.globals[key]
        if value == nil then
            return default_value
        end
        return value
    end
    GlobalsSetValue = function(key, value)
        state.globals[key] = tostring(value)
    end
    SessionNumbersGetValue = function(key)
        if key == "NEW_GAME_PLUS_COUNT" then
            return "0"
        end
        return state.session_numbers and state.session_numbers[key] or "0"
    end
    EntityHasTag = function()
        return false
    end
    GameGetFrameNum = function()
        return state.frame
    end
    ModSettingGet = function(id)
        return state.settings[id]
    end
    ModSettingSet = function(id, value)
        state.settings[id] = value
    end
    GamePrint = function(text)
        state.printed = (state.printed or "") .. tostring(text) .. "\n"
    end
    GamePrintImportant = function(title, text)
        state.printed = (state.printed or "") .. tostring(title) .. ": " .. tostring(text) .. "\n"
    end
    GetParallelWorldPosition = function(x)
        -- the engine's own mapping, approximated the way the mod falls back to
        -- it: the world repeats every BossLocatorConfig.NORMAL_WORLD_WIDTH
        local width = (BossLocatorConfig and BossLocatorConfig.NORMAL_WORLD_WIDTH) or 35840
        return math.floor((tonumber(x) or 0) / width + 0.5)
    end
    return state
end

function M.assert_equal(expected, actual, message)
    if expected ~= actual then
        error((message or "values differ") .. ": expected " .. tostring(expected) ..
            ", got " .. tostring(actual))
    end
end

function M.assert_true(value, message)
    if not value then
        error(message or "expected a true value")
    end
end

return M
