-- Boss Locator configuration.
--
-- The game data uses entity filenames rather than a single, reliable "boss"
-- tag for every boss.  Keep the matchers here so they can be adjusted when a
-- game update or another mod changes an entity filename.

BossLocatorConfig = BossLocatorConfig or {}

BossLocatorConfig.MOD_ID = "boss_locator"
BossLocatorConfig.NORMAL_WORLD_WIDTH = 35840
BossLocatorConfig.NG_PLUS_WORLD_WIDTH = 32768
BossLocatorConfig.SCAN_IDS_PER_FRAME = 2000
BossLocatorConfig.POSITION_SAVE_INTERVAL = 15

-- Settings owned by the save scanner (see settings.lua).
BossLocatorConfig.SETTING_SCAN_SAVE = "scan_save_positions"
BossLocatorConfig.SETTING_SLOT_OVERRIDE = "save_slot_override"
BossLocatorConfig.SETTING_SCAN_ON_LOAD = "save_scan_on_load"

-- The engine names its save directories save00 - save06 (the range the
-- "Save Slots Enabler" game mode exposes).  Only used to build the manual
-- override list - the scanner itself discovers the slots that exist.
BossLocatorConfig.SAVE_SLOT_COUNT = 7

-- world_policy values:
--   main     the entity is generated only in the main world
--   parallel the entity is generated only in parallel worlds
--   all      the entity can be generated in every world
--
-- default_position is optional.  Coordinates are main-world coordinates and
-- are shifted by the world offset for "all"/"parallel" entries.  Leaving it
-- nil is deliberate: an unobserved boss should not be shown at a made-up
-- coordinate.  Add a verified coordinate when one is available.
BossLocatorConfig.BOSSES = {
    {
        id = "kolmisilma",
        display_name = "Kolmisilmä (Three-Eye)",
        filename_patterns = { "boss_centipede" },
        name_patterns = { "$animal_boss_centipede" },
        tags = { "boss" },
        world_policy = "main",
        death_flag = "boss_centipede",
        default_position = nil,
    },
    {
        id = "kolmisilman_koipi",
        display_name = "Kolmisilmän Koipi (Three-Eye's Legs)",
        -- Guardian Slime uses slimeshooter_boss_limbs, while the parallel
        -- copy uses parallel_tentacles.  Keep this match specific to the
        -- Koipi entity rather than matching the shared "boss_limbs" token.
        filename_patterns = { "boss_limbs/boss_limbs.xml" },
        name_patterns = { "$animal_boss_limbs", "kolmisilmän koipi", "three-eye's legs" },
        tags = { "boss" },
        -- The vanilla data also contains entities with the same name that are
        -- not the Boss: boss_limbs_physics.xml (its physics body, tag
        -- "glue_NOT") and the copy below ending_placeholder/ (no "boss" tag).
        -- Requiring the Boss tag keeps them out of the tracker and out of a
        -- save scan.
        require_tags = true,
        exclude_tags = { "boss_parallel", "boss_minion" },
        world_policy = "main",
        default_position = nil,
    },
    {
        id = "kolmisilman_silma",
        display_name = "Kolmisilmän silmä (Three-Eye's Eye)",
        filename_patterns = { "boss_robot" },
        name_patterns = { "$animal_boss_robot" },
        tags = { "boss" },
        world_policy = "all",
        death_flag = "miniboss_robot",
        default_position = nil,
    },
    {
        id = "kolmisilman_sydan",
        display_name = "Kolmisilmän sydän (Three-Eye's Heart)",
        filename_patterns = { "boss_meat" },
        name_patterns = { "$animal_boss_meat" },
        tags = { "boss" },
        world_policy = "all",
        default_position = nil,
    },
    {
        id = "unohdettu",
        display_name = "Unohdettu (Forgotten)",
        filename_patterns = { "boss_ghost" },
        name_patterns = { "$animal_boss_ghost" },
        tags = { "boss" },
        world_policy = "all",
        death_flag = "miniboss_ghost",
        default_position = nil,
    },
    {
        id = "mestarien_mestari",
        display_name = "Mestarien mestari (Grand Master)",
        filename_patterns = { "boss_wizard" },
        name_patterns = { "$animal_boss_wizard" },
        tags = { "boss" },
        world_policy = "all",
        death_flag = "miniboss_wizard",
        default_position = nil,
    },
    {
        id = "sauvojen_tuntija",
        display_name = "Sauvojen tuntija (Connoisseur of Wands)",
        filename_patterns = { "boss_pit" },
        name_patterns = { "$animal_boss_pit" },
        tags = { "boss" },
        world_policy = "all",
        -- Monstrous Powder can create a new instance after an earlier one was
        -- defeated, so a death must not permanently close this Boss type.
        repeatable = true,
        death_flag = "miniboss_pit",
        default_position = nil,
    },
    {
        id = "ylialkemisti",
        display_name = "Ylialkemisti (High Alchemist)",
        filename_patterns = { "boss_alchemist" },
        name_patterns = { "$animal_boss_alchemist" },
        tags = { "boss" },
        exclude_tags = { "boss_parallel" },
        require_tags = true,
        world_policy = "all",
        death_flag = "miniboss_alchemist",
        default_position = nil,
    },
    {
        id = "epaalkemisti",
        display_name = "Epäalkemisti (Non-alchemist)",
        filename_patterns = { "failed_alchemist_b.xml" },
        name_patterns = { "$animal_failed_alchemist_b", "$animal_failed_alchemist" },
        revival_orb_filename_patterns = { "failed_alchemist_orb.xml" },
        revival_orb_name_patterns = { "$animal_failed_alchemist_orb" },
        revival_orb_script_patterns = { "failed_alchemist_orb.lua" },
        tags = { "mage" },
        world_policy = "all",
        -- The 220-frame orb phase is a resurrection window, not a confirmed
        -- kill.  The tracker keeps this state until the orb is destroyed or
        -- the living Boss entity is observed again.
        resurrection_frames = 220,
        default_position = nil,
    },
    {
        id = "alkemistin_varjo",
        display_name = "Alkemistin Varjo (Alchemist's Shadow)",
        -- The parallel copy is an entity of its own rather than a tagged
        -- variant: data/entities/animals/parallel/alchemist/parallel_alchemist.xml
        -- with the name "$animal_parallel_alchemist".  The tag "boss_parallel"
        -- that this entry used to require does not exist in the vanilla entity
        -- data (checked against the installed game data), which made the entry
        -- unmatchable - neither at runtime nor in a save scan.
        filename_patterns = { "parallel_alchemist.xml" },
        name_patterns = { "$animal_parallel_alchemist" },
        world_policy = "parallel",
        repeatable = true,
        default_position = nil,
    },
    {
        id = "limatoukka",
        display_name = "Limatoukka (Slime Maggot)",
        filename_patterns = { "maggot_tiny" },
        name_patterns = { "$animal_maggot_tiny" },
        tags = { "boss" },
        world_policy = "main",
        death_flag = "miniboss_maggot",
        default_position = nil,
    },
    {
        id = "suomuhauki",
        display_name = "Suomuhauki (Dragon)",
        filename_patterns = { "boss_dragon" },
        name_patterns = { "$animal_boss_dragon" },
        tags = { "boss" },
        world_policy = "all",
        -- The vanilla kill flag is run-global.  It is intentionally not used
        -- here because a Dragon in one world must not kill the marker in all
        -- other worlds; the observed entity state is world-scoped instead.
        default_position = nil,
    },
    {
        id = "kivi",
        display_name = "Kivi (Stone)",
        filename_patterns = { "boss_sky" },
        name_patterns = { "$animal_boss_sky" },
        tags = { "boss" },
        world_policy = "all",
        default_position = nil,
    },
    {
        id = "syvaolento",
        display_name = "Syväolento (Creature of the Deep)",
        filename_patterns = { "fish_giga" },
        name_patterns = { "$animal_fish_giga" },
        tags = { "boss" },
        world_policy = "main",
        default_position = nil,
    },
    {
        id = "toveri",
        display_name = "Toveri (Friend)",
        filename_patterns = { "friend" },
        name_patterns = { "$animal_friend" },
        tags = { "boss" },
        world_policy = "all",
        default_position = nil,
    },
    {
        id = "tapion_vasalli",
        display_name = "Tapion vasalli (Tapio's Vassal)",
        filename_patterns = { "islandspirit" },
        name_patterns = { "$animal_islandspirit" },
        -- Tapio's Vassal is in the ghost faction and is not marked with the
        -- generic boss tag in the vanilla entity definition.
        tags = { "ghost" },
        world_policy = "main",
        default_position = nil,
    },
    {
        id = "veska",
        display_name = "Veska (Gate Guardian)",
        filename_patterns = { "gate_monster_a" },
        name_patterns = { "$animal_gate_monster_a" },
        tags = { "boss" },
        world_policy = "all",
        default_position = nil,
    },
    {
        id = "molari",
        display_name = "Molari (Gate Guardian)",
        filename_patterns = { "gate_monster_b" },
        name_patterns = { "$animal_gate_monster_b" },
        tags = { "boss" },
        world_policy = "all",
        default_position = nil,
    },
    {
        id = "mokke",
        display_name = "Mokke (Gate Guardian)",
        filename_patterns = { "gate_monster_c" },
        name_patterns = { "$animal_gate_monster_c" },
        tags = { "boss" },
        world_policy = "all",
        default_position = nil,
    },
    {
        id = "seula",
        display_name = "Seula (Gate Guardian)",
        filename_patterns = { "gate_monster_d" },
        name_patterns = { "$animal_gate_monster_d" },
        tags = { "boss" },
        world_policy = "all",
        default_position = nil,
    },
    {
        id = "kolmisilman_katyri",
        display_name = "Kolmisilmän Kätyri (Three-Eye's Minion)",
        filename_patterns = { "parallel_tentacles" },
        name_patterns = { "$animal_parallel_tentacles" },
        tags = { "boss_parallel" },
        world_policy = "parallel",
        repeatable = true,
        default_position = nil,
    },
}

function BossLocatorConfig.setting_id(boss_id)
    return BossLocatorConfig.MOD_ID .. ".track_" .. boss_id
end

function BossLocatorConfig.is_visible_in_world(config, world_index)
    if config.world_policy == "main" then
        return world_index == 0
    end
    if config.world_policy == "parallel" then
        return world_index ~= 0
    end
    return true
end

local function lower(value)
    return string.lower(value or "")
end

local function contains_any(value, patterns)
    local candidate = lower(value)
    if patterns == nil then
        return false
    end
    for _, pattern in ipairs(patterns) do
        if string.find(candidate, lower(pattern), 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function has_any_tag(entity_id, tags)
    if tags == nil or type(EntityHasTag) ~= "function" then
        return false
    end
    for _, tag in ipairs(tags) do
        if EntityHasTag(entity_id, tag) then
            return true
        end
    end
    return false
end

local function has_excluded_tag(entity_id, tags)
    if tags == nil or type(EntityHasTag) ~= "function" then
        return false
    end
    for _, tag in ipairs(tags) do
        if EntityHasTag(entity_id, tag) then
            return true
        end
    end
    return false
end

-- A tag is an additional discriminator, not a replacement for the filename:
-- some vanilla entities have a broad "boss" tag and a few parallel-world
-- variants share the same XML file.
function BossLocatorConfig.matches_entity(config, entity_id, filename, entity_name)
    local filename_match = contains_any(filename, config.filename_patterns)
    local name_match = contains_any(entity_name, config.name_patterns)
    if not filename_match and not name_match then
        return false
    end
    if config.require_name_match and not name_match then
        return false
    end

    -- Filename/name matching is the primary discriminator.  Vanilla bosses
    -- use several different faction tags (and some have no generic "boss"
    -- tag), so a configured tag list is required only when a definition opts
    -- into it.
    if config.require_tags and config.tags ~= nil and not has_any_tag(entity_id, config.tags) then
        return false
    end
    if has_excluded_tag(entity_id, config.exclude_tags) then
        return false
    end
    return true
end

local function has_script_pattern(entity_id, patterns)
    if entity_id == nil or patterns == nil or
        type(EntityGetComponentIncludingDisabled) ~= "function" or
        type(ComponentGetValue2) ~= "function" then
        return false
    end

    local components = EntityGetComponentIncludingDisabled(entity_id, "LuaComponent") or {}
    for _, component_id in ipairs(components) do
        local script = ComponentGetValue2(component_id, "script_source_file") or ""
        if contains_any(script, patterns) then
            return true
        end
    end
    return false
end

function BossLocatorConfig.matches_revival_orb(config, filename, entity_name, entity_id)
    return contains_any(filename, config.revival_orb_filename_patterns) or
        contains_any(entity_name, config.revival_orb_name_patterns) or
        has_script_pattern(entity_id, config.revival_orb_script_patterns)
end

function BossLocatorConfig.get_by_id(boss_id)
    for _, config in ipairs(BossLocatorConfig.BOSSES) do
        if config.id == boss_id then
            return config
        end
    end
    return nil
end

-- ------------------------------------------------- matching stored entities
--
-- The base data of an entity that sits in a save file carries the entity name,
-- its XML path, the tag list and the transform - nothing else, because
-- saves/entity_parser.lua deliberately never decodes component payloads.  A
-- save also stores the helper entities a Boss owns ('body.xml',
-- 'boss_centipede_minion.xml', 'orb_green_boss_dragon.xml', ...), so a
-- substring search over the path - which is good enough for a live entity that
-- was found through a tag - would produce false positions here.
--
-- Stored entities are therefore matched on the exact file name stem
-- ('boss_centipede' for 'boss_centipede.xml') or on the entity name
-- ('$animal_boss_centipede'), and tags are compared as whole tokens.

local function file_stem(path)
    local name = tostring(path or ""):match("[^/\\]*$") or ""
    return lower((name:gsub("%.xml$", "")))
end

local function stem_matches(path, patterns)
    if patterns == nil then
        return false
    end
    local stem = file_stem(path)
    if stem == "" then
        return false
    end
    for _, pattern in ipairs(patterns) do
        if file_stem(pattern) == stem then
            return true
        end
    end
    return false
end

--- Entity names are compared exactly here: the name attribute of a helper
--- entity starts with the name of its owner ('$animal_boss_centipede_minion'
--- for '$animal_boss_centipede'), which a substring search would confuse.
local function name_matches(name, patterns)
    if patterns == nil then
        return false
    end
    local candidate = lower(name)
    if candidate == "" then
        return false
    end
    for _, pattern in ipairs(patterns) do
        if lower(pattern) == candidate then
            return true
        end
    end
    return false
end

local function stored_tags(record)
    if record.stored_tag_list == nil then
        local list = {}
        for tag in tostring(record.tags or ""):gmatch("[^,%s]+") do
            list[lower(tag)] = true
        end
        record.stored_tag_list = list
    end
    return record.stored_tag_list
end

local function stored_has_any_tag(record, tags)
    if tags == nil then
        return false
    end
    local list = stored_tags(record)
    for _, tag in ipairs(tags) do
        if list[lower(tag)] then
            return true
        end
    end
    return false
end

--- Matches one record parsed from a save file against a Boss definition.
-- 'record' is an entity_parser record: { path, name, tags, x, y, ... }.
function BossLocatorConfig.matches_saved_entity(config, record)
    if record == nil then
        return false
    end

    local filename_match = stem_matches(record.path, config.filename_patterns)
    local name_match = name_matches(record.name, config.name_patterns)
    if not filename_match and not name_match then
        return false
    end
    if config.require_name_match and not name_match then
        return false
    end

    if config.require_tags and config.tags ~= nil and
        not stored_has_any_tag(record, config.tags) then
        return false
    end
    if stored_has_any_tag(record, config.exclude_tags) then
        return false
    end
    return true
end

--- Matches the death orb of a resurrection-aware Boss in a save file.  The
--- component based check used at runtime is unavailable here, so the orb is
--- recognised through its file name and entity name.
function BossLocatorConfig.matches_saved_revival_orb(config, record)
    if record == nil then
        return false
    end
    if config.revival_orb_filename_patterns == nil and
        config.revival_orb_name_patterns == nil then
        return false
    end
    return stem_matches(record.path, config.revival_orb_filename_patterns) or
        name_matches(record.name, config.revival_orb_name_patterns)
end
