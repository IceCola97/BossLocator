-- Unit tests for saves/save_scanner.lua.
--
-- The scanner injects both directory enumeration and file reading, so the whole
-- module can be tested in memory: nothing here touches the filesystem or a shell.
--
-- Contract under test: the caller passes a save<N> directory, the scanner asks
-- the host to enumerate its world/ sub directory and matches the entity files
-- found there.
package.path = package.path .. ";saves/?.lua"
local scriptDir = (debug.getinfo(1, "S").source:sub(2):match("^(.*[\\/])") or "./"):gsub("\\", "/")
package.path = package.path .. ";" .. scriptDir .. "../saves/?.lua"
local scanner = require("save_scanner")

local checks = 0
local function check(condition, message)
    checks = checks + 1
    if not condition then
        error(message or ("check " .. checks .. " failed"), 2)
    end
end

-- matching: entity files directly inside a world/ directory, both separators,
-- absolute and relative paths, negative indices
check(scanner.matches("C:\\games\\Noita\\save00\\world\\entities_12.bin"))
check(scanner.matches("/home/x/.noita/save1/world/entities_-2000.bin"))
check(scanner.matches("save03/world/entities_0.bin"))
check(scanner.matches("/backup/save00/world/entities_0.bin"))
check(not scanner.matches("save00/world/entities_0.bin.bak"))
check(not scanner.matches("save00/world/player.bin"))
check(not scanner.matches("save00/world/entities_.bin"))
check(not scanner.matches("save00/persistent/entities_0.bin"))
check(not scanner.matches("save00/entities_0.bin"), "entity files outside world/ do not match")
check(not scanner.matches("save00/world/sub/entities_0.bin"), "world/ sub directories do not match")
check(not scanner.matches(""))
check(not scanner.matches(nil))

-- save id helpers
check(scanner.saveId("/a/save07/world/entities_1.bin") == "save07", "saveId absolute")
check(scanner.saveId("save12/world/entities_1.bin") == "save12", "saveId relative")
check(scanner.saveId("C:\\x\\save02\\world\\entities_1.bin") == "save02", "saveId windows")
check(scanner.saveId("/a/save07/world/player.bin") == nil, "saveId non entity file")
check(scanner.saveId("/a/mysave/world/entities_1.bin") == nil, "saveId for a non save<N> directory")
check(scanner.saveName("/a/save07") == "save07", "saveName plain")
check(scanner.saveName("/a/save07/") == "save07", "saveName trailing separator")
check(scanner.saveName("C:\\x\\save02") == "save02", "saveName windows")
check(scanner.saveName("/a/mysave") == nil, "saveName of another directory")

-- the world directory handed to the enumerator follows the caller's separator
check(scanner.worldPath("/a/save00") == "/a/save00/world", "worldPath posix")
check(scanner.worldPath("/a/save00/") == "/a/save00/world", "worldPath with trailing separator")
check(scanner.worldPath("C:\\x\\save00") == "C:\\x\\save00\\world", "worldPath windows")

-- enumeration is injected; nothing is read here
local listed = {
    "/a/save00/world/entities_2.bin",
    "/a/save00/world/entities_10.bin",
    "/a/save00/world/nope.bin",
    "/a/save00/persistent/flag",
    "/a/save00/world/player.bin",
}
local seenDirectory
local matched, visited = scanner.list("/a/save00", {
    enumerate = function(directory)
        seenDirectory = directory
        return listed
    end,
})
check(seenDirectory == "/a/save00/world", "the world directory is enumerated")
check(visited == 5, "every listed entry is inspected")
check(#matched == 2, "only entity files match")
check(matched[1] == "/a/save00/world/entities_10.bin", "matches are sorted")

-- an iterator based enumerator works too
local iteratorIndex = 0
local fromIterator = scanner.list("/a/save00", {
    enumerate = function()
        return function()
            iteratorIndex = iteratorIndex + 1
            return listed[iteratorIndex]
        end
    end,
})
check(#fromIterator == 2, "iterator enumerators are accepted")

-- pre-listed files skip enumeration entirely
local fromFiles = scanner.list(nil, { files = listed })
check(#fromFiles == 2, "opts.files skips enumeration")

-- scan hands path/saveId/index to the callback and can feed the bytes
local calls = {}
local handled, visitedCount, summary = scanner.scan("/a/save00", function(path, saveId, index, data)
    calls[#calls + 1] = { path = path, saveId = saveId, index = index, data = data }
    return true
end, {
    enumerate = function() return listed end,
    read = function(path) return "bytes:" .. path end,
})
check(handled == 2, "two files handled")
check(visitedCount == 5, "visited count reported")
check(visitedCount == summary.visited and summary.matched == 2, "summary matches")
check(summary.saveDir == "/a/save00" and summary.saveId == "save00", "summary reports the save")
check(summary.read == 2 and summary.failed == 0 and not summary.stopped, "summary counters")
check(calls[1].saveId == "save00" and calls[1].index == 1, "callback receives saveId and index")
check(calls[1].data == "bytes:" .. calls[1].path, "callback receives the file bytes")

-- a directory that is not named save<N> falls back to the path, then to nil
local renamed = { "/a/backup_copy/world/entities_3.bin" }
local fallbackId = "unset"
scanner.scan("/a/backup_copy", function(_, saveId) fallbackId = saveId end, {
    enumerate = function() return renamed end,
})
check(fallbackId == nil, "no save id for a non save<N> directory")
fallbackId = "unset"
scanner.scan("/a/backup_copy", function(_, saveId) fallbackId = saveId end, {
    enumerate = function() return { "/a/save09/world/entities_3.bin" } end,
})
check(fallbackId == "save09", "save id falls back to the file path")

-- without opts.read the callback gets no data
local noData = scanner.scan("/a/save00", function(_, _, _, data)
    check(data == nil, "no data without opts.read")
end, { enumerate = function() return listed end })
check(noData == 2, "no read still handles every match")

-- read failures are collected instead of calling the callback
local failures = {}
local callbackCalls = 0
local failedSummary
handled, _, failedSummary = scanner.scan("/a/save00", function() callbackCalls = callbackCalls + 1 end, {
    enumerate = function() return listed end,
    read = function(path)
        if path:match("entities_10") then return nil, "locked" end
        return "ok"
    end,
    onError = function(path, message) failures[#failures + 1] = path .. "|" .. tostring(message) end,
})
check(handled == 1 and callbackCalls == 1, "unreadable files are skipped")
check(failedSummary.failed == 1 and #failedSummary.errors == 1, "read failure is recorded")
check(failedSummary.errors[1].path:match("entities_10") ~= nil, "recorded path is the unreadable file")
check(failures[1]:match("locked") ~= nil, "onError reports the message")

-- callback returning false stops the scan
local stopped = 0
local stoppedSummary
handled, _, stoppedSummary = scanner.scan("/a/save00", function()
    stopped = stopped + 1
    return false
end, { enumerate = function() return listed end })
check(handled == 1 and stopped == 1, "early stop after the first file")
check(stoppedSummary.stopped == true, "summary reports the stop")

-- missing save directory, missing enumerator and empty listings fail loudly
local ok, message = pcall(scanner.list, "/a/save00")
check(not ok and tostring(message):match("no enumerator"), "missing enumerator is an error")
ok, message = pcall(scanner.list, "/a/save00", { enumerate = function() return {} end })
check(not ok and tostring(message):match("nothing listed"), "empty listing is an error")
ok, message = pcall(scanner.list, "/a/save00", { enumerate = function() return {} end, allowEmpty = true })
check(ok, "allowEmpty tolerates an empty listing")
ok, message = pcall(scanner.worldPath, "")
check(not ok and tostring(message):match("save directory is required"), "worldPath validates its input")
ok, message = pcall(scanner.scan, "/a/save00", "not a function", { enumerate = function() return listed end })
check(not ok and tostring(message):match("callback must be a function"), "callback type is enforced")

print(string.format("save_scanner_test: ok (%d checks)", checks))
