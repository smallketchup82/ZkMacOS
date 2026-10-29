local file = assert(io.open("external/chobby/LuaMenu/widgets/gui_settings_window.lua"))
local source = file:read("*a")
file:close()
local start = assert(source:find('local function GetTelemetryTabControls()', 1, true))
local finish = assert(source:find('local function GetLobbyTabControls()', start, true))
local controls, config, engine = {}, {}, {}
local Configuration = setmetatable({}, {__index = function(_, key) return config[key] end})
function Configuration:GetFont() return {} end
Button = {New = function(_, value) return value end}
function Configuration:SetConfigValue(key, value) config[key] = value end
WG = {Chobby = {Configuration = Configuration}}
Spring = {SetConfigInt = function(key, value) engine[key] = value end}
function AddCheckboxSetting(offset, caption, key, default, callback, tooltip)
	local control = {checked = config[key] == nil and default or config[key]}
	function control:SetToggle(value)
		if self.checked == value then return end
		self.checked = value
		config[key] = value
		callback(value)
	end
	controls[caption] = control
	return control, offset + 30
end
local block = source:sub(start, finish - 1):gsub("local function GetTelemetryTabControls", "function GetTelemetryTabControls")
local run = assert(loadstring(block .. '\nGetTelemetryTabControls()'))
for _, platform in ipairs({"MacOS", "MacOSX"}) do
	Platform = {osFamily = platform}
	controls, config, engine = {}, {}, {}
	run()
	if platform == "Linux" then
		assert(next(controls) == nil)
	else
		local crash, errors, disable = controls["Automatic Crash Reporting"], controls["Automatic Error Reporting"], controls["Disable All Telemetry"]
		assert(crash and errors and disable)
		for _, name in ipairs({"Replay and game timestamp", "Full logs", "Engine screenshot", "Configuration data"}) do
			assert(controls["Include " .. name] and not controls["Include " .. name].checked)
		end
		assert(crash.checked and not errors.checked and not disable.checked)
		errors:SetToggle(true)
		assert(engine.MacAutomaticErrorReporting == 1 and crash.checked)
		crash:SetToggle(false)
		crash:SetToggle(true)
		assert(engine.MacAutomaticCrashReporting == 1)
		disable:SetToggle(true)
		assert(engine.MacDisableAllTelemetry == 1)
		assert(engine.MacAutomaticCrashReporting == 0 and engine.MacAutomaticErrorReporting == 0)
		assert(not crash.checked and not errors.checked)
		crash:SetToggle(true)
		errors:SetToggle(true)
		assert(not crash.checked and not errors.checked)
		disable:SetToggle(false)
		assert(engine.MacDisableAllTelemetry == 0 and not crash.checked and not errors.checked)
	end
end
print("Lobby telemetry toggles, independence, opt-in defaults and master switch checks passed")
