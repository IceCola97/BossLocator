local files = {
    "init.lua",
    "settings.lua",
    "files/config.lua",
    "files/world.lua",
    "files/state.lua",
    "files/locator.lua",
    "files/death_hook.lua",
}

for _, filename in ipairs(files) do
    local chunk, message = loadfile(filename)
    if chunk == nil then
        error(filename .. ": " .. tostring(message))
    end
end

print("syntax_test: ok")
