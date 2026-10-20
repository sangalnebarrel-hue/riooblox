-- SERVER EXORCISM (ServerScriptService.Halloween.Exorcism): one shared Haunted Souls counter per server.
-- Every candy earned and every Dead Yard objective adds souls (Config.Exorcism.Souls). Milestones:
--   1000 -> server Candy Rush x2 for 5 minutes, 2500 -> a RARE Pumpkin Lucky Block (MinRank: Epic+ rewards only) for every
--   player on the server,
--   4000 -> event mutation chance x2 for 10 minutes, 5000 -> THE GRAVEKEEPER rises (then the counter starts over).
-- Published on RS.Halloween.State.Exorcism (Souls, Goal, Cycle, Milestone) + State.ServerRushUntil/MutationBoostUntil.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Halloween = RS:WaitForChild("Halloween")
local Shared = require(Halloween:WaitForChild("Shared"))
local Config = Shared.Config

local Ex = { Souls = 0, Cycle = 1, Milestone = 0, PendingBoss = false, Hooks = {} }
local State = Halloween:WaitForChild("State")
local folder = State:WaitForChild("Exorcism")
local core = nil

local function publish()
	folder:SetAttribute("Souls", math.floor(Ex.Souls))
	folder:SetAttribute("Goal", Config.Exorcism.Goal)
	folder:SetAttribute("Cycle", Ex.Cycle)
	folder:SetAttribute("Milestone", Ex.Milestone)
end

-- the boss module registers how to summon (Ex.Hooks.SummonBoss = function(difficulty, reason) -> ok)
function Ex.SetBossHook(fn)
	Ex.Hooks.SummonBoss = fn
end

local function grantBlockToAll(tier: string, minRank: number?)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			-- server-made receipt (one block per player per cycle); a cached reply was granted and toasted before
			local ok, res, _, cached = core.Transact(player, "ExorcismBlock", function(_p, _h, ctx)
				local row = ctx.Reward({ Kind = "Block", Id = tier, Amount = 1, MinRank = minRank })
				return { Reward = row }
			end, { Receipt = "hw-exo:" .. player.UserId .. ":" .. Ex.Cycle .. ":" .. tier })
			if ok and not cached then
				local row = type(res) == "table" and res.Reward or nil
				if row and row.Converted then -- full Lucky Block storage: ctx.Reward paid candy instead
					core.Signal(player, "Toast", { Text = "Lucky Block storage full: +" .. tostring(row.Amount or 0) .. " Candy instead", Kind = "info" })
				else
					local rare = (tonumber(minRank) or 1) > 1 and "RARE " or ""
					core.Signal(player, "Toast", { Text = rare .. string.upper(tier) .. " LUCKY BLOCK added to your Inventory", Kind = "success" })
				end
			end
		end)
	end
end

local function reach(index: number)
	local m = Config.Exorcism.Milestones[index]
	if not m then
		return
	end
	Ex.Milestone = index
	publish()
	local now = os.time()
	if m.Kind == "CandyRush" then
		State:SetAttribute("ServerRushUntil", math.max(State:GetAttribute("ServerRushUntil") or 0, now) + m.Seconds)
	elseif m.Kind == "Block" then
		grantBlockToAll(m.Tier or "Pumpkin", m.MinRank)
	elseif m.Kind == "Mutation" then
		State:SetAttribute("MutationBoostUntil", math.max(State:GetAttribute("MutationBoostUntil") or 0, now) + m.Seconds)
	elseif m.Kind == "Boss" then
		Ex.PendingBoss = true
	end
	core.Signal("all", "Milestone", { Index = index, Name = m.Name, Kind = m.Kind, Souls = m.At, Cycle = Ex.Cycle })
	if Ex.PendingBoss then
		task.spawn(Ex.TrySummon)
	end
end

function Ex.TrySummon()
	if not Ex.PendingBoss then
		return
	end
	local hook = Ex.Hooks.SummonBoss
	if hook then
		local m = Config.Exorcism.Milestones[#Config.Exorcism.Milestones]
		local ok = hook(m.Difficulty or 2, "Exorcism")
		if ok then
			Ex.PendingBoss = false
		end
	end
end

-- called by the boss module when a fight that the exorcism started is over
function Ex.Reset()
	Ex.Souls = 0
	Ex.Milestone = 0
	Ex.Cycle += 1
	Ex.PendingBoss = false
	publish()
	core.Signal("all", "Exorcism", { Souls = 0, Goal = Config.Exorcism.Goal, Cycle = Ex.Cycle, Reset = true })
end

local lastPulse = 0
function Ex.Add(n: number, player: Player?)
	if not Shared.Enabled() or not n or n <= 0 then
		return
	end
	if Ex.Milestone >= #Config.Exorcism.Milestones then
		return -- full: waiting for the Gravekeeper fight to end
	end
	Ex.Souls = math.min(Config.Exorcism.Goal, Ex.Souls + n)
	publish()
	for i = Ex.Milestone + 1, #Config.Exorcism.Milestones do
		if Ex.Souls >= Config.Exorcism.Milestones[i].At then
			reach(i)
		else
			break
		end
	end
	if os.clock() - lastPulse > 2 then
		lastPulse = os.clock()
		core.Signal("all", "Exorcism", { Souls = math.floor(Ex.Souls), Goal = Config.Exorcism.Goal, Cycle = Ex.Cycle })
	end
end

function Ex.Start(c)
	core = c
	publish()
	c.OnSouls(function(n, player)
		Ex.Add(n, player)
	end)
	task.spawn(function()
		while true do
			task.wait(5)
			if Ex.PendingBoss then
				Ex.TrySummon()
			end
		end
	end)
end

return Ex
