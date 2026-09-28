-- Runtime tracker and on-screen renderer.

BossLocator = BossLocator or {}

local runtime = {
    gui = nil,
    tracked = {},
    next_scan_id = 1,
    current_world = nil,
    last_frame = -1,
}

local function setting_enabled(setting_id, default_value)
    if type(ModSettingGet) ~= "function" then
        return default_value
    end
    local value = ModSettingGet(setting_id)
    if value == nil then
        return default_value
    end
    return value == true or value == "1" or value == 1
end

local function current_frame()
    if type(GameGetFrameNum) == "function" then
        return GameGetFrameNum()
    end
    return runtime.last_frame + 1
end

local function is_alive(entity_id)
    return entity_id ~= nil and entity_id ~= 0 and
        type(EntityGetIsAlive) == "function" and EntityGetIsAlive(entity_id)
end

local function entity_position(entity_id)
    if not is_alive(entity_id) or type(EntityGetTransform) ~= "function" then
        return nil, nil
    end
    local x, y = EntityGetTransform(entity_id)
    if x == nil or y == nil then
        return nil, nil
    end
    return x, y
end

local function entity_filename(entity_id)
    if type(EntityGetFilename) ~= "function" then
        return ""
    end
    return EntityGetFilename(entity_id) or ""
end

local function entity_name(entity_id)
    if type(EntityGetName) ~= "function" then
        return ""
    end
    return EntityGetName(entity_id) or ""
end

local function config_for_entity(entity_id)
    local filename = entity_filename(entity_id)
    local name = entity_name(entity_id)
    for _, config in ipairs(BossLocatorConfig.BOSSES) do
        if BossLocatorConfig.matches_revival_orb(config, filename, name, entity_id) then
            return config, "revival_orb"
        end
        if BossLocatorConfig.matches_entity(config, entity_id, filename, name) then
            return config, "boss"
        end
    end
    return nil, nil
end

local function read_hp(entity_id)
    if type(EntityGetFirstComponentIncludingDisabled) ~= "function" or
        type(ComponentGetValue2) ~= "function" then
        return nil
    end
    if entity_id == nil or entity_id == 0 then
        return nil
    end
    local damage_model = EntityGetFirstComponentIncludingDisabled(entity_id, "DamageModelComponent")
    if damage_model == nil then
        return nil
    end
    return tonumber(ComponentGetValue2(damage_model, "hp"))
end

local function attach_death_hook(entity_id)
    if type(EntityGetFirstComponentIncludingDisabled) == "function" and
        EntityGetFirstComponentIncludingDisabled(
            entity_id,
            "LuaComponent",
            "boss_locator_death_hook"
        ) ~= nil then
        return
    end

    local values = {
        _tags = "boss_locator_death_hook",
        script_death = "mods/boss_locator/files/death_hook.lua",
        execute_every_n_frame = -1,
    }
    if type(EntityAddComponent2) == "function" then
        EntityAddComponent2(entity_id, "LuaComponent", values)
    elseif type(EntityAddComponent) == "function" then
        EntityAddComponent(entity_id, "LuaComponent", {
            _tags = values._tags,
            script_death = values.script_death,
            execute_every_n_frame = tostring(values.execute_every_n_frame),
        })
    end
end

local function active_entity_exists(config_id, world_index, ignored_id)
    for entity_id, tracked in pairs(runtime.tracked) do
        if entity_id ~= ignored_id and tracked.config.id == config_id and
            tracked.world_index == world_index and is_alive(entity_id) then
            return true
        end
    end
    return false
end

local function active_boss_exists(config_id, world_index, ignored_id)
    for entity_id, tracked in pairs(runtime.tracked) do
        if entity_id ~= ignored_id and tracked.role == "boss" and
            tracked.config.id == config_id and tracked.world_index == world_index and
            is_alive(entity_id) then
            return true
        end
    end
    return false
end

local function record_death(tracked, frame)
    if tracked.death_observed then
        return
    end

    -- A resurrection-aware Boss and its replacement can overlap for one
    -- update.  The live replacement is authoritative; the old entity must not
    -- turn the state back into revive_pending (or dead for the orb).
    if tracked.config.resurrection_frames ~= nil and
        active_boss_exists(tracked.config.id, tracked.world_index, tracked.entity_id) then
        return
    end

    tracked.death_observed = true
    if tracked.role == "revival_orb" then
        BossLocatorState.mark_dead(
            tracked.config,
            tracked.world_index,
            tracked.last_x,
            tracked.last_y,
            frame
        )
    elseif tracked.config.resurrection_frames ~= nil then
        BossLocatorState.mark_revival_pending(
            tracked.config,
            tracked.world_index,
            tracked.last_x,
            tracked.last_y,
            frame
        )
    else
        BossLocatorState.mark_dead(
            tracked.config,
            tracked.world_index,
            tracked.last_x,
            tracked.last_y,
            frame
        )
    end
end

local function record_disappearance(entity_id, frame)
    local tracked = runtime.tracked[entity_id]
    if tracked == nil then
        return
    end

    runtime.tracked[entity_id] = nil
    local replacement_boss = tracked.config.resurrection_frames ~= nil and
        active_boss_exists(tracked.config.id, tracked.world_index, entity_id)

    -- The new living entity wins over the old entity's destruction.  This is
    -- possible when an orb expires and the Boss is spawned during the same
    -- frame, or when an area is streamed while both entities are present.
    if replacement_boss then
        return
    end

    local confirmed_death = tracked.death_observed or
        (tracked.last_hp ~= nil and tracked.last_hp <= 0) or
        BossLocatorState.is_dead(tracked.world_index, tracked.config.id)
    if confirmed_death then
        if tracked.role == "revival_orb" or tracked.config.resurrection_frames == nil then
            BossLocatorState.mark_dead(
                tracked.config,
                tracked.world_index,
                tracked.last_x,
                tracked.last_y,
                frame
            )
        else
            BossLocatorState.mark_revival_pending(
                tracked.config,
                tracked.world_index,
                tracked.last_x,
                tracked.last_y,
                frame
            )
        end
        return
    end

    if tracked.role == "revival_orb" and tracked.config.resurrection_frames ~= nil and
        not BossLocatorState.is_dead(tracked.world_index, tracked.config.id) then
        BossLocatorState.mark_revival_orb_unloaded(
            tracked.config,
            tracked.world_index,
            tracked.last_x,
            tracked.last_y,
            frame,
            false
        )
        return
    end

    -- A destroyed entity may simply belong to a chunk that was streamed out.
    -- Keep its cached position and mark it as unloaded until a new entity is
    -- observed in this world.
    if not active_entity_exists(tracked.config.id, tracked.world_index, entity_id) then
        BossLocatorState.mark_unloaded(
            tracked.config,
            tracked.world_index,
            tracked.last_x,
            tracked.last_y,
            frame
        )
    end
end

local function track_entity(entity_id)
    if not is_alive(entity_id) or runtime.tracked[entity_id] ~= nil then
        return false
    end

    local config, role = config_for_entity(entity_id)
    if config == nil then
        return false
    end

    local x, y = entity_position(entity_id)
    if x == nil or y == nil then
        return false
    end

    local hp = read_hp(entity_id)
    if hp ~= nil and hp <= 0 then
        if role == "boss" and config.resurrection_frames ~= nil then
            BossLocatorState.mark_revival_pending(
                config,
                BossLocatorWorld.index_for_position(x, y),
                x,
                y,
                current_frame()
            )
        else
            BossLocatorState.mark_dead(
                config,
                BossLocatorWorld.index_for_position(x, y),
                x,
                y,
                current_frame()
            )
        end
        return false
    end

    local world_index = BossLocatorWorld.index_for_position(x, y)
    -- A dead record remains hidden permanently.  A resurrection-aware Boss
    -- only becomes trackable again from revive_pending, which is handled by
    -- the state transition in mark_seen after this guard.
    if BossLocatorState.is_dead(world_index, config.id) then
        return false
    end

    attach_death_hook(entity_id)
    runtime.tracked[entity_id] = {
        entity_id = entity_id,
        config = config,
        world_index = world_index,
        role = role,
        last_x = x,
        last_y = y,
        last_hp = hp,
        death_observed = false,
    }
    if role == "revival_orb" then
        BossLocatorState.mark_revival_orb_seen(
            config,
            world_index,
            x,
            y,
            current_frame(),
            active_boss_exists(config.id, world_index, entity_id)
        )
    else
        BossLocatorState.mark_seen(config, world_index, x, y, current_frame())
    end
    return true
end

local function scan_tagged_entities()
    if type(EntityGetWithTag) ~= "function" then
        return
    end
    local tags = { "boss", "boss_parallel", "boss_centipede_active" }
    for _, tag in ipairs(tags) do
        local entities = EntityGetWithTag(tag) or {}
        for _, entity_id in ipairs(entities) do
            track_entity(entity_id)
        end
    end
end

local function scan_entity_ids()
    if type(EntitiesGetMaxID) ~= "function" then
        return
    end

    local max_id = EntitiesGetMaxID()
    if max_id == nil or max_id < 1 then
        return
    end
    if runtime.next_scan_id > max_id then
        -- Entity slots can be reused after an entity is destroyed.  Repeating
        -- the bounded scan therefore matters even after the first pass.
        runtime.next_scan_id = 1
    end
    local scanned = 0
    local scan_budget = math.min(BossLocatorConfig.SCAN_IDS_PER_FRAME, max_id)
    while scanned < scan_budget do
        local entity_id = runtime.next_scan_id
        runtime.next_scan_id = runtime.next_scan_id + 1
        if runtime.next_scan_id > max_id then
            runtime.next_scan_id = 1
        end
        scanned = scanned + 1
        if is_alive(entity_id) then
            track_entity(entity_id)
        end
    end
end

local function sync_death_flags(frame)
    if type(GameHasFlagRun) ~= "function" then
        return
    end

    for _, config in ipairs(BossLocatorConfig.BOSSES) do
        -- Run-global flags are safe only for main-world-only entities.  Using
        -- one for an "all worlds" boss would incorrectly kill every copy.
        if config.death_flag ~= nil and config.world_policy == "main" and
            GameHasFlagRun(config.death_flag) then
            local record = BossLocatorState.get(0, config.id)
            BossLocatorState.mark_dead(config, 0, record.last_x, record.last_y, frame)
        end
    end
end

local function update_tracked(frame)
    local to_remove = {}
    for entity_id, tracked in pairs(runtime.tracked) do
        -- Some vanilla death scripts replace an entity with a related entity
        -- (for example the Non-alchemist and its Death Orb).  Re-read the
        -- filename so a role change cannot be mistaken for an ordinary live
        -- update.
        local current_config, current_role = config_for_entity(entity_id)
        if current_config ~= nil and current_config.id == tracked.config.id then
            tracked.role = current_role
        end

        local alive = is_alive(entity_id)
        local hp = read_hp(entity_id)
        if hp ~= nil then
            tracked.last_hp = hp
        end

        local x, y = entity_position(entity_id)
        if x ~= nil and y ~= nil then
            tracked.last_x = x
            tracked.last_y = y
            -- Bosses normally cannot cross a world boundary, but using the
            -- entity position here keeps the key correct if a spell moves
            -- one across the boundary.
            tracked.world_index = BossLocatorWorld.index_for_position(x, y)
        end

        -- Read the health component before treating a missing entity as an
        -- unload.  This catches a boss killed between two update callbacks,
        -- while an entity that simply streamed out keeps its last position.
        if hp ~= nil and hp <= 0 then
            record_death(tracked, frame)
            table.insert(to_remove, entity_id)
        elseif not alive then
            table.insert(to_remove, entity_id)
        elseif x ~= nil and y ~= nil and
            (not BossLocatorState.is_dead(tracked.world_index, tracked.config.id) or
                (tracked.role == "boss" and tracked.config.resurrection_frames ~= nil)) then
            if tracked.role == "revival_orb" then
                BossLocatorState.mark_revival_orb_seen(
                    tracked.config,
                    tracked.world_index,
                    x,
                    y,
                    frame,
                    active_boss_exists(
                        tracked.config.id,
                        tracked.world_index,
                        entity_id
                    )
                )
            else
                BossLocatorState.mark_seen(
                    tracked.config,
                    tracked.world_index,
                    x,
                    y,
                    frame
                )
            end
        end
    end

    for _, entity_id in ipairs(to_remove) do
        record_disappearance(entity_id, frame)
    end
end

local function screen_arrow(dx, dy)
    if math.abs(dx) >= math.abs(dy) then
        if dx >= 0 then
            return ">"
        end
        return "<"
    end
    if dy >= 0 then
        return "v"
    end
    return "^"
end

local function edge_point(cx, cy, sx, sy, width, height, margin)
    local dx = sx - cx
    local dy = sy - cy
    if dx == 0 and dy == 0 then
        return cx, cy, "*"
    end

    local half_width = math.max(1, width * 0.5 - margin)
    local half_height = math.max(1, height * 0.5 - margin)
    local tx = math.huge
    local ty = math.huge
    if dx ~= 0 then
        tx = half_width / math.abs(dx)
    end
    if dy ~= 0 then
        ty = half_height / math.abs(dy)
    end
    local scale = math.min(tx, ty)
    local x = cx + dx * scale
    local y = cy + dy * scale
    return x, y, screen_arrow(dx, dy)
end

local function marker_positions(config, world)
    local positions = {}
    for _, tracked in pairs(runtime.tracked) do
        if tracked.config.id == config.id and tracked.world_index == world.index and
            tracked.role == "boss" and is_alive(tracked.entity_id) then
            table.insert(positions, {
                x = tracked.last_x,
                y = tracked.last_y,
                kind = "*",
            })
        end
    end

    for _, tracked in pairs(runtime.tracked) do
        if tracked.config.id == config.id and tracked.world_index == world.index and
            tracked.role == "revival_orb" and is_alive(tracked.entity_id) then
            table.insert(positions, {
                x = tracked.last_x,
                y = tracked.last_y,
                kind = "~",
            })
        end
    end

    if #positions > 0 then
        return positions
    end

    local x, y, record = BossLocatorState.get_position(config, world.index, world.offset)
    if x == nil or y == nil then
        return positions
    end
    table.insert(positions, { x = x, y = y, kind = "~" })
    return positions
end

local function draw_marker_at(gui, screen_width, screen_height, camera_x, camera_y, camera_width, camera_height,
    config, world_x, world_y, marker_kind)
    local screen_x = (world_x - camera_x) / camera_width * screen_width
    local screen_y = (world_y - camera_y) / camera_height * screen_height
    local margin = 8
    local on_screen = screen_x >= margin and screen_x <= screen_width - margin and
        screen_y >= margin and screen_y <= screen_height - margin
    local text = marker_kind .. " " .. config.display_name

    if on_screen then
        GuiText(gui, math.floor(screen_x), math.floor(screen_y), text)
        return
    end

    local center_x = screen_width * 0.5
    local center_y = screen_height * 0.5
    local edge_x, edge_y, arrow = edge_point(
        center_x,
        center_y,
        screen_x,
        screen_y,
        screen_width,
        screen_height,
        margin
    )
    GuiText(gui, math.floor(edge_x), math.floor(edge_y), arrow .. " " .. config.display_name)
end

local function draw_markers(gui, screen_width, screen_height, camera_x, camera_y, camera_width, camera_height,
    config, world)
    if not BossLocatorConfig.is_visible_in_world(config, world.index) or
        not setting_enabled(BossLocatorConfig.setting_id(config.id), true) or
        BossLocatorState.is_dead(world.index, config.id) then
        return
    end

    for _, marker in ipairs(marker_positions(config, world)) do
        draw_marker_at(
            gui,
            screen_width,
            screen_height,
            camera_x,
            camera_y,
            camera_width,
            camera_height,
            config,
            marker.x,
            marker.y,
            marker.kind
        )
    end
end

function BossLocator.draw()
    if not setting_enabled(BossLocatorConfig.MOD_ID .. ".show_overlay", true) then
        return
    end
    if type(GuiCreate) ~= "function" or type(GuiStartFrame) ~= "function" or
        type(GuiGetScreenDimensions) ~= "function" or type(GuiText) ~= "function" then
        return
    end

    if runtime.gui == nil then
        runtime.gui = GuiCreate()
    end
    if runtime.gui == nil then
        return
    end

    GuiStartFrame(runtime.gui)
    local screen_width, screen_height = GuiGetScreenDimensions(runtime.gui)
    if screen_width == nil or screen_height == nil or screen_width <= 0 or screen_height <= 0 then
        return
    end

    local camera_x, camera_y, camera_width, camera_height = BossLocatorWorld.camera()
    if camera_width == nil or camera_height == nil or camera_width <= 0 or camera_height <= 0 then
        camera_width = screen_width
        camera_height = screen_height
        camera_x = camera_x - camera_width * 0.5
        camera_y = camera_y - camera_height * 0.5
    end

    local world = runtime.current_world or BossLocatorWorld.current()
    for _, config in ipairs(BossLocatorConfig.BOSSES) do
        draw_markers(
            runtime.gui,
            screen_width,
            screen_height,
            camera_x,
            camera_y,
            camera_width,
            camera_height,
            config,
            world
        )
    end
end

function BossLocator.update()
    local frame = current_frame()
    if frame == runtime.last_frame then
        return
    end
    runtime.last_frame = frame
    runtime.current_world = BossLocatorWorld.current()

    scan_tagged_entities()
    scan_entity_ids()
    update_tracked(frame)
    sync_death_flags(frame)
    BossLocator.draw()
end

function BossLocator.reset()
    runtime.tracked = {}
    runtime.next_scan_id = 1
    runtime.current_world = nil
    runtime.last_frame = -1
    runtime.gui = nil
    BossLocatorState.clear_runtime_cache()
end

function BossLocator.entity_created(entity_id)
    track_entity(entity_id)
end

function BossLocator.entity_destroyed(entity_id)
    local frame = current_frame()
    record_disappearance(entity_id, frame)
end
