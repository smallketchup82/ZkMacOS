-- Run from ZkMacOS with luajit tests/check-gpu-sharing-settings.lua.
local config = {MacRetinaMode = 1}
local prompts = 0
Spring = {
	Orig = {GetViewSizes = function() return 1280, 800 end},
	GetConfigInt = function(key, fallback) return config[key] == nil and fallback or config[key] end,
	SetConfigInt = function(key, value) config[key] = value end,
	SetConfigString = function(key, value) config[key] = tonumber(value) end,
	Echo = function() end,
}
WG = {Chobby = {InformationPopup = function() prompts = prompts + 1 end}}

for _, platform in ipairs({"MacOS", "MacOSX", "Windows", "Linux"}) do
	Platform = {osFamily = platform, gpuVendor = "Test GPU"}
	local settings, names, defaults = dofile("external/chobby/LuaMenu/configs/gameConfig/zk/settingsMenu.lua")
	if platform == "MacOS" or platform == "MacOSX" then
		local setting = assert(names.MacGPUSharing)
		assert(defaults.MacGPUSharing == "Off")
		for index, row in ipairs(settings[1].settings) do
			if row.name == "MacHDR" then assert(settings[1].settings[index + 1] == setting) end
		end
		assert(setting.options[1].apply.MacGPUSharing == 0)
		assert(setting.options[2].apply.MacGPUSharing == 1)
		config.MacGPUSharing = 1
		assert(setting.defaultFunction() == "On")
		config.MacGPUSharing = 0
	else
		assert(not names.MacGPUSharing and not defaults.MacGPUSharing)
	end
end

-- Load the real configuration methods so a stale lobby save cannot overwrite
-- a manually edited engine setting on startup.
LCS = {class = function() return setmetatable({}, {__call = function(self) return self end}) end}
LUA_DIRNAME = "LuaMenu/"
VFS = {Include = function(path)
	if path:find("springsettingsChanges.lua", 1, true) then return {}, {}, {}, {}, 1 end
end}
dofile("external/chobby/LuaMenu/widgets/chobby/components/configuration.lua")
Platform = {osFamily = "MacOS", gpuVendor = "Test GPU"}
local _, names = dofile("external/chobby/LuaMenu/configs/gameConfig/zk/settingsMenu.lua")
local configuration = setmetatable({
	gameConfig = {settingsNames = names}, noNaiveConfigOverride = {settingsMenuValues = true},
	channels = {}, game_settings = {}, settingsMenuValues = {},
	listeners = {}, configParamTypes = {MacHDR = "bool", MacRetinaMode = "int", MacGPUSharing = "bool", MacNotchFullscreen = "bool", MacMetalFXSpatial = "bool", MacDisplayLink = "bool"},
}, {__index = Configuration})
WG.Chobby.Configuration = configuration

for _, enabled in ipairs({1, 0}) do
	config.MacGPUSharing = enabled
	config.MacNotchFullscreen = enabled
	configuration:SetConfigData({
		game_settings = {MacGPUSharing = 1 - enabled, MacNotchFullscreen = 1 - enabled},
		settingsMenuValues = {MacGPUSharing = enabled == 1 and "Off" or "On", MacNotchFullscreen = enabled == 1 and "Off" or "On"},
	})
	assert(config.MacGPUSharing == enabled)
	assert(config.MacNotchFullscreen == enabled and configuration.game_settings.MacNotchFullscreen == enabled)
	assert(configuration.game_settings.MacGPUSharing == enabled)
	assert(configuration.settingsMenuValues.MacGPUSharing == (enabled == 1 and "On" or "Off"))
end

widget = {}
dofile("external/chobby/LuaMenu/widgets/gui_macos_display.lua")
local lobbyWidget = widget
Spring.SendLuaMenuMsg = function(message) lobbyWidget:RecvLuaMsg(message) end
widgetHandler = {RemoveWidget = function() error("unexpected removal") end}
widget = {}
dofile("external/chobby/macos/game-data/LuaUI/Widgets/gui_macos_display.lua")
widget:Initialize()
assert(options.gpuSharing.noSave and not options.gpuSharing.value)
for _, enabled in ipairs({true, false}) do
	options.gpuSharing.value = enabled
	options.gpuSharing:OnChange()
	assert(config.MacGPUSharing == (enabled and 1 or 0))
	assert(configuration.settingsMenuValues.MacGPUSharing == (enabled and "On" or "Off"))
end
for _, invalid in ipairs({"macGPUSharing 2", "macGPUSharing 10", "macGPUSharing -1"}) do
	lobbyWidget:RecvLuaMsg(invalid)
	assert(config.MacGPUSharing == 0)
end
assert(prompts == 0, "GPU sharing toggles must not request a restart")
print("PASS: lobby and game GPU sharing toggle, config authority, persistence, synchronization and platform gating")
