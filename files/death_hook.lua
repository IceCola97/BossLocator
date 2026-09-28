-- Runs in the dying entity's Lua context.  The runtime scanner remains the
-- main tracking path; this hook distinguishes a real death from chunk unload
-- when an entity dies between two scans.

dofile_once("mods/boss_locator/files/config.lua")
dofile_once("mods/boss_locator/files/world.lua")
dofile_once("mods/boss_locator/files/state.lua")

function death(damage_type_bit_field, damage_message, entity_thats_responsible, drop_items)
    local entity_id = GetUpdatedEntityID()
    if entity_id == nil or entity_id == 0 then
        return
    end

    local filename = ""
    if type(EntityGetFilename) == "function" then
        filename = EntityGetFilename(entity_id) or ""
    end

    local entity_name = ""
    if type(EntityGetName) == "function" then
        entity_name = EntityGetName(entity_id) or ""
    end

    local x, y = 0, 0
    if type(EntityGetTransform) == "function" then
        x, y = EntityGetTransform(entity_id)
    end
    x = x or 0
    y = y or 0

    local frame = 0
    if type(GameGetFrameNum) == "function" then
        frame = GameGetFrameNum()
    end
    local world_index = BossLocatorWorld.index_for_position(x, y)

    for _, config in ipairs(BossLocatorConfig.BOSSES) do
        if BossLocatorConfig.matches_revival_orb(config, filename, entity_name, entity_id) then
            local hp = nil
            if type(EntityGetFirstComponentIncludingDisabled) == "function" and
                type(ComponentGetValue2) == "function" then
                local damage_model = EntityGetFirstComponentIncludingDisabled(
                    entity_id,
                    "DamageModelComponent"
                )
                if damage_model ~= nil then
                    hp = tonumber(ComponentGetValue2(damage_model, "hp"))
                end
            end

            -- Expiration revives the Boss and can also trigger a death callback.
            -- Only an orb whose health reached zero is a confirmed final kill.
            if hp ~= nil and hp <= 0 then
                BossLocatorState.mark_dead(config, world_index, x, y, frame)
            else
                BossLocatorState.mark_revival_pending(config, world_index, x, y, frame)
            end
            return
        end

        if BossLocatorConfig.matches_entity(config, entity_id, filename, entity_name) then
            if config.resurrection_frames ~= nil then
                BossLocatorState.mark_revival_pending(config, world_index, x, y, frame)
            else
                BossLocatorState.mark_dead(config, world_index, x, y, frame)
            end
            return
        end
    end
end
