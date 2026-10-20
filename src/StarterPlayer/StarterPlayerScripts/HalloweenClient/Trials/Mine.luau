-- BELL SEAL IV · HOLLOW MINE · client presenter (StarterPlayerScripts.HalloweenClient.Trials.Mine, WP-I; DESIGN §8.4.4,
-- §24.1, §24.2 "hollow ore (I)"). The server (SealMine) grows invisible Strike targets (kind "UyHollowOre", attributes
-- UyRun, Index, HP / MaxHP, Seed, Ground, Facing) at the MineNode_n craters and sends the hazards as Event HP hazards
-- (CombatFX draws every telegraph and plays the impacts). This presenter dresses YOUR run:
--   * HOLLOW ORE (Models.Seals1.HollowOre): a crooked rock foot, violet crystal spires and the hollow core in its
--     glowing shell grow out of the crater; as the node loses HP its cracks light up and the crystals break off in three
--     stages (shards fly, a crack sound); the core beats faster; the break shatters it and the core flies up ("CORE"),
--     every swing jolts it and sparks.
--   * HAZARD DRESSING (Bus "CombatHazard" from CombatFX, only hazards on the mine floor): FALLING ROCKS drop from the
--     cavern ceiling onto their telegraph exactly at the impact (dust trickles first); GAS VENTS crack the floor open and
--     breathe green gas for the lingering time; COLLAPSES rain rubble along the tunnel line.
--   * HudLines: the cores, Gold (20, never downed) and the revive hint when a miner is down.
-- ReducedMotion: no jolts / beats (the falls stay: they are the danger). Low quality: fewer shards and particles.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Halloween = RS:WaitForChild("Halloween")
local View = require(Halloween:WaitForChild("Seals1View"))
local Models = require(Halloween:WaitForChild("Models"):WaitForChild("Seals1"))
local Rules = require(Halloween:WaitForChild("SealRules"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))
local Hazards = require(Halloween:WaitForChild("Hazards"))

local P = { Ids = { "HollowMine" }, ScoreLabel = { "CORES", "ЯДРА" } }

local L = View.L
local V3 = Vector3.new
local COL = Models.Colors
local KIND = "UyHollowOre"
local CEILING_Y = 2 -- the cavern ceiling's underside (Undercrypt builder)

local ctx: any = nil
local active: any = nil

local function num(v: any, d: number?): number
	return tonumber(v) or d or 0
end

local function act(): any
	return Rules.Activity(4)
end

---------------------------------------------------------------------------------------------------------------------
-- ore nodes
---------------------------------------------------------------------------------------------------------------------
local function groundOf(part: BasePart): (Vector3, number)
	local g = part:GetAttribute("Ground")
	local ground = typeof(g) == "Vector3" and g or (part.Position - V3(0, 2.5, 0))
	return ground, num(part:GetAttribute("Facing"))
end

-- break the crystals of one stage off (shards fly, a crack)
local function breakStage(rec: any, stage: number)
	local list = rec.P.Crystals[stage] or {}
	for _, p in ipairs(list) do
		if p.Parent and p.Transparency < 1 then
			local pos = p.Position
			View.FX(ctx, "Debris", pos, COL.Ore, Enum.Material.Neon, math.floor(View.Detail(4, 3, 2)), 9)
			p.Transparency = 1
		end
	end
	View.Audio(ctx, "PlateCrack", rec.Ground + V3(0, 2, 0), { Volume = .5, Pitch = 1.2 + stage * .1 })
end

local function build(part: BasePart)
	local a = active
	if not a then
		return
	end
	local ground, facing = groundOf(part)
	local cf = CFrame.new(ground) * CFrame.Angles(0, facing, 0)
	local model, pieces = Models.HollowOre(cf, math.floor(num(part:GetAttribute("Seed"), 1)))
	model.Parent = View.Folder(ctx)
	local rec: any = { Part = part, Model = model, P = pieces, Ground = ground, CF = cf, Born = os.clock(), Stage = 0, Phase = math.random() * 6 }
	rec.CoreRel = {}
	for _, p in ipairs({ pieces.Core, pieces.Shell, pieces.CoreEye }) do
		rec.CoreRel[p] = pieces.CoreCF:ToObjectSpace(p.CFrame)
	end
	a.Recs[part] = rec
	model:PivotTo(cf * CFrame.new(0, -5, 0))
	View.Audio(ctx, "GroundCrack", ground, { Volume = .35, Pitch = 1.3 })
	View.FX(ctx, "Burst", ground + V3(0, .5, 0), { Color = COL.Rock:Lerp(COL.Bone, .3), Color2 = COL.Ore, Count = 16, Speed = { 3, 7 }, Size = { .4, .6, 0 },
		Lifetime = { .5, 1 }, Acceleration = V3(0, -20, 0) })
	-- damage stages follow the HP at once (not only while the node is animated near the camera)
	local function stages()
		local hp, max = num(part:GetAttribute("HP"), 1), math.max(1, num(part:GetAttribute("MaxHP"), 1))
		local frac = math.clamp(hp / max, 0, 1)
		local stage = frac < .34 and 2 or (frac < .67 and 1 or 0)
		while rec.Stage < stage do
			rec.Stage += 1
			breakStage(rec, rec.Stage)
		end
		local dmg = 1 - frac
		rec.Damage = dmg
		for _, c in ipairs(rec.P.Cracks) do
			c.Transparency = dmg >= num(c:GetAttribute("At")) * .9 and .1 or 1
		end
	end
	table.insert(rec, part:GetAttributeChangedSignal("HP"):Connect(function()
		rec.HitAt = os.clock()
		stages()
	end))
	table.insert(rec, part:GetAttributeChangedSignal("MaxHP"):Connect(stages))
	stages()
end

local function onRemove(part: BasePart, reason: string?)
	local a = active
	local rec = a and a.Recs[part]
	if not rec then
		return
	end
	a.Recs[part] = nil
	for _, c in ipairs(rec) do
		c:Disconnect()
	end
	local m = rec.Model
	if reason == "Broke" then
		local core = rec.P.CoreCF.Position
		View.FX(ctx, "Burst", core, { Color = COL.Ore, Color2 = COL.VioletHi, Count = math.floor(View.Detail(70, 50, 30)), Speed = { 8, 18 },
			Size = { .5, .9, 0 }, Lifetime = { .6, 1.3 }, Acceleration = V3(0, -10, 0), Drag = 2 })
		View.FX(ctx, "Debris", rec.Ground + V3(0, 1, 0), COL.Rock, Enum.Material.Slate, math.floor(View.Detail(10, 7, 4)), 14)
		View.FX(ctx, "Ring", rec.Ground + V3(0, .3, 0), COL.Ore, 8, .7)
		View.Audio(ctx, "OreBreak", core, { Volume = .8 })
		View.Audio(ctx, "SoulBurst", core, { Volume = .4, Pitch = 1.3 })
		for stage = 1, 3 do
			breakStage(rec, stage)
		end
		-- the hollow core rises and fades
		local t0 = os.clock()
		local conn: RBXScriptConnection? = nil
		conn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - t0
			if not m.Parent or t > .9 then
				if conn then
					conn:Disconnect()
				end
				m:Destroy()
				return
			end
			local k = t / .9
			local cf = rec.P.CoreCF * CFrame.new(0, 7 * k, 0) * CFrame.Angles(0, k * 6, 0)
			for p, rel in pairs(rec.CoreRel) do
				p.CFrame = cf * rel
				p.Transparency = math.max(p.Transparency, k)
			end
			for _, r in ipairs(rec.P.Rocks) do
				r.Transparency = k
			end
		end)
		task.delay(1.4, function()
			if m.Parent then
				m:Destroy()
			end
		end)
	else
		View.Fade(m, .5, 1, true)
	end
end

local function stepNode(rec: any, t: number, reduced: boolean)
	local m = rec.Model
	if not m.Parent then
		return
	end
	-- grow out of the crater
	local grow = math.clamp((os.clock() - rec.Born) / .8, 0, 1)
	local jolt = rec.Jolt and os.clock() - rec.Jolt or 9
	local base = rec.CF * CFrame.new(0, -5 * (1 - grow) ^ 3, 0)
	if jolt < .22 and not reduced then
		base *= CFrame.new(math.sin(jolt * 80) * (1 - jolt / .22) * .3, 0, 0)
	end
	if grow < 1 or jolt < .3 then
		m:PivotTo(base)
	end
	-- damage (stages / cracks: the HP watch in build): the core beats faster
	local dmg = num(rec.Damage)
	local rate = 1.6 + dmg * 5
	local beat = reduced and .5 or (.5 + .5 * math.sin(t * rate * math.pi + rec.Phase))
	rec.P.Shell.Transparency = .62 - beat * .25
	if rec.P.Light then
		rec.P.Light.Brightness = 1.2 + beat * 1.2 + dmg
	end
	if grow >= 1 and jolt >= .3 then
		local cf = rec.P.CoreCF -- the core sits on its node once grown
		local s = reduced and 1 or (1 + .06 * beat)
		for p, rel in pairs(rec.CoreRel) do
			if p == rec.P.Shell then
				p.Size = V3(2.6, 2.6, 2.6) * s
			end
			p.CFrame = cf * rel
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- hazard dressing
---------------------------------------------------------------------------------------------------------------------
local function onFloor(pos: Vector3): boolean
	local f = Layout.Undercrypt.Floor
	return pos.X >= f.Min.X - 4 and pos.X <= f.Max.X + 4 and pos.Z >= f.Min.Z - 4 and pos.Z <= f.Max.Z + 4
end

local function dressRock(a: any, centre: Vector3, impactAt: number)
	local floorY = Layout.Undercrypt.FloorY
	local fall = .55
	local seed = math.floor(centre.X * 7 + centre.Z * 13)
	local model, rp = Models.FallingRock(seed)
	local top = V3(centre.X, CEILING_Y - 1.2, centre.Z)
	local land = V3(centre.X, floorY + 1.2, centre.Z)
	model:PivotTo(CFrame.new(top))
	model.Parent = nil
	a.Maid.Give(model)
	-- dust trickles from the ceiling while the telegraph grows
	View.FX(ctx, "Emit", V3(centre.X, CEILING_Y - .5, centre.Z), 10, math.max(.2, impactAt - View.Now() - fall),
		{ Color = COL.Bone:Lerp(COL.Rock, .4), Size = { .3, .5, 0 }, Speed = { 1, 3 }, Acceleration = V3(0, -30, 0), Lifetime = { .6, 1.1 } })
	local rec = { Model = model, Top = top, Land = land, ImpactAt = impactAt, Fall = fall, Spin = math.random() * 6, P = rp }
	table.insert(a.Rocks, rec)
end

local function stepRocks(a: any)
	local now = View.Now()
	for i = #a.Rocks, 1, -1 do
		local r = a.Rocks[i]
		local start = r.ImpactAt - r.Fall
		if now >= start then
			if r.Model.Parent == nil then
				r.Model.Parent = View.Folder(ctx)
			end
			local k = math.clamp((now - start) / r.Fall, 0, 1)
			local pos = r.Top:Lerp(r.Land, k * k) -- gravity: slow off the ceiling, fast at the floor
			r.Model:PivotTo(CFrame.new(pos) * CFrame.Angles(k * r.Spin, k * 2, 0))
			if k >= 1 and not r.Landed then
				r.Landed = now
				View.FX(ctx, "Debris", r.Land, COL.Rock, Enum.Material.Slate, math.floor(View.Detail(8, 6, 3)), 12)
				View.FX(ctx, "Smoke", r.Land, COL.Bone:Lerp(COL.Rock, .5), 6, 1.4)
			end
		end
		if r.Landed and now - r.Landed > 1.2 then
			View.Fade(r.Model, .5, 1, true)
			table.remove(a.Rocks, i)
		end
	end
end

local function dressGas(a: any, centre: Vector3, impactAt: number, radius: number)
	local floorY = Layout.Undercrypt.FloorY
	local model, gp = Models.GasVent(CFrame.new(centre.X, floorY + .02, centre.Z), radius)
	model.Parent = View.Folder(ctx)
	a.Maid.Give(model)
	for _, e in ipairs(gp.Emitters) do
		e.Enabled = false
	end
	local linger = num(act().Gas and act().Gas.Linger, 6)
	local rec = { Model = model, P = gp, ImpactAt = impactAt, Until = impactAt + linger, Born = os.clock() }
	table.insert(a.Vents, rec)
	View.Audio(ctx, "GroundCrack", centre, { Volume = .35, Pitch = 1.6 })
end

local function stepVents(a: any, t: number)
	local now = View.Now()
	for i = #a.Vents, 1, -1 do
		local v = a.Vents[i]
		local open = now >= v.ImpactAt
		for _, e in ipairs(v.P.Emitters) do
			e.Enabled = open and now < v.Until
		end
		local glow = open and (.1 + .15 * math.sin(t * 6)) or (.6 - .4 * math.clamp((os.clock() - v.Born) / 1.2, 0, 1))
		for _, c in ipairs(v.P.Cracks) do
			c.Transparency = glow
		end
		if open and not v.Hiss then
			v.Hiss = true
			View.Audio(ctx, "CurseWhisper", v.Model:GetPivot().Position, { Volume = .5, Pitch = .7 })
		end
		if now >= v.Until + 1.5 then
			View.Fade(v.Model, .8, 1, true)
			table.remove(a.Vents, i)
		end
	end
end

local function dressCollapse(a: any, from: Vector3, to: Vector3, impactAt: number)
	local floorY = Layout.Undercrypt.FloorY
	local f, t2 = V3(from.X, floorY, from.Z), V3(to.X, floorY, to.Z)
	local model, cp = Models.CollapseDebris(f, t2, math.floor(from.X + to.Z))
	model.Parent = nil
	a.Maid.Give(model)
	local rest = {}
	for _, c in ipairs(cp.Chunks) do
		rest[c] = c.CFrame
	end
	table.insert(a.Collapses, { Model = model, P = cp, Rest = rest, ImpactAt = impactAt })
	-- dust along the line during the telegraph
	local n = math.floor(View.Detail(5, 4, 2))
	for k = 1, n do
		local p = f:Lerp(t2, (k - .5) / n)
		View.FX(ctx, "Emit", V3(p.X, CEILING_Y - .5, p.Z), 6, math.max(.2, impactAt - View.Now() - .3),
			{ Color = COL.Bone:Lerp(COL.Rock, .4), Size = { .3, .5, 0 }, Speed = { 1, 3 }, Acceleration = V3(0, -30, 0), Lifetime = { .6, 1.1 } })
	end
	View.Audio(ctx, "BellCreak", (f + t2) / 2, { Volume = .4, Pitch = .6 })
end

local function stepCollapses(a: any)
	local now = View.Now()
	for i = #a.Collapses, 1, -1 do
		local c = a.Collapses[i]
		local start = c.ImpactAt - .35
		if now >= start then
			if c.Model.Parent == nil then
				c.Model.Parent = View.Folder(ctx)
			end
			for _, chunk in ipairs(c.P.Chunks) do
				local delay = num(chunk:GetAttribute("K")) * .15
				local k = math.clamp((now - start - delay) / .35, 0, 1)
				chunk.CFrame = c.Rest[chunk] * CFrame.new(0, 16 * (1 - k * k), 0)
			end
		end
		if now > c.ImpactAt + 1.8 then
			View.Fade(c.Model, .6, 1, true)
			table.remove(a.Collapses, i)
		end
	end
end

local function onHazard(d: any)
	local a = active
	if not a or type(d) ~= "table" or type(d.Shape) ~= "table" then
		return
	end
	local ok, err = pcall(function()
		local ty = Hazards.TypeOf(d.Shape)
		local centre = Hazards.Center(d.Shape)
		if not centre or not onFloor(centre) then
			return
		end
		local impactAt = num(d.ImpactAt, View.Now() + 1)
		if d.Kind == "Rock" and ty == "Circle" then
			dressRock(a, centre, impactAt)
		elseif d.Kind == "Gas" and ty == "Circle" then
			dressGas(a, centre, impactAt, num(d.Shape.Radius, 5))
		elseif d.Kind == "Collapse" and ty == "Line" then
			dressCollapse(a, d.Shape.From, d.Shape.To, impactAt)
		end
	end)
	if not ok then
		warn("Trials.Mine: hazard dressing failed: " .. tostring(err))
	end
end

---------------------------------------------------------------------------------------------------------------------
-- presenter
---------------------------------------------------------------------------------------------------------------------
function P.Start(c: any, run: any)
	ctx = c
	P.Stop(c, nil, "Restart")
	if type(run) ~= "table" then
		return
	end
	local a: any = { RunId = run.RunId, Maid = View.Maid(), Recs = {}, Rocks = {}, Vents = {}, Collapses = {}, Data = type(run.Data) == "table" and run.Data or {},
		Players = run.Players or {} }
	active = a
	local stopTargets = View.Targets(KIND, run.RunId, build, onRemove)
	a.Maid.Give(stopTargets)
	local Bus = c and c.Bus
	if Bus then
		a.Maid.Give(Bus.On("CombatHazard", onHazard))
		a.Maid.Give(Bus.On("StrikeSwing", function(d)
			local rec = type(d) == "table" and a.Recs[d.Part]
			if rec then
				rec.Jolt = os.clock()
				local pos = typeof(d.Position) == "Vector3" and d.Position or rec.P.CoreCF.Position
				View.FX(c, "Burst", pos, { Color = d.Perfect and COL.Gold or COL.VioletHi, Count = d.Perfect and 18 or 10, Speed = { 4, 9 }, Size = { .25, .4, 0 },
					Lifetime = { .3, .6 } })
			end
		end))
	end
	local t = 0
	a.Maid.Give(RunService.Heartbeat:Connect(function(dt)
		t += dt
		local reduced = View.Reduced()
		local ok, err = pcall(function()
			for _, rec in pairs(a.Recs) do
				if View.Near(rec.Ground, 200) or os.clock() - rec.Born < 1 then
					stepNode(rec, t, reduced)
				end
			end
			stepRocks(a)
			stepVents(a, t)
			stepCollapses(a)
		end)
		if not ok and not a.Warned then
			a.Warned = true
			warn("Trials.Mine: " .. tostring(err))
		end
	end))
	a.Maid.Give(function()
		for part, rec in pairs(a.Recs) do
			a.Recs[part] = nil
			for _, cn in ipairs(rec) do
				cn:Disconnect()
			end
			View.Fade(rec.Model, .4, 1, true)
		end
	end)
	View.Trials(c, "Banner", "HOLLOW MINE", "ПОЛАЯ ШАХТА", {
		Sub = { string.format("Break %d hollow cores · rocks, gas and collapses hurt", num(run.Goal, 14)),
			string.format("Разбей %d полых ядер · камни, газ и обвалы ранят", num(run.Goal, 14)) }, Color = COL.Ore, Seconds = 3.2 })
end

function P.Update(_c: any, run: any)
	local a = active
	if a and type(run) == "table" and run.RunId == a.RunId then
		a.Data = type(run.Data) == "table" and run.Data or a.Data
		a.Players = run.Players or a.Players
	end
end

function P.Signal(c: any, kind: string, data: any, _run: any)
	local a = active
	if not a or type(data) ~= "table" then
		return
	end
	if kind == "Core" then
		local pos = typeof(data.Position) == "Vector3" and data.Position or nil
		if pos then
			local mine = tonumber(data.UserId) == Players.LocalPlayer.UserId
			local pl = Players:GetPlayerByUserId(math.floor(num(data.UserId)))
			local who = mine and "" or ((pl and pl.DisplayName or "?") .. " · ")
			View.Trials(c, "Popup", pos + V3(0, 7, 0), who .. "CORE +1", who .. "ЯДРО +1", mine and COL.Gold or COL.VioletHi, mine)
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
	local lines = { L("Break the hollow ore: each core counts", "Разбивай полую руду: каждое ядро в счёт") }
	local downed = {}
	for _, uid in ipairs(type(run) == "table" and run.Players or a.Players or {}) do
		local pl = Players:GetPlayerByUserId(math.floor(num(uid)))
		if pl and pl:GetAttribute("HwDowned") == true then
			table.insert(downed, pl.DisplayName)
		end
	end
	if #downed > 0 then
		table.insert(lines, L("DOWN: ", "ПОВЕРЖЕН: ") .. table.concat(downed, ", ") .. L(" · hold REVIVE on them", " · удерживай ПОДНЯТЬ рядом"))
	else
		table.insert(lines, L("Dodge the falling rocks, the gas and the collapses", "Уворачивайся от камней, газа и обвалов"))
	end
	return lines
end

function P.Active(): any
	return active
end

return P
