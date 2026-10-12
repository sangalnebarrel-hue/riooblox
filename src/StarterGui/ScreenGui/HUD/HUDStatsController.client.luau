local Players = game:GetService("Players")

local player = Players.LocalPlayer
local hud = script.Parent


-- =========================================================
-- NUMBER FORMAT
-- =========================================================

local function formatNumber(number)
	number = math.floor(tonumber(number) or 0)

	local formatted = tostring(number)

	while true do
		local newFormatted, replacements = formatted:gsub(
			"^(-?%d+)(%d%d%d)",
			"%1,%2"
		)

		formatted = newFormatted

		if replacements == 0 then
			break
		end
	end

	return formatted
end


-- =========================================================
-- XP WIDGET
-- =========================================================

local xpWidget = hud:WaitForChild("XPWidget")
local xpMain = xpWidget:WaitForChild("Main")

local levelLabel = xpMain:WaitForChild("LevelLabel")
local xpText = xpMain:WaitForChild("XPText")

local xpBarBackground = xpMain:WaitForChild("XPBarBackground")
local xpFill = xpBarBackground:WaitForChild("Fill")


local function updateXP()
	local level = player:GetAttribute("Level") or 1
	local xp = player:GetAttribute("XP") or 0
	local xpRequired = player:GetAttribute("XPRequired") or 1

	-- Не даём делить на 0
	if xpRequired <= 0 then
		xpRequired = 1
	end

	levelLabel.Text = "LV. " .. tostring(level)

	xpText.Text =
		formatNumber(xp)
		.. " / "
		.. formatNumber(xpRequired)
		.. " XP"

	local progress = math.clamp(xp / xpRequired, 0, 1)

	xpFill.Size = UDim2.new(
		progress,
		0,
		1,
		0
	)
end


-- =========================================================
-- GLOBAL DIG WIDGET
-- =========================================================

local globalDigWidget = hud:WaitForChild("GlobalDigWidget")
local globalMain = globalDigWidget:WaitForChild("Main")

local globalProgressText = globalMain:WaitForChild("ProgressText")

local globalBarBackground =
	globalMain:WaitForChild("ProgressBarBackground")

local globalFill =
	globalBarBackground:WaitForChild("Fill")


local GLOBAL_MILESTONES = {
	500,
	2500,
	10000,
	50000,
	200000
}


local function getNextGlobalMilestone(total)
	for _, milestone in ipairs(GLOBAL_MILESTONES) do
		if total < milestone then
			return milestone
		end
	end

	return nil
end


local function updateGlobalDig()
	local total =
		player:GetAttribute("GlobalDigTotal") or 0

	local nextMilestone =
		getNextGlobalMilestone(total)

	if nextMilestone then

		globalProgressText.Text =
			formatNumber(total)
			.. " / "
			.. formatNumber(nextMilestone)

		local progress =
			math.clamp(
				total / nextMilestone,
				0,
				1
			)

		globalFill.Size = UDim2.new(
			progress,
			0,
			1,
			0
		)

	else

		globalProgressText.Text =
			formatNumber(total)
			.. " COMPLETE"

		globalFill.Size = UDim2.new(
			1,
			0,
			1,
			0
		)

	end
end


-- =========================================================
-- INITIAL UPDATE
-- =========================================================

updateXP()
updateGlobalDig()


-- =========================================================
-- ATTRIBUTE LISTENERS
-- =========================================================

player:GetAttributeChangedSignal("Level"):Connect(updateXP)

player:GetAttributeChangedSignal("XP"):Connect(updateXP)

player:GetAttributeChangedSignal("XPRequired"):Connect(updateXP)

player:GetAttributeChangedSignal("GlobalDigTotal"):Connect(
	updateGlobalDig
)

-- =========================================================
-- INCOME CHIP
-- "+$X/min" from the server's income model (player attribute IncomePerMinute, the same number
-- as the Yard card and offline earnings) and the discovery storage state ("FINDS FULL · SELL").
-- Built at runtime, it localizes itself (NoTranslate) and sits next to the counters that
-- UITheme.LayoutHUD places: right of the XP row on desktop, in the free row under XP on touch.
-- =========================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local IncomeText = require(ReplicatedStorage:WaitForChild("DogEconomy"):WaitForChild("IncomeText"))
local screen = hud:FindFirstAncestorWhichIsA("ScreenGui")
local moneyWidget = hud:WaitForChild("MoneyWidget")
local NAVY = Color3.fromRGB(23, 43, 76)

local chip = Instance.new("Frame")
chip.Name = "IncomeChip"
chip.BackgroundTransparency = 1
chip.AnchorPoint = Vector2.new(0, 1)
chip.Size = UDim2.fromOffset(300, 32)
chip.Visible = false
chip:SetAttribute("NoTranslate", true)
local chipScale = Instance.new("UIScale")
chipScale.Parent = chip
local row = Instance.new("UIListLayout")
row.FillDirection = Enum.FillDirection.Horizontal
row.VerticalAlignment = Enum.VerticalAlignment.Center
row.Padding = UDim.new(0, 8)
row.SortOrder = Enum.SortOrder.LayoutOrder
row.Parent = chip

local function stroke(parent, thickness)
	local s = Instance.new("UIStroke")
	s.Color = NAVY
	s.Thickness = thickness
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local rateButton = Instance.new("TextButton")
rateButton.Name = "Rate"
rateButton.LayoutOrder = 1
rateButton.AutoButtonColor = false
rateButton.BackgroundTransparency = 1
rateButton.AutomaticSize = Enum.AutomaticSize.X
rateButton.Size = UDim2.fromOffset(0, 32)
rateButton.Font = Enum.Font.FredokaOne
rateButton.TextSize = 25
rateButton.TextColor3 = Color3.fromRGB(132, 255, 57)
rateButton.TextXAlignment = Enum.TextXAlignment.Left
rateButton.Text = ""
stroke(rateButton, 2)
rateButton.Parent = chip

local fullButton = Instance.new("TextButton")
fullButton.Name = "FindsFull"
fullButton.LayoutOrder = 2
fullButton.AutoButtonColor = false
fullButton.AutomaticSize = Enum.AutomaticSize.X
fullButton.Size = UDim2.fromOffset(0, 26)
fullButton.BackgroundColor3 = Color3.fromRGB(247, 73, 112)
fullButton.Font = Enum.Font.FredokaOne
fullButton.TextSize = 15
fullButton.TextColor3 = Color3.new(1, 1, 1)
fullButton.Text = ""
fullButton.Visible = false
local fullCorner = Instance.new("UICorner")
fullCorner.CornerRadius = UDim.new(0, 9)
fullCorner.Parent = fullButton
local fullPadding = Instance.new("UIPadding")
fullPadding.PaddingLeft = UDim.new(0, 10)
fullPadding.PaddingRight = UDim.new(0, 10)
fullPadding.Parent = fullButton
stroke(fullButton, 2).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
fullButton.Parent = chip
chip.Parent = hud

-- Taps: a full finds storage guides the player home to sell; otherwise open MY YARD.
local function navigation()
	local modules = screen and screen:FindFirstChild("Modules")
	local module = modules and modules:FindFirstChild("GUIIntegration")
	if not module then return nil end
	local ok, nav = pcall(require, module)
	return ok and nav or nil
end
local function itemsFull()
	local count, capacity = player:GetAttribute("ItemCount"), player:GetAttribute("ItemCapacity")
	return type(count) == "number" and type(capacity) == "number" and capacity > 0 and count >= capacity
end
local function tapped()
	local nav = navigation()
	if not nav then return end
	if itemsFull() then
		pcall(nav.Notify, IncomeText.Get("SellTip"))
		pcall(nav.Navigate, "Your yard")
	else
		pcall(nav.OpenPage, "Yard")
	end
end
rateButton.Activated:Connect(tapped)
fullButton.Activated:Connect(tapped)

-- The rate counts toward its new value instead of jumping.
local shownRate, rateFrom, rateTarget, rateStart = 0, 0, 0, 0
local rateConnection = nil
local function renderRate(value)
	rateButton.Text = IncomeText.PerMinute(value)
end
local pulse = nil
local function refreshChip()
	local income = math.max(0, tonumber(player:GetAttribute("IncomePerMinute")) or 0)
	local full = itemsFull()
	fullButton.Text = IncomeText.Get("ItemsFull")
	fullButton.Visible = full
	rateButton.Visible = income > 0
	chip.Visible = income > 0 or full
	if full and not pulse and player:GetAttribute("ReducedMotion") ~= true then
		pulse = TweenService:Create(fullButton, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.35 })
		pulse:Play()
	elseif not full and pulse then
		pulse:Cancel()
		pulse = nil
		fullButton.BackgroundTransparency = 0
	end
	if income == rateTarget then return end
	rateFrom, rateTarget, rateStart = shownRate, income, os.clock()
	if shownRate == 0 or player:GetAttribute("ReducedMotion") == true then
		shownRate = income
		renderRate(income)
		return
	end
	if rateConnection then return end
	rateConnection = RunService.Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - rateStart) / 0.5, 0, 1)
		shownRate = rateFrom + (rateTarget - rateFrom) * (1 - (1 - t) ^ 3)
		if t >= 1 then
			shownRate = rateTarget
			rateConnection:Disconnect()
			rateConnection = nil
		end
		renderRate(shownRate)
	end)
end

-- Placement follows the counters (UITheme.LayoutHUD positions them; all anchored bottom-left).
local function widgetScale(widget)
	local s = widget and widget:FindFirstChildWhichIsA("UIScale")
	return s and s.Scale or 1
end
local function placeChip()
	local xp = hud:FindFirstChild("XPWidget")
	if not xp or not screen then return end
	local dig = hud:FindFirstChild("GlobalDigWidget")
	local f = widgetScale(moneyWidget)
	chipScale.Scale = f
	local xpX, xpY = xp.Position.X.Offset, xp.Position.Y.Offset
	local innerLeft = screen:GetAttribute("HUDInnerLeft") or 12
	local innerRight = screen:GetAttribute("HUDInnerRight") or (screen.AbsoluteSize.X - 12)
	local width = math.max(1, chip.AbsoluteSize.X / math.max(0.01, chipScale.Scale))
	local x, y
	if xpY > moneyWidget.Position.Y.Offset then
		-- Touch: counters stack downward from the top of the free zone; take the next row.
		local below = (dig and dig.Visible) and dig or xp
		x, y = xpX, below.Position.Y.Offset + 4 * f + 32 * f
		-- The map marker button shares that zone while a route is shown.
		local guide = screen:FindFirstChild("DistrictGuide")
		local clear = guide and guide:FindFirstChild("ClearMarker")
		if clear and clear:IsA("GuiObject") and clear.Visible and clear.AbsoluteSize.Y > 0 then
			local clearTop = clear.AbsolutePosition.Y - hud.AbsolutePosition.Y
			if y > clearTop - 2 then y = math.max(y, clearTop + clear.AbsoluteSize.Y + 4 + 32 * f) end
		end
	else
		-- Desktop: same row as the XP counter, to its right; above it if the row is too narrow.
		x, y = xpX + 330 * f, xpY
		if x + width * f > innerRight - 8 then
			x, y = math.max(xpX, innerLeft), xpY - 36 * f
		end
	end
	chip.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

for _, attribute in ipairs({ "IncomePerMinute", "ItemCount", "ItemCapacity", "ItemFull" }) do
	player:GetAttributeChangedSignal(attribute):Connect(refreshChip)
end
local xpWidgetForChip = hud:WaitForChild("XPWidget")
xpWidgetForChip:GetPropertyChangedSignal("Position"):Connect(placeChip)
moneyWidget:GetPropertyChangedSignal("Position"):Connect(placeChip)
chip:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeChip)
if screen then
	screen:GetAttributeChangedSignal("HUDInnerRight"):Connect(placeChip)
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeChip)
	local guide = screen:FindFirstChild("DistrictGuide")
	local clear = guide and guide:FindFirstChild("ClearMarker")
	if clear then clear:GetPropertyChangedSignal("Visible"):Connect(placeChip) end
end
task.defer(function()
	local s = moneyWidget:FindFirstChildWhichIsA("UIScale")
	if s then s:GetPropertyChangedSignal("Scale"):Connect(placeChip) end
	placeChip()
end)
refreshChip()
placeChip()