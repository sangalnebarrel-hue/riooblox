-- Instance helpers shared by every kit component: creation, decoration, text, icons, the kit
-- ScreenGui layers, the safe area and the press animation.
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.Theme)
local Motion = require(script.Parent.Motion)

local Base = {}

local ALIGN_X = { Left = Enum.TextXAlignment.Left, Center = Enum.TextXAlignment.Center, Right = Enum.TextXAlignment.Right }
local ALIGN_Y = { Top = Enum.TextYAlignment.Top, Center = Enum.TextYAlignment.Center, Bottom = Enum.TextYAlignment.Bottom }

-- Instance.new + properties (+ parent last, so watchers see the final state).
function Base.New(className: string, props: { [string]: any }?, parent: Instance?): any
	local object: any = Instance.new(className)
	if props then
		for key, value in pairs(props) do
			object[key] = value
		end
	end
	if parent then
		object.Parent = parent
	end
	return object
end

-- radius: pixels, or "pill" for fully rounded ends.
function Base.Corner(object: Instance, radius: any): UICorner
	local old = object:FindFirstChildWhichIsA("UICorner")
	if old then
		old:Destroy()
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius == "pill" and UDim.new(0.5, 0) or UDim.new(0, tonumber(radius) or Theme.Radius.Button)
	corner.Parent = object
	return corner
end

function Base.Stroke(object: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	local old = object:FindFirstChildWhichIsA("UIStroke")
	if old then
		old:Destroy()
	end
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color or Theme.Colors.edge
	stroke.Thickness = thickness or 2
	stroke.Transparency = transparency or 0
	stroke.Parent = object
	return stroke
end

function Base.Padding(object: Instance, left: number, top: number?, right: number?, bottom: number?): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, left)
	padding.PaddingTop = UDim.new(0, top or left)
	padding.PaddingRight = UDim.new(0, right or left)
	padding.PaddingBottom = UDim.new(0, bottom or top or left)
	padding.Parent = object
	return padding
end

-- Vertical gradient from `top` to `bottom` over a white background (keeps colours exact).
function Base.Gradient(object: GuiObject, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local old = object:FindFirstChildWhichIsA("UIGradient")
	if old then
		old:Destroy()
	end
	object.BackgroundColor3 = Theme.White
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = rotation or 90
	gradient.Parent = object
	return gradient
end

export type TextProps = {
	Name: string?,
	Text: string?,
	TextSize: number?,
	MinTextSize: number?,
	Color: Color3?,
	Font: any?, -- "display" (default), "numeric" or a Font
	AlignX: string?, -- "Left" | "Center" | "Right"
	AlignY: string?, -- "Top" | "Center" | "Bottom"
	Wrap: boolean?,
	Scaled: boolean?, -- shrink to fit (UITextSizeConstraint between MinTextSize and TextSize)
	Stroke: any?, -- true or a transparency number: navy text outline (white titles)
	Rich: boolean?,
	NoTranslate: boolean?, -- the text is self-localized (Kit.T) or numbers only
	AutoX: boolean?, -- AutomaticSize X (pills)
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	ZIndex: number?,
	LayoutOrder: number?,
	Transparency: number?,
	Class: string?, -- "TextLabel" (default) or "TextButton"
}

-- A text label in the kit style. Attributes are set before parenting: PlaceTypography and
-- DOGROTS_AutoTranslateUI read them when the label appears.
function Base.Text(parent: Instance?, props: TextProps?): any
	local p: any = props or {}
	local label: any = Instance.new(p.Class or "TextLabel")
	label.Name = p.Name or "Label"
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	local font = p.Font
	if font == nil or font == "display" then
		label.FontFace = Theme.Font
	else
		label.FontFace = font == "numeric" and Theme.FontNumeric or font
		label:SetAttribute("KeepFont", true)
	end
	if p.NoTranslate then
		label:SetAttribute("NoTranslate", true)
	end
	if label:IsA("TextButton") then
		label.AutoButtonColor = false
	end
	label.Text = p.Text or ""
	label.TextSize = p.TextSize or 16
	label.TextColor3 = p.Color or Theme.Ink
	label.TextTransparency = p.Transparency or 0
	label.TextXAlignment = ALIGN_X[p.AlignX or "Left"] or Enum.TextXAlignment.Left
	label.TextYAlignment = ALIGN_Y[p.AlignY or "Center"] or Enum.TextYAlignment.Center
	label.TextWrapped = p.Wrap == true
	label.TextTruncate = p.Wrap and Enum.TextTruncate.None or Enum.TextTruncate.AtEnd
	label.RichText = p.Rich == true
	if p.Scaled then
		label.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = math.max(1, math.floor(p.TextSize or 16))
		limit.MinTextSize = math.max(1, math.min(limit.MaxTextSize, math.floor(p.MinTextSize or 9)))
		limit.Parent = label
	end
	if p.Stroke then
		label.TextStrokeColor3 = Theme.Colors.edge
		label.TextStrokeTransparency = p.Stroke == true and 0 or tonumber(p.Stroke) or 0
	else
		label.TextStrokeTransparency = 1
	end
	if p.AutoX then
		label.AutomaticSize = Enum.AutomaticSize.X
	end
	label.Size = p.Size or UDim2.fromScale(1, 1)
	label.Position = p.Position or UDim2.new()
	label.AnchorPoint = p.AnchorPoint or Vector2.zero
	label.ZIndex = p.ZIndex or 1
	label.LayoutOrder = p.LayoutOrder or 0
	if parent then
		label.Parent = parent
	end
	return label
end

-- Image for an icon key: an asset URL as is, a HUD icon (Theme.Icons) or a GameIcons key.
local gameIcons: any = nil
function Base.IconImage(key: string?): string?
	if type(key) ~= "string" or key == "" then
		return nil
	end
	if string.find(key, "^rbxasset") or string.find(key, "^rbxthumb") or string.find(key, "^http") then
		return key
	end
	local own = (Theme.Icons :: any)[key]
	if own then
		return own
	end
	if gameIcons == nil then
		gameIcons = false
		local module = ReplicatedStorage:FindFirstChild("GameIcons")
		if module and module:IsA("ModuleScript") then
			local ok, value = pcall(require, module)
			if ok and type(value) == "table" then
				gameIcons = value
			end
		end
	end
	if gameIcons and type(gameIcons.Resolve) == "function" then
		local ok, url = pcall(gameIcons.Resolve, key)
		if ok and type(url) == "string" then
			return url
		end
	end
	return nil
end

local GLYPHS = { Coins = "$", Star = "★", Lock = "🔒", Check = "✓", Info = "i", Warning = "!", Search = "⌕" }

-- An icon: ImageLabel when the key resolves to an image, otherwise a text glyph.
function Base.Icon(parent: Instance?, key: string?, props: { Size: UDim2?, Position: UDim2?, AnchorPoint: Vector2?, ZIndex: number?, Color: Color3?, Glyph: string? }?): any
	local p: any = props or {}
	local image = Base.IconImage(key)
	local icon
	if image then
		icon = Base.New("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Image = image,
			ScaleType = Enum.ScaleType.Fit,
			ImageColor3 = p.Color or Theme.White,
		})
	else
		icon = Base.Text(nil, {
			Name = "Icon",
			Text = p.Glyph or (key and (GLYPHS :: any)[key]) or "★",
			TextSize = 18,
			Scaled = true,
			MinTextSize = 8,
			AlignX = "Center",
			Color = p.Color or Theme.Ink,
			NoTranslate = true,
		})
		icon:SetAttribute("KitGlyph", true)
	end
	icon.Size = p.Size or UDim2.fromOffset(24, 24)
	icon.Position = p.Position or UDim2.new()
	icon.AnchorPoint = p.AnchorPoint or Vector2.zero
	icon.ZIndex = p.ZIndex or 1
	if parent then
		icon.Parent = parent
	end
	return icon
end

-- Places `object` on the pixel rectangle (x, y, w, h) with its anchor at the centre, so a UIScale
-- animates around the middle. Offsets are whole pixels (UDim offsets are integers): the anchor is
-- nudged instead of rounding the centre, which keeps odd sizes exact.
function Base.PlaceCentered(object: GuiObject, x: number, y: number, w: number, h: number)
	w, h = math.max(1, math.floor(w)), math.max(1, math.floor(h))
	local hx, hy = math.floor(w / 2), math.floor(h / 2)
	object.AnchorPoint = Vector2.new(hx / w, hy / h)
	object.Position = UDim2.fromOffset(math.floor(x) + hx, math.floor(y) + hy)
	object.Size = UDim2.fromOffset(w, h)
end

-- Selects `object` for gamepad navigation when the player is using a gamepad.
function Base.GamepadFocus(object: GuiObject?)
	if not object then
		return
	end
	local ok, last = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if ok and last and string.find(tostring(last), "Gamepad", 1, true) then
		GuiService.SelectedObject = object
	end
end

-- PlayerGui of the local player (nil on the server or before it exists).
function Base.PlayerGui(): Instance?
	local player = Players.LocalPlayer
	if not player then
		return nil
	end
	return player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
end

-- The kit ScreenGuis: full screen (no inset), so positions are screen pixels and the dim
-- backdrop covers the notch and the top bar too. Content is placed inside Base.SafeArea.
local layers: { [string]: any } = {}
function Base.Layer(name: string, displayOrder: number): ScreenGui
	local existing = layers[name]
	if existing and existing.Parent then
		return existing
	end
	local playerGui = Base.PlayerGui()
	assert(playerGui, "Kit: PlayerGui is not available (the kit is client-only)")
	local gui: any = playerGui:FindFirstChild(name)
	if not (gui and gui:IsA("ScreenGui")) then
		gui = Instance.new("ScreenGui")
		gui.Name = name
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.ScreenInsets = Enum.ScreenInsets.None
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.DisplayOrder = displayOrder
		gui:SetAttribute("KitLayer", true)
		gui.Parent = playerGui
	end
	layers[name] = gui
	return gui
end

-- Usable rectangle of a ScreenGui in its own pixels: the Core UI safe area (top bar, notch and
-- home indicator excluded). Same maths as UITheme.SafeArea.
function Base.SafeArea(gui: any): (number, number, number, number)
	local size = gui.AbsoluteSize
	local ok, safe, own = pcall(function()
		local service: any = GuiService
		return service:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets), service:GetInsetArea(gui.ScreenInsets)
	end)
	if ok and safe and own then
		local left = math.clamp(safe.Min.X - own.Min.X, 0, size.X)
		local top = math.clamp(safe.Min.Y - own.Min.Y, 0, size.Y)
		local right = math.clamp(safe.Max.X - own.Min.X, left, size.X)
		local bottom = math.clamp(safe.Max.Y - own.Min.Y, top, size.Y)
		return left, top, right - left, bottom - top
	end
	local top = gui.IgnoreGuiInset and 58 or 0
	return 0, top, size.X, math.max(1, size.Y - top)
end

-- Hover / press / gamepad-selection scale animation on a button. `target` gets a UIScale
-- (KitPress). The button is skipped while its KitDisabled attribute is true.
function Base.Press(button: GuiButton, target: GuiObject?, maid: any?, hoverScale: number?): UIScale
	local holder: any = target or button
	local scale: any = holder:FindFirstChild("KitPress")
	if not (scale and scale:IsA("UIScale")) then
		scale = Base.New("UIScale", { Name = "KitPress" }, holder)
	end
	local hover, pressed = false, false
	local function draw()
		local enabled = button:GetAttribute("KitDisabled") ~= true
		local goal = (not enabled and 1) or (pressed and 0.96) or (hover and (hoverScale or 1.03)) or 1
		Motion.Tween(scale, Theme.Motion.Press, { Scale = goal })
	end
	local connections = {
		button.MouseEnter:Connect(function()
			hover = true
			draw()
		end),
		button.MouseLeave:Connect(function()
			hover, pressed = false, false
			draw()
		end),
		button.MouseButton1Down:Connect(function()
			pressed = true
			draw()
		end),
		button.MouseButton1Up:Connect(function()
			pressed = false
			draw()
		end),
		button.SelectionGained:Connect(function()
			hover = true
			draw()
		end),
		button.SelectionLost:Connect(function()
			hover, pressed = false, false
			draw()
		end),
	}
	if maid then
		for _, connection in ipairs(connections) do
			maid:Give(connection)
		end
	end
	return scale
end

-- Every kit button is a transparent hit target with a "Face" frame inside it. Besides keeping the
-- visuals in one place, this makes UITheme.ApplyStandalone skip kit buttons placed under the
-- main ScreenGui (its EnhanceButton repaints opaque buttons and ignores transparent ones).
function Base.Face(button: GuiButton, color: Color3?, radius: any?, zIndex: number?): Frame
	button.BackgroundTransparency = 1
	local face = Base.New("Frame", {
		Name = "Face",
		BackgroundColor3 = color or Theme.White,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex or button.ZIndex,
	}, button)
	Base.Corner(face, radius or Theme.Radius.Button)
	return face
end

-- A rounded pill-shaped toggle button that grows with its text (tabs, chips, menu options).
-- Returns the button, its caption and its face (colour it, it holds the UIStroke).
function Base.PillButton(parent: Instance, props: { Name: string?, Text: string?, TextSize: number?, MinWidth: number?, Height: number?, LayoutOrder: number?, ZIndex: number?, NoTranslate: boolean? }): (any, any, any)
	local zIndex = props.ZIndex or 1
	local button = Base.New("TextButton", {
		Name = props.Name or "Pill",
		Text = "",
		AutoButtonColor = false,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = props.Height and UDim2.fromOffset(0, props.Height) or UDim2.fromScale(0, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = zIndex,
	})
	local pad = 14
	Base.Padding(button, pad, 0, pad, 0)
	-- The face spans the padding too (children are laid out inside the padding).
	local face = Base.Face(button, Theme.White, "pill", zIndex)
	face.Position = UDim2.fromOffset(-pad, 0)
	face.Size = UDim2.new(1, pad * 2, 1, 0)
	Base.Stroke(face, Theme.Colors.edge, 2, 0.55)
	Base.New("UISizeConstraint", { MinSize = Vector2.new(props.MinWidth or 56, 0) }, button)
	local label = Base.Text(button, {
		Name = "Caption",
		Text = props.Text,
		TextSize = props.TextSize or 16,
		AutoX = true,
		Size = UDim2.fromScale(0, 1),
		AlignX = "Center",
		ZIndex = zIndex + 1,
		NoTranslate = props.NoTranslate,
	})
	button.Parent = parent
	return button, label, face
end

-- A horizontal strip that scrolls sideways when its pills overflow (tabs, chips).
function Base.Strip(parent: Instance?, name: string, gap: number?): any
	local strip = Base.New("ScrollingFrame", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		ClipsDescendants = true,
		Selectable = false,
	}, parent)
	Base.New("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, gap or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, strip)
	Base.Padding(strip, 2, 2, 2, 2)
	return strip
end

-- Scrolls a horizontal strip so `child` is fully visible.
function Base.Reveal(strip: any, child: GuiObject)
	local left = child.AbsolutePosition.X - strip.AbsolutePosition.X + strip.CanvasPosition.X
	local right = left + child.AbsoluteSize.X
	local view = strip.AbsoluteSize.X
	local x = strip.CanvasPosition.X
	if left < x then
		x = math.max(0, left - 12)
	elseif right > x + view then
		x = right - view + 12
	end
	if x ~= strip.CanvasPosition.X then
		strip.CanvasPosition = Vector2.new(x, 0)
	end
end

return Base
