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
		SetPos = function(self, newX, newY, newWidth, newHeight)
			self.x, self.y = newX or self.x, newY or self.y
			self.width, self.height = newWidth or self.width, newHeight or self.height
			for _, child in ipairs(self.children or {}) do
				if child.right == 0 then child.width = self.width end
				if child.bottom == 0 then child.height = self.height end
			end
		end,
		SetPosRelative = function(self, x, y, width, height) self.x = x; self.y = y or self.y; self.width = width; self.height = height or self.height end,
	}
end
local metal = Control("Metal", 0, 330)
local energy = Control("Energy", 330, 330)
local metalIcon = Control("metal icon", 0, 56); metalIcon.file = "LuaUI/Images/ibeam.png"
local energyIcon = Control("energy icon", 0, 56); energyIcon.file = "LuaUI/Images/energy.png"
local metalHolder, energyHolder = Control("holder", 0, 270), Control("holder", 0, 270)
local metalFlow, energyFlow = Control("flow", 0, 210), Control("flow", 0, 210)
local energyFill = Control("energy fill", 0, 210)
energyFill.classname, energyFill.font, energyFill.caption = "progressbar", {size = 12}, ""
energyFill.height = 16
energyFill.right, energyFill.bottom = 0, 0
local fillDraws, overlayDraws = 0, 0
energyFill.DrawControl = function() fillDraws = fillDraws + 1 end
energyFlow.noSkin = true
energyFlow.DrawControl = function() overlayDraws = overlayDraws + 1 end
local originalOverlayDraw = energyFlow.DrawControl
for _, flow in ipairs({metalFlow, energyFlow}) do
	flow.classname, flow.font, flow.fontOffset = "progressbar", {size = 20}, -2
	flow.height, flow.caption = 16, ">"
	flow.right, flow.bottom = 0, 0
end
metalHolder.children, energyHolder.children = {metalFlow}, {energyFlow, energyFill}
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
local originalLabelDraw = metalText[2].DrawControl
metal.children = {metalIcon, unpack(metalText)}; energy.children = {energyIcon, unpack(energyText)}
metal.GetObjectByName = function() return {parent = metalHolder} end
energy.GetObjectByName = function() return {parent = energyHolder} end
local main = Control("Main Display", 0, 660, {Metal = metal, Energy = energy})
local originalMetalDraw, originalEnergyDraw = metal.DrawControl, energy.DrawControl
local panel = Control("EconomyPanelDefaultTwo", 426, 660, {["Main Display"] = main})
local strip
WG = {GetFont = function(size) return {size = size} end, GetSpecialFont = function(size, _, settings) return {
	size = size, color = settings.color,
	GetTextHeight = function(self, caption)
		return 0.75 * self.size, caption:find("[<>]") and 0.2 * self.size or 0
	end,
	Draw = function(self, caption, x, y)
		self.lastDraw = {caption, x, y}
		-- Glyph quads cancel the font's global descender in glPrint. The
		-- caption descender leaves half its height above the requested center.
		local _, descender = self:GetTextHeight(caption)
		self.visibleCenterY = y - descender / 2
	end,
} end, uiScale = 1, Chili = {CHILI_DIRNAME = "LuaUI/Widgets/chili_old/", Panel = {New = function(_, properties)
	strip = properties
	strip.padding = strip.padding or {0, 0, 0, 6} -- panel_0001_small's actual skin padding.
	function strip:SendToBack() end
	function strip:Dispose() self.disposed = true end
	function strip:SetPos(x,y,w,h) self.x,self.y,self.width,self.height=x,y,w,h end
	return strip
end}, Screen0 = {
	width = 1512, GetChildByName = function(_, name)
		if name == "EconomyPanelDefaultTwo" then return panel end
		if name == "globalCommandsWindow" then return {x = 0, width = 429, height = 38 / WG.uiScale} end
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
assert(metalHolder.y + metalHolder.height / 2 == 16)
assert(energyHolder.y + energyHolder.height / 2 == 16)
assert(metalIcon.y + metalIcon.height / 2 == 16)
for _, data in ipairs({{metalText, metalIcon, metalHolder}, {energyText, energyIcon, energyHolder}}) do
	local text, icon, holder = unpack(data)
	assert(text[1].x + text[1].width / 2 == icon.x + icon.width / 2)
	assert(text[2].x + text[2].width / 2 == holder.x + holder.width * 0.25)
	assert(text[3].x + text[3].width / 2 == holder.x + holder.width * 0.75)
	assert(text[1].font.size == 14)
	assert(text[2].font.size == 14 and text[3].font.size == 14)
	assert(text[2].y == holder.y and text[3].y == holder.y)
	for _, label in ipairs(text) do
		label:DrawControl()
		assert(math.abs(label.font.visibleCenterY - (label.y + label.height / 2)) < 0.000001)
		assert(label.font.lastDraw[2] == label.x + label.width / 2)
	end
	assert(text[1].tooltip == nil and text[1]:HitTest() == nil)
	assert(text[2].caption == "+6.0" and text[3].caption == "-0.0")
	text[3]:UpdateLayout(); assert(text[3]._caption == "-0.0")
	assert(text[2]:HitTest() == text[2]); ctrl = true; assert(text[2]:HitTest() == nil); ctrl = false
end
assert(metalFlow.font.size == 20 and energyFlow.font.size == 20)
metalFlow:DrawControl()
assert(metalFlow.caption == ">")
assert(metalFlow.font.lastDraw[2] == 105 and metalFlow.font.visibleCenterY == 8)
energyFlow:DrawControl(); energyFill:DrawControl()
assert(overlayDraws == 0 and fillDraws == 1)
assert(energyFlow.caption == ">" and energyFlow.font.visibleCenterY == 8)
assert(strip.classname == "panel_0001_small" and strip.width == 654)
assert(panel.x + strip.x == 429 and panel.x + strip.x + strip.width == 1083)
assert(metal.DrawControl ~= originalMetalDraw and energy.DrawControl ~= originalEnergyDraw)
widget:Update(0.2); assert(panel.width == 860)
for _, renderer in ipairs({"chili_old", "chili"}) do
	WG.Chili.CHILI_DIRNAME = "LuaUI/Widgets/" .. renderer .. "/"
	for _, scale in ipairs({1.25, 2, 1}) do
		WG.uiScale = scale
		widget:Update(0.2)
		local center = (38 / scale - strip.padding[4]) / 2
		for _, data in ipairs({{metalText, metalIcon, metalHolder, metalFlow}, {energyText, energyIcon, energyHolder, energyFlow}}) do
			local text, icon, holder, flow = unpack(data)
			assert(math.abs(holder.y + holder.height / 2 - center) < 0.000001)
			assert(math.abs(icon.y + icon.height / 2 - center) < 0.000001)
			for _, label in ipairs(text) do
				label.caption = "-123.4"
				label:DrawControl()
				-- Chili 2.1 translates the control before drawing; old Chili does not.
				local originX = renderer == "chili" and label.x or 0
				local originY = renderer == "chili" and label.y or 0
				assert(math.abs(originY + label.font.visibleCenterY - center) < 0.000001)
				assert(originX + label.font.lastDraw[2] == label.x + label.width / 2)
			end
			flow:DrawControl()
			assert(math.abs(holder.y + flow.font.visibleCenterY - center) < 0.000001)
		end
	end
end
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
assert(metalText[2].DrawControl == originalLabelDraw and energyFlow.DrawControl == originalOverlayDraw)
energyFlow:DrawControl(); assert(overlayDraws == 1)
assert(metal.width == "50%" and energy.width == "50%" and energy.x == "50%")
print("PASS: old/new Chili text coordinates, notch gap, bar/icon/glyph centers at multiple UI scales, overlay text without a gray rectangle, tooltips and restoration")
