-- BELL SEAL III · MIRROR GRAVES · client presenter (StarterPlayerScripts.HalloweenClient.Trials.Mirror, WP-I; DESIGN
-- §8.4.3, §24.1, §24.2 "mirror grave stone rotation (I)"). The server (SealMirror) keeps the puzzle: each round's
-- awake graves (Data.Active), the stones' facings (Data.Current, d in 0..3 = the rune faces Angles(0, d * 90°) * +Z),
-- and what the pond remembers (Data.Reflection = {{Grave, At = 7 - Grave, Dir = the target mirrored east <-> west}}).
-- This presenter shows it for the runners:
--   * the six headstones (MourningMarsh.MirrorGraves.MirrorGrave_i_Stone, hinge PrimaryPart StoneHinge) turn to the
--     run's facings: every TURN grinds the stone a quarter round its hinge (eased, dust at its foot); a new round
--     spins them into the round's start. Restored to their rest pose on Stop.
--   * MIRROR RUNES: the runes of the awake graves burn violet (a soft light on the face), sleeping graves go dark.
--   * THE POND'S REFLECTION: for every awake grave g a spectral copy of ITS headstone (a clone of the stone: the same
--     rune glyph) stands on the water at the place of grave 7 - g, facing the remembered (mirrored) direction, with a
--     ripple under it; a dashed mirror axis crosses the pond between graves 6|1 and 3|4. A right answer ripples gold and
--     the next round's reflection rises; a wrong one flashes red (-15 s, the HUD shows the cut).
-- HudLines: the round, the mirror rule, the Gold state. The TURN / CONSULT prompts are the server's (only runners see
-- them: the trials host); this presenter never changes the puzzle.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Halloween = RS:WaitForChild("Halloween")
local View = require(Halloween:WaitForChild("Seals1View"))
local Models = require(Halloween:WaitForChild("Models"):WaitForChild("Seals1"))
local Rules = require(Halloween:WaitForChild("SealRules"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))

local P = { Ids = { "MirrorGraves" }, ScoreLabel = { "ROUNDS", "РАУНДЫ" } }

local L = View.L
local V3 = Vector3.new
local COL = Models.Colors
local QUARTER = math.pi / 2
local WATER_Y = -0.15 -- the mirror pond's glass top (Marsh: disc at -0.35, 0.3 thick)

local ctx: any = nil
local active: any = nil

local function num(v: any, d: number?): number
	return tonumber(v) or d or 0
end

local function act(): any
	return Rules.Activity(3)
end

-- pond centre and the place of grave i on the reflection ring (UnderyardLayout.Ring convention: grave 1 north)
local function pondCentre(): Vector3
	return Layout.Anchor("MirrorPond") or Layout.Marsh.Pond.Centre
end

local function reflectionSpot(i: number): Vector3
	local a = (i - 1) * math.pi * 2 / Rules.Graves
	local r = num(act().PondRadius, 8.6)
	local c = pondCentre()
	return V3(c.X + math.sin(a) * r, WATER_Y, c.Z - math.cos(a) * r)
end
P.ReflectionSpot = reflectionSpot

---------------------------------------------------------------------------------------------------------------------
-- the stones
---------------------------------------------------------------------------------------------------------------------
local function findStones(a: any)
	a.Stones = {}
	for g = 1, Rules.Graves do
		local m = View.Find("MirrorGrave_" .. g .. "_Stone", "Model", "MourningMarsh")
		if m and m:IsA("Model") and (m :: Model).PrimaryPart then
			local model = m :: Model
			local rest = model:GetAttribute("UyRestPivot")
			if typeof(rest) ~= "CFrame" then
				rest = model:GetPivot()
				model:SetAttribute("UyRestPivot", rest)
			end
			local runes = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and (d.Name == "RuneGlyph" or d.Name == "RunePanel") then
					table.insert(runes, { Part = d, Color = d.Color, Transparency = d.Transparency, Material = d.Material })
				end
			end
			a.Stones[g] = { Model = model, Rest = rest, Angle = 0, Dir = 0, Anim = nil, Runes = runes, Awake = nil }
		end
	end
end

local function poseStone(s: any, angle: number)
	s.Angle = angle
	s.Model:PivotTo(s.Rest * CFrame.Angles(0, angle, 0))
end

-- turn stone s to facing d: forward (the way TURN goes) by the shortest number of quarters, `spins` extra full turns
local function turnStone(s: any, d: number, seconds: number, spins: number?)
	local cur = s.Anim and s.Anim.To or s.Angle
	local curDir = math.floor((cur / QUARTER) + .5) % 4
	local steps = (math.floor(d) - curDir) % 4
	local to = cur + steps * QUARTER + (spins or 0) * math.pi * 2
	s.Dir = math.floor(d) % 4
	if math.abs(to - s.Angle) < 1e-4 and not s.Anim then
		return
	end
	if View.Reduced() and (spins or 0) > 0 then
		to = cur + steps * QUARTER
	end
	s.Anim = { From = s.Angle, To = to, At = os.clock(), Seconds = math.max(.05, seconds) }
end

local function stepStones(a: any)
	for _, s in pairs(a.Stones) do
		local an = s.Anim
		if an then
			local k = math.clamp((os.clock() - an.At) / an.Seconds, 0, 1)
			-- a stone grinds: slow start, a little overshoot at the end
			local e = k < 1 and (1 - (1 - k) ^ 3) * (1 + .08 * math.sin(k * math.pi)) or 1
			poseStone(s, an.From + (an.To - an.From) * e)
			if k >= 1 then
				s.Anim = nil
				-- keep the angle small (no drift over many turns)
				poseStone(s, (s.Dir % 4) * QUARTER)
			end
		end
	end
end

local function paintRunes(a: any, activeSet: { [number]: boolean })
	for g, s in pairs(a.Stones) do
		local awake = activeSet[g] == true
		if s.Awake ~= awake then
			s.Awake = awake
			for _, r in ipairs(s.Runes) do
				local p = r.Part
				if p.Name == "RuneGlyph" then
					p.Material = Enum.Material.Neon
					p.Color = awake and COL.VioletHi or COL.Ink:Lerp(COL.Violet, .25)
					p.Transparency = awake and 0 or .35
				end
			end
			if s.Light then
				s.Light:Destroy()
				s.Light = nil
			end
			if awake then
				local glyph = nil
				for _, r in ipairs(s.Runes) do
					if r.Part.Name == "RuneGlyph" then
						glyph = r.Part
						break
					end
				end
				if glyph then
					local l = Instance.new("PointLight")
					l.Name = "TrialRuneLight"
					l.Color = COL.VioletHi
					l.Range = 9
					l.Brightness = 1.6
					l.Shadows = false
					l.Parent = glyph
					s.Light = l
				end
			end
		end
	end
end

local function restoreStones(a: any)
	for _, s in pairs(a.Stones or {}) do
		s.Anim = nil
		pcall(poseStone, s, 0)
		for _, r in ipairs(s.Runes) do
			r.Part.Color, r.Part.Transparency, r.Part.Material = r.Color, r.Transparency, r.Material
		end
		if s.Light then
			s.Light:Destroy()
			s.Light = nil
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the reflection
---------------------------------------------------------------------------------------------------------------------
local function ghostOf(a: any, g: number): Model
	local s = a.Stones[g]
	local ghost: Model? = nil
	if s then
		local ok, clone = pcall(function()
			return s.Model:Clone()
		end)
		if ok and clone then
			ghost = clone
			clone:SetAttribute("UyRestPivot", nil)
			local hinge = clone:FindFirstChild("StoneHinge")
			if hinge and hinge:IsA("BasePart") then
				clone.PrimaryPart = hinge
			end
			for _, d in ipairs(clone:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
					d.CastShadow = false
					if d.Name == "RuneGlyph" then
						d.Material = Enum.Material.Neon
						d.Color = COL.VioletHi
						d.Transparency = 0
					elseif d.Transparency < 1 then
						d.Material = Enum.Material.ForceField
						d.Color = COL.Moon
						d.Transparency = .1
					end
				elseif d:IsA("Light") or d:IsA("ParticleEmitter") then
					d:Destroy()
				end
			end
			pcall(function()
				(clone :: any):ScaleTo(.62)
			end)
		end
	end
	if not ghost then
		local m = Models.GhostStone(CFrame.new())
		ghost = m
	end
	local gm = ghost :: Model
	gm.Name = "Reflection_" .. g
	return gm
end

local function clearReflection(a: any, sink: boolean)
	for _, r in ipairs(a.Reflection or {}) do
		if sink then
			View.Fade(r.Model, .5, 1, true)
			if r.Ripple then
				View.Fade(r.Ripple, .5, 1, true)
			end
		else
			r.Model:Destroy()
			if r.Ripple then
				r.Ripple:Destroy()
			end
		end
	end
	a.Reflection = {}
end

local function buildReflection(a: any, list: { any }, round: number)
	clearReflection(a, true)
	a.ShownRound = round
	for _, e in ipairs(list or {}) do
		local g, at, dir = math.floor(num(e.Grave)), math.floor(num(e.At)), math.floor(num(e.Dir))
		local spot = reflectionSpot(at)
		local ghost = ghostOf(a, g)
		local cf = CFrame.new(spot) * CFrame.Angles(0, dir * QUARTER, 0)
		ghost.Parent = View.Folder(ctx)
		pcall(function()
			ghost:PivotTo(cf * CFrame.new(0, -3, 0))
		end)
		-- a ripple ring under it
		local ripple = Instance.new("Model")
		ripple.Name = "Ripple_" .. g
		for k = 1, 12 do
			local ang = (k - .5) / 12 * math.pi * 2
			Models.Part(ripple, "RippleSeg", V3(1.1, .05, .18), CFrame.new(spot) * CFrame.Angles(0, -ang, 0) * CFrame.new(0, .03, -2.2), COL.Moon,
				Enum.Material.Neon, { Transparency = .45 })
		end
		ripple.Parent = View.Folder(ctx)
		table.insert(a.Reflection, { Model = ghost, Ripple = ripple, CF = cf, Born = os.clock(), Grave = g, At = at, Dir = dir })
	end
	View.Audio(ctx, "MarshFrog", pondCentre(), { Volume = .15, Pitch = .7 })
	View.Audio(ctx, "Whisper2", pondCentre(), { Volume = .35 })
end

local function stepReflection(a: any, t: number, reduced: boolean)
	for i, r in ipairs(a.Reflection) do
		local k = math.clamp((os.clock() - r.Born - (i - 1) * .12) / .8, 0, 1)
		local rise = -3 * (1 - k) ^ 3 -- out of the water (ease-out)
		local bob = reduced and 0 or math.sin(t * 1.3 + i) * .12
		pcall(function()
			r.Model:PivotTo(r.CF * CFrame.new(0, rise + bob, 0))
		end)
		if r.Ripple then
			local tr = .35 + (reduced and 0 or .25 * math.sin(t * 2.4 + i))
			for _, d in ipairs(r.Ripple:GetChildren()) do
				if d:IsA("BasePart") then
					d.Transparency = tr
				end
			end
		end
	end
end

-- the mirror axis: between graves 6 | 1 and 3 | 4 (left <-> right of the pond)
local function buildAxis(a: any)
	local m = Instance.new("Model")
	m.Name = "MirrorAxis"
	local c = pondCentre()
	local ang = -math.pi / Rules.Graves -- halfway between grave 6 and grave 1
	local dir = V3(math.sin(ang), 0, -math.cos(ang))
	local r = num(act().PondRadius, 8.6) + 3.6
	local n = 11
	for k = 0, n - 1 do
		local u0 = -r + (k + .2) / n * 2 * r
		local u1 = -r + (k + .75) / n * 2 * r
		local p0, p1 = V3(c.X, WATER_Y + .04, c.Z) + dir * u0, V3(c.X, WATER_Y + .04, c.Z) + dir * u1
		local mid = (p0 + p1) / 2
		Models.Part(m, "AxisDash", V3(.22, .04, (p1 - p0).Magnitude), Models.Look(mid, p1), COL.VioletHi, Enum.Material.Neon, { Transparency = .5 })
	end
	m.Parent = View.Folder(ctx)
	a.Maid.Give(m)
end

---------------------------------------------------------------------------------------------------------------------
-- presenter
---------------------------------------------------------------------------------------------------------------------
local function activeSet(data: any): { [number]: boolean }
	local set = {}
	for _, g in ipairs(type(data.Active) == "table" and data.Active or {}) do
		set[math.floor(num(g))] = true
	end
	return set
end

-- bring the stones / runes / reflection in line with the server's data (late joins, missed signals)
local function sync(a: any, data: any, seconds: number?)
	local cur = type(data.Current) == "table" and data.Current or {}
	for g, s in pairs(a.Stones) do
		local d = cur[g]
		if d ~= nil and (math.floor(num(d)) % 4 ~= s.Dir or (s.Anim == nil and math.abs(s.Angle - s.Dir * QUARTER) > 1e-3)) then
			turnStone(s, num(d), seconds or .35)
		end
	end
	paintRunes(a, activeSet(data))
	local round = math.floor(num(data.Round, 1))
	if a.ShownRound ~= round and type(data.Reflection) == "table" then
		buildReflection(a, data.Reflection, round)
	end
end

function P.Start(c: any, run: any)
	ctx = c
	P.Stop(c, nil, "Restart")
	if type(run) ~= "table" then
		return
	end
	local data = type(run.Data) == "table" and run.Data or {}
	local a: any = { RunId = run.RunId, Maid = View.Maid(), Data = data, Reflection = {} }
	active = a
	findStones(a)
	a.Maid.Give(function()
		clearReflection(a, false)
		restoreStones(a)
	end)
	pcall(buildAxis, a)
	sync(a, data, .6)
	local t = 0
	a.Maid.Give(RunService.Heartbeat:Connect(function(dt)
		t += dt
		local ok, err = pcall(function()
			stepStones(a)
			stepReflection(a, t, View.Reduced())
		end)
		if not ok and not a.Warned then
			a.Warned = true
			warn("Trials.Mirror: " .. tostring(err))
		end
	end))
	View.Trials(c, "Banner", "MIRROR GRAVES", "ЗЕРКАЛЬНЫЕ МОГИЛЫ", {
		Sub = { "Turn the runes until they match the pond, mirrored", "Поверни руны так, как помнит пруд — зеркально" }, Color = COL.Moon, Seconds = 3.4 })
end

function P.Update(_c: any, run: any)
	local a = active
	if not a or type(run) ~= "table" or run.RunId ~= a.RunId or type(run.Data) ~= "table" then
		return
	end
	a.Data = run.Data
	sync(a, run.Data)
end

function P.Signal(c: any, kind: string, data: any, run: any)
	local a = active
	if not a or type(data) ~= "table" then
		return
	end
	local rd = type(run) == "table" and type(run.Data) == "table" and run.Data or a.Data
	a.Data = rd
	if kind == "Turn" then
		local g = math.floor(num(data.Grave))
		local s = a.Stones[g]
		if s then
			turnStone(s, num(data.Dir), num(act().TurnCooldown, .35))
			local foot = s.Rest.Position
			View.FX(c, "Burst", foot + V3(0, .4, 0), { Color = COL.Bone:Lerp(COL.Rock, .5), Count = 12, Speed = { 2, 5 }, Size = { .3, .5, 0 },
				Lifetime = { .4, .8 }, Acceleration = V3(0, -12, 0) })
			View.Audio(c, "GroundCrack", foot, { Volume = .3, Pitch = 1.5 })
		end
	elseif kind == "Round" then
		local pond = pondCentre()
		View.FX(c, "Ring", V3(pond.X, WATER_Y + .1, pond.Z), COL.Gold, 15, 1.2)
		View.FX(c, "Burst", V3(pond.X, 1, pond.Z), { Color = COL.Gold, Color2 = COL.Moon, Count = 40, Speed = { 5, 12 }, Size = { .4, .7, 0 },
			Lifetime = { .7, 1.4 } })
		View.Audio(c, "Toll", pond, { Volume = .6, Pitch = 1.3 })
		if data.Final then
			clearReflection(a, true)
		else
			View.Trials(c, "Banner", string.format("ROUND %d / %d", num(data.Round), num(rd.Rounds, 3)),
				string.format("РАУНД %d / %d", num(data.Round), num(rd.Rounds, 3)), { Sub = { "The pond remembers more graves", "Пруд помнит больше могил" },
				Color = COL.Gold, Seconds = 2.2 })
			-- the stones spin into the next round's start while the new reflection rises
			local cur = type(rd.Current) == "table" and rd.Current or {}
			for g, s in pairs(a.Stones) do
				if cur[g] ~= nil then
					turnStone(s, num(cur[g]), num(act().RoundPause, 1.4), 1)
				end
			end
			paintRunes(a, activeSet(rd))
			if type(rd.Reflection) == "table" then
				buildReflection(a, rd.Reflection, math.floor(num(rd.Round, num(data.Round))))
			end
		end
	elseif kind == "Wrong" then
		local pond = pondCentre()
		View.FX(c, "Ring", V3(pond.X, WATER_Y + .1, pond.Z), COL.Blood, 15, .9)
		View.Audio(c, "Deny", nil, { Volume = .7 })
		View.Audio(c, "CurseWhisper", pond, { Volume = .4 })
		local n = math.floor(num(data.Wrong))
		local pen = math.floor(num(data.Penalty, num(act().WrongPenalty, 15)))
		View.Trials(c, "Toast", string.format("The pond disagrees: %d %s still wrong (-%d s)", n, n == 1 and "grave is" or "graves are", pen),
			string.format("Пруд не согласен: неверных могил — %d (-%d с)", n, pen), "warn")
		for _, r in ipairs(a.Reflection) do
			r.Born = os.clock() - .8 -- (no re-rise)
			if r.Ripple then
				for _, d in ipairs(r.Ripple:GetChildren()) do
					if d:IsA("BasePart") then
						d.Color = COL.Blood
					end
				end
				task.delay(.8, function()
					if r.Ripple and r.Ripple.Parent then
						for _, d in ipairs(r.Ripple:GetChildren()) do
							if d:IsA("BasePart") then
								d.Color = COL.Moon
							end
						end
					end
				end)
			end
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
	local awake = type(data.Active) == "table" and #data.Active or 0
	local lines = {
		string.format(L("Round %d / %d · %d graves awake", "Раунд %d / %d · проснулось могил: %d"), num(data.Round, 1), num(data.Rounds, 3), awake),
		L("The pond swaps graves 1↔6, 2↔5, 3↔4 and flips east↔west", "Пруд меняет могилы 1↔6, 2↔5, 3↔4 и восток↔запад"),
	}
	local wrong = num(data.Wrong)
	if wrong > 0 then
		table.insert(lines, string.format(L("Wrong consults: %d (Gold lost)", "Ошибок у пруда: %d (золото упущено)"), wrong))
	elseif View.Now() < num(data.ReadyAt) then
		table.insert(lines, L("The graves are settling...", "Могилы успокаиваются..."))
	else
		table.insert(lines, L("TURN the runes, then CONSULT THE POND at the basin", "ПОВЕРНИ руны и СПРОСИ ПРУД у чаши"))
	end
	return lines
end

function P.Results(run: any, _result: any): { any }?
	local data = type(run) == "table" and type(run.Data) == "table" and run.Data or {}
	return { { "WRONG CONSULTS", "ОШИБОК У ПРУДА", tostring(math.floor(num(data.Wrong))) } }
end

function P.Active(): any
	return active
end

return P
