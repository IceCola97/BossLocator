-- Noita's settings entry point.  This file is kept separate from init.lua so
-- the settings screen can be opened before a world is running.

dofile("data/scripts/lib/mod_settings.lua")
dofile_once("mods/boss_locator/files/config.lua")
dofile_once("mods/boss_locator/files/world.lua")
dofile_once("mods/boss_locator/files/state.lua")

local mod_id = BossLocatorConfig.MOD_ID
mod_settings_version = 1

local function boss_setting(config)
    return {
        id = "track_" .. config.id,
        ui_name = config.display_name,
        ui_description = "Show a marker for this Boss. Status is read from the current save.",
        value_default = true,
        scope = MOD_SETTING_SCOPE_RUNTIME,
        _boss_config = config,
    }
end

mod_settings = {
    {
        id = "show_overlay",
        ui_name = "Show Boss markers",
        ui_description = "Draw selected Boss positions and off-screen arrows during gameplay.",
        value_default = true,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
}

for _, config in ipairs(BossLocatorConfig.BOSSES) do
    table.insert(mod_settings, boss_setting(config))
end

local function current_status(config)
    local world = BossLocatorWorld.current()
    return BossLocatorState.status_text(config, world.index, world.offset)
end

function ModSettingsUpdate(init_scope)
    mod_settings_update(mod_id, mod_settings, init_scope)
end

function ModSettingsGuiCount()
    return mod_settings_gui_count(mod_id, mod_settings)
end

function ModSettingsGui(gui, in_main_menu)
    for _, setting in ipairs(mod_settings) do
        if setting._boss_config ~= nil then
            setting.ui_description = "Show a marker for this Boss.\nStatus: " ..
                current_status(setting._boss_config)
        end
    end
    mod_settings_gui(mod_id, mod_settings, gui, in_main_menu)
end
