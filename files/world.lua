-- World and camera helpers.

BossLocatorWorld = BossLocatorWorld or {}

local function get_player_position()
    if type(EntityGetWithTag) == "function" and type(EntityGetTransform) == "function" then
        local players = EntityGetWithTag("player_unit") or {}
        for _, player in ipairs(players) do
            if player ~= nil and player ~= 0 then
                local alive = true
                if type(EntityGetIsAlive) == "function" then
                    alive = EntityGetIsAlive(player)
                end
                if alive then
                    local x, y = EntityGetTransform(player)
                    if x ~= nil and y ~= nil then
                        return x, y
                    end
                end
            end
        end
    end

    if type(GameGetCameraPos) == "function" then
        return GameGetCameraPos()
    end
    return 0, 0
end

local function is_new_game_plus()
    if type(SessionNumbersGetValue) == "function" then
        local count = tonumber(SessionNumbersGetValue("NEW_GAME_PLUS_COUNT")) or 0
        if count > 0 then
            return true
        end
    end
    -- Nightmare uses the compact NG+ style world width as well.  The guard
    -- keeps this compatible with API versions that do not expose the flag.
    if type(GameHasFlagRun) == "function" and GameHasFlagRun("run_nightmare") then
        return true
    end
    return false
end

function BossLocatorWorld.width()
    if is_new_game_plus() then
        return BossLocatorConfig.NG_PLUS_WORLD_WIDTH
    end
    return BossLocatorConfig.NORMAL_WORLD_WIDTH
end

function BossLocatorWorld.index_for_position(x, y)
    -- Prefer the engine's own mapping.  Besides avoiding boundary drift, this
    -- remains correct if a game update changes the repeating world layout.
    if type(GetParallelWorldPosition) == "function" then
        local world_index = GetParallelWorldPosition(x or 0, y or 0)
        if world_index ~= nil then
            return math.floor(tonumber(world_index) or 0)
        end
    end

    local width = BossLocatorWorld.width()
    return math.floor(((x or 0) / width) + 0.5)
end

function BossLocatorWorld.index_for_x(x)
    return BossLocatorWorld.index_for_position(x, 0)
end

function BossLocatorWorld.current()
    local x, y = get_player_position()
    local width = BossLocatorWorld.width()
    local index = BossLocatorWorld.index_for_position(x, y)
    return {
        x = x,
        y = y,
        index = index,
        width = width,
        offset = index * width,
    }
end

function BossLocatorWorld.camera()
    if type(GameGetCameraBounds) == "function" then
        local x, y, width, height = GameGetCameraBounds()
        if x ~= nil and y ~= nil and width ~= nil and height ~= nil and width > 0 and height > 0 then
            return x, y, width, height
        end
    end

    local cx, cy = 0, 0
    if type(GameGetCameraPos) == "function" then
        cx, cy = GameGetCameraPos()
    end
    -- This fallback is only for older API builds without camera bounds.  The
    -- camera dimensions are replaced by GUI dimensions by the renderer.
    return cx, cy, nil, nil
end
