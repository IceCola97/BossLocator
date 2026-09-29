local files = {
    "init.lua",
    "settings.lua",
    "files/config.lua",
    "files/world.lua",
    "files/state.lua",
    "files/locator.lua",
    "files/death_hook.lua",
    "files/lua_bit.lua",
    "files/save_fs.lua",
    "files/save_locator.lua",
    "files/save_sync.lua",
    -- shared offline modules (kept free of os.execute/os.getenv/io.popen)
    "saves/entity_parser.lua",
    "saves/save_scanner.lua",
    -- vendored fastlz (pure Lua, used for compressed entity chunks)
    "fastlz/fastlz.lua",
}

for _, filename in ipairs(files) do
    local chunk, message = loadfile(filename)
    if chunk == nil then
        error(filename .. ": " .. tostring(message))
    end
end

print("syntax_test: ok")
