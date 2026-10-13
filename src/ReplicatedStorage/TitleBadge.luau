-- TitleBadge: draws a player title (DogEconomy.TitleDefinitions) into any GuiObject: the BillboardGui
-- above a character (PlayerTitles) and the live preview / cards of the TITLES window (TitlesScreen).
-- One look per rarity (TitleDefinitions.Styles):
--   Common     plain text on a soft dark plate
--   Uncommon   + a coloured plate border
--   Rare       + a glowing text stroke
--   Epic       + a gradient (static)
--   Legendary  + an animated shimmer (a light band sweeping the gradient)
--   Mythic / Secret  + animated shimmer and twinkling sparkles (Secret: a dark void plate)
-- Animation runs only for badges registered with :SetAnimated(true): one shared Heartbeat (30 Hz)
-- exists while at least one badge is animated, none otherwise. Reduced Motion keeps badges still.
--   local badge = TitleBadge.new(frame, {ZIndex = 3})
--   local aspect = badge:Set(def, "ru")      -- width / height of the content: size the holder with it
--   badge:SetAnimated(true); badge:Destroy()
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")
local RS = game:GetService("ReplicatedStorage")
local Titles = require(RS:WaitForChild("DogEconomy"):WaitForChild("TitleDefinitions"))

local Badge = {}
Badge.__index = Badge

local REF_TEXT = 40 -- reference text size for measuring
local REF_H = 56 -- plate height at that text size
local ICON_W, GAP, PAD = 44, 6, 18
local FONT = Enum.Font.FredokaOne

-- true / false forces reduced motion (tests); nil follows Roblox's accessibility setting.
Badge.ReducedOverride = nil :: boolean?
function Badge.Reduced(): boolean
	if Badge.ReducedOverride ~= nil then
		return Badge.ReducedOverride == true
	end
	local ok, value = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end

local widthCache: { [string]: number } = {}
local function textWidth(text: string): number
	local hit = widthCache[text]
	if hit then
		return hit
	end
	local ok, size = pcall(function()
		return TextService:GetTextSize(text, REF_TEXT, FONT, Vector2.new(4000, 200))
	end)
	local w = ok and size.X or #text * REF_TEXT * 0.55
	widthCache[text] = w
	return w
end

-- Width / height of a title's content (icon + text + padding).
function Badge.Measure(def: any, lang: string?): (number, number, number)
	local text = Titles.Text(def, lang)
	local w = textWidth(text)
	local total = PAD * 2 + ICON_W + GAP + w
	return total / REF_H, ICON_W / total, (w + GAP) / total
end

local function sequence(colors: { Color3 }, shimmer: boolean): ColorSequence
	local n = #colors
	if n < 2 then
		local c = colors[1] or Color3.new(1, 1, 1)
		if shimmer then
			return ColorSequence.new({
				ColorSequenceKeypoint.new(0, c),
				ColorSequenceKeypoint.new(0.42, c),
				ColorSequenceKeypoint.new(0.5, c:Lerp(Color3.new(1, 1, 1), 0.8)),
				ColorSequenceKeypoint.new(0.58, c),
				ColorSequenceKeypoint.new(1, c),
			})
		end
		return ColorSequence.new(c)
	end
	if shimmer then
		-- First colour, the rest, a white band in the middle, then mirrored back.
		local a, b = colors[1], colors[2]
		local c = colors[3] or a
		return ColorSequence.new({
			ColorSequenceKeypoint.new(0, a),
			ColorSequenceKeypoint.new(0.3, b),
			ColorSequenceKeypoint.new(0.46, c),
			ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
			ColorSequenceKeypoint.new(0.54, c),
			ColorSequenceKeypoint.new(0.7, b),
			ColorSequenceKeypoint.new(1, a),
		})
	end
	local points = {}
	for i, color in ipairs(colors) do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (n - 1), color))
	end
	return ColorSequence.new(points)
end

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in pairs(props) do
		(o :: any)[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

-- props: ZIndex (default 1), Stroke (pixel scale of strokes, default 1), NoPlate (text only).
function Badge.new(parent: Instance, props: any?): any
	local p = props or {}
	local self = setmetatable({}, Badge)
	local z = p.ZIndex or 1
	self.Z = z
	self.StrokeScale = p.Stroke or 1
	self.Phase = math.random() * 3
	local plate = new("Frame", {
		Name = "TitlePlate",
		BackgroundColor3 = Color3.fromRGB(18, 22, 34),
		BackgroundTransparency = p.NoPlate and 1 or 0.55,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, plate)
	self.Plate = plate
	self.Border = new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 2 * self.StrokeScale, Transparency = 1 }, plate)
	self.BorderGradient = new("UIGradient", { Enabled = false }, self.Border)
	local row = new("Frame", { Name = "Row", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = z }, plate)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	self.Icon = new("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(0.2, 0.8),
		LayoutOrder = 1,
		ZIndex = z + 1,
	}, row)
	self.Text = new("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = FONT,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(0.7, 0.64),
		LayoutOrder = 2,
		ZIndex = z + 1,
	}, row)
	for _, label in ipairs({ self.Icon, self.Text }) do
		label:SetAttribute("NoTranslate", true)
		label:SetAttribute("KeepFont", true)
	end
	self.TextStroke = new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Thickness = 1.5 * self.StrokeScale, Color = Color3.fromRGB(14, 16, 26) }, self.Text)
	self.Gradient = new("UIGradient", { Enabled = false }, self.Text)
	self.Sparks = {}
	for i, at in ipairs({ Vector2.new(0.04, 0.12), Vector2.new(0.95, 0.86), Vector2.new(0.86, 0.04) }) do
		self.Sparks[i] = new("TextLabel", {
			Name = "Sparkle",
			BackgroundTransparency = 1,
			Font = FONT,
			Text = "✦",
			TextScaled = true,
			TextColor3 = Color3.new(1, 1, 1),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(at.X, at.Y),
			Size = UDim2.fromScale(0.09, 0.42),
			Visible = false,
			ZIndex = z + 2,
		}, plate)
		self.Sparks[i]:SetAttribute("NoTranslate", true)
		self.Sparks[i]:SetAttribute("KeepFont", true)
		new("UIAspectRatioConstraint", { AspectRatio = 1 }, self.Sparks[i])
	end
	self.Animated = false
	return self
end

-- Draws `def` (nil clears). Returns the content aspect ratio (width / height).
function Badge.Set(self: any, def: any, lang: string?): number
	self.Def = def
	if not def then
		self.Plate.Visible = false
		self:SetAnimated(false)
		return 1
	end
	self.Plate.Visible = true
	local aspect, iconFrac, textFrac = Badge.Measure(def, lang)
	self.Icon.Text = def.Icon or ""
	self.Icon.Size = UDim2.fromScale(iconFrac, 0.8)
	self.Text.Text = Titles.Text(def, lang)
	self.Text.Size = UDim2.fromScale(math.min(0.92, textFrac), 0.64)
	local style = Titles.Style(def)
	local colors = Titles.Colors(def)
	local main = colors[1]
	self.Style = style
	-- Plate
	self.Plate.BackgroundColor3 = style.Dark and Color3.fromRGB(14, 6, 26) or Color3.fromRGB(18, 22, 34)
	if self.Plate.BackgroundTransparency < 1 then
		self.Plate.BackgroundTransparency = style.Plate or 0.55
	end
	if style.Border then
		self.Border.Transparency = 0.15
		self.Border.Color = style.Gradient and Color3.new(1, 1, 1) or style.Border
		self.BorderGradient.Enabled = style.Gradient == true
		if style.Gradient then
			self.BorderGradient.Color = sequence(colors, false)
		end
	else
		self.Border.Transparency = 1
		self.BorderGradient.Enabled = false
	end
	-- Text: colour or gradient, a dark outline or a glow.
	if style.Gradient then
		self.Text.TextColor3 = Color3.new(1, 1, 1)
		self.Gradient.Enabled = true
		self.Gradient.Color = sequence(colors, style.Animated == true)
		self.Gradient.Rotation = style.Animated and 12 or 0
		self.Gradient.Offset = Vector2.zero
	else
		self.Gradient.Enabled = false
		self.Text.TextColor3 = main
	end
	if style.Glow then
		self.TextStroke.Color = main:Lerp(Color3.new(1, 1, 1), 0.25)
		self.TextStroke.Transparency = 0.45
		self.TextStroke.Thickness = 2.6 * self.StrokeScale
	else
		self.TextStroke.Color = Color3.fromRGB(14, 16, 26)
		self.TextStroke.Transparency = 0.15
		self.TextStroke.Thickness = 1.5 * self.StrokeScale
	end
	for _, spark in ipairs(self.Sparks) do
		spark.Visible = style.Sparkle == true
		spark.TextColor3 = (colors[2] or main):Lerp(Color3.new(1, 1, 1), 0.5)
		spark.TextTransparency = 0.2
	end
	if not style.Animated then
		self:SetAnimated(false)
	end
	return aspect
end

function Badge.CanAnimate(self: any): boolean
	return self.Style ~= nil and self.Style.Animated == true and not Badge.Reduced()
end

-- Shared animator ------------------------------------------------------------------------------
local animated: { [any]: boolean } = {}
local connection: RBXScriptConnection? = nil
local acc = 0
local function stepAll(dt: number)
	acc += dt
	if acc < 1 / 30 then
		return
	end
	acc = 0
	local t = os.clock()
	for badge in pairs(animated) do
		badge:_step(t)
	end
end
function Badge.ActiveCount(): number
	local n = 0
	for _ in pairs(animated) do
		n += 1
	end
	return n
end

function Badge._step(self: any, t: number)
	if not self.Plate.Parent then
		animated[self] = nil
		return
	end
	-- The light band sweeps across in ~1.7 s, then rests off the text for ~1 s.
	local u = (t * 0.6 + self.Phase) % 1.6
	self.Gradient.Offset = Vector2.new(u < 1 and (u * 2.1 - 1.05) or 1.05, 0)
	if self.Style and self.Style.Sparkle then
		for i, spark in ipairs(self.Sparks) do
			local k = 0.5 + 0.5 * math.sin(t * 3.2 + i * 2.1 + self.Phase)
			spark.TextTransparency = 1 - k * 0.9
			spark.Rotation = (t * 40 + i * 30) % 360
		end
	end
end

function Badge.SetAnimated(self: any, on: boolean)
	on = on and self:CanAnimate()
	if on == self.Animated then
		return
	end
	self.Animated = on
	if on then
		animated[self] = true
		if not connection then
			connection = RunService.Heartbeat:Connect(stepAll)
		end
	else
		animated[self] = nil
		self.Gradient.Offset = Vector2.zero
		for _, spark in ipairs(self.Sparks) do
			spark.TextTransparency = 0.2
			spark.Rotation = 0
		end
		if next(animated) == nil and connection then
			connection:Disconnect()
			connection = nil
		end
	end
end

function Badge.Destroy(self: any)
	self:SetAnimated(false)
	self.Plate:Destroy()
end

return Badge
