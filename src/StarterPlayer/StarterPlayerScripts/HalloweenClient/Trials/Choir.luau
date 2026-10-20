-- BELL SEAL VI · CHOIR HUNT · client presenter (StarterPlayerScripts.HalloweenClient.Trials.Choir, WP-J; DESIGN §8.4
-- item 6, §24.1 presenter contract, §24.2 "choir spirits (J)").
-- The server wanders seven invisible Strike targets (kind "UyChoir", attributes UyRunId / UyChoirNote / UyMembers) along
-- their loops; this presenter gives the hunters their spirits:
--   * a little singing ghost-dog in a choir robe (Models.Seals2.ChoirSpirit, tinted by its note) glides after each
--     target of YOUR run (smoothed, facing where it goes, bobbing; the note above its head turns slowly)
--   * the song: spirit i sings note Melody[i] of the Last Bell's song (Halloween Audio "ChoirNote", 3D at the spirit) at
--     the server-time schedule Seals2Rules.SingAt(i, run.StartedAt, SingEvery, n) — the same instant on every client of
--     the party; the spirit glows and a ring of its colour spreads while it sings. The song is the only hint.
--   * C2Trial "ChoirFlee" {TargetId, From, To, UserId}: startled — a shiver, an afterimage trail, "ONLY A PERFECT
--     CATCHES IT!" for the hitter. "ChoirCaught" {TargetId, Note, UserId, Caught}: the spirit sings its note one last
--     time, spirals up and fades in a burst of its colour. "ChoirMoth" {TargetId}: H13 moths fly from you to the nearest.
--   * win: the whole song, the seven notes in order. HudLines: caught n / 7 + the hint.
-- All models live in workspace.DOGROTS_Seals2FX and are destroyed on Stop (any result); ReducedMotion: no bob / spin.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Halloween = RS:WaitForChild("Halloween")
local View = require(Halloween:WaitForChild("Seals2View"))

local P = { Ids = { "ChoirHunt" } }

local player = Players.LocalPlayer
local L = View.L
local Cfg = View.Config
local CC = Cfg.Choir
local SR = View.Rules
local V3 = Vector3.new
local WHITE = Color3.new(1, 1, 1)
local SPIRIT = View.Colors.Spirit

local ctx: any = nil
local active: any = nil -- {RunId, Maid, Spirits = {[part] = rec}, StartedAt, Every, Count, Caught, Total, Flash}

local function audio(cue: string, where: any?, opts: any?)
	local a = ctx and ctx.Audio
	if a and a.Play then
		pcall(a.Play, cue, where, opts)
	end
end

local function fx(name: string, ...: any)
	local f = ctx and ctx.FX
	local fn = f and f[name]
	if type(fn) == "function" then
		pcall(fn, ...)
	end
end

local function num(v: any, d: number?): number
	return tonumber(v) or d or 0
end

local function rootPos(): Vector3?
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	return root and (root :: BasePart).Position or nil
end

local function noteColor(note: number): Color3
	local ok, c = pcall(View.Models.NoteColor, note)
	return ok and typeof(c) == "Color3" and c or SPIRIT
end

local function noteName(note: number): string
	return tostring(CC.NoteNames[note] or note)
end

local function mine(part: Instance, a: any): boolean
	if not part:IsA("BasePart") or part:GetAttribute("Kind") ~= "UyChoir" then
		return false
	end
	if a.RunId and part:GetAttribute("UyRunId") ~= nil and part:GetAttribute("UyRunId") ~= a.RunId then
		return false
	end
	local members = part:GetAttribute("UyMembers")
	return type(members) ~= "string" or members == "" or string.find(members, "," .. player.UserId .. ",", 1, true) ~= nil
end

---------------------------------------------------------------------------------------------------------------------
-- spirits
---------------------------------------------------------------------------------------------------------------------
local function setGlow(rec: any, k: number)
	for _, g in ipairs(rec.Glow) do
		g.Part.Transparency = g.Transparency * (1 - k * .8)
	end
	if rec.Light then
		rec.Light.Brightness = 1.1 + k * 2.4
		rec.Light.Range = 9 + k * 8
	end
end

local function singNow(a: any, rec: any, last: boolean?)
	local pos = rec.Pos
	-- a living spirit carries its note; the last one stays where it was caught (its part goes away)
	audio("ChoirNote", (not last and rec.Part.Parent) and rec.Part or pos, { Pitch = CC.Melody[rec.Note] or 1, Volume = last and 1 or .9 })
	rec.Sing = 1
	if not View.Reduced() then
		fx("Ring", pos - V3(0, 2.6, 0), rec.Color, 9, 1.1, { Thickness = .14 })
	end
end

local function dropSpirit(a: any, part: BasePart)
	local rec = a.Spirits[part]
	a.Spirits[part] = nil
	if rec then
		rec.Maid.Clean()
	end
end

-- caught: one last note, a spiral up into the dark, a burst of its colour
local function caughtFx(a: any, rec: any)
	if rec.Gone then
		return
	end
	rec.Gone = true
	singNow(a, rec, true)
	local base = rec.Pos
	fx("Burst", base, { Color = rec.Color, Color2 = WHITE, Count = 34, Speed = { 6, 14 } })
	fx("Light", base, rec.Color, 20, 3, 1.4)
	audio("Sparkle", base, { Volume = .8 })
	local model = rec.Model
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, { Part = d, T = d.Transparency })
		end
	end
	local yaw = rec.Yaw or 0
	View.Animate(1.6, function(k)
		local up = View.Ease(k) * 14
		local spin = k * 9
		local r = (1 - k) * 2.5
		local p = base + V3(math.cos(spin) * r, up, math.sin(spin) * r)
		model:PivotTo(CFrame.new(p) * CFrame.Angles(0, yaw + spin, 0) * rec.PivotRel)
		for _, e in ipairs(parts) do
			e.Part.Transparency = e.T + (1 - e.T) * k
		end
	end, function()
		rec.Maid.Clean()
	end)
end

local function addSpirit(a: any, part: Instance)
	if a ~= active or a.Spirits[part] or not mine(part, a) then
		return
	end
	local bp = part :: BasePart
	local note = math.floor(num(bp:GetAttribute("UyChoirNote"), 1))
	local okM, model = pcall(View.Models.ChoirSpirit, note, { Lite = View.Quality() == "Low" })
	if not okM or not model then
		return
	end
	local maid = View.Maid()
	model.Parent = View.Folder()
	maid.Give(model)
	local noteModel = model:FindFirstChild("Note")
	local rec: any = { Part = bp, Model = model, Maid = maid, Note = note, Color = noteColor(note), Pos = bp.Position,
		Yaw = nil, Phase = note * 1.3, Sing = 0, PivotRel = model:GetPivot(), NoteModel = noteModel,
		NoteRel = noteModel and (noteModel :: Model):GetPivot() or nil, Glow = {}, Light = nil, Flee = 0 }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Material == Enum.Material.ForceField then
			table.insert(rec.Glow, { Part = d, Transparency = d.Transparency })
		elseif d:IsA("PointLight") then
			rec.Light = d
		end
	end
	rec.NextSing = SR.SingAt(note, a.StartedAt, { SingEvery = a.Every }, a.Count, View.Shared.Now())
	a.Spirits[bp] = rec
	maid.Give(bp:GetAttributeChangedSignal("EndReason"):Connect(function()
		local why = bp:GetAttribute("EndReason")
		if why == "Broke" or why == "Sang" then
			caughtFx(a, rec)
		else
			dropSpirit(a, bp)
		end
	end))
	maid.Give(bp.AncestryChanged:Connect(function()
		if not bp:IsDescendantOf(workspace) and not rec.Gone then
			-- streamed out / removed without a catch
			task.defer(function()
				if not rec.Gone then
					dropSpirit(a, bp)
				end
			end)
		end
	end))
	-- appear: a puff of its colour
	fx("Burst", bp.Position, { Color = rec.Color, Color2 = WHITE, Count = 12, Speed = { 3, 7 } })
end

local function step(a: any, dt: number)
	local now = View.Shared.Now()
	local t = os.clock()
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position or V3()
	local reduced = View.Reduced()
	local follow = 1 - math.exp(-(Cfg.Client.SpiritLerp or 8) * dt)
	for part, rec in pairs(a.Spirits) do
		if not rec.Gone and part.Parent then
			local target = part.Position
			local prev = rec.Pos
			rec.Pos = (target - prev).Magnitude > 60 and target or prev:Lerp(target, follow)
			local look = part.CFrame.LookVector
			local move = rec.Pos - prev
			local dir = V3(move.X, 0, move.Z).Magnitude > .02 and V3(move.X, 0, move.Z) or V3(look.X, 0, look.Z)
			if dir.Magnitude > .01 then
				local want = math.atan2(-dir.X, -dir.Z)
				rec.Yaw = rec.Yaw or want
				local d = (want - rec.Yaw + math.pi) % (2 * math.pi) - math.pi
				rec.Yaw += d * math.min(1, dt * 5)
			end
			-- the song (server-time schedule shared by the party)
			if now >= rec.NextSing then
				rec.NextSing = SR.SingAt(rec.Note, a.StartedAt, { SingEvery = a.Every }, a.Count, now + .05)
				if (rec.Pos - camPos).Magnitude <= 170 then
					singNow(a, rec, false)
				end
			end
			rec.Sing = math.max(0, rec.Sing - dt * .7)
			rec.Flee = math.max(0, rec.Flee - dt)
			if (rec.Pos - camPos).Magnitude <= 260 then
				local bob = reduced and 0 or math.sin(t * 2.2 + rec.Phase) * .35
				local shiver = (rec.Flee > 0 and not reduced) and math.sin(t * 50) * .25 * rec.Flee or 0
				local lean = reduced and 0 or math.clamp(move.Magnitude / math.max(dt, 1e-3) / 40, 0, .35)
				local body = CFrame.new(rec.Pos + V3(shiver, bob, 0)) * CFrame.Angles(0, rec.Yaw or 0, 0) * CFrame.Angles(-lean, 0, 0)
				rec.Model:PivotTo(body * rec.PivotRel)
				if rec.NoteModel and rec.NoteRel then
					local spin = reduced and 0 or t * 1.4 + rec.Phase
					local hop = rec.Sing * .6
					local nr = rec.NoteRel
					local pivotAt = nr.Position
					rec.NoteModel:PivotTo(body * CFrame.new(pivotAt + V3(0, hop, 0)) * CFrame.Angles(0, spin, 0) * CFrame.new(-pivotAt) * nr)
				end
				setGlow(rec, rec.Sing)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- presenter
---------------------------------------------------------------------------------------------------------------------
local function cleanup()
	local a = active
	active = nil
	if not a then
		return
	end
	for part in pairs(a.Spirits) do
		dropSpirit(a, part)
	end
	a.Maid.Clean()
end

function P.Start(c: any, run: any)
	ctx = View.Ctx(c)
	cleanup()
	if type(run) ~= "table" then
		return
	end
	local data = type(run.Data) == "table" and run.Data or {}
	local maid = View.Maid()
	local a: any = { RunId = run.RunId, Maid = maid, Spirits = {}, StartedAt = num(run.StartedAt, View.Shared.Now()),
		Every = num(data.SingEvery, CC.SingEvery), Count = math.max(1, num(data.Count, #CC.Melody)), Caught = num(data.Caught, 0),
		Total = math.max(1, num(data.Count, num(run.Goal, 7))) }
	active = a
	View.Banner(ctx, "CHOIR HUNT", "ОХОТА НА ХОР", { Sub = { "Follow the song · only a PERFECT catches a spirit",
		"Иди на песню · поймать духа можно только ИДЕАЛЬНЫМ ударом" }, Color = SPIRIT, Seconds = 3.2 })
	for _, part in ipairs(CollectionService:GetTagged("HalloweenTarget")) do
		pcall(addSpirit, a, part)
	end
	maid.Give(CollectionService:GetInstanceAddedSignal("HalloweenTarget"):Connect(function(part)
		task.defer(function()
			if active == a then
				pcall(addSpirit, a, part)
			end
		end)
	end))
	maid.Give(RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, a, dt)
		if not ok and not a.Warned then
			a.Warned = true
			warn("Trials.Choir: " .. tostring(err))
		end
	end))
end

function P.Update(_c: any, run: any)
	local a = active
	if not a or type(run) ~= "table" or run.RunId ~= a.RunId then
		return
	end
	local data = type(run.Data) == "table" and run.Data or {}
	a.Caught = num(data.Caught, a.Caught)
end

local function recById(a: any, id: any): any
	id = tonumber(id)
	for part, rec in pairs(a.Spirits) do
		if part:GetAttribute("TargetId") == id then
			return rec
		end
	end
	return nil
end

function P.Signal(c: any, kind: string, data: any, _run: any)
	ctx = View.Ctx(c)
	local a = active
	if not a or type(data) ~= "table" then
		return
	end
	if kind == "ChoirFlee" then
		local rec = recById(a, data.TargetId)
		if rec then
			rec.Flee = .8
			audio("GhostWoo", rec.Pos, { Volume = .8, Pitch = 1.3 })
			if not View.Reduced() then
				fx("Burst", rec.Pos, { Color = rec.Color, Count = 10, Speed = { 2, 5 }, Lifetime = { .5, 1 } })
			end
			fx("Popup", rec.Pos + V3(0, 3, 0), "!", rec.Color, true)
		end
		if data.UserId == player.UserId then
			View.Toast(ctx, "It fled! Only a PERFECT catches a spirit", "Сбежал! Духа ловит только ИДЕАЛЬНЫЙ удар", "warning")
		end
	elseif kind == "ChoirCaught" then
		a.Caught = num(data.Caught, a.Caught + 1)
		local rec = recById(a, data.TargetId)
		if rec then
			caughtFx(a, rec)
			fx("Popup", rec.Pos + V3(0, 3.5, 0), L("CAUGHT", "ПОЙМАН") .. " " .. a.Caught .. " / " .. a.Total, rec.Color, true)
		end
		if data.UserId == player.UserId then
			local note = math.floor(num(data.Note, 1))
			View.Toast(ctx, "Caught: the note " .. noteName(note) .. " · " .. a.Caught .. " / " .. a.Total,
				"Пойман: нота " .. noteName(note) .. " · " .. a.Caught .. " / " .. a.Total, "success")
		end
	elseif kind == "ChoirMoth" then
		local rec = recById(a, data.TargetId)
		local from = rootPos()
		local to = rec and rec.Pos or nil
		if not to then
			local part = View.Target(data.TargetId)
			to = part and part.Position or nil
		end
		if from and to then
			pcall(View.MothSwarm, from, to, { Count = 6, Seconds = 2.2, StopShort = 6 })
			audio("Moths", from, { Volume = .5 })
		end
	end
end

function P.Stop(c: any, run: any, result: any)
	ctx = View.Ctx(c)
	local a = active
	if a and run and run.RunId and a.RunId ~= run.RunId then
		return
	end
	local won = result == "Won" or (type(result) == "table" and (result.Kind == "Won" or result.Result == "Won"))
	cleanup()
	if won then
		-- the Last Bell's song, all seven notes
		for i, pitch in ipairs(CC.Melody) do
			task.delay((i - 1) * .42, function()
				audio("ChoirNote", nil, { Pitch = pitch, Volume = .8 })
			end)
		end
	end
end

function P.HudLines(_run: any): { string }?
	local a = active
	if not a then
		return nil
	end
	return {
		L("Spirits caught", "Поймано духов") .. ": " .. a.Caught .. " / " .. a.Total,
		L("Listen for the song · only a PERFECT catches", "Слушай песню · ловит только ИДЕАЛЬНЫЙ удар"),
	}
end

function P.Active(): boolean
	return active ~= nil
end

return P
