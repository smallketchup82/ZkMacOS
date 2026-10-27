-- Run from ZkMacOS with luajit tests/check-settings.lua.
local mode, prompts = 1, 0
Spring = {
	Orig = {GetViewSizes = function() return 1488, 813 end},
	GetConfigInt = function(_, fallback) return mode or fallback end,
	Echo = function() end,
	Utilities = {MergeTable = function(first, second)
		local merged = {}
		for key, value in pairs(second) do merged[key] = value end
		for key, value in pairs(first) do merged[key] = value end
		return merged
	end},
}
WG = {Chobby = {InformationPopup = function() prompts = prompts + 1 end}}

for _, platform in ipairs({"MacOS", "MacOSX", "Windows", "Linux"}) do
	Platform = {osFamily = platform, gpuVendor = "Test GPU"}
	local config, names, defaults, defaultPreset = dofile((arg[1] or "external/chobby") .. "/LuaMenu/configs/gameConfig/zk/settingsMenu.lua")
	if platform == "MacOS" or platform == "MacOSX" then
		assert(not names.VSync and not defaults.VSync)
		local retina = assert(names.MacRetinaMode)
		assert(retina.defaultFunction() == "Retina text and UI")
		for index, setting in ipairs(config[1].settings) do
			if setting.name == "ActiveGraphicsLabel" then assert(config[1].settings[index + 1] == retina) end
		end
		for _, preset in ipairs(config[1].presets) do assert(not preset.settings.VSync) end
		for _, memory in ipairs({0, 512*1024, 4096*1024}) do
			Platform.gpuMemorySize = memory
			local selected = defaultPreset()
			for key, value in pairs(config[1].presets[3].settings) do
				assert(selected[key] == value, "macOS should default to Low: " .. key)
			end
		end
		local previousPrompts = prompts
		assert(retina.options[2].applyFunction().MacRetinaMode == 1 and prompts == previousPrompts)
		assert(retina.options[3].applyFunction().MacRetinaMode == 2 and prompts == previousPrompts + 1)
	else
		assert(names.VSync and defaults.VSync and not names.MacRetinaMode)
		Platform.gpuMemorySize = 4096*1024
		assert(defaultPreset().ShaderDetail == "High")
	end
end
print("PASS: macOS Retina, restart notice, VSync removal and Low default; Windows/Linux controls and automatic presets preserved")
