-- Boss Locator runtime entry point.

dofile_once("mods/boss_locator/files/config.lua")
dofile_once("mods/boss_locator/files/lua_bit.lua")
dofile_once("mods/boss_locator/files/save_fs.lua")
dofile_once("mods/boss_locator/files/save_locator.lua")
dofile_once("mods/boss_locator/files/world.lua")
dofile_once("mods/boss_locator/files/state.lua")
dofile_once("mods/boss_locator/files/save_sync.lua")
dofile_once("mods/boss_locator/files/locator.lua")

function OnWorldInitialized()
    BossLocator.reset()
    -- Arms the optional automatic save scan; it runs a couple of seconds later
    -- so that loading a world is not slowed down by it.
    BossLocatorSaveSync.on_world_initialized()
end

function OnWorldPostUpdate()
    BossLocator.update()
    BossLocatorSaveSync.tick()
end

-- The runtime's supported path is the bounded scan in locator.lua (the public
-- Noita API does not promise global entity-created/entity-destroyed hooks).
-- These optional entry points are harmless on builds that do not emit them and
-- provide a fast path on hook layers that do.
function OnEntityCreated(entity_id)
    BossLocator.entity_created(entity_id)
end

function OnEntityDestroyed(entity_id)
    BossLocator.entity_destroyed(entity_id)
end
