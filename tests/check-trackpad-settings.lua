-- Run from ZkMacOS with luajit tests/check-trackpad-settings.lua.
local config = {}
Spring = {
	GetConfigInt = function(key, fallback) return config[key] == nil and fallback or config[key] end,
	GetConfigFloat = function(_, fallback) return fallback end,
	SetConfigInt = function(key, value) config[key] = value end,
	SetConfigFloat = function() end,
}
Platform = {osFamily = "MacOS"}
widgetHandler = {RemoveWidget = function() error("unexpected removal") end}

local function loadSettings()
	widget = {}
	dofile("external/chobby/macos/game-data/LuaUI/Widgets/gui_macos_trackpad.lua")
	widget:Initialize()
end

loadSettings()
assert(options.threeFinger.value == false and options.threeFinger.noSave)
options.threeFinger.value = true
options.threeFinger:OnChange()
assert(config.MacTrackpadThreeFingerTilt == 1)
loadSettings()
assert(options.threeFinger.value == true)
options.threeFinger.value = false
options.threeFinger:OnChange()
assert(config.MacTrackpadThreeFingerTilt == 0 and config.MacTrackpadEnabled == 1)
print("PASS: three-finger tilt defaults off, persists both choices, and leaves trackpad controls enabled")
