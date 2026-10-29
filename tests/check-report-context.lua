local originalIO, originalOS = io, os
local files, context, screenshots = {}, nil, 0
local disabled = false
widget = {}
Game = {gameName = "Example mod", gameVersion = "2.3", mapName = "Example map"}
Spring = {
	GetConfigInt = function() return disabled and 1 or 0 end,
	GetReplayRecordingFilePath = function() return "demos/current.sdfz" end,
	GetGameFrame = function() return 900 end,
	SendCommands = function(command) assert(command == "screenshot png"); screenshots = screenshots + 1 end,
}
io = {open = function(path, mode)
	if mode == "r" then return files[path] and {close = function() end} or nil end
	return {write = function(_, text) files[path] = text end, close = function() end}
end}
os = {
	time = function() return 1000 end,
	rename = function(from, to) files[to] = files[from]; files[from] = nil end,
	remove = function(path) files[path] = nil end,
}
dofile("external/chobby/macos/game-data/LuaUI/Widgets/gui_macos_reporting.lua")
widget:GameID("0123456789abcdef0123456789abcdef")
files["macos-report-screenshot"] = ""
widget:Update(1)
context = assert(files["macos-report-game.json"])
assert(context:find('"game_id":"0123456789abcdef0123456789abcdef"', 1, true))
assert(context:find('"map":"Example map"', 1, true))
assert(context:find('"version":"2.3"', 1, true))
assert(context:find('"frame":900', 1, true))
assert(screenshots == 1 and not files["macos-report-screenshot"])
disabled = true
files["macos-report-game.json"] = nil
widget:Update(1)
assert(not files["macos-report-game.json"])
io, os = originalIO, originalOS
print("PASS: game ID, mod version, map, frame, replay context and engine-only screenshot requests")
