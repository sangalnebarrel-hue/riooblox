-- BELL SEAL V · CROOKED DOORS (ServerScriptService.Halloween.SealDoors, WP-J; docs/halloween2/DESIGN.md §8.4 item 5).
-- Crooked Row's door wall: four door prompts (Door_1..4). Each opening uses one of the day's door openings
-- (Chapter2Config.Doors.PerDay, +1 with all daily contracts claimed: ctx.UseDoor) and reveals what the server dealt
-- behind that door BEFORE the choice (Seals2Rules.NewDeal: i.i.d. Reward 40 / Challenge 30 / Mini boss 20 / Rare 10;
-- H13 Moth Hound in the yard team: 35% that a moth marks a reward door, sent when the player walks up to the wall).
--   Reward    a chest: Bell Shards 30-80 (DR "Door"), Lucky Dust, 15% Coffin Key, a small showcase-find chance.
--   Challenge Seals.RegisterTrial("DoorChallenge"): 25 s hazard dance in the Door Court (the door throws the player in;
--             fleeing the court or getting downed fails it).
--   MiniBoss  Seals.RegisterTrial("Doorkeeper"): THE DOORKEEPER steps out (Strike kind "UyDoorkeeper", Power HP by
--             fighters), telegraphed SLAM / SWEEP / RING / CHARGE (EventHP hazards); after a slam it is stuck: hits count x2.
--             Nearby eligible players join the fight (Seals party rules).
--   Rare      the hidden room behind the wall (teleport): three chests = a guaranteed showcase find, a Coffin Key and
--             Lucky Dust (+ the 0.5% HOLLOW KING roll); everything is granted at the opening, the chests reveal it; the
--             room sends the player back out in front of the door.
-- Seal V: every completed outcome while the seal is playable (date + Seal IV + offering) adds ctx.SealProgress(5, 1):
-- Reward / Rare count at once, a challenge / mini boss only when won; failed fights count nothing. Every 3 outcomes
-- clear the seal (first clear, then repeats) through Chapter2.GrantSeal; Gold = no counted fight of the cycle had the
-- opener downed (u.Seals["5"].GoldLost). Two concurrent fights never share hazards: each run gets its own EventHP zone
-- "Trial:<Id>:<RunId>" (run.Zone, so the Seals framework's down / bleed-out / wipe handling follows it).
-- Request: C2DoorState {} -> {Left, Max, Progress, Need, Playable, Cleared, Hint?}. Signal C2Door {Kind = "State" | "Hint"
-- | "Open" | "Swing" | "Rare" | "Chest" | "RareEnd", ...}. Player attributes UyDoorsLeft, UyDoorsMax, UySealVProgress,
-- UyRareRoom (door number while in the hidden room, else 0).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Base = require(Halloween:WaitForChild("Chapter2Config"))
local Rules = require(Halloween:WaitForChild("Chapter2Rules"))
local Cfg = require(Halloween:WaitForChild("Seals2Config"))
local SR = require(Halloween:WaitForChild("Seals2Rules"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))

local D = {}
D.Config = Cfg
D.Rules = SR

local DC = Cfg.Doors
local SEAL = DC.CountsFor
local NEED = Base.Seals[SEAL].Activity.Outcomes or Base.Seals[SEAL].Trial.Goal or 3
local CLOSED = "Chapter II is closed"

local core: any = nil
local modules: any = nil
local ram: { [Player]: any } = {}
local pending: { [Player]: any } = {} -- door fights waiting for Seals.Start (CanStart only accepts these)
local runsById: { [number]: any } = {}
local slotsUsed: { [number]: number } = {} -- Doorkeeper slot -> run id
local rng = Random.new()

-- overridable (tests drive the module with fake players and a manual clock)
D.Now = function(): number
	return workspace:GetServerTimeNow()
end
D.Clock = function(): number
	return os.clock()
end
D.Roll = function(): number
	return rng:NextNumber()
end
D.Spawn = function(fn: (...any) -> (), ...: any)
	task.spawn(fn, ...)
end
D.Delay = function(seconds: number, fn: (...any) -> (), ...: any)
	task.delay(seconds, fn, ...)
end
D.Wait = function(seconds: number)
	task.wait(seconds)
end

local function C2(): any
	return modules and modules.Chapter2
end
local function UY(): any
	return modules and modules.Underyard
end
local function SealsM(): any
	return modules and modules.Seals
end
local function HP(): any
	return modules and modules.EventHP
end
local function StrikeM(): any
	return modules and modules.Strike
end

local function stateOf(player: Player): any
	local st = ram[player]
	if not st then
		st = { LastAction = -1e9, Busy = false, Near = false, Synced = false }
		ram[player] = st
	end
	return st
end
D.StateOf = stateOf

local function toast(player: Player, text: string)
	local c2 = C2()
	if c2 then
		c2.Toast(player, text)
	end
end

local function signal(player: Player, data: any)
	if core then
		core.Signal(player, "C2Door", data)
	end
end

local function anchorPos(name: string): Vector3?
	local c2 = C2()
	if c2 and c2.AnchorPos then
		return c2.AnchorPos(name)
	end
	return Layout.Anchor(name)
end

local function rootPos(player: Player): Vector3?
	local root = core and core.Root(player)
	return root and root.Position or nil
end

local function call(m: any, name: string, ...: any): (boolean, any, any)
	local fn = m and m[name]
	if type(fn) ~= "function" then
		return false, nil, nil
	end
	local ok, a, b = pcall(fn, ...)
	if not ok then
		warn("SealDoors: " .. name .. " failed: " .. tostring(a))
		return false, nil, nil
	end
	return true, a, b
end

local function wallCentre(): Vector3
	local a, b = Layout.Crooked.Doors[1], Layout.Crooked.Doors[#Layout.Crooked.Doors]
	return (a + b) / 2
end

local function courtCentre(): Vector3
	return anchorPos(DC.Challenge.Court) or Layout.Crooked.Court.Centre
end

local function compact(rows: { any }?): { any }
	local out = {}
	for _, r in ipairs(rows or {}) do
		local conv = nil
		if type(r.Conversion) == "table" then
			conv = {}
			for _, c in ipairs(r.Conversion) do
				table.insert(conv, { Kind = c.Kind, Amount = c.Amount })
			end
		end
		table.insert(out, { Kind = r.Kind, Id = r.Id, Amount = r.Amount, Rank = r.Rank, Converted = r.Converted, Reason = r.Reason,
			Conversion = conv })
	end
	return out
end
D.Compact = compact

local function dogsOf(rows: { any }): { string }
	local out = {}
	for _, r in ipairs(rows) do
		if r.Kind == "Dog" and type(r.Id) == "string" and not table.find(out, r.Id) then
			table.insert(out, r.Id)
		end
	end
	return out
end

---------------------------------------------------------------------------------------------------------------------
-- Deals (what waits behind the four doors for a player's next opening) and the H13 moth hint
---------------------------------------------------------------------------------------------------------------------
function D.Deal(player: Player): any
	local st = stateOf(player)
	if not st.Deal or D.Clock() - (st.DealAt or 0) > DC.DealLife then
		local c2 = C2()
		local moth = c2 ~= nil and c2.HasTeamDog ~= nil and c2.HasTeamDog(player, "HW_MothHound") == true
		st.Deal = SR.NewDeal(D.Roll, Base, { Moth = moth, Count = DC.Count })
		st.DealAt = D.Clock()
		st.HintSent = false
	end
	return st.Deal
end

-- doors left today / the daily maximum, from the player's last committed Chapter II view
local function doorsOf(player: Player): (number, number)
	local c2 = C2()
	local view = c2 and c2.ViewOf and c2.ViewOf(player)
	local daily = view and view.Daily
	if type(daily) == "table" then
		local today = Rules.Day(os.time())
		local max = tonumber(daily.DoorsMax) or Base.Doors.PerDay
		local used = daily.Day == today and (tonumber(daily.Doors) or 0) or 0
		return math.max(0, max - used), max
	end
	return Base.Doors.PerDay, Base.Doors.PerDay
end

local function sealRow(player: Player): any
	local c2 = C2()
	local view = c2 and c2.ViewOf and c2.ViewOf(player)
	return view and view.Seals and view.Seals[SEAL] or nil
end

local function stateData(player: Player): any
	local st = stateOf(player)
	local left, max = doorsOf(player)
	local row = sealRow(player)
	local data = { Kind = "State", Left = left, Max = max, Progress = st.Progress or 0, Need = NEED,
		Playable = row ~= nil and row.Playable == true, Cleared = row ~= nil and row.Cleared == true }
	if left > 0 and st.Deal and st.Deal.Hint then
		data.Hint = st.Deal.Hint
	end
	return data
end

local function syncAttrs(player: Player)
	if not player.Parent then
		return
	end
	local st = stateOf(player)
	local left, max = doorsOf(player)
	local function set(k: string, v: any)
		if player:GetAttribute(k) ~= v then
			player:SetAttribute(k, v)
		end
	end
	set("UyDoorsLeft", left)
	set("UyDoorsMax", max)
	set("UySealVProgress", st.Progress or 0)
	set("UyRareRoom", st.Rare and st.Rare.Door or 0)
end
D.SyncAttrs = syncAttrs

---------------------------------------------------------------------------------------------------------------------
-- Seal V progress (inside a Chapter II transaction) and the clear
---------------------------------------------------------------------------------------------------------------------
-- -> counted, progress, due (seal clears now owed), goldOk
local function progressIn(u: any, ctx: any, now: number, downed: boolean): (boolean, number, number, boolean)
	local c2 = C2()
	local s = u.Seals[tostring(SEAL)]
	local ok = Rules.SealPlayable(u, SEAL, now, Base, c2 and c2.PhaseOverride and c2.PhaseOverride() or nil)
	if not ok then
		return false, s.Progress or 0, 0, false
	end
	if downed then
		s.GoldLost = true
	end
	local before = s.Progress or 0
	local total = ctx.SealProgress(SEAL, 1)
	local _, due = SR.SealStep(before, total - before, NEED)
	local goldOk = s.GoldLost ~= true
	if due > 0 then
		s.GoldLost = nil -- the next cycle starts clean
	end
	return true, total, due, goldOk
end
D.ProgressIn = progressIn

-- Chapter2.GrantSeal (first clear, then repeats; Gold the first time) + the trial hook. A busy profile gets a retry.
local function grantSeal(player: Player, progress: number, goldOk: boolean)
	local c2 = C2()
	if not c2 then
		return
	end
	local ok, err = c2.GrantSeal(player, SEAL, { Gold = goldOk, Score = progress })
	if not ok then
		warn("SealDoors: GrantSeal failed for " .. player.Name .. ": " .. tostring(err))
		D.Wait(2)
		if not player.Parent then
			return
		end
		ok = c2.GrantSeal(player, SEAL, { Gold = goldOk, Score = progress })
	end
	if ok then
		c2.TrialCleared(player, "CrookedDoors", { Seal = SEAL, Gold = goldOk })
	end
end
D.GrantSeal = grantSeal

-- a challenge / mini boss outcome finished: count it for the opener (won fights only)
local function countFight(player: Player, outcome: string, won: boolean, downed: boolean)
	if not SR.Counts(outcome, won) or not player.Parent then
		return
	end
	local c2 = C2()
	if not c2 then
		return
	end
	local ok, res = c2.Transact(player, "C2DoorFight", function(_p, u, ctx, now)
		local counted, progress, due, goldOk = progressIn(u, ctx, now, downed)
		return { Counted = counted, Progress = progress, Due = due, Gold = goldOk, Cleared = u.Seals[tostring(SEAL)].Cleared }
	end)
	if not ok or type(res) ~= "table" then
		return
	end
	local st = stateOf(player)
	st.Progress = res.Progress
	syncAttrs(player)
	signal(player, { Kind = "Outcome", Outcome = outcome, Won = won, Counted = res.Counted, Progress = res.Progress, Need = NEED })
	if (res.Due or 0) > 0 then
		grantSeal(player, res.Progress, res.Gold)
	end
end
D.CountFight = countFight

-- first time near the wall this session: read the persistent progress; a clear that was owed but never granted
-- (server stopped in between) is paid now
local function syncProgress(player: Player)
	local st = stateOf(player)
	if st.Synced or st.Syncing then
		return
	end
	local c2 = C2()
	if not c2 then
		return
	end
	st.Syncing = true
	local ok, res = c2.Transact(player, "C2DoorSync", function(_p, u)
		local s = u.Seals[tostring(SEAL)]
		return { Progress = s.Progress or 0, Cleared = s.Cleared == true, Offered = s.Offered == true, GoldLost = s.GoldLost == true }
	end, { Silent = true })
	st.Syncing = false
	if ok and type(res) == "table" then
		st.Synced = true
		st.Progress = res.Progress
		syncAttrs(player)
		if res.Offered and not res.Cleared and res.Progress >= NEED then
			grantSeal(player, res.Progress, not res.GoldLost)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Opening a door
---------------------------------------------------------------------------------------------------------------------
local function near(player: Player, pos: Vector3?, radius: number): boolean
	return pos ~= nil and core ~= nil and core.Near(player, pos, radius + Base.Proximity.Slack)
end

local function refundDoor(player: Player)
	local c2 = C2()
	if c2 then
		c2.Transact(player, "C2DoorRefund", function(_p, u)
			u.Daily.Doors = math.max(0, (u.Daily.Doors or 0) - 1)
			return {}
		end)
	end
end

local function swingFor(player: Player, door: number, outcome: string)
	local pos = anchorPos("Door_" .. door)
	if not pos or not core then
		return
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			local p = rootPos(other)
			if p and (p - pos).Magnitude <= DC.SwingRadius then
				signal(other, { Kind = "Swing", Door = door, UserId = player.UserId, Outcome = outcome })
			end
		end
	end
end

local enterRare -- forward

local function startFight(player: Player, trialId: string, door: number)
	local seals = SealsM()
	pending[player] = { Door = door, Trial = trialId, At = D.Clock() }
	local ok, err = false, "Something went wrong, try again"
	if seals and seals.Start then
		local okCall, a, b = pcall(seals.Start, player, trialId)
		if okCall then
			ok, err = a, b
		end
	end
	pending[player] = nil
	if not ok then
		refundDoor(player)
		toast(player, "The door slammed shut. Your opening was returned")
		if type(err) == "string" then
			warn("SealDoors: " .. trialId .. " did not start for " .. player.Name .. ": " .. err)
		end
		signal(player, { Kind = "Refund", Door = door })
		syncAttrs(player)
	end
end

function D.Open(player: Player, door: number): (boolean, string?)
	if not Shared.Chapter2Enabled() then
		return false, CLOSED
	end
	door = math.floor(tonumber(door) or 0)
	if door < 1 or door > DC.Count then
		return false, "Unknown door"
	end
	local c2, uy, seals, hp = C2(), UY(), SealsM(), HP()
	if not c2 or not uy then
		return false, CLOSED
	end
	local st = stateOf(player)
	if st.Busy or st.Rare then
		return false, "Please wait a moment"
	end
	if D.Clock() - st.LastAction < DC.Cooldown then
		return false, "Please wait a moment"
	end
	if not c2.Eligible(player) then
		return false, "Finish Chapter I first"
	end
	if seals and seals.RunOf and seals.RunOf(player) then
		return false, "Finish your trial first"
	end
	if hp and hp.InCombat and hp.InCombat(player) then
		return false, "Finish your fight first"
	end
	if not uy.InZone(player) or not uy.Unlocked(player, "CrookedRow") then
		return false, "This district is still sealed"
	end
	if not near(player, anchorPos("Door_" .. door), DC.OpenRadius) then
		return false, "Walk up to the door"
	end
	st.Busy, st.LastAction = true, D.Clock()
	local deal = D.Deal(player)
	local outcome = deal.Doors[door] or "Reward"
	-- every random part is rolled before the write (dog rows must be declared to the transaction)
	local rows, rare = {}, nil
	if outcome == "Reward" then
		rows = SR.RewardChest(D.Roll, Base)
	elseif outcome == "Rare" then
		rare = SR.RareRoom(D.Roll, Base)
		rows = rare.Rows
	end
	local okCall, ok, res = pcall(c2.Transact, player, "C2Door", function(_p, u, ctx, now)
		local left = ctx.UseDoor()
		local out = { Door = door, Outcome = outcome, Left = left, Rewards = {}, Counted = false, Due = 0, Gold = false }
		for _, row in ipairs(rows) do
			table.insert(out.Rewards, ctx.C2Reward(row))
		end
		if SR.Counts(outcome, false) then
			out.Counted, out.Progress, out.Due, out.Gold = progressIn(u, ctx, now, false)
		else
			out.Progress = u.Seals[tostring(SEAL)].Progress or 0
		end
		out.Cleared = u.Seals[tostring(SEAL)].Cleared
		return out
	end, { Dogs = dogsOf(rows) })
	st.Busy = false
	if not okCall then
		warn("SealDoors: door transaction failed: " .. tostring(ok))
		return false, "Something went wrong, try again"
	end
	if not ok or type(res) ~= "table" then
		return false, type(res) == "string" and res or "Something went wrong, try again"
	end
	st.Deal, st.HintSent = nil, false
	st.Progress = res.Progress
	st.Synced = true
	c2.Progress(player, "Door", 1)
	local left, max = doorsOf(player)
	left = math.min(left, res.Left or left)
	local granted = compact(res.Rewards)
	local data = { Kind = "Open", Door = door, Outcome = outcome, Left = left, Max = max, Progress = res.Progress, Need = NEED,
		Counted = res.Counted, Rewards = outcome ~= "Rare" and granted or nil }
	if rare then
		data.Chests = #rare.Chests
	end
	signal(player, data)
	swingFor(player, door, outcome)
	syncAttrs(player)
	if (res.Due or 0) > 0 then
		D.Spawn(grantSeal, player, res.Progress, res.Gold)
	end
	if outcome == "Challenge" then
		startFight(player, "DoorChallenge", door)
	elseif outcome == "MiniBoss" then
		startFight(player, "Doorkeeper", door)
	elseif outcome == "Rare" and rare then
		-- the granted rows in chest order (the transaction granted rare.Rows in the same order)
		local chests, k = {}, 0
		for i, list in ipairs(rare.Chests) do
			chests[i] = {}
			for _ = 1, #list do
				k += 1
				table.insert(chests[i], granted[k])
			end
		end
		enterRare(player, door, chests)
	end
	return true, outcome
end

---------------------------------------------------------------------------------------------------------------------
-- The hidden room
---------------------------------------------------------------------------------------------------------------------
local function returnCFrame(door: number): CFrame
	local pos = anchorPos("Door_" .. door) or Layout.Crooked.Doors[door]
	local p = Vector3.new(pos.X, 3.2, pos.Z + DC.Rare.ReturnAhead)
	return CFrame.lookAt(p, p + Vector3.new(0, 0, 1))
end

local function teleport(player: Player, cf: CFrame, opts: any?)
	local uy = UY()
	if uy and uy.Teleport then
		local ok, res = pcall(uy.Teleport, player, cf, opts or { NoStream = true })
		return ok and res ~= false
	end
	return false
end

-- is the character inside the hidden room's box? (a player who died there respawned elsewhere: never pull them back)
local function inRareRoom(player: Player): boolean
	local pos = rootPos(player)
	local rr = Layout.Crooked.RareRoom
	if not pos then
		return false
	end
	local d = pos - rr.Centre
	return math.abs(d.X) <= rr.Half.X + 3 and math.abs(d.Z) <= rr.Half.Z + 3 and d.Y > -6 and d.Y <= rr.Half.Y * 2 + 4
end
D.InRareRoom = inRareRoom

local function exitRare(player: Player, visit: any)
	local st = stateOf(player)
	if st.Rare ~= visit then
		return
	end
	st.Rare = nil
	syncAttrs(player)
	if player.Parent then
		signal(player, { Kind = "RareEnd", Door = visit.Door })
		if inRareRoom(player) then
			teleport(player, returnCFrame(visit.Door), { NoStream = true })
		end
	end
end
D.ExitRare = function(player: Player)
	local st = stateOf(player)
	if st.Rare then
		exitRare(player, st.Rare)
	end
end

enterRare = function(player: Player, door: number, chests: { any })
	local st = stateOf(player)
	local visit = { Door = door, Chests = chests, Opened = {}, Until = D.Clock() + DC.Rare.Visit }
	st.Rare = visit
	syncAttrs(player)
	signal(player, { Kind = "Rare", Door = door, Chests = #chests, Until = D.Now() + DC.Rare.Visit })
	local spawn = anchorPos(DC.Rare.Spawn) or Layout.Crooked.RareRoom.Spawn
	local look = Layout.Crooked.RareRoom.Centre
	D.Spawn(function()
		if not teleport(player, CFrame.lookAt(spawn + Vector3.new(0, 2.6, 0), Vector3.new(look.X, spawn.Y + 2.6, look.Z - 20)), {}) then
			-- no character to move: the rewards are already in the profile, close the visit
			exitRare(player, visit)
		end
	end)
	D.Delay(DC.Rare.Visit, function()
		exitRare(player, visit)
	end)
end

-- RareChest_i prompt
function D.OpenChest(player: Player, index: number): (boolean, string?)
	local st = stateOf(player)
	local visit = st.Rare
	if not visit then
		return false, "Nothing to open here"
	end
	index = math.floor(tonumber(index) or 0)
	if not visit.Chests[index] then
		return false, "Nothing to open here"
	end
	if visit.Opened[index] then
		return false, "This chest is already open"
	end
	visit.Opened[index] = true
	signal(player, { Kind = "Chest", Index = index, Rewards = visit.Chests[index] })
	local all = true
	for i in ipairs(visit.Chests) do
		if not visit.Opened[i] then
			all = false
		end
	end
	if all then
		D.Delay(DC.Rare.ExitDelay, function()
			exitRare(player, visit)
		end)
	end
	return true, nil
end

-- the RareChest_i anchors are this package's own (positions from Seals2Config.Doors.Rare.Chests)
local function chestAnchors()
	local uy = UY()
	local root = uy and uy.Root and uy.Root()
	if not root then
		return
	end
	local anchors = root:FindFirstChild("Anchors")
	if not anchors then
		anchors = Instance.new("Folder")
		anchors.Name = "Anchors"
		anchors.Parent = root
	end
	local c = Layout.Crooked.RareRoom.Centre
	for i, off in ipairs(DC.Rare.Chests) do
		local name = "RareChest_" .. i
		if not anchors:FindFirstChild(name) then
			local p = Instance.new("Part")
			p.Name = name
			p.Size = Vector3.new(1, 1, 1)
			p.Transparency = 1
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.CFrame = CFrame.new(c + Vector3.new(off[1], off[2], off[3]))
			p.Parent = anchors
		end
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Door fights: per-run EventHP zones
---------------------------------------------------------------------------------------------------------------------
local function members(run: any): string
	local ids = {}
	for _, pl in ipairs(run.Players) do
		table.insert(ids, tostring(pl.UserId))
	end
	return "," .. table.concat(ids, ",") .. ","
end
D.Members = members

local function ownZone(run: any, name: { string })
	local hp = HP()
	local zone = "Trial:" .. run.TrialId .. ":" .. run.Id
	local spawn = courtCentre()
	run.Zone = zone
	if hp then
		call(hp, "SetZone", zone, { Spawn = spawn, Name = name, Trial = run.TrialId })
		for _, pl in ipairs(run.Players) do
			call(hp, "Enter", pl, zone, { Spawn = spawn, Name = name, Trial = run.TrialId })
		end
	end
end

local function dropZone(run: any)
	local hp = HP()
	if not hp then
		return
	end
	call(hp, "CancelHazards", run.Zone)
	local zone = run.Zone
	D.Delay(8, function()
		local z = hp.Zones and hp.Zones[zone]
		if z and next(z.Members) == nil then
			hp.Zones[zone] = nil
		end
	end)
end

local function fighters(run: any): { Player }
	local hp = HP()
	local out = {}
	for _, pl in ipairs(run.Players) do
		if not hp or not hp.CanTarget or hp.CanTarget(pl) then
			table.insert(out, pl)
		end
	end
	return out
end

local function onStartCommon(run: any): any
	local pl = run.Leader
	local p = pending[pl]
	pending[pl] = nil
	run.Data.Opener = pl
	run.Data.Door = p and p.Door or 1
	runsById[run.Id] = run
	return p
end

local function onEndCommon(run: any, result: string)
	runsById[run.Id] = nil
	dropZone(run)
	local opener = run.Data.Opener
	if result == "Won" and opener and table.find(run.Players, opener) then
		local outcome = run.TrialId == "DoorChallenge" and "Challenge" or "MiniBoss"
		D.Spawn(countFight, opener, outcome, true, run.Downed[opener.UserId] == true)
	elseif opener and opener.Parent then
		signal(opener, { Kind = "Outcome", Outcome = run.TrialId == "DoorChallenge" and "Challenge" or "MiniBoss", Won = false,
			Counted = false, Progress = stateOf(opener).Progress or 0, Need = NEED })
	end
end

-- CHALLENGE -----------------------------------------------------------------------------------------------------------
local CH = DC.Challenge
local CHALLENGE_NAME = { "DOOR CHALLENGE", "ИСПЫТАНИЕ ДВЕРИ" }

local function challengeSeconds(): number
	return Base.Trials.Defs.DoorChallenge.TimeLimit or Base.Doors.Challenge.Seconds or 25
end

local function challengeStart(run: any)
	onStartCommon(run)
	run.Data.Rewards = SR.ChallengeRewards(D.Roll, Base)
	ownZone(run, CHALLENGE_NAME)
	local c = courtCentre()
	run.Data.NextWave = D.Clock() + CH.FirstWave
	run.Data.Out = {}
	run.Public = { Kind = "Challenge", Door = run.Data.Door, Center = c, Radius = CH.Radius, LeaveRadius = CH.LeaveRadius,
		Seconds = challengeSeconds(), FinaleAt = run.StartedAt + CH.Finale.At }
	-- the door throws the player into the court
	local pl = run.Leader
	local door = anchorPos("Door_" .. run.Data.Door) or c
	local at = c + Vector3.new(0, 3.2, -CH.Radius * .35)
	D.Spawn(teleport, pl, CFrame.lookAt(at, Vector3.new(door.X, at.Y, door.Z)), { NoStream = true })
	run.Data.GraceUntil = D.Clock() + 2
end

local function challengeTick(run: any, _dt: number)
	local clock = D.Clock()
	local seconds = challengeSeconds()
	local elapsed = D.Now() - run.StartedAt
	local c = courtCentre()
	-- fleeing the court fails the challenge
	if clock >= (run.Data.GraceUntil or 0) then
		for _, pl in ipairs(table.clone(run.Players)) do
			local p = rootPos(pl)
			if p and Vector3.new(p.X - c.X, 0, p.Z - c.Z).Magnitude > CH.LeaveRadius then
				run.Data.Out[pl.UserId] = run.Data.Out[pl.UserId] or clock
				if clock - run.Data.Out[pl.UserId] >= CH.LeaveGrace then
					local seals = SealsM()
					if seals then
						seals.Leave(pl, "LeftCourt")
					end
				end
			else
				run.Data.Out[pl.UserId] = nil
			end
		end
	end
	if run.State ~= "Running" or clock < run.Data.NextWave then
		return
	end
	local pl = run.Players[1]
	local pos = pl and rootPos(pl)
	if not pos then
		run.Data.NextWave = clock + .5
		return
	end
	local court = { Center = c, Radius = CH.Radius }
	local kind
	if elapsed >= CH.Finale.At then
		if run.Data.FinaleDone then
			run.Data.NextWave = math.huge
			return
		end
		run.Data.FinaleDone = true
		kind = "Finale"
	elseif elapsed + SR.Every(CH.Telegraph, elapsed / seconds) + .5 >= seconds then
		-- a wave whose impact would land after the time limit is not sent (the finale lingers to the end on purpose)
		run.Data.NextWave = math.huge
		return
	else
		kind = SR.ChallengeKind(run.Data.Prev, D.Roll)
	end
	local defs = SR.ChallengeWave(kind, court, pos, elapsed, CH, D.Roll, seconds)
	local hp = HP()
	if hp then
		call(hp, "HazardWave", run.Zone, defs)
	end
	run.Data.Prev = kind
	local seals = SealsM()
	if seals then
		seals.Signal(run, "DoorWave", { Wave = kind })
	end
	run.Data.NextWave = clock + SR.Every(CH.Every, elapsed / seconds)
end

local function challengeTimeUp(run: any)
	local seals = SealsM()
	local hp = HP()
	local alive = false
	for _, pl in ipairs(run.Players) do
		if not (hp and hp.IsDowned and hp.IsDowned(pl)) then
			alive = true
		end
	end
	if seals then
		if alive then
			seals.Win(run)
		else
			seals.Fail(run, "Time")
		end
	end
end

-- THE DOORKEEPER --------------------------------------------------------------------------------------------------------
local DK = DC.Doorkeeper

local function slotFor(run: any): (number, Vector3)
	local slot = 1
	for i in ipairs(DK.Slots) do
		if not slotsUsed[i] then
			slot = i
			break
		end
		slot = (run.Id % #DK.Slots) + 1
	end
	slotsUsed[slot] = run.Id
	local off = DK.Slots[slot]
	local c = courtCentre()
	return slot, Vector3.new(c.X + off[1], c.Y, c.Z + off[2])
end

local function keeperStart(run: any)
	onStartCommon(run)
	local n = #run.Players
	local slot, pos = slotFor(run)
	run.Data.Slot, run.Data.Pos = slot, pos
	run.Data.MaxHP = DK.HP + DK.HPPerFighter * math.max(0, n - 1)
	run.Data.RewardsBy = {}
	for _, pl in ipairs(run.Players) do
		run.Data.RewardsBy[pl.UserId] = SR.MiniBossRewards(D.Roll, Base)
	end
	ownZone(run, Base.Doors.MiniBoss.Name)
	run.Data.SpawnAt = D.Clock() + DK.Intro
	run.Data.NextAttack = run.Data.SpawnAt + 1.2
	run.Public = { Kind = "MiniBoss", Door = run.Data.Door, Keeper = pos, Slot = slot, ReadyAt = D.Now() + DK.Intro,
		HP = run.Data.MaxHP, MaxHP = run.Data.MaxHP, TargetId = 0, StaggerUntil = 0 }
end

local function keeperFace(run: any): CFrame
	local pos = run.Data.Pos
	local door = anchorPos("Door_" .. run.Data.Door) or (pos - Vector3.new(0, 0, 40))
	local look = Vector3.new(door.X, pos.Y, door.Z)
	if (look - pos).Magnitude < 1 then
		look = pos + Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(pos + Vector3.new(0, DK.Height, 0), look + Vector3.new(0, DK.Height, 0))
end

local function keeperTick(run: any, _dt: number)
	local clock = D.Clock()
	local strike = StrikeM()
	if not run.Data.Target and clock >= run.Data.SpawnAt and strike then
		local t = strike.Add({
			Kind = "UyDoorkeeper", CFrame = keeperFace(run), Size = Vector3.new(DK.Size[1], DK.Size[2], DK.Size[3]), Radius = 3.5,
			HP = run.Data.MaxHP, MaxHP = run.Data.MaxHP, Unit = 1, Color = Color3.fromRGB(168, 92, 255), Material = "Slate",
			Data = { RunId = run.Id }, Name = "THE DOORKEEPER", NameRU = "ПРИВРАТНИК", Panel = true,
			Attributes = { UyRunId = run.Id, UyMembers = members(run) },
		})
		run.Data.Target = t
		run.Public.TargetId = t.Id
		local seals = SealsM()
		if seals then
			seals.Signal(run, "DoorkeeperReady", { TargetId = t.Id })
		end
	end
	local t = run.Data.Target
	if not t or not t.Alive or clock < run.Data.NextAttack then
		return
	end
	local list = fighters(run)
	if #list == 0 then
		run.Data.NextAttack = clock + .5
		return
	end
	local victim = list[math.clamp(1 + math.floor(D.Roll() * #list), 1, #list)]
	local vpos = rootPos(victim)
	if not vpos then
		run.Data.NextAttack = clock + .5
		return
	end
	local kind = SR.AttackKind(DK, run.Data.PrevAttack, D.Roll)
	local second = nil
	if kind == "Slam" and #list >= (DK.Attacks.Slam.Second or 99) then
		for _, other in ipairs(list) do
			if other ~= victim then
				second = rootPos(other)
				break
			end
		end
	end
	local defs = SR.DoorkeeperAttack(kind, run.Data.Pos, vpos, DK, D.Roll, second)
	local hp = HP()
	if hp then
		call(hp, "HazardWave", run.Zone, defs)
	end
	run.Data.PrevAttack = kind
	local a = DK.Attacks[kind]
	local impact = D.Now() + .35 + (a and a.Telegraph or 1.3)
	if kind == "Slam" then
		run.Data.StaggerFrom, run.Data.StaggerTo = impact, impact + DK.Stagger
		run.Public.StaggerUntil = impact + DK.Stagger
	end
	local seals = SealsM()
	if seals then
		seals.Signal(run, "DoorkeeperAttack", { Attack = kind, ImpactAt = impact, Target = vpos, StaggerUntil = kind == "Slam" and impact + DK.Stagger or nil })
	end
	local frac = t.HP / math.max(1, t.MaxHP)
	run.Data.NextAttack = clock + SR.Every(DK.Every, 1 - frac) + (a and a.Telegraph or 1.3)
end

local function keeperEnd(run: any, result: string)
	local t = run.Data.Target
	local strike = StrikeM()
	if t and t.Alive and strike then
		strike.Remove(t, result == "Won" and "Broke" or "Fled")
	end
	if run.Data.Slot and slotsUsed[run.Data.Slot] == run.Id then
		slotsUsed[run.Data.Slot] = nil
	end
	onEndCommon(run, result)
end

-- Strike kind: only the members of that fight hit it; a slam leaves it stuck (x StaggerMult)
local function keeperRun(target: any): any
	local id = target and target.Data and target.Data.RunId
	return id and runsById[id] or nil
end

local function registerKinds()
	local strike = StrikeM()
	if not strike or not strike.Register then
		return
	end
	strike.Register("UyDoorkeeper", {
		Range = DK.Range, Verb = "STRIKE", Damage = "Power", Perfect = false, EventMult = "Apply", Activity = "Hit",
		CanHit = function(player: Player, target: any)
			local run = keeperRun(target)
			local seals = SealsM()
			if not run or run.State ~= "Running" or not seals or seals.RunOf(player) ~= run then
				return false, "HW:NOT_YOURS"
			end
			return true
		end,
		OnHit = function(player: Player, target: any, hit: any)
			local run = keeperRun(target)
			local c2, seals = C2(), SealsM()
			local perfect = hit.Quality == 2
			if c2 then
				c2.StreakHit(player, perfect)
			end
			if run and seals then
				seals.Hit(run, player, perfect)
			end
			local now = D.Now()
			if run and run.Data.StaggerFrom and now >= run.Data.StaggerFrom - .2 and now <= run.Data.StaggerTo then
				hit.Applied = (tonumber(hit.Applied) or 0) * DK.StaggerMult
				return { Weak = true, Stagger = true }
			end
			return nil
		end,
		OnBreak = function(_killer: Player?, target: any)
			local run = keeperRun(target)
			local seals = SealsM()
			if run and run.State == "Running" and seals then
				run.Public.HP = 0
				seals.Win(run)
			end
		end,
	})
end

---------------------------------------------------------------------------------------------------------------------
-- Approach scan: deal + moth hint + state when a player walks up to the wall
---------------------------------------------------------------------------------------------------------------------
local function approach()
	local uy = UY()
	local c2 = C2()
	if not uy or not c2 then
		return
	end
	local centre = wallCentre()
	for _, player in ipairs(uy.Players()) do
		local st = stateOf(player)
		local pos = rootPos(player)
		local inRange = pos ~= nil and uy.District(player) == "CrookedRow" and c2.Eligible(player)
			and Vector3.new(pos.X - centre.X, 0, pos.Z - centre.Z).Magnitude <= DC.ApproachRadius
		if inRange and not st.Near then
			st.Near = true
			D.Spawn(function()
				syncProgress(player)
				local left = doorsOf(player)
				if left > 0 then
					D.Deal(player)
				end
				local data = stateData(player)
				if data.Hint then
					stateOf(player).HintSent = true
				end
				signal(player, data)
				syncAttrs(player)
			end)
		elseif inRange and st.Deal and st.Deal.Hint and not st.HintSent then
			st.HintSent = true
			signal(player, { Kind = "Hint", Door = st.Deal.Hint })
		elseif not inRange and st.Near then
			st.Near = false
		end
	end
end
D.Approach = approach

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
function D.Start(c: any, m: any)
	core, modules = c, m
	core.OnRequest("C2DoorState", function(player)
		if not Shared.Chapter2Enabled() then
			return false, CLOSED
		end
		local c2 = C2()
		if not c2 or not c2.Eligible(player) then
			return false, "Finish Chapter I first"
		end
		local left = doorsOf(player)
		local uy = UY()
		if left > 0 and uy and uy.District(player) == "CrookedRow" then
			D.Deal(player)
		end
		syncAttrs(player)
		return true, stateData(player)
	end, { Cost = 1 })
	if not Shared.Chapter2Enabled() then
		return
	end
	local seals, uy = SealsM(), UY()
	registerKinds()
	if seals then
		seals.Register(SEAL, {
			-- Seal V is not a timed run: its "trial" is the doors themselves (progress across days)
			Prompt = false, StartAnchor = "DoorCourt", District = "CrookedRow",
			CanStart = function()
				return false, "Open the Crooked Doors in Crooked Row"
			end,
		})
		local function canFight(player: Player): (boolean, string?)
			if pending[player] then
				return true, nil
			end
			return false, "Open a Crooked Door to face it"
		end
		seals.RegisterTrial("DoorChallenge", {
			Name = CHALLENGE_NAME, District = "CrookedRow", StartAnchor = "", Combat = true, Exclusive = false, MaxParty = 1,
			Prompt = false, Spawn = courtCentre(), CanStart = canFight, OnStart = challengeStart, OnTick = challengeTick,
			OnTimeUp = challengeTimeUp, OnEnd = onEndCommon,
			Rewards = function(run: any)
				return run.Data.Rewards
			end,
			IsGold = function()
				return false
			end,
		})
		seals.RegisterTrial("Doorkeeper", {
			Name = Base.Doors.MiniBoss.Name, District = "CrookedRow", StartAnchor = "", Combat = true, Exclusive = false,
			Prompt = false, Spawn = courtCentre(), CanStart = canFight, OnStart = keeperStart, OnTick = keeperTick, OnEnd = keeperEnd,
			OnTimeUp = function(run: any)
				local s = SealsM()
				if s then
					s.Fail(run, "Time")
				end
			end,
			Rewards = function(run: any, player: Player)
				return run.Data.RewardsBy and run.Data.RewardsBy[player.UserId] or SR.MiniBossRewards(D.Roll, Base)
			end,
			IsGold = function()
				return false
			end,
		})
	else
		warn("SealDoors: Seals framework missing")
	end
	if uy and uy.Prompt then
		for i = 1, DC.Count do
			uy.Prompt("Door_" .. i, {
				Name = "UyDoorPrompt", ActionText = "OPEN", ActionTextRU = "ОТКРЫТЬ", ObjectText = "CROOKED DOOR " .. i,
				ObjectTextRU = "КРИВАЯ ДВЕРЬ " .. i, HoldDuration = DC.PromptHold, MaxActivationDistance = DC.PromptRange,
				Attributes = { UyDoor = i },
			}, function(player)
				local ok, err = D.Open(player, i)
				if not ok and type(err) == "string" then
					toast(player, err)
				end
			end)
		end
		chestAnchors()
		for i = 1, #DC.Rare.Chests do
			uy.Prompt("RareChest_" .. i, {
				Name = "UyRareChestPrompt", ActionText = "OPEN", ActionTextRU = "ОТКРЫТЬ", ObjectText = "TREASURE CHEST",
				ObjectTextRU = "СУНДУК С СОКРОВИЩАМИ", HoldDuration = .3, MaxActivationDistance = DC.Rare.ChestRange,
				Attributes = { UyRareChest = i },
			}, function(player)
				local ok, err = D.OpenChest(player, i)
				if not ok and type(err) == "string" then
					toast(player, err)
				end
			end)
		end
		uy.Prompt(DC.Rare.Spawn, {
			Name = "UyRareLeavePrompt", ActionText = "LEAVE", ActionTextRU = "УЙТИ", ObjectText = "THE HIDDEN ROOM",
			ObjectTextRU = "ТАЙНАЯ КОМНАТА", HoldDuration = .5, MaxActivationDistance = 8, Attributes = { UyRareLeave = true },
		}, function(player)
			D.ExitRare(player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player)
		ram[player] = nil
		pending[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(DC.ApproachRate)
			if Shared.Chapter2Enabled() then
				local ok, err = pcall(approach)
				if not ok then
					warn("SealDoors approach failed: " .. tostring(err))
				end
			end
		end
	end)
end

return D
