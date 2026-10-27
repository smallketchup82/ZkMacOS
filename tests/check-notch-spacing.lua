-- Run from the workspace root with luajit tests/check-notch-spacing.lua.
local config = {MacNotchFullscreen = 1}
local viewWidth, viewHeight = 1512, 982
local ctrl = false
local notch = {664, 849, 32}
Spring = {
	GetConfigInt = function(key, fallback) return config[key] == nil and fallback or config[key] end,
	GetMacNotchGeometry = function() if notch then return unpack(notch) end end,
	Orig = {GetViewSizes = function() return viewWidth, viewHeight end},
	GetScreenGeometry = function() return 1512, 982 end,
	GetModKeyState = function() return false, ctrl end,
}
local function Control(name, x, width, children)
	return {name = name, x = x, y = 0, width = width, height = 116,
		DrawControl = function() return "original skin" end,
		Invalidate = function() end,
		BringToFront = function() end,
		GetChildByName = function(_, key) return children and children[key] end,
		SetPos = function(self, newX, newY, newWidth, newHeight) self.x = newX or self.x; self.y = newY or self.y; self.width = newWidth or self.width; self.height = newHeight or self.height end,
		SetPosRelative = function(self, x, y, width, height) self.x = x; self.y = y or self.y; self.width = width; self.height = height or self.height end,
	}
end
local metal = Control("Metal", 0, 330)
local energy = Control("Energy", 330, 330)
local metalIcon = Control("metal icon", 0, 56); metalIcon.file = "LuaUI/Images/ibeam.png"
local energyIcon = Control("energy icon", 0, 56); energyIcon.file = "LuaUI/Images/energy.png"
local metalHolder, energyHolder = Control("holder", 0, 270), Control("holder", 0, 270)
local metalFlow, energyFlow = Control("flow", 0, 210), Control("flow", 0, 210)
for _, flow in ipairs({metalFlow, energyFlow}) do
	flow.classname, flow.font, flow.fontOffset = "progressbar", {size = 20}, -2
	flow.height, flow.caption = 16, ">"
end
metalHolder.children, energyHolder.children = {metalFlow}, {energyFlow}
local function Labels()
	local labels = {}
	for i, x in ipairs({59, 145, 231}) do
		local label = Control("resource text", x, 50)
		label.classname, label.caption = "label", ({"500", "+6.0", "-0.0"})[i]
		label.font = {size = 20, color = {0.8, 0.8, 0.8, 1}, GetTextHeight = function(_, _, size) return 0.75 * size, 0 end}
		label.tooltip, label.autosize, label.align, label.valign = "original tooltip", true, "left", "center"
		label.HitTest = function(self) return self end
		label.UpdateLayout = function(self) self._caption = "..." end
		labels[i] = label
	end
	return labels
end
local metalText, energyText = Labels(), Labels()
metal.children = {metalIcon, unpack(metalText)}; energy.children = {energyIcon, unpack(energyText)}
metal.GetObjectByName = function() return {parent = metalHolder} end
energy.GetObjectByName = function() return {parent = energyHolder} end
local main = Control("Main Display", 0, 660, {Metal = metal, Energy = energy})
local originalMetalDraw, originalEnergyDraw = metal.DrawControl, energy.DrawControl
local panel = Control("EconomyPanelDefaultTwo", 426, 660, {["Main Display"] = main})
local strip
WG = {GetFont = function(size) return {size = size} end, GetSpecialFont = function(size, _, settings) return {size = size, color = settings.color, Draw = function(self, caption, x, y) self.lastDraw = {caption, x, y} end} end, uiScale = 1, Chili = {Panel = {New = function(_, properties)
	strip = properties
	function strip:SendToBack() end
	function strip:Dispose() self.disposed = true end
	function strip:SetPos(x,y,w,h) self.x,self.y,self.width,self.height=x,y,w,h end
	return strip
end}, Screen0 = {
	width = 1512, GetChildByName = function(_, name)
		if name == "EconomyPanelDefaultTwo" then return panel end
		if name == "globalCommandsWindow" then return {x = 0, width = 429, height = 38} end
		if name == "epicmenubar" then return {x = 1083, width = 429} end
	end,
}}}
widget = {}
dofile("external/chobby/macos/game-data/LuaUI/Widgets/gui_macos_display.lua")
config.MacNotchFullscreen = 0 -- Native coverage, rather than the saved preference, controls layout.
widget:Update(0.2)
assert(panel.width == 860 and panel.x == 326)
assert(metal.width == 330 and energy.width == 330)
assert(energy.x - metal.x - metal.width == 200)
assert(panel.x + metal.width < 664 and panel.x + energy.x > 849)
assert(panel.y == 0 and panel.height == 116)
assert(metalIcon.width == 28 and energyIcon.height == 28)
assert(metalHolder.width == 210 and energyHolder.height == 16)
assert(metalIcon.y >= 0 and metalIcon.y + metalIcon.height <= 38)
assert(energyHolder.y >= 0 and energyHolder.y + energyHolder.height <= 38)
for _, data in ipairs({{metalText, metalIcon, metalHolder}, {energyText, energyIcon, energyHolder}}) do
	local text, icon, holder = unpack(data)
	assert(text[1].x + text[1].width / 2 == icon.x + icon.width / 2)
	assert(text[2].x + text[2].width / 2 == holder.x + holder.width * 0.25)
	assert(text[3].x + text[3].width / 2 == holder.x + holder.width * 0.75)
	assert(text[1].font.size == 14)
	assert(text[2].font.size == 14 and text[3].font.size == 14)
	assert(text[2].y == holder.y - 1 and text[3].y == holder.y - 1)
	assert(text[1].tooltip == nil and text[1]:HitTest() == nil)
	assert(text[2].caption == "+6.0" and text[3].caption == "-0.0")
	text[3]:UpdateLayout(); assert(text[3]._caption == "-0.0")
	assert(text[2]:HitTest() == text[2]); ctrl = true; assert(text[2]:HitTest() == nil); ctrl = false
end
assert(metalFlow.font.size == 20 and energyFlow.font.size == 20)
metalFlow:DrawControl()
assert(metalFlow.caption == ">")
assert(metalFlow.font.lastDraw[2] == 105.5 and metalFlow.font.lastDraw[3] == 8)
assert(strip.classname == "panel_0001_small" and strip.width == 654)
assert(panel.x + strip.x == 429 and panel.x + strip.x + strip.width == 1083)
assert(metal.DrawControl ~= originalMetalDraw and energy.DrawControl ~= originalEnergyDraw)
widget:Update(0.2); assert(panel.width == 860)
notch = {620, 892, 38} -- A wider camera housing at another display scale/model.
widget:Update(0.2)
assert(energy.x - metal.width == 287)
assert(panel.x + metal.width < 620 and panel.x + energy.x > 892)
notch = {664, 849, 32}
widget:Update(0.2)
local saved = widget:GetConfigData()
-- A preset can recreate the ordinary economy widget using its current width.
panel = Control("EconomyPanelDefaultTwo", 326, 860, {["Main Display"] = main})
widget:Update(0.2); assert(panel.width == 860)
-- Width remembered by the docking widget must not accumulate another gap.
widget:Shutdown()
panel.x, panel.width = 326, 860
widget = {}
dofile("external/chobby/macos/game-data/LuaUI/Widgets/gui_macos_display.lua")
saved.expandedWidth = saved.expandedWidth + 0.0000001 -- Serialized fractional bounds.
widget:SetConfigData(saved)
widget:Update(0.2); assert(panel.width == 860)
notch = nil
viewWidth, viewHeight = 1512, 949 -- Ordinary fullscreen avoids the notch.
widget:Update(0.2)
assert(panel.width == 660 and panel.x == 426)
assert(metal.DrawControl == originalMetalDraw and energy.DrawControl == originalEnergyDraw and strip.disposed)
assert(metalFlow.font.size == 20 and metalFlow.fontOffset == -2)
assert(metalText[1].tooltip == "original tooltip" and metalText[1].font.size == 20)
assert(metal.width == "50%" and energy.width == "50%" and energy.x == "50%")
print("PASS: centered notch gap, unchanged bar dimensions, non-overlapping strip, compact icons/fill bars, quantity/icon overlay, fill-height rate text at 25/75 percent, matching centered arrows, automatic fullscreen detection, tooltip passthrough and restoration")
