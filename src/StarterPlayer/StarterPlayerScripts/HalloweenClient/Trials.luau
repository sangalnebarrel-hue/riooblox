-- BELL SEAL TRIALS · client host (StarterPlayerScripts.HalloweenClient.Trials, WP-I; docs/halloween2/DESIGN.md §24.1,
-- §8.4, §16.2, §24.3). Listens to the server's C2Trial / C2Seal / C2TrialMsg signals (Chapter2State Bus "C2Signal") and
-- owns everything generic about a trial on the client:
--   * the PRESENTERS: every ModuleScript child of this module is required once at boot; a presenter is
--       {Ids = {"EchoDig"}, Start(ctx, run), Update(ctx, run), Signal(ctx, kind, data, run), Stop(ctx, run, result),
--        HudLines(run) -> {string}?}                                                              (§24.1 contract)
--     run = the latest C2Trial payload {Kind, TrialId, Seal, RunId, StartedAt, EndsAt, Players, Score, Total, Goal,
--     Data (the server's run.Public), State, ...}; result = "Won" | "Failed" | "Left" (the payload has Reason / Gold).
--     Optional extras this host reads: Init(ctx) (called once at boot: always-on world layers), ScoreLabel = {en, ru},
--     Score(run) -> value, goal, labelEn?, labelRu? (e.g. the runner's own rings), HoldStart = true (movement is held
--     during the 3-2-1), Results(run, result) -> {{en, ru}} (extra stat lines on the results card).
--     ctx = the Halloween client ctx + ctx.Trials = {Request(action, args) (the C2Trial request), Run(), Banner(en, ru,
--     opts{Sub = {en, ru}, Color, Seconds, Style}), Toast(en, ru, kind?), Mark(pos, en, ru, opts?) -> handle
--     {Destroy, SetPosition, SetText}, Cinema, Mixer, plus L(en, ru), T(serverText), Now(), Folder() (the trials FX
--     folder), Reduced(), Quality(), Popup(pos, en, ru, color?, big?), Refresh() (redraw the HUD now)}.
--   * the TRIAL HUD (own ScreenGui DOGROTS_TrialHUD, HideWithUI, under the HUD strip, between HUDInnerLeft / Right):
--     seal numeral + trial name, the time bar (time left, red + ticks + the TRIAL music's Urgent layer in the last
--     seconds, "-15 s" popups when the server cuts the limit), Score / Goal, the Gold target with a live ON / LOST
--     state, the presenter's lines, the party (Event HP for combat trials, score), LEAVE (GuiButton.Activated, tap again
--     to confirm -> C2TrialLeave). Hidden while a menu is open, with HIDE UI and during a cinematic.
--   * the COUNTDOWN 3-2-1-GO (Data.GoAt, server time), the RESULTS card (Won / Gold / Failed / out, reason, time, score,
--     the Gold criteria, the rewards of C2Seal), the STAMP when a run ends.
--   * the SEAL-CLEAR CINEMATIC on C2Seal {Stage = "Cleared" | "Gold"}: Cinema orbit of the broken bell tower with its
--     toll, the seal's altar igniting (Models.Seals1.AltarFlare + SealIgnite), then the next gate whose veil dissolves
--     and the district lights coming on (Bus "UySealReveal": UnderyardFX releases the held seal state), title cards.
--     Journal replay: Bus C2Replay {Id = "Seal", Seal = i} plays it again (no requests, no flags).
--   * TRIAL PROMPTS: prompts with attribute UyTrialOnly = "<TrialId>" (Mirror Graves TURN / CONSULT) are shown only to
--     that trial's runners; BEGIN TRIAL (UyTrialId) and the seal altars (UySeal) are hidden while you are in a trial.
--     (Only prompt.Enabled is touched, never ProximityPromptService.)
-- Exception safety: everything is built in pcall; the HUD, overlays and controls hold are torn down on every end of a
-- run (signal, the UyTrial attribute clearing, character removal) and nothing here ever sinks input (only buttons
-- are Active).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Trials: any = { Started = false }
Trials.Presenters = {} -- trialId -> presenter
Trials.Loaded = {} -- {Name, P}

local player = Players.LocalPlayer
local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Bus = require(Halloween:WaitForChild("Bus"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local SC = require(Halloween:WaitForChild("SealConfig"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))
local Models: any = nil
pcall(function()
	Models = require(Halloween:WaitForChild("Models"):WaitForChild("Seals1"))
end)

local RGB = Color3.fromRGB
local WHITE = Color3.new(1, 1, 1)
local INK = RGB(16, 12, 26)
local DEEP = RGB(30, 18, 48)
local VIOLET = RGB(150, 80, 230)
local VIOLET_HI = RGB(196, 150, 255)
local MOON = RGB(150, 200, 255)
local SICKLY = RGB(120, 255, 140)
local CANDLE = RGB(255, 170, 80)
local BLOOD = RGB(220, 40, 60)
local BONE = RGB(230, 222, 200)
local GOLD = RGB(255, 210, 110)
local GREY = RGB(150, 140, 168)
-- the seals' own colours (BellSquare altars, I .. VII)
local SEAL_GLOW = { RGB(150, 205, 255), RGB(255, 170, 80), RGB(200, 220, 255), RGB(130, 255, 150), RGB(190, 120, 255), RGB(245, 240, 255),
	RGB(160, 70, 255) }
Trials.SealColors = SEAL_GLOW

local ctx: any = nil
local CS: any = nil
local Kit: any = nil
local main: any = nil
local api: any = {}
local current: any = nil -- the local player's run: {RunId, TrialId, Seal, P, Payload, GoAt, Limit, EndsAt, Downed, Started}
local ended: { [number]: string } = {} -- runId -> result already presented
local pendingEnd: any = nil -- {RunId, Seal, Result, Payload, At, Rewards, Gold, Shown}
local results: any = nil -- the results card
local seal1Loc: any = nil

---------------------------------------------------------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------------------------------------------------------
local function num(v: any, d: number?): number
	local n = tonumber(v)
	if n == nil or n ~= n then
		return d or 0
	end
	return n
end

local function L(en: string, ru: string?): string
	return Shared.L(en, ru)
end

local function pair(p: any): string
	if type(p) == "table" then
		return Shared.L(tostring(p[1] or ""), p[2])
	end
	return tostring(p or "")
end

local function now(): number
	return Shared.Now()
end

local function reduced(): boolean
	return Shared.ReducedMotion() or (Kit ~= nil and Kit.Motion ~= nil and Kit.Motion.Reduced())
end

local function quality(): string
	return Shared.Quality()
end

-- Russian of an English server message (Localization.Seals1 first, then Chapter2State's dictionaries)
local function translate(text: any): string
	if type(text) ~= "string" then
		return L("Connection problem; try again", "Проблема со связью, попробуй ещё раз")
	end
	if not Shared.IsRussian() then
		return text
	end
	if seal1Loc == nil then
		local ok, m = pcall(function()
			local folder = RS:FindFirstChild("Localization")
			local inst = folder and folder:FindFirstChild("Seals1")
			return inst and require(inst)
		end)
		seal1Loc = ok and type(m) == "table" and m or false
	end
	local out = seal1Loc and seal1Loc.Translate and seal1Loc.Translate(text, "ru")
	if out then
		return out
	end
	if CS and CS.T then
		return CS.T(text)
	end
	return Shared.T(text)
end
Trials.T = translate

local function audio(cue: string, where: any?, opts: any?)
	local a = ctx and ctx.Audio
	if a and type(a.Play) == "function" then
		pcall(a.Play, cue, where, opts)
	end
end

local function hasCue(cue: string): boolean
	local a = ctx and ctx.Audio
	local ok, has = pcall(function()
		return a and a.Has and a.Has(cue)
	end)
	return ok and has == true
end

local function fx(name: string, ...: any)
	local f = ctx and ctx.FX
	local fn = f and f[name]
	if type(fn) == "function" then
		pcall(fn, ...)
	end
end

local function cinema(): any
	local c = ctx and ctx.Modules and ctx.Modules.Cinema
	if c then
		return c
	end
	local ok, m = pcall(function()
		return require(script.Parent:WaitForChild("Cinema", 5) :: ModuleScript)
	end)
	return ok and m or nil
end

local function mixer(): any
	local ok, m = pcall(function()
		return require(RS:WaitForChild("AudioMixer", 5) :: ModuleScript)
	end)
	return ok and m or nil
end

local function music(): any
	local ok, m = pcall(function()
		return require(Halloween:WaitForChild("Music", 5) :: ModuleScript)
	end)
	return ok and type(m) == "table" and m or nil
end

local function rootPart(): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return (r and r:IsA("BasePart")) and r or nil
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function myTrial(): string
	local t = player:GetAttribute("UyTrial")
	return type(t) == "string" and t or ""
end

local function sealOf(payload: any): number?
	local s = payload and tonumber(payload.Seal)
	if s and Cfg.Seals[s] then
		return s
	end
	return nil
end

local function trialTitle(payload: any): (string, string)
	local s = sealOf(payload)
	if s then
		local t = Cfg.Seals[s].Title
		return t[1], t[2]
	end
	local id = payload and tostring(payload.TrialId or "") or ""
	local defs = Cfg.Trials and Cfg.Trials.Defs or {}
	local d = defs[id]
	if d and type(d.Name) == "table" then
		return d.Name[1], d.Name[2]
	end
	local names = {
		Toll = { "TRIAL OF THE TOLL", "ИСПЫТАНИЕ ЗВОНА" }, Mourner = { "THE MOURNER", "ПЛАКАЛЬЩИК" },
		DoorChallenge = { "DOOR CHALLENGE", "ИСПЫТАНИЕ ДВЕРИ" }, Doorkeeper = { "THE DOORKEEPER", "ПРИВРАТНИК" },
		Assault = { "BLACK BELL ASSAULT", "ШТУРМ ЧЁРНОГО КОЛОКОЛА" },
	}
	local n = names[id]
	if n then
		return n[1], n[2]
	end
	return string.upper(id), string.upper(id)
end

local function isMember(payload: any): boolean
	for _, uid in ipairs(payload and payload.Players or {}) do
		if tonumber(uid) == player.UserId then
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------------------------------------------------
-- presenters
---------------------------------------------------------------------------------------------------------------------
local function call(p: any, name: string, ...: any): ...any
	local fn = p and p[name]
	if type(fn) ~= "function" then
		return nil
	end
	local out = table.pack(pcall(fn, ...))
	if not out[1] then
		warn("Trials: presenter " .. tostring(p.__Name or "?") .. "." .. name .. " failed: " .. tostring(out[2]))
		return nil
	end
	return table.unpack(out, 2, out.n)
end
Trials.Call = call

local function loadPresenters()
	local list = {}
	for _, child in ipairs(script:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	for _, child in ipairs(list) do
		local ok, p = pcall(require, child)
		if not ok then
			warn("Trials: presenter " .. child.Name .. " failed to load: " .. tostring(p))
		elseif type(p) ~= "table" or type(p.Ids) ~= "table" then
			warn("Trials: presenter " .. child.Name .. " has no Ids")
		else
			p.__Name = child.Name
			table.insert(Trials.Loaded, { Name = child.Name, P = p })
			for _, id in ipairs(p.Ids) do
				if type(id) == "string" then
					if Trials.Presenters[id] then
						warn("Trials: trial " .. id .. " has two presenters (" .. tostring(Trials.Presenters[id].__Name) .. ", " .. child.Name .. ")")
					end
					Trials.Presenters[id] = p
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the trials FX folder + world marks
---------------------------------------------------------------------------------------------------------------------
local fxFolder: Folder? = nil
local function folder(): Folder
	if fxFolder and fxFolder.Parent then
		return fxFolder
	end
	local f = workspace:FindFirstChild("DOGROTS_TrialsFX")
	if not (f and f:IsA("Folder")) then
		f = Instance.new("Folder")
		f.Name = "DOGROTS_TrialsFX"
		f:SetAttribute("SelfManagedFX", true)
		f.Parent = workspace
	end
	fxFolder = f :: Folder
	return f :: Folder
end
Trials.Folder = folder

local marks: { [any]: any } = {}

local function metres(studs: number): string
	return string.format(Shared.IsRussian() and "%d м" or "%d m", math.max(0, math.floor(studs + .5)))
end

function api.Mark(pos: Vector3, en: string, ru: string?, opts: any?): any
	local o = opts or {}
	local color = typeof(o.Color) == "Color3" and o.Color or GOLD
	local holder = Instance.new("Part")
	holder.Name = "TrialMark"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.new(.2, .2, .2)
	holder.CFrame = CFrame.new(pos)
	holder.Parent = folder()
	local bb = Instance.new("BillboardGui")
	bb.Name = "MarkGui"
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(170, 74)
	bb.StudsOffsetWorldSpace = Vector3.new(0, num(o.Height, 5), 0)
	bb.MaxDistance = num(o.MaxDistance, 700)
	bb.Adornee = holder
	bb:SetAttribute("NoTranslate", true)
	bb.Parent = holder
	local diamond = Instance.new("Frame")
	diamond.Name = "Diamond"
	diamond.AnchorPoint = Vector2.new(.5, .5)
	diamond.Position = UDim2.new(.5, 0, 0, 14)
	diamond.Size = UDim2.fromOffset(18, 18)
	diamond.Rotation = 45
	diamond.BackgroundColor3 = color
	diamond.BorderSizePixel = 0
	diamond.Parent = bb
	local ds = Instance.new("UIStroke")
	ds.Color = INK
	ds.Thickness = 2
	ds.Parent = diamond
	local function label(name: string, y: number, h: number, size: number, c: Color3): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(0, y)
		t.Size = UDim2.new(1, 0, 0, h)
		t.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		t.TextSize = size
		t.TextColor3 = c
		t.TextStrokeColor3 = INK
		t.TextStrokeTransparency = .1
		t.TextXAlignment = Enum.TextXAlignment.Center
		t.TextYAlignment = Enum.TextYAlignment.Center
		t.Text = ""
		t:SetAttribute("NoTranslate", true)
		t.Parent = bb
		return t
	end
	local title = label("Label", 26, 24, 20, color)
	local dist = label("Distance", 50, 20, 15, BONE)
	local handle: any = { Alive = true, Part = holder, Gui = bb, En = en, Ru = ru }
	function handle.SetPosition(p: Vector3)
		if handle.Alive and holder.Parent then
			holder.CFrame = CFrame.new(p)
		end
	end
	function handle.SetText(e: string, r: string?)
		handle.En, handle.Ru = e, r
		title.Text = L(e, r)
	end
	function handle.SetColor(c: Color3)
		diamond.BackgroundColor3 = c
		title.TextColor3 = c
	end
	function handle.Destroy()
		if not handle.Alive then
			return
		end
		handle.Alive = false
		marks[handle] = nil
		holder:Destroy()
	end
	handle.Remove = handle.Destroy
	handle.SetText(en, ru)
	marks[handle] = { Title = title, Dist = dist, Holder = holder }
	return handle
end

local function updateMarks()
	local r = rootPart()
	for h, m in pairs(marks) do
		if not (m.Holder and m.Holder.Parent) then
			marks[h] = nil
		else
			m.Title.Text = L(h.En or "", h.Ru)
			m.Dist.Text = r and metres((m.Holder.Position - r.Position).Magnitude) or ""
		end
	end
end

local function clearMarks()
	for h in pairs(marks) do
		pcall(h.Destroy)
	end
	table.clear(marks)
end

---------------------------------------------------------------------------------------------------------------------
-- ctx.Trials
---------------------------------------------------------------------------------------------------------------------
function api.Request(action: string, args: any?): (boolean, any)
	local a = {}
	for k, v in pairs(type(args) == "table" and args or {}) do
		a[k] = v
	end
	a.Action = action
	if not CS then
		return false, "Not ready"
	end
	return CS.Request("C2Trial", a)
end

function api.Run(): any
	return current and current.Payload or nil
end

function api.Banner(en: string, ru: string?, opts: any?)
	local o = opts or {}
	Bus.Fire("Banner", { Title = L(en, ru), Subtitle = o.Sub and pair(o.Sub) or "", Color = o.Color, Style = o.Style or "Event",
		Seconds = o.Seconds or 3, NoTranslate = true })
end

function api.Toast(en: string, ru: string?, kind: string?)
	Bus.Fire("Toast", { Text = L(en, ru), Kind = kind or "info", NoTranslate = true })
end

function api.Popup(pos: Vector3, en: string, ru: string?, color: Color3?, big: boolean?)
	fx("Popup", pos, L(en, ru), color, big)
end

api.L = L
api.T = translate
api.Now = now
api.Folder = folder
api.Reduced = reduced
api.Quality = quality
api.Layout = Layout
api.Config = Cfg
api.SealConfig = SC

---------------------------------------------------------------------------------------------------------------------
-- trial prompts: UyTrialOnly for that trial's runners, BEGIN TRIAL / altars hidden while in a trial
---------------------------------------------------------------------------------------------------------------------
local prompts: { [ProximityPrompt]: boolean } = {}

-- nil = not a prompt this host manages
function Trials.PromptWanted(prompt: Instance, trial: string): boolean?
	local only = prompt:GetAttribute("UyTrialOnly")
	if type(only) == "string" and only ~= "" then
		return string.sub(trial, 1, #only + 1) == only .. ":"
	end
	if prompt:GetAttribute("UyTrialId") ~= nil or prompt:GetAttribute("UySeal") ~= nil then
		return trial == ""
	end
	return nil
end

local function applyPrompt(prompt: ProximityPrompt)
	local want = Trials.PromptWanted(prompt, myTrial())
	if want == nil then
		prompts[prompt] = nil
		return
	end
	prompts[prompt] = true
	if prompt.Enabled ~= want then
		prompt.Enabled = want
	end
end

local function refreshPrompts()
	for prompt in pairs(prompts) do
		if prompt.Parent then
			applyPrompt(prompt)
		else
			prompts[prompt] = nil
		end
	end
end

local function watchPrompts()
	local hooked: Instance? = nil
	local function hook(root: Instance)
		if hooked == root then
			return
		end
		hooked = root
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				applyPrompt(d)
			end
		end
		root.DescendantAdded:Connect(function(d)
			if d:IsA("ProximityPrompt") then
				task.defer(applyPrompt, d)
			end
		end)
	end
	task.spawn(function()
		while true do
			local d = workspace:FindFirstChild("DOGROTS_District")
			local root = d and d:FindFirstChild("40_Underyard")
			if root then
				hook(root)
			end
			task.wait(hooked and 10 or 2)
		end
	end)
	-- safety net: a prompt that shows up anyway (streamed in through another path)
	ProximityPromptService.PromptShown:Connect(function(prompt)
		if Trials.PromptWanted(prompt, myTrial()) ~= nil then
			applyPrompt(prompt)
		end
	end)
	player:GetAttributeChangedSignal("UyTrial"):Connect(refreshPrompts)
end

---------------------------------------------------------------------------------------------------------------------
-- Gold criteria (Chapter2Config.Seals[i].Gold) -> text + live state
---------------------------------------------------------------------------------------------------------------------
local function goldOf(seal: number?): any
	local s = seal and Cfg.Seals[seal]
	return s and type(s.Gold) == "table" and s.Gold or nil
end

-- {{en, ru, key}} pieces of the Gold target
function Trials.GoldParts(seal: number?, scoreLabel: any?): { any }
	local g = goldOf(seal)
	local out = {}
	if not g then
		return out
	end
	local lab = type(scoreLabel) == "table" and scoreLabel or { "", "" }
	if g.Total then
		local en = (string.gsub(string.format("%d %s", g.Total, lab[1] or ""), "%s+$", ""))
		local ru = (string.gsub(string.format("%d %s", g.Total, lab[2] or ""), "%s+$", ""))
		table.insert(out, { en, ru, "Total" })
	end
	if g.PerfectShare then
		local p = math.floor(g.PerfectShare * 100 + .5)
		table.insert(out, { p .. "% PERFECT", p .. "% ИДЕАЛЬНЫХ", "PerfectShare" })
	end
	if g.Time then
		local c = Shared.Clock(g.Time)
		table.insert(out, { "UNDER " .. c, "БЫСТРЕЕ " .. c, "Time" })
	end
	if g.NoMistakes then
		table.insert(out, { "NO MISTAKES", "БЕЗ ОШИБОК", "NoMistakes" })
	end
	if g.NoDowns then
		table.insert(out, { "NEVER DOWNED", "НИ РАЗУ НЕ ПАСТЬ", "NoDowns" })
	end
	if g.NoBleedOut then
		table.insert(out, { "NO ONE BLEEDS OUT", "НИКТО НЕ ИСТЁК", "NoBleedOut" })
	end
	return out
end

-- "On" (still reachable), "Lost" (a criterion already failed) for the local run
function Trials.GoldState(seal: number?, payload: any, ctxRun: any?): string
	local g = goldOf(seal)
	if not g then
		return "None"
	end
	local data = payload and type(payload.Data) == "table" and payload.Data or {}
	if g.Time then
		local goAt = num(data.GoAt, num(payload and payload.StartedAt, 0))
		local mine = data.Finish and data.Finish[tostring(player.UserId)]
		local t = mine and num(mine) or (now() - goAt)
		if goAt > 0 and t > g.Time + 1e-6 then
			return "Lost"
		end
	end
	if g.NoMistakes and (num(data.Wrong) > 0 or num(data.Mistakes) > 0) then
		return "Lost"
	end
	if g.NoDowns and ctxRun and ctxRun.Downed then
		return "Lost"
	end
	if g.NoBleedOut and ctxRun and ctxRun.BledOut then
		return "Lost"
	end
	if g.PerfectShare then
		local hits = num(data.Hits)
		if hits >= 6 and num(data.Perfects) / hits < g.PerfectShare then
			return "Behind"
		end
	end
	return "On"
end

---------------------------------------------------------------------------------------------------------------------
-- HUD
---------------------------------------------------------------------------------------------------------------------
local hud: any = nil

-- the HUD card rectangle (main ScreenGui pixels): x, y, width (pure maths, tested)
function Trials.HudRect(W: number, H: number, a: any): (number, number, number, boolean)
	local phone = math.min(W, H) < 560
	local l = num(a.HUDInnerLeft, 12)
	local r = num(a.HUDInnerRight, W - 12)
	if r - l < 300 then
		l, r = 12, W - 12
	end
	local w = math.floor(math.clamp(r - l - 16, 280, phone and 360 or 440))
	w = math.min(w, W - 24)
	local top = num(a.HwStripBottom, phone and 52 or 64) + (phone and 6 or 10)
	local cx = math.clamp((l + r) / 2, w / 2 + 12, W - w / 2 - 12)
	return math.floor(cx - w / 2), math.floor(top), w, phone
end

local function new(class: string, props: any?, parent: Instance?): any
	local o: any = Instance.new(class)
	for k, v in pairs(props or {}) do
		o[k] = v
	end
	if parent then
		o.Parent = parent
	end
	return o
end

local function corner(o: Instance, r: any)
	local c = Instance.new("UICorner")
	c.CornerRadius = r == "pill" and UDim.new(.5, 0) or UDim.new(0, tonumber(r) or 10)
	c.Parent = o
end

local function stroke(o: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
	return s
end

local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local function text(parent: Instance, name: string, props: any): TextLabel
	local t = new("TextLabel", { Name = name, BackgroundTransparency = 1, FontFace = FONT, TextColor3 = props.Color or WHITE,
		TextSize = props.Size or 16, TextXAlignment = props.AlignX or Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		Text = props.Text or "", TextScaled = props.Scaled == true, TextWrapped = props.Wrap == true, ZIndex = props.ZIndex or 2,
		Position = props.Position or UDim2.new(), Size = props.Size2 or UDim2.fromScale(1, 1), AnchorPoint = props.AnchorPoint or Vector2.zero,
		RichText = props.Rich == true }, parent)
	t:SetAttribute("NoTranslate", true)
	if props.Scaled then
		new("UITextSizeConstraint", { MaxTextSize = props.Size or 16, MinTextSize = props.Min or 9 }, t)
	end
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = props.Stroke or 1.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Name = "HwStroke"
	s.Parent = t
	return t
end

local function mainAttr(name: string): any
	return main and main:GetAttribute(name)
end

local function hidden(): boolean
	return mainAttr("OpenMenu") ~= nil or mainAttr("UIHidden") == true or mainAttr("CinemaActive") == true
end

local function screenSize(): Vector2
	local s = main and main.AbsoluteSize or Vector2.new(1280, 720)
	if s.X < 10 then
		local cam = workspace.CurrentCamera
		s = cam and cam.ViewportSize or Vector2.new(1280, 720)
	end
	return s
end

local function teardownHud()
	local h = hud
	hud = nil
	if not h then
		return
	end
	for _, c in ipairs(h.Conns) do
		c:Disconnect()
	end
	if h.Leave and h.Leave.Destroy then
		pcall(function()
			h.Leave:Destroy()
		end)
	end
	if h.Gui then
		h.Gui:Destroy()
	end
end

local function leaveNow()
	if not current then
		return
	end
	task.spawn(function()
		if CS then
			CS.Request("C2TrialLeave", {})
		end
	end)
end

local function buildHud(): any
	local h: any = { Conns = {}, Party = {}, Lines = {}, LeaveArmed = 0, TickSecond = -1, Shown = {} }
	local gui = new("ScreenGui", { Name = "DOGROTS_TrialHUD", DisplayOrder = 49, ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = main and main.IgnoreGuiInset or false })
	pcall(function()
		gui.ScreenInsets = main.ScreenInsets
	end)
	gui:SetAttribute("HideWithUI", true)
	gui:SetAttribute("NoTranslate", true)
	h.Gui = gui
	local card = new("Frame", { Name = "TrialCard", BackgroundColor3 = WHITE, BackgroundTransparency = .06, BorderSizePixel = 0, ZIndex = 2 }, gui)
	corner(card, 16)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(56, 30, 86), RGB(20, 10, 34)) }, card)
	h.CardStroke = stroke(card, VIOLET, 2, .05)
	h.Card = card
	h.Pop = new("UIScale", { Name = "Pop" }, card)
	-- header: the seal badge, the trial name, LEAVE
	local badge = new("Frame", { Name = "Badge", BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 3 }, card)
	corner(badge, "pill")
	h.BadgeStroke = stroke(badge, GOLD, 2, 0)
	h.Badge = badge
	h.Numeral = text(badge, "Numeral", { Size = 20, Scaled = true, Min = 10, AlignX = Enum.TextXAlignment.Center, Color = GOLD, ZIndex = 4 })
	h.Title = text(card, "Title", { Size = 20, Scaled = true, Min = 11, Color = WHITE, ZIndex = 3 })
	local leave = new("TextButton", { Name = "Leave", Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(120, 34, 52), BorderSizePixel = 0,
		Active = true, Selectable = true, ZIndex = 4 }, card)
	corner(leave, 12)
	h.LeaveStroke = stroke(leave, INK, 2, .1)
	h.LeaveText = text(leave, "Label", { Size = 15, Scaled = true, Min = 9, AlignX = Enum.TextXAlignment.Center, ZIndex = 5, Color = WHITE })
	h.Leave = leave
	table.insert(h.Conns, leave.Activated:Connect(function()
		local t = os.clock()
		if t - h.LeaveArmed <= 3 then
			h.LeaveArmed = 0
			leaveNow()
		else
			h.LeaveArmed = t
			if Kit and Kit.Sound and Kit.Sound.Play then
				pcall(Kit.Sound.Play, "Click")
			end
		end
		Trials.Refresh()
	end))
	-- the time bar
	local track = new("Frame", { Name = "TimeTrack", BackgroundColor3 = RGB(26, 12, 30), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 3 }, card)
	corner(track, 8)
	stroke(track, WHITE, 1.5, .7)
	h.Track = track
	h.Fill = new("Frame", { Name = "Fill", BackgroundColor3 = WHITE, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 4 }, track)
	corner(h.Fill, 8)
	h.FillGrad = new("UIGradient", { Rotation = 90 }, h.Fill)
	h.Shine = new("Frame", { Name = "Shine", BackgroundColor3 = WHITE, BackgroundTransparency = .8, BorderSizePixel = 0, Size = UDim2.new(1, 0, .4, 0),
		Position = UDim2.fromScale(0, .08), ZIndex = 5 }, h.Fill)
	corner(h.Shine, "pill")
	h.Time = text(card, "Time", { Size = 26, Scaled = true, Min = 12, AlignX = Enum.TextXAlignment.Right, ZIndex = 4, Stroke = 2 })
	-- score + gold
	h.Score = text(card, "Score", { Size = 28, Scaled = true, Min = 12, ZIndex = 3, Stroke = 2, Color = WHITE })
	h.ScoreLabel = text(card, "ScoreLabel", { Size = 15, Scaled = true, Min = 8, ZIndex = 3, Color = VIOLET_HI })
	local gold = new("Frame", { Name = "Gold", BackgroundColor3 = RGB(70, 48, 14), BackgroundTransparency = .15, BorderSizePixel = 0, ZIndex = 3 }, card)
	corner(gold, "pill")
	h.GoldStroke = stroke(gold, GOLD, 1.5, .1)
	h.Gold = gold
	h.GoldText = text(gold, "Text", { Size = 14, Scaled = true, Min = 7, AlignX = Enum.TextXAlignment.Center, Color = GOLD, ZIndex = 4 })
	-- presenter lines
	for i = 1, 3 do
		h.Lines[i] = text(card, "Line" .. i, { Size = 15, Scaled = true, Min = 10, ZIndex = 3, Color = BONE })
	end
	-- the party
	local party = new("Frame", { Name = "Party", BackgroundColor3 = INK, BackgroundTransparency = .25, BorderSizePixel = 0, ZIndex = 2, Visible = false }, gui)
	corner(party, 12)
	stroke(party, VIOLET, 1.5, .3)
	h.PartyBox = party
	for i = 1, 6 do
		local row = new("Frame", { Name = "Member" .. i, BackgroundTransparency = 1, ZIndex = 3 }, party)
		local dot = new("Frame", { Name = "Dot", BorderSizePixel = 0, ZIndex = 4, AnchorPoint = Vector2.new(0, .5) }, row)
		corner(dot, "pill")
		local name = text(row, "Name", { Size = 14, Scaled = true, Min = 7, ZIndex = 4 })
		local score = text(row, "Score", { Size = 14, Scaled = true, Min = 7, ZIndex = 4, AlignX = Enum.TextXAlignment.Right, Color = VIOLET_HI })
		local hpBack = new("Frame", { Name = "HP", BackgroundColor3 = RGB(40, 14, 30), BorderSizePixel = 0, ZIndex = 4 }, row)
		corner(hpBack, "pill")
		local hpFill = new("Frame", { Name = "Fill", BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 5, BackgroundColor3 = SICKLY }, hpBack)
		corner(hpFill, "pill")
		h.Party[i] = { Row = row, Dot = dot, Name = name, Score = score, HP = hpBack, Fill = hpFill }
	end
	gui.Parent = player:FindFirstChildOfClass("PlayerGui")
	return h
end

local function layoutHud(h: any, texts: { string }, partyN: number)
	local lines = #texts
	local size = screenSize()
	local x, y, w, phone = Trials.HudRect(size.X, size.Y, {
		HUDInnerLeft = mainAttr("HUDInnerLeft"), HUDInnerRight = mainAttr("HUDInnerRight"), HwStripBottom = mainAttr("HwStripBottom"),
	})
	-- phone landscape: a compact card in the right part of the free zone, clear of the character in the screen's centre
	local land = phone and size.X > size.Y
	if land then
		w = math.min(w, 300)
		x = math.floor(math.max(12, num(mainAttr("HUDInnerRight"), size.X - 12) - w - 8))
		lines = math.min(lines, 1)
	end
	local pad = phone and 8 or 10
	local headH = 44
	local barH = phone and 22 or 24
	local scoreH = phone and 28 or 32
	local lineH = phone and 18 or 20
	local hasTime = current and current.Limit and current.Limit > 0
	local inner0 = w - pad * 2
	-- the Gold target gets its own row when the card is narrow (phones), long lines wrap onto two rows
	local goldRow = not land and inner0 < 400 and h.Gold.Visible
	local goldH = goldRow and (phone and 22 or 24) or 0
	local rows = {}
	local textSize = phone and 13 or 15
	local linesH = 0
	for i = 1, lines do
		local n = utf8.len(texts[i]) or #texts[i]
		rows[i] = (n * textSize * .55 > inner0 - 4) and 2 or 1
		linesH += rows[i] * lineH
	end
	local cardH = pad + headH + 4 + (hasTime and (barH + 6) or 0) + scoreH + goldH + linesH + pad
	h.Card.Position = UDim2.fromOffset(x, y)
	h.Card.Size = UDim2.fromOffset(w, cardH)
	local inner = w - pad * 2
	-- header: badge | title | LEAVE (44 px tall touch target)
	local leaveW = phone and 92 or 108
	h.Badge.Position = UDim2.fromOffset(pad, pad + 4)
	h.Badge.Size = UDim2.fromOffset(headH - 8, headH - 8)
	h.Numeral.Size = UDim2.new(1, -6, 1, -6)
	h.Numeral.Position = UDim2.fromOffset(3, 3)
	h.Title.Position = UDim2.fromOffset(pad + headH, pad)
	h.Title.Size = UDim2.fromOffset(inner - headH - leaveW - 6, headH)
	h.Leave.Position = UDim2.fromOffset(w - pad - leaveW, pad)
	h.Leave.Size = UDim2.fromOffset(leaveW, headH)
	h.LeaveText.Position = UDim2.fromOffset(6, 4)
	h.LeaveText.Size = UDim2.new(1, -12, 1, -8)
	local yy = pad + headH + 4
	h.Track.Visible = hasTime == true
	h.Time.Visible = hasTime == true
	if hasTime then
		local timeW = phone and 58 or 70
		h.Track.Position = UDim2.fromOffset(pad, yy + 2)
		h.Track.Size = UDim2.fromOffset(inner - timeW - 8, barH - 4)
		h.Time.Position = UDim2.fromOffset(w - pad - timeW, yy - 2)
		h.Time.Size = UDim2.fromOffset(timeW, barH + 4)
		yy += barH + 6
	end
	local scoreW = math.floor(inner * (goldRow and .32 or .26))
	local goldW = goldRow and inner or math.floor(inner * .52)
	h.Score.Position = UDim2.fromOffset(pad, yy)
	h.Score.Size = UDim2.fromOffset(scoreW, scoreH)
	h.ScoreLabel.Position = UDim2.fromOffset(pad + scoreW + 4, yy + 4)
	h.ScoreLabel.Size = UDim2.fromOffset(goldRow and (inner - scoreW - 4) or (inner - goldW - scoreW - 10), scoreH - 8)
	if goldRow then
		h.Gold.Position = UDim2.fromOffset(pad, yy + scoreH + 1)
		h.Gold.Size = UDim2.fromOffset(goldW, goldH - 3)
	else
		h.Gold.Position = UDim2.fromOffset(w - pad - goldW, yy + 3)
		h.Gold.Size = UDim2.fromOffset(goldW, scoreH - 6)
	end
	h.GoldText.Position = UDim2.fromOffset(8, 2)
	h.GoldText.Size = UDim2.new(1, -16, 1, -4)
	yy += scoreH + goldH
	for i, l in ipairs(h.Lines) do
		l.Visible = i <= lines
		if i <= lines then
			l.Position = UDim2.fromOffset(pad + 2, yy)
			l.Size = UDim2.fromOffset(inner - 4, rows[i] * lineH)
			l.TextWrapped = rows[i] > 1
			yy += rows[i] * lineH
		end
	end
	-- party under the card, as wide as the card (rows of 22 px); only the rows that fit above the screen's bottom
	h.PartyBox.Visible = partyN > 1
	local rowH = phone and 20 or 22
	local top = y + cardH + 6
	local shown = math.min(partyN, math.max(1, math.floor((size.Y - top - 16) / rowH)))
	h.PartyShown = shown
	if partyN > 1 then
		local pw = math.min(w, phone and 260 or 300)
		h.PartyBox.Position = UDim2.fromOffset(x, top)
		h.PartyBox.Size = UDim2.fromOffset(pw, 8 + shown * rowH)
		for i, r in ipairs(h.Party) do
			r.Row.Visible = i <= shown
			r.Row.Position = UDim2.fromOffset(8, 4 + (i - 1) * rowH)
			r.Row.Size = UDim2.fromOffset(pw - 16, rowH)
			r.Dot.Position = UDim2.new(0, 0, .5, 0)
			r.Dot.Size = UDim2.fromOffset(8, 8)
			r.Name.Position = UDim2.fromOffset(14, 1)
			r.Name.Size = UDim2.new(.5, -14, 1, -2)
			r.HP.Position = UDim2.new(.5, 4, .5, -3)
			r.HP.Size = UDim2.new(.3, -8, 0, 6)
			r.Score.Position = UDim2.new(.8, 0, 0, 1)
			r.Score.Size = UDim2.new(.2, 0, 1, -2)
		end
	end
	h.Bottom = y + cardH + (partyN > 1 and (6 + 8 + shown * rowH) or 0)
	if main then
		main:SetAttribute("HwTrialBottom", h.Bottom)
	end
end

local function hpColor(frac: number): Color3
	if frac > .6 then
		return SICKLY
	elseif frac > .3 then
		return CANDLE
	end
	return BLOOD
end

local function setUrgent(g: number)
	local m = music()
	if m and type(m.SetLayer) == "function" then
		pcall(m.SetLayer, "TRIAL", "Urgent", g)
	end
end

function Trials.Refresh()
	local h = hud
	local run = current
	if not h or not run then
		return
	end
	local payload = run.Payload or {}
	h.Gui.Enabled = not hidden()
	local t = now()
	local data = type(payload.Data) == "table" and payload.Data or {}
	-- header
	local en, ru = trialTitle(payload)
	h.Title.Text = L(en, ru)
	local seal = run.Seal
	h.Numeral.Text = seal and Cfg.Seals[seal].Numeral or "!"
	local accent = seal and SEAL_GLOW[seal] or VIOLET_HI
	h.BadgeStroke.Color = accent
	h.Numeral.TextColor3 = accent
	local armed = os.clock() - h.LeaveArmed <= 3
	h.LeaveText.Text = armed and L("SURE?", "ТОЧНО?") or L("LEAVE", "ВЫЙТИ")
	h.Leave.BackgroundColor3 = armed and BLOOD or RGB(96, 30, 52)
	-- time
	local endsAt = num(payload.EndsAt)
	if run.Limit and run.Limit > 0 and endsAt > 0 then
		local goAt = run.GoAt or 0
		local left = math.max(0, endsAt - math.max(t, goAt))
		local frac = math.clamp(left / run.Limit, 0, 1)
		h.Fill.Size = UDim2.fromScale(frac, 1)
		local col = frac > .4 and VIOLET_HI:Lerp(MOON, .4) or (left > 10 and CANDLE or BLOOD)
		h.FillGrad.Color = ColorSequence.new(col:Lerp(WHITE, .35), col)
		if t < goAt then
			h.Time.Text = Shared.Clock(run.Limit)
			h.Time.TextColor3 = WHITE
		elseif left <= 10 then
			h.Time.Text = string.format("%.1f", left)
			local pulse = reduced() and 0 or (.5 + .5 * math.sin(os.clock() * 10))
			h.Time.TextColor3 = BLOOD:Lerp(WHITE, pulse * .5)
		else
			h.Time.Text = Shared.Clock(math.ceil(left))
			h.Time.TextColor3 = WHITE
		end
		-- last seconds: a tick per second, the Urgent layer of the TRIAL theme
		if t >= goAt and left > 0 and left <= 5 then
			local sec = math.ceil(left)
			if sec ~= h.TickSecond then
				h.TickSecond = sec
				audio("TrialTick", nil, { Volume = .7, Pitch = 1 + (5 - sec) * .05 })
			end
		end
		-- (the TRIAL theme's Urgent layer is Soundscape's: it owns the music)
		-- the server cut the limit (a wrong consult): "-15 s"
		if run.LastEndsAt and endsAt < run.LastEndsAt - .5 then
			local cut = math.floor(run.LastEndsAt - endsAt + .5)
			local rp = rootPart()
			api.Popup((rp and rp.Position or Vector3.zero) + Vector3.new(0, 6, 0), "-" .. cut .. " s", "-" .. cut .. " с", BLOOD, true)
			h.Pop.Scale = 1.06
			if TweenService then
				TweenService:Create(h.Pop, TweenInfo.new(.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
			audio("TrialFail", nil, { Volume = .35, Pitch = 1.4 })
		end
		run.LastEndsAt = endsAt
	end
	-- score
	local p = run.P
	local value, goal, le, lr = nil, nil, nil, nil
	if p and type(p.Score) == "function" then
		value, goal, le, lr = call(p, "Score", payload)
	end
	if value == nil then
		value, goal = num(payload.Total), num(payload.Goal, 1)
	end
	local label = (p and type(p.ScoreLabel) == "table") and p.ScoreLabel or { "SCORE", "СЧЁТ" }
	h.Score.Text = string.format("%d / %d", math.floor(num(value)), math.floor(num(goal, 1)))
	h.ScoreLabel.Text = L(le or label[1], lr or label[2])
	-- gold
	local parts = Trials.GoldParts(seal, label)
	h.Gold.Visible = #parts > 0
	if #parts > 0 then
		local words = {}
		for _, g in ipairs(parts) do
			table.insert(words, L(g[1], g[2]))
		end
		local state = Trials.GoldState(seal, payload, run)
		local head = L("GOLD", "ЗОЛОТО")
		if state == "Lost" then
			h.GoldText.Text = head .. ": " .. L("LOST", "УПУЩЕНО")
			h.GoldText.TextColor3 = GREY
			h.GoldStroke.Color = GREY
			h.Gold.BackgroundColor3 = RGB(40, 34, 46)
		else
			h.GoldText.Text = head .. ": " .. table.concat(words, " · ")
			h.GoldText.TextColor3 = state == "Behind" and CANDLE or GOLD
			h.GoldStroke.Color = state == "Behind" and CANDLE or GOLD
			h.Gold.BackgroundColor3 = RGB(70, 48, 14)
		end
	end
	-- presenter lines
	local lines = p and call(p, "HudLines", payload) or nil
	local texts = {}
	for i = 1, 3 do
		local s = type(lines) == "table" and lines[i] or nil
		if type(s) == "string" and s ~= "" then
			table.insert(texts, s)
			h.Lines[#texts].Text = s
		end
	end
	-- the party
	local members = payload.Players or {}
	local partyN = math.min(6, #members)
	for i, row in ipairs(h.Party) do
		local uid = members[i]
		if uid and i <= partyN then
			local pl = Players:GetPlayerByUserId(tonumber(uid) or 0)
			row.Name.Text = pl and pl.DisplayName or ("#" .. tostring(uid))
			row.Name.TextColor3 = tonumber(uid) == player.UserId and GOLD or WHITE
			local sc = payload.Score and payload.Score[tostring(uid)]
			row.Score.Text = tostring(math.floor(num(sc)))
			local combat = pl ~= nil and pl:GetAttribute("HwCombat") == true
			row.HP.Visible = combat
			if combat then
				local hp, max = num(pl:GetAttribute("HwHP")), math.max(1, num(pl:GetAttribute("HwHPMax"), 100))
				local frac = pl:GetAttribute("HwDowned") == true and 0 or math.clamp(hp / max, 0, 1)
				row.Fill.Size = UDim2.fromScale(frac, 1)
				row.Fill.BackgroundColor3 = hpColor(frac)
			end
			row.Dot.BackgroundColor3 = (pl and pl:GetAttribute("HwDowned") == true) and BLOOD or (pl and SICKLY or GREY)
		end
	end
	layoutHud(h, texts, partyN)
	-- rows that do not fit (phone landscape, big parties): the last shown row says how many more are in the party
	local shown = h.PartyShown or partyN
	if partyN > shown and h.Party[shown] then
		h.Party[shown].Score.Text = "+" .. (partyN - shown + 1)
		h.Party[shown].Name.Text = L("more", "ещё")
		h.Party[shown].HP.Visible = false
	end
	updateMarks()
end

---------------------------------------------------------------------------------------------------------------------
-- countdown 3-2-1-GO
---------------------------------------------------------------------------------------------------------------------
local countdown: any = nil

local function stopCountdown()
	local c = countdown
	countdown = nil
	if not c then
		return
	end
	if c.Conn then
		c.Conn:Disconnect()
	end
	if c.Locked then
		local cin = cinema()
		if cin and cin.Unlock then
			pcall(cin.Unlock, "TrialCountdown")
		end
	end
	if c.Gui then
		c.Gui:Destroy()
	end
end

local function startCountdown(goAt: number, hold: boolean)
	stopCountdown()
	if goAt <= now() + .15 then
		return
	end
	local c: any = { GoAt = goAt, Last = nil }
	countdown = c
	local ok, err = pcall(function()
		local gui = new("ScreenGui", { Name = "DOGROTS_TrialCountdown", DisplayOrder = 60, ResetOnSpawn = false, IgnoreGuiInset = true })
		gui:SetAttribute("NoTranslate", true)
		c.Gui = gui
		local label = text(gui, "Count", { Size = 120, Scaled = true, Min = 40, AlignX = Enum.TextXAlignment.Center, Color = WHITE, Stroke = 5,
			AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .42), Size2 = UDim2.fromScale(.6, .22), ZIndex = 5 })
		c.Label = label
		c.Scale = new("UIScale", {}, label)
		c.Sub = text(gui, "Sub", { Size = 28, Scaled = true, Min = 12, AlignX = Enum.TextXAlignment.Center, Color = VIOLET_HI, Stroke = 3,
			AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .55), Size2 = UDim2.fromScale(.7, .06), ZIndex = 5 })
		gui.Parent = player:FindFirstChildOfClass("PlayerGui")
		if hold then
			local cin = cinema()
			if cin and cin.LockControls then
				c.Locked = true
				cin.LockControls("TrialCountdown")
			end
		end
		c.Conn = RunService.Heartbeat:Connect(function()
			local left = c.GoAt - now()
			local show: string
			if left > 0 then
				show = tostring(math.ceil(left))
				c.Sub.Text = L("GET READY", "ПРИГОТОВЬСЯ")
			else
				show = L("GO!", "ВПЕРЁД!")
				c.Sub.Text = ""
			end
			if show ~= c.Last then
				c.Last = show
				c.Label.Text = show
				c.Label.TextColor3 = left > 0 and WHITE or SICKLY
				if not reduced() then
					c.Scale.Scale = 1.45
					TweenService:Create(c.Scale, TweenInfo.new(.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
				end
				if left > 0 then
					audio("TrialTick", nil, { Volume = .8, Pitch = 1 })
				else
					audio("TrialStart", nil, { Volume = .9 })
					if c.Locked then
						c.Locked = false
						local cin = cinema()
						if cin and cin.Unlock then
							pcall(cin.Unlock, "TrialCountdown")
						end
					end
				end
			end
			c.Label.TextTransparency = left < -.5 and math.clamp((-left - .5) / .4, 0, 1) or 0
			if left < -.95 then
				stopCountdown()
			end
		end)
	end)
	if not ok then
		warn("Trials: countdown failed: " .. tostring(err))
		stopCountdown()
	end
	-- whatever happens, the hold never outlives GO by more than a moment
	task.delay(math.max(0, goAt - now()) + 1.5, function()
		if countdown == c then
			stopCountdown()
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- results card
---------------------------------------------------------------------------------------------------------------------
local REASONS = {
	Time = { "Time ran out", "Время вышло" },
	Wipe = { "Everyone was downed", "Все повержены" },
	BledOut = { "You bled out before a revive", "Ты не дождался помощи" },
	LeftZone = { "You left the Underyard", "Ты покинул Поддворье" },
	LeftDistrict = { "You left the trial's district", "Ты покинул район испытания" },
	Died = { "You fell", "Ты погиб" },
	Invalid = { "Too fast to be true: the run did not count", "Слишком быстро: забег не засчитан" },
	Abandoned = { "Trial abandoned", "Испытание брошено" },
	Left = { "You left the trial", "Ты вышел из испытания" },
	Ascend = { "You left the Underyard", "Ты покинул Поддворье" },
	Kicked = { "You were removed from the trial", "Тебя убрали из испытания" },
	Error = { "Something went wrong", "Что-то пошло не так" },
	Failed = { "The trial failed", "Испытание провалено" },
}
Trials.Reasons = REASONS

-- {English, Russian {one, few, many} after a number (or one form for every count), icon}
local REWARD_TEXT = {
	Shards = { "Bell Shards", { "осколок колокола", "осколка колокола", "осколков колокола" }, "🔔" },
	Dust = { "Lucky Dust", "счастливой пыли", "✨" },
	Key = { "Coffin Keys", { "ключ от гроба", "ключа от гроба", "ключей от гроба" }, "🗝" },
	Fragments = { "fragments", { "фрагмент", "фрагмента", "фрагментов" }, "🧵" },
	Candy = { "Candy", { "конфета", "конфеты", "конфет" }, "🍬" },
	Bones = { "Bones", { "кость", "кости", "костей" }, "🦴" },
	Cash = { "Coins", { "монета", "монеты", "монет" }, "🪙" },
}
local function ruCount(forms: any, n: number): string
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

-- one reward row -> display text (EN / RU through L)
function Trials.RewardText(row: any): string
	if type(row) ~= "table" then
		return ""
	end
	local kind = row.Kind
	local amount = math.floor(num(row.Amount))
	local t = REWARD_TEXT[kind]
	local out: string
	if t then
		if kind == "Key" then
			out = string.format("%s +%d %s", t[3], amount, L(amount == 1 and "Coffin Key" or "Coffin Keys", ruCount(t[2], amount)))
		else
			out = string.format("%s +%s %s", t[3], Shared.Format(amount), L(t[1], ruCount(t[2], amount)))
		end
	elseif kind == "Dog" then
		local def = Cfg.Dogs.Defs[row.Id or ""]
		out = "🐶 " .. (def and pair(def.Name) or tostring(row.Id)) .. (def and def.Code and (" · " .. def.Code) or "")
	elseif kind == "Decor" then
		local def = Cfg.Decor and Cfg.Decor.Defs and Cfg.Decor.Defs[row.Id or ""]
		out = "🏰 " .. (def and pair(def.Name) or tostring(row.Id or ""))
	elseif kind == "Skin" then
		local def = Cfg.Skins and Cfg.Skins.Defs and Cfg.Skins.Defs[row.Id or ""]
		out = "⛏ " .. (def and pair(def.Name) or tostring(row.Id or ""))
	elseif kind == "Find" then
		local def = Cfg.Finds and Cfg.Finds.Defs and Cfg.Finds.Defs[row.Id or ""]
		out = "💎 " .. (def and pair(def.Name) or tostring(row.Id or ""))
	elseif kind == "Title" then
		local t = Cfg.Titles and Cfg.Titles[row.Id or ""]
		out = "🏷 " .. L("Title: ", "Титул: ") .. (t and pair(t) or tostring(row.Id or ""))
	else
		out = tostring(kind or "") .. " " .. tostring(amount)
	end
	if row.Converted and type(row.Conversion) == "table" then
		local parts = {}
		for _, c in ipairs(row.Conversion) do
			table.insert(parts, Trials.RewardText(c))
		end
		if #parts > 0 then
			out = out .. "  →  " .. table.concat(parts, ", ")
		end
	end
	if type(row.Overflow) == "table" then
		out = out .. "  (" .. L("full: ", "лимит: ") .. Trials.RewardText(row.Overflow) .. ")"
	end
	return out
end

local function closeResults()
	local r = results
	results = nil
	if r and r.Gui then
		r.Gui:Destroy()
	end
end

-- r = {Result = "Won"|"Failed"|"Left", Gold, First, Seal, Payload, Reason, Rewards, Stats = {{en, ru, value}}}
function Trials.ShowResults(r: any)
	closeResults()
	local ok, err = pcall(function()
		local res: any = { Info = r }
		results = res
		local size = screenSize()
		local W, H = size.X, size.Y
		local phone = math.min(W, H) < 560
		local w = math.min(phone and 380 or 460, W - 32)
		local gui = new("ScreenGui", { Name = "DOGROTS_TrialResults", DisplayOrder = 61, ResetOnSpawn = false, IgnoreGuiInset = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
		gui:SetAttribute("NoTranslate", true)
		gui:SetAttribute("HideWithUI", true)
		res.Gui = gui
		local won = r.Result == "Won"
		local accent = won and (r.Gold and GOLD or (r.Seal and SEAL_GLOW[r.Seal] or SICKLY)) or BLOOD
		local card = new("Frame", { Name = "ResultCard", AnchorPoint = Vector2.new(.5, .5), Position = UDim2.fromScale(.5, .5), BackgroundColor3 = WHITE,
			BorderSizePixel = 0, ZIndex = 2 }, gui)
		corner(card, 18)
		new("UIGradient", { Rotation = 90, Color = ColorSequence.new(RGB(54, 30, 84), RGB(16, 10, 28)) }, card)
		stroke(card, accent, 3, 0)
		res.Card = card
		res.Scale = new("UIScale", {}, card)
		local pad = 14
		local y = pad
		local function row(name: string, h: number, props: any): TextLabel
			props.Position = UDim2.fromOffset(pad, y)
			props.Size2 = UDim2.fromOffset(w - pad * 2, h)
			local t = text(card, name, props)
			y += h
			return t
		end
		local en, ru = trialTitle(r.Payload or { Seal = r.Seal })
		local head: string
		if won then
			if r.First and r.Seal then
				head = L("BELL SEAL " .. Cfg.Seals[r.Seal].Numeral .. " BROKEN!", "ПЕЧАТЬ " .. Cfg.Seals[r.Seal].Numeral .. " СЛОМАНА!")
			elseif r.Gold then
				head = L("GOLD!", "ЗОЛОТО!")
			else
				head = L("TRIAL CLEARED", "ИСПЫТАНИЕ ПРОЙДЕНО")
			end
		elseif r.Result == "Left" then
			head = L("OUT OF THE TRIAL", "ТЫ ВНЕ ИСПЫТАНИЯ")
		else
			head = L("TRIAL FAILED", "ИСПЫТАНИЕ ПРОВАЛЕНО")
		end
		res.Head = row("Head", phone and 34 or 40, { Text = head, Size = phone and 30 or 36, Scaled = true, Min = 14, AlignX = Enum.TextXAlignment.Center,
			Color = accent, Stroke = 3, ZIndex = 3 })
		local reason = r.Reason and REASONS[r.Reason]
		local sub = L(en, ru) .. (reason and (" · " .. pair(reason)) or "")
		res.Sub = row("Sub", 22, { Text = sub, Size = 18, Scaled = true, Min = 9, AlignX = Enum.TextXAlignment.Center, Color = BONE, ZIndex = 3 })
		y += 6
		-- rank medal + the Gold criteria
		local parts = Trials.GoldParts(r.Seal, r.ScoreLabel)
		if won then
			local medal = r.Gold and L("RANK: GOLD", "РАНГ: ЗОЛОТО") or L("RANK: CLEAR", "РАНГ: ПРОЙДЕНО")
			res.Rank = row("Rank", 26, { Text = medal, Size = 20, Scaled = true, Min = 10, AlignX = Enum.TextXAlignment.Center,
				Color = r.Gold and GOLD or MOON, ZIndex = 3, Stroke = 2 })
		end
		if #parts > 0 then
			local words = {}
			for _, g in ipairs(parts) do
				table.insert(words, L(g[1], g[2]))
			end
			res.GoldLine = row("GoldLine", 20, { Text = L("Gold: ", "Золото: ") .. table.concat(words, " · ") .. ((won and r.Gold) and "  ✓" or ""),
				Size = 15, Scaled = true, Min = 8, AlignX = Enum.TextXAlignment.Center, Color = (won and r.Gold) and GOLD or GREY, ZIndex = 3 })
		end
		y += 6
		-- stats
		res.Stats = {}
		for _, s in ipairs(r.Stats or {}) do
			local t = row("Stat", 21, { Text = L(s[1], s[2]) .. ": " .. tostring(s[3]), Size = 16, Scaled = true, Min = 8, Color = WHITE, ZIndex = 3 })
			table.insert(res.Stats, t)
		end
		-- rewards (C2Seal rows; they may arrive a moment later: Trials.ResultRewards)
		y += 4
		res.RewardsTop = y
		res.Rewards = {}
		res.W = w
		res.Pad = pad
		res.Phone = phone
		res.Layout = function()
			local yy = res.RewardsTop
			-- a tall list on a short screen goes into two columns (short rows side by side, long ones across), so the
			-- CLOSE button always stays on the card
			local n = #res.Rewards
			local two = n > 3 and res.RewardsTop + n * 22 + 10 + 48 + pad > H - 24
			local full = w - pad * 2
			local colW = math.floor(full / 2)
			local col, rows = 0, 0
			for _, l in ipairs(res.Rewards) do
				local long = utf8.len(l.Text) or #l.Text
				local wide = not two or long * 8.6 > colW - 6
				if wide then
					if col == 1 then
						rows += 1
						col = 0
					end
					l.Position = UDim2.fromOffset(pad, yy + rows * 22)
					l.Size = UDim2.fromOffset(full, 22)
					rows += 1
				else
					l.Position = UDim2.fromOffset(pad + col * colW, yy + rows * 22)
					l.Size = UDim2.fromOffset(colW, 22)
					col += 1
					if col == 2 then
						col = 0
						rows += 1
					end
				end
			end
			if col == 1 then
				rows += 1
			end
			yy += rows * 22
			yy += 10
			res.Close.Instance.Position = UDim2.fromOffset(math.floor((w - 160) / 2), yy)
			yy += 48 + pad
			local maxH = H - 24
			card.Size = UDim2.fromOffset(w, math.min(yy, maxH))
			res.Height = yy
		end
		res.SetRewards = function(rows: { any })
			for _, l in ipairs(res.Rewards) do
				l:Destroy()
			end
			table.clear(res.Rewards)
			for i, rw in ipairs(rows or {}) do
				if i > 8 then
					break
				end
				local t = text(card, "Reward", { Text = Trials.RewardText(rw), Size = 17, Scaled = true, Min = 8, Color = GOLD, ZIndex = 3,
					Size2 = UDim2.fromOffset(w - pad * 2, 22), AlignX = Enum.TextXAlignment.Center })
				table.insert(res.Rewards, t)
			end
			res.Layout()
		end
		-- CLOSE (Activated); Kit.Button when the kit is there
		local closeFn = function()
			if results == res then
				closeResults()
			end
		end
		if Kit and Kit.Button then
			res.Close = Kit.Button(card, { Name = "Close", Text = L("CLOSE", "ЗАКРЫТЬ"), Style = won and "success" or "secondary", NoTranslate = true,
				Size = UDim2.fromOffset(160, 48), ZIndex = 4, OnClick = closeFn })
		else
			local b = new("TextButton", { Name = "Close", Text = L("CLOSE", "ЗАКРЫТЬ"), FontFace = FONT, TextSize = 20, TextColor3 = WHITE,
				BackgroundColor3 = won and RGB(60, 150, 90) or RGB(90, 80, 110), Size = UDim2.fromOffset(160, 48), ZIndex = 4, Active = true }, card)
			corner(b, 12)
			b.Activated:Connect(closeFn)
			res.Close = { Instance = b }
		end
		res.SetRewards(r.Rewards or {})
		gui.Parent = player:FindFirstChildOfClass("PlayerGui")
		if not reduced() then
			res.Scale.Scale = .85
			TweenService:Create(res.Scale, TweenInfo.new(.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		-- hidden while a menu / cinematic / HIDE UI is on; gone after a while
		task.spawn(function()
			local born = os.clock()
			while results == res do
				gui.Enabled = not hidden()
				if os.clock() - born > 14 then
					closeResults()
					break
				end
				task.wait(.25)
			end
		end)
	end)
	if not ok then
		warn("Trials: results card failed: " .. tostring(err))
		closeResults()
	end
end

function Trials.ResultsCard(): any
	return results
end

---------------------------------------------------------------------------------------------------------------------
-- the seal-clear cinematic (+ journal replay)
---------------------------------------------------------------------------------------------------------------------
local OPENS = {
	FuneralCarnival = { "THE FUNERAL CARNIVAL IS OPEN", "ПОХОРОННЫЙ КАРНАВАЛ ОТКРЫТ" },
	MourningMarsh = { "THE MOURNING MARSH IS OPEN", "ТРАУРНАЯ ТОПЬ ОТКРЫТА" },
	Undercrypt = { "THE UNDERCRYPT IS OPEN", "ПОДКЛЕПЬЕ ОТКРЫТО" },
	CrookedRow = { "CROOKED ROW IS OPEN", "КРИВОЙ РЯД ОТКРЫТ" },
	BlackBellArena = { "THE BLACK BELL ARENA IS OPEN", "АРЕНА ЧЁРНОГО КОЛОКОЛА ОТКРЫТА" },
}
local FOCUS = {
	BellSquare = Vector3.new(0, 8, 2400), FuneralCarnival = Vector3.new(150, 4, 2250), MourningMarsh = Vector3.new(-142, 2, 2548),
	Undercrypt = Vector3.new(110, 4, 2500), CrookedRow = Vector3.new(-148, 6, 2240), BlackBellArena = Vector3.new(0, 10, 2625),
}

-- the district a seal opens (UnderyardLayout.Unlock == i), else nil
function Trials.OpensDistrict(i: number): string?
	for name, need in pairs(Layout.Unlock) do
		if need == i and name ~= "BellSquare" then
			return name
		end
	end
	return nil
end

local function lookAt(from: Vector3, to: Vector3): CFrame
	local cin = cinema()
	if cin and cin.LookAt then
		return cin.LookAt(from, to)
	end
	return CFrame.lookAt(from, to)
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- the shot plan of seal i: {Duration, Shot = fn(t) -> CFrame, Altar, Socket, Gate?, District?, Beats = {...}}
function Trials.SealShots(i: number, goldOnly: boolean?): any
	local tower = Layout.Anchor("TowerBell") or Vector3.new(0, 70, 2400)
	local centre = Layout.Centre
	local altar = Layout.SealAltars[i] or centre + Vector3.new(0, 0, -34)
	local out = flat(altar - centre)
	out = out.Magnitude > 1e-3 and out.Unit or Vector3.new(0, 0, -1)
	local socket = altar + Vector3.new(0, 4.3, 0)
	local side = Vector3.new(-out.Z, 0, out.X)
	local opens = Trials.OpensDistrict(i)
	local gate = opens and Layout.Gates[opens] or nil
	local seal = Cfg.Seals[i]
	local district = opens or (seal and seal.District ~= "*" and seal.District) or "BellSquare"
	-- beat 1: an orbit round the tower bell, starting on the altar's side
	local a0 = math.atan2(out.Z, out.X) + .95
	local orbit = function(t: number): CFrame
		local a = a0 - .85 * smooth(t / 3.6)
		local r = 54
		local pos = tower + Vector3.new(math.cos(a) * r, -16 + 6 * smooth(t / 3.6), math.sin(a) * r)
		return lookAt(pos, tower + Vector3.new(0, 2, 0))
	end
	-- beat 2: in front of the altar, the tower behind it, a slow push in
	local altarFrom = lookAt(socket + out * 16 + side * 3 + Vector3.new(0, 6.5, 0), socket + Vector3.new(0, 1.5, 0))
	local altarTo = lookAt(socket + out * 9.5 + side * 1.5 + Vector3.new(0, 3.4, 0), socket + Vector3.new(0, 1.8, 0))
	local altarShot = function(t: number): CFrame
		return altarFrom:Lerp(altarTo, smooth(t / 3.4))
	end
	-- beat 3: through the gate the seal opens (its veil in front, the district behind), else over its own district
	local wideFrom: CFrame, wideTo: CFrame
	if gate then
		local P, F = gate.Position, gate.Facing
		wideFrom = lookAt(P - F * 34 + Vector3.new(0, 22, 0), P + F * 40 + Vector3.new(0, 2, 0))
		wideTo = lookAt(P - F * 19 + Vector3.new(0, 11, 0), P + F * 44 + Vector3.new(0, 4, 0))
	else
		local f = FOCUS[district] or FOCUS.BellSquare
		local dir = flat(f - centre)
		dir = dir.Magnitude > 1 and dir.Unit or Vector3.new(0, 0, 1)
		wideFrom = lookAt(f - dir * 70 + Vector3.new(0, 46, 0), f)
		wideTo = lookAt(f - dir * 52 + Vector3.new(0, 32, 0), f + Vector3.new(0, 2, 0))
	end
	local wideShot = function(t: number): CFrame
		return wideFrom:Lerp(wideTo, smooth(t / 4.4))
	end
	local B1, B2 = 3.6, 7.0
	local duration = goldOnly and 7.2 or 11.4
	local blend = .7
	local function shot(t: number): CFrame
		if t < B1 - blend * .5 then
			return orbit(t)
		elseif t < B1 + blend * .5 then
			local k = smooth((t - (B1 - blend * .5)) / blend)
			return orbit(t):Lerp(altarShot(t - B1 + blend * .5), k)
		elseif goldOnly or t < B2 - blend * .5 then
			return altarShot(t - B1 + blend * .5)
		elseif t < B2 + blend * .5 then
			local k = smooth((t - (B2 - blend * .5)) / blend)
			return altarShot(t - B1 + blend * .5):Lerp(wideShot(t - B2 + blend * .5), k)
		end
		return wideShot(t - B2 + blend * .5)
	end
	return { Duration = duration, Shot = shot, Altar = altar, Socket = socket, Out = out, Gate = gate, Opens = opens, District = district,
		Tower = tower, B1 = B1, B2 = B2, Ignite = B1 + .7, Reveal = B2 + .35 }
end

local sealPlaying = false

-- plays the seal-clear cinematic of seal i; done(ok) after it (also when Cinema refuses: the world state is released)
function Trials.PlaySeal(i: number, opts: any?)
	local o = opts or {}
	local done = type(o.Done) == "function" and o.Done or function() end
	local seal = Cfg.Seals[i]
	if not seal then
		done(false)
		return
	end
	local cin = cinema()
	local plan = Trials.SealShots(i, o.GoldOnly)
	local color = o.Gold and GOLD or (SEAL_GLOW[i] or VIOLET_HI)
	local flare: any = nil
	local finished = false
	local function reveal()
		Bus.Fire("UySealReveal", { Seal = i })
	end
	local function cleanup()
		local f = flare
		flare = nil
		if f and f.Model then
			local m = f.Model
			pcall(function()
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") then
						TweenService:Create(d, TweenInfo.new(1.2), { Transparency = 1 }):Play()
					elseif d:IsA("PointLight") then
						TweenService:Create(d, TweenInfo.new(1.2), { Brightness = 0 }):Play()
					end
				end
			end)
			task.delay(1.3, function()
				m:Destroy()
			end)
		end
	end
	local function finish(ok: boolean)
		if finished then
			return
		end
		finished = true
		sealPlaying = false
		reveal()
		cleanup()
		done(ok)
	end
	local function ignite()
		audio("SealIgnite", plan.Socket, { Volume = 1 })
		fx("Burst", plan.Socket + Vector3.new(0, 1, 0), { Color = color, Color2 = WHITE, Count = 60, Speed = { 4, 12 }, Size = { .5, .8, 0 },
			Lifetime = { .8, 1.6 }, Acceleration = Vector3.new(0, 4, 0), Drag = 2 })
		fx("Ring", plan.Altar + Vector3.new(0, .7, 0), color, 9, 1.1)
		if cin and cin.Flash then
			cin.Flash(color, .3, .5)
		end
		if Models and Models.AltarFlare then
			local ok, m, P = pcall(Models.AltarFlare, CFrame.new(plan.Socket), color)
			if ok and m then
				flare = P
				m.Parent = folder()
				-- grow the flames, spin the shard (each shard piece keeps its place relative to the shard's centre)
				local rel = {}
				for _, sp in ipairs(P.Shard) do
					rel[sp] = P.ShardCF:ToObjectSpace(sp.CFrame)
				end
				local born = os.clock()
				local conn: RBXScriptConnection? = nil
				conn = RunService.Heartbeat:Connect(function()
					if flare ~= P or not m.Parent then
						if conn then
							conn:Disconnect()
						end
						return
					end
					local t = os.clock() - born
					local k = smooth(t / .6)
					for idx, f in ipairs(P.Flames) do
						local flick = reduced() and 1 or (1 + .12 * math.sin(t * 13 + idx * 2))
						f.Size = Vector3.new(.7, 1.6 * k * flick, .7) * math.max(.05, k)
					end
					local spin = reduced() and 0 or t * 1.6
					for _, sp in ipairs(P.Shard) do
						sp.CFrame = P.ShardCF * CFrame.new(0, .3 * math.sin(t * 2), 0) * CFrame.Angles(0, spin, 0) * rel[sp]
					end
					P.Column.Transparency = .6 + .35 * smooth((t - .2) / 1.5)
				end)
			end
		end
	end
	local function play()
		sealPlaying = true
		local title = seal.Name
		local timeline = {
			{ .25, function()
				audio("BellTollHuge", plan.Tower, { Volume = 1 })
				Bus.Fire("UyBellToll", {})
				if cin and cin.Shake then
					cin.Shake(.25, .7)
				end
			end },
			{ .9, function()
				if cin and cin.Title then
					cin.Title("BELL SEAL " .. seal.Numeral, "ПЕЧАТЬ КОЛОКОЛА " .. seal.Numeral, {
						Sub = o.GoldOnly and { title[1] .. " · GOLD", title[2] .. " · ЗОЛОТО" } or { title[1] .. " · BROKEN", title[2] .. " · СЛОМАНА" },
						Duration = 2.6, Size = "Large", Position = "Upper", Color = color })
				end
			end },
			{ plan.Ignite, ignite },
		}
		if not o.GoldOnly then
			table.insert(timeline, { plan.Reveal, function()
				reveal()
				audio("SealComplete", nil, { Volume = .9 })
				local text = plan.Opens and OPENS[plan.Opens] or { "THE UNDERYARD STIRS", "ПОДДВОРЬЕ ПРОБУЖДАЕТСЯ" }
				if cin and cin.Title then
					cin.Title(text[1], text[2], { Duration = 3, Size = "Medium", Position = "Lower", Color = color })
				end
			end, Always = true })
		end
		local handle = cin and cin.Play({
			Id = "SealClear", Duration = plan.Duration, Shot = plan.Shot, Fov = 60, Letterbox = true, Skippable = true, SkipAfter = 1,
			LockControls = true, HideUI = true, Duck = "Cinematic", Timeline = timeline,
			Focus = function(t: number)
				if t < plan.B1 then
					return { Target = plan.Tower, Radius = 30 }
				elseif o.GoldOnly or t < plan.B2 then
					return { Target = plan.Socket, Radius = 8 }
				end
				return { Target = plan.Gate and plan.Gate.Position or (FOCUS[plan.District] or plan.Tower), Radius = 40 }
			end,
			OnDone = function(ok: boolean)
				finish(ok)
			end,
		})
		if not handle then
			finish(false)
		end
	end
	if not cin or type(cin.Play) ~= "function" then
		finish(false)
		return
	end
	-- a strike session / menu may still be closing after the trial: wait for the camera a moment
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 4 do
			local blocked = cin.Blocked and cin.Blocked({}) or nil
			if not blocked then
				break
			end
			task.wait(.25)
		end
		local ok, err = pcall(play)
		if not ok then
			warn("Trials: seal cinematic failed: " .. tostring(err))
			finish(false)
		end
	end)
end

function Trials.Replay(i: number)
	if sealPlaying then
		return
	end
	-- the scene is filmed in the Underyard: elsewhere it is not streamed in (the church replay has the same rule)
	if CS and type(CS.InZone) == "function" and not CS.InZone() then
		api.Toast("Go down to the Underyard to replay this scene.", "Спустись в Поддворье, чтобы пересмотреть эту сцену.", "warn")
		return
	end
	Trials.PlaySeal(i, { Replay = true })
end

---------------------------------------------------------------------------------------------------------------------
-- the end of a run: stamp, wait for the seal's rewards, cinematic, results
---------------------------------------------------------------------------------------------------------------------
local function stamp(en: string, ru: string, color: Color3)
	local cin = cinema()
	if cin and cin.Title and not sealPlaying then
		cin.Title(en, ru, { Duration = 1.8, Size = "Huge", Position = "Center", Color = color })
	end
end

local function statsOf(e: any): { any }
	local payload = e.Payload or {}
	local data = type(payload.Data) == "table" and payload.Data or {}
	local out = {}
	local p = e.P
	local elapsed = tonumber(payload.Elapsed)
	local goAt = num(data.GoAt, 0)
	local mine = data.Finish and tonumber(data.Finish[tostring(player.UserId)])
	if mine then
		table.insert(out, { "YOUR TIME", "ТВОЁ ВРЕМЯ", string.format(L("%.2f s", "%.2f с"), mine) })
	elseif elapsed and goAt > 0 and payload.StartedAt then
		table.insert(out, { "TIME", "ВРЕМЯ", Shared.Clock(math.max(0, elapsed - (goAt - num(payload.StartedAt)))) })
	end
	local value, goal = nil, nil
	if p and type(p.Score) == "function" then
		value, goal = call(p, "Score", payload)
	end
	value, goal = value or num(payload.Total), goal or num(payload.Goal, 1)
	local label = (p and type(p.ScoreLabel) == "table") and p.ScoreLabel or { "SCORE", "СЧЁТ" }
	table.insert(out, { label[1], label[2], string.format("%d / %d", math.floor(num(value)), math.floor(num(goal, 1))) })
	local hits = num(data.Hits)
	if hits > 0 then
		table.insert(out, { "PERFECT HITS", "ИДЕАЛЬНЫЕ УДАРЫ", string.format("%d / %d (%d%%)", num(data.Perfects), hits,
			math.floor(num(data.Perfects) / hits * 100 + .5)) })
	end
	for _, s in ipairs((p and call(p, "Results", payload, e.Result)) or {}) do
		if type(s) == "table" and s[1] then
			table.insert(out, s)
		end
	end
	return out
end

local function presentEnd(e: any)
	if e.Shown then
		return
	end
	e.Shown = true
	local function card()
		Trials.ShowResults({ Result = e.Result, Gold = e.Gold, First = e.First, Seal = e.Seal, Payload = e.Payload, Reason = e.Reason,
			Rewards = e.Rewards, Stats = statsOf(e), ScoreLabel = e.P and e.P.ScoreLabel })
	end
	if e.Cinematic and e.Seal then
		local wait = math.max(0, 1.6 - (os.clock() - e.At))
		task.delay(wait, function()
			Trials.PlaySeal(e.Seal, { Gold = e.Gold, GoldOnly = e.Cinematic == "Gold", Done = function()
				card()
			end })
		end)
	else
		card()
	end
end

-- C2Seal {Seal, Stage, Rewards}
local function onSeal(data: any)
	if type(data) ~= "table" then
		return
	end
	local i = tonumber(data.Seal)
	if not i or not Cfg.Seals[i] then
		return
	end
	local stage = data.Stage
	if stage ~= "Cleared" and stage ~= "Repeat" and stage ~= "Gold" then
		return
	end
	local e = pendingEnd
	if e and e.Seal == i and not e.Shown then
		for _, r in ipairs(type(data.Rewards) == "table" and data.Rewards or {}) do
			table.insert(e.Rewards, r)
		end
		if stage == "Cleared" then
			e.First = true
			e.Cinematic = "Cleared"
		elseif stage == "Gold" then
			e.Gold = true
			e.Cinematic = e.Cinematic or "Gold"
		end
		return
	end
	if e and e.Seal == i and e.Shown and results and results.Info == e then
		-- rewards that arrived after the card
		for _, r in ipairs(type(data.Rewards) == "table" and data.Rewards or {}) do
			table.insert(e.Rewards, r)
		end
		results.SetRewards(e.Rewards)
		return
	end
	if stage == "Cleared" or stage == "Gold" then
		-- no local run to attach to (e.g. the client restarted mid-trial): the cinematic + a card with the rewards
		local solo = { Result = "Won", Seal = i, Gold = stage == "Gold", First = stage == "Cleared", Payload = { Seal = i, TrialId = Cfg.Seals[i].Trial.Id },
			Rewards = type(data.Rewards) == "table" and table.clone(data.Rewards) or {}, At = os.clock() - 2, Cinematic = stage }
		pendingEnd = solo
		presentEnd(solo)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- run lifecycle
---------------------------------------------------------------------------------------------------------------------
local function stopRun(result: string, payload: any)
	local run = current
	current = nil
	if not run then
		return
	end
	ended[run.RunId] = result
	stopCountdown()
	call(run.P, "Stop", ctx, payload or run.Payload, result)
	clearMarks()
	teardownHud()
	setUrgent(0)
	if main then
		main:SetAttribute("HwTrialBottom", nil)
	end
end

local function beginRun(payload: any, late: boolean?)
	if current and current.RunId == payload.RunId then
		return
	end
	if current then
		stopRun("Left", current.Payload)
	end
	closeResults()
	local data = type(payload.Data) == "table" and payload.Data or {}
	local goAt = num(data.GoAt, num(payload.StartedAt, now()))
	local endsAt = num(payload.EndsAt)
	local run: any = { RunId = payload.RunId, TrialId = payload.TrialId, Seal = sealOf(payload), P = Trials.Presenters[payload.TrialId or ""],
		Payload = payload, GoAt = goAt, EndsAt = endsAt, Limit = endsAt > 0 and math.max(1, endsAt - goAt) or 0, Downed = false, BledOut = false,
		Started = os.clock() }
	current = run
	if not run.P then
		warn("Trials: no presenter for " .. tostring(payload.TrialId) .. " (the generic HUD still runs)")
	end
	local ok, err = pcall(function()
		hud = buildHud()
	end)
	if not ok then
		warn("Trials: HUD failed: " .. tostring(err))
		teardownHud()
	end
	if not late or goAt > now() + .3 then
		startCountdown(goAt, run.P ~= nil and run.P.HoldStart == true)
	end
	if not late then
		audio("TrialStart", nil, { Volume = .6, Pitch = .9 })
	end
	call(run.P, "Start", ctx, payload)
	Trials.Refresh()
end

local function finishRun(result: string, payload: any)
	local run = current
	if not run or run.RunId ~= payload.RunId then
		return
	end
	run.Payload = payload
	local gold = result == "Won" and type(payload.Gold) == "table" and payload.Gold[tostring(player.UserId)] == true or false
	local e: any = { RunId = run.RunId, Seal = run.Seal, Result = result, Payload = payload, Reason = payload.Reason, At = os.clock(),
		Rewards = {}, Gold = gold, P = run.P, Cinematic = nil }
	stopRun(result, payload)
	pendingEnd = e
	if result == "Won" then
		audio("TrialWin", nil, { Volume = 1 })
		if gold then
			stamp("GOLD!", "ЗОЛОТО!", GOLD)
		else
			stamp("TRIAL CLEARED!", "ИСПЫТАНИЕ ПРОЙДЕНО!", run.Seal and SEAL_GLOW[run.Seal] or SICKLY)
		end
		-- the seal's rewards / cinematic follow (C2Seal); wait a moment for them
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < (run.Seal and 2.6 or .2) and not e.Cinematic and #e.Rewards == 0 do
				task.wait(.1)
			end
			-- a first clear sends Cleared then Gold in one go: let the second one land
			if e.Cinematic then
				task.wait(.15)
			end
			presentEnd(e)
		end)
	elseif result == "Left" and (payload.Reason == nil or payload.Reason == "Left") then
		-- the player pressed LEAVE: no verdict, just a word
		e.Shown = true
		api.Toast("You left the trial", "Ты вышел из испытания", "info")
	else
		audio("TrialFail", nil, { Volume = .9 })
		stamp(result == "Left" and "OUT!" or "FAILED", result == "Left" and "ВЫБЫЛ!" or "ПРОВАЛ", BLOOD)
		task.delay(1.4, function()
			presentEnd(e)
		end)
	end
end

-- C2Trial payloads
local function onTrial(payload: any)
	if type(payload) ~= "table" or type(payload.Kind) ~= "string" then
		return
	end
	local kind = payload.Kind
	local runId = payload.RunId
	if kind == "Start" then
		if isMember(payload) then
			beginRun(payload, false)
		end
		return
	end
	if not current or current.RunId ~= runId then
		-- late: the client (re)started after the run began
		if (kind == "Tick" or kind == "Score") and not ended[runId] and isMember(payload) then
			beginRun(payload, true)
		else
			return
		end
	end
	local run = current
	run.Payload = payload
	run.EndsAt = num(payload.EndsAt, run.EndsAt)
	if kind == "Score" or kind == "Tick" then
		call(run.P, "Update", ctx, payload)
		Trials.Refresh()
	elseif kind == "Won" or kind == "Failed" then
		finishRun(kind, payload)
	elseif kind == "Left" then
		if tonumber(payload.UserId) == nil or tonumber(payload.UserId) == player.UserId then
			if payload.Reason == "BledOut" then
				run.BledOut = true
			end
			finishRun("Left", payload)
		end
	else
		call(run.P, "Signal", ctx, kind, payload, payload)
		Trials.Refresh()
	end
end
Trials.OnTrial = onTrial
Trials.OnSeal = onSeal

function Trials.Current(): any
	return current
end

function Trials.Hud(): any
	return hud
end

---------------------------------------------------------------------------------------------------------------------
-- start
---------------------------------------------------------------------------------------------------------------------
function Trials.Start(c: any)
	if Trials.Started then
		return
	end
	Trials.Started = true
	ctx = c
	CS = (c and c.Modules and c.Modules.Chapter2State) or nil
	if not CS then
		local ok, m = pcall(function()
			return require(script.Parent:WaitForChild("Chapter2State", 10) :: ModuleScript)
		end)
		CS = ok and m or nil
	end
	api.Cinema = cinema()
	api.Mixer = mixer()
	api.Refresh = function()
		Trials.Refresh()
	end
	c.Trials = api
	Trials.Api = api
	local pg = player:WaitForChild("PlayerGui")
	main = pg:WaitForChild("ScreenGui", 60)
	if main then
		local mods = main:WaitForChild("Modules", 20)
		local kitMod = mods and mods:WaitForChild("Kit", 20)
		if kitMod then
			local ok, k = pcall(require, kitMod)
			Kit = ok and k or nil
		end
	end
	loadPresenters()
	for _, rec in ipairs(Trials.Loaded) do
		if type(rec.P.Init) == "function" then
			task.spawn(call, rec.P, "Init", c)
		end
	end
	Bus.On("C2Signal", function(sig)
		if type(sig) ~= "table" then
			return
		end
		if sig.Kind == "C2Trial" then
			local ok, err = pcall(onTrial, sig.Data)
			if not ok then
				warn("Trials: C2Trial failed: " .. tostring(err))
			end
		elseif sig.Kind == "C2Seal" then
			local ok, err = pcall(onSeal, sig.Data)
			if not ok then
				warn("Trials: C2Seal failed: " .. tostring(err))
			end
		elseif sig.Kind == "C2TrialMsg" and type(sig.Data) == "table" then
			Bus.Fire("Toast", { Text = translate(sig.Data.Text), Kind = "warn", NoTranslate = true })
		end
	end)
	Bus.On("C2Replay", function(d)
		if type(d) == "table" and d.Id == "Seal" and tonumber(d.Seal) then
			Trials.Replay(tonumber(d.Seal) :: number)
		end
	end)
	watchPrompts()
	-- the HUD loop (10 Hz), the downed watch, the run that ended without its signal
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < .1 then
			return
		end
		acc = 0
		local run = current
		if not run then
			return
		end
		if player:GetAttribute("HwDowned") == true then
			run.Downed = true
		end
		if myTrial() == "" then
			run.Gone = run.Gone or os.clock()
			if os.clock() - run.Gone > 5 then
				-- the server says we are out, but its signal never came: close the run locally
				stopRun("Left", run.Payload)
				return
			end
		else
			run.Gone = nil
		end
		local ok, err = pcall(Trials.Refresh)
		if not ok and not run.Warned then
			run.Warned = true
			warn("Trials: HUD refresh failed: " .. tostring(err))
		end
	end)
	player.CharacterRemoving:Connect(function()
		-- a held start never survives a respawn
		if countdown and countdown.Locked then
			stopCountdown()
		end
	end)
end

return Trials
