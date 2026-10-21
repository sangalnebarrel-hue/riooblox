-- Client helpers of the BELL SEALS V-VII presenters (ReplicatedStorage.Halloween.Seals2View, WP-J). Client only.
-- Shared by HalloweenClient.Trials.Doors / Choir / Bell / Assault / Resonance so each presenter stays about its activity:
--   View.Ctx(ctx?) -> ctx              the Halloween client ctx (or one built from ReplicatedStorage when a presenter boots
--                                      itself), with Trials fallbacks: Banner / Toast through Bus when the host has none
--   View.L(en, ru) · View.T(en)        self-localized pick · Russian of an English server message (Seals2, Underyard, ...)
--   View.Banner(ctx, en, ru, opts) · View.Toast(ctx, en, ru, kind)
--   View.Target(id) -> BasePart?        the server Strike target part (Workspace.HalloweenLive.Targets, attribute TargetId)
--   View.Root() -> Model? · View.Find(name, within?) -> Instance?   the Underyard world (40_Underyard) and a named model
--   View.Maid() -> {Give, Clean}        connections / instances / functions cleaned together (guaranteed teardown)
--   View.Animate(seconds, fn(alpha), done?) -> handle {Stop}   per-frame driver that always reaches alpha 1 (or stops)
--   View.Rest(model) -> CFrame · View.Pivot(model, cf)          a world model's untouched pivot + a safe local PivotTo
--   View.MothSwarm(from, to, opts) · View.MothCloud(pos, opts) -> {Destroy}   H13 moths (Models.Seals2.Moth)
--   View.Reduced() · View.Quality() · View.Detail(high, medium, low)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Bus = require(Halloween:WaitForChild("Bus"))

local View = {}
View.Shared = Shared
View.Bus = Bus
View.Config = require(Halloween:WaitForChild("Seals2Config"))
View.Base = require(Halloween:WaitForChild("Chapter2Config"))
View.Rules = require(Halloween:WaitForChild("Seals2Rules"))
View.Layout = require(Halloween:WaitForChild("UnderyardLayout"))
View.Models = require(Halloween:WaitForChild("Models"):WaitForChild("Seals2"))

local function color(t: any): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end
View.Color = color
View.Colors = {}
for k, v in pairs(View.Config.Client.Colors) do
	View.Colors[k] = color(v)
end

---------------------------------------------------------------------------------------------------------------------
-- ctx, language, messages
---------------------------------------------------------------------------------------------------------------------
local selfCtx: any = nil
function View.Ctx(ctx: any?): any
	if type(ctx) == "table" and ctx.Shared then
		return ctx
	end
	if not selfCtx then
		local okFx, FX = pcall(function()
			return require(Halloween:WaitForChild("FX"))
		end)
		local okA, Audio = pcall(function()
			return require(Halloween:WaitForChild("Audio"))
		end)
		selfCtx = { Player = Players.LocalPlayer, Shared = Shared, Config = Shared.Config, Bus = Bus, FX = okFx and FX or nil,
			Audio = okA and Audio or nil, Modules = {} }
	end
	return selfCtx
end

function View.L(en: string, ru: string): string
	return Shared.L(en, ru)
end

local dicts: any = nil
local function dictionaries(): { any }
	if dicts == nil then
		dicts = {}
		local folder = RS:FindFirstChild("Localization")
		for _, name in ipairs({ "Seals2", "Underyard", "Combat", "Halloween" }) do
			local inst = folder and folder:FindFirstChild(name)
			if inst then
				local ok, m = pcall(require, inst)
				if ok and type(m) == "table" then
					table.insert(dicts, m)
				end
			end
		end
	end
	return dicts
end

-- Russian of an English server message, else the message
function View.T(en: any): string
	if type(en) ~= "string" then
		return View.L("Connection problem; try again", "Проблема со связью, попробуй ещё раз")
	end
	if not Shared.IsRussian() then
		return en
	end
	for _, d in ipairs(dictionaries()) do
		local out = type(d.Translate) == "function" and d.Translate(en, "ru") or (type(d.Exact) == "table" and d.Exact[en])
		if type(out) == "string" then
			return out
		end
	end
	return Shared.T(en)
end

function View.Pair(pair: any): string
	if type(pair) == "table" then
		return Shared.L(pair[1] or "", pair[2])
	end
	return tostring(pair or "")
end

function View.Banner(ctx: any, en: string, ru: string, opts: any?)
	local o = opts or {}
	local trials = type(ctx) == "table" and ctx.Trials
	if trials and type(trials.Banner) == "function" then
		local ok = pcall(trials.Banner, en, ru, o)
		if ok then
			return
		end
	end
	Bus.Fire("Banner", { Title = Shared.L(en, ru), Subtitle = o.Sub and View.Pair(o.Sub) or "", Color = o.Color, Style = o.Style or "Event",
		Seconds = o.Seconds or 3, NoTranslate = true })
end

function View.Toast(ctx: any, en: string, ru: string, kind: string?)
	local trials = type(ctx) == "table" and ctx.Trials
	if trials and type(trials.Toast) == "function" then
		local ok = pcall(trials.Toast, en, ru)
		if ok then
			return
		end
	end
	Bus.Fire("Toast", { Text = Shared.L(en, ru), Kind = kind or "info", NoTranslate = true })
end

-- a world marker from the host (ctx.Trials.Mark), removed whatever handle shape the host returns
function View.Mark(ctx: any, pos: Vector3, en: string, ru: string): any
	local trials = type(ctx) == "table" and ctx.Trials
	if trials and type(trials.Mark) == "function" then
		local ok, h = pcall(trials.Mark, pos, en, ru)
		if ok then
			return h
		end
	end
	return nil
end

function View.Unmark(h: any)
	if h == nil then
		return
	end
	pcall(function()
		if typeof(h) == "Instance" then
			h:Destroy()
		elseif type(h) == "table" then
			local fn = h.Destroy or h.Remove or h.Clear or h.Hide
			if type(fn) == "function" then
				fn(h)
			end
		elseif type(h) == "function" then
			h()
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- quality
---------------------------------------------------------------------------------------------------------------------
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

---------------------------------------------------------------------------------------------------------------------
-- world lookups
---------------------------------------------------------------------------------------------------------------------
function View.Target(id: any): BasePart?
	id = tonumber(id)
	if not id or id <= 0 then
		return nil
	end
	local live = workspace:FindFirstChild("HalloweenLive")
	local folder = live and live:FindFirstChild("Targets")
	if not folder then
		return nil
	end
	local named = folder:FindFirstChild("Target_" .. id)
	if named and named:IsA("BasePart") then
		return named
	end
	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") and p:GetAttribute("TargetId") == id then
			return p
		end
	end
	return nil
end

function View.Root(): Instance?
	local d = workspace:FindFirstChild("DOGROTS_District")
	return d and d:FindFirstChild("40_Underyard") or nil
end

local found: { [string]: Instance } = {}
-- a named instance inside the Underyard (or inside `within`); cached while it stays in the world
function View.Find(name: string, within: Instance?): Instance?
	local key = name .. "@" .. (within and within:GetFullName() or "")
	local hit = found[key]
	if hit and hit.Parent and (within == nil or hit:IsDescendantOf(within)) then
		return hit
	end
	local root = within or View.Root()
	if not root then
		return nil
	end
	local inst = root:FindFirstChild(name, true)
	if inst then
		found[key] = inst
	end
	return inst
end

---------------------------------------------------------------------------------------------------------------------
-- maid + animation
---------------------------------------------------------------------------------------------------------------------
function View.Maid(): any
	local items = {}
	local maid = {}
	function maid.Give(x: any): any
		table.insert(items, x)
		return x
	end
	function maid.Clean()
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
				elseif type(x) == "table" then
					local fn = x.Disconnect or x.Destroy or x.Stop
					if type(fn) == "function" then
						fn(x)
					end
				end
			end)
		end
	end
	return maid
end

-- calls fn(alpha) every frame for `seconds` (alpha 0 -> 1), then done(); ReducedMotion jumps to the end at once.
-- -> {Stop(finish?)}: finish = true runs fn(1) + done
function View.Animate(seconds: number, fn: (number) -> (), done: (() -> ())?): any
	local handle = { Alive = true }
	local t0 = os.clock()
	local conn: any = nil
	local function stop(finish: boolean?)
		if not handle.Alive then
			return
		end
		handle.Alive = false
		if conn then
			conn:Disconnect()
			conn = nil
		end
		if finish then
			pcall(fn, 1)
			if done then
				pcall(done)
			end
		end
	end
	handle.Stop = stop
	if seconds <= 0 or Shared.ReducedMotion() then
		stop(true)
		return handle
	end
	pcall(fn, 0)
	conn = RunService.Heartbeat:Connect(function()
		local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
		local ok, err = pcall(fn, a)
		if not ok then
			warn("Seals2View animation failed: " .. tostring(err))
			stop(false)
			return
		end
		if a >= 1 then
			handle.Alive = false
			if conn then
				conn:Disconnect()
				conn = nil
			end
			if done then
				pcall(done)
			end
		end
	end)
	return handle
end

function View.Tween(inst: Instance, t: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween?
	local ok, tw = pcall(function()
		local tween = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goals)
		tween:Play()
		return tween
	end)
	return ok and tw or nil
end

function View.Ease(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- the pivot a world model had before any presenter touched it (client-side animation always starts from here)
local rest = setmetatable({}, { __mode = "k" })
function View.Rest(model: Instance): CFrame?
	if not model then
		return nil
	end
	local r = rest[model]
	if r then
		return r
	end
	local ok, cf = pcall(function()
		return (model :: any):GetPivot()
	end)
	if ok and typeof(cf) == "CFrame" then
		rest[model] = cf
		return cf
	end
	return nil
end

function View.Pivot(model: Instance, cf: CFrame)
	if model and model.Parent then
		pcall(function()
			(model :: any):PivotTo(cf)
		end)
	end
end

function View.ForgetRest(model: Instance)
	rest[model] = nil
end

---------------------------------------------------------------------------------------------------------------------
-- client folder + moths (H13 MOTH SWARM)
---------------------------------------------------------------------------------------------------------------------
function View.Folder(): Instance
	local folder = workspace:FindFirstChild("DOGROTS_Seals2FX")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DOGROTS_Seals2FX"
		folder:SetAttribute("SelfManagedFX", true)
		folder.Parent = workspace
	end
	return folder
end

local function flap(moth: Model, t: number, speed: number)
	local wl, wr = moth:FindFirstChild("WingL"), moth:FindFirstChild("WingR")
	local base = moth.PrimaryPart and moth.PrimaryPart.CFrame or CFrame.new()
	local a = math.sin(t * speed) * .9
	if wl and wl:IsA("Model") and wl.PrimaryPart then
		local root = base * CFrame.new(-.05, 0, 0)
		wl:PivotTo(root * CFrame.Angles(0, 0, a))
	end
	if wr and wr:IsA("Model") and wr.PrimaryPart then
		local root = base * CFrame.new(.05, 0, 0)
		wr:PivotTo(root * CFrame.Angles(0, 0, -a))
	end
end

-- moths flying from `from` towards `to` (stopping short), fading out after opts.Seconds
function View.MothSwarm(from: Vector3, to: Vector3, opts: any?): any
	local o = opts or {}
	local n = math.max(1, math.floor(View.Detail(o.Count or 7, math.ceil((o.Count or 7) * .7), math.ceil((o.Count or 7) * .4))))
	local seconds = o.Seconds or 2.6
	local folder = View.Folder()
	local moths = {}
	for i = 1, n do
		local m = View.Models.Moth()
		m.Parent = folder
		local offset = Vector3.new(math.sin(i * 2.1) * 1.6, math.cos(i * 1.3) * .8 + 1.5, math.cos(i * 2.7) * 1.6)
		table.insert(moths, { Model = m, Offset = offset, Phase = i * .7 })
	end
	local dir = to - from
	local dist = math.max(0, dir.Magnitude - (o.StopShort or 5))
	local unit = dir.Magnitude > .01 and dir.Unit or Vector3.new(0, 0, -1)
	local handle
	handle = View.Animate(seconds, function(a)
		local t = os.clock()
		for _, e in ipairs(moths) do
			local k = View.Ease(math.clamp(a * 1.15 - e.Phase * .03, 0, 1))
			local pos = from + unit * dist * k + e.Offset + Vector3.new(math.sin(t * 6 + e.Phase) * .5, math.sin(t * 9 + e.Phase) * .35, 0)
			e.Model:PivotTo(CFrame.lookAt(pos, pos + unit))
			flap(e.Model, t, 28 + e.Phase)
			if a > .75 then
				for _, p in ipairs(e.Model:GetDescendants()) do
					if p:IsA("BasePart") and p.Name ~= "Root" and p.Name ~= "WingRoot" then
						p.Transparency = math.max(p.Transparency, (a - .75) / .25)
					end
				end
			end
		end
	end, function()
		for _, e in ipairs(moths) do
			e.Model:Destroy()
		end
	end)
	return handle
end

-- moths fluttering around a point until Destroy()
function View.MothCloud(pos: Vector3, opts: any?): any
	local o = opts or {}
	local n = math.max(1, math.floor(View.Detail(o.Count or 8, 6, 3)))
	local folder = View.Folder()
	local moths = {}
	for i = 1, n do
		local m = View.Models.Moth()
		m.Parent = folder
		table.insert(moths, { Model = m, Phase = i / n * math.pi * 2, Radius = 1.2 + (i % 3) * .5, Speed = 1.4 + (i % 4) * .25 })
	end
	local reduced = Shared.ReducedMotion()
	local conn = RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for _, e in ipairs(moths) do
			local a = e.Phase + (reduced and 0 or t * e.Speed)
			local p = pos + Vector3.new(math.cos(a) * e.Radius, math.sin(a * 1.7) * .6, math.sin(a) * e.Radius)
			local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
			e.Model:PivotTo(CFrame.lookAt(p, p + tangent))
			if not reduced then
				flap(e.Model, t, 30 + e.Speed * 4)
			end
		end
	end)
	local handle = {}
	function handle.Destroy()
		conn:Disconnect()
		for _, e in ipairs(moths) do
			e.Model:Destroy()
		end
		table.clear(moths)
	end
	handle.Stop = handle.Destroy
	return handle
end

-- the noun after a count: Russian takes the counted form (1 осколок, 2 осколка, 5 осколков), English the plain name
local function counted(kind: string, n: number): string
	local ui = View.Loc().UI
	local kinds = ui.Kinds
	local forms = ui.Counted and ui.Counted[kind]
	if forms and Shared.IsRussian() then
		if type(forms) == "string" then
			return forms
		end
		local m10, m100 = n % 10, n % 100
		if m10 == 1 and m100 ~= 11 then
			return forms[1]
		elseif m10 >= 2 and m10 <= 4 and (m100 < 12 or m100 > 14) then
			return forms[2]
		end
		return forms[3]
	end
	return View.Pair(kinds[kind] or { tostring(kind), tostring(kind) })
end

-- a reward row -> one short line ("+52 Bell Shards", "Coffin Key", "Showcase find")
function View.RewardLine(r: any): string
	local kinds = View.Loc().UI.Kinds
	local name = View.Pair(kinds[r.Kind] or { tostring(r.Kind), tostring(r.Kind) })
	if r.Converted then
		local parts = {}
		for _, c in ipairs(r.Conversion or {}) do
			local amount = math.floor(tonumber(c.Amount) or 0)
			table.insert(parts, "+" .. tostring(amount) .. " " .. counted(tostring(c.Kind), amount))
		end
		return name .. " → " .. table.concat(parts, " · ")
	end
	local n = math.floor(tonumber(r.Amount) or 0)
	if (r.Kind == "Shards" or r.Kind == "Dust" or r.Kind == "Fragments" or r.Kind == "Bones" or r.Kind == "Cash" or r.Kind == "Candy") and n > 0 then
		return "+" .. Shared.Format(n) .. " " .. counted(r.Kind, n)
	end
	if r.Kind == "Key" and n > 1 then
		return "+" .. n .. " " .. counted("Key", n)
	end
	return name
end

local loc: any = nil
function View.Loc(): any
	if loc == nil then
		local ok, m = pcall(function()
			return require(RS:WaitForChild("Localization"):WaitForChild("Seals2"))
		end)
		loc = ok and type(m) == "table" and m or { UI = { Kinds = {}, Outcomes = {}, OutcomeLines = {} }, Reasons = {} }
	end
	return loc
end

-- the main ScreenGui's "hide everything" state: a menu, HIDE UI or a cinematic
function View.Hidden(): boolean
	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChild("PlayerGui")
	local main = gui and gui:FindFirstChild("ScreenGui")
	if not main then
		return false
	end
	return main:GetAttribute("OpenMenu") ~= nil or main:GetAttribute("UIHidden") == true or main:GetAttribute("CinemaActive") == true
end

return View
