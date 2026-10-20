-- BELL SEAL III · MIRROR GRAVES (ServerScriptService.Halloween.SealMirror, WP-I; docs/halloween2/DESIGN.md §8.4.3).
-- A Mourning Marsh puzzle run by the Seals framework (start: the scrying basin PondConsult). Six headstones stand
-- around the mirror pond (MirrorGrave_1..6 anchors; hinge models MirrorGrave_i_Stone turned by the client presenter),
-- each rune faces one of four directions; the server prompt TURN (on MirrorGrave_i) turns a stone a quarter.
-- The pond (HalloweenClient.Trials.Mirror) shows the target arrangement MIRRORED left <-> right: the rune of grave i
-- floats at grave 7 - i's place, its facing flipped east <-> west (SealRules.Reflection). CONSULT THE POND (prompt on
-- PondConsult) checks the active graves on the server: right = the next round, wrong = -Activity.WrongPenalty seconds
-- of the time limit and a mistake (Gold = no wrong consults). 3 rounds of Activity.Rounds (4, 5, 6) active graves within
-- the time limit; the puzzles come from the run leader's daily seed (SealRules.MirrorSeed: the same three all UTC day).
-- Rewards per round: Chapter2.QueueShards(Activity.ObjectiveShards, "Objective") to every member.
-- Requests through C2Trial (the prompts call the same code): Turn {Grave}, Consult {}.
-- Public run data: {GoAt, ReadyAt, Round, Rounds, Active, Reflection = {{Grave, At, Dir}}, Current = {d1..d6},
-- Wrong, Penalty, Gold = {NoMistakes}}. Extra C2Trial kinds: Turn {Grave, Dir, UserId}, Round {Round, Cleared, Final?,
-- UserId}, Wrong {Wrong (graves still off), Penalty, UserId}.
-- Player messages go out as Signal C2TrialMsg {Text} (localized by HalloweenClient.Trials from Localization.Seals1).
-- Prompt placement: grave 1's headstone and the basin stand ~2-3.5 studs apart, so TURN sits on each grave's outer side
-- and CONSULT on the basin's pond side (Attachments, Activity.TurnOffset / ConsultOffset), with tight activation
-- distances and different keys (TURN E / ButtonX, CONSULT F / ButtonY); both carry UyTrialOnly (the client shows them
-- to Mirror Graves runners only).
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local C2Rules = require(Halloween:WaitForChild("Chapter2Rules"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))
local Rules = require(Halloween:WaitForChild("SealRules"))

local SEAL = 3
local Mirror = {}
Mirror.Seal = SEAL
Mirror.Act = Rules.Activity(SEAL)
Mirror.TrialId = Cfg.Seals[SEAL].Trial.Id
-- overridable (tests)
Mirror.Now = function(): number
	return workspace:GetServerTimeNow()
end
Mirror.Day = function(): number
	return C2Rules.Day(os.time())
end

local core: any = nil
local modules: any = nil
local made: { [string]: boolean } = {}

local function C2(): any
	return modules and modules.Chapter2
end
local function SealsMod(): any
	return modules and modules.Seals
end

local function message(player: Player, text: string)
	if core then
		core.Signal(player, "C2TrialMsg", { Text = text })
	end
end

local function anchor(name: string): Vector3?
	local c2 = C2()
	return (c2 and c2.AnchorPos and c2.AnchorPos(name)) or Layout.Anchor(name)
end

local function near(player: Player, name: string, radius: number): boolean
	local pos = anchor(name)
	return pos ~= nil and core ~= nil and core.Near(player, pos, radius + Cfg.Proximity.Slack)
end

local function runOf(player: Player): any
	local S = SealsMod()
	local run = S and S.RunOf(player)
	if run and run.TrialId == Mirror.TrialId and run.State == "Running" and run.Data.Mirror then
		return run
	end
	return nil
end

-- a round becomes current: its graves wake, every stone shuffles to the round's start
local function setRound(run: any, r: number, now: number)
	local st = run.Data.Mirror
	local round = st.Rounds[r]
	st.Round = r
	for i = 1, Rules.Graves do
		st.Current[i] = round.Start[i]
	end
	st.ReadyAt = math.max(st.GoAt, now + (r > 1 and Mirror.Act.RoundPause or 0))
	local pub = run.Public
	pub.Round, pub.Active, pub.Reflection, pub.ReadyAt = r, table.clone(round.Active), Rules.Reflection(round), st.ReadyAt
	pub.Current = table.clone(st.Current)
end

function Mirror.Turn(player: Player, grave: any): (boolean, any)
	local run = runOf(player)
	if not run then
		return false, "Begin the trial at the pond first"
	end
	local g = math.floor(tonumber(grave) or 0)
	if g < 1 or g > Rules.Graves then
		return false, "Unknown grave"
	end
	local st = run.Data.Mirror
	local now = Mirror.Now()
	if now < st.ReadyAt then
		return false, "Wait for the graves to settle"
	end
	if not table.find(st.Rounds[st.Round].Active, g) then
		return false, "This grave sleeps this round"
	end
	if not near(player, "MirrorGrave_" .. g, Mirror.Act.TurnRange) then
		return false, "Move closer to the grave"
	end
	if now - (st.TurnAt[g] or -1e9) < Mirror.Act.TurnCooldown then
		return false, "The stone is still turning"
	end
	st.TurnAt[g] = now
	st.Turns += 1
	st.Current[g] = (st.Current[g] + 1) % 4
	run.Public.Current = table.clone(st.Current)
	SealsMod().Signal(run, "Turn", { Grave = g, Dir = st.Current[g], UserId = player.UserId })
	return true, { Grave = g, Dir = st.Current[g] }
end

function Mirror.Consult(player: Player): (boolean, any)
	local run = runOf(player)
	if not run then
		return false, "Begin the trial at the pond first"
	end
	local st = run.Data.Mirror
	local now = Mirror.Now()
	if now < st.ReadyAt then
		return false, "Wait for the graves to settle"
	end
	if not near(player, "PondConsult", Mirror.Act.ConsultRange) then
		return false, "Stand at the scrying basin to consult the pond"
	end
	if now - st.ConsultAt < Mirror.Act.ConsultCooldown then
		return false, "The pond is still rippling"
	end
	st.ConsultAt = now
	local S = SealsMod()
	local ok, wrong = Rules.MirrorCheck(st.Rounds[st.Round], st.Current)
	if not ok then
		S.Mistake(run, 1)
		st.Wrong += 1
		local penalty = Mirror.Act.WrongPenalty
		if run.EndsAt > 0 then
			run.EndsAt = math.max(now + .25, run.EndsAt - penalty)
		end
		run.Public.Wrong = st.Wrong
		S.Signal(run, "Wrong", { Wrong = wrong, Penalty = penalty, UserId = player.UserId })
		return true, { Cleared = false, Wrong = wrong, Penalty = penalty }
	end
	-- the round is solved: shards to everyone, the next round (or the seal)
	local c2 = C2()
	if c2 then
		for _, pl in ipairs(run.Players) do
			c2.QueueShards(pl, Mirror.Act.ObjectiveShards, "Objective")
		end
	end
	local cleared = st.Round
	local final = cleared >= #st.Rounds
	if final then
		run.Public.Solved = true
		S.Signal(run, "Round", { Round = cleared, Cleared = cleared, Final = true, UserId = player.UserId })
	else
		setRound(run, cleared + 1, now)
		S.Signal(run, "Round", { Round = cleared + 1, Cleared = cleared, UserId = player.UserId })
	end
	S.AddScore(run, player, 1) -- WinAtGoal: the third round wins the run
	return true, { Cleared = true, Round = cleared, Final = final }
end

---------------------------------------------------------------------------------------------------------------------
-- Prompts: TURN on every grave, CONSULT THE POND on the basin (shown only to Mirror Graves runners by the client)
---------------------------------------------------------------------------------------------------------------------
local function keyCode(name: any, default: Enum.KeyCode): Enum.KeyCode
	local ok, k = pcall(function()
		return (Enum.KeyCode :: any)[name]
	end)
	if ok and typeof(k) == "EnumItem" then
		return k :: any
	end
	return default
end

-- a prompt on a part sits at the part's centre: move it onto an Attachment of its anchor part at `world`
local function placePrompt(prompt: ProximityPrompt, world: Vector3)
	local anchor = prompt.Parent
	if not (anchor and anchor:IsA("BasePart")) then
		return
	end
	local att = Instance.new("Attachment")
	att.Name = prompt.Name .. "Spot"
	att.CFrame = (anchor :: BasePart).CFrame:ToObjectSpace(CFrame.new(world))
	att.Parent = anchor
	prompt.Parent = att
end

-- TURN spot of grave g: on its outer side, Activity.TurnOffset studs from the stone, away from the pond
function Mirror.TurnSpot(g: number): Vector3?
	local a = Mirror.Act
	local pos = anchor("MirrorGrave_" .. g)
	local pond = anchor("MirrorPond") or Layout.Marsh.Pond.Centre
	if not pos then
		return nil
	end
	local out = Rules.Flat(pos - pond)
	out = out.Magnitude > 1e-3 and out.Unit or Vector3.new(0, 0, -1)
	return pos + out * (tonumber(a.TurnOffset) or 0)
end

-- CONSULT spot: the pond side of the scrying basin
function Mirror.ConsultSpot(): Vector3?
	local pos = anchor("PondConsult")
	local o = Mirror.Act.ConsultOffset or { 0, 0, 0 }
	return pos and pos + Vector3.new(tonumber(o[1]) or 0, tonumber(o[2]) or 0, tonumber(o[3]) or 0) or nil
end

function Mirror.EnsurePrompts()
	local UY = modules and modules.Underyard
	if not UY or type(UY.Prompt) ~= "function" then
		return
	end
	local a = Mirror.Act
	local tk, ck = a.TurnKeys or {}, a.ConsultKeys or {}
	for g = 1, Rules.Graves do
		local name = "MirrorGrave_" .. g
		if not made[name] then
			local prompt = UY.Prompt(name, {
				Name = "UyMirrorTurn", ActionText = "TURN", ActionTextRU = "ПОВЕРНУТЬ", ObjectText = "MIRROR GRAVE " .. g,
				ObjectTextRU = "ЗЕРКАЛЬНАЯ МОГИЛА " .. g, HoldDuration = 0, MaxActivationDistance = a.TurnPromptRange or a.TurnRange,
				KeyboardKeyCode = keyCode(tk[1], Enum.KeyCode.E), Attributes = { UyTrialOnly = Mirror.TrialId, MirrorGrave = g },
			}, function(player)
				local ok, err = Mirror.Turn(player, g)
				if not ok and type(err) == "string" then
					message(player, err)
				end
			end)
			if prompt then
				prompt.GamepadKeyCode = keyCode(tk[2], Enum.KeyCode.ButtonX)
				local spot = Mirror.TurnSpot(g)
				if spot then
					placePrompt(prompt, spot)
				end
			end
			made[name] = prompt ~= nil
		end
	end
	if not made.PondConsult then
		local prompt = UY.Prompt("PondConsult", {
			Name = "UyMirrorConsult", ActionText = "CONSULT THE POND", ActionTextRU = "СПРОСИТЬ ПРУД", ObjectText = "MIRROR POND",
			ObjectTextRU = "ЗЕРКАЛЬНЫЙ ПРУД", HoldDuration = .35, MaxActivationDistance = a.ConsultPromptRange or a.ConsultRange,
			KeyboardKeyCode = keyCode(ck[1], Enum.KeyCode.F), Attributes = { UyTrialOnly = Mirror.TrialId, MirrorConsult = true },
		}, function(player)
			local ok, err = Mirror.Consult(player)
			if not ok and type(err) == "string" then
				message(player, err)
			end
		end)
		if prompt then
			prompt.GamepadKeyCode = keyCode(ck[2], Enum.KeyCode.ButtonY)
			local spot = Mirror.ConsultSpot()
			if spot then
				placePrompt(prompt, spot)
			end
		end
		made.PondConsult = prompt ~= nil
	end
end

---------------------------------------------------------------------------------------------------------------------
-- The trial (Seals def)
---------------------------------------------------------------------------------------------------------------------
function Mirror.OnStart(run: any)
	Mirror.EnsurePrompts()
	local a = Mirror.Act
	local goAt = run.StartedAt + a.Countdown
	if run.EndsAt > 0 then
		run.EndsAt += a.Countdown
	end
	local seed = Rules.MirrorSeed(run.Leader and run.Leader.UserId or 0, Mirror.Day())
	local st = { GoAt = goAt, Seed = seed, Rounds = Rules.MirrorRounds(seed, a), Round = 1, Current = {}, TurnAt = {}, ConsultAt = -1e9,
		ReadyAt = goAt, Wrong = 0, Turns = 0 }
	run.Data.Mirror = st
	run.Public = { GoAt = goAt, Rounds = #st.Rounds, Wrong = 0, Penalty = a.WrongPenalty, Gold = { NoMistakes = true } }
	setRound(run, 1, goAt)
end

function Mirror.Start(c: any, m: any)
	core, modules = c, m
	Mirror.Act = Rules.Activity(SEAL)
	if not Shared.Chapter2Enabled() then
		return
	end
	local Seals = m and m.Seals
	if not Seals then
		warn("SealMirror: Seals missing; MIRROR GRAVES disabled")
		return
	end
	Seals.Register(SEAL, {
		StartAnchor = Mirror.Act.StartAnchor,
		WinAtGoal = true,
		Goal = #(Mirror.Act.Rounds or { 1, 2, 3 }),
		OnStart = Mirror.OnStart,
		Requests = {
			Turn = function(_run, player, args)
				return Mirror.Turn(player, args.Grave)
			end,
			Consult = function(_run, player)
				return Mirror.Consult(player)
			end,
		},
	})
	Mirror.EnsurePrompts()
end

return Mirror
