-- Client state of NIGHT OF THE BURIED MOON (StarterPlayerScripts.HalloweenClient.State).
-- State.View          latest profile view (Features.Halloween shape: Candy, Curse, Cauldron, Quests, Rush, Skins...)
-- State.Server        latest server view (Exorcism, ServerRushUntil, MutationBoostUntil)
-- State.Request(action, args) -> ok, result   (RS.Halloween.Remotes.Request; refreshes View; never throws)
-- State.BloodMoon() / State.Boss() / State.Exorcism()   live server attributes as tables
-- State.InZone() / State.ZoneWeight()                   local character / camera position in THE DEAD YARD
-- Every server Signal is re-fired on the Bus as "Signal" {Kind, Data} (and Toast / CandyGain / StateChanged helpers).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Bus = require(Halloween:WaitForChild("Bus"))
local Layout = Shared.Layout

local State = { View = nil, Server = nil, Ready = false }
local player = Players.LocalPlayer
local remotes = Halloween:WaitForChild("Remotes")
local stateFolder = Halloween:WaitForChild("State")

local function setView(view)
	if type(view) ~= "table" then
		return
	end
	State.View = view
	Bus.Fire("StateChanged", { View = view })
end

function State.Request(action: string, args: any?): (boolean, any)
	local remote = remotes:FindFirstChild("Request")
	if not remote then
		return false, "Not ready"
	end
	local ok, a, b = pcall(function()
		return remote:InvokeServer(action, args or {})
	end)
	if not ok then
		return false, "Connection problem; try again"
	end
	if a and type(b) == "table" and type(b.View) == "table" then
		setView(b.View)
	end
	return a == true, b
end

local function attrs(inst: Instance?): { [string]: any }
	return inst and inst:GetAttributes() or {}
end

function State.BloodMoon()
	return Shared.BloodMoonState(Shared.Now())
end

function State.Boss()
	return attrs(stateFolder:FindFirstChild("Boss"))
end

function State.Exorcism()
	return attrs(stateFolder:FindFirstChild("Exorcism"))
end

function State.Root(): BasePart?
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

function State.InZone(): boolean
	local root = State.Root()
	return root ~= nil and Layout.InZone(root.Position, 2)
end

function State.ZoneWeight(feather: number?): number
	local cam = workspace.CurrentCamera
	local pos = cam and cam.CFrame.Position or (State.Root() and State.Root().Position)
	if not pos then
		return 0
	end
	return Layout.Weight(pos, feather)
end

function State.Candy(): number
	return player:GetAttribute("MoonCandy") or (State.View and State.View.Candy) or 0
end

function State.Curse(): number
	return player:GetAttribute("MoonCurse") or 0
end

function State.Start(ctx)
	local signal = remotes:WaitForChild("Signal")
	signal.OnClientEvent:Connect(function(kind, data)
		if kind == "View" and type(data) == "table" then
			setView(data.View)
		elseif kind == "Toast" and type(data) == "table" then
			Bus.Fire("Toast", data)
		elseif kind == "CandyFx" and type(data) == "table" then
			Bus.Fire("CandyGain", data)
		end
		Bus.Fire("Signal", { Kind = kind, Data = data })
	end)
	-- zone enter / exit for everyone else
	task.spawn(function()
		local inside = nil
		while true do
			local now = State.InZone()
			if now ~= inside then
				inside = now
				Bus.Fire("ZoneChanged", { Inside = now })
			end
			task.wait(.25)
		end
	end)
	task.spawn(function()
		for attempt = 1, 90 do
			local ok, res = State.Request("Hello")
			if ok and type(res) == "table" then
				State.Server = res.Server
				State.Ready = true
				Bus.Fire("Ready", { View = State.View, Server = res.Server })
				return
			end
			task.wait(math.min(2 + attempt * .25, 6))
		end
	end)
end

return State
