-- Install only in an isolated profile. Records rendered frame intervals, then exits.
function widget:GetInfo()
	return {name = "MetalFX benchmark", desc = "Fixed-camera rendering benchmark",
		author = "OpenAI Codex", license = "GNU GPL v2 or later", layer = 0, enabled = true}
end

local started, lastFrame, finished, selected, captured
local commander, selectionChanges = nil, 0
local frames = {}
local warmup, duration = 15, 30
local replay = Spring.IsReplay()
local replayTarget, seekRequested, replayStartFrame, replayStartUnits, lastSeekRequest
local replayDisplayLink
local GL_VIEWPORT = 0x0BA2
local camera = {mode = 1, px = Game.mapSizeX / 2, py = 0, pz = Game.mapSizeZ / 2,
	height = 2500, angle = 0.6, flipped = 0, fov = 45}

-- Keep incidental clicks and shortcuts from changing the measured scene.
function widget:MousePress() return true end
function widget:MouseRelease() return -1 end
function widget:MouseWheel() return true end
function widget:KeyPress() return true end

local function SeekReplay()
	if not replay or not replayTarget or started then return end
	local now = Spring.GetTimerMicros()
	if lastSeekRequest and Spring.DiffTimers(now, lastSeekRequest, false, true) < 2 then return end
	Spring.SendCommands("skip " .. math.floor(replayTarget / Game.gameSpeed))
	lastSeekRequest = now
	seekRequested = true
	Spring.Echo("[Benchmark replay seek]", replayTarget)
end

function widget:Initialize()
	started = Spring.GetTimerMicros()
	if replay then
		local input = assert(io.open("benchmark_replay_start.txt", "r"))
		replayTarget = assert(tonumber(input:read("*a"))) * Game.gameSpeed
		input:close()
		started = nil
		camera.height = 4000
		replayDisplayLink = Spring.GetConfigInt("MacDisplayLink", 0)
		Spring.SetConfigInt("MacDisplayLink", 0)
		Spring.SendCommands("specfullview 3")
		-- Start only this local replay server, then fast-forward recorded pregame.
		Spring.SendCommands("forcestart")
		SeekReplay()
	end
	Spring.SetCameraState(camera, 0)
end

function widget:Update()
	Spring.SetCameraState(camera, 0)
	if replay then
		SeekReplay()
		if seekRequested and not started and Spring.GetGameFrame() >= replayTarget then
			Spring.SetConfigInt("MacDisplayLink", replayDisplayLink)
			started = Spring.GetTimerMicros()
			Spring.SelectUnitArray({})
			Spring.Echo("[Benchmark selected]", 0)
		end
	elseif not selected and Spring.GetGameFrame() > 30 then
		local units = Spring.GetTeamUnits(Spring.GetMyTeamID())
		if #units > 0 then
			Spring.SelectUnitArray(units)
			commander = units[1]
			Spring.Echo("[Benchmark selected]", #units)
			selected = true
		end
	end
	if commander then
		local units = Spring.GetSelectedUnits()
		if #units ~= 1 or units[1] ~= commander then
			if lastFrame and not finished then selectionChanges = selectionChanges + 1 end
			Spring.SelectUnitArray({commander})
		end
	end
	if finished and not captured then
		Spring.SendCommands("screenshot")
		captured = true
	end
	if finished and Spring.DiffTimers(Spring.GetTimerMicros(), finished, false, true) > 3 then
		Spring.SendCommands("quitforce")
	end
end

function widget:DrawScreen()
	-- DrawScreen also runs while the replay is still showing recorded pregame.
	SeekReplay()
	if finished or not started then return end
	local now = Spring.GetTimerMicros()
	local elapsed = Spring.DiffTimers(now, started, false, true)
	if elapsed < warmup then return end
	if not lastFrame then
		Spring.Echo("[Benchmark viewport]", gl.GetNumber(GL_VIEWPORT, 4))
		if replay then
			replayStartFrame, replayStartUnits = Spring.GetGameFrame(), #Spring.GetAllUnits()
		end
	end
	if lastFrame then
		frames[#frames + 1] = Spring.DiffTimers(now, lastFrame, true, true)
	end
	lastFrame = now
	if elapsed < warmup + duration then return end
	finished = now
	local output = assert(io.open("benchmark_frames.csv", "w"))
	output:write("frame,interval_ms\n")
	for i = 1, #frames do output:write(string.format("%d,%.6f\n", i, frames[i])) end
	output:close()
	Spring.Echo("[Benchmark] completed", #frames, "frames; mode", Spring.GetConfigInt("MacRetinaMode"),
		"MetalFX", Spring.GetConfigInt("MacMetalFXSpatial"), "sharing", Spring.GetConfigInt("MacGPUSharing"))
	Spring.Echo("[Benchmark view]", Spring.GetViewGeometry())
	Spring.Echo("[Benchmark viewport]", gl.GetNumber(GL_VIEWPORT, 4))
	Spring.Echo("[Benchmark minimap]", Spring.GetMiniMapGeometry())
	Spring.Echo("[Benchmark camera]", Spring.GetCameraState().px, Spring.GetCameraState().pz,
		Spring.GetCameraState().height)
	Spring.Echo("[Benchmark selection changes]", selectionChanges)
	Spring.Echo("[Benchmark selected at end]", #Spring.GetSelectedUnits())
	if replay then
		Spring.Echo("[Benchmark replay frames]", replayStartFrame, Spring.GetGameFrame())
		Spring.Echo("[Benchmark replay units]", replayStartUnits, #Spring.GetAllUnits())
	end
end
