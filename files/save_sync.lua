-- Old save compatibility: read the entity chunks of the save the game is
-- currently using, parse them with saves/entity_parser.lua, match the entities
-- against the Boss definitions in files/config.lua and record their positions.
--
-- A save that was played before this mod was enabled contains all the Boss
-- positions this mod needs; this module recovers them instead of waiting for
-- every Boss to come into view again.
--
-- Everything here is read only: saves are never written to.  Reading them
-- requires the file system, which Noita only hands to a mod that asks for it in
-- mod.xml (request_no_api_restrictions="1"), so the capability is checked
-- before anything is touched and reported to the user when it is missing.
--
-- The modules under saves/ are the shared, host independent ones: this file
-- only injects the two host services they document - a directory enumerator
-- and a file reader - and the fastlz decompressor they need for compressed
-- chunks.  The enumerator works on every platform (see files/save_fs.lua) and
-- falls back to probing the chunk name grid, so a save can still be scanned
-- when the platform cannot list a directory at all.

BossLocatorSaveSync = BossLocatorSaveSync or {}

local MOD_ROOT = "mods/boss_locator/"
local MAX_ERRORS = 5
local MAX_MATCHED_NAMES = 6

local runtime = {
    modules = nil,
    module_error = nil,
    injected = nil,
    last_result = nil,
    auto_countdown = nil,
    auto_job = nil,
}

-- ------------------------------------------------------------------ helpers

local function clock()
    if type(os) == "table" and type(os.clock) == "function" then
        return os.clock()
    end
    return 0
end

local function current_frame()
    if type(GameGetFrameNum) == "function" then
        local ok, frame = pcall(GameGetFrameNum)
        if ok and type(frame) == "number" then
            return frame
        end
    end
    return 0
end

local function setting_full_id(id)
    return BossLocatorConfig.MOD_ID .. "." .. id
end

--- Reads a mod setting; returns nil when the setting cannot be read.
function BossLocatorSaveSync.setting_value(id)
    if type(ModSettingGet) ~= "function" then
        return nil
    end
    local ok, value = pcall(ModSettingGet, setting_full_id(id))
    if not ok then
        return nil
    end
    return value
end

function BossLocatorSaveSync.setting_enabled(id, default_value)
    local value = BossLocatorSaveSync.setting_value(id)
    if value == nil then
        return default_value
    end
    return value == true or value == "1" or value == 1
end

local function format_size(bytes)
    if bytes < 1024 then
        return tostring(bytes) .. " B"
    end
    if bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    end
    return string.format("%.2f MB", bytes / (1024 * 1024))
end

-- ------------------------------------------------------------ module loading

local function script_loader()
    if type(dofile_once) == "function" then
        return dofile_once
    end
    if type(dofile) == "function" then
        return dofile
    end
    return nil
end

--- Loads a Lua file that returns a module table.
--
-- dofile_once runs a file only once per Lua context; a build that answers a
-- repeated call without the module table is handled by falling back to dofile,
-- which always returns the file's return value.
local function load_module(path)
    local loader = script_loader()
    if loader == nil then
        return nil, "dofile_once is not available"
    end

    local ok, value, err = pcall(loader, path)
    if not ok then
        return nil, tostring(value)
    end
    if value == nil and loader ~= dofile and type(dofile) == "function" then
        local retry_ok, retry_value, retry_err = pcall(dofile, path)
        if retry_ok and retry_value ~= nil then
            return retry_value
        end
        err = retry_err or err
    end
    if value == nil then
        return nil, tostring(err or (path .. " did not return a module table"))
    end
    return value
end

--- Installs the modules used by a scan (used by the tests to inject stubs).
function BossLocatorSaveSync.inject_modules(scanner, parser, fastlz)
    runtime.injected = { scanner = scanner, parser = parser, fastlz = fastlz }
    runtime.modules = nil
    runtime.module_error = nil
    return runtime.injected
end

function BossLocatorSaveSync.load_modules()
    if runtime.injected ~= nil then
        return runtime.injected, nil
    end
    if runtime.modules ~= nil then
        return runtime.modules, nil
    end
    if runtime.module_error ~= nil then
        return nil, runtime.module_error
    end

    local bit_ok, bit_source = BossLocatorLuaBit.ensure()
    if not bit_ok then
        runtime.module_error = "fastlz 解压所需的位运算库不可用：" .. tostring(bit_source)
        return nil, runtime.module_error
    end

    local scanner, scanner_error = load_module(MOD_ROOT .. "saves/save_scanner.lua")
    if scanner == nil then
        runtime.module_error = "无法加载 saves/save_scanner.lua：" .. tostring(scanner_error)
        return nil, runtime.module_error
    end

    local parser, parser_error = load_module(MOD_ROOT .. "saves/entity_parser.lua")
    if parser == nil then
        runtime.module_error = "无法加载 saves/entity_parser.lua：" .. tostring(parser_error)
        return nil, runtime.module_error
    end

    local fastlz, fastlz_error = load_module(MOD_ROOT .. "fastlz/fastlz.lua")
    if fastlz == nil then
        runtime.module_error = "无法加载 fastlz/fastlz.lua：" .. tostring(fastlz_error)
        return nil, runtime.module_error
    end

    runtime.modules = {
        scanner = scanner,
        parser = parser,
        fastlz = fastlz,
        bit_source = bit_source,
    }
    return runtime.modules, nil
end

-- -------------------------------------------------------- game provided data

--- The slot the game itself reports, when the build exposes one.
--
-- The WorldStateComponent keeps the per run statistic file below the active
-- save slot, and the engine also accepts a slot on the command line; both are
-- read here defensively because an older build may not provide either.
function BossLocatorSaveSync.game_slot_hint()
    local values = {}

    if type(GameGetWorldStateEntity) == "function" and type(ComponentGetValue2) == "function" then
        local ok, entity = pcall(GameGetWorldStateEntity)
        if ok and type(entity) == "number" and entity ~= 0 then
            local ok_value, value = pcall(ComponentGetValue2, entity, "session_stat_file")
            if ok_value and type(value) == "string" then
                values[#values + 1] = value
            end
        end
    end

    if type(SessionNumbersGetValue) == "function" then
        local ok, value = pcall(SessionNumbersGetValue, "SAVE_SLOT")
        if ok and type(value) == "string" then
            values[#values + 1] = value
        end
    end
    if type(GlobalsGetValue) == "function" then
        local ok, value = pcall(GlobalsGetValue, "SAVE_SLOT", "")
        if ok and type(value) == "string" then
            values[#values + 1] = value
        end
    end

    for _, value in ipairs(values) do
        local slot = BossLocatorSaveLocator.normalize_slot(value)
        if slot ~= nil then
            return slot
        end
        -- A bare number is the slot index the engine names save00 - save06.
        local digits = tostring(value):match("^%s*(%d+)%s*$")
        if digits ~= nil and #digits <= 2 then
            return string.format("save%02d", tonumber(digits))
        end
    end
    return nil
end

--- True when a run is loaded.  The mod settings screen reports whether it was
--- opened from the main menu; the frame counter is used as a second opinion.
function BossLocatorSaveSync.is_in_game(in_main_menu)
    if in_main_menu == true then
        return false
    end
    if in_main_menu == false then
        return true
    end
    return current_frame() > 0
end

-- ------------------------------------------------------- save slot discovery

local location_cache = { at = nil, value = nil }

local function wall_clock()
    if type(os) == "table" and type(os.time) == "function" then
        local ok, value = pcall(os.time)
        if ok and type(value) == "number" then
            return value
        end
    end
    return nil
end

--- Resolves the save directory to scan.  Called by the settings screen on every
--- frame it is open, so the result is reused for a few seconds; the scan itself
--- always resolves again.
function BossLocatorSaveSync.peek_location(max_age)
    local now = wall_clock()
    local age = max_age or 5
    if location_cache.value ~= nil and location_cache.at ~= nil and now ~= nil and
        now - location_cache.at < age then
        return location_cache.value
    end

    local override = BossLocatorSaveSync.setting_value(BossLocatorConfig.SETTING_SLOT_OVERRIDE)
    local value = BossLocatorSaveLocator.resolve({
        slot = override,
        hint = BossLocatorSaveSync.game_slot_hint(),
    })
    location_cache.at = now
    location_cache.value = value
    return value
end

--- What the settings screen needs to know before offering the scan.
-- Returns { can_scan, stage, hint }.
function BossLocatorSaveSync.capability(in_main_menu)
    local file_ok, file_reason = BossLocatorSaveFs.available()
    if not file_ok then
        return {
            can_scan = false,
            stage = "unsafe_api",
            hint = "需要不安全模式：mod.xml 中的 request_no_api_restrictions 必须为 \"1\"，" ..
                "并在改动后重启游戏（" .. tostring(file_reason) .. "）",
        }
    end
    if not BossLocatorSaveSync.is_in_game(in_main_menu) then
        return {
            can_scan = false,
            stage = "in_game",
            hint = "需要先进入游戏（载入一个存档）才能扫描存档",
        }
    end
    return {
        can_scan = true,
        stage = "ready",
        hint = "扫描当前存档的实体区块，把每个 Boss 的位置写入本存档记录",
    }
end

-- ------------------------------------------------------------------ scanning

local function same_directory(left, right)
    local function normalize(path)
        local text = tostring(path or ""):gsub("[/\\]+", "/"):gsub("/+$", "")
        if BossLocatorSaveFs.platform() == "windows" then
            return string.lower(text)
        end
        return text
    end
    return normalize(left) == normalize(right)
end

--- Directory enumerator injected into saves/save_scanner.lua.
local function make_enumerator(location)
    return function(directory)
        if location ~= nil and same_directory(directory, location.world) then
            -- Already resolved (a listing, or the probe fallback), so the scan
            -- works even where directories cannot be listed.
            return location.files
        end
        local paths = BossLocatorSaveFs.list_paths(directory, "files")
        return paths or {}
    end
end

local function distance_squared(reference, x, y)
    if reference == nil or reference.x == nil or reference.y == nil then
        return nil
    end
    local dx = x - reference.x
    local dy = y - reference.y
    return dx * dx + dy * dy
end

--- Matches one parsed entity record against the Boss definitions.
local function match_record(record)
    for _, config in ipairs(BossLocatorConfig.BOSSES) do
        if BossLocatorConfig.matches_saved_revival_orb(config, record) then
            return config, "revival_orb"
        end
        if BossLocatorConfig.matches_saved_entity(config, record) then
            return config, "boss"
        end
    end
    return nil, nil
end

local function aggregate_match(aggregated, config, role, record, world_index, player)
    local key = config.id .. "@" .. tostring(world_index)
    local entry = aggregated[key]
    local distance = distance_squared(player, record.x, record.y)

    if entry == nil then
        aggregated[key] = {
            config = config,
            role = role,
            world_index = world_index,
            x = record.x,
            y = record.y,
            distance = distance,
            count = 1,
        }
        return
    end

    entry.count = entry.count + 1

    -- A living Boss wins over its death orb, and among equal roles the instance
    -- closest to the player is the one a marker should point at.
    local preferred = false
    if entry.role == "revival_orb" and role == "boss" then
        preferred = true
    elseif entry.role == role and distance ~= nil and
        (entry.distance == nil or distance < entry.distance) then
        preferred = true
    end
    if preferred then
        entry.role = role
        entry.x = record.x
        entry.y = record.y
        entry.distance = distance
    end
end

--- Result table for the states that keep the scan from starting at all.
local function failure_result(stage, hint, location)
    return {
        ok = false,
        stage = stage,
        location = location,
        hint = hint,
        short = hint,
        message = hint,
    }
end

-- A large save can hold thousands of chunks, so a scan is split into slices: the
-- settings screen and the runtime each process a bounded amount of work per
-- frame instead of freezing the game for the whole scan.
local SCAN_STEP_BYTES = 96 * 1024
local SCAN_STEP_FILES = 12

--- Prepares a scan without reading anything yet.
--
-- options.in_main_menu : forwarded from the settings screen
-- options.slot         : explicit slot override (defaults to the setting)
-- options.reason       : "manual" (default) or "auto"; only used for reporting
--
-- Returns a job for step_scan(), or nil plus a result table explaining why the
-- scan cannot run.
function BossLocatorSaveSync.begin_scan(options)
    options = options or {}

    local ability = BossLocatorSaveSync.capability(options.in_main_menu)
    if not ability.can_scan then
        local result = failure_result(ability.stage, ability.hint)
        runtime.last_result = result
        return nil, result
    end

    local override = options.slot
    if override == nil then
        override = BossLocatorSaveSync.setting_value(BossLocatorConfig.SETTING_SLOT_OVERRIDE)
    end
    local hint = BossLocatorSaveSync.game_slot_hint()
    local location = BossLocatorSaveLocator.resolve({ slot = override, hint = hint })
    location_cache.value = location
    location_cache.at = wall_clock()

    if not location.ok then
        local result = failure_result("no_save",
            "没有找到包含实体区块的存档目录：" .. tostring(location.message), location)
        result.short = "没有找到可扫描的存档"
        runtime.last_result = result
        return nil, result
    end

    local modules, module_error = BossLocatorSaveSync.load_modules()
    if modules == nil then
        local result = failure_result("modules", tostring(module_error), location)
        result.short = "扫描模块加载失败"
        runtime.last_result = result
        return nil, result
    end

    local scanner = modules.scanner
    local parser = modules.parser
    local fastlz = modules.fastlz
    scanner.enumerate = make_enumerator(location)

    local player = BossLocatorWorld.current()
    if player ~= nil and player.x == 0 and player.y == 0 then
        -- Without a usable player position the closest instance cannot be
        -- chosen; the first one observed is kept instead.
        player = nil
    end

    local job = {
        options = options,
        location = location,
        modules = modules,
        files = location.files,
        index = 0,
        started = clock(),
        finished = false,
        result = nil,
        player = player,
        aggregated = {},
        stats = {
            files = 0,
            bytes = 0,
            read_failed = 0,
            parse_failed = 0,
            unvalidated = 0,
            records = 0,
            entities = 0,
            matches = 0,
            errors = {},
        },
    }

    job.collector = function(path, save_id, file_index, data)
        local stats = job.stats
        stats.files = stats.files + 1
        if data == nil then
            stats.read_failed = stats.read_failed + 1
            return true
        end
        stats.bytes = stats.bytes + #data

        local ok, parsed = pcall(parser.parse, data, fastlz)
        if not ok or parsed == nil then
            stats.parse_failed = stats.parse_failed + 1
            if not ok and #stats.errors < MAX_ERRORS then
                stats.errors[#stats.errors + 1] = string.format("%s: %s",
                    tostring(path:match("[^/\\]+$")), tostring(parsed))
            end
            return true
        end
        if parsed.structureValid ~= true then
            stats.unvalidated = stats.unvalidated + 1
        end

        stats.entities = stats.entities + (tonumber(parsed.entityCount) or 0)
        local records = parser.flatten(parsed.entities or {})
        for _, record in ipairs(records) do
            stats.records = stats.records + 1
            if type(record.x) == "number" and type(record.y) == "number" then
                local config, role = match_record(record)
                if config ~= nil then
                    stats.matches = stats.matches + 1
                    local world_index = BossLocatorWorld.index_for_position(record.x, record.y)
                    aggregate_match(job.aggregated, config, role, record, world_index, job.player)
                end
            end
        end
        return true
    end

    return job, nil
end

--- Writes the collected positions into the state and builds the result table.
local function finish_job(job)
    local stats = job.stats
    local frame = current_frame()
    local updated, unchanged, skipped = 0, 0, 0
    local matched_names = {}
    local matched_count = 0

    for _, entry in pairs(job.aggregated) do
        matched_count = matched_count + 1
        if #matched_names < MAX_MATCHED_NAMES then
            matched_names[#matched_names + 1] = entry.config.display_name
        end
        local _, changed, dead = BossLocatorState.sync_saved_position(
            entry.config, entry.world_index, entry.x, entry.y, frame, entry.role)
        if dead then
            skipped = skipped + 1
        elseif changed then
            updated = updated + 1
        else
            unchanged = unchanged + 1
        end
    end

    local result = {
        ok = true,
        stage = "done",
        reason = job.options.reason or "manual",
        location = job.location,
        slot = job.location.slot,
        root = job.location.root,
        files = stats.files,
        bytes = stats.bytes,
        read_failed = stats.read_failed,
        parse_failed = stats.parse_failed,
        unvalidated = stats.unvalidated,
        records = stats.records,
        entities = stats.entities,
        matches = stats.matches,
        matched_bosses = matched_count,
        matched_names = matched_names,
        updated = updated,
        unchanged = unchanged,
        skipped = skipped,
        seconds = clock() - job.started,
        errors = stats.errors,
        bit_source = job.modules.bit_source,
    }

    result.short = BossLocatorSaveSync.summary_text(result)
    result.message = BossLocatorSaveSync.detail_text(result)
    return result
end

--- Processes the next slice of a scan job.
--
-- budgets.max_files / budgets.max_bytes bound the work of this call; both
-- default to one slice.  Returns
--   { running, done, total, result }   (result is set once the job finished).
function BossLocatorSaveSync.step_scan(job, budgets)
    if job == nil then
        return { running = false, done = 0, total = 0, result = nil }
    end
    if job.finished then
        return { running = false, done = job.index, total = #job.files, result = job.result }
    end

    budgets = budgets or {}
    local max_files = budgets.max_files or SCAN_STEP_FILES
    local max_bytes = budgets.max_bytes or SCAN_STEP_BYTES
    local scanner = job.modules.scanner
    local processed, bytes = 0, 0

    while job.index < #job.files and processed < max_files and bytes < max_bytes do
        job.index = job.index + 1
        local before = job.stats.bytes
        local _, _, summary = scanner.scan(job.location.dir, job.collector, {
            files = { job.files[job.index] },
            read = BossLocatorSaveFs.read,
        })
        bytes = bytes + (job.stats.bytes - before)
        processed = processed + 1
        if summary ~= nil then
            for _, failure in ipairs(summary.errors or {}) do
                job.stats.read_failed = job.stats.read_failed + 1
                if #job.stats.errors < MAX_ERRORS then
                    job.stats.errors[#job.stats.errors + 1] = tostring(failure.path) .. ": " ..
                        tostring(failure.message)
                end
            end
        end
    end

    if job.index >= #job.files then
        job.result = finish_job(job)
        job.finished = true
        runtime.last_result = job.result
    end

    return {
        running = not job.finished,
        done = job.index,
        total = #job.files,
        result = job.result,
    }
end

--- Runs a scan to completion in one call; see summary_text()/detail_text() for
--- the result.  The settings screen and the runtime use begin_scan/step_scan so
--- that a scan of a large save is spread over several frames.
function BossLocatorSaveSync.scan(options)
    local job, failure = BossLocatorSaveSync.begin_scan(options)
    if job == nil then
        return failure
    end
    local progress
    repeat
        progress = BossLocatorSaveSync.step_scan(job, {
            max_files = math.huge,
            max_bytes = math.huge,
        })
    until progress.running ~= true
    return progress.result
end

local function sorted_names(names)
    local copy = {}
    for _, name in ipairs(names) do
        copy[#copy + 1] = name
    end
    table.sort(copy)
    return copy
end

--- Progress line shown while a scan is spread over several frames.
function BossLocatorSaveSync.progress_text(done, total)
    return string.format("扫描中 %d/%d 个区块", tonumber(done) or 0, tonumber(total) or 0)
end

--- One line summary, used on the settings screen.
function BossLocatorSaveSync.summary_text(result)
    if result == nil then
        return "尚未扫描"
    end
    if result.ok ~= true then
        return tostring(result.short or result.message or "扫描未执行")
    end
    local text = string.format("%s：区块 %d，更新 %d 个 Boss 位置",
        tostring(result.slot), result.files, result.updated)
    if result.skipped > 0 then
        text = text .. string.format("，跳过已死亡 %d", result.skipped)
    end
    if result.parse_failed > 0 or result.read_failed > 0 then
        text = text .. string.format("，失败 %d", result.parse_failed + result.read_failed)
    end
    return text
end

--- Multi line description, used for logs and tooltips.
function BossLocatorSaveSync.detail_text(result)
    if result == nil then
        return "尚未扫描"
    end
    if result.ok ~= true then
        return tostring(result.message or result.hint or "扫描未执行")
    end

    local lines = {}
    lines[#lines + 1] = string.format("存档：%s", BossLocatorSaveLocator.describe(result.location))
    lines[#lines + 1] = string.format(
        "区块 %d（%s），实体 %d，匹配记录 %d，命中 Boss %d，更新 %d，未变 %d，跳过已死亡 %d",
        result.files, format_size(result.bytes), result.entities, result.matches,
        result.matched_bosses, result.updated, result.unchanged, result.skipped)
    if result.parse_failed > 0 or result.read_failed > 0 or result.unvalidated > 0 then
        lines[#lines + 1] = string.format("解析失败 %d，读取失败 %d，结构未校验 %d",
            result.parse_failed, result.read_failed, result.unvalidated)
    end
    if #result.matched_names > 0 then
        lines[#lines + 1] = "包含：" .. table.concat(sorted_names(result.matched_names), "、")
    end
    if #result.errors > 0 then
        lines[#lines + 1] = "错误：" .. table.concat(result.errors, "；")
    end
    lines[#lines + 1] = string.format("耗时 %.2f 秒（位于存档 %s）",
        result.seconds, result.slot)
    return table.concat(lines, "\n")
end

function BossLocatorSaveSync.last_result()
    return runtime.last_result
end

-- ------------------------------------------------------------------ printing

--- Shows a scan result in game.  'important' raises a full notification, which
--- suits a scan the player asked for; the automatic scan only logs.
function BossLocatorSaveSync.announce(result, important)
    if result == nil then
        return
    end
    local text = tostring(result.message or result.short or "")
    if type(GamePrintImportant) == "function" and important then
        local ok = pcall(GamePrintImportant, "Boss Locator: 存档同步", text)
        if ok then
            return
        end
    end
    if type(GamePrint) == "function" then
        pcall(GamePrint, "Boss Locator: " .. text:gsub("\n", " | "))
    end
end

-- --------------------------------------------------------------- auto syncing

local AUTO_SYNC_DELAY = 120 -- frames after a world was initialized

--- Arms the optional automatic scan that runs once per world.
function BossLocatorSaveSync.on_world_initialized()
    runtime.auto_job = nil
    if BossLocatorSaveSync.setting_enabled(BossLocatorConfig.SETTING_SCAN_ON_LOAD, false) then
        runtime.auto_countdown = AUTO_SYNC_DELAY
    else
        runtime.auto_countdown = nil
    end
end

--- Called once per frame from the runtime; performs the armed automatic scan a
--- slice at a time, so that loading a world is never blocked by it.
function BossLocatorSaveSync.tick()
    if runtime.auto_job ~= nil then
        local progress = BossLocatorSaveSync.step_scan(runtime.auto_job)
        if progress.running ~= true then
            runtime.auto_job = nil
            BossLocatorSaveSync.announce(progress.result, false)
        end
        return
    end

    if runtime.auto_countdown == nil then
        return
    end
    runtime.auto_countdown = runtime.auto_countdown - 1
    if runtime.auto_countdown > 0 then
        return
    end
    runtime.auto_countdown = nil

    local job, failure = BossLocatorSaveSync.begin_scan({
        reason = "auto",
        in_main_menu = false,
    })
    if job == nil then
        BossLocatorSaveSync.announce(failure, false)
        return
    end
    runtime.auto_job = job
end
