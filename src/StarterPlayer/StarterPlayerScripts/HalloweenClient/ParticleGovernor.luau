-- NIGHT OF THE BURIED MOON — client particle governor (StarterPlayerScripts.HalloweenClient.ParticleGovernor).
-- Enforces Config.Quality[Q].Particles (Shared.Budget("Particles")) as the cap on simultaneously running CONTINUOUS
-- ParticleEmitters of the event on this client (Enabled and Rate > 0; one-shot :Emit() bursts have Rate 0 and are free).
-- * Tracks the emitters under the event's client roots — FX.Folder(), Workspace.HalloweenLive and
--   Workspace.DOGROTS_District.38_DeadYard / 39_HalloweenLayer — with DescendantAdded / DescendantRemoving bookkeeping
--   (one GetDescendants per root when it (re)appears; StreamingEnabled: roots and their parts come and go).
-- * Every 0.5 s: ranks the running + governed emitters by distance from the camera (parent BasePart / Attachment world
--   position), keeps the nearest N running and suppresses the rest. Ranking: attribute HwParticlePriority = true (on the
--   emitter or its parent) is never suppressed, emitters within 25 studs always win, the ones kept last pass get a 15 %
--   distance bonus (no flip-flop at the edge of the budget).
-- * Lever: Enabled = false + attribute HwGoverned = true; only emitters the governor suppressed are ever re-enabled.
--   Owners stay in charge: while an emitter is governed its Enabled is watched — an owner switching it ON (or clearing
--   HwGoverned) takes it back (a candidate again on the next pass, which then comes early); the governor's own writes are
--   recognised by value (signals are deferred). Rate 0 while governed = idle but still ours (owners that only drive Rate
--   get it back). An owner's Enabled = false on an already governed emitter is not observable: switch it off with
--   Rate = 0 or clear HwGoverned as well. The 39_HalloweenLayer emitters are left alone while MainMapLayer hides it.
-- * Budget changes (WorldEventFX setting / Quality) apply on the next pass. Event off: nothing runs; Stop() hands every
--   suppressed emitter back (re-enabled, unless the event was switched off: then the owners' cleanup decides).
-- API: Start(ctx), Stop(), Pass() (one pass now; tests),
--      Stats() -> {Budget, Tracked, Demand, Running, Governed, Passes, Takeovers} (last pass + owner takeovers so far).
local RunService = game:GetService("RunService")

local M = {}
M.Interval = .5 -- seconds between passes
M.MinGap = .15 -- earliest early pass after an owner switched a governed emitter back on
M.Near = 25 -- emitters this close to the camera always win
M.Hysteresis = .85 -- distance factor for the emitters kept last pass

local MARK, PRIORITY = "HwGoverned", "HwParticlePriority"
local EMPTY = { Budget = 0, Tracked = 0, Demand = 0, Running = 0, Governed = 0, Passes = 0, Takeovers = 0 }

function M.Stats()
	return EMPTY
end
function M.Pass() end
function M.Stop() end

function M.Start(ctx)
	local Shared, FX = ctx.Shared, ctx.FX
	if not Shared.Enabled() or M.Started then
		return
	end
	M.Started = true
	local alive = true
	local recs = {} -- ParticleEmitter -> {E, Id, Root, Governed, Kept, Conn, Parent, Holder, Att}
	local roots = {} -- key -> {Key, Inst, Conns}
	local nextId = 0
	local dirty = false
	local stats = { Budget = 0, Tracked = 0, Demand = 0, Running = 0, Governed = 0, Passes = 0, Takeovers = 0 }
	local takeovers = 0 -- owners that switched a governed emitter back on

	-- hand a governed emitter back (restore = switch it on again: the owner's state when we took it)
	local function release(rec, restore: boolean)
		if not rec.Governed then
			return
		end
		rec.Governed = false
		if rec.Conn then
			rec.Conn:Disconnect()
			rec.Conn = nil
		end
		pcall(function()
			rec.E:SetAttribute(MARK, nil)
			if restore then
				rec.E.Enabled = true
			end
		end)
	end

	local function watch(rec)
		local e = rec.E
		-- our own write arrives here as Enabled == false (ignored); an owner switching it on takes it over
		rec.Conn = e:GetPropertyChangedSignal("Enabled"):Connect(function()
			if rec.Governed and e.Enabled then
				release(rec, false)
				takeovers += 1
				dirty = true
			end
		end)
	end

	local function suppress(rec)
		local ok = pcall(function()
			rec.E:SetAttribute(MARK, true)
			rec.E.Enabled = false
		end)
		if ok then
			rec.Governed = true
			watch(rec)
		end
	end

	local function track(d: Instance, r)
		if recs[d] or not d:IsDescendantOf(r.Inst) then
			return
		end
		nextId += 1
		local rec = { E = d, Id = nextId, Root = r, Governed = false, Kept = false }
		recs[d] = rec
		if d:GetAttribute(MARK) == true then -- left over from an earlier start: still ours
			rec.Governed = true
			watch(rec)
		end
	end

	local function untrack(d: Instance)
		local rec = recs[d]
		if rec then
			recs[d] = nil
			release(rec, true) -- leaving the event roots (or destroyed): back as the owner left it
		end
	end

	local function detach(key: string, restore: boolean)
		local r = roots[key]
		if not r then
			return
		end
		roots[key] = nil
		for _, c in ipairs(r.Conns) do
			c:Disconnect()
		end
		for e, rec in pairs(recs) do
			if rec.Root == r then
				recs[e] = nil
				release(rec, restore)
			end
		end
	end

	local function attach(key: string, inst: Instance)
		local r = { Key = key, Inst = inst, Conns = {} }
		roots[key] = r
		table.insert(r.Conns, inst.DescendantAdded:Connect(function(d)
			if alive and roots[key] == r and d.ClassName == "ParticleEmitter" then
				track(d, r)
			end
		end))
		table.insert(r.Conns, inst.DescendantRemoving:Connect(function(d)
			local rec = recs[d]
			if rec and rec.Root == r then
				untrack(d)
			end
		end))
		for _, d in ipairs(inst:GetDescendants()) do
			if d.ClassName == "ParticleEmitter" then
				track(d, r)
			end
		end
	end

	local ROOTS = {
		{ "FX", function()
			return FX.Folder()
		end },
		{ "Live", function()
			return workspace:FindFirstChild("HalloweenLive")
		end },
		{ "Yard", function()
			local district = workspace:FindFirstChild("DOGROTS_District")
			return district and district:FindFirstChild("38_DeadYard")
		end },
		{ "Layer", function()
			local district = workspace:FindFirstChild("DOGROTS_District")
			return district and district:FindFirstChild("39_HalloweenLayer")
		end },
	}
	local function resolveRoots()
		for _, row in ipairs(ROOTS) do
			local key = row[1]
			local ok, inst = pcall(row[2])
			inst = ok and inst or nil
			local r = roots[key]
			if r and (r.Inst ~= inst or not r.Inst.Parent) then
				detach(key, true)
				r = nil
			end
			if inst and not r then
				attach(key, inst)
			end
		end
	end

	-- world position of what the emitter emits from (nil: not under a BasePart / Attachment, emits nothing)
	local function posOf(rec): Vector3?
		local e = rec.E
		local p = e.Parent
		if p ~= rec.Parent then
			rec.Parent, rec.Holder, rec.Att = p, nil, nil
			if p and p:IsA("BasePart") then
				rec.Holder = p
			elseif p and p:IsA("Attachment") then
				rec.Att = p
				local h = p.Parent
				rec.Holder = (h and h:IsA("BasePart")) and h or nil
			end
		end
		if rec.Att then
			if rec.Holder then
				return (rec.Holder.CFrame * rec.Att.CFrame).Position
			end
			local ok, w = pcall(function()
				return rec.Att.WorldPosition
			end)
			return ok and w or nil
		elseif rec.Holder then
			return rec.Holder.CFrame.Position
		end
		return nil
	end

	local function priority(e: Instance): boolean
		if e:GetAttribute(PRIORITY) == true then
			return true
		end
		local p = e.Parent
		return p ~= nil and p:GetAttribute(PRIORITY) == true
	end

	local function pass()
		if not alive then
			return
		end
		dirty = false
		resolveRoots()
		local budget = math.max(0, math.floor(Shared.Budget("Particles") or 0))
		local cam = workspace.CurrentCamera
		local camPos = cam and cam.CFrame.Position or Vector3.zero
		local mml = ctx.Modules and ctx.Modules.MainMapLayer
		local layerHidden = type(mml) == "table" and type(mml.IsVisible) == "function" and mml.IsVisible() == false
		local cands = {}
		local tracked = 0
		for e, rec in pairs(recs) do
			if not e.Parent then
				recs[e] = nil -- gone without a DescendantRemoving we saw
				release(rec, false)
				continue
			end
			tracked += 1
			if rec.Governed and (e.Enabled or e:GetAttribute(MARK) ~= true) then
				release(rec, false) -- the owner switched it on (or took it back) behind our back: its state now
			end
			if layerHidden and rec.Root.Key == "Layer" then
				release(rec, false)
				rec.Kept = false
				continue
			end
			if e.Rate > 0 and (e.Enabled or rec.Governed) then
				local pos = posOf(rec)
				local d = pos and (pos - camPos).Magnitude or math.huge
				local prio = priority(e)
				local score
				if prio then
					score = -1e9 + d
				elseif d <= M.Near then
					score = -1e6 + d
				else
					score = rec.Kept and d * M.Hysteresis or d
				end
				table.insert(cands, { Rec = rec, Score = score, Prio = prio })
			else
				rec.Kept = false
			end
		end
		table.sort(cands, function(a, b)
			if a.Score ~= b.Score then
				return a.Score < b.Score
			end
			return a.Rec.Id < b.Rec.Id
		end)
		local running, governed = 0, 0
		for i, c in ipairs(cands) do
			local rec = c.Rec
			if i <= budget or c.Prio then
				rec.Kept = true
				running += 1
				if rec.Governed then
					release(rec, true)
				end
			else
				rec.Kept = false
				if not rec.Governed then
					suppress(rec)
				end
			end
		end
		for _, rec in pairs(recs) do
			if rec.Governed then
				governed += 1
			end
		end
		stats = { Budget = budget, Tracked = tracked, Demand = #cands, Running = running, Governed = governed, Passes = stats.Passes + 1,
			Takeovers = takeovers }
	end

	local conn
	local function cleanup(restore: boolean)
		if not alive then
			return
		end
		alive = false
		M.Started = false
		if conn then
			conn:Disconnect()
		end
		local keys = {}
		for key in pairs(roots) do
			table.insert(keys, key)
		end
		for _, key in ipairs(keys) do
			detach(key, restore)
		end
		for e, rec in pairs(recs) do
			recs[e] = nil
			release(rec, restore)
		end
	end
	M.Stop = function()
		cleanup(Shared.Enabled())
	end
	M.Pass = pass
	M.Stats = function()
		stats.Takeovers = takeovers
		return stats
	end

	local acc = M.Interval -- first pass on the first frame
	conn = RunService.Heartbeat:Connect(function(dt)
		if not alive then
			return
		end
		acc += dt
		if acc < M.Interval and not (dirty and acc >= M.MinGap) then
			return
		end
		acc = 0
		local ok, err = pcall(function()
			if not Shared.Enabled() then
				cleanup(false)
				return
			end
			pass()
		end)
		if not ok and not M.Warned then
			M.Warned = true
			warn("Halloween ParticleGovernor failed: " .. tostring(err))
		end
	end)
end

return M
