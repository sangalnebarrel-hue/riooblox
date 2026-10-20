-- BELL SEAL I · ECHO DIG · client presenter (StarterPlayerScripts.HalloweenClient.Trials.Echo, WP-I; DESIGN §8.4.1,
-- §24.1, §24.2 "echo point visuals (I)"). The server (SealEcho) raises invisible Strike targets (kind "UyEcho",
-- attributes UyRun, Index, Ground, Facing, LifeFrom, Life, ExpireAt, JumpTo?, JumpAt?, NextPos?, Pup) at the EchoPoint_n
-- anchors; this presenter turns each of YOUR run's targets into a haunted echo (Models.Seals1.EchoMound):
--   * a spectral grave mound rising out of the plaza with a ghostly shell, a crooked headstone with a bell rune, a rune
--     ring whose 18 segments are the echo's LIFE (they go dark one by one: when the ring is empty it jumps) and a
--     swaying spirit bell over it; wisps and a cold light.
--   * the JUMP: when the server telegraphs it (JumpTo / JumpAt) the ring flashes violet, an arc of wisp orbs reaches out
--     to the landing point (a comet runs along it) and a landing rune pulses there; at the jump the mound sinks, a soul
--     orb flies the arc, and the mound rises again at the new point.
--   * H09 Bell Pup (ECHO EAR, attribute NextPos): the next landing point pulses gold with a paw from the moment the echo
--     rises; the life is 4 s longer (the server's numbers, shown in the HUD line).
--   * digging: every swing jolts the mound and throws soil; the dig (EndReason "Broke") bursts the echo into wisps, the
--     bell rings out (a Perfect dig bursts gold).
-- HudLines: what to do, the Perfect share for Gold, the Bell Pup bonus. ReducedMotion: no sway / bob / jolt (the arc and
-- the life ring stay: they are the mechanic). Everything lives in the trials FX folder and goes on Stop.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Halloween = RS:WaitForChild("Halloween")
local View = require(Halloween:WaitForChild("Seals1View"))
local Models = require(Halloween:WaitForChild("Models"):WaitForChild("Seals1"))

local P = { Ids = { "EchoDig" }, ScoreLabel = { "ECHOES", "ЭХО" } }

local L = View.L
local V3 = Vector3.new
local COL = Models.Colors
local KIND = "UyEcho"

local ctx: any = nil
local active: any = nil -- {RunId, Maid, Recs = {[part] = rec}, StopTargets, Pup, Life}

local function num(v: any, d: number?): number
	return tonumber(v) or d or 0
end

local function groundOf(part: BasePart): (Vector3, number)
	local g = part:GetAttribute("Ground")
	local ground = typeof(g) == "Vector3" and g or (part.Position - V3(0, 2.2, 0))
	return ground, num(part:GetAttribute("Facing"))
end

local function pivotOf(rec: any, ground: Vector3, facing: number, dy: number): CFrame
	return CFrame.new(ground + V3(0, dy, 0)) * CFrame.Angles(0, facing, 0)
end

-- bell parts keep their offset from the bell pivot (they sway on their own)
local function bellOffsets(rec: any)
	rec.BellRel = {}
	local pivot = rec.P.BellPivot
	for _, p in ipairs(rec.P.Bell) do
		rec.BellRel[p] = pivot:ToObjectSpace(p.CFrame)
	end
	rec.BellBase = rec.Model:GetPivot():ToObjectSpace(pivot)
end

local function clearTrail(rec: any)
	if rec.Trail then
		rec.Trail.Model:Destroy()
		rec.Trail = nil
	end
end

local function clearNext(rec: any)
	if rec.Next then
		rec.Next.Model:Destroy()
		rec.Next = nil
	end
end

local function build(part: BasePart)
	local a = active
	if not a then
		return
	end
	local ground, facing = groundOf(part)
	local model, pieces = Models.EchoMound(pivotOf(nil, ground, facing, 0))
	model.Parent = View.Folder(ctx)
	local rec: any = { Part = part, Model = model, P = pieces, Ground = ground, Facing = facing, Born = os.clock(), Rise = 0, Sway = math.random() * 6,
		Lit = -1, Flash = false }
	bellOffsets(rec)
	a.Recs[part] = rec
	-- rise out of the plaza
	model:PivotTo(pivotOf(rec, ground, facing, -2.6))
	View.FX(ctx, "Burst", ground + V3(0, .6, 0), { Color = COL.Soil:Lerp(COL.Bone, .3), Color2 = COL.Spirit, Count = 18, Speed = { 3, 7 },
		Size = { .4, .6, 0 }, Lifetime = { .5, 1 }, Acceleration = V3(0, -18, 0) })
	View.Audio(ctx, "SoulRise", ground, { Volume = .45, Pitch = 1.2 })
	View.Audio(ctx, "Toll", ground, { Volume = .25, Pitch = 1.5 })
	-- watch the server's jump telegraph and the move
	table.insert(rec, part:GetAttributeChangedSignal("Ground"):Connect(function()
		local g, f = groundOf(part)
		if (g - rec.Ground).Magnitude > .5 then
			rec.Move = { From = rec.Ground, To = g, Facing = f, At = os.clock() }
			rec.Ground, rec.Facing = g, f
			clearTrail(rec)
			View.Audio(ctx, "GhostWoo", g, { Volume = .35, Pitch = 1.3 })
		end
	end))
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
	clearTrail(rec)
	clearNext(rec)
	local m = rec.Model
	if reason == "Broke" then
		-- dug: the bell rings out, the echo bursts into wisps (gold for a Perfect dig)
		local perfect = rec.Perfect == true
		local pos = rec.Ground + V3(0, 2, 0)
		View.FX(ctx, "Burst", pos, { Color = perfect and COL.Gold or COL.Spirit, Color2 = COL.Moon, Count = perfect and 60 or 36, Speed = { 6, 14 },
			Size = { .5, .8, 0 }, Lifetime = { .6, 1.3 }, Acceleration = V3(0, 6, 0), Drag = 3 })
		View.FX(ctx, "Ring", rec.Ground + V3(0, .3, 0), perfect and COL.Gold or COL.Spirit, 7, .6)
		View.Audio(ctx, "SoulBurst", pos, { Volume = .55 })
		View.Audio(ctx, "Toll", pos, { Volume = .5, Pitch = perfect and 1.9 or 1.6 })
		if perfect then
			View.Audio(ctx, "Sparkle", pos, { Volume = .5 })
		end
		-- the spirit bell flies up while the mound sinks
		local t0 = os.clock()
		local conn: RBXScriptConnection? = nil
		conn = RunService.Heartbeat:Connect(function()
			local t = os.clock() - t0
			if not m.Parent or t > .7 then
				if conn then
					conn:Disconnect()
				end
				m:Destroy()
				return
			end
			local k = t / .7
			m:PivotTo(pivotOf(rec, rec.Ground, rec.Facing, -2.4 * k * k))
			View.SetTransparency(m, k)
		end)
		task.delay(1.2, function()
			if m.Parent then
				m:Destroy()
			end
		end)
	else
		View.Fade(m, .5, 1, true)
	end
end

-- one frame of one echo
local function step(rec: any, t: number, dt: number, reduced: boolean)
	local part = rec.Part
	local m = rec.Model
	if not m.Parent then
		return
	end
	local now = View.Now()
	-- the move (jump): sink at the old point, a soul orb along the arc, rise at the new one
	local dy = 0
	local mv = rec.Move
	if mv then
		local k = os.clock() - mv.At
		if k < .3 then
			dy = -2.6 * (k / .3)
			m:PivotTo(pivotOf(rec, mv.From, rec.Facing, dy))
		elseif k < .62 then
			if not mv.Orb then
				local orb = Models.Part(View.Folder(ctx), "JumpSoul", V3(1.1, 1.1, 1.1), CFrame.new(mv.From), COL.Spirit, Enum.Material.Neon,
					{ Shape = Enum.PartType.Ball, Transparency = .1 })
				mv.Orb = orb
				m:PivotTo(pivotOf(rec, mv.To, rec.Facing, -2.6))
			end
			local u = (k - .3) / .32
			local h = 5 + (mv.To - mv.From).Magnitude * .12
			mv.Orb.CFrame = CFrame.new(mv.From:Lerp(mv.To, u) + V3(0, 1.2 + math.sin(u * math.pi) * h, 0))
		elseif k < 1.1 then
			if mv.Orb then
				mv.Orb:Destroy()
				mv.Orb = nil
				View.FX(ctx, "Burst", mv.To + V3(0, .6, 0), { Color = COL.Spirit, Count = 16, Speed = { 2, 6 }, Size = { .35, .5, 0 }, Lifetime = { .4, .9 } })
			end
			dy = -2.6 * (1 - (k - .62) / .48)
			m:PivotTo(pivotOf(rec, mv.To, rec.Facing, dy))
		else
			if mv.Orb then
				mv.Orb:Destroy()
			end
			rec.Move = nil
			m:PivotTo(pivotOf(rec, mv.To, rec.Facing, 0))
		end
	elseif rec.Rise < 1 then
		rec.Rise = math.min(1, (os.clock() - rec.Born) / .55)
		local k = 1 - (1 - rec.Rise) ^ 3
		m:PivotTo(pivotOf(rec, rec.Ground, rec.Facing, -2.6 * (1 - k)))
	end
	-- the life ring (the echo's time on this point)
	local life = math.max(.1, num(part:GetAttribute("Life"), 4.5))
	local expire = num(part:GetAttribute("ExpireAt"), now + life)
	local frac = math.clamp((expire - now) / life, 0, 1)
	local jumping = typeof(part:GetAttribute("JumpTo")) == "Vector3"
	local n = #rec.P.Ring
	local lit = math.ceil(frac * n - 1e-6)
	local flash = jumping and (math.floor(t * 8) % 2 == 0)
	if lit ~= rec.Lit or flash ~= rec.Flash then
		rec.Lit, rec.Flash = lit, flash
		for i, seg in ipairs(rec.P.Ring) do
			local on = i <= lit
			seg.Color = jumping and (flash and COL.VioletHi or COL.Violet) or (frac < .3 and COL.Candle or COL.Moon)
			seg.Transparency = on and .08 or .82
		end
	end
	-- sway the spirit bell, breathe the shell
	if not mv then
		local pivot = m:GetPivot() * rec.BellBase
		local sway = reduced and 0 or math.sin(t * 2.1 + rec.Sway) * .16
		local bob = reduced and 0 or math.sin(t * 1.4 + rec.Sway) * .25
		local bell = pivot * CFrame.new(0, bob, 0) * CFrame.Angles(sway, 0, sway * .6)
		for p, rel in pairs(rec.BellRel) do
			p.CFrame = bell * rel
		end
		local jolt = rec.Jolt and os.clock() - rec.Jolt or 9
		if jolt < .25 and not reduced then
			local s = (1 - jolt / .25) * .35
			m:PivotTo(pivotOf(rec, rec.Ground, rec.Facing, 0) * CFrame.new(math.sin(jolt * 70) * s, 0, 0))
		end
	end
	rec.P.Shell.Transparency = .1 + (reduced and .05 or (.06 * (1 + math.sin(t * 3 + rec.Sway))))
	-- the telegraphed jump: arc + landing rune
	if jumping and not rec.Trail and not mv then
		local to = part:GetAttribute("JumpTo")
		local tm, tp = Models.JumpTrail(rec.Ground, to, { Count = View.Detail(14, 11, 8) })
		tm.Parent = View.Folder(ctx)
		rec.Trail = tp
		View.Audio(ctx, "GhostWoo", rec.Ground, { Volume = .3, Pitch = 1.5 })
	elseif not jumping and rec.Trail then
		clearTrail(rec)
	end
	if rec.Trail then
		local jumpAt = num(part:GetAttribute("JumpAt"), expire)
		local u = math.clamp(1 - (jumpAt - now) / 1.2, 0, 1)
		for i, orb in ipairs(rec.Trail.Orbs) do
			local k = num(orb:GetAttribute("K"))
			local head = (t * 1.6) % 1
			local glow = math.max(0, 1 - math.abs(k - head) * 6)
			orb.Transparency = math.clamp(.7 - u * .4 - glow * .5, 0, .95)
			orb.Size = V3(.5, .5, .5) * (1 + glow * .8)
		end
		local pulse = .3 + .3 * math.sin(t * 9)
		for _, seg in ipairs(rec.Trail.Land) do
			seg.Transparency = math.clamp(pulse - u * .2, 0, .9)
		end
	end
	-- H09: the next landing point
	local nextPos = part:GetAttribute("NextPos")
	if typeof(nextPos) == "Vector3" and not jumping then
		if not rec.Next or (rec.NextAt - nextPos).Magnitude > .5 then
			clearNext(rec)
			local nm, np = Models.NextMark(nextPos)
			nm.Parent = View.Folder(ctx)
			rec.Next, rec.NextAt = np, nextPos
		end
		local pulse = .35 + .25 * math.sin(t * 4)
		for _, p in ipairs(rec.Next.Ring) do
			p.Transparency = pulse
		end
	elseif rec.Next then
		clearNext(rec)
	end
end

function P.Start(c: any, run: any)
	ctx = c
	P.Stop(c, nil, "Restart")
	if type(run) ~= "table" then
		return
	end
	local maid = View.Maid()
	local data = type(run.Data) == "table" and run.Data or {}
	local a: any = { RunId = run.RunId, Maid = maid, Recs = {}, Pup = data.Pup == true, Life = num(data.Life, 4.5), Data = data }
	active = a
	a.StopTargets = View.Targets(KIND, run.RunId, build, onRemove)
	maid.Give(function()
		if a.StopTargets then
			a.StopTargets()
		end
	end)
	-- a swing on one of our echoes: jolt + soil; the local hitter's Perfect makes its burst gold
	local Bus = c and c.Bus
	if Bus then
		maid.Give(Bus.On("StrikeSwing", function(d)
			local rec = type(d) == "table" and a.Recs[d.Part]
			if rec then
				rec.Jolt = os.clock()
				rec.Perfect = d.Perfect == true
				View.FX(ctx, "Burst", rec.Ground + V3(0, .8, 0), { Color = COL.Soil:Lerp(COL.Bone, .3), Count = 10, Speed = { 3, 6 }, Size = { .3, .45, 0 },
					Lifetime = { .4, .8 }, Acceleration = V3(0, -20, 0) })
			end
		end))
	end
	local t = 0
	maid.Give(RunService.Heartbeat:Connect(function(dt)
		t += dt
		local reduced = View.Reduced()
		for _, rec in pairs(a.Recs) do
			if rec.Move or rec.Rise < 1 or View.Near(rec.Ground, 220) then
				local ok, err = pcall(step, rec, t, dt, reduced)
				if not ok and not a.Warned then
					a.Warned = true
					warn("Trials.Echo: " .. tostring(err))
				end
			end
		end
	end))
	View.Trials(c, "Banner", "ECHO DIG", "ЭХО-РАСКОПКИ", {
		Sub = { string.format("Dig %d haunted echoes before they jump away", num(run.Goal, 12)),
			string.format("Раскопай %d призрачных эхо, пока они не ускользнули", num(run.Goal, 12)) },
		Color = COL.Spirit, Seconds = 3.2 })
end

function P.Update(_c: any, run: any)
	local a = active
	if a and type(run) == "table" and run.RunId == a.RunId and type(run.Data) == "table" then
		a.Data = run.Data
		a.Pup = run.Data.Pup == true
		a.Life = num(run.Data.Life, a.Life)
	end
end

function P.Signal(_c: any, _kind: string, _data: any, _run: any) end

function P.Stop(_c: any, run: any, _result: any)
	local a = active
	if not a or (type(run) == "table" and run.RunId ~= nil and run.RunId ~= a.RunId) then
		return
	end
	active = nil
	a.Maid.Clean()
	for part, rec in pairs(a.Recs) do
		a.Recs[part] = nil
		for _, c in ipairs(rec) do
			c:Disconnect()
		end
		clearTrail(rec)
		clearNext(rec)
		if rec.Move and rec.Move.Orb then
			rec.Move.Orb:Destroy()
		end
		View.Fade(rec.Model, .4, 1, true)
	end
end

function P.HudLines(run: any): { string }?
	local a = active
	if not a then
		return nil
	end
	local data = type(run) == "table" and type(run.Data) == "table" and run.Data or a.Data or {}
	local lines = { L("Dig each echo before its ring runs out and it jumps!", "Раскопай эхо, пока не погасло кольцо и оно не прыгнуло!") }
	local hits, perfects = num(data.Hits), num(data.Perfects)
	if hits > 0 then
		table.insert(lines, string.format("%s %d / %d (%d%%)", L("Perfect digs:", "Идеальные удары:"), perfects, hits, math.floor(perfects / hits * 100 + .5)))
	else
		table.insert(lines, L("PERFECT digs count for Gold", "Для золота нужны ИДЕАЛЬНЫЕ удары"))
	end
	if a.Pup then
		table.insert(lines, string.format(L("Bell Pup: echoes linger %.1f s, the next jump glows gold", "Колокольчик: эхо живёт %.1f с, следующий прыжок светится"),
			a.Life))
	end
	return lines
end

-- tests / QA
function P.Active(): any
	return active
end

return P
