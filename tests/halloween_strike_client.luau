--!nocheck
-- MiningClient.HalloweenStrike on the fake client of tests/lib/client_env.luau: when a session may start, and what
-- happens to a press under a cinematic (the gui attribute CinemaActive, HalloweenClient.Cinema). A strike never starts
-- under a cinematic; the press is kept and starts the strike once the shot is over (within 2 s), so the click / tap that
-- skipped the shot is not lost. The server is a fake Remotes.Request that counts StrikeBegin calls.
-- lune run tests/halloween_strike_client.luau
local roblox = require("@lune/roblox")
local CE = require("./lib/client_env")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local passed, failed = 0, 0
local function test(name, fn)
	local before = #CE.Errors
	local ok, err = pcall(fn)
	if ok and #CE.Errors > before then
		ok, err = false, "runtime errors:\n  " .. table.concat(CE.Errors, "\n  ", before + 1)
	end
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. " got " .. tostring(a), 2)
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the fake engine pieces and the Halloween modules the strike client reads
---------------------------------------------------------------------------------------------------------------------
local tagged, added, removed = {}, CE.Signal.new(), CE.Signal.new()
local CS = CE.Service("CollectionService")
CS.GetTagged = function()
	return table.clone(tagged)
end
CS.GetInstanceAddedSignal = function()
	return added
end
CS.GetInstanceRemovedSignal = function()
	return removed
end
local CAS = CE.Service("ContextActionService")
CAS.BindActionAtPriority = function() end
CAS.UnbindAction = function() end

local RS = CE.Service("ReplicatedStorage")
local Halloween = CE.Folder("Halloween", RS)
for _, name in ipairs({ "Shared", "Bus", "FX", "Audio", "PickaxeSkins" }) do
	local m = CE.Instance.new("ModuleScript")
	m.Name = name
	m.Parent = Halloween
end
CE.Overrides["ReplicatedStorage/Halloween/Shared"] = {
	Config = { HalloweenEventEnabled = true, Candy = { PerfectHit = 1 } },
	Enabled = function()
		return true
	end,
}
CE.Overrides["ReplicatedStorage/Halloween/Bus"] = { Fire = function() end }
CE.Overrides["ReplicatedStorage/Halloween/FX"] = {}
CE.Overrides["ReplicatedStorage/Halloween/Audio"] = {}
CE.Overrides["ReplicatedStorage/Halloween/PickaxeSkins"] = {}
local Remotes = CE.Folder("Remotes", Halloween)
local request = CE.Instance.new("RemoteFunction")
request.Name = "Request"
request.Parent = Remotes
local signal = CE.Instance.new("RemoteEvent")
signal.Name = "Signal"
signal.Parent = Remotes

-- the server: StrikeBegin answers "gone" (the session itself is not under test), or runs `during` first
local calls = { StrikeBegin = 0, StrikeEnd = 0 }
local during = nil
local beginOk = false
CE.OnInvoke = function(_, action)
	calls[action] = (calls[action] or 0) + 1
	if action == "StrikeBegin" then
		if during then
			local fn = during
			during = nil
			fn()
		end
		if beginOk then
			return true, { HP = 10, MaxHP = 10, Targets = {} }
		end
		return false, "HW:GONE"
	end
	return true, nil
end

local gui = CE.MainGui()
local toasts = {}
local function noop() end
local ctx = {
	Player = CE.Player,
	Gui = gui,
	Main = gui,
	M = { Timing = { GoodFrom = .5, PerfectFrom = .8, PerfectTo = .92 }, Pickaxes = { { Name = "Wood", Swing = 1, FX = 1, Theme = "Wood", Color = { 160, 120, 80 } } } },
	Text = {
		L = function(en)
			return en
		end,
		Get = function(key)
			return key
		end,
		IsRussian = function()
			return false
		end,
		Name = function(p)
			return p.Name or ""
		end,
		Message = function(code)
			return code
		end,
	},
	Audio = { Play = noop, Pickaxe = noop },
	U = { Colors = { red = roblox.Color3.new(1, 0, 0), gold = roblox.Color3.new(1, 1, 0) } },
	World = {},
	FX = { ReducedMotion = function()
		return true
	end, Hit = noop },
	Hud = { Toast = function(text)
		table.insert(toasts, text)
	end },
	Anim = { Draw = noop, SetReady = noop, Swing = noop },
	MenuOpen = function()
		return gui:GetAttribute("OpenMenu") ~= nil
	end,
}
CE.Player:SetAttribute("MiningPickaxe", 1)
CE.Spawn(Vector3.new(0, 3, 0))

local target = CE.Part("Chain", Vector3.new(4, 3, 0), nil, CE.Workspace)
target:SetAttribute("TargetId", "chain1")
target:SetAttribute("Kind", "Chain")
target:SetAttribute("HP", 10)
target:SetAttribute("Range", 20)
table.insert(tagged, target)

local folder = CE.Folder("MiningClient", CE.Service("StarterPlayer"))
CE.Mount("StarterPlayer/StarterPlayerScripts/MiningClient", folder)
local Strike = CE.Require(folder.HalloweenStrike).new(ctx)
CE.Advance(1) -- the start task attaches the prompts

local function prompt()
	return target:FindFirstChild("HalloweenStrikePrompt")
end
local function press()
	prompt().Triggered:Fire(CE.Player)
	CE.Advance(.05)
end
local function shot(on)
	gui:SetAttribute("CinemaActive", on and true or nil)
	CE.Advance(.05)
end
local function reset()
	calls.StrikeBegin, calls.StrikeEnd = 0, 0
	during = nil
	beginOk = false
	shot(false)
	CE.Advance(2.5)
end

---------------------------------------------------------------------------------------------------------------------
test("a press without a cinematic asks the server at once", function()
	reset()
	eq(prompt() ~= nil and prompt().Enabled, true, "the target has a live prompt")
	press()
	eq(calls.StrikeBegin, 1)
	eq(Strike.Active, false, "the server refused (gone)")
end)

test("a press under a cinematic waits for its end, then starts the strike once", function()
	reset()
	shot(true)
	press()
	press() -- a second press while waiting is not queued twice
	eq(calls.StrikeBegin, 0, "nothing starts under the shot")
	CE.Advance(.5)
	shot(false)
	eq(calls.StrikeBegin, 1, "the kept press starts the strike when the shot ends")
	shot(true)
	shot(false)
	eq(calls.StrikeBegin, 1, "and only once")
end)

test("a kept press expires after 2 s", function()
	reset()
	shot(true)
	press()
	CE.Advance(2.5)
	shot(false)
	eq(calls.StrikeBegin, 0, "a press older than 2 s is dropped")
end)

test("the pickaxe click that skips the shot starts the strike after the return glide", function()
	reset()
	local tool = CE.Instance.new("Tool")
	tool.Name = "Pickaxe"
	tool:SetAttribute("MiningPickaxeTool", true)
	tool.Parent = CE.Player.Character
	CE.Advance(.1)
	shot(true)
	tool.Activated:Fire()
	CE.Advance(.3) -- Strike.Enter runs .25 s after the click, still inside Cinema's .3 s glide
	eq(calls.StrikeBegin, 0)
	shot(false)
	eq(calls.StrikeBegin, 1, "the skipping click is not lost")
	tool:Destroy()
end)

test("a cinematic that begins during the StrikeBegin round trip: refused, closed, started again after the shot", function()
	reset()
	beginOk = true
	during = function()
		gui:SetAttribute("CinemaActive", true)
	end
	press()
	eq(calls.StrikeBegin, 1)
	eq(Strike.Active, false, "no session under the shot")
	CE.Advance(.1)
	eq(calls.StrikeEnd, 1, "the server session opened by the round trip is closed")
	beginOk = false
	shot(false)
	eq(calls.StrikeBegin, 2, "asked again once the shot is over")
end)

test("a menu opened while waiting: the kept press is refused like any press", function()
	reset()
	shot(true)
	press()
	gui:SetAttribute("OpenMenu", "Shop")
	shot(false)
	eq(calls.StrikeBegin, 0, "no strike while a menu is open")
	gui:SetAttribute("OpenMenu", nil)
	CE.Advance(.1)
end)

print(string.format("halloween_strike_client: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("halloween_strike_client tests failed")
end
