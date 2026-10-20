-- DOG RUSH (docs/DOG_RUSH.md): the shared, pure rules of the event.
--   * The stampede: packs of dogs run along real streets of the district (the DOG EXPRESS lanes, the
--     north end of MainBoulevard and the south garden loop; a second loop on the open south half of the
--     boulevard). Where a pack is depends only on the server clock (workspace:GetServerTimeNow()) and
--     the event's StartTimestamp, so every client draws the same pack at the same place without any
--     replication (WorldEventStampede draws them).
--   * Runaway golden pups: the server spawns catchable pups at street points along the routes
--     (WorldEventService), a few at a time; catching one pays a small income-scaled reward and counts
--     towards the per-event chests (3 / 6 / 10) and the lifetime DOG WRANGLER titles (Features.DogRush).
-- Coordinates: +Z is south, the streets' top surface is at Y = 0.5 (MainBoulevard X -18..18,
-- Z 146..754; DOG EXPRESS lanes X ±23..29; south garden loop Z 725..735).
local RS = game:GetService("ReplicatedStorage")
local Pricing = require(RS:WaitForChild("DogEconomy"):WaitForChild("BoostPricing"))

local M = {}
M.EventId = "DOG_RUSH"
M.Version = 1

-- Runaway pups (server rules; the client only draws them).
M.Pups = {
	PerEvent = 12, -- catches per player per event (the chests need 10)
	Cooldown = 1.5, -- seconds between two catches of one player
	Distance = 14, -- the server accepts a catch this close to the pup (studs)
	Lifetime = 40, -- an uncaught pup runs home after this many seconds
	FirstAfter = 6, -- seconds into the event before the first pup
	SpawnEvery = 3, -- at most one new pup every this many seconds
	MinActive = 3,
	MaxActive = 10,
	PerPlayer = 0.75, -- extra pups in the street per player in the server
	Spacing = 14, -- minimum distance between two pups
	NearChance = 0.7, -- most pups appear near a random player...
	NearMin = 25,
	NearMax = 110, -- ...between these distances along the route
	Bones = 1,
	Coins = { MinCash = 100, IncomeMinutes = 0.2 }, -- BoostPricing.Coins: 12 s of team income, floor x layer scale
}
-- Per-event chests, granted automatically by the catch that reaches Count (Features.DogRush).
-- stylua: ignore
M.Milestones = {
	{ Count = 3, Name = "PUP CHEST", RU = "СУНДУК ЩЕНКА", Icon = "🎁", Coins = { MinCash = 400, IncomeMinutes = 0.5 }, Bones = 3 },
	{ Count = 6, Name = "PACK CHEST", RU = "СУНДУК СТАИ", Icon = "🎁", Coins = { MinCash = 800, IncomeMinutes = 1 }, Bones = 5 },
	{ Count = 10, Name = "GOLDEN CHEST", RU = "ЗОЛОТОЙ СУНДУК", Icon = "👑", Coins = { MinCash = 1500, IncomeMinutes = 2 }, Bones = 8,
		Block = { Tier = "Rare", Count = 1 }, FallbackBones = 12 },
}
M.Goal = M.Milestones[#M.Milestones].Count

------------------------------------------------------------------------------------------------
-- Routes
------------------------------------------------------------------------------------------------
M.StreetY = 0.5
M.Step = 2 -- studs between route samples
M.Speed = 22 -- studs per second
M.SurgeBoost = 1.6 -- ALPHA STAMPEDE (the event's signature moment): packs sprint
-- Closed loops, corners rounded with this radius. Lateral: how far a pup may sit off the centre line.
-- stylua: ignore
M.Routes = {
	{ Id = "Outer", Corner = 9, Lateral = 2.5, Speed = 1,
		Points = { { -26, 172 }, { -26, 728 }, { 26, 728 }, { 26, 172 } } },
	{ Id = "Inner", Corner = 7, Lateral = 6, Speed = 0.92,
		Points = { { 9, 418 }, { 9, 712 }, { -9, 712 }, { -9, 418 } } },
}
-- Packs: canonical, so a pack is at the same place for every player. Quality decides how many of them
-- (and how many of their dogs) a client draws: Low 1 pack x 3, Medium 2 x 4, High 3 packs (14 dogs).
-- stylua: ignore
M.Packs = {
	{ Route = "Outer", Phase = 0, Leader = "CaptainCorgi", Dogs = { "Breadog", "Sausagedog", "CoffeeDog", "Burgerdog" }, MinQuality = 1 },
	{ Route = "Inner", Phase = 0.35, Leader = "KingCorgi", Dogs = { "Sushiba", "Ramendog", "GalaxyHusky" }, MinQuality = 2 },
	{ Route = "Outer", Phase = 0.5, Leader = "SunDog", Dogs = { "MechaBark", "InfernoBull", "RocketDachshund", "Cerberdog" }, MinQuality = 3 },
}
-- Formation slots behind the leader: {lateral, back} in studs (leader first).
M.Formation = { { 0, 0 }, { -1.7, -4.2 }, { 1.7, -4.6 }, { -1.1, -8.8 }, { 1.4, -9.4 } }
-- The sky portal of the event (WorldEventSpectacle): a fixed world anchor and view direction, the
-- portal stands far above the south loop where the stampede turns.
M.SkyStage = { Near = Vector3.new(0, M.StreetY, 330), Look = Vector3.new(0, 0, 1) }

local function v2(x: number, z: number): Vector3
	return Vector3.new(x, 0, z)
end

-- A closed polyline with every corner replaced by a quadratic curve, resampled every M.Step studs.
local function buildRoute(def: any): any
	local raw = {}
	for _, p in ipairs(def.Points) do
		table.insert(raw, v2(p[1], p[2]))
	end
	local n = #raw
	local path = {}
	for i = 1, n do
		local a, b, c = raw[(i - 2) % n + 1], raw[i], raw[i % n + 1]
		local inLen, outLen = (b - a).Magnitude, (c - b).Magnitude
		local r = math.min(def.Corner or 8, inLen * 0.45, outLen * 0.45)
		local p1 = b - (b - a).Unit * r
		local p2 = b + (c - b).Unit * r
		for k = 0, 6 do
			local t = k / 6
			local q = p1 * (1 - t) * (1 - t) + b * 2 * (1 - t) * t + p2 * t * t
			table.insert(path, q)
		end
	end
	-- Cumulative length of the closed path.
	local cum = { 0 }
	local m = #path
	for i = 1, m do
		local a, b = path[i], path[i % m + 1]
		cum[i + 1] = cum[i] + (b - a).Magnitude
	end
	local length = cum[m + 1]
	local count = math.max(8, math.floor(length / M.Step + 0.5))
	local step = length / count
	local xs, zs = table.create(count), table.create(count)
	local seg = 1
	for i = 0, count - 1 do
		local s = i * step
		while cum[seg + 1] < s and seg < m do
			seg += 1
		end
		local a, b = path[seg], path[seg % m + 1]
		local segLen = cum[seg + 1] - cum[seg]
		local f = segLen > 0 and (s - cum[seg]) / segLen or 0
		local q = a:Lerp(b, f)
		xs[i + 1], zs[i + 1] = q.X, q.Z
	end
	-- Unit tangents from the neighbours (smooth headings).
	local tx, tz = table.create(count), table.create(count)
	for i = 1, count do
		local prev, nxt = (i - 2) % count + 1, i % count + 1
		local dx, dz = xs[nxt] - xs[prev], zs[nxt] - zs[prev]
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 1e-6 then
			dx, dz, len = 0, 1, 1
		end
		tx[i], tz[i] = dx / len, dz / len
	end
	local ys = table.create(count, M.StreetY)
	return {
		Id = def.Id,
		Def = def,
		Count = count,
		StepLength = step,
		Length = length,
		X = xs,
		Z = zs,
		Y = ys, -- street heights; the client may refine them once (WorldEventStampede)
		TX = tx,
		TZ = tz,
		Lateral = def.Lateral or 3,
		Speed = def.Speed or 1,
	}
end

M.Route = {}
M.RouteList = {}
for _, def in ipairs(M.Routes) do
	local route = buildRoute(def)
	M.Route[def.Id] = route
	table.insert(M.RouteList, route)
end

-- Position (x, y, z) and unit heading (tx, tz) at arc length d along a route (wraps around).
function M.Sample(route: any, d: number): (number, number, number, number, number)
	local count = route.Count
	local u = (d % route.Length) / route.StepLength
	local i0 = math.floor(u)
	local f = u - i0
	local a = i0 % count + 1
	local b = a % count + 1
	local x = route.X[a] + (route.X[b] - route.X[a]) * f
	local z = route.Z[a] + (route.Z[b] - route.Z[a]) * f
	local y = route.Y[a] + (route.Y[b] - route.Y[a]) * f
	local tx = route.TX[a] + (route.TX[b] - route.TX[a]) * f
	local tz = route.TZ[a] + (route.TZ[b] - route.TZ[a]) * f
	local len = math.sqrt(tx * tx + tz * tz)
	if len < 1e-6 then
		tx, tz, len = route.TX[a], route.TZ[a], 1
	end
	return x, y, z, tx / len, tz / len
end

-- Arc length a pack has travelled `elapsed` seconds into the event (the signature surge included).
local surgeAt, surgeLength = 60, 18
do
	local ok, D = pcall(function()
		return require(script.Parent:WaitForChild("WorldEventDefinitions"))
	end)
	local row = ok and type(D) == "table" and D.ById and D.ById[M.EventId]
	if row then
		surgeAt = tonumber(row.SignatureSeconds) or surgeAt
		surgeLength = tonumber(row.SignatureDuration) or surgeLength
	end
end
M.SurgeAt, M.SurgeLength = surgeAt, surgeLength
function M.Distance(elapsed: number): number
	elapsed = math.max(0, elapsed)
	local boosted = math.clamp(elapsed - surgeAt, 0, surgeLength)
	return M.Speed * elapsed + (M.SurgeBoost - 1) * M.Speed * boosted
end
function M.Surging(elapsed: number): boolean
	return elapsed >= surgeAt and elapsed < surgeAt + surgeLength
end

-- Where pack `index` (M.Packs) is at server time `now` for an event started at `start`:
-- route, arc length of its leader.
function M.PackDistance(index: number, now: number, start: number): (any, number)
	local pack = M.Packs[index]
	local route = M.Route[pack.Route]
	return route, pack.Phase * route.Length + M.Distance(now - start) * route.Speed
end

-- Packs and dogs a client draws for a quality level (1 Low, 2 Medium, 3 High) and dog budget.
function M.PacksFor(quality: number, budget: number): { any }
	local out = {}
	local perPack = quality >= 3 and 5 or quality == 2 and 4 or 3
	local left = math.max(0, math.floor(budget))
	for index, pack in ipairs(M.Packs) do
		if quality >= pack.MinQuality and left > 0 then
			local size = math.min(perPack, 1 + #pack.Dogs, left)
			left -= size
			table.insert(out, { Index = index, Size = size, Pack = pack })
		end
	end
	return out
end

-- Offset of a dog (slot >= 1, leader = 1) from its leader at time t: lateral, back (studs).
function M.Slot(slot: number, t: number): (number, number)
	local f = M.Formation[(slot - 1) % #M.Formation + 1]
	local lateral = f[1] + math.sin(t * 1.7 + slot * 1.3) * 0.35
	local back = f[2] + math.sin(t * 1.1 + slot * 2.1) * 0.9
	if slot == 1 then
		lateral, back = math.sin(t * 0.9) * 0.4, 0
	end
	return lateral, back
end

------------------------------------------------------------------------------------------------
-- Pups (server)
------------------------------------------------------------------------------------------------
-- Pups that should be in the street with `players` players in the server.
function M.TargetPups(players: number): number
	local p = M.Pups
	return math.clamp(p.MinActive + math.floor(math.max(0, players) * p.PerPlayer), p.MinActive, p.MaxActive)
end

-- A street point for a new pup. rand() -> [0, 1); near: player positions (Vector3) to spawn close to;
-- occupied: positions of live pups. Returns Vector3 (on the street, Y = route height) or nil.
function M.PickSpawn(rand: () -> number, near: { Vector3 }?, occupied: { Vector3 }?, tries: number?): Vector3?
	local pups = M.Pups
	occupied = occupied or {}
	local function free(x: number, z: number): boolean
		for _, o in ipairs(occupied :: { Vector3 }) do
			local dx, dz = o.X - x, o.Z - z
			if dx * dx + dz * dz < pups.Spacing * pups.Spacing then
				return false
			end
		end
		return true
	end
	local total = 0
	for _, route in ipairs(M.RouteList) do
		total += route.Length
	end
	for _ = 1, tries or 12 do
		local route, d
		local anchor = near and #near > 0 and rand() < pups.NearChance and near[math.floor(rand() * #near) + 1] or nil
		if anchor then
			-- Route samples within NearMin..NearMax of the player.
			local options = {}
			for _, r in ipairs(M.RouteList) do
				for i = 1, r.Count do
					local dx, dz = r.X[i] - anchor.X, r.Z[i] - anchor.Z
					local dist2 = dx * dx + dz * dz
					if dist2 >= pups.NearMin * pups.NearMin and dist2 <= pups.NearMax * pups.NearMax then
						table.insert(options, { r, (i - 1) * r.StepLength })
					end
				end
			end
			if #options > 0 then
				local pick = options[math.floor(rand() * #options) + 1]
				route, d = pick[1], pick[2]
			end
		end
		if not route then
			local s = rand() * total
			for _, r in ipairs(M.RouteList) do
				if s < r.Length or r == M.RouteList[#M.RouteList] then
					route, d = r, math.clamp(s, 0, r.Length)
					break
				end
				s -= r.Length
			end
		end
		local x, y, z, tx, tz = M.Sample(route, d)
		local side = (rand() * 2 - 1) * route.Lateral
		x, z = x - tz * side, z + tx * side
		if free(x, z) then
			return Vector3.new(x, y, z)
		end
	end
	return nil
end

-- Coins of one pup / one chest for this player now (server and client agree).
function M.PupCoins(p: any, now: number): number
	return Pricing.Coins(M.Pups.Coins, p or {}, now)
end
function M.ChestCoins(milestone: any, p: any, now: number): number
	return Pricing.Coins(milestone.Coins, p or {}, now)
end
function M.Milestone(count: number): any
	for _, m in ipairs(M.Milestones) do
		if m.Count == count then
			return m
		end
	end
	return nil
end
-- The next chest a player is working towards (nil when all are open).
function M.NextMilestone(caught: number): any
	for _, m in ipairs(M.Milestones) do
		if caught < m.Count then
			return m
		end
	end
	return nil
end

return M
