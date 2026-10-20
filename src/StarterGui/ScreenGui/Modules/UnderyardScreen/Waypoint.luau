-- SHOW THE WAY inside THE UNDERYARD (Modules.UnderyardScreen.Waypoint, WP-L). The island's PathGuide routes the main map;
-- inside the Underyard the Underyard window points at a Bell Square / district anchor with this client-only marker:
-- a beam from the character to the target, a pulsing ground ring and a floating label with the distance.
--   Waypoint.Show(position, label, {Color?, Arrive?, Timeout?}) -> true | false   (replaces the previous one)
--   Waypoint.Clear(reason?) · Waypoint.Active() -> {Label, Position, Reason?} | nil
-- Everything lives in Workspace.DOGROTS_UnderyardWay + one attachment on the HumanoidRootPart; built in pcall, torn down
-- on arrival, timeout, leaving the Underyard, respawn or Clear. Reduced Motion: no bobbing, no scrolling beam. Low quality:
-- no beam texture.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local W = {}

local player = Players.LocalPlayer
local C = Color3.fromRGB
local VIOLET = C(150, 80, 230)
local MOON = C(150, 200, 255)

local active: any = nil

local function shared(): any
	local folder = RS:FindFirstChild("Halloween")
	local mod = folder and folder:FindFirstChild("Shared")
	if not mod then
		return nil
	end
	local ok, m = pcall(require, mod)
	return ok and m or nil
end

local function reduced(): boolean
	local s = shared()
	if s and s.ReducedMotion then
		local ok, v = pcall(s.ReducedMotion)
		if ok and v then
			return true
		end
	end
	local ok, v = pcall(function()
		return game:GetService("GuiService").ReducedMotionEnabled
	end)
	return ok and v == true
end

local function low(): boolean
	local s = shared()
	if s and s.Low then
		local ok, v = pcall(s.Low)
		return ok and v == true
	end
	return false
end

local function rootPart(): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return (r and r:IsA("BasePart")) and r or nil
end

function W.Clear(reason: string?)
	local a = active
	active = nil
	if not a then
		return
	end
	a.Reason = reason or "clear"
	for _, c in ipairs(a.Conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	for i = #a.Owned, 1, -1 do
		pcall(function()
			a.Owned[i]:Destroy()
		end)
	end
end

function W.Active(): any
	if not active then
		return nil
	end
	return { Label = active.Label, Position = active.Position }
end

-- position: world point of the target (an Underyard anchor); label: what is there (already localized)
function W.Show(position: Vector3, label: string, opts: { [string]: any }?): boolean
	W.Clear("replaced")
	local o = opts or {}
	local color = typeof(o.Color) == "Color3" and o.Color or VIOLET
	local arrive = tonumber(o.Arrive) or 10
	local timeout = tonumber(o.Timeout) or 180
	local a: any = { Label = label, Position = position, Owned = {}, Conns = {}, Started = os.clock() }
	local ok, err = pcall(function()
		local folder = Instance.new("Folder")
		folder.Name = "DOGROTS_UnderyardWay"
		table.insert(a.Owned, folder)
		local anchor = Instance.new("Part")
		anchor.Name = "Target"
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CastShadow = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(1, 1, 1)
		anchor.CFrame = CFrame.new(position)
		anchor.Parent = folder
		local a1 = Instance.new("Attachment")
		a1.Name = "WayEnd"
		a1.Parent = anchor
		-- the ground ring (anchors stand ~3 studs above the floor)
		local ring = Instance.new("Part")
		ring.Name = "Ring"
		ring.Shape = Enum.PartType.Cylinder
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Material = Enum.Material.Neon
		ring.Color = color
		ring.Transparency = .45
		ring.Size = Vector3.new(.2, 9, 9)
		ring.CFrame = CFrame.new(position - Vector3.new(0, 2.85, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = folder
		-- the floating label
		local bb = Instance.new("BillboardGui")
		bb.Name = "Label"
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Size = UDim2.fromOffset(220, 74)
		bb.StudsOffset = Vector3.new(0, 4.5, 0)
		bb.MaxDistance = 2000
		bb.ResetOnSpawn = false
		bb:SetAttribute("NoTranslate", true)
		bb.Adornee = anchor
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Size = UDim2.new(1, 0, 0, 30)
		title.Font = Enum.Font.FredokaOne
		title.TextScaled = true
		title.TextColor3 = Color3.new(1, 1, 1)
		title.TextStrokeColor3 = C(20, 10, 34)
		title.TextStrokeTransparency = .2
		title.Text = label
		title:SetAttribute("NoTranslate", true)
		title.Parent = bb
		local dist = title:Clone()
		dist.Name = "Distance"
		dist.Position = UDim2.fromOffset(0, 30)
		dist.Size = UDim2.new(1, 0, 0, 20)
		dist.TextColor3 = MOON
		dist.Text = ""
		dist.Parent = bb
		local arrow = title:Clone()
		arrow.Name = "Arrow"
		arrow.Position = UDim2.fromOffset(0, 50)
		arrow.Size = UDim2.new(1, 0, 0, 22)
		arrow.TextColor3 = color
		arrow.Text = "▼"
		arrow.Parent = bb
		bb.Parent = folder
		folder.Parent = workspace
		a.Ring, a.Distance, a.Arrow, a.Anchor = ring, dist, arrow, anchor
		-- the beam from the character
		local function bindBeam()
			if a.Beam then
				pcall(function()
					a.Beam:Destroy()
				end)
				a.Beam = nil
			end
			if a.A0 then
				pcall(function()
					a.A0:Destroy()
				end)
				a.A0 = nil
			end
			local r = rootPart()
			if not r then
				return
			end
			local a0 = Instance.new("Attachment")
			a0.Name = "DOGROTS_UnderyardWayStart"
			a0.Position = Vector3.new(0, -1.5, 0)
			a0.Parent = r
			table.insert(a.Owned, a0)
			local beam = Instance.new("Beam")
			beam.Name = "Way"
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.FaceCamera = true
			beam.Width0, beam.Width1 = 1.1, 2.4
			beam.LightEmission = 1
			beam.Color = ColorSequence.new(MOON, color)
			beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .85), NumberSequenceKeypoint.new(.2, .3), NumberSequenceKeypoint.new(1, .15) })
			beam.Segments = 1
			if not low() then
				beam.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				beam.TextureMode = Enum.TextureMode.Wrap
				beam.TextureLength = 3
				beam.TextureSpeed = reduced() and 0 or 1.2
			end
			beam.Parent = folder
			a.Beam, a.A0 = beam, a0
		end
		bindBeam()
		table.insert(a.Conns, player.CharacterAdded:Connect(function()
			task.defer(bindBeam)
		end))
		table.insert(a.Conns, player:GetAttributeChangedSignal("UyInZone"):Connect(function()
			if player:GetAttribute("UyInZone") == false then
				W.Clear("left")
			end
		end))
		local still = reduced()
		table.insert(a.Conns, RunService.Heartbeat:Connect(function()
			if active ~= a then
				return
			end
			local t = os.clock() - a.Started
			if t > timeout then
				W.Clear("timeout")
				return
			end
			local r = rootPart()
			if r then
				local d = (r.Position - position).Magnitude
				a.Distance.Text = tostring(math.floor(d + .5)) .. " m"
				if d <= arrive then
					W.Clear("arrived")
					return
				end
			end
			if not still then
				a.Arrow.Position = UDim2.fromOffset(0, 50 + math.floor(math.sin(t * 4) * 4))
				a.Ring.Transparency = .45 + .25 * math.sin(t * 3)
			end
		end))
	end)
	if not ok then
		warn("Underyard waypoint: " .. tostring(err))
		active = a
		W.Clear("error")
		return false
	end
	active = a
	return true
end

return W
