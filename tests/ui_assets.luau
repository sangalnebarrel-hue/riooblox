--!nocheck
--!nolint
-- UISound (cue table, voice pool, buses) and the GameIcons glyph set.
-- lune run tests/ui_assets.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local L = require("./lib/economy_env")

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
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
local function truthy(v, msg)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

-- Every src file, for "already used in this project" checks.
local sources = {}
local function scan(dir)
	for _, entry in ipairs(fs.readDir(dir)) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			scan(path)
		elseif entry:match("%.luau$") then
			sources[path] = fs.readFile(path)
		end
	end
end
scan("src")

-- A player-like object with attributes and synchronous changed signals.
local function fakePlayer()
	local p = { Attributes = {}, Signals = {} }
	function p:GetAttribute(k)
		return self.Attributes[k]
	end
	function p:SetAttribute(k, v)
		self.Attributes[k] = v
		for _, fn in ipairs(self.Signals[k] or {}) do
			fn()
		end
	end
	function p:GetAttributeChangedSignal(k)
		local list = self.Signals[k] or {}
		self.Signals[k] = list
		return { Connect = function(_, fn) table.insert(list, fn); return { Disconnect = function() end } end }
	end
	return p
end

-- A real Instance stands in for SoundService so the buses are real SoundGroups.
local soundService = roblox.Instance.new("Folder")
soundService.Name = "SoundService"
local existing = roblox.Instance.new("Folder")
existing.Name = "DOGROTS_AUDIO"
existing.Parent = soundService
local music = roblox.Instance.new("SoundGroup")
music.Name = "Music"
music.Volume = 0.7
music.Parent = existing
L.Stubs.SoundService = soundService
local player = fakePlayer()
L.Stubs.Players.LocalPlayer = player
L.Stubs.RunService.IsClient = function() return true end

local UISound = L.Require("ReplicatedStorage.UISound")
local REQUIRED = { "Hover", "Press", "Open", "Close", "Tab", "Toggle", "Success", "Error", "Reward", "Coin", "Whoosh", "Pop", "Rare", "Epic", "Legendary", "Countdown", "Lock" }

-- UISOUND ---------------------------------------------------------------------------------------------
test("every cue exists and resolves to a bundled sound this project already uses", function()
	local bundled = {}
	for _, id in ipairs(UISound.Bundled) do
		bundled[id] = true
		local usedElsewhere = false
		for path, text in pairs(sources) do
			if not path:find("UISound.luau", 1, true) and text:find(id, 1, true) then
				usedElsewhere = true
				break
			end
		end
		truthy(usedElsewhere, id .. " is used by another audio module")
	end
	for _, cue in ipairs(REQUIRED) do
		local def = UISound.Cues[cue]
		truthy(def, "cue " .. cue)
		truthy(UISound.AssetIds[cue] ~= nil, "AssetIds has " .. cue)
		local layers = UISound.Layers(cue)
		truthy(#layers >= 1 and #layers <= UISound.MaxVoices, cue .. " layer count")
		for i, layer in ipairs(layers) do
			local label = cue .. " layer " .. i
			truthy(bundled[layer[1]], label .. " asset " .. tostring(layer[1]))
			truthy(layer[2] > 0 and layer[2] <= 1, label .. " volume")
			truthy(layer[3] >= 0.2 and layer[3] <= 4, label .. " pitch")
			truthy((layer[4] or 0) >= 0 and (layer[4] or 0) < 1, label .. " delay")
			truthy((layer[5] or 0) >= 0 and (layer[5] or 0) <= 0.2, label .. " jitter")
		end
		truthy(def.Cooldown >= 0, cue .. " cooldown")
		truthy(def.Priority >= 0 and def.Priority <= 4, cue .. " priority")
		truthy(def.Bus == "UI" or def.Bus == "SFX", cue .. " bus")
	end
	eq(UISound.Cues.Hover.Priority, 0, "hover never cuts another sound off")
	truthy(UISound.Cues.Hover.Cooldown > 0, "hover spam is throttled")
	eq(UISound.Layers("NoSuchCue"), nil)
end)

test("an uploaded asset id replaces the built-in recipe", function()
	UISound.AssetIds.Press = 1234567
	local layers = UISound.Layers("Press")
	eq(#layers, 1)
	eq(layers[1][1], "rbxassetid://1234567")
	UISound.AssetIds.Press = 0
	eq(UISound.Layers("Press")[1][1], "rbxasset://sounds/volume_slider.ogg")
end)

test("voice pool: at most MaxVoices, priorities, reuse", function()
	local now = 0
	local stops = 0
	local made = 0
	local mixer = UISound.Mixer.new({
		Max = 6,
		Clock = function() return now end,
		Create = function()
			made += 1
			return { Stop = function() stops += 1 end }
		end,
	})
	local voices = {}
	for i = 1, 6 do
		now = i * 0.01
		voices[i] = mixer:Take(1, 1)
		truthy(voices[i], "voice " .. i)
	end
	eq(made, 6)
	eq(mixer:Busy(), 6)
	eq(mixer:Take(0, 1), nil, "a hover never cuts a sound off")
	local stolen = mixer:Take(2, 1)
	eq(stolen, voices[1], "a more important cue takes the oldest voice")
	eq(stops, 1)
	eq(mixer:Take(1, 1), voices[2], "equal priority takes the oldest")
	now = 5
	eq(mixer:Busy(), 0)
	truthy(mixer:Take(0, 0.2), "free voices are reused")
	eq(made, 6, "never more than MaxVoices sounds")
end)

test("buses: EnsureGroups creates UI, SFX and Ambient once and keeps Music", function()
	local folder = UISound.EnsureGroups()
	eq(folder, existing)
	for _, name in ipairs({ "UI", "SFX", "Ambient" }) do
		local group = folder:FindFirstChild(name)
		truthy(group and group:IsA("SoundGroup"), name)
	end
	UISound.EnsureGroups()
	eq(#folder:GetChildren(), 4, "idempotent")
	eq(folder:FindFirstChild("Music"), music)
	truthy(math.abs(music.Volume - 0.7) < 1e-4, "existing groups untouched")
end)

test("buses: client volumes follow Setting_UIVolume / Setting_SFXVolume", function()
	player.Attributes.Setting_UIVolume = 0.4
	local ui = UISound.Group("UI")
	truthy(ui, "UI group found")
	eq(math.floor(ui.Volume * 100 + 0.5), 40)
	player:SetAttribute("Setting_UIVolume", 0.8)
	eq(math.floor(ui.Volume * 100 + 0.5), 80, "updates when the setting changes")
	player:SetAttribute("Setting_UIVolume", 7)
	eq(ui.Volume, 1, "clamped")
	local sfx = UISound.Group("SFX")
	eq(sfx.Volume, 1, "missing setting = full volume")
	eq(UISound.Group("Nope"), nil)
end)

test("UISoundOff silences a GUI subtree", function()
	local window = roblox.Instance.new("Frame")
	local inner = roblox.Instance.new("Frame")
	inner.Parent = window
	local button = roblox.Instance.new("TextButton")
	button.Parent = inner
	eq(UISound.Silenced(button), false)
	window:SetAttribute("UISoundOff", true)
	eq(UISound.Silenced(button), true)
	eq(UISound.Play("Press", { From = button }), false, "a silenced subtree plays nothing")
	eq(UISound.Play("NoSuchCue"), false)
end)

-- GAMEICONS -------------------------------------------------------------------------------------------
local Icons = L.Require("ReplicatedStorage.GameIcons")

test("glyphs for rarities, item classes, actions and places", function()
	local Theme
	do
		local env = setmetatable({ Color3 = roblox.Color3, Font = roblox.Font, Enum = roblox.Enum }, { __index = _G })
		local chunk = require("@lune/luau").load(fs.readFile("src/StarterGui/ScreenGui/Modules/Kit/Theme.luau"), { environment = env })
		Theme = chunk()
	end
	for rarity in pairs(Theme.Rarity) do
		truthy(Icons.Glyph(rarity, "Rarity") ~= Icons.GlyphFallback, "rarity " .. rarity)
	end
	local classes = {}
	for _, item in pairs(L.Require("ReplicatedStorage.DogEconomy.ItemDefinitions")) do
		classes[item.Class] = true
	end
	for class in pairs(classes) do
		truthy(Icons.Glyph(class, "Class") ~= Icons.GlyphFallback, "item class " .. class)
	end
	local names = {
		"sell", "favourite", "favorite", "lock", "trade", "showcase", "mutate", "route", "eye", "hide", "settings",
		"filter", "sort", "search", "close", "back", "lab", "shop", "museum", "yard", "mine", "events",
	}
	for _, name in ipairs(names) do
		truthy(Icons.Glyph(name) ~= Icons.GlyphFallback, "glyph " .. name)
	end
	truthy(Icons.Glyph("Secret") ~= Icons.Glyph("Secret", "Class"), "a group picks between rarity and class")
	eq(Icons.Glyph("Secret"), Icons.Glyphs.Action.Secret or Icons.Glyphs.Rarity.Secret)
	eq(Icons.Glyph(nil), Icons.GlyphFallback)
	eq(Icons.Glyph(""), Icons.GlyphFallback)
	eq(Icons.Glyph("NoSuchIcon"), Icons.GlyphFallback)
	eq(Icons.Glyph(42), Icons.GlyphFallback)
	for group, glyphs in pairs(Icons.Glyphs) do
		for name, glyph in pairs(glyphs) do
			local length = utf8.len(glyph)
			truthy(length and length >= 1 and length <= 3, group .. "." .. name .. " is one short symbol")
		end
	end
end)

test("existing GameIcons exports are intact", function()
	truthy(#Icons.Keys >= 20)
	eq(Icons.Resolve("Coins"), "rbxassetid://139025872961174")
	eq(Icons.Resolve("Ticket"), "rbxassetid://105854491216231", "aliases still resolve")
	eq(Icons.FallbackKey("Settings"), "Lab")
	eq(Icons.AssetUrl(5), "rbxassetid://5")
	local applied = Icons.Apply({})
	eq(applied.Coins, "rbxassetid://139025872961174")
	eq(type(Icons.Preload), "function")
end)

print(string.format("ui_assets: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("ui_assets tests failed")
end
