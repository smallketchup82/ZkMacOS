-- Install only in an isolated profile; captures the same map edge in SDR/HDR.
function widget:GetInfo()
	return {name = "HDR map edge validation", desc = "Compares mirrored map-edge fading, then exits",
		author = "OpenAI Codex", license = "GNU GPL v2 or later", layer = 0, enabled = true}
end

local started, stage = nil, 0
local configured = false
local camera = {mode = 1, px = Game.mapSizeX - 100, py = 0, pz = Game.mapSizeZ / 2,
	height = 2800, angle = 0.6, flipped = 0, fov = 45}

function widget:Initialize()
	Spring.SetConfigInt("MacHDR", 0)
	Spring.SetCameraState(camera, 0)
end

function widget:DrawScreen()
	started = started or Spring.GetTimer()
end

function widget:Update()
	Spring.SetCameraState(camera, 0)
	if not started then return end
	if not configured and WG.SetWidgetOption then
		WG.SetWidgetOption("Map Edge Extension", "Settings/Graphics/Map Exterior", "mapBorderStyle", "grid")
		WG.SetWidgetOption("Map Edge Extension", "Settings/Graphics/Map Exterior", "useShader", true)
		local option = WG.GetWidgetOption("Map Edge Extension", "Settings/Graphics/Map Exterior", "mapBorderStyle")
		assert(option.value == "grid", "Map edge grid setting is unavailable")
		Spring.Echo("[Map edge probe] grid configured", option.value)
		configured = true
	end
	local elapsed = Spring.DiffTimers(Spring.GetTimer(), started)
	if stage == 0 and elapsed > 2 then
		Spring.SendCommands("screenshot")
		Spring.Echo("[Map edge probe] captured SDR")
		stage = 1
	elseif stage == 1 and elapsed > 3 then
		Spring.SetConfigInt("MacHDR", 1)
		stage = 2
	elseif stage == 2 and elapsed > 6 then
		Spring.SendCommands("screenshot")
		Spring.Echo("[Map edge probe] captured HDR")
		stage = 3
	elseif stage == 3 and elapsed > 8 then
		Spring.Echo("[Map edge probe] completed")
		Spring.SendCommands("quitforce")
		stage = 4
	end
end
