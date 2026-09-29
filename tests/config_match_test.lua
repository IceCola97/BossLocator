-- Boss matchers against the vanilla entity data.
--
-- The records below are the name/tag/path values of real vanilla entity files
-- (read from the installed game data), plus the look-alike files that share a
-- name or a path element with a Boss.  The test locks in two properties:
--
--   1. every Boss definition matches its own entity, and only its own entity,
--   2. no helper entity and no look-alike file is mistaken for a Boss.
--
-- This is the regression test for entries that could silently become
-- unmatchable (for example a definition that requires a tag the game data does
-- not contain).
local support = dofile("tests/save_test_support.lua")
local assert_equal, assert_true = support.assert_equal, support.assert_true

dofile("files/config.lua")

local function record(path, name, tags)
    return { path = path, name = name, tags = tags or "" }
end

-- One real entity per Boss definition.
local BOSSES = {
    { id = "kolmisilma", record = record(
        "data/entities/animals/boss_centipede/boss_centipede.xml",
        "$animal_boss_centipede",
        "enemy,mortal,hittable,homing_target,teleportable_NOT,sampo_or_boss,boss_centipede,polymorphable_NOT,boss,necrobot_NOT,glue_NOT") },
    { id = "kolmisilman_koipi", record = record(
        "data/entities/animals/boss_limbs/boss_limbs.xml",
        "$animal_boss_limbs",
        "enemy,mortal,human,hittable,homing_target,teleportable_NOT,boss,polymorphable_NOT,miniboss,music_energy_100,necrobot_NOT,glue_NOT") },
    { id = "kolmisilman_silma", record = record(
        "data/entities/animals/boss_robot/boss_robot.xml",
        "$animal_boss_robot",
        "enemy,mortal,human,hittable,homing_target,teleportable_NOT,boss,polymorphable_NOT,miniboss,music_energy_100,necrobot_NOT,glue_NOT") },
    { id = "kolmisilman_sydan", record = record(
        "data/entities/animals/boss_meat/boss_meat.xml",
        "$animal_boss_meat",
        "enemy,mortal,human,hittable,homing_target,teleportable_NOT,boss,polymorphable_NOT,miniboss,music_energy_100,necrobot_NOT,glue_NOT") },
    { id = "unohdettu", record = record(
        "data/entities/animals/boss_ghost/boss_ghost.xml",
        "$animal_boss_ghost",
        "enemy,teleportable_NOT,hittable,mortal,boss,touchmagic_immunity,music_energy_100,miniboss,polymorphable_NOT,necrobot_NOT,glue_NOT,curse_NOT") },
    { id = "mestarien_mestari", record = record(
        "data/entities/animals/boss_wizard/boss_wizard.xml",
        "$animal_boss_wizard",
        "touchmagic_immunity,polymorphable_NOT,boss,miniboss,music_energy_100,boss_wizard,necrobot_NOT,glue_NOT") },
    { id = "sauvojen_tuntija", record = record(
        "data/entities/animals/boss_pit/boss_pit.xml",
        "$animal_boss_pit",
        "enemy,mortal,human,hittable,homing_target,teleportable_NOT,boss,touchmagic_immunity,music_energy_100,miniboss,polymorphable_NOT,necrobot_NOT,glue_NOT,curse_NOT") },
    { id = "ylialkemisti", record = record(
        "data/entities/animals/boss_alchemist/boss_alchemist.xml",
        "$animal_boss_alchemist",
        "touchmagic_immunity,polymorphable_NOT,boss,miniboss,music_energy_100,necrobot_NOT,glue_NOT,curse_NOT") },
    { id = "epaalkemisti", record = record(
        "data/entities/animals/failed_alchemist_b.xml",
        "$animal_failed_alchemist_b", "") },
    { id = "alkemistin_varjo", record = record(
        "data/entities/animals/parallel/alchemist/parallel_alchemist.xml",
        "$animal_parallel_alchemist",
        "touchmagic_immunity,polymorphable_NOT") },
    { id = "limatoukka", record = record(
        "data/entities/animals/maggot_tiny/maggot_tiny.xml",
        "$animal_maggot_tiny",
        "enemy,hittable,teleportable_NOT,homing_target,glue_NOT,necrobot_NOT,polymorphable_NOT,touchmagic_immunity") },
    { id = "suomuhauki", record = record(
        "data/entities/animals/boss_dragon.xml",
        "$animal_boss_dragon",
        "enemy,mortal,hittable,teleportable_NOT,boss_dragon,homing_target,glue_NOT,necrobot_NOT,polymorphable_NOT") },
    { id = "kivi", record = record(
        "data/entities/animals/boss_sky/boss_sky.xml",
        "$animal_boss_sky",
        "enemy,mortal,human,hittable,homing_target,teleportable_NOT,boss,polymorphable_NOT,miniboss,music_energy_000,necrobot_NOT,glue_NOT,touchmagic_immunity") },
    { id = "syvaolento", record = record(
        "data/entities/animals/boss_fish/fish_giga.xml",
        "$animal_fish_giga",
        "hittable,polymorphable_NOT,necrobot_NOT,glue_NOT,teleportable_NOT,curse_NOT,touchmagic_immunity,mortal,hiteffect_enabled") },
    { id = "toveri", record = record(
        "data/entities/animals/friend.xml",
        "$animal_friend", "big_friend") },
    { id = "tapion_vasalli", record = record(
        "data/entities/animals/boss_spirit/islandspirit.xml",
        "$animal_islandspirit",
        "touchmagic_immunity,polymorphable_NOT,boss,miniboss,music_energy_100,necrobot_NOT,glue_NOT,curse_NOT,islandspirit") },
    { id = "veska", record = record(
        "data/entities/animals/boss_gate/gate_monster_a.xml",
        "$animal_gate_monster_a", "gate_monster,necrobot_NOT,glue_NOT") },
    { id = "molari", record = record(
        "data/entities/animals/boss_gate/gate_monster_b.xml",
        "$animal_gate_monster_b", "gate_monster") },
    { id = "mokke", record = record(
        "data/entities/animals/boss_gate/gate_monster_c.xml",
        "$animal_gate_monster_c", "gate_monster") },
    { id = "seula", record = record(
        "data/entities/animals/boss_gate/gate_monster_d.xml",
        "$animal_gate_monster_d", "") },
    { id = "kolmisilman_katyri", record = record(
        "data/entities/animals/parallel/tentacles/parallel_tentacles.xml",
        "$animal_parallel_tentacles",
        "enemy,mortal,human,hittable,homing_target,teleportable_NOT,touchmagic_immunity,polymorphable_NOT,glue_NOT") },
}

-- Entities that share a path element or a name with a Boss without being one.
local LOOKALIKES = {
    -- helpers of Kolmisilmä
    record("data/entities/animals/boss_centipede/boss_centipede_minion.xml",
        "$animal_boss_centipede_minion", "boss_centipede_minion,glue_NOT"),
    record("data/entities/animals/boss_centipede/boss_centipede_shield_strong.xml",
        "shield_entity", "energy_shield"),
    record("data/entities/animals/boss_centipede/body.xml", "", ""),
    -- the physics body and the ending copy of the Guardian Slime share its name
    record("data/entities/animals/boss_limbs/boss_limbs_physics.xml",
        "$animal_boss_limbs", "glue_NOT"),
    record("data/entities/animals/ending_placeholder/boss_limbs/boss_limbs.xml",
        "$animal_boss_limbs", "mortal,human,hittable,homing_target,teleportable_NOT,enemy"),
    -- files whose name merely contains a keyword of a Boss
    record("data/entities/projectiles/orb_green_boss_dragon.xml",
        "$animal_boss_dragon_endcrystal", "projectile"),
    record("data/entities/misc/custom_cards/damage_friendly.xml",
        "$animal_damage_friendly", "card"),
    record("data/entities/animals/boss_gate/gate_monster_a_glow.xml", "", ""),
    record("data/entities/animals/boss_alchemist/boss_alchemist_sprite.xml", "", ""),
    record("data/entities/animals/boss_alchemist/wand_orb.xml", "", ""),
    record("data/entities/animals/boss_sky/apparition_spawn_fx.xml", "",
        "miniboss,music_energy_50"),
    record("data/entities/animals/boss_pit/boss_pit_spawner.xml", "", ""),
    record("data/entities/animals/parallel/alchemist/sprite.xml", "", ""),
    record("data/entities/animals/parallel/tentacles/tentacle.xml", "", ""),
    -- unrelated entities
    record("data/entities/animals/zombie.xml", "$animal_zombie", "enemy,mortal"),
    record("data/entities/vegetation/tree_entity.xml", "unknown", "vegetation"),
}

local function matches_of(record_value)
    local matched = {}
    for _, config in ipairs(BossLocatorConfig.BOSSES) do
        if BossLocatorConfig.matches_saved_entity(config, record_value) then
            matched[#matched + 1] = config.id
        end
    end
    return matched
end

local checked = 0
for _, entry in ipairs(BOSSES) do
    local config = BossLocatorConfig.get_by_id(entry.id)
    assert_true(config ~= nil, "the configuration must define " .. entry.id)
    assert_true(BossLocatorConfig.matches_saved_entity(config, entry.record),
        entry.id .. " must match its own vanilla entity " .. entry.record.path)

    local matched = matches_of(entry.record)
    assert_equal(1, #matched, entry.record.path ..
        " must be matched by exactly one definition, got " .. table.concat(matched, ","))
    assert_equal(entry.id, matched[1], entry.record.path .. " must be attributed to " .. entry.id)
    checked = checked + 1
end

for _, lookalike in ipairs(LOOKALIKES) do
    local matched = matches_of(lookalike)
    assert_equal(0, #matched, lookalike.path ..
        " must not be mistaken for a Boss, got " .. table.concat(matched, ","))
end

-- The Non-alchemist has more than one vanilla entity; all of them describe the
-- same Boss, so matching all of them is intended.
local non_alchemist = BossLocatorConfig.get_by_id("epaalkemisti")
for _, path in ipairs({
    "data/entities/animals/failed_alchemist.xml",
    "data/entities/animals/crypt/failed_alchemist.xml",
}) do
    local entity = record(path, "$animal_failed_alchemist", "")
    assert_true(BossLocatorConfig.matches_saved_entity(non_alchemist, entity),
        path .. " is a Non-alchemist variant and has to be tracked")
end

-- The death orb is recognised as the resurrection state, not as the Boss.
local orb = record("data/entities/animals/failed_alchemist_orb.xml",
    "$animal_failed_alchemist_orb", "item")
local orb_config = nil
for _, config in ipairs(BossLocatorConfig.BOSSES) do
    if BossLocatorConfig.matches_saved_revival_orb(config, orb) then
        orb_config = config.id
    end
end
assert_equal("epaalkemisti", orb_config, "the death orb must belong to the Non-alchemist")

print(string.format("config_match_test: ok (%d Boss definitions, %d look-alikes)",
    checked, #LOOKALIKES))
