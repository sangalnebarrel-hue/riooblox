-- THE BLACK COFFIN — server (ServerScriptService.Halloween.Coffin, WP-K4; docs/halloween2/DESIGN.md §9.1-§9.4, §24.4).
-- One opening = 150 Bell Shards + 1 Coffin Key at the coffin shrine in Bell Square (Chapter2Config.Coffin.Price).
-- * Request C2CoffinOpen {} (Halloween Request remote, Cost CoffinConfig.Request.Cost) and the shrine prompt "OPEN"
--   (UY.Prompt on 40_Underyard.Anchors.CoffinShrine) run the same Coffin.Open(player).
-- * Checks: Chapter II on, Chapter I latched (eligible), server proximity (CoffinConfig.Radius + Proximity.Slack),
--   per-player cooldown and one opening at a time; inside the write, before anything is spent: a key, the shards, and
--   room in the dog storage whenever a dog row could roll ("Make room in your dog storage first": a dog is never
--   converted to shards just because the kennel was full, §9.4).
-- * The roll happens on the server with a fresh Random (no client seed): Chapter2Rules.CoffinRoll over
--   Chapter2Config.Coffin.Table, forced to the showcase-find group on the onboarding's first coffin
--   (C2.ForceCoffinFind). Extra showcase-find rolls: H16 CROWN OF THE UNDERYARD (a stored crown roll, ctx.TakeCrownRoll)
--   and H12 COFFIN SENSE (Dogs.Defs.HW_CoffinPug.BonusFindChance while the pug is in the yard team). Every reward goes
--   through ctx.C2Reward inside ONE C2.Transact: duplicates / full item storage / not-yet-available content convert
--   (§9.4, H12's +25% included) and never fail; ctx.RecordCoffin keeps Coffins.Last and advances the "Coffin" contract
--   and the onboarding step (Chapter2Config.Tutorial "CoffinOpened").
-- * Signals (Core.Signal through C2.Signal), sent after the commit:
--     C2Coffin        {Id, UserId, Name, Rank, Rarity, Tier, Main, Rows, Converted, Duplicate, Forced, Keys, Shards,
--                      Seed, At, Preview?, Arrival?, Handoff?} to the opener (CoffinFX plays the show from it; At = server
--                      time of show second 0, so every viewer's show runs on the same clock)
--     C2CoffinNear    {Id, UserId, Name, Rank, Rarity, Main, Seed, At, Preview?, Arrival?, Handoff?} to other players near
--                      the shrine (the lighter show)
--     C2CoffinRefused {Text, Need?} to a player whose prompt opening was refused (CoffinFX localizes the toast)
--     C2Announce      {Kind = "HollowKing"|"Mythic", Name, UserId, DogId?, RewardKind, Id, Rank, RevealAt, Arrival?} to
--                      everyone (§24.4), sent when the show reveals the reward (CoffinConfig.Beats .Reveal / .Handoff),
--                      so no banner spoils the opener's lid
-- * THE HOLLOW KING (H16): at At + Beats(6).Handoff the server hands the show over to the Secret arrival:
--   ServerScriptService.SecretReveal.Show("HW_HollowKing", in front of the coffin's foot, facing the tower,
--   {Venue = "Coffin", By = name}) — the display king walks out of the coffin under the black moon on every nearby client
--   (SecretArrivals/Dogs/HW_HollowKing) and the Mega layer names the raiser world-wide. C2Coffin carries Arrival (the
--   arrival exists in this place) and Handoff (server time) so CoffinFX presents the coffin part only.
-- * Studio only (RunService:IsStudio() and GameId 0): request C2CoffinDebug {Rank, Kind?, Id?} sends a presentation-only
--   C2Coffin (Preview = true): nothing is granted, nothing is spent, nothing is announced.
-- Other modules reach this one lazily through `modules.Coffin`.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Cfg = require(Halloween:WaitForChild("Chapter2Config"))
local Rules = require(Halloween:WaitForChild("Chapter2Rules"))
local CC = require(Halloween:WaitForChild("CoffinConfig"))
local Layout = require(Halloween:WaitForChild("UnderyardLayout"))
local Resources = require(RS:WaitForChild("DogEconomy"):WaitForChild("Resources"))

local Coffin = {}
Coffin.Config = CC
Coffin.Closed = "Chapter II is closed"
Coffin.StorageFull = "Make room in your dog storage first"
-- scheduler of the timed hand-off / announcements (tests replace it)
Coffin.Delay = function(seconds: number, fn: () -> ())
	task.delay(seconds, fn)
end

local core: any = nil
local modules: any = nil
local lastOpen: { [Player]: number } = {}
local busy: { [Player]: boolean } = {}
local openId = 0

local function C2(): any
	return modules and modules.Chapter2
end

local function UY(): any
	return modules and modules.Underyard
end

local function now(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	return ok and type(t) == "number" and t or os.time()
end

---------------------------------------------------------------------------------------------------------------------
-- The roll (pure but for the Random it is given): the main row + the two bonus showcase-find rows, decided before the
-- write so the dog's supply key can be declared (Core.Transact opts.Dogs). Which bonus rows apply is decided inside.
---------------------------------------------------------------------------------------------------------------------
local function unit(rng: any): number
	if type(rng) == "function" then
		return rng()
	end
	return rng:NextNumber()
end

-- rng: a Random (or a () -> 0..1 function). forced: the onboarding's first coffin (showcase-find group only)
function Coffin.Plan(rng: any, forced: boolean?): any
	local main = Rules.CoffinRoll(rng, Cfg, nil, forced and { Group = "Find" } or nil)
	local crown = Rules.CoffinRoll(rng, Cfg, nil, { Group = CC.BonusGroup })
	crown.Bonus = "Crown"
	local pug = Rules.CoffinRoll(rng, Cfg, nil, { Group = CC.BonusGroup })
	pug.Bonus = "Pug"
	return { Main = main, Crown = crown, Pug = pug, PugRoll = unit(rng), Seed = 1 + math.floor(unit(rng) * 2147483645),
		Forced = forced == true }
end

-- a reward out of ctx.C2Reward reduced to what the client needs (signals stay small)
local function clean(out: any, bonus: string?): any
	local r: { [string]: any } = { Kind = out.Kind, Id = out.Id, Key = out.Key, Amount = tonumber(out.Amount) or 0,
		Rank = tonumber(out.Rank), Group = out.Group, Tier = out.Tier, Bonus = bonus }
	if out.Converted then
		r.Converted, r.Reason = true, out.Reason
		r.Conversion = {}
		for _, c in ipairs(type(out.Conversion) == "table" and out.Conversion or {}) do
			table.insert(r.Conversion, { Kind = c.Kind, Amount = tonumber(c.Amount) or 0 })
		end
	end
	if type(out.Overflow) == "table" then
		r.Overflow = { Kind = out.Overflow.Kind, Amount = tonumber(out.Overflow.Amount) or 0 }
	end
	if type(out.Item) == "table" then
		r.Item = { ItemId = out.Item.ItemId, Mutation = out.Item.Mutation, ItemUid = out.Item.ItemUid }
	end
	if type(out.Dog) == "table" then
		r.Dog = { DogId = out.Dog.DogId, Variant = out.Dog.Variant, DogUid = out.Dog.DogUid }
	end
	return r
end
Coffin.Clean = clean

-- rarity rank of a planned row (1..6; Chapter2Config.Coffin.Table rows carry Rank)
local function rankOf(row: any): number
	return math.clamp(math.floor(tonumber(row and row.Rank) or 1), 1, 6)
end

---------------------------------------------------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------------------------------------------------
local function anchorPos(): Vector3?
	local c2 = C2()
	if c2 and c2.AnchorPos then
		return c2.AnchorPos(CC.Anchor)
	end
	local part = Layout.AnchorPart(CC.Anchor)
	return part and part.Position or Layout.Anchor(CC.Anchor)
end

local function nearShrine(player: Player, radius: number): boolean
	local pos = anchorPos()
	return pos ~= nil and core ~= nil and core.Near(player, pos, radius)
end

-- -> ok, result (C2.Transact result: Rewards, Coffin = the C2Coffin payload, View) | false, message, need?
-- need = "Key" | "Shards" | "Dogs" for refusals the window can help with
function Coffin.Open(player: Player): (boolean, any, string?)
	local c2 = C2()
	if not core or not c2 or not Shared.Chapter2Enabled() then
		return false, Coffin.Closed, nil
	end
	if not c2.Eligible(player) then
		return false, "Finish Chapter I first", nil
	end
	if busy[player] or os.clock() - (lastOpen[player] or -1e9) < CC.Cooldown then
		return false, "Please wait a moment", nil
	end
	if not nearShrine(player, CC.Radius + Cfg.Proximity.Slack) then
		return false, "Come closer to the Black Coffin", nil
	end
	busy[player] = true
	local okCall, ok, res, need = pcall(function(): (boolean, any, string?)
		-- queued progress (streak shards, the H16 crown seconds) is written first so this opening sees it
		c2.FlushNow(player)
		local forced = c2.ForceCoffinFind(player)
		local plan = Coffin.Plan(Random.new(), forced)
		local price = c2.CoffinPrice()
		local dogs = {}
		if plan.Main.Kind == "Dog" then
			table.insert(dogs, plan.Main.Id)
		end
		local why: string? = nil
		local okT, result, _raw, cached = c2.Transact(player, "C2Coffin", function(p, u, ctx)
			local Rl = core.Rules
			why = "Key"
			Rl.Check(u.Keys >= price.Keys, "You need a Coffin Key")
			why = "Shards"
			Rl.Check(Resources.Get(p, "BellShards") >= price.Shards, "Not enough Bell Shards")
			why = "Dogs"
			Rl.Check(plan.Forced or Rl.Free(p), Coffin.StorageFull)
			why = nil
			ctx.SpendShards(price.Shards)
			u.Keys -= price.Keys
			local rows = { clean(ctx.C2Reward(plan.Main), nil) }
			-- H16 CROWN OF THE UNDERYARD: a stored crown roll is one extra showcase find
			if ctx.TakeCrownRoll() then
				table.insert(rows, clean(ctx.C2Reward(plan.Crown), "Crown"))
			end
			-- H12 COFFIN SENSE: a chance of one extra showcase find while the pug works in the yard
			local pug = Cfg.Dogs.Defs[CC.BonusDog]
			if pug and c2.TeamOfProfile(p)[CC.BonusDog] and plan.PugRoll < (pug.BonusFindChance or 0) then
				table.insert(rows, clean(ctx.C2Reward(plan.Pug), "Pug"))
			end
			local main = rows[1]
			ctx.RecordCoffin({ Key = plan.Main.Key, Kind = main.Kind, Id = main.Id, Amount = main.Amount, Rank = rankOf(plan.Main),
				Converted = main.Converted })
			return { Message = "The Black Coffin opens", Rewards = rows, Keys = u.Keys, Shards = Resources.Get(p, "BellShards") }
		end, { Dogs = dogs })
		if not okT then
			if type(result) ~= "string" or string.find(result, ":%d+:") then
				warn("Coffin: opening failed: " .. tostring(result))
				return false, "Something went wrong, try again", nil
			end
			return false, result, why
		end
		lastOpen[player] = os.clock()
		if cached then
			return true, result, nil
		end
		local rows = type(result) == "table" and result.Rewards or {}
		local main = rows[1] or { Kind = plan.Main.Kind, Id = plan.Main.Id, Amount = 0 }
		local rank = rankOf(plan.Main)
		local rarity = Shared.Rarity(rank)
		openId += 1
		local payload = {
			Id = openId, UserId = player.UserId, Name = player.DisplayName, Rank = rank, Rarity = rarity, Tier = rank,
			Main = main, Rows = rows, Converted = main.Converted == true, Duplicate = main.Converted == true and main.Reason == "Owned",
			Forced = plan.Forced, Keys = result.Keys, Shards = result.Shards, Seed = plan.Seed, At = now(),
		}
		result.Coffin = payload
		Coffin.Broadcast(player, payload)
		return true, result, nil
	end)
	busy[player] = nil
	if not okCall then
		warn("Coffin: opening failed: " .. tostring(ok))
		return false, "Something went wrong, try again", nil
	end
	return ok, res, need
end

---------------------------------------------------------------------------------------------------------------------
-- The Hollow King's arrival (ServerScriptService.SecretReveal: presentation only, ownership is already committed)
---------------------------------------------------------------------------------------------------------------------
local revealMod: any = nil
local function secretReveal(): any
	if revealMod == nil then
		local ok, m = pcall(function()
			local inst = game:GetService("ServerScriptService"):FindFirstChild("SecretReveal")
			return inst and require(inst :: any)
		end)
		revealMod = ok and type(m) == "table" and type(m.Show) == "function" and m or false
	end
	return revealMod or nil
end
Coffin.SecretReveal = secretReveal

-- where the display king stands (in front of the coffin's foot) and the way it faces (the tower)
function Coffin.KingSpot(): (Vector3, Vector3)
	local shrine: CFrame = Layout.Square.CoffinShrine
	return (shrine * CFrame.new(CC.King.Ground)).Position, shrine.LookVector
end

-- does this place have the king's arrival (template + SecretArrivalConfig)?
local function arrivalReady(): boolean
	local sr = secretReveal()
	if not sr then
		return false
	end
	if type(sr.Has) ~= "function" then
		return true
	end
	local ok, has = pcall(sr.Has, CC.SecretDog)
	return ok and has == true
end

-- hand the show over to the Secret arrival; -> the arrival started
local function raiseKing(payload: any): boolean
	local sr = secretReveal()
	if not sr then
		return false
	end
	local ground, facing = Coffin.KingSpot()
	local ok, model = pcall(sr.Show, CC.SecretDog, ground, facing, { Venue = CC.King.Venue, By = payload.Name })
	if not ok then
		warn("Coffin: the Hollow King's arrival failed: " .. tostring(model))
		return false
	end
	return model ~= nil
end

---------------------------------------------------------------------------------------------------------------------
-- Broadcast: the show for the opener, the lighter show for everyone near the shrine, the hand-off to the Hollow King's
-- arrival and the server-wide announcement on the show's reveal beat
---------------------------------------------------------------------------------------------------------------------
local function announce(payload: any, kind: string, revealAt: number, arrival: boolean?)
	local c2 = C2()
	if not c2 then
		return
	end
	local main = payload.Main
	c2.Signal("all", "C2Announce", { Kind = kind, Name = payload.Name, UserId = payload.UserId,
		DogId = main.Kind == "Dog" and main.Id or nil, RewardKind = main.Kind, Id = main.Id, Rank = payload.Rank, RevealAt = revealAt,
		Arrival = arrival })
end

function Coffin.Broadcast(player: Player, payload: any)
	local c2 = C2()
	if not c2 then
		return
	end
	local main = payload.Main
	local beats = CC.Beats(payload.Rank)
	local king = main.Kind == "Dog" and main.Id == CC.SecretDog and not main.Converted
	if king then
		payload.Arrival = arrivalReady()
		payload.Handoff = payload.At + (beats.Handoff or beats.Open)
	end
	c2.Signal(player, "C2Coffin", payload)
	local near = { Id = payload.Id, UserId = payload.UserId, Name = payload.Name, Rank = payload.Rank, Rarity = payload.Rarity,
		Main = { Kind = main.Kind, Id = main.Id, Amount = main.Amount, Converted = main.Converted }, Seed = payload.Seed,
		At = payload.At, Preview = payload.Preview, Arrival = payload.Arrival, Handoff = payload.Handoff }
	local pos = anchorPos()
	if pos then
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and core.Near(other, pos, CC.NearRadius) then
				c2.Signal(other, "C2CoffinNear", near)
			end
		end
	end
	local function after(showT: number, fn: () -> ())
		Coffin.Delay(math.max(0, payload.At + showT - now()), function()
			local ok, err = pcall(fn)
			if not ok then
				warn("Coffin: " .. tostring(err))
			end
		end)
	end
	if king then
		-- the arrival also plays for a Studio preview (presentation only); only real openings are announced
		after(beats.Handoff or beats.Open, function()
			local arrived = payload.Arrival == true and raiseKing(payload)
			if not payload.Preview then
				announce(payload, "HollowKing", payload.At + beats.Reveal, arrived)
			end
		end)
	elseif not payload.Preview and not main.Converted and payload.Rank >= CC.AnnounceRank then
		after(beats.Reveal, function()
			announce(payload, "Mythic", payload.At + beats.Reveal, nil)
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- Studio preview of the presentation (C2CoffinDebug): nothing is granted or spent
---------------------------------------------------------------------------------------------------------------------
local PREVIEW = { -- a sample reward of each rank
	{ Kind = "Dust", Amount = 96 }, { Kind = "Find", Id = "uy_lost_veil" }, { Kind = "Find", Id = "uy_dead_wedding_ring" },
	{ Kind = "Decor", Id = "uy_ghost_fountain" }, { Kind = "Dog", Id = "HW_Bridehound" }, { Kind = "Dog", Id = "HW_HollowKing" },
}
function Coffin.Preview(player: Player, args: any): (boolean, any)
	local a = type(args) == "table" and args or {}
	local rank = math.clamp(math.floor(tonumber(a.Rank) or 1), 1, 6)
	local sample = PREVIEW[rank]
	local main = { Kind = type(a.Kind) == "string" and a.Kind or sample.Kind, Id = type(a.Id) == "string" and a.Id or sample.Id,
		Amount = sample.Amount or 1, Rank = rank }
	openId += 1
	local payload = { Id = openId, UserId = player.UserId, Name = player.DisplayName, Rank = rank, Rarity = Shared.Rarity(rank),
		Tier = rank, Main = main, Rows = { main }, Converted = false, Duplicate = false, Forced = false,
		Keys = tonumber(player:GetAttribute("CoffinKeys")) or 0, Shards = tonumber(player:GetAttribute("BellShards")) or 0,
		Seed = math.random(1, 2147483646), At = now(), Preview = true }
	Coffin.Broadcast(player, payload)
	return true, { Message = "Coffin preview", Coffin = payload }
end

---------------------------------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------------------------------
-- the Underyard window's COFFIN tab (how to get keys / shards) after a refused prompt opening
function Coffin.OpenWindow(player: Player)
	local remote = RS:FindFirstChild("DogEconomyOpen")
	if remote and remote:IsA("RemoteEvent") then
		remote:FireClient(player, CC.Window.Page, { Tab = CC.Window.Tab })
	end
end

function Coffin.Start(c: any, m: any)
	core, modules = c, m
	-- the request is registered even with Chapter II off: it answers "Chapter II is closed"
	core.OnRequest(CC.Request.Action, function(player: Player, _args: any)
		if not Shared.Chapter2Enabled() then
			return false, Coffin.Closed
		end
		local ok, res = Coffin.Open(player)
		return ok, res
	end, { Cost = CC.Request.Cost })
	if RunService:IsStudio() and game.GameId == 0 then
		core.OnRequest(CC.Request.DebugAction, function(player: Player, args: any)
			return Coffin.Preview(player, args)
		end, { Cost = .5 })
	end
	if not Shared.Chapter2Enabled() then
		return
	end
	local uy = UY()
	if uy and uy.Prompt then
		uy.Prompt(CC.Anchor, {
			Name = "UyCoffinPrompt", ActionText = CC.Prompt.ActionText[1], ObjectText = CC.Prompt.ObjectText[1],
			ActionTextRU = CC.Prompt.ActionText[2], ObjectTextRU = CC.Prompt.ObjectText[2], HoldDuration = CC.Prompt.HoldDuration,
			MaxActivationDistance = CC.Prompt.MaxActivationDistance, Attributes = { CoffinPrompt = true },
		}, function(player: Player)
			local ok, err, need = Coffin.Open(player)
			if not ok then
				local c2 = C2()
				if c2 then
					c2.Signal(player, "C2CoffinRefused", { Text = tostring(err), Need = need })
				end
				if need == "Key" or need == "Shards" then
					Coffin.OpenWindow(player)
				end
			end
		end)
	else
		warn("Coffin: no Underyard zone module, the shrine prompt is missing (the window's OPEN still works)")
	end
	Players.PlayerRemoving:Connect(function(player)
		lastOpen[player] = nil
		busy[player] = nil
	end)
end

return Coffin
