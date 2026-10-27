-- Run from the workspace root with luajit.
local config = {MacRetinaMode = 1}
local lobbyWidget
local lobbyPrompts, gamePrompts = 0, 0
Platform = {osFamily = "MacOS", gpuVendor = "Test GPU"}
Spring = {
	Orig = {GetViewSizes = function() return 1488, 813 end},
	GetConfigInt = function(key, fallback) return config[key] == nil and fallback or config[key] end,
	SetConfigInt = function(key, value) config[key] = value end,
	Echo = function() end,
	SendLuaMenuMsg = function(message) lobbyWidget:RecvLuaMsg(message) end,
}
widgetHandler = {RemoveCallIn = function() end, RemoveWidget = function() error("unexpected removal") end}
local configuration = {
	gameConfig = {},
	settingsMenuValues = {}, game_settings = {},
}
configuration.gameConfig.settingsConfig, configuration.gameConfig.settingsNames, configuration.gameConfig.settingsDefault =
	dofile("external/chobby/LuaMenu/configs/gameConfig/zk/settingsMenu.lua")
function configuration:SetSettingsConfigOption(key, label)
	local option = self.gameConfig.settingsNames[key].optionNames[label]
	assert(option)
	local apply = option.apply or option.applyFunction()
	self.settingsMenuValues[key] = label
	self.game_settings.MacRetinaMode = apply.MacRetinaMode
	Spring.SetConfigInt("MacRetinaMode", apply.MacRetinaMode)
end
WG = {
	Chobby = {Configuration = configuration, InformationPopup = function() lobbyPrompts = lobbyPrompts + 1 end},
	Chili = {
		Window = {New = function() gamePrompts = gamePrompts + 1; return {Dispose = function() end} end},
		TextBox = {New = function() end}, Button = {New = function() end},
	},
}
widget = {}
dofile("external/chobby/LuaMenu/widgets/gui_macos_display.lua")
lobbyWidget = widget
local settings = configuration.gameConfig.settingsConfig[1].settings
for index, setting in ipairs(settings) do
	if setting.name == "ActiveGraphicsLabel" then assert(settings[index + 1].name == "MacRetinaMode") end
end
lobbyWidget:RecvLuaMsg("macRetinaMode 2")
assert(config.MacRetinaMode == 2 and configuration.settingsMenuValues.MacRetinaMode == "Full Retina")
assert(lobbyPrompts == 1)
widget = {}
dofile("external/chobby/macos/game-data/LuaUI/Widgets/gui_macos_display.lua")
widget:Initialize()
assert(options.retina.value == "2" and options.retina.noSave)
options.retina.value = "0"
options.retina:OnChange()
assert(config.MacRetinaMode == 0 and configuration.game_settings.MacRetinaMode == 0)
assert(configuration.settingsMenuValues.MacRetinaMode == "Standard")
assert(gamePrompts == 1 and lobbyPrompts == 1) -- No duplicate lobby dialog for a game change.
options.retina:OnChange()
assert(gamePrompts == 1) -- Selecting the same saved mode needs no prompt.
configuration:SetSettingsConfigOption("MacRetinaMode", "Retina text and UI")
widget = {}
dofile("external/chobby/macos/game-data/LuaUI/Widgets/gui_macos_display.lua")
assert(options.retina.value == "1")
assert(lobbyPrompts == 2)
print("PASS: dropdown registration, all modes, persistence, synchronization and restart prompts")
