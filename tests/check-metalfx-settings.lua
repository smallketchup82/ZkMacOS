-- Run from ZkMacOS with luajit tests/check-metalfx-settings.lua.
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
		local setting = assert(names.MacMetalFXSpatial)
		assert(defaults.MacMetalFXSpatial == "Off")
		for index, row in ipairs(settings[1].settings) do
			if row.name == "MacRetinaMode" then assert(settings[1].settings[index + 1] == setting) end
		end
		assert(setting.options[1].apply.MacMetalFXSpatial == 0)
		assert(setting.options[2].apply.MacMetalFXSpatial == 1)
		config.MacMetalFXSpatial = 1
		assert(setting.defaultFunction() == "On")
		config.MacMetalFXSpatial = 0
	else
		assert(not names.MacMetalFXSpatial and not defaults.MacMetalFXSpatial)
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
	listeners = {}, configParamTypes = {MacGPUSharing = "bool", MacRetinaMode = "int", MacMetalFXSpatial = "bool", MacNotchFullscreen = "bool", MacHDR = "bool"},
}, {__index = Configuration})
WG.Chobby.Configuration = configuration

for _, enabled in ipairs({1, 0}) do
	config.MacMetalFXSpatial = enabled
	config.MacNotchFullscreen = enabled
	configuration:SetConfigData({
		game_settings = {MacMetalFXSpatial = 1 - enabled, MacNotchFullscreen = 1 - enabled},
		settingsMenuValues = {MacMetalFXSpatial = enabled == 1 and "Off" or "On", MacNotchFullscreen = enabled == 1 and "Off" or "On"},
	})
	assert(config.MacMetalFXSpatial == enabled)
	assert(config.MacNotchFullscreen == enabled and configuration.game_settings.MacNotchFullscreen == enabled)
	assert(configuration.game_settings.MacMetalFXSpatial == enabled)
	assert(configuration.settingsMenuValues.MacMetalFXSpatial == (enabled == 1 and "On" or "Off"))
end

widget = {}
dofile("external/chobby/LuaMenu/widgets/gui_macos_display.lua")
local lobbyWidget = widget
Spring.SendLuaMenuMsg = function(message) lobbyWidget:RecvLuaMsg(message) end
widgetHandler = {RemoveWidget = function() error("unexpected removal") end}
widget = {}
dofile("external/chobby/macos/game-data/LuaUI/Widgets/gui_macos_display.lua")
widget:Initialize()
assert(options.metalFX.noSave and not options.metalFX.value)
for _, enabled in ipairs({true, false}) do
	options.metalFX.value = enabled
	options.metalFX:OnChange()
	assert(config.MacMetalFXSpatial == (enabled and 1 or 0))
	assert(configuration.settingsMenuValues.MacMetalFXSpatial == (enabled and "On" or "Off"))
end
for _, invalid in ipairs({"macMetalFXSpatial 2", "macMetalFXSpatial 10", "macMetalFXSpatial -1"}) do
	lobbyWidget:RecvLuaMsg(invalid)
	assert(config.MacMetalFXSpatial == 0)
end
assert(prompts == 0, "MetalFX toggles must not request a restart")
print("PASS: lobby and game MetalFX toggle, config authority, persistence, synchronization and platform gating")
