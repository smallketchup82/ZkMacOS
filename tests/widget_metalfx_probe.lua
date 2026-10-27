-- Optional test widget: copy only into an isolated test profile's LuaUI/Widgets.
function widget:GetInfo()
	return {name = "MetalFX validation probe", desc = "Exercises live MetalFX toggles and resizing, then exits",
		author = "OpenAI Codex", license = "GNU GPL v2 or later", layer = 0, enabled = true}
end

local started, previous, stage

function widget:Initialize()
	started = Spring.GetTimer()
	previous = Spring.GetConfigInt("MacMetalFXSpatial", 0)
	stage = 0
	Spring.SetConfigInt("MacMetalFXSpatial", 1)
	Spring.Echo("[MetalFX probe] enabled; Retina mode", Spring.GetConfigInt("MacRetinaMode", 1))
end

function widget:Update()
	local elapsed = Spring.DiffTimers(Spring.GetTimer(), started)
	if stage == 0 and elapsed > 3 then
		Spring.SendCommands("screenshot")
		stage = 1
	elseif stage == 1 and elapsed > 5 then
		Spring.SetConfigInt("MacMetalFXSpatial", 0)
		Spring.Echo("[MetalFX probe] disabled")
		stage = 2
	elseif stage == 2 and elapsed > 7 then
		Spring.SendCommands("screenshot")
		stage = 3
	elseif stage == 3 and elapsed > 8 then
		Spring.SetConfigInt("MacMetalFXSpatial", 1)
		Spring.SetConfigInt("XResolutionWindowed", 1023)
		Spring.SetConfigInt("YResolutionWindowed", 701)
		Spring.Echo("[MetalFX probe] reenabled; resize to 1023x701")
		stage = 4
	elseif stage == 4 and elapsed > 15 then
		Spring.SendCommands("screenshot")
		Spring.Echo("[MetalFX probe] completed live toggle and resize sequence")
		stage = 5
	elseif stage == 5 and elapsed > 20 then
		Spring.SendCommands("quitforce")
		stage = 6
	end
end

function widget:Shutdown()
	if previous then Spring.SetConfigInt("MacMetalFXSpatial", previous) end
end
