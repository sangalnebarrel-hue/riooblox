-- Stored crafting resources (p.Resources). Stone comes from breaking Limestone at the Mining
-- Corner and pays for plot decor next to coins, so the most common ore is a useful resource and
-- not only small change. Server code changes amounts only inside an economy transaction.
--   Resources.Get(p, "Stone") -> integer
--   Resources.Add(p, "Stone", n) -> added (clamped to Max)
--   Resources.CanSpend(p, cost) / Resources.Spend(p, cost)   cost = {Stone = 12, ...}
-- Saved data: p.Resources = {Stone = n}; missing table or keys mean 0 (old profiles).
local Resources = {}

Resources.Kinds = {
	Stone = { Name = "Stone", RU = "Камень", Icon = "🪨", Color = Color3.fromRGB(176, 170, 160), Max = 1000000000 },
}
Resources.Order = { "Stone" }

local function amount(v: any): number
	if type(v) ~= "number" or v ~= v or v < 0 then
		return 0
	end
	return math.floor(v)
end

function Resources.Get(p: any, kind: string): number
	local t = type(p) == "table" and p.Resources
	return type(t) == "table" and amount(t[kind]) or 0
end

function Resources.Add(p: any, kind: string, n: number): number
	local def = Resources.Kinds[kind]
	assert(def, "Unknown resource " .. tostring(kind))
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then
		return 0
	end
	if type(p.Resources) ~= "table" then
		p.Resources = {}
	end
	local before = amount(p.Resources[kind])
	local after = math.min(def.Max, before + n)
	p.Resources[kind] = after
	return after - before
end

function Resources.CanSpend(p: any, cost: { [string]: number }?): boolean
	for kind, n in pairs(cost or {}) do
		if Resources.Kinds[kind] and n > 0 and Resources.Get(p, kind) < n then
			return false
		end
	end
	return true
end

-- Errors (aborting the transaction) when the player cannot pay.
function Resources.Spend(p: any, cost: { [string]: number }?)
	for kind, n in pairs(cost or {}) do
		local def = Resources.Kinds[kind]
		assert(def, "Unknown resource " .. tostring(kind))
		if n > 0 then
			local have = Resources.Get(p, kind)
			if have < n then
				error("Not enough " .. def.Name, 0)
			end
			p.Resources[kind] = have - math.floor(n)
		end
	end
end

-- Normalize for saved data: heals bad values of known kinds. Unknown kinds are kept untouched
-- (a rolled-back server must not erase what a newer version saved).
function Resources.Normalize(p: any)
	if type(p.Resources) ~= "table" then
		p.Resources = {}
		return
	end
	for kind in pairs(Resources.Kinds) do
		local v = p.Resources[kind]
		if v ~= nil and (type(v) ~= "number" or v ~= v or v < 0 or v % 1 ~= 0) then
			p.Resources[kind] = amount(v)
		end
	end
end

-- Structural check after a transaction (nil-safe: profiles that skipped Normalize pass).
function Resources.Validate(p: any)
	local t = p.Resources
	if t == nil then
		return
	end
	assert(type(t) == "table", "Invalid resources")
	for kind, def in pairs(Resources.Kinds) do
		local v = t[kind]
		assert(v == nil or (type(v) == "number" and v == v and v >= 0 and v % 1 == 0 and v <= def.Max), "Invalid " .. kind)
	end
end

return Resources
