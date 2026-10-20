-- Event on/off world switch + shared world prompts (ServerScriptService.Halloween.World).
-- The built place ships with the event ON: the COMING SOON cube is hidden and THE DEAD YARD
-- (Workspace.DOGROTS_District.38_DeadYard) plus the main-map layer (39_HalloweenLayer) are in the place.
-- With Config.HalloweenEventEnabled = false the server restores the cube (opaque, solid, COMING SOON faces), removes the
-- event geometry and restores every existing part the build changed (attributes Halloween_Original*). Player data is
-- never touched.
-- [WP-F] Chapter II: 40_Underyard and 41_HalloweenCalendar go with the event too; the church edit (38_DeadYard.Church:
-- doors, slit, portal, cracks, FX rails) lives inside 38_DeadYard, so it and the GrandCrypt parts it replaced go with
-- the yard. World.Enable puts the church in its baseline (doors closed, portal and cracks hidden): the open church
-- is per player, drawn client-side by HalloweenClient.Reveal from the Chapter2RevealSeen flag.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Config = Shared.Config
local Layout = Shared.Layout

local World = {}

local function district()
	return workspace:FindFirstChild("DOGROTS_District")
end

function World.Cube(): BasePart?
	local d = district()
	local a = d and d:FindFirstChild("37_AttractionRefresh")
	local m = a and a:FindFirstChild("GlobalEventComingSoon")
	return m and m:FindFirstChild("OpaqueBlackCuboid")
end

function World.DeadYard(): Model?
	local d = district()
	return d and d:FindFirstChild("38_DeadYard")
end

local function restoreOriginals(root: Instance)
	for _, inst in ipairs(root:GetDescendants()) do
		local c = inst:GetAttribute("Halloween_OriginalColor")
		if typeof(c) == "Color3" then
			pcall(function()
				(inst :: any).Color = c
			end)
		end
		local t = inst:GetAttribute("Halloween_OriginalTransparency")
		if type(t) == "number" and inst:IsA("BasePart") then
			inst.Transparency = t
		end
		local col = inst:GetAttribute("Halloween_OriginalCanCollide")
		if type(col) == "boolean" and inst:IsA("BasePart") then
			inst.CanCollide = col
		end
		local q = inst:GetAttribute("Halloween_OriginalCanQuery")
		if type(q) == "boolean" and inst:IsA("BasePart") then
			inst.CanQuery = q
		end
		local en = inst:GetAttribute("Halloween_OriginalEnabled")
		if type(en) == "boolean" then
			pcall(function()
				(inst :: any).Enabled = en
			end)
		end
	end
end

function World.Disable()
	local cube = World.Cube()
	if cube then
		cube.Transparency = 0
		cube.CanCollide = true
		cube.CanQuery = true
		cube.CastShadow = true
		for _, g in ipairs(cube:GetChildren()) do
			if g:IsA("SurfaceGui") then
				g.Enabled = true
			end
		end
	end
	local d = district()
	if d then
		for _, name in ipairs({ "38_DeadYard", "39_HalloweenLayer", "40_Underyard", "41_HalloweenCalendar" }) do -- [WP-F] + Chapter II
			local m = d:FindFirstChild(name)
			if m then
				m:Destroy()
			end
		end
		restoreOriginals(d)
	end
	local live = workspace:FindFirstChild("HalloweenLive")
	if live then
		live:Destroy()
	end
	local state = Halloween:FindFirstChild("State")
	if state then
		state:SetAttribute("Enabled", false)
	end
end

-- [WP-F] the church's shared baseline (38_DeadYard.Church, built by tools/edits/38_church.luau): both doors at their
-- ClosedPivot, every portal part and crack hidden, portal lights dark, the slit at its sealed glow. Nothing here is per
-- player: HalloweenClient.Reveal opens the church locally for players whose Chapter2RevealSeen flag is set.
function World.ResetChurch(): boolean
	local yard = World.DeadYard()
	local church = yard and yard:FindFirstChild("Church")
	if not church then
		return false
	end
	for _, inst in ipairs(church:GetDescendants()) do
		if inst:IsA("Model") and inst:GetAttribute("ChurchDoor") then
			local closed = inst:GetAttribute("ClosedPivot")
			if typeof(closed) == "CFrame" and inst.PrimaryPart then
				inst:PivotTo(closed)
			end
		elseif inst:IsA("BasePart") then
			local inPortal = inst:FindFirstAncestor("ChurchPortal") ~= nil
			local inCracks = inst:FindFirstAncestor("ChurchCracks") ~= nil
			if inPortal or inCracks then
				inst.Transparency = 1
			elseif inst:GetAttribute("ChurchSlit") then
				local t = inst:GetAttribute("RevealT")
				inst.Transparency = type(t) == "number" and t or .25
			end
		elseif inst:IsA("Light") and inst:GetAttribute("RevealBrightness") ~= nil then
			inst.Brightness = 0
		end
	end
	return true
end

function World.Enable()
	local cube = World.Cube()
	if cube then
		cube.Transparency = 1
		cube.CanCollide = false
		cube.CanQuery = false
		cube.CastShadow = false
		for _, g in ipairs(cube:GetChildren()) do
			if g:IsA("SurfaceGui") then
				g.Enabled = false
			end
		end
	end
	local state = Halloween:FindFirstChild("State")
	if state then
		state:SetAttribute("Enabled", true)
		state:SetAttribute("Season", Config.Season)
	end
	pcall(World.ResetChurch) -- [WP-F]
	if not Config.MainMapDecorations then
		local d = district()
		local layer = d and d:FindFirstChild("39_HalloweenLayer")
		if layer then
			layer:Destroy()
		end
		-- the recoloured street lamps go back to their own colours (the Dead Yard keeps its look)
		for _, inst in ipairs(d and d:GetDescendants() or {}) do
			if inst:GetAttribute("Halloween_MapLamp") then
				local c = inst:GetAttribute("Halloween_OriginalColor")
				if typeof(c) == "Color3" then
					pcall(function()
						(inst :: any).Color = c
					end)
				end
			end
		end
	end
end

-- a server prompt on one of the Persistent Dead Yard anchors
function World.Prompt(anchorName: string, props: { [string]: any }, onTriggered: (Player) -> ()): ProximityPrompt?
	local yard = World.DeadYard()
	local anchors = yard and yard:FindFirstChild("Anchors")
	local anchor = anchors and anchors:FindFirstChild(anchorName)
	if not anchor then
		warn("Halloween: missing Dead Yard anchor " .. anchorName)
		return nil
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = props.Name or ("Halloween" .. anchorName .. "Prompt")
	prompt.ActionText = props.ActionText or "OPEN"
	prompt.ObjectText = props.ObjectText or ""
	prompt.HoldDuration = props.HoldDuration or 0
	prompt.MaxActivationDistance = props.MaxActivationDistance or 14
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = props.KeyboardKeyCode or Enum.KeyCode.E
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt:SetAttribute("HalloweenPrompt", anchorName)
	prompt.Parent = anchor
	prompt.Triggered:Connect(function(player)
		if Shared.Enabled() then
			onTriggered(player)
		end
	end)
	return prompt
end

function World.OpenWindow(player: Player, tab: string?)
	local remote = RS:FindFirstChild("DogEconomyOpen")
	if remote then
		remote:FireClient(player, "Halloween", { Tab = tab })
	end
end

function World.Start(core)
	World.Enable()
	World.Prompt("Cauldron", { ActionText = "BREW", ObjectText = "HAUNTED CAULDRON", MaxActivationDistance = 16 }, function(player)
		if core.Near(player, Layout.Cauldron.Center, Config.Cauldron.Range + 6) then
			World.OpenWindow(player, "Cauldron")
		end
	end)
	-- arrivals: a player who respawns inside the closed pit or below the floor is put back at the gate
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(ch)
			task.wait(1)
			local root = ch:FindFirstChild("HumanoidRootPart")
			local pos = root and root.Position
			local zone = Layout.Zone
			-- inside the yard's footprint (x/z) and below the pit floor: fell through or spawned under the map
			if pos and pos.X >= zone.Min.X and pos.X <= zone.Max.X and pos.Z >= zone.Min.Z and pos.Z <= zone.Max.Z
				and pos.Y < Layout.Pit.FloorY - 6 then
				ch:PivotTo(CFrame.new(Layout.Arrival))
			end
		end)
	end)
end

return World
