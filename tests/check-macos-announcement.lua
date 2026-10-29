-- Run from ZkMacOS with luajit tests/check-macos-announcement.lua.
local config = {}
Spring = {
	Orig = {GetViewSizes = function() return 1280, 800 end},
	GetConfigInt = function(key, fallback) return config[key] == nil and fallback or config[key] end,
	SetConfigInt = function(key, value) config[key] = value end,
	Echo = function() end,
}
WG = {}

for _, platform in ipairs({"MacOS", "MacOSX", "Windows", "Linux"}) do
	Platform = {osFamily = platform}
	local settings, names, defaults = dofile("external/chobby/LuaMenu/configs/gameConfig/zk/settingsMenu.lua")
	for _, key in ipairs({"MacAnnounceChat", "MacAnnounceMarker"}) do
		if platform == "MacOS" or platform == "MacOSX" then
			local setting = assert(names[key])
			assert(defaults[key] == "On")
			assert(settings[2].name == "Game")
			assert(settings[2].settings[1] == setting or settings[2].settings[2] == setting)
			assert(settings[2].presets[1].settings[key] == "On")
			for _, choice in ipairs({"Off", "On"}) do
				setting.optionNames[choice].applyFunction()
				assert(config[key] == (choice == "On" and 1 or 0))
				assert(setting.defaultFunction() == choice)
			end
			config[key] = nil
		else
			assert(not names[key] and not defaults[key])
		end
	end
end

-- Saved lobby choices must be reapplied to engine config on the next launch.
LCS = {class = function() return setmetatable({}, {__call = function(self) return self end}) end}
LUA_DIRNAME = "LuaMenu/"
VFS = {Include = function(path)
	if path:find("springsettingsChanges.lua", 1, true) then return {}, {}, {}, {}, 1 end
end}
dofile("external/chobby/LuaMenu/widgets/chobby/components/configuration.lua")
Platform = {osFamily = "MacOS"}
local _, names = dofile("external/chobby/LuaMenu/configs/gameConfig/zk/settingsMenu.lua")
local configuration = setmetatable({
	gameConfig = {settingsNames = {MacAnnounceChat = names.MacAnnounceChat, MacAnnounceMarker = names.MacAnnounceMarker}},
	noNaiveConfigOverride = {settingsMenuValues = true}, channels = {}, game_settings = {},
	settingsMenuValues = {}, listeners = {},
}, {__index = Configuration})
for _, choice in ipairs({"Off", "On"}) do
	configuration:SetConfigData({settingsMenuValues = {MacAnnounceChat = choice, MacAnnounceMarker = choice}})
	local expected = choice == "On" and 1 or 0
	assert(config.MacAnnounceChat == expected and config.MacAnnounceMarker == expected)
end
config = {}

local function loadGame(args)
	args = args or {}
	local state = {chat = {}, markers = {}, units = args.units or {11}}
	Platform = {osFamily = args.platform or "MacOS"}
	UnitDefs = {
		[1] = {customParams = {dynamic_comm = "1"}},
		[2] = {customParams = {}},
	}
	Spring.IsReplay = function() return args.replay or false end
	Spring.GetSpectatingState = function() return args.spectator or false end
	Spring.GetGameFrame = function() return args.frame or 0 end
	Spring.GetMyPlayerID = function() return 7 end
	Spring.GetMyTeamID = function() return 2 end
	Spring.GetPlayerRulesParam = function(playerID, key)
		assert(playerID == 7 and key == "commshare_orig_teamid")
		return args.originalTeam
	end
	Spring.GetTeamUnits = function(teamID) assert(teamID == 2); return state.units end
	Spring.GetUnitDefID = function(unitID) return unitID == 10 and 2 or 1 end
	Spring.GetUnitRulesParam = function(unitID, key)
		assert(key == "commander_owner_team")
		return args.owners and args.owners[unitID]
	end
	Spring.GetUnitPosition = function(unitID) return unitID * 10 + (state.moved or 0), 1000, unitID * 20 end
	Spring.GetGroundHeight = function() return 42 end
	Spring.SendCommands = function(command) state.chat[#state.chat + 1] = command end
	Spring.MarkerAddPoint = function(...) state.markers[#state.markers + 1] = {...} end
	widgetHandler = {RemoveWidget = function() state.removed = true end}
	widget = {}
	dofile("external/chobby/macos/game-data/LuaUI/Widgets/gui_macos_announcement.lua")
	assert(widget:GetInfo().enabled)
	widget:Initialize()
	return state, widget
end

-- Loading and pregame must stay silent; only GameStart arms the widget.
local state, w = loadGame()
w:GameFrame(0)
assert(#state.chat == 0 and #state.markers == 0 and not state.removed)
w:GameStart()
assert(#state.chat == 1 and #state.markers == 0)
assert(state.chat[1] == "say Playing on ZkMacOS; sorry if technical issues disconnect me.")
w:GameFrame(1)
assert(#state.markers == 0 and not state.removed)
-- The game clears start markers on frame 4; ours must survive that cleanup.
state.markers = {}
state.moved = 500
w:GameFrame(4)
w:GameFrame(16)
assert(#state.markers == 0 and not state.removed)
w:GameFrame(31)
assert(#state.markers == 1 and state.removed)
local marker = state.markers[1]
assert(marker[1] == 110 and marker[2] == 42 and marker[3] == 220)
assert(marker[4] == "Playing on ZkMacOS" and marker[5] == false, "marker must be shared")
w:GameStart()
w:GameFrame(46)
assert(#state.chat == 1 and #state.markers == 1, "announce once per game")

-- Each toggle works independently, and a new game announces again.
for chat = 0, 1 do
	for markerEnabled = 0, 1 do
		config.MacAnnounceChat, config.MacAnnounceMarker = chat, markerEnabled
		state, w = loadGame()
		w:GameStart()
		w:GameFrame(1)
		w:GameFrame(31)
		assert(#state.chat == chat and #state.markers == markerEnabled)
	end
end
config = {}

-- Spawn can arrive after GameStart; ignore ordinary units and teammates' commanders.
state, w = loadGame({units = {10, 11}, originalTeam = 3, owners = {[11] = 2, [12] = 3}})
w:GameStart()
w:GameFrame(1)
assert(#state.markers == 0 and not state.removed)
state.units[#state.units + 1] = 12
w:GameFrame(16)
w:GameFrame(31)
assert(#state.markers == 1 and state.markers[1][1] == 120)

for _, args in ipairs({{replay = true}, {spectator = true}, {frame = 500}, {platform = "Linux"}}) do
	state = loadGame(args)
	assert(state.removed and #state.chat == 0 and #state.markers == 0)
end
state, w = loadGame()
Spring.GetSpectatingState = function() return true end
w:GameStart()
assert(#state.chat == 0 and #state.markers == 0)

print("PASS: Game-tab toggles default on; announcements wait for game start, respect both toggles, mark the owned commander, and skip spectators, replays and midgame reloads")
