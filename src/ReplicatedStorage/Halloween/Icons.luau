-- NIGHT OF THE BURIED MOON vector icons (ReplicatedStorage.Halloween.Icons), client UI only.
-- The event has no uploaded art, so every event icon is BUILT from layered Frames (UICorner / UIGradient / UIStroke) in the
-- style of UITheme's procedural icons (U.Icon): one look on every OS, crisp at any size, no emoji. Every shape is laid
-- out in Scale units of a square root Frame, so an icon follows its parent's size; outlines (UIStroke, pixels) are
-- re-fitted to the drawn size (Icons.Fit, automatic on AbsoluteSize changes).
--   local h = Icons.New(parent, "Candy", {Size = 40, ZIndex = 12, Color = ..., Glow = ...})
--   h.Instance (Frame "HwIcon"), h:Set(kind, opts?) (redraw), h:Fit(), h:Destroy()
--   Icons.Kinds -> list of the kinds: Candy, Skull, Pumpkin, Moon, Ghost, Bolt, Potion, Bat, Cauldron, Bell, Scroll, Door,
--   Check, Lock, Bone, Star, Crown, Pickaxe, Dog, Book
-- opts: Size (px, outline hint before layout), ZIndex, Color (main tint), Glow (accent / eyes / brew), Dim (0..1, locked
-- look), Outline (Color3 | false), State (Moon: "Full" | "Blood" | "Fading"; Skull: "Grin"), Face (Pumpkin: carved, true).
local Icons = {}

local C = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = C(22, 10, 34)
local PUMPKIN = C(255, 128, 24)
local CREAM = C(255, 240, 214)
local BONE = C(236, 226, 200)
local NEON = C(120, 255, 110)
local PURPLE = C(122, 62, 200)
local GOLD = C(255, 200, 70)
local GHOST = C(140, 215, 255)
local BLOOD = C(200, 30, 50)
Icons.Palette = { Pumpkin = PUMPKIN, Cream = CREAM, Bone = BONE, Neon = NEON, Purple = PURPLE, Gold = GOLD, Ghost = GHOST, Blood = BLOOD, Ink = INK }

local function lerp(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

-- hard-edged stripes for a UIGradient (n stripe pairs, 4n + 1 keypoints <= 20)
function Icons.Stripes(a: Color3, b: Color3, n: number): ColorSequence
	n = math.clamp(math.floor(n), 1, 4)
	local keys = {}
	local eps = .002
	for i = 0, n - 1 do
		local t0, mid, t1 = i / n, (i + .5) / n, (i + 1) / n
		table.insert(keys, ColorSequenceKeypoint.new(t0, a))
		table.insert(keys, ColorSequenceKeypoint.new(mid - eps, a))
		table.insert(keys, ColorSequenceKeypoint.new(mid, b))
		table.insert(keys, ColorSequenceKeypoint.new(t1 - eps, b))
	end
	table.insert(keys, ColorSequenceKeypoint.new(1, a))
	return ColorSequence.new(keys)
end

-- drawing context: every helper adds one Frame in Scale units of the icon box
local Draw = {}
Draw.__index = Draw

function Draw:frame(name: string, x: number, y: number, w: number, h: number, color: Color3, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.AnchorPoint = Vector2.new(.5, .5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	self.Z += 1
	f.ZIndex = self.Base + math.min(self.Z, 18)
	if props then
		for k, v in pairs(props) do
			(f :: any)[k] = v
		end
	end
	f.Parent = props and props.Parent or self.Root
	return f
end
-- rounded: r = "pill" | scale of the short side (0..0.5)
function Draw:round(f: GuiObject, r: any)
	local c = Instance.new("UICorner")
	c.CornerRadius = r == "pill" and UDim.new(.5, 0) or UDim.new(tonumber(r) or .2, 0)
	c.Parent = f
	return c
end
function Draw:grad(f: GuiObject, top: Color3, bottom: Color3, rotation: number?, alpha: NumberSequence?)
	local g = Instance.new("UIGradient")
	f.BackgroundColor3 = WHITE
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	if alpha then
		g.Transparency = alpha
	end
	g.Parent = f
	return g
end
-- outline k = thickness as a fraction of the icon's pixel size (re-fitted on resize)
function Draw:line(f: GuiObject, color: Color3?, k: number?, alpha: number?)
	if self.Outline == false then
		return nil
	end
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Color = color or self.Outline or INK
	s.Transparency = alpha or 0
	s.LineJoinMode = Enum.LineJoinMode.Round
	s:SetAttribute("HwK", k or .045)
	s.Thickness = math.max(1, (k or .045) * self.Px)
	s.Parent = f
	return s
end
function Draw:circle(name: string, x: number, y: number, d: number, color: Color3, props: { [string]: any }?): Frame
	local f = self:frame(name, x, y, d, d, color, props)
	self:round(f, "pill")
	return f
end
function Draw:ellipse(name: string, x: number, y: number, w: number, h: number, color: Color3, props: { [string]: any }?): Frame
	local f = self:frame(name, x, y, w, h, color, props)
	self:round(f, "pill")
	return f
end
-- soft round glow behind the icon (transparent radial falloff)
function Draw:glow(color: Color3, d: number, alpha: number?)
	local f = self:circle("Glow", .5, .5, d, color, { BackgroundTransparency = 0 })
	local a = alpha or .55
	self:grad(f, color, color, 0, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.25, 1 - (1 - a) * .5),
		NumberSequenceKeypoint.new(.5, a), NumberSequenceKeypoint.new(.75, 1 - (1 - a) * .5), NumberSequenceKeypoint.new(1, 1) }))
	-- a second, crossed pass makes the falloff round instead of a band
	local g2 = self:circle("Glow2", .5, .5, d * .7, color, { BackgroundTransparency = 0 })
	self:grad(g2, color, color, 90, NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(.5, a + (1 - a) * .3),
		NumberSequenceKeypoint.new(1, 1) }))
	return f
end
-- a bar from (x0, y0) to (x1, y1) (icon units; the box is square, so angles hold on screen)
function Draw:bar(name: string, x0: number, y0: number, x1: number, y1: number, thick: number, color: Color3, props: { [string]: any }?): Frame
	local dx, dy = x1 - x0, y1 - y0
	local len = math.sqrt(dx * dx + dy * dy)
	local f = self:frame(name, (x0 + x1) / 2, (y0 + y1) / 2, len, thick, color, props)
	f.Rotation = math.deg(math.atan2(dy, dx))
	return f
end
-- an isosceles triangle (apex "Up" or "Down") in the box (x, y = centre, w x h): the upper / lower half of a rotated
-- square seen through a clipping frame (clipping works because the clip frame itself is never rotated)
function Draw:triangle(name: string, x: number, y: number, w: number, h: number, top: Color3, bottom: Color3?, dir: string?): Frame
	local clip = self:frame(name, x, y, w, h, WHITE, { BackgroundTransparency = 1, ClipsDescendants = true })
	local up = dir ~= "Down"
	-- square side s = w / sqrt2 (diagonal = base); in clip units: X = 0.707, Y = 0.707 * w / h * (pixel aspect is 1)
	local sy = .7071 * w / h
	local sq = Instance.new("Frame")
	sq.Name = "Shape"
	sq.BorderSizePixel = 0
	sq.AnchorPoint = Vector2.new(.5, .5)
	sq.Position = UDim2.fromScale(.5, up and 1 or 0)
	sq.Size = UDim2.fromScale(.7071, sy)
	sq.Rotation = 45
	sq.ZIndex = clip.ZIndex
	sq.BackgroundColor3 = WHITE
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom or top)
	g.Rotation = 45 -- the square is turned 45: 45 here = top -> bottom on screen
	g.Parent = sq
	sq.Parent = clip
	return clip
end
-- a glossy highlight (top-left shine)
function Draw:shine(x: number, y: number, w: number, h: number, alpha: number?)
	local f = self:ellipse("Shine", x, y, w, h, WHITE, { BackgroundTransparency = alpha or .45, Rotation = -25 })
	return f
end

---------------------------------------------------------------------------------------------------------------------
-- the icons
---------------------------------------------------------------------------------------------------------------------
local K = {}

-- wrapped candy: striped round body, two pleated wrapper ends, ink outline, gloss
K.Candy = function(d, o)
	local body = o.Color or PUMPKIN
	local stripe = o.Glow or CREAM
	local wrap = lerp(body, WHITE, .25)
	local dark = lerp(body, INK, .35)
	for _, s in ipairs({ -1, 1 }) do
		-- outer pleat (a diamond) and the twist knot where it meets the body
		local fan = d:frame("Wrap", .5 + s * .34, .5, .3, .3, WHITE, { Rotation = 45 })
		d:round(fan, .18)
		d:grad(fan, wrap, dark, s > 0 and 0 or 180)
		d:line(fan, nil, .04)
		local pleat = d:frame("Pleat", .5 + s * .37, .5, .05, .2, dark, { BackgroundTransparency = .35 })
		d:round(pleat, "pill")
		local knot = d:ellipse("Knot", .5 + s * .25, .5, .1, .16, lerp(body, WHITE, .1))
		d:line(knot, nil, .035)
	end
	local ball = d:circle("Body", .5, .5, .56, WHITE)
	local g = Instance.new("UIGradient")
	g.Color = Icons.Stripes(body, stripe, 4)
	g.Rotation = 40
	g.Parent = ball
	d:line(ball, nil, .05)
	-- a soft shade over the stripes so the ball reads round
	local shade = d:circle("Shade", .5, .5, .56, WHITE)
	d:grad(shade, WHITE, INK, 120, NumberSequence.new({ NumberSequenceKeypoint.new(0, .82), NumberSequenceKeypoint.new(.55, 1),
		NumberSequenceKeypoint.new(1, .55) }))
	d:shine(.4, .36, .2, .1, .35)
end

-- skull: cranium + cheekbones + jaw, deep sockets with glowing pupils, nose, teeth; Glow = eye colour
K.Skull = function(d, o)
	local bone = o.Color or BONE
	local eye = o.Glow or C(196, 120, 255)
	local shadow = lerp(bone, C(90, 70, 120), .55)
	if o.Glow then
		d:glow(eye, 1.05, .72)
	end
	local cran = d:ellipse("Cranium", .5, .42, .74, .66, WHITE)
	d:grad(cran, lerp(bone, WHITE, .35), shadow, 90)
	d:line(cran, nil, .05)
	local jaw = d:frame("Jaw", .5, .76, .44, .22, WHITE)
	d:round(jaw, .32)
	d:grad(jaw, bone, shadow, 90)
	d:line(jaw, nil, .045)
	-- cheeks blend the cranium into the jaw (drawn over the jaw's top stroke)
	local cheek = d:frame("Cheek", .5, .64, .5, .16, lerp(bone, shadow, .35))
	d:round(cheek, .4)
	for _, s in ipairs({ -1, 1 }) do
		local socket = d:ellipse("Socket", .5 + s * .155, .47, .2, .22, INK, { Rotation = s * -12 })
		local pupil = d:circle("Pupil", .5 + s * .15, .49, .085, eye)
		d:grad(pupil, lerp(eye, WHITE, .55), eye, 90)
		local _ = socket
	end
	local nose = d:frame("Nose", .5, .62, .075, .075, INK, { Rotation = 45 })
	d:round(nose, .2)
	for i = -1, 1 do
		local tooth = d:frame("Gap", .5 + i * .085, .79, .024, .12, INK, { BackgroundTransparency = .1 })
		d:round(tooth, "pill")
	end
	local crack = d:frame("Crack", .62, .2, .028, .16, shadow, { Rotation = 28 })
	d:round(crack, "pill")
	d:shine(.37, .25, .22, .09, .5)
end

-- pumpkin: three ribs, stem + leaf + curl, carved glowing face (Face = true) and an inner glow
K.Pumpkin = function(d, o)
	local body = o.Color or PUMPKIN
	local hi = lerp(body, C(255, 190, 90), .45)
	local lo = lerp(body, C(150, 50, 10), .5)
	local fire = o.Glow or C(255, 168, 36)
	if o.Face ~= false then
		d:glow(lerp(body, fire, .4), 1.08, .74)
	end
	-- stem first (behind the ribs)
	local stem = d:frame("Stem", .53, .17, .11, .2, WHITE, { Rotation = 14 })
	d:round(stem, .3)
	d:grad(stem, C(150, 170, 80), C(70, 84, 34), 0)
	d:line(stem, nil, .035)
	local leaf = d:ellipse("Leaf", .66, .2, .2, .09, WHITE, { Rotation = -24 })
	d:grad(leaf, C(150, 220, 90), C(60, 130, 50), 90)
	d:line(leaf, nil, .03)
	for _, s in ipairs({ -1, 1 }) do
		local rib = d:ellipse("Rib", .5 + s * .2, .58, .5, .7, WHITE)
		d:grad(rib, hi, lo, 90 + s * 18)
		d:line(rib, nil, .045)
	end
	local mid = d:ellipse("RibMid", .5, .57, .46, .74, WHITE)
	d:grad(mid, lerp(hi, WHITE, .06), lo, 90)
	d:line(mid, nil, .045)
	for _, s in ipairs({ -1, 1 }) do
		for _, y in ipairs({ .3, .85 }) do
			local groove = d:ellipse("Groove", .5 + s * .1, y, .03, .12, lo, { BackgroundTransparency = .5 })
			local _ = groove
		end
	end
	if o.Face ~= false then
		local lit = C(255, 250, 190)
		local core = C(255, 214, 80)
		local carve = C(100, 30, 6)
		-- carved holes: a dark rim (pass 1) under the glowing insides (pass 2)
		for pass = 1, 2 do
			local g = pass == 1 and .045 or 0
			for _, s in ipairs({ -1, 1 }) do
				d:triangle("Eye", .5 + s * .15, .48, .22 + g * 2, .11 + g, pass == 1 and carve or lit, pass == 1 and carve or core, "Up")
			end
			d:triangle("Nose", .5, .6, .1 + g * 2, .05 + g, pass == 1 and carve or lit, pass == 1 and carve or core, "Up")
		end
		local mouth = d:frame("Mouth", .5, .73, .46, .14, WHITE)
		d:round(mouth, .45)
		d:grad(mouth, lit, core, 90)
		d:line(mouth, carve, .03)
		for _, x in ipairs({ -.1, .1 }) do
			local tooth = d:frame("Tooth", .5 + x, .685, .075, .06, lerp(hi, lo, .3))
			d:round(tooth, .15)
		end
		local lower = d:frame("ToothLow", .5, .785, .075, .055, lerp(hi, lo, .55))
		d:round(lower, .15)
	end
	d:shine(.27, .5, .08, .18, .55)
end

-- moon: disc + craters; State "Blood" (red, veins), "Fading" (dim)
K.Moon = function(d, o)
	local state = o.State or "Full"
	local top, bottom = C(255, 248, 222), C(255, 176, 84)
	if state == "Blood" then
		top, bottom = C(255, 150, 140), C(170, 16, 40)
	elseif state == "Fading" then
		top, bottom = C(210, 170, 190), C(110, 60, 90)
	end
	if o.Color then
		top, bottom = lerp(o.Color, WHITE, .5), o.Color
	end
	d:glow(bottom, 1.1, state == "Blood" and .6 or .72)
	local disc = d:circle("Disc", .5, .5, .76, WHITE)
	d:grad(disc, top, bottom, 125)
	d:line(disc, lerp(bottom, INK, .55), .04)
	for _, c in ipairs({ { .38, .38, .18 }, { .62, .6, .14 }, { .44, .66, .09 }, { .64, .35, .07 } }) do
		local crater = d:circle("Crater", c[1], c[2], c[3], lerp(bottom, INK, .2), { BackgroundTransparency = .45 })
		local _ = crater
	end
	if state == "Blood" then
		for _, v in ipairs({ { .5, .5, .4, 30 }, { .42, .58, .26, -40 } }) do
			local vein = d:frame("Vein", v[1], v[2], v[3], .025, C(120, 0, 20), { Rotation = v[4], BackgroundTransparency = .25 })
			d:round(vein, "pill")
		end
	end
	d:shine(.38, .32, .2, .09, .5)
end

-- ghost: round head, scalloped hem, dark eyes and an "o" mouth; Color = body tint
K.Ghost = function(d, o)
	local body = o.Color or C(236, 246, 255)
	local tint = o.Glow or GHOST
	d:glow(tint, 1.0, .74)
	local shape = d:frame("Body", .5, .48, .62, .74, WHITE)
	d:round(shape, .5)
	d:grad(shape, body, lerp(body, tint, .55), 90)
	d:line(shape, nil, .045)
	for i = -1, 1 do
		local hem = d:circle("Hem", .5 + i * .2, .82, .22, lerp(body, tint, .55))
		local _ = hem
	end
	-- arms
	for _, s in ipairs({ -1, 1 }) do
		local arm = d:ellipse("Arm", .5 + s * .33, .58, .16, .1, lerp(body, tint, .35), { Rotation = s * -30 })
		d:line(arm, nil, .035)
	end
	for _, s in ipairs({ -1, 1 }) do
		d:ellipse("Eye", .5 + s * .11, .42, .1, .15, INK)
		d:circle("EyeShine", .5 + s * .11 - .02, .39, .035, WHITE)
	end
	d:ellipse("Mouth", .5, .58, .09, .1, INK)
	d:shine(.4, .25, .2, .08, .45)
end

-- lightning bolt (three slanted bars)
K.Bolt = function(d, o)
	local col = o.Color or GOLD
	d:glow(col, 1.0, .7)
	local hi, lo = lerp(col, WHITE, .55), lerp(col, C(200, 80, 0), .45)
	local bars = { { .68, .06, .4, .54, .2 }, { .34, .5, .68, .5, .16 }, { .62, .47, .36, .9, .15 } }
	-- pass 1: one merged ink silhouette (a stroke per bar would cut the bolt into links), pass 2: the gold bolt
	for pass = 1, 2 do
		for _, b in ipairs(bars) do
			local grow = pass == 1 and .07 or 0
			local dx, dy = b[3] - b[1], b[4] - b[2]
			local len = math.sqrt(dx * dx + dy * dy)
			local ex, ey = dx / len * grow / 2, dy / len * grow / 2
			local f = d:bar(pass == 1 and "Edge" or "Bar", b[1] - ex, b[2] - ey, b[3] + ex, b[4] + ey, b[5] + grow, pass == 1 and INK or WHITE)
			d:round(f, .12)
			if pass == 2 then
				d:grad(f, hi, lo, 0)
			end
		end
	end
	d:shine(.58, .2, .06, .16, .45)
end

-- potion bottle: round flask with glowing brew, neck, cork, bubbles; Glow = brew colour
K.Potion = function(d, o)
	local brew = o.Glow or NEON
	local glass = o.Color or C(200, 230, 255)
	d:glow(brew, 1.05, .7)
	local neck = d:frame("Neck", .5, .25, .2, .24, lerp(glass, WHITE, .3), { BackgroundTransparency = .25 })
	d:round(neck, .25)
	d:line(neck, nil, .04)
	local cork = d:frame("Cork", .5, .12, .24, .12, WHITE)
	d:round(cork, .3)
	d:grad(cork, C(196, 140, 90), C(120, 76, 40), 90)
	d:line(cork, nil, .035)
	local flask = d:circle("Flask", .5, .62, .64, lerp(glass, WHITE, .2), { BackgroundTransparency = .35 })
	d:line(flask, nil, .05)
	local liquid = d:ellipse("Brew", .5, .7, .54, .42, WHITE)
	d:grad(liquid, lerp(brew, WHITE, .45), lerp(brew, INK, .35), 90)
	local surface = d:ellipse("Surface", .5, .52, .5, .08, lerp(brew, WHITE, .6))
	local _ = surface
	for _, b in ipairs({ { .42, .66, .07 }, { .58, .74, .05 }, { .5, .6, .04 } }) do
		d:circle("Bubble", b[1], b[2], b[3], lerp(brew, WHITE, .7), { BackgroundTransparency = .2 })
	end
	d:shine(.36, .52, .1, .2, .4)
end

-- bat: body + head with ears + two scalloped wings; Glow = eyes
K.Bat = function(d, o)
	local body = o.Color or C(46, 24, 70)
	local eye = o.Glow or C(255, 170, 60)
	for _, s in ipairs({ -1, 1 }) do
		local wing = d:ellipse("Wing", .5 + s * .26, .48, .44, .22, WHITE, { Rotation = s * 14 })
		d:grad(wing, lerp(body, WHITE, .2), body, 90)
		d:line(wing, nil, .035)
		local tip = d:frame("WingTip", .5 + s * .44, .42, .1, .16, lerp(body, WHITE, .1), { Rotation = s * 30 })
		d:round(tip, .3)
		local ear = d:frame("Ear", .5 + s * .07, .32, .07, .12, body, { Rotation = s * 18 })
		d:round(ear, .2)
	end
	local torso = d:ellipse("Torso", .5, .52, .22, .3, WHITE)
	d:grad(torso, lerp(body, WHITE, .25), body, 90)
	d:line(torso, nil, .035)
	local head = d:circle("Head", .5, .4, .2, lerp(body, WHITE, .15))
	d:line(head, nil, .03)
	for _, s in ipairs({ -1, 1 }) do
		d:circle("Eye", .5 + s * .045, .4, .05, eye)
	end
end

-- cauldron: iron pot, rim, glowing brew, bubbles, legs and green flames; Glow = brew colour
K.Cauldron = function(d, o)
	local brew = o.Glow or NEON
	local iron = o.Color or C(84, 76, 98)
	d:glow(brew, 1.0, .74)
	for _, s in ipairs({ -1, 1 }) do
		local leg = d:frame("Leg", .5 + s * .2, .86, .09, .14, lerp(iron, INK, .5))
		d:round(leg, .3)
	end
	for i = -1, 1 do
		local flame = d:ellipse("Flame", .5 + i * .14, .88, .12, .18, WHITE)
		d:grad(flame, C(220, 255, 170), C(40, 170, 70), 90)
	end
	local pot = d:ellipse("Pot", .5, .6, .76, .56, WHITE)
	d:grad(pot, lerp(iron, WHITE, .2), lerp(iron, INK, .55), 90)
	d:line(pot, nil, .05)
	local band = d:frame("Band", .5, .62, .74, .05, lerp(iron, WHITE, .3), { BackgroundTransparency = .3 })
	local _ = band
	local rim = d:ellipse("Rim", .5, .36, .84, .16, WHITE)
	d:grad(rim, lerp(iron, WHITE, .35), lerp(iron, INK, .3), 90)
	d:line(rim, nil, .045)
	local liquid = d:ellipse("Brew", .5, .36, .7, .1, WHITE)
	d:grad(liquid, lerp(brew, WHITE, .5), brew, 90)
	for _, b in ipairs({ { .4, .25, .1 }, { .56, .18, .07 }, { .64, .28, .06 } }) do
		d:circle("Bubble", b[1], b[2], b[3], lerp(brew, WHITE, .55), { BackgroundTransparency = .15 })
	end
	d:shine(.33, .55, .1, .2, .6)
end

-- bell: dome, flared lip, clapper, hanging loop
K.Bell = function(d, o)
	local metal = o.Color or C(196, 170, 110)
	local loop = d:circle("Loop", .5, .14, .14, C(0, 0, 0), { BackgroundTransparency = 1 })
	d:line(loop, lerp(metal, INK, .4), .05)
	local dome = d:frame("Dome", .5, .46, .5, .58, WHITE)
	d:round(dome, .5)
	d:grad(dome, lerp(metal, WHITE, .4), lerp(metal, INK, .45), 0)
	d:line(dome, nil, .045)
	local lip = d:ellipse("Lip", .5, .74, .78, .16, WHITE)
	d:grad(lip, lerp(metal, WHITE, .25), lerp(metal, INK, .5), 90)
	d:line(lip, nil, .045)
	local clapper = d:circle("Clapper", .5, .86, .14, lerp(metal, INK, .6))
	d:line(clapper, nil, .035)
	d:shine(.4, .4, .08, .22, .5)
end

-- quest scroll: parchment with rolled ends and lines
K.Scroll = function(d, o)
	local paper = o.Color or C(244, 226, 186)
	local sheet = d:frame("Sheet", .5, .5, .62, .6, WHITE)
	d:round(sheet, .1)
	d:grad(sheet, lerp(paper, WHITE, .3), lerp(paper, C(170, 120, 70), .4), 90)
	d:line(sheet, nil, .045)
	for _, y in ipairs({ .2, .8 }) do
		local roll = d:frame("Roll", .5, y, .78, .14, WHITE)
		d:round(roll, "pill")
		d:grad(roll, lerp(paper, WHITE, .2), lerp(paper, C(140, 90, 50), .5), 90)
		d:line(roll, nil, .045)
	end
	for i = 0, 2 do
		local l = d:frame("Line", .5, .38 + i * .12, .4 - (i == 2 and .14 or 0), .035, C(140, 96, 60), { BackgroundTransparency = .2 })
		d:round(l, "pill")
	end
	local seal = d:circle("Seal", .66, .66, .14, o.Glow or BLOOD)
	d:line(seal, nil, .03)
end

-- haunted door: arched planks, a knocker, a glowing window
K.Door = function(d, o)
	local wood = o.Color or C(120, 74, 46)
	local frameF = d:frame("Arch", .5, .54, .62, .84, WHITE)
	d:round(frameF, .45)
	d:grad(frameF, lerp(wood, WHITE, .15), lerp(wood, INK, .45), 90)
	d:line(frameF, nil, .05)
	for _, x in ipairs({ -.15, 0, .15 }) do
		d:frame("Plank", .5 + x, .6, .02, .62, lerp(wood, INK, .5), { BackgroundTransparency = .3 })
	end
	local win = d:circle("Window", .5, .3, .18, o.Glow or C(255, 200, 90))
	d:line(win, nil, .03)
	local knob = d:circle("Knocker", .66, .6, .1, C(0, 0, 0), { BackgroundTransparency = 1 })
	d:line(knob, GOLD, .04)
end

-- check mark (two bars) in a disc
K.Check = function(d, o)
	local col = o.Color or WHITE
	local a = d:frame("Short", .37, .58, .12, .3, WHITE, { Rotation = -45 })
	d:round(a, "pill")
	d:grad(a, col, lerp(col, C(170, 200, 170), .4), 90)
	d:line(a, nil, .045)
	local b = d:frame("Long", .58, .48, .12, .56, WHITE, { Rotation = 38 })
	d:round(b, "pill")
	d:grad(b, col, lerp(col, C(170, 200, 170), .4), 90)
	d:line(b, nil, .045)
end

-- padlock
K.Lock = function(d, o)
	local metal = o.Color or C(200, 196, 214)
	local shackle = d:frame("Shackle", .5, .34, .4, .44, C(0, 0, 0), { BackgroundTransparency = 1 })
	d:round(shackle, .5)
	d:line(shackle, lerp(metal, INK, .3), .09)
	local body = d:frame("Body", .5, .64, .6, .44, WHITE)
	d:round(body, .2)
	d:grad(body, lerp(metal, WHITE, .3), lerp(metal, INK, .45), 90)
	d:line(body, nil, .045)
	d:circle("Hole", .5, .6, .1, INK)
	d:frame("Slot", .5, .7, .05, .12, INK)
end

-- bone (for Bones rewards)
K.Bone = function(d, o)
	local col = o.Color or BONE
	local shaft = d:frame("Shaft", .5, .5, .62, .16, WHITE, { Rotation = -30 })
	d:round(shaft, "pill")
	d:grad(shaft, lerp(col, WHITE, .4), lerp(col, C(150, 120, 90), .4), 90)
	d:line(shaft, nil, .04)
	for _, p in ipairs({ { .2, .58 }, { .28, .72 }, { .72, .28 }, { .8, .42 } }) do
		local k = d:circle("Knuckle", p[1], p[2], .2, WHITE)
		d:grad(k, lerp(col, WHITE, .45), lerp(col, C(150, 120, 90), .35), 90)
		d:line(k, nil, .04)
	end
end

-- star (four-point sparkle)
K.Star = function(d, o)
	local col = o.Color or GOLD
	d:glow(col, 1.0, .65)
	for _, r in ipairs({ 0, 90 }) do
		local f = d:frame("Ray", .5, .5, .18, .86, WHITE, { Rotation = r })
		d:round(f, "pill")
		d:grad(f, lerp(col, WHITE, .6), col, 90)
	end
	local core = d:frame("Core", .5, .5, .34, .34, WHITE, { Rotation = 45 })
	d:round(core, .15)
	d:grad(core, WHITE, col, 90)
	d:line(core, nil, .035)
end

-- crown (titles)
K.Crown = function(d, o)
	local col = o.Color or GOLD
	for i = -1, 1 do
		local spike = d:frame("Spike", .5 + i * .22, .4 - (i == 0 and .06 or 0), .2, .2, WHITE, { Rotation = 45 })
		d:round(spike, .15)
		d:grad(spike, lerp(col, WHITE, .4), col, 90)
		d:line(spike, nil, .04)
		d:circle("Gem", .5 + i * .22, .28 - (i == 0 and .06 or 0), .1, i == 0 and (o.Glow or BLOOD) or C(120, 220, 255))
	end
	local band = d:frame("Band", .5, .62, .7, .3, WHITE)
	d:round(band, .2)
	d:grad(band, lerp(col, WHITE, .35), lerp(col, C(170, 100, 10), .5), 90)
	d:line(band, nil, .045)
	d:circle("BandGem", .5, .62, .12, o.Glow or BLOOD)
end

-- pickaxe (skins)
K.Pickaxe = function(d, o)
	local head = o.Color or C(200, 210, 230)
	local handle = d:bar("Handle", .2, .86, .62, .32, .1, WHITE)
	d:round(handle, "pill")
	d:grad(handle, C(176, 124, 82), C(100, 64, 40), 90)
	d:line(handle, nil, .04)
	-- the head: two curved arms meeting over the handle's end
	for _, a in ipairs({ { .6, .3, .18, .2 }, { .6, .3, .86, .54 } }) do
		local arm = d:bar("Arm", a[1], a[2], a[3], a[4], .13, WHITE)
		d:round(arm, .45)
		d:grad(arm, lerp(head, WHITE, .45), lerp(head, INK, .35), 90)
		d:line(arm, nil, .045)
	end
	local cap = d:circle("Socket", .6, .3, .16, lerp(head, INK, .2))
	d:line(cap, nil, .04)
	d:circle("Gem", .6, .3, .08, o.Glow or NEON)
end

-- dog head (event dogs)
K.Dog = function(d, o)
	local fur = o.Color or C(230, 150, 70)
	for _, s in ipairs({ -1, 1 }) do
		local ear = d:ellipse("Ear", .5 + s * .3, .36, .2, .38, WHITE, { Rotation = s * 24 })
		d:grad(ear, lerp(fur, INK, .2), lerp(fur, INK, .5), 90)
		d:line(ear, nil, .04)
	end
	local head = d:ellipse("Head", .5, .52, .62, .58, WHITE)
	d:grad(head, lerp(fur, WHITE, .25), lerp(fur, INK, .25), 90)
	d:line(head, nil, .045)
	local muzzle = d:ellipse("Muzzle", .5, .66, .34, .24, lerp(fur, WHITE, .55))
	local _ = muzzle
	d:ellipse("Nose", .5, .6, .12, .08, INK)
	for _, s in ipairs({ -1, 1 }) do
		d:circle("Eye", .5 + s * .13, .46, .08, INK)
		d:circle("EyeShine", .5 + s * .13 - .015, .44, .03, WHITE)
	end
end

-- open book (DogDex)
K.Book = function(d, o)
	local cover = o.Color or C(120, 62, 200)
	for _, s in ipairs({ -1, 1 }) do
		local page = d:frame("Page", .5 + s * .2, .52, .38, .62, WHITE, { Rotation = s * 4 })
		d:round(page, .1)
		d:grad(page, C(255, 250, 236), C(220, 206, 180), 90)
		d:line(page, cover, .05)
		for i = 0, 2 do
			d:frame("Text", .5 + s * .2, .38 + i * .1, .24, .025, C(150, 130, 120), { BackgroundTransparency = .3, Rotation = s * 4 })
		end
	end
	d:frame("Spine", .5, .54, .04, .66, lerp(cover, INK, .3))
end

Icons.Kinds = {}
for name in pairs(K) do
	table.insert(Icons.Kinds, name)
end
table.sort(Icons.Kinds)
Icons.Draw = K

---------------------------------------------------------------------------------------------------------------------
-- handles
---------------------------------------------------------------------------------------------------------------------
local Handle = {}
Handle.__index = Handle

function Handle:Fit()
	local root = self.Instance
	if not root or not root.Parent then
		return
	end
	local ok, size = pcall(function()
		return root.AbsoluteSize
	end)
	local px = ok and size and math.min(size.X, size.Y) or 0
	if px < 2 then
		px = self.Px
	end
	if math.abs(px - (self.Fitted or -1)) < .5 then
		return
	end
	self.Fitted = px
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("UIStroke") then
			local k = d:GetAttribute("HwK")
			if type(k) == "number" then
				d.Thickness = math.max(1, k * px)
			end
		end
	end
end

function Handle:Set(kind: string?, opts: { [string]: any }?)
	kind = kind or self.Kind
	opts = opts or self.Opts
	local key = tostring(kind) .. "|" .. (opts and table.concat({ tostring(opts.Color), tostring(opts.Glow), tostring(opts.State), tostring(opts.Face),
		tostring(opts.Dim), tostring(opts.Outline) }, "|") or "")
	if key == self.Key then
		return self
	end
	self.Key, self.Kind, self.Opts = key, kind, opts or {}
	local root = self.Instance
	for _, c in ipairs(root:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local fn = K[kind]
	if not fn then
		return self
	end
	local o = self.Opts
	local d = setmetatable({ Root = root, Z = 0, Base = root.ZIndex, Px = self.Px, Outline = o.Outline }, Draw)
	local ok, err = pcall(fn, d, o)
	if not ok then
		warn("Halloween Icons " .. tostring(kind) .. ": " .. tostring(err))
	end
	if o.Dim and o.Dim > 0 then
		-- locked / not reached: a dark veil over the drawing (keeps the silhouette readable)
		local veil = d:circle("Dim", .5, .5, .9, C(20, 10, 34), { BackgroundTransparency = 1 - .7 * math.clamp(o.Dim, 0, 1) })
		local _ = veil
	end
	self.Fitted = nil
	self:Fit()
	return self
end

function Handle:Destroy()
	if self.Conn then
		self.Conn:Disconnect()
	end
	if self.Instance then
		self.Instance:Destroy()
	end
end

-- Icons.New(parent, kind, opts) -> handle. The root Frame is transparent; place / size it like any GuiObject
-- (default: fills the parent).
function Icons.New(parent: Instance?, kind: string, opts: { [string]: any }?): any
	opts = opts or {}
	local root = Instance.new("Frame")
	root.Name = opts.Name or "HwIcon"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ZIndex = opts.ZIndex or 2
	root.AnchorPoint = opts.AnchorPoint or Vector2.zero
	root.Position = opts.Position or UDim2.new()
	root.Size = opts.FrameSize or UDim2.fromScale(1, 1)
	root:SetAttribute("NoTranslate", true)
	local self = setmetatable({ Instance = root, Px = opts.Size or 40, Kind = kind, Opts = opts }, Handle)
	root.Parent = parent
	self:Set(kind, opts)
	local ok, conn = pcall(function()
		return root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			self:Fit()
		end)
	end)
	if ok then
		self.Conn = conn
	end
	return self
end

-- the reward row -> icon kind / colours (reward cards, chips)
function Icons.ForReward(row: { [string]: any }): (string, { [string]: any })
	local kind = row.Kind
	if kind == "Candy" then
		return "Candy", {}
	elseif kind == "Bones" then
		return "Bone", {}
	elseif kind == "Block" then
		local cursed = row.Id == "Cursed Pumpkin"
		return "Pumpkin", cursed and { Color = C(96, 40, 140), Glow = C(200, 120, 255) } or {}
	elseif kind == "Skin" then
		return "Pickaxe", {}
	elseif kind == "Dog" then
		return "Dog", {}
	elseif kind == "Decor" then
		return "Ghost", { Glow = NEON }
	elseif kind == "Mutation" then
		return "Potion", { Glow = C(190, 110, 255) }
	elseif kind == "Title" then
		return "Crown", {}
	elseif kind == "Cash" then
		return "Star", { Color = GOLD }
	end
	return "Star", {}
end

return Icons
