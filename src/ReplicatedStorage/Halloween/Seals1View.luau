-- BELL SEALS I-IV · client helpers of the presenters (ReplicatedStorage.Halloween.Seals1View, WP-I). Client only.
-- Shared by HalloweenClient.Trials.Echo / Run / Mirror / Mine so each presenter stays about its activity:
--   View.Maid() -> {Give(conn | instance | fn), Clean()}      everything a run builds goes away together
--   View.Targets(kind, runId, onAdd(part), onRemove(part, reason)) -> stop()   the run's Strike target parts
--                                                 (Workspace.HalloweenLive.Targets, tag "HalloweenTarget", attributes
--                                                 Kind / UyRun; onRemove when EndReason appears or the part goes)
--   View.Root() -> Model? · View.Find(name, class?, within?) -> Instance?   the Underyard world (40_Underyard)
--   View.Audio(ctx, cue, where?, opts?) · View.FX(ctx, name, ...) · View.L(en, ru) · View.Reduced() · View.Quality()
--   View.Detail(high, medium, low) · View.Near(pos, dist) (camera distance) · View.Root position helpers
--   View.Fade(model | {parts}, seconds, toTransparency?, destroy?) · View.SetTransparency(model, t)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))

local View = {}
View.Shared = Shared
View.TAG = "HalloweenTarget"

function View.L(en: string, ru: string?): string
	return Shared.L(en, ru)
end

function View.Reduced(): boolean
	return Shared.ReducedMotion()
end

function View.Quality(): string
	return Shared.Quality()
end

function View.Detail(high: any, medium: any, low: any): any
	local q = Shared.Quality()
	if q == "Low" then
		return low
	elseif q == "Medium" then
		return medium
	end
	return high
end

function View.Now(): number
	return Shared.Now()
end

function View.Audio(ctx: any, cue: string, where: any?, opts: any?)
	local a = ctx and ctx.Audio
	if a and type(a.Play) == "function" then
		pcall(a.Play, cue, where, opts)
	end
end

function View.FX(ctx: any, name: string, ...: any)
	local f = ctx and ctx.FX
	local fn = f and f[name]
	if type(fn) == "function" then
		pcall(fn, ...)
	end
end

-- the trials host's helpers (ctx.Trials), each call protected
function View.Trials(ctx: any, name: string, ...: any): any
	local t = ctx and ctx.Trials
	local fn = t and t[name]
	if type(fn) == "function" then
		local ok, res = pcall(fn, ...)
		return ok and res or nil
	end
	return nil
end

function View.Folder(ctx: any): Instance
	local f = View.Trials(ctx, "Folder")
	if typeof(f) == "Instance" then
		return f
	end
	local existing = workspace:FindFirstChild("DOGROTS_TrialsFX")
	if existing then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "DOGROTS_TrialsFX"
	folder:SetAttribute("SelfManagedFX", true)
	folder.Parent = workspace
	return folder
end

function View.Player(): Player
	return Players.LocalPlayer
end

function View.RootPart(): BasePart?
	local ch = Players.LocalPlayer.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return (r and r:IsA("BasePart")) and r or nil
end

-- is pos within dist of the camera (animation culling)
function View.Near(pos: Vector3, dist: number): boolean
	local cam = workspace.CurrentCamera
	return cam == nil or (cam.CFrame.Position - pos).Magnitude <= dist
end

---------------------------------------------------------------------------------------------------------------------
-- maid
---------------------------------------------------------------------------------------------------------------------
function View.Maid(): any
	local items = {}
	local m: any = {}
	function m.Give(x: any): any
		table.insert(items, x)
		return x
	end
	function m.Clean()
		local list = items
		items = {}
		for i = #list, 1, -1 do
			local x = list[i]
			pcall(function()
				if typeof(x) == "RBXScriptConnection" then
					x:Disconnect()
				elseif typeof(x) == "Instance" then
					x:Destroy()
				elseif type(x) == "function" then
					x()
				elseif type(x) == "table" and type(x.Disconnect) == "function" then
					x.Disconnect()
				elseif type(x) == "table" and type(x.Destroy) == "function" then
					x.Destroy()
				end
			end)
		end
	end
	return m
end

---------------------------------------------------------------------------------------------------------------------
-- world lookups
---------------------------------------------------------------------------------------------------------------------
function View.Root(): Instance?
	local d = workspace:FindFirstChild("DOGROTS_District")
	return d and d:FindFirstChild("40_Underyard") or nil
end

-- the first descendant called `name` (of `class` when given; the Anchors folder holds parts with the same names as
-- several models), searched in `within` (a district model name or an instance) or the whole Underyard
function View.Find(name: string, class: string?, within: any?): Instance?
	local root = View.Root()
	if not root then
		return nil
	end
	local scope: Instance? = root
	if type(within) == "string" then
		scope = root:FindFirstChild(within) or root
	elseif typeof(within) == "Instance" then
		scope = within
	end
	local hit = (scope :: Instance):FindFirstChild(name, true)
	if hit and (class == nil or hit:IsA(class)) then
		return hit
	end
	for _, d in ipairs((scope :: Instance):GetDescendants()) do
		if d.Name == name and (class == nil or d:IsA(class)) then
			return d
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------
-- the run's Strike target parts
---------------------------------------------------------------------------------------------------------------------
function View.Targets(kind: string, runId: any, onAdd: (BasePart) -> (), onRemove: (BasePart, string?) -> ()): () -> ()
	local seen: { [BasePart]: { RBXScriptConnection } } = {}
	local alive = true
	local function mine(part: Instance): boolean
		return part:IsA("BasePart") and part:GetAttribute("Kind") == kind and part:GetAttribute("UyRun") == runId
	end
	local function drop(part: BasePart, reason: string?)
		local conns = seen[part]
		if not conns then
			return
		end
		seen[part] = nil
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		local ok, err = pcall(onRemove, part, reason)
		if not ok then
			warn("Seals1View: onRemove failed: " .. tostring(err))
		end
	end
	local function add(part: Instance)
		if not alive or seen[part :: BasePart] or not mine(part) then
			return
		end
		local p = part :: BasePart
		if p:GetAttribute("EndReason") then
			return
		end
		local conns = {}
		seen[p] = conns
		table.insert(conns, p:GetAttributeChangedSignal("EndReason"):Connect(function()
			drop(p, p:GetAttribute("EndReason"))
		end))
		table.insert(conns, p.AncestryChanged:Connect(function()
			if not p:IsDescendantOf(game) then
				drop(p, p:GetAttribute("EndReason") or "Gone")
			end
		end))
		local ok, err = pcall(onAdd, p)
		if not ok then
			warn("Seals1View: onAdd failed: " .. tostring(err))
		end
	end
	for _, part in ipairs(CollectionService:GetTagged(View.TAG)) do
		add(part)
	end
	local c1 = CollectionService:GetInstanceAddedSignal(View.TAG):Connect(function(part)
		task.defer(add, part)
	end)
	local c2 = CollectionService:GetInstanceRemovedSignal(View.TAG):Connect(function(part)
		if seen[part] then
			drop(part, part:GetAttribute("EndReason") or "Gone")
		end
	end)
	return function()
		alive = false
		c1:Disconnect()
		c2:Disconnect()
		for p in pairs(seen) do
			drop(p, "Stop")
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- looks
---------------------------------------------------------------------------------------------------------------------
local function partsOf(target: any): { BasePart }
	if type(target) == "table" then
		return target
	end
	local out = {}
	if typeof(target) == "Instance" then
		if target:IsA("BasePart") then
			table.insert(out, target)
		end
		for _, d in ipairs(target:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then
				table.insert(out, d)
			end
		end
	end
	return out
end

-- fades every visible part (and light / emitter) to `to` over `seconds`; destroy = remove the model afterwards
function View.Fade(target: any, seconds: number, to: number?, destroy: boolean?)
	local goal = to or 1
	for _, p in ipairs(partsOf(target)) do
		pcall(function()
			TweenService:Create(p, TweenInfo.new(seconds), { Transparency = math.max(p.Transparency, goal) }):Play()
		end)
	end
	if typeof(target) == "Instance" then
		for _, d in ipairs(target:GetDescendants()) do
			if d:IsA("Light") then
				pcall(function()
					TweenService:Create(d, TweenInfo.new(seconds), { Brightness = 0 }):Play()
				end)
			elseif d:IsA("ParticleEmitter") then
				d.Enabled = false
			end
		end
		if destroy then
			task.delay(seconds + .05, function()
				target:Destroy()
			end)
		end
	end
end

-- remembers each part's own transparency once (attribute UyT0) and sets base + extra
function View.SetTransparency(model: Instance, extra: number)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local t0 = d:GetAttribute("UyT0")
			if t0 == nil then
				t0 = d.Transparency
				d:SetAttribute("UyT0", t0)
			end
			d.Transparency = math.clamp(t0 + (1 - t0) * extra, 0, 1)
		end
	end
end

return View
