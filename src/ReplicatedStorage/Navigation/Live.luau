-- Navigation.Live: the event switches the routes depend on, read at CALL time (Destinations, RouteGraph, PathGuide).
-- THE DEAD YARD and the church only exist while the Halloween event runs; a live server can switch the event off
-- (World.Disable writes RS.Halloween.State.Enabled = false) or close Chapter II (State attribute
-- HalloweenChapter2Enabled), so a destination's Sealed state, the Dead Yard nodes and the yard / COMING SOON blockers
-- follow these readers instead of a value cached when the module loaded.
--   Live.Configured() -> bool   Config.HalloweenEventEnabled (the place ships the event geometry; list membership)
--   Live.Halloween() -> bool    the event is running (config flag and the server's State.Enabled)
--   Live.Chapter2() -> bool     CHAPTER II is open (Halloween() and its flag / State attribute)
--   Live.Override = {Halloween = bool?, Chapter2 = bool?} | nil   (tests)
-- Pure enough for Lune: every read is protected and falls back to the config flags.
local Live = {}
Live.Override = nil :: { [string]: boolean? }?

local cached: any = nil
local function halloweenFolder(): Instance?
	local ok, folder = pcall(function()
		return game:GetService("ReplicatedStorage"):FindFirstChild("Halloween")
	end)
	return ok and folder or nil
end

local function config(): any
	if cached == nil then
		local ok, cfg = pcall(function()
			local folder = halloweenFolder()
			local module = folder and folder:FindFirstChild("Config")
			return module and require(module :: any)
		end)
		cached = ok and type(cfg) == "table" and cfg or false
	end
	return cached or nil
end

local function stateAttr(name: string): any
	local ok, value = pcall(function()
		local folder = halloweenFolder()
		local state = folder and folder:FindFirstChild("State")
		return state and state:GetAttribute(name)
	end)
	return ok and value or nil
end

function Live.Configured(): boolean
	local cfg = config()
	return cfg ~= nil and cfg.HalloweenEventEnabled == true
end

function Live.Halloween(): boolean
	local o = Live.Override
	if o and o.Halloween ~= nil then
		return o.Halloween == true
	end
	if not Live.Configured() then
		return false
	end
	return stateAttr("Enabled") ~= false
end

function Live.Chapter2(): boolean
	local o = Live.Override
	if o and o.Chapter2 ~= nil then
		return o.Chapter2 == true and Live.Halloween()
	end
	if not Live.Halloween() then
		return false
	end
	local cfg = config()
	if not cfg or cfg.HalloweenChapter2Enabled ~= true then
		return false
	end
	return stateAttr("HalloweenChapter2Enabled") ~= false
end

return Live
