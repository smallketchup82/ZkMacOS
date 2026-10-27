-- Run with luajit tests/check-notch-settings.lua.
-- Setting is opt-in and only registered on macOS; selecting it requests restart.
Platform = {}
Spring = {}
WG = {}
local config, prompts = {MacNotchFullscreen = 0}, 0
Spring.Orig = {GetViewSizes = function() return 1280, 800 end}
Spring.GetConfigInt = function(key, fallback) return config[key] == nil and fallback or config[key] end
Spring.SetConfigInt = function(key, value) config[key] = value end
Spring.Echo = function() end
WG.Chobby = {InformationPopup = function() prompts = prompts + 1 end}
for _, platform in ipairs({"MacOS", "MacOSX", "Windows", "Linux"}) do
	Platform.osFamily = platform
	local _, names, defaults = dofile("external/chobby/LuaMenu/configs/gameConfig/zk/settingsMenu.lua")
	if platform == "MacOS" or platform == "MacOSX" then
		local setting = assert(names.MacNotchFullscreen)
		assert(defaults.MacNotchFullscreen == "Off")
		assert(setting.options[1].applyFunction().MacNotchFullscreen == 0)
		assert(setting.options[2].applyFunction().MacNotchFullscreen == 1)
	else
		assert(not names.MacNotchFullscreen and not defaults.MacNotchFullscreen)
	end
end
assert(prompts == 2)
-- In-game setting persists and synchronizes without duplicate lobby prompts.
Platform.osFamily = "MacOS"
local _, names = dofile("external/chobby/LuaMenu/configs/gameConfig/zk/settingsMenu.lua")
local selected
WG.Chobby.Configuration = {gameConfig = {settingsNames = names}, SetSettingsConfigOption = function(_, key, label)
	selected = label
	local apply = names[key].optionNames[label].applyFunction()
	Spring.SetConfigInt(key, apply[key])
end}
widget = {}
dofile("external/chobby/LuaMenu/widgets/gui_macos_display.lua")
local lobby = widget
Spring.SendLuaMenuMsg = function(message) lobby:RecvLuaMsg(message) end
local gamePrompts = 0
WG.Chili = {
	Window = {New = function() gamePrompts = gamePrompts + 1; return {Dispose = function() end} end},
	TextBox = {New = function() end}, Button = {New = function() end},
}
widget = {}
dofile("external/chobby/macos/game-data/LuaUI/Widgets/gui_macos_display.lua")
assert(options.notch.noSave and not options.notch.value)
for _, enabled in ipairs({true, false}) do
	options.notch.value = enabled; options.notch:OnChange()
	assert(config.MacNotchFullscreen == (enabled and 1 or 0))
	assert(selected == (enabled and "On" or "Off"))
end
options.notch:OnChange()
assert(gamePrompts == 2 and prompts == 2)
lobby:RecvLuaMsg("macNotchFullscreen 2")
assert(config.MacNotchFullscreen == 0)
print("PASS: notchful fullscreen is opt-in, platform-gated, persistent and synchronized with restart prompts")
