local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local Price = require(ReplicatedStorage:WaitForChild("PriceFormat"))

local player = Players.LocalPlayer
local moneyWidget = script.Parent
local main = moneyWidget:WaitForChild("Main")
local amountLabel = main:WaitForChild("Amount")
local screen = moneyWidget:FindFirstAncestorWhichIsA("ScreenGui")
local leaderstats = player:WaitForChild("leaderstats")
local coins = leaderstats:WaitForChild("Coins")

local textLimit = amountLabel:FindFirstChildWhichIsA("UITextSizeConstraint")
if not textLimit then
	textLimit = Instance.new("UITextSizeConstraint")
	textLimit.Name = "FullWalletTextLimit"
	textLimit.Parent = amountLabel
end
textLimit.MinTextSize = 12
textLimit.MaxTextSize = 40

local layoutQueued = false
local function layoutAmount()
	-- The shared HUD retains its 320-pixel anchor. Expand the text alone so the
	-- full wallet can grow left on touch screens without pushing beyond the edge.
	local scale = 1
	local ancestor = main
	while ancestor and ancestor ~= screen do
		local uiScale = ancestor:FindFirstChildWhichIsA("UIScale")
		if uiScale then scale *= uiScale.Scale end
		ancestor = ancestor.Parent
	end
	scale = math.max(0.01, scale)
	local viewportWidth = screen and screen.AbsoluteSize.X or 800
	-- UITheme.LayoutHUD publishes which way the wallet may grow and its right limit
	-- (the free zone between the HUD button columns, in ScreenGui pixels).
	local growLeft = moneyWidget:GetAttribute("HUDGrowLeft")
	if growLeft == nil then growLeft = UserInputService.TouchEnabled end
	local maxRight = moneyWidget:GetAttribute("HUDMaxRight")
	local availablePixels
	if growLeft then
		availablePixels = math.min(viewportWidth - 28, main.AbsolutePosition.X + main.AbsoluteSize.X - 14)
	elseif type(maxRight) == "number" and screen then
		availablePixels = screen.AbsolutePosition.X + maxRight - main.AbsolutePosition.X
	else
		availablePixels = viewportWidth - main.AbsolutePosition.X - 18
	end
	local measured = TextService:GetTextSize(amountLabel.Text, 40, Enum.Font.FredokaOne, Vector2.new(10000, 46))
	local preferredWidth = math.max(320, math.ceil(measured.X * 1.06) + 16)
	local width = math.floor(math.min(preferredWidth, math.max(1, availablePixels) / scale) * 4) / 4
	local anchor = Vector2.new(growLeft and 1 or 0, 0)
	local position = UDim2.new(growLeft and 1 or 0, 0, 0, 0)
	local alignment = growLeft and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
	-- Do not rewrite watched properties on every fit. Roblox may signal a write
	-- even when its value is equivalent, causing an unbounded deferred reflow.
	if main.ClipsDescendants then main.ClipsDescendants = false end
	if moneyWidget.ClipsDescendants then moneyWidget.ClipsDescendants = false end
	if amountLabel.AnchorPoint ~= anchor then amountLabel.AnchorPoint = anchor end
	if amountLabel.Position ~= position then amountLabel.Position = position end
	local size = amountLabel.Size
	if size.X.Scale ~= 0 or size.Y.Scale ~= 0 or math.abs(size.X.Offset - width) > 0.2 or size.Y.Offset ~= 46 then
		amountLabel.Size = UDim2.fromOffset(width, 46)
	end
	if amountLabel.TextXAlignment ~= alignment then amountLabel.TextXAlignment = alignment end
	if amountLabel.TextWrapped then amountLabel.TextWrapped = false end
	-- Roblox constraints must fit the rendered height, including the HUD scale.
	-- A fixed 28px minimum cannot fit the 22px-tall portrait wallet.
	local maxText = math.max(12, math.min(40, math.floor(46 * scale * 0.82)))
	if textLimit.MinTextSize ~= 12 then textLimit.MinTextSize = 12 end
	if textLimit.MaxTextSize ~= maxText then textLimit.MaxTextSize = maxText end
	if not amountLabel.TextScaled then amountLabel.TextScaled = true end
	if amountLabel.TextTruncate ~= Enum.TextTruncate.None then amountLabel.TextTruncate = Enum.TextTruncate.None end
end

local function queueLayout()
	if layoutQueued then return end
	layoutQueued = true
	task.defer(function()
		if moneyWidget.Parent then layoutAmount() end
		-- Keep this guard set while layoutAmount changes its own watched values.
		layoutQueued = false
	end)
end

-- Match every purchase/sale price: commas, all digits, no K/M/B suffixes.
local shown = coins.Value
local function render(value)
	local text = "$" .. Price.Number(value)
	if amountLabel.Text ~= text then
		amountLabel.Text = text
		queueLayout()
	end
end

-- Income counts up smoothly (dog income arrives every few seconds); spending and big
-- jumps from far below snap, so prices and purchases always read exactly.
local rolling, from, target, startedAt, duration = nil, 0, 0, 0, 0
local function stopRolling()
	if rolling then
		rolling:Disconnect()
		rolling = nil
	end
end
local function updateMoney()
	local value = coins.Value
	if value <= shown or player:GetAttribute("ReducedMotion") == true then
		stopRolling()
		shown = value
		render(value)
		return
	end
	from, target, startedAt = shown, value, os.clock()
	duration = math.clamp(0.25 + 0.12 * math.log10(math.max(1, value - shown)), 0.35, 0.9)
	if rolling then return end
	rolling = RunService.Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - startedAt) / duration, 0, 1)
		local eased = 1 - (1 - t) ^ 3
		shown = math.floor(from + (target - from) * eased + 0.5)
		if t >= 1 then
			shown = target
			stopRolling()
		end
		render(shown)
	end)
end

coins:GetPropertyChangedSignal("Value"):Connect(updateMoney)
main:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout)
main:GetPropertyChangedSignal("AbsolutePosition"):Connect(queueLayout)
UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(queueLayout)
moneyWidget:GetAttributeChangedSignal("HUDGrowLeft"):Connect(queueLayout)
moneyWidget:GetAttributeChangedSignal("HUDMaxRight"):Connect(queueLayout)
if screen then screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout) end
-- UITheme can apply after this LocalScript. Refit once its initial fixed-size
-- counter styling is applied, as well as after a later theme rebuild.
for _, property in ipairs({ "Size", "Position", "TextScaled", "Font" }) do
	amountLabel:GetPropertyChangedSignal(property):Connect(queueLayout)
end
shown = coins.Value
render(shown)
