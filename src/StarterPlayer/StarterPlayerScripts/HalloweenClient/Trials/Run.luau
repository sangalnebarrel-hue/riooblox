-- BELL SEAL II · FUNERAL RUN · client presenter (StarterPlayerScripts.HalloweenClient.Trials.Run, WP-I; DESIGN §8.4.2,
-- §24.1, §24.2). The server (SealRun) validates every ring from 4 Hz samples; this presenter guides the runner:
--   * CHECKPOINTS: the next arch (FuneralCarnival.FuneralRun.Checkpoints.RunCheckpoint_i) glows gold (its Neon hoop
--     RunRing + a Highlight + a light), the one after it violet, the passed ones green; a world mark "RING n" with the
--     distance hangs over the next arch. Every ring the server credits: a burst, a chime, the split time.
--   * the NEXT ARROW: a gold arrow floats over the runner's head and turns to the next ring (smoothed).
--   * PENDULUMS: under each coffin (RunPendulum_i) a dashed arc on the lane shows its sweep; the dash under the coffin
--     right now lights up (the §24.2 swing on the server clock, the same formula as the server hazard and UnderyardFX).
--     The telegraph / damage of each pass is CombatFX's (Event HP hazards).
--   * CAROUSEL: on the leg that crosses the carousel deck (Data.Carousel) the HUD says to ride it round.
--   * REWIND (Signal "Rewind": the server put the runner back on its last ring): a red flash and why ("Too fast").
--   * FINISH: your time, Gold or not; the party's finishes as toasts.
-- HoldStart: movement is held during the 3-2-1 (the trials host). Score: YOUR rings / 10. Every arch, light and model
-- is restored / destroyed on Stop.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Halloween = RS:WaitForChild("Halloween")
local View = require(Halloween:WaitForChild("Seals1View"))
local Models = require(Halloween:WaitForChild("Models"):WaitForChild("Seals1"))
local Rules = require(Halloween:WaitForChild("SealRules"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))

local P = { Ids = { "FuneralRun" }, ScoreLabel = { "RINGS", "КОЛЬЦА" }, HoldStart = true }

local L = View.L
local V3 = Vector3.new
local COL = Models.Colors
local NEXT = COL.Gold
local AFTER = COL.VioletHi
local DONE = COL.Sickly

local ctx: any = nil
local active: any = nil

local function num(v: any, d: number?): number
	return tonumber(v) or d or 0
end

local function me(): number
	return Players.LocalPlayer.UserId
end

local function myRings(data: any): number
	return math.floor(num(data and data.Progress and data.Progress[tostring(me())], 0))
end

local function checkpointPos(i: number): Vector3?
	return Layout.Anchor("RunCheckpoint_" .. i)
end

---------------------------------------------------------------------------------------------------------------------
-- the arches: remember every RunRing part, paint them by state, restore them
---------------------------------------------------------------------------------------------------------------------
local function collectArches(a: any)
	a.Arches = {}
	local run = View.Find("FuneralRun", "Model", "FuneralCarnival")
	local holder = run and run:FindFirstChild("Checkpoints")
	for i = 1, num(a.Count, 10) do
		local arch = holder and holder:FindFirstChild("RunCheckpoint_" .. i) or View.Find("RunCheckpoint_" .. i, "Model", "FuneralCarnival")
		if arch and arch:IsA("Model") then
			local rec = { Model = arch, Rings = {}, State = nil }
			for _, d in ipairs(arch:GetDescendants()) do
				if d:IsA("BasePart") and (d.Name == "RunRing" or d.Name == "RunLine" or d.Name == "ArchFinialGlow") then
					table.insert(rec.Rings, { Part = d, Color = d.Color, Transparency = d.Transparency, Material = d.Material })
				end
			end
			a.Arches[i] = rec
		end
	end
end

local function paintArch(a: any, i: number, state: string)
	local rec = a.Arches[i]
	if not rec or rec.State == state then
		return
	end
	rec.State = state
	for _, r in ipairs(rec.Rings) do
		local p = r.Part
		if state == "Base" then
			p.Color, p.Transparency, p.Material = r.Color, r.Transparency, r.Material
		else
			p.Material = Enum.Material.Neon
			p.Color = state == "Next" and NEXT or (state == "After" and AFTER or DONE)
			p.Transparency = state == "Done" and .35 or 0
		end
	end
	if rec.Highlight then
		rec.Highlight:Destroy()
		rec.Highlight = nil
	end
	if rec.Light then
		rec.Light:Destroy()
		rec.Light = nil
	end
	if state == "Next" then
		local h = Instance.new("Highlight")
		h.Name = "TrialNextRing"
		h.FillTransparency = .85
		h.FillColor = NEXT
		h.OutlineColor = NEXT
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Adornee = rec.Model
		h.Parent = View.Folder(ctx)
		rec.Highlight = h
		local pos = checkpointPos(i)
		if pos then
			local holder = Models.Part(View.Folder(ctx), "NextRingLight", V3(.2, .2, .2), CFrame.new(pos + V3(0, 3, 0)), NEXT, Enum.Material.SmoothPlastic,
				{ Transparency = 1 })
			local l = Instance.new("PointLight")
			l.Color = NEXT
			l.Range = 18
			l.Brightness = 2
			l.Shadows = false
			l.Parent = holder
			rec.Light = holder
		end
	end
end

local function restoreArches(a: any)
	for i in pairs(a.Arches or {}) do
		paintArch(a, i, "Base")
	end
end

local function refreshArches(a: any)
	local nextI = a.Rings + 1
	for i in pairs(a.Arches) do
		local state = (i < nextI and "Done") or (i == nextI and "Next") or (i == nextI + 1 and "After") or "Base"
		paintArch(a, i, state)
	end
	-- the world mark over the next ring
	local pos = checkpointPos(nextI)
	if pos and not a.Finished then
		local en, ru = "RING " .. nextI, "КОЛЬЦО " .. nextI
		if nextI == a.Count then
			en, ru = "FINISH", "ФИНИШ"
		end
		if a.Mark then
			pcall(a.Mark.SetPosition, pos + V3(0, 4, 0))
			pcall(a.Mark.SetText, en, ru)
		else
			a.Mark = View.Trials(ctx, "Mark", pos + V3(0, 4, 0), en, ru, { Color = NEXT, Height = 6 })
		end
	elseif a.Mark then
		pcall(a.Mark.Destroy)
		a.Mark = nil
	end
end

---------------------------------------------------------------------------------------------------------------------
-- pendulum arcs
---------------------------------------------------------------------------------------------------------------------
local function buildArcs(a: any)
	a.Arcs = {}
	local act = Rules.Activity(2)
	for i = 1, #Layout.Carnival.Pendulums do
		local m = View.Find("RunPendulum_" .. i, "Model", "FuneralCarnival")
		local hinge: CFrame? = nil
		local attrs = nil
		if m and m:IsA("Model") then
			local pp = (m :: Model).PrimaryPart
			hinge = pp and pp.CFrame or (m :: Model):GetPivot()
			attrs = m:GetAttributes()
		end
		if not hinge then
			local path = { Layout.Carnival.RunStart }
			for _, p in ipairs(Layout.Carnival.Checkpoints) do
				table.insert(path, p)
			end
			hinge = Rules.FallbackHinge(Layout.Carnival.Pendulums[i], path, act)
		end
		local spec = Rules.PendulumSpec(i, hinge :: CFrame, attrs, act)
		local am, ap = Models.SwingArc(spec.Hinge, spec.Arm, spec.Amp, spec.GroundY, View.Detail(15, 13, 9))
		am.Parent = View.Folder(ctx)
		a.Maid.Give(am)
		table.insert(a.Arcs, { Spec = spec, P = ap })
	end
end

local function stepArcs(a: any)
	local t = View.Now()
	for _, arc in ipairs(a.Arcs) do
		local s = arc.Spec
		local angle = Rules.SwingAngle(t, s.Amp, s.Period, s.Phase)
		for _, d in ipairs(arc.P.Dashes) do
			local da = math.abs(num(d:GetAttribute("A")) - angle)
			local hot = math.clamp(1 - da / .22, 0, 1)
			d.Transparency = .55 - hot * .5
			d.Color = COL.Candle:Lerp(COL.Blood, hot)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the guide arrow
---------------------------------------------------------------------------------------------------------------------
local function stepArrow(a: any, dt: number, reduced: boolean)
	local root = View.RootPart()
	local target = checkpointPos(a.Rings + 1)
	local show = root ~= nil and target ~= nil and not a.Finished
	if not show then
		if a.Arrow then
			a.Arrow.Model.Parent = nil
		end
		return
	end
	if not a.Arrow then
		local m, ap = Models.RunArrow(1.5)
		a.Arrow = ap
		a.Maid.Give(m)
	end
	local m = a.Arrow.Model
	if m.Parent == nil then
		m.Parent = View.Folder(ctx)
	end
	local from = (root :: BasePart).Position
	local d = Rules.Flat((target :: Vector3) - from)
	if d.Magnitude < .5 then
		return
	end
	local yaw = math.atan2(-d.X, -d.Z)
	a.ArrowYaw = a.ArrowYaw and (a.ArrowYaw + math.atan2(math.sin(yaw - a.ArrowYaw), math.cos(yaw - a.ArrowYaw)) * math.min(1, dt * 10)) or yaw
	local bob = reduced and 0 or math.sin(os.clock() * 3) * .3
	local pos = from + V3(0, 6.2 + bob, 0) + V3(-math.sin(a.ArrowYaw), 0, -math.cos(a.ArrowYaw)) * 1.5
	m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, a.ArrowYaw, 0) * CFrame.Angles(-.25, 0, 0))
end

---------------------------------------------------------------------------------------------------------------------
-- presenter
---------------------------------------------------------------------------------------------------------------------
function P.Score(run: any): (number, number)
	local data = type(run) == "table" and type(run.Data) == "table" and run.Data or {}
	return myRings(data), num(data.Checkpoints, num(run and run.Goal, 10))
end

function P.Start(c: any, run: any)
	ctx = c
	P.Stop(c, nil, "Restart")
	if type(run) ~= "table" then
		return
	end
	local data = type(run.Data) == "table" and run.Data or {}
	local a: any = { RunId = run.RunId, Maid = View.Maid(), Count = num(data.Checkpoints, 10), Rings = myRings(data), Data = data, Splits = {},
		Finished = data.Finish ~= nil and data.Finish[tostring(me())] ~= nil, Party = #(run.Players or {}) }
	active = a
	collectArches(a)
	a.Maid.Give(function()
		restoreArches(a)
		for _, rec in pairs(a.Arches or {}) do
			if rec.Highlight then
				rec.Highlight:Destroy()
			end
			if rec.Light then
				rec.Light:Destroy()
			end
		end
		if a.Mark then
			pcall(a.Mark.Destroy)
			a.Mark = nil
		end
	end)
	pcall(buildArcs, a)
	refreshArches(a)
	a.Maid.Give(RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(function()
			stepArrow(a, dt, View.Reduced())
			stepArcs(a)
		end)
		if not ok and not a.Warned then
			a.Warned = true
			warn("Trials.Run: " .. tostring(err))
		end
	end))
	View.Trials(c, "Banner", "FUNERAL RUN", "ПОХОРОННЫЙ ЗАБЕГ", {
		Sub = { "10 rings in order · mind the swinging coffins", "10 колец по порядку · берегись качающихся гробов" }, Color = COL.Candle, Seconds = 3.2 })
end

function P.Update(_c: any, run: any)
	local a = active
	if not a or type(run) ~= "table" or run.RunId ~= a.RunId then
		return
	end
	a.Data = type(run.Data) == "table" and run.Data or a.Data
	a.Party = #(run.Players or {})
	local rings = myRings(a.Data)
	if rings ~= a.Rings then
		a.Rings = rings
		refreshArches(a)
	end
end

function P.Signal(c: any, kind: string, data: any, run: any)
	local a = active
	if not a or type(data) ~= "table" then
		return
	end
	if type(run) == "table" and type(run.Data) == "table" then
		a.Data = run.Data
	end
	local mine = tonumber(data.UserId) == me()
	if kind == "Checkpoint" then
		local i = math.floor(num(data.Index))
		local pos = checkpointPos(i)
		if mine then
			a.Rings = math.max(a.Rings, i)
			a.Splits[i] = num(data.Split)
			refreshArches(a)
			if pos then
				View.FX(c, "Ring", pos - V3(0, 2.6, 0), NEXT, 9, .6)
				View.FX(c, "Burst", pos + V3(0, 2, 0), { Color = NEXT, Color2 = COL.Bone, Count = 26, Speed = { 4, 10 }, Size = { .35, .55, 0 },
					Lifetime = { .5, 1 } })
				View.Trials(c, "Popup", pos + V3(0, 5, 0), string.format("RING %d · %.1f s", i, num(data.Split)),
					string.format("КОЛЬЦО %d · %.1f с", i, num(data.Split)), NEXT, false)
			end
			View.Audio(c, "Toll", pos, { Volume = .5, Pitch = 1.2 + i * .04 })
			View.Audio(c, "Unlock", nil, { Volume = .35 })
		elseif pos then
			local pl = Players:GetPlayerByUserId(math.floor(num(data.UserId)))
			View.Trials(c, "Popup", pos + V3(0, 6, 0), (pl and pl.DisplayName or "?") .. " · " .. i, (pl and pl.DisplayName or "?") .. " · " .. i,
				COL.Moon, false)
		end
	elseif kind == "Finish" then
		local tm = num(data.Time)
		local gold = num(Cfg.Seals[2].Gold.Time, 55)
		if mine then
			a.Finished = true
			a.FinishTime = tm
			refreshArches(a)
			local pos = checkpointPos(a.Count)
			if pos then
				View.FX(c, "Beam", pos - V3(0, 3, 0), tm <= gold and COL.Gold or COL.Sickly, 30, 2.4)
			end
			View.Trials(c, "Banner", "FINISHED!", "ФИНИШ!", { Sub = { string.format("%.2f s%s", tm, tm <= gold and " · GOLD PACE" or ""),
				string.format("%.2f с%s", tm, tm <= gold and " · ЗОЛОТОЙ ТЕМП" or "") }, Color = tm <= gold and COL.Gold or COL.Sickly, Seconds = 3 })
			if a.Party > 1 then
				View.Trials(c, "Toast", "Wait for the others: the run ends when everyone has finished", "Жди остальных: забег закончится, когда все финишируют")
			end
		else
			local pl = Players:GetPlayerByUserId(math.floor(num(data.UserId)))
			local name = pl and pl.DisplayName or "?"
			View.Trials(c, "Toast", string.format("%s finished in %.1f s", name, tm), string.format("%s финишировал за %.1f с", name, tm))
		end
	elseif kind == "Rewind" and mine then
		a.Rings = math.max(0, math.floor(num(data.Index, 1)) - 1)
		refreshArches(a)
		View.Audio(c, "Deny", nil, { Volume = .7 })
		local cin = c and c.Trials and c.Trials.Cinema
		if cin and cin.Flash then
			pcall(cin.Flash, COL.Blood, .35, .5)
		end
		local left = math.max(0, num(Cfg.Seals[2].Activity.MaxViolations, Rules.Activity(2).MaxViolations) - num(data.Violations))
		if data.Reason == "TooFast" then
			View.Trials(c, "Toast", string.format("Too fast to be true: back to ring %d (%d more and you are out)", a.Rings, left),
				string.format("Слишком быстро: назад к кольцу %d (ещё %d — и ты выбыл)", a.Rings, left), "warn")
		else
			View.Trials(c, "Toast", string.format("You jumped too far: back to ring %d (%d more and you are out)", a.Rings, left),
				string.format("Слишком далёкий прыжок: назад к кольцу %d (ещё %d — и ты выбыл)", a.Rings, left), "warn")
		end
	end
end

function P.Stop(_c: any, run: any, _result: any)
	local a = active
	if not a or (type(run) == "table" and run.RunId ~= nil and run.RunId ~= a.RunId) then
		return
	end
	active = nil
	a.Maid.Clean()
end

function P.HudLines(run: any): { string }?
	local a = active
	if not a then
		return nil
	end
	local data = type(run) == "table" and type(run.Data) == "table" and run.Data or a.Data or {}
	local lines = {}
	if a.Finished then
		table.insert(lines, string.format(L("Finished in %.2f s", "Финиш за %.2f с"), num(a.FinishTime)))
	else
		local nextI = a.Rings + 1
		local pos = checkpointPos(nextI)
		local root = View.RootPart()
		local dist = (pos and root) and Rules.Flat(pos - root.Position).Magnitude or nil
		local label = nextI >= a.Count and L("Next: the FINISH", "Дальше: ФИНИШ") or string.format(L("Next: ring %d", "Дальше: кольцо %d"), nextI)
		table.insert(lines, label .. (dist and string.format(L(" · %d m", " · %d м"), math.floor(dist + .5)) or ""))
		if num(data.Carousel) > 0 and nextI == num(data.Carousel) + 1 then
			table.insert(lines, L("Ride the turning carousel deck round to the next ring", "Проедь на крутящейся карусели к следующему кольцу"))
		end
	end
	local last = a.Splits[a.Rings]
	if a.Party > 1 then
		local n = 0
		for _ in pairs(type(data.Finish) == "table" and data.Finish or {}) do
			n += 1
		end
		table.insert(lines, string.format(L("Finished: %d / %d", "Финишировали: %d / %d"), n, a.Party))
	elseif last and not a.Finished then
		table.insert(lines, string.format(L("Last split: %.1f s", "Последний отрезок: %.1f с"), last))
	end
	return lines
end

function P.Active(): any
	return active
end

return P
