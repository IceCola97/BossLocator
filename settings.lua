-- Noita's settings entry point.  This file is kept separate from init.lua so
-- the settings screen can be opened before a world is running.

dofile("data/scripts/lib/mod_settings.lua")
dofile_once("mods/boss_locator/files/config.lua")
dofile_once("mods/boss_locator/files/world.lua")
dofile_once("mods/boss_locator/files/state.lua")
dofile_once("mods/boss_locator/files/lua_bit.lua")
dofile_once("mods/boss_locator/files/save_fs.lua")
dofile_once("mods/boss_locator/files/save_locator.lua")
dofile_once("mods/boss_locator/files/save_sync.lua")

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

-- "扫描存档以同步实际位置" is an action, not a stored value: the entry is drawn
-- by its own ui_fn and skipped by mod_settings_update (not_setting).  A scan is
-- processed one slice per frame so the settings screen stays responsive.
local scan_job = nil
local scan_progress = nil

local function draw_scan_button(mod_id_arg, gui, in_main_menu, im_id, setting)
    local ability = BossLocatorSaveSync.capability(in_main_menu)

    GuiLayoutBeginHorizontal(gui, 0, 0)
    if ability.can_scan then
        local clicked = GuiButton(gui, im_id, 0, 0, setting.ui_name)
        if clicked and scan_job == nil then
            local job, failure = BossLocatorSaveSync.begin_scan({
                in_main_menu = in_main_menu,
                reason = "manual",
            })
            if job ~= nil then
                scan_job = job
                scan_progress = { done = 0, total = #job.files }
            else
                BossLocatorSaveSync.announce(failure, true)
            end
        end
        if scan_job ~= nil then
            local progress = BossLocatorSaveSync.step_scan(scan_job)
            if progress.running then
                scan_progress = { done = progress.done, total = progress.total }
            else
                scan_job = nil
                scan_progress = nil
                BossLocatorSaveSync.announce(progress.result, true)
            end
        end
    else
        -- Without a run, or without the file system permission the mod has to
        -- request in mod.xml, the button is drawn disabled and the reason is
        -- shown next to it.
        if type(GuiOptionsAddForNextWidget) == "function" and
            type(GUI_OPTION) == "table" and GUI_OPTION.Disabled ~= nil then
            GuiOptionsAddForNextWidget(gui, GUI_OPTION.Disabled)
        end
        GuiButton(gui, im_id, 0, 0, setting.ui_name)
    end

    local text = nil
    if not ability.can_scan then
        text = ability.hint
    elseif scan_progress ~= nil then
        text = BossLocatorSaveSync.progress_text(scan_progress.done, scan_progress.total)
    else
        local last = BossLocatorSaveSync.last_result()
        if last ~= nil then
            text = BossLocatorSaveSync.summary_text(last)
        else
            local target = BossLocatorSaveSync.peek_location()
            if target ~= nil and target.ok == true then
                text = "将扫描 " .. tostring(target.slot) .. "（" .. tostring(target.reason) .. "）"
            end
        end
    end
    if text ~= nil and text ~= "" then
        GuiText(gui, 0, 0, text)
    end
    GuiLayoutEnd(gui)

    if type(GuiTooltip) == "function" then
        GuiTooltip(gui, setting.ui_description,
            BossLocatorSaveSync.detail_text(BossLocatorSaveSync.last_result()))
    end
end

mod_settings = {
    {
        id = "show_overlay",
        ui_name = "Show Boss markers",
        ui_description = "Draw selected Boss positions and off-screen arrows during gameplay.",
        value_default = true,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
    {
        id = BossLocatorConfig.SETTING_SCAN_SAVE,
        ui_name = "扫描存档以同步实际位置",
        ui_description = "读取当前存档的实体区块，解析其中每个实体的标签与位置，把匹配到的 Boss " ..
            "位置写入本存档的记录，使旧存档也能立即显示所有 Boss 的位置。\n" ..
            "只读取存档，不会写入或修改任何存档文件。\n" ..
            "需要在游戏中（载入存档后）才可使用，并需要 mod.xml 中的不安全权限 " ..
            "(request_no_api_restrictions=\"1\")。",
        not_setting = true,
        ui_fn = draw_scan_button,
    },
    {
        id = BossLocatorConfig.SETTING_SCAN_ON_LOAD,
        ui_name = "载入存档时自动同步一次",
        ui_description = "每次进入世界后延迟两秒自动执行一次存档扫描，适合长期游玩旧存档时保持位置最新。",
        value_default = false,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    },
}

do
    local slot_values = { { "", "自动（使用游戏实际使用的存档槽）" } }
    for index = 0, BossLocatorConfig.SAVE_SLOT_COUNT - 1 do
        local slot = string.format("save%02d", index)
        slot_values[#slot_values + 1] = { slot, slot }
    end
    table.insert(mod_settings, {
        id = BossLocatorConfig.SETTING_SLOT_OVERRIDE,
        ui_name = "扫描的存档槽",
        ui_description = "扫描存档时使用的存档槽。默认自动：优先采用游戏自身报告的存档槽，" ..
            "否则使用最近写入的存档槽，因此支持把存档切换到 save01 之类的多存档模组。",
        value_default = "",
        values = slot_values,
        scope = MOD_SETTING_SCOPE_RUNTIME,
    })
end

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
