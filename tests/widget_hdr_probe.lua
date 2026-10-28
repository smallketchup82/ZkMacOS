-- Install only in an isolated profile. Exercises HDR rendering and exits.
function widget:GetInfo()
	return {name = "macOS HDR validation probe", desc = "HDR display output, GPU sharing, viewport and resize validation",
		author = "OpenAI Codex", license = "GNU GPL v2 or later", layer = 0, enabled = true}
end

local started, stage, previous, previousFX
local viewportStage = -1
local frames = {}
local copyTexture, copiedStage

function widget:Initialize()
	started, stage = Spring.GetTimerMicros(), 0
	previous = Spring.GetConfigInt("MacHDR", 0)
	previousFX = Spring.GetConfigInt("MacMetalFXSpatial", 0)
	Spring.SetConfigInt("MacHDR", 1)
	Spring.SetCameraState({mode = 1, px = Game.mapSizeX / 2, py = 0, pz = Game.mapSizeZ / 2,
		height = 2500, angle = 0.6, flipped = 0, fov = 45}, 0)
	Spring.Echo("[HDR probe] started; Retina mode", Spring.GetConfigInt("MacRetinaMode"))
end

function widget:DrawScreenEffects()
	-- Exercise screen copies without adding visible test graphics to the world.
	gl.PushAttrib(GL.ALL_ATTRIB_BITS)
	if copiedStage ~= stage then
		copyTexture = copyTexture or gl.CreateTexture(32, 32, {format = 0x881A, min_filter = GL.LINEAR, mag_filter = GL.LINEAR})
		if copyTexture then gl.CopyToTexture(copyTexture, 0, 0, 0, 0, 32, 32) end
		copiedStage = stage
		Spring.Echo("[HDR world screen copy]", stage)
	end
	gl.PopAttrib()
end

function widget:DrawScreen()
	if viewportStage ~= stage then
		Spring.Echo("[HDR viewport]", stage, gl.GetNumber(0x0BA2, 4))
		Spring.Echo("[HDR framebuffer]", stage, gl.GetNumber(0x8CA6))
		viewportStage = stage
	end
	local now = Spring.GetTimerMicros()
	local elapsed = Spring.DiffTimers(now, started, false, true)
	if elapsed >= 2 and elapsed < 5 then frames[#frames + 1] = now end
end

function widget:Update()
	local elapsed = Spring.DiffTimers(Spring.GetTimerMicros(), started, false, true)
	if stage == 0 and elapsed > 5 then
		Spring.SendCommands("screenshot")
		Spring.SetConfigInt("MacHDR", 0)
		Spring.Echo("[HDR probe] disabled; CPU presentation fallback")
		stage = 1
	elseif stage == 1 and elapsed > 8 then
		Spring.SendCommands("screenshot")
		Spring.SetConfigInt("MacHDR", 1)
		Spring.SetConfigInt("MacMetalFXSpatial", 1)
		Spring.SetConfigInt("XResolutionWindowed", 1023)
		Spring.SetConfigInt("YResolutionWindowed", 701)
		Spring.Echo("[HDR probe] reenabled with MetalFX; resize to 1023x701")
		stage = 2
	elseif stage == 2 and elapsed > 13 then
		Spring.SendCommands("screenshot")
		Spring.SetConfigInt("MacMetalFXSpatial", 0)
		Spring.SetConfigInt("XResolutionWindowed", 1101)
		Spring.SetConfigInt("YResolutionWindowed", 733)
		stage = 3
	elseif stage == 3 and elapsed > 18 then
		Spring.Echo("[HDR minimap]", Spring.GetMiniMapGeometry())
		Spring.SendCommands("screenshot")
		Spring.Echo("[HDR probe] completed toggle, MetalFX, resize and screenshot sequence")
		if #frames > 1 then
			local duration = Spring.DiffTimers(frames[#frames], frames[1], false, true)
			Spring.Echo("[HDR probe FPS]", (#frames - 1) / duration)
		end
		stage = 4
	elseif stage == 4 and elapsed > 21 then
		Spring.SendCommands("quitforce")
		stage = 5
	end
end

function widget:Shutdown()
	if copyTexture then gl.DeleteTexture(copyTexture) end
	if previous then Spring.SetConfigInt("MacHDR", previous) end
	if previousFX then Spring.SetConfigInt("MacMetalFXSpatial", previousFX) end
end
