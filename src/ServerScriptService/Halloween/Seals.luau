-- BELL SEAL trials framework (ServerScriptService.Halloween.Seals; docs/halloween2/DESIGN.md §8.4, §22.4).
-- The activities themselves are other modules (SealEcho, SealRun, SealMirror, SealMine, SealDoors, SealChoir, SealBell,
-- the onboarding trials): each registers a def and this module runs it.
--   Seals.Register(sealIndex, def) · Seals.RegisterTrial(id, def)
--   def = {Id, Name = {en, ru}, District ("*" = any unlocked district), StartAnchor ("SealAltar_n" default),
--          TimeLimit (0 = none), MaxParty (6), PartyRadius (30), Combat = bool (EventHP zone "Trial:<Id>"),
--          Spawn = Vector3 (edge respawn), Exclusive = bool (one run on the server; default = Combat),
--          OnStart(run), OnTick(run, dt), OnSample(run, player, position, serverTime) (4 Hz), OnLeave(run, player, reason),
--          OnEnd(run, result), OnTimeUp(run) (default: Total >= Goal wins), Goal(run) -> number | number,
--          IsGold(run, player) -> bool (default Seals.DefaultGold: Chapter2Config.Seals[i].Gold), CanStart(player) -> ok, err,
--          Rewards = rows | fn(run, player) -> rows (non-seal trials), TutorialEvent = "Toll"|..., WinAtGoal = bool,
--          Prompt = bool | {ActionText, ObjectText, ActionTextRU, ObjectTextRU} (a BEGIN TRIAL prompt on StartAnchor),
--          Requests = {[action] = fn(run, player, args) -> ok, res}}
--   run = {Id, TrialId, Seal?, Def, Players = {Player}, Leader, StartedAt, EndsAt (server time; 0 = no limit),
--          Data = {} (server only), Public = {} (sent to clients as Data), Score = {[userId] = n}, Total, Goal,
--          State = "Running"|"Won"|"Failed", Zone ("Trial:<Id>"), Downed = {[userId] = true}, BledOut = bool, Left = {}}
--   Seals.Start(player, trialIdOrSeal) -> ok, run|err · Seals.AddScore(run, player?, n) · Seals.Win(run, perPlayerInfo?)
--   Seals.Fail(run, reason) · Seals.RunOf(player) · Seals.Leave(player, reason) · Seals.Hit(run, player, perfect)
--   Seals.Mistake(run, n?) · Seals.BledOut(player, zoneId?) · Seals.DefaultGold(run, player) · Seals.Signal(run, kind, extra)
-- Requests: C2TrialStart {Seal | Trial}, C2TrialLeave {}, C2Trial {Action, ...} (routed to def.Requests[Action]).
-- Signal C2Trial {Kind = "Start"|"Score"|"Tick"|"Won"|"Failed"|"Left", TrialId, Seal, RunId, EndsAt, Players, Score,
-- Total, Goal, Data, Reason?, Gold?}. Player attribute UyTrial = "<TrialId>:<RunId>" ("" outside a trial).
-- Win -> Chapter2.GrantSeal (first clear / repeat / gold) or the trial's Rewards, then Chapter2.TrialCleared.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local Rules = require(Halloween:WaitForChild("Chapter2Rules"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))

local Seals = {}
local core: any = nil
local modules: any = nil
local defs: { [string]: any } = {}
local sealDefs: { [number]: string } = {}
local runs: { [number]: any } = {}
local runOf: { [Player]: any } = {}
local lastStart: { [Player]: number } = {}
local conns: { [Player]: RBXScriptConnection } = {}
local nextId = 0
local TC = Cfg.Trials

local function C2(): any
	return modules and modules.Chapter2
end
local function UY(): any
	return modules and modules.Underyard
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function toast(player: Player, text: string)
	local c2 = C2()
	if c2 then
		c2.Toast(player, text)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------------------------------------------------
local createPrompt

local function finishDef(def: any, base: any)
	def.Name = def.Name or base.Name or { def.Id, def.Id }
	def.District = def.District or base.District or "*"
	def.TimeLimit = def.TimeLimit or base.TimeLimit or 0
	def.MaxParty = def.MaxParty or base.MaxParty or TC.MaxParty
	def.PartyRadius = def.PartyRadius or base.PartyRadius or TC.PartyRadius
	if def.Combat == nil then
		def.Combat = base.Combat == true
	end
	if def.Exclusive == nil then
		def.Exclusive = def.Combat == true
	end
	if def.Goal == nil then
		def.Goal = base.Goal or 1
	end
	def.Zone = "Trial:" .. def.Id
	return def
end

function Seals.Register(sealIndex: number, def: { [string]: any })
	local seal = Cfg.Seals[sealIndex]
	assert(seal, "Seals.Register: unknown seal " .. tostring(sealIndex))
	def = table.clone(def or {})
	def.Seal = sealIndex
	def.Id = def.Id or seal.Trial.Id
	local act = seal.Activity or {}
	def.StartAnchor = def.StartAnchor or act.StartAnchor or ("SealAltar_" .. sealIndex)
	if def.Spawn == nil and act.Spawn then
		def.Spawn = Layout.Anchor(act.Spawn)
	end
	if def.Prompt == nil then
		def.Prompt = true
	end
	finishDef(def, { Name = seal.Title, District = seal.District, TimeLimit = seal.Trial.TimeLimit, Goal = seal.Trial.Goal,
		Combat = seal.Trial.Combat })
	defs[def.Id] = def
	sealDefs[sealIndex] = def.Id
	if core then
		createPrompt(def)
	end
	return def
end

function Seals.RegisterTrial(id: string, def: { [string]: any })
	assert(type(id) == "string", "Seals.RegisterTrial: id")
	local base = TC.Defs[id] or {}
	def = table.clone(def or {})
	def.Id = id
	def.StartAnchor = def.StartAnchor or base.StartAnchor
	finishDef(def, base)
	defs[id] = def
	if core then
		createPrompt(def)
	end
	return def
end

function Seals.Def(idOrSeal: any): any
	if type(idOrSeal) == "number" then
		local id = sealDefs[idOrSeal]
		return id and defs[id] or nil
	end
	if type(idOrSeal) == "string" then
		if defs[idOrSeal] then
			return defs[idOrSeal]
		end
		for i, seal in ipairs(Cfg.Seals) do
			if seal.Id == idOrSeal and sealDefs[i] then
				return defs[sealDefs[i]]
			end
		end
	end
	return nil
end

function Seals.RunOf(player: Player): any
	return runOf[player]
end

function Seals.Runs(): { any }
	local out = {}
	for _, run in pairs(runs) do
		table.insert(out, run)
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------------------------------------------------------
local function userIds(list: { Player }): { number }
	local out = {}
	for _, pl in ipairs(list) do
		table.insert(out, pl.UserId)
	end
	return out
end

local function scoreTable(run: any): { [string]: number }
	local out = {}
	for uid, n in pairs(run.Score) do
		out[tostring(uid)] = n
	end
	return out
end

function Seals.Signal(run: any, kind: string, extra: { [string]: any }?, only: Player?)
	if not core then
		return
	end
	local data = { Kind = kind, TrialId = run.TrialId, Seal = run.Seal, RunId = run.Id, EndsAt = run.EndsAt,
		StartedAt = run.StartedAt, Players = userIds(run.Players), Score = scoreTable(run), Total = run.Total, Goal = run.Goal,
		Data = run.Public, State = run.State }
	for k, v in pairs(extra or {}) do
		data[k] = v
	end
	if only then
		core.Signal(only, "C2Trial", data)
		return
	end
	for _, pl in ipairs(run.Players) do
		core.Signal(pl, "C2Trial", data)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Membership
---------------------------------------------------------------------------------------------------------------------
local function eventHP(method: string, player: Player, zoneId: string, opts: any?)
	local EventHP = modules and modules.EventHP
	local fn = EventHP and EventHP[method]
	if type(fn) == "function" then
		local ok, err = pcall(fn, player, zoneId, opts)
		if not ok then
			warn("Seals: EventHP." .. method .. " failed: " .. tostring(err))
		end
	end
end

local function call(run: any, name: string, ...: any): (boolean, any)
	local fn = run.Def[name]
	if type(fn) ~= "function" then
		return true, nil
	end
	local ok, res = pcall(fn, ...)
	if not ok then
		warn("Seals: " .. run.TrialId .. "." .. name .. " failed: " .. tostring(res))
	end
	return ok, res
end

local function detach(run: any, player: Player)
	runOf[player] = nil
	local i = table.find(run.Players, player)
	if i then
		table.remove(run.Players, i)
	end
	if conns[player] then
		conns[player]:Disconnect()
		conns[player] = nil
	end
	if player.Parent then
		player:SetAttribute("UyTrial", "")
	end
	if run.Def.Combat then
		eventHP("Leave", player, run.Zone)
	end
end

local finish

-- reasons: "Left" (button / disconnect), "LeftZone", "LeftDistrict", "Died", "BledOut", "Ascend", "Kicked"
function Seals.Leave(player: Player, reason: string?)
	local run = runOf[player]
	if not run then
		return
	end
	reason = reason or "Left"
	run.Left[player.UserId] = reason
	if reason == "BledOut" then
		run.BledOut = true
	end
	detach(run, player)
	call(run, "OnLeave", run, player, reason)
	if player.Parent then
		Seals.Signal(run, "Left", { Reason = reason, UserId = player.UserId }, player)
	end
	if run.State == "Running" then
		if #run.Players == 0 then
			finish(run, "Failed", reason == "Left" and "Abandoned" or reason)
		else
			Seals.Signal(run, "Score", { UserId = player.UserId, Reason = reason })
		end
	end
end

-- EventHP (or anyone) reports a bleed-out: that player fails the trial, the party continues
function Seals.BledOut(player: Player, zoneId: string?)
	local run = runOf[player]
	if run and (zoneId == nil or zoneId == run.Zone) then
		Seals.Leave(player, "BledOut")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Scoring helpers (standard fields read by the default Gold evaluator)
---------------------------------------------------------------------------------------------------------------------
function Seals.AddScore(run: any, player: Player?, n: number?)
	if not run or run.State ~= "Running" then
		return
	end
	n = tonumber(n) or 1
	run.Total += n
	if player then
		run.Score[player.UserId] = (run.Score[player.UserId] or 0) + n
	end
	Seals.Signal(run, "Score", { UserId = player and player.UserId or 0, Added = n })
	if run.Def.WinAtGoal and run.Total >= run.Goal then
		Seals.Win(run)
	end
end

-- a judged hit inside the run (Gold PerfectShare)
function Seals.Hit(run: any, player: Player?, perfect: boolean)
	if not run then
		return
	end
	run.Data.Hits = (run.Data.Hits or 0) + 1
	if perfect then
		run.Data.Perfects = (run.Data.Perfects or 0) + 1
	end
	if player then
		local per = run.Data.PlayerHits or {}
		run.Data.PlayerHits = per
		local row = per[player.UserId] or { Hits = 0, Perfects = 0 }
		per[player.UserId] = row
		row.Hits += 1
		if perfect then
			row.Perfects += 1
		end
	end
end

-- a wrong answer / penalty (Gold NoMistakes)
function Seals.Mistake(run: any, n: number?)
	if run then
		run.Data.Mistakes = (run.Data.Mistakes or 0) + (n or 1)
	end
end

function Seals.Elapsed(run: any): number
	return math.max(0, (run.EndedAt or serverNow()) - run.StartedAt)
end

-- Chapter2Config.Seals[i].Gold (or def.Gold): every listed criterion must hold
function Seals.DefaultGold(run: any, player: Player): boolean
	local g = run.Def.Gold or (run.Seal and Cfg.Seals[run.Seal].Gold)
	if type(g) ~= "table" then
		return false
	end
	if g.Total and run.Total < g.Total then
		return false
	end
	if g.Time and Seals.Elapsed(run) > g.Time then
		return false
	end
	if g.PerfectShare then
		local hits = run.Data.Hits or 0
		if hits <= 0 or (run.Data.Perfects or 0) / hits < g.PerfectShare then
			return false
		end
	end
	if g.NoMistakes and (run.Data.Mistakes or 0) > 0 then
		return false
	end
	if g.NoDowns and run.Downed[player.UserId] then
		return false
	end
	if g.NoBleedOut and run.BledOut then
		return false
	end
	return true
end

---------------------------------------------------------------------------------------------------------------------
-- End of a run
---------------------------------------------------------------------------------------------------------------------
local function rewardsFor(run: any, player: Player): { any }?
	local r = run.Def.Rewards
	if type(r) == "function" then
		local ok, rows = pcall(r, run, player)
		return ok and type(rows) == "table" and rows or nil
	end
	return type(r) == "table" and r or nil
end

local function grant(run: any, player: Player, gold: boolean, info: any)
	local c2 = C2()
	if not c2 then
		return
	end
	local uid = player.UserId
	local score = info and tonumber(info.Score) or run.Score[uid] or run.Total
	if run.Seal then
		local ok, err = c2.GrantSeal(player, run.Seal, { Gold = gold, Score = score, Time = Seals.Elapsed(run), RunId = run.Id })
		if not ok then
			warn("Seals: GrantSeal failed for " .. player.Name .. ": " .. tostring(err))
			-- a busy profile must not cost a seal: one retry after a moment
			task.wait(2)
			if player.Parent then
				c2.GrantSeal(player, run.Seal, { Gold = gold, Score = score, Time = Seals.Elapsed(run), RunId = run.Id })
			end
		end
	else
		local rows = rewardsFor(run, player)
		if rows and #rows > 0 then
			c2.Grant(player, "C2Trial", rows, { Message = "Trial cleared" })
		end
	end
	c2.TrialCleared(player, run.TrialId, { Seal = run.Seal, Gold = gold, RunId = run.Id })
	if run.Def.TutorialEvent then
		c2.TutorialEvent(player, run.Def.TutorialEvent)
	end
end

finish = function(run: any, result: string, reason: string?, perPlayerInfo: any?)
	if run.State ~= "Running" then
		return
	end
	run.State = result
	run.EndedAt = serverNow()
	local members = table.clone(run.Players)
	if result == "Won" then
		local golds = {}
		for _, pl in ipairs(members) do
			local gold = false
			if type(run.Def.IsGold) == "function" then
				local ok, res = pcall(run.Def.IsGold, run, pl)
				gold = ok and res == true
			else
				gold = Seals.DefaultGold(run, pl)
			end
			golds[tostring(pl.UserId)] = gold
			local info = perPlayerInfo and perPlayerInfo[pl.UserId] or nil
			task.spawn(grant, run, pl, gold, info)
		end
		Seals.Signal(run, "Won", { Gold = golds, Elapsed = Seals.Elapsed(run) })
	else
		Seals.Signal(run, "Failed", { Reason = reason or "Failed" })
	end
	call(run, "OnEnd", run, result)
	for _, pl in ipairs(members) do
		detach(run, pl)
	end
	task.delay(TC.EndHold, function()
		runs[run.Id] = nil
	end)
end

function Seals.Win(run: any, perPlayerInfo: any?)
	if run then
		finish(run, "Won", nil, perPlayerInfo)
	end
end

function Seals.Fail(run: any, reason: string?)
	if run then
		finish(run, "Failed", reason or "Failed")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
-- the player's seal state as Chapter2Rules expects it, from the RAM view of their last write
local function sealsOf(player: Player): any
	local c2 = C2()
	local view = c2 and c2.ViewOf(player)
	local out = {}
	for i, s in ipairs(view and view.Seals or {}) do
		out[tostring(i)] = { Offered = s.Offered == true, Cleared = s.Cleared == true }
	end
	return { Seals = out }
end

local function playable(player: Player, seal: number): (boolean, string?)
	local c2 = C2()
	return Rules.SealPlayable(sealsOf(player), seal, os.time(), Cfg, c2 and c2.PhaseOverride())
end

local function rootPos(player: Player): Vector3?
	local root = core.Root(player)
	return root and root.Position or nil
end

function Seals.Start(player: Player, trialIdOrSeal: any): (boolean, any)
	if not Shared.Chapter2Enabled() then
		return false, "Chapter II is closed"
	end
	local c2, uy = C2(), UY()
	if not c2 or not uy then
		return false, "Chapter II is closed"
	end
	local def = Seals.Def(trialIdOrSeal)
	if not def then
		if type(trialIdOrSeal) == "number" and Cfg.Seals[trialIdOrSeal] then
			return false, "This trial is not ready yet"
		end
		return false, "Unknown trial"
	end
	if runOf[player] then
		return false, "You are already in a trial"
	end
	if os.clock() - (lastStart[player] or -1e9) < TC.Cooldown then
		return false, "Please wait a moment"
	end
	if not c2.Eligible(player) then
		return false, "Finish Chapter I first"
	end
	if not uy.InZone(player) then
		return false, "Go down to the Underyard first"
	end
	if def.Seal then
		local ok, why = playable(player, def.Seal)
		if not ok then
			return false, why
		end
	end
	if def.District ~= "*" and not uy.Unlocked(player, def.District) then
		return false, "This district is still sealed"
	end
	local startPos = def.StartAnchor and c2.AnchorPos(def.StartAnchor)
	if startPos and not core.Near(player, startPos, TC.StartRadius + Cfg.Proximity.Slack) then
		return false, "Walk to the trial's start"
	end
	if def.Exclusive then
		for _, other in pairs(runs) do
			if other.TrialId == def.Id and other.State == "Running" then
				return false, "This trial is already running. Wait for it to end"
			end
		end
	end
	if type(def.CanStart) == "function" then
		local ok, res, err = pcall(def.CanStart, player)
		if not ok or res ~= true then
			return false, ok and (err or "You can't start this trial now") or "Something went wrong, try again"
		end
	end
	lastStart[player] = os.clock()
	-- party: eligible players around the leader who may play this trial too
	local party = { player }
	local leaderPos = rootPos(player)
	if leaderPos and def.MaxParty > 1 then
		for _, pl in ipairs(Players:GetPlayers()) do
			if #party >= def.MaxParty then
				break
			end
			if pl ~= player and not runOf[pl] and c2.Eligible(pl) and uy.InZone(pl) then
				local pos = rootPos(pl)
				local okSeal = not def.Seal or playable(pl, def.Seal)
				if pos and (pos - leaderPos).Magnitude <= def.PartyRadius and okSeal
					and (def.District == "*" or uy.Unlocked(pl, def.District)) then
					table.insert(party, pl)
				end
			end
		end
	end
	nextId += 1
	local now = serverNow()
	local run = {
		Id = nextId, TrialId = def.Id, Seal = def.Seal, Def = def, Players = party, Leader = player, StartedAt = now,
		EndsAt = def.TimeLimit > 0 and now + def.TimeLimit or 0, Data = {}, Public = {}, Score = {}, Total = 0, Goal = 1,
		State = "Running", Zone = def.Zone, Downed = {}, BledOut = false, Left = {}, Clock = os.clock(), Out = {},
		Weakened = {}, TickAt = 0, SampleAt = 0,
	}
	if type(def.Goal) == "function" then
		local ok, g = pcall(def.Goal, run)
		run.Goal = ok and tonumber(g) or 1
	else
		run.Goal = tonumber(def.Goal) or 1
	end
	-- districts the run may use: its own and the start anchor's (Bell Square altars of activities elsewhere)
	run.Districts = { [def.District] = true }
	if startPos then
		run.Districts[Layout.District(startPos) or "BellSquare"] = true
	end
	runs[run.Id] = run
	for _, pl in ipairs(party) do
		runOf[pl] = run
		pl:SetAttribute("UyTrial", def.Id .. ":" .. run.Id)
		local ch = pl.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum then
			conns[pl] = hum.Died:Connect(function()
				if runOf[pl] == run then
					Seals.Leave(pl, "Died")
				end
			end)
		end
		if def.Combat then
			eventHP("Enter", pl, run.Zone, { Spawn = def.Spawn, Trial = def.Id, RunId = run.Id })
		end
		run.Score[pl.UserId] = 0
		run.Weakened[pl.UserId] = tonumber(pl:GetAttribute("HwWeakenedUntil")) or 0
	end
	local ok = call(run, "OnStart", run)
	if not ok then
		finish(run, "Failed", "Error")
		return false, "Something went wrong, try again"
	end
	if run.State ~= "Running" then
		return false, "Trial over"
	end
	Seals.Signal(run, "Start")
	return true, run
end

---------------------------------------------------------------------------------------------------------------------
-- Run ticks (10 Hz max): time limit, membership checks at 4 Hz, combat state, Tick signal
---------------------------------------------------------------------------------------------------------------------
local function checkMember(run: any, player: Player, now: number)
	if not player.Parent then
		Seals.Leave(player, "Left")
		return
	end
	local uy = UY()
	if uy and not uy.InZone(player) then
		Seals.Leave(player, "LeftZone")
		return
	end
	local where = uy and uy.District(player) or nil
	if run.Def.District ~= "*" and where and not run.Districts[where] then
		run.Out[player.UserId] = run.Out[player.UserId] or os.clock()
		if os.clock() - run.Out[player.UserId] >= TC.LeaveGrace then
			Seals.Leave(player, "LeftDistrict")
			return
		end
	else
		run.Out[player.UserId] = nil
	end
	if run.Def.Combat then
		local uid = player.UserId
		local downed = player:GetAttribute("HwDowned") == true
		if downed and not run.Downed[uid] then
			run.Downed[uid] = true
			local c2 = C2()
			if c2 then
				c2.Progress(player, "Down", 1)
			end
		end
		-- bleed-out fallback when EventHP does not report it: a downed player got WEAKENED (bleed-out penalty)
		local weak = tonumber(player:GetAttribute("HwWeakenedUntil")) or 0
		if weak > (run.Weakened[uid] or 0) + .5 and run.Downed[uid] and not downed then
			run.Weakened[uid] = weak
			Seals.Leave(player, "BledOut")
			return
		end
		run.Weakened[uid] = math.max(run.Weakened[uid] or 0, weak)
	end
	if type(run.Def.OnSample) == "function" then
		local pos = rootPos(player)
		if pos then
			call(run, "OnSample", run, player, pos, now)
		end
	end
end

local function stepRun(run: any, dt: number)
	if run.State ~= "Running" then
		return
	end
	local now = serverNow()
	if run.EndsAt > 0 and now >= run.EndsAt then
		if type(run.Def.OnTimeUp) == "function" then
			call(run, "OnTimeUp", run)
			if run.State == "Running" then
				finish(run, "Failed", "Time")
			end
		elseif run.Total >= run.Goal then
			Seals.Win(run)
		else
			finish(run, "Failed", "Time")
		end
		return
	end
	call(run, "OnTick", run, dt)
	if run.State ~= "Running" then
		return
	end
	local clock = os.clock()
	if clock - run.SampleAt >= TC.SampleRate then
		run.SampleAt = clock
		for _, pl in ipairs(table.clone(run.Players)) do
			if run.State == "Running" and runOf[pl] == run then
				checkMember(run, pl, now)
			end
		end
		if run.State ~= "Running" then
			return
		end
		-- team wipe: everyone still in a combat trial is downed
		if run.Def.Combat and #run.Players > 0 then
			local all = true
			for _, pl in ipairs(run.Players) do
				if pl:GetAttribute("HwDowned") ~= true then
					all = false
					break
				end
			end
			if all then
				finish(run, "Failed", "Wipe")
				return
			end
		end
	end
	if clock - run.TickAt >= TC.SignalEvery then
		run.TickAt = clock
		Seals.Signal(run, "Tick")
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Prompts: the seven altars (offer / begin) + BEGIN TRIAL on activity start points
---------------------------------------------------------------------------------------------------------------------
local function openWindow(player: Player, seal: number?)
	local remote = RS:FindFirstChild("DogEconomyOpen")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, "Underyard", { Tab = "Seals", Seal = seal })
	end
end

local function beginFrom(player: Player, def: any)
	local ok, err = Seals.Start(player, def.Seal or def.Id)
	if not ok and type(err) == "string" then
		toast(player, err)
	end
end

local made: { [string]: boolean } = {}
createPrompt = function(def: any)
	local uy = UY()
	if not uy or not def.Prompt or not def.StartAnchor or made[def.StartAnchor] then
		return
	end
	if def.Seal and def.StartAnchor == "SealAltar_" .. def.Seal then
		return -- the altar prompt handles it
	end
	made[def.StartAnchor] = true
	local p = type(def.Prompt) == "table" and def.Prompt or {}
	local name = def.Name or { def.Id, def.Id }
	uy.Prompt(def.StartAnchor, {
		Name = "UyTrialPrompt", ActionText = p.ActionText or "BEGIN TRIAL", ActionTextRU = p.ActionTextRU or "НАЧАТЬ ИСПЫТАНИЕ",
		ObjectText = p.ObjectText or name[1], ObjectTextRU = p.ObjectTextRU or name[2], HoldDuration = p.HoldDuration or .4,
		MaxActivationDistance = p.MaxActivationDistance or 12, Attributes = { UyTrialId = def.Id },
	}, function(player)
		beginFrom(player, def)
	end)
end

local function altarPrompts()
	local uy = UY()
	if not uy then
		return
	end
	for i, seal in ipairs(Cfg.Seals) do
		local anchor = "SealAltar_" .. i
		made[anchor] = true
		uy.Prompt(anchor, {
			Name = "UySealPrompt", ActionText = "BELL SEAL " .. seal.Numeral, ActionTextRU = "ПЕЧАТЬ " .. seal.Numeral,
			ObjectText = seal.Name[1], ObjectTextRU = seal.Name[2], HoldDuration = .3, MaxActivationDistance = 12,
			Attributes = { UySeal = i },
		}, function(player)
			local s = sealsOf(player).Seals[tostring(i)]
			local def = Seals.Def(i)
			if not s or not s.Offered or not def then
				openWindow(player, i) -- offering (or the seal card when its trial is not here yet)
				return
			end
			if def.StartAnchor ~= anchor then
				toast(player, "Go to the trial's start point")
				openWindow(player, i)
				return
			end
			beginFrom(player, def)
		end)
	end
	for _, def in pairs(defs) do
		createPrompt(def)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
function Seals.Start_(c: any, m: any)
	core, modules = c, m
	local R = core.Rules
	local function closed(): (boolean, any)
		return false, "Chapter II is closed"
	end
	core.OnRequest("C2TrialStart", function(player, a)
		if not Shared.Chapter2Enabled() then
			return closed()
		end
		local which = a.Seal ~= nil and math.floor(tonumber(a.Seal) or 0) or a.Trial
		R.Check(type(which) == "number" or (type(which) == "string" and #which <= 40), "Unknown trial")
		local ok, res = Seals.Start(player, which)
		if not ok then
			return false, res
		end
		return true, { RunId = res.Id, TrialId = res.TrialId, EndsAt = res.EndsAt, Players = userIds(res.Players) }
	end, { Cost = 2 })
	core.OnRequest("C2TrialLeave", function(player)
		if runOf[player] then
			Seals.Leave(player, "Left")
		end
		return true, { Message = "" }
	end, { Cost = 1 })
	core.OnRequest("C2Trial", function(player, a)
		if not Shared.Chapter2Enabled() then
			return closed()
		end
		local run = runOf[player]
		R.Check(run ~= nil and run.State == "Running", "You are not in a trial")
		R.Check(type(a.Action) == "string", "Unknown trial action")
		local fn = run.Def.Requests and run.Def.Requests[a.Action]
		R.Check(type(fn) == "function", "Unknown trial action")
		return fn(run, player, a)
	end, { Cost = .5 })
	if not Shared.Chapter2Enabled() then
		return
	end
	local EventHP = modules.EventHP
	if EventHP and type(EventHP.OnBleedOut) == "function" then
		pcall(EventHP.OnBleedOut, function(player, zoneId)
			Seals.BledOut(player, zoneId)
		end)
	end
	altarPrompts()
	Players.PlayerRemoving:Connect(function(player)
		if runOf[player] then
			Seals.Leave(player, "Left")
		end
		lastStart[player] = nil
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(TC.TickRate)
			local now = os.clock()
			local dt = math.clamp(now - last, 0, 1)
			last = now
			for _, run in pairs(runs) do
				local ok, err = pcall(stepRun, run, dt)
				if not ok then
					warn("Seals: run tick failed: " .. tostring(err))
					pcall(finish, run, "Failed", "Error")
				end
			end
		end
	end)
end

-- One name, two contracts: HalloweenServer boots every module with Start(core, modules) (a table), while DESIGN §22.4
-- names the trial start Seals.Start(player, trialIdOrSeal) (a Player). The exported Start tells them apart by the
-- first argument; everything else is the Seals table itself.
local module = setmetatable({}, { __index = Seals })
module.Start = function(a: any, b: any): (boolean, any)
	if typeof(a) == "table" and type(a.Transact) == "function" then
		Seals.Start_(a, b)
		return true, nil
	end
	return Seals.Start(a, b)
end
return module
