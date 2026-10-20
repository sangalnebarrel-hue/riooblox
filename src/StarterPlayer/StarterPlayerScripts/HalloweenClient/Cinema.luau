-- CINEMA (StarterPlayerScripts.HalloweenClient.Cinema): the one cinematic runner every presentation shares
-- (docs/halloween2/DESIGN.md §16.2): the church reveal, seal clears, the portal, the coffin, the finale, tutorial
-- camera focus. Works without the Halloween event too (require it by path; Start(ctx) is optional).
--
--   Cinema.Play{ Id, Duration, Shot = fn(t, dt) -> CFrame?, Fov = number | fn(t) -> number?,
--                Focus = {Distance? | Target = Vector3?, Radius?, Far?, Near?} | fn(t) -> that?,
--                Letterbox = true, Skippable = true, SkipAfter = .5, LockControls = true, HideUI = true,
--                Duck = "Cinematic" (AudioMixer preset / levels table / false), BlendIn = .9, BlendOut = .8,
--                Timeline = {{t, fn(handle), Always = bool?}}, OnSkip = fn(handle), OnDone = fn(ok, reason, handle),
--                Force = bool (ignore menus / mining / camera type), Preempt = bool (cancel a running cinematic),
--                CutEvery = 1.6 (ReducedMotion: seconds per static cut) }
--     -> handle {Id, Done (signal: Connect / Once / Wait -> ok, reason), Cancel(), Skip(), Elapsed(), Running(),
--                StartCFrame, Camera} | nil, refusal reason
--     A cinematic refuses (returns nil and calls OnDone(false, reason)) when another runs ("Busy"), the camera is not
--     Custom ("Camera"), a timing-hit session is active ("Mining"), a menu / Kit window is open ("Menu") or the
--     character is dead ("Dead") — unless Force. OnDone(ok, reason) runs exactly once: ok = the beat was presented
--     ("Done" at its end, "Skipped" by the player, "Menu" when a menu opened mid-shot: OnSkip ran), false for
--     "Cancelled" / "Error" / "Died" / "Character". Shot = nil keeps the player's own camera (letterbox, lock, duck only).
--     Timeline entries fire in order (pcall'd); on a skip the remaining ones with Always = true still fire.
--     ReducedMotion: no blends, static cuts (the shot sampled every CutEvery seconds), no shake / impulse, half flashes.
--   Cinema.Busy() -> bool, id ; Cinema.Current() -> handle? ; Cinema.Cancel(reason?)
--   Cinema.LockControls(reason) / Cinema.Unlock(reason) (= UnlockControls) ; Cinema.Locked() -> bool
--     Ref-counted. Movement is sunk through ContextActionService and the PlayerModule controls are disabled only when
--     no menu owns them: it never disables while GUIIntegration has a menu open and never re-enables what it did not
--     disable (a release during a menu waits for the menu to close).
--   Cinema.HideUI(reason) / Cinema.ShowUI(reason)   ref-counted interface hiding (main ScreenGui + HUD-like layers +
--                                                   any ScreenGui with HideWithUI / CinemaHide; CinemaKeep opts out)
--   Cinema.Shake(amount, dur) · Cinema.Impulse(strength, dir?) · Cinema.Flash(color?, strength?, dur?)
--   Cinema.Fade(alpha, dur?, {Color, MaxHold}) · Cinema.Title(en, ru, opts) -> {Hide(fade?)}
--     Title opts {Sub = {en, ru}, Duration = 3.4, Delay, Color, SubColor, Size = "Huge"|"Large"|"Medium",
--     Position = "Center"|"Lower"|"Upper"}
--   Shot helpers (pure, return a Shot): Cinema.Dolly(fromCF, toCF, t1?, t0?), Cinema.Orbit(center, radius, height, a0,
--     a1, duration, lookOffset?), Cinema.Path({{t, CFrame}, ...}), Cinema.LookAt(from, to) -> CFrame, Cinema.Smooth(x)
-- Exception safety: everything a cinematic builds registers its undo first; error, death, character removal, Cancel,
-- a menu opening or the end all run the same teardown (camera Custom + subject + FOV, controls, UI, duck, DoF, bars,
-- the main gui attribute CinemaActive). Nothing Cinema shows is input-sinking (bars, fades, titles are inactive
-- frames), and a Fade left dark is cleared by its MaxHold watchdog.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Cinema = {}
Cinema.RenderName = "DOGROTS_Cinema"
Cinema.Priority = Enum.RenderPriority.Camera.Value + 1
Cinema.LetterboxScale = .11
Cinema.DisplayOrder = 90 -- letterbox; the fade / flash / title overlay sits one above

local ctx: any = nil
local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local C3 = Color3.fromRGB

---------------------------------------------------------------------------------------------------------------------
-- small helpers
---------------------------------------------------------------------------------------------------------------------
local warned = {}
local function warnOnce(key: string, msg: string)
	if not warned[key] then
		warned[key] = true
		warn("Cinema: " .. msg)
	end
end

local sharedMod: any = nil
local function shared(): any
	if sharedMod == nil then
		local ok, m = pcall(function()
			return (ctx and ctx.Shared) or require(RS:WaitForChild("Halloween", 5):WaitForChild("Shared", 5) :: ModuleScript)
		end)
		sharedMod = ok and m or false
	end
	return sharedMod or nil
end
local fxMod: any = nil
local function fx(): any
	if fxMod == nil then
		local ok, m = pcall(function()
			return (ctx and ctx.FX) or require(RS:WaitForChild("Halloween", 5):WaitForChild("FX", 5) :: ModuleScript)
		end)
		fxMod = ok and m or false
	end
	return fxMod or nil
end
local mixerMod: any = nil
local function mixer(): any
	if mixerMod == nil then
		local ok, m = pcall(function()
			return require(RS:WaitForChild("AudioMixer", 5) :: ModuleScript)
		end)
		mixerMod = ok and type(m) == "table" and m or false
	end
	return mixerMod or nil
end

local function L(en: string, ru: string?): string
	local s = shared()
	if s and s.L then
		return s.L(en, ru)
	end
	return en
end
local function reducedMotion(): boolean
	local s = shared()
	if s and s.ReducedMotion then
		local ok, v = pcall(s.ReducedMotion)
		if ok and v then
			return true
		end
	end
	return player ~= nil and player:GetAttribute("ReducedMotion") == true
end
local function quality(): string
	local s = shared()
	if s and s.Quality then
		local ok, q = pcall(s.Quality)
		if ok and type(q) == "string" then
			return q
		end
	end
	return "High"
end
local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local function tween(inst: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(inst, TweenInfo.new(math.max(0, seconds), style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goals)
	tw:Play()
	return tw
end
local function playerGui(): PlayerGui?
	return player and player:FindFirstChildOfClass("PlayerGui")
end
local function mainGui(): ScreenGui?
	local pg = playerGui()
	local g = pg and pg:FindFirstChild("ScreenGui")
	return (g and g:IsA("ScreenGui")) and g or nil
end
local function menuOpen(): boolean
	local g = mainGui()
	return g ~= nil and (g:GetAttribute("OpenMenu") ~= nil or (tonumber(g:GetAttribute("ModalOwnerCount")) or 0) > 0)
end
local function miningActive(): boolean
	local g = mainGui()
	return g ~= nil and g:GetAttribute("MiningActive") == true
end
local function humanoid(): Humanoid?
	local c = player and player.Character
	return c and c:FindFirstChildOfClass("Humanoid") or nil
end

-- tiny signal: Connect / Once / Wait; firing twice is ignored; a late Wait returns at once
local function newSignal()
	local sig: any = { _fns = {}, _waiting = {}, _fired = nil }
	function sig:Connect(fn)
		local entry = { Fn = fn, Live = true }
		table.insert(self._fns, entry)
		local conn = { Connected = true }
		function conn:Disconnect()
			entry.Live = false
			self.Connected = false
		end
		if self._fired then
			task.spawn(fn, table.unpack(self._fired, 1, self._fired.n))
		end
		return conn
	end
	function sig:Once(fn)
		local conn
		local done = false
		conn = self:Connect(function(...)
			if done then
				return
			end
			done = true
			if conn then
				conn:Disconnect()
			end
			fn(...)
		end)
		return conn
	end
	function sig:Wait()
		if self._fired then
			return table.unpack(self._fired, 1, self._fired.n)
		end
		table.insert(self._waiting, coroutine.running())
		return coroutine.yield()
	end
	function sig:_Fire(...)
		if self._fired then
			return
		end
		self._fired = table.pack(...)
		for _, e in ipairs(self._fns) do
			if e.Live then
				task.spawn(e.Fn, ...)
			end
		end
		for _, th in ipairs(self._waiting) do
			task.spawn(th, ...)
		end
		table.clear(self._waiting)
	end
	return sig
end

---------------------------------------------------------------------------------------------------------------------
-- control lock (ref-counted, cooperative with GUIIntegration)
---------------------------------------------------------------------------------------------------------------------
local SINK = "DOGROTS_CinemaLock"
local locks: { [string]: number } = {}
local controls: any = nil
local controlsTried = false
local ownDisable = false
local sinkBound = false
local menuWatch: RBXScriptConnection? = nil
local syncControls: () -> ()

local function getControls(): any
	if controls or controlsTried then
		return controls
	end
	controlsTried = true
	local ok, c = pcall(function()
		local ps = player:WaitForChild("PlayerScripts", 5)
		local pm = ps and ps:WaitForChild("PlayerModule", 5)
		return pm and require(pm :: ModuleScript):GetControls()
	end)
	controls = ok and c or nil
	return controls
end

local function watchMenus()
	if menuWatch then
		return
	end
	local g = mainGui()
	if not g then
		return
	end
	local function changed()
		pcall(syncControls)
	end
	-- a single combined watcher: OpenMenu / ModalOwnerCount both mean "a menu owns the controls"
	menuWatch = g.AttributeChanged:Connect(function(name)
		if name == "OpenMenu" or name == "ModalOwnerCount" then
			task.defer(changed)
		end
	end)
end

syncControls = function()
	local want = next(locks) ~= nil
	local c = getControls()
	if want then
		if not sinkBound then
			sinkBound = true
			ContextActionService:BindActionAtPriority(SINK, function()
				return Enum.ContextActionResult.Sink
			end, false, 3000, Enum.PlayerActions.CharacterForward, Enum.PlayerActions.CharacterBackward,
				Enum.PlayerActions.CharacterLeft, Enum.PlayerActions.CharacterRight, Enum.PlayerActions.CharacterJump,
				Enum.KeyCode.Thumbstick1, Enum.KeyCode.ButtonA)
		end
		-- only take the PlayerModule controls when no menu owns them (GUIIntegration disables / enables its own)
		if c and not ownDisable and not menuOpen() and c.controlsEnabled ~= false then
			c:Disable()
			ownDisable = true
		end
		watchMenus()
	else
		if sinkBound then
			sinkBound = false
			ContextActionService:UnbindAction(SINK)
		end
		-- give back only what we took, and never while a menu holds them (its close re-runs this)
		if ownDisable and c and not menuOpen() then
			ownDisable = false
			c:Enable()
		end
		if not ownDisable and menuWatch then
			menuWatch:Disconnect()
			menuWatch = nil
		end
	end
end

function Cinema.LockControls(reason: string?)
	local key = tostring(reason or "Cinema")
	locks[key] = (locks[key] or 0) + 1
	local ok, err = pcall(syncControls)
	if not ok then
		warnOnce("lock", tostring(err))
	end
end

function Cinema.Unlock(reason: string?)
	local key = tostring(reason or "Cinema")
	local n = locks[key]
	if not n then
		return
	end
	locks[key] = n > 1 and n - 1 or nil
	local ok, err = pcall(syncControls)
	if not ok then
		warnOnce("unlock", tostring(err))
	end
end
Cinema.UnlockControls = Cinema.Unlock

function Cinema.Locked(): boolean
	return next(locks) ~= nil
end

---------------------------------------------------------------------------------------------------------------------
-- hiding the interface (ref-counted; a layer a script enables meanwhile is noted and stays off until the release)
---------------------------------------------------------------------------------------------------------------------
local LAYERS = { MiningGui = true, MiningToast = true, KitOverlay = true, DOGROTS_LuckyArrivalBanner = true }
local hideReasons: { [string]: number } = {}
local held: { [Instance]: any } = {}

local function hideable(g: Instance): boolean
	if not g:IsA("LayerCollector") or g:GetAttribute("CinemaKeep") == true then
		return false
	end
	return g.Name == "ScreenGui" or LAYERS[g.Name] == true or g:GetAttribute("HideWithUI") == true or g:GetAttribute("CinemaHide") == true
end

-- transparency fade of the VISIBLE part of a subtree (hidden pages are skipped; restored exactly once the layer is off)
local function collect(root: Instance, cap: number): { any }
	local list = {}
	local function add(o: Instance): boolean
		local props: { [string]: number } = {}
		if o:IsA("GuiObject") then
			if not o.Visible then
				return false -- nothing of it shows: skip the whole subtree
			end
			props.BackgroundTransparency = o.BackgroundTransparency
			if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
				props.TextTransparency = (o :: any).TextTransparency
				props.TextStrokeTransparency = (o :: any).TextStrokeTransparency
			elseif o:IsA("ImageLabel") or o:IsA("ImageButton") then
				props.ImageTransparency = (o :: any).ImageTransparency
			end
		elseif o:IsA("UIStroke") then
			props.Transparency = o.Transparency
		else
			return o:IsA("Folder") or o:IsA("LayerCollector")
		end
		table.insert(list, { Object = o, Props = props })
		return true
	end
	local function walk(node: Instance)
		for _, d in ipairs(node:GetChildren()) do
			if #list >= cap then
				return
			end
			if add(d) then
				walk(d)
			end
		end
	end
	walk(root)
	return list
end
local function applyFade(list: { any }, alpha: number)
	for _, e in ipairs(list) do
		local o: any = e.Object
		if o.Parent then
			for prop, home in pairs(e.Props) do
				o[prop] = home + (1 - home) * alpha
			end
		end
	end
end
-- one interface fade at a time; starting another first FINISHES the running one (its end puts the real transparencies
-- back), so a new fade never mistakes half-faded values for the real ones
local currentFade: any = nil
local function stopFade()
	local f = currentFade
	if f then
		currentFade = nil
		f.Conn:Disconnect()
		if f.Done then
			pcall(f.Done)
		end
	end
end
local function runFade(list: { any }, from: number, to: number, seconds: number, done: (() -> ())?)
	stopFade()
	local t0 = os.clock()
	local rec: any = { Done = done }
	rec.Conn = RunService.Heartbeat:Connect(function()
		local k = math.clamp((os.clock() - t0) / math.max(.01, seconds), 0, 1)
		local ok = pcall(applyFade, list, from + (to - from) * k)
		if k >= 1 or not ok then
			if currentFade == rec then
				currentFade = nil
			end
			rec.Conn:Disconnect()
			if done then
				pcall(done)
			end
		end
	end)
	currentFade = rec
end

local function hold(g: LayerCollector, fade: boolean)
	if held[g] then
		return
	end
	local rec: any = { Wanted = g.Enabled }
	held[g] = rec
	rec.Conn = g:GetPropertyChangedSignal("Enabled"):Connect(function()
		if held[g] == rec and g.Enabled then
			rec.Wanted = true
			g.Enabled = false
		end
	end)
	if not rec.Wanted then
		return
	end
	if fade and not reducedMotion() then
		stopFade()
		local list = collect(g, 400)
		runFade(list, 0, 1, .25, function()
			if held[g] == rec then
				g.Enabled = false
			end
			applyFade(list, 0)
		end)
	else
		g.Enabled = false
	end
end
local function release(g: LayerCollector, fade: boolean)
	local rec = held[g]
	if not rec then
		return
	end
	held[g] = nil
	rec.Conn:Disconnect()
	if not rec.Wanted or not g.Parent then
		return
	end
	if fade and not reducedMotion() then
		stopFade()
		local list = collect(g, 400)
		applyFade(list, 1)
		g.Enabled = true
		runFade(list, 1, 0, .3, function()
			applyFade(list, 0)
		end)
	else
		g.Enabled = true
	end
end
local function syncUI(fade: boolean)
	local pg = playerGui()
	if not pg then
		return
	end
	if next(hideReasons) ~= nil then
		for _, g in ipairs(pg:GetChildren()) do
			if hideable(g) then
				hold(g :: LayerCollector, fade and g.Name == "ScreenGui")
			end
		end
	else
		for g in pairs(held) do
			release(g :: LayerCollector, fade and g.Name == "ScreenGui")
		end
	end
end

function Cinema.HideUI(reason: string?)
	local key = tostring(reason or "Cinema")
	hideReasons[key] = (hideReasons[key] or 0) + 1
	local ok, err = pcall(syncUI, true)
	if not ok then
		warnOnce("hide", tostring(err))
	end
end
function Cinema.ShowUI(reason: string?)
	local key = tostring(reason or "Cinema")
	local n = hideReasons[key]
	if not n then
		return
	end
	hideReasons[key] = n > 1 and n - 1 or nil
	local ok, err = pcall(syncUI, true)
	if not ok then
		warnOnce("show", tostring(err))
	end
end

---------------------------------------------------------------------------------------------------------------------
-- overlay: fade / flash / title (one persistent, never input-sinking ScreenGui above the letterbox)
---------------------------------------------------------------------------------------------------------------------
local overlay: ScreenGui? = nil
local fadeFrame: Frame? = nil
local function getOverlay(): ScreenGui?
	if overlay and overlay.Parent then
		return overlay
	end
	local pg = playerGui()
	if not pg then
		return nil
	end
	local g = Instance.new("ScreenGui")
	g.Name = "DOGROTS_CinemaOverlay"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = Cinema.DisplayOrder + 1
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g:SetAttribute("NoTranslate", true)
	g:SetAttribute("CinemaKeep", true)
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.None
	end)
	local f = Instance.new("Frame")
	f.Name = "Fade"
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 1
	f.Active = false
	f.ZIndex = 1
	f.Parent = g
	fadeFrame = f
	g.Parent = pg
	overlay = g
	return g
end

local fadeHold = 0
function Cinema.Fade(alpha: number, dur: number?, opts: { [string]: any }?)
	local ok, err = pcall(function()
		local g = getOverlay()
		local f = fadeFrame
		if not g or not f then
			return
		end
		local o = opts or {}
		local a = math.clamp(tonumber(alpha) or 0, 0, 1)
		if o.Color then
			f.BackgroundColor3 = o.Color
		end
		tween(f, dur or .5, { BackgroundTransparency = 1 - a }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		fadeHold += 1
		local my = fadeHold
		if a > 0 then
			-- watchdog: a fade nobody lifts again is lifted after MaxHold (never a permanent black screen)
			local maxHold = tonumber(o.MaxHold) or 12
			task.delay((dur or .5) + maxHold, function()
				if fadeHold == my and f.Parent and f.BackgroundTransparency < .999 then
					tween(f, .6, { BackgroundTransparency = 1 })
				end
			end)
		end
	end)
	if not ok then
		warnOnce("fade", tostring(err))
	end
end

function Cinema.Flash(color: Color3?, strength: number?, dur: number?)
	pcall(function()
		local g = getOverlay()
		if not g then
			return
		end
		local s = math.clamp(strength or .6, 0, 1)
		if reducedMotion() then
			s *= .5
		end
		local f = Instance.new("Frame")
		f.Name = "Flash"
		f.Size = UDim2.fromScale(1, 1)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color or Color3.new(1, 1, 1)
		f.BackgroundTransparency = 1 - s
		f.Active = false
		f.ZIndex = 20
		f.Parent = g
		tween(f, dur or .4, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay((dur or .4) + .1, function()
			f:Destroy()
		end)
	end)
end

local SIZES = { Huge = { 76, 40 }, Large = { 58, 32 }, Medium = { 42, 26 } }
function Cinema.Title(en: string, ru: string?, opts: { [string]: any }?)
	local o = opts or {}
	local handle: any = { Alive = true }
	local frame: Frame? = nil
	function handle.Hide(fade: number?)
		if not handle.Alive then
			return
		end
		handle.Alive = false
		local f = frame
		if not f then
			return
		end
		local t = fade or .7
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("TextLabel") then
				tween(d, t, { TextTransparency = 1, TextStrokeTransparency = 1 })
			elseif d:IsA("Frame") then
				tween(d, t, { BackgroundTransparency = 1 })
			elseif d:IsA("UIStroke") then
				tween(d, t, { Transparency = 1 })
			end
		end
		task.delay(t + .1, function()
			f:Destroy()
		end)
	end
	local ok, err = pcall(function()
		local g = getOverlay()
		if not g then
			return
		end
		local size = SIZES[o.Size or "Huge"] or SIZES.Huge
		local pos = ({ Center = .46, Lower = .72, Upper = .24 })[o.Position or "Center"] or .46
		local f = Instance.new("Frame")
		f.Name = "Title"
		f.AnchorPoint = Vector2.new(.5, .5)
		f.Position = UDim2.fromScale(.5, pos)
		f.Size = UDim2.new(.9, 0, 0, size[1] + size[2] + 34)
		f.BackgroundTransparency = 1
		f.Active = false
		f.ZIndex = 10
		f.Parent = g
		frame = f
		local scale = Instance.new("UIScale")
		scale.Scale = reducedMotion() and 1 or 1.08
		scale.Parent = f
		local main = Instance.new("TextLabel")
		main.Name = "Main"
		main.BackgroundTransparency = 1
		main.Size = UDim2.new(1, 0, 0, size[1])
		main.FontFace = FONT
		main.Text = L(en, ru)
		main.TextScaled = true
		main.TextColor3 = o.Color or C3(230, 222, 200)
		main.TextTransparency = 1
		main.TextStrokeTransparency = 1
		main.ZIndex = 11
		main:SetAttribute("NoTranslate", true)
		main.Parent = f
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = size[1]
		limit.MinTextSize = 18
		limit.Parent = main
		local stroke = Instance.new("UIStroke")
		stroke.Color = C3(16, 12, 26)
		stroke.Thickness = 3
		stroke.Transparency = 1
		stroke.Parent = main
		local line = Instance.new("Frame")
		line.Name = "Line"
		line.AnchorPoint = Vector2.new(.5, .5)
		line.Position = UDim2.new(.5, 0, 0, size[1] + 12)
		line.Size = UDim2.new(0, 0, 0, 2)
		line.BorderSizePixel = 0
		line.BackgroundColor3 = o.SubColor or C3(150, 200, 255)
		line.BackgroundTransparency = 1
		line.ZIndex = 11
		line.Parent = f
		local sub: TextLabel? = nil
		if type(o.Sub) == "table" or type(o.Sub) == "string" then
			local s = Instance.new("TextLabel")
			s.Name = "Sub"
			s.BackgroundTransparency = 1
			s.Position = UDim2.new(0, 0, 0, size[1] + 22)
			s.Size = UDim2.new(1, 0, 0, size[2])
			s.FontFace = FONT
			s.Text = type(o.Sub) == "table" and L(o.Sub[1], o.Sub[2]) or tostring(o.Sub)
			s.TextScaled = true
			s.TextColor3 = o.SubColor or C3(150, 200, 255)
			s.TextTransparency = 1
			s.TextStrokeTransparency = 1
			s.ZIndex = 11
			s:SetAttribute("NoTranslate", true)
			s.Parent = f
			local sl = Instance.new("UITextSizeConstraint")
			sl.MaxTextSize = size[2]
			sl.MinTextSize = 12
			sl.Parent = s
			local ss = Instance.new("UIStroke")
			ss.Color = C3(16, 12, 26)
			ss.Thickness = 2
			ss.Transparency = 1
			ss.Parent = s
			sub = s
		end
		local delay = tonumber(o.Delay) or 0
		task.delay(delay, function()
			if not handle.Alive or not f.Parent then
				return
			end
			tween(scale, .9, { Scale = 1 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			tween(main, .6, { TextTransparency = 0, TextStrokeTransparency = .35 })
			tween(stroke, .6, { Transparency = .2 })
			tween(line, .9, { Size = UDim2.new(.42, 0, 0, 2), BackgroundTransparency = .25 }, Enum.EasingStyle.Quint)
			if sub then
				task.delay(.35, function()
					if handle.Alive and sub.Parent then
						tween(sub, .6, { TextTransparency = 0, TextStrokeTransparency = .5 })
						local st = sub:FindFirstChildOfClass("UIStroke")
						if st then
							tween(st, .6, { Transparency = .3 })
						end
					end
				end)
			end
			local hold = tonumber(o.Duration) or 3.4
			if hold > 0 then
				task.delay(hold, function()
					handle.Hide(.8)
				end)
			end
		end)
	end)
	if not ok then
		warnOnce("title", tostring(err))
		handle.Hide(0)
	end
	return handle
end

---------------------------------------------------------------------------------------------------------------------
-- shake / impulse
---------------------------------------------------------------------------------------------------------------------
function Cinema.Shake(amount: number?, dur: number?)
	if reducedMotion() then
		return
	end
	local f = fx()
	if f and f.Shake then
		pcall(f.Shake, amount, dur)
	end
end

-- a short directional camera kick (a pitch-up recoil and a push), decaying over ~.32 s, plus a small FOV punch. Applied
-- as an offset after the camera writers (Camera+2); our last offset is taken back first when nobody rewrote the camera.
local impulse: any = nil
function Cinema.Impulse(strength: number?, dir: Vector3?)
	if reducedMotion() then
		return
	end
	local s = math.clamp(tonumber(strength) or 1, 0, 2.5)
	if s <= 0 then
		return
	end
	local running = impulse ~= nil
	impulse = { T0 = os.clock(), S = s, Dir = dir, Last = impulse and impulse.Last, Written = impulse and impulse.Written }
	local f = fx()
	if f and f.Punch then
		pcall(f.Punch, math.min(1.6, s * .6))
	end
	if running then
		return
	end
	RunService:BindToRenderStep("DOGROTS_CinemaImpulse", Enum.RenderPriority.Camera.Value + 2, function()
		local p = impulse
		local cam = workspace.CurrentCamera
		if not p or not cam then
			impulse = nil
			RunService:UnbindFromRenderStep("DOGROTS_CinemaImpulse")
			return
		end
		local base = cam.CFrame
		if p.Written and p.Last and base == p.Written then
			base = base * p.Last:Inverse()
		end
		local e = (os.clock() - p.T0) / .32
		if e >= 1 then
			cam.CFrame = base
			impulse = nil
			RunService:UnbindFromRenderStep("DOGROTS_CinemaImpulse")
			return
		end
		-- a fast attack then a damped settle
		local k = (e < .12 and e / .12 or (1 - (e - .12) / .88) ^ 2) * p.S
		local side = 0
		if p.Dir then
			local local3 = base:VectorToObjectSpace(p.Dir)
			side = math.clamp(local3.X, -1, 1)
		end
		local offset = CFrame.new(side * .12 * k, -.06 * k, .22 * k) * CFrame.Angles(math.rad(1.6) * k, 0, math.rad(-side * 1.2) * k)
		local cf = base * offset
		cam.CFrame = cf
		p.Last, p.Written = offset, cf
	end)
end

---------------------------------------------------------------------------------------------------------------------
-- shot helpers (pure: they return Shot functions for Cinema.Play)
---------------------------------------------------------------------------------------------------------------------
Cinema.Smooth = smooth

-- a camera at `from` looking at `to`, safe when the direction is (almost) vertical
function Cinema.LookAt(from: Vector3, to: Vector3): CFrame
	local d = to - from
	if d.Magnitude < 1e-4 then
		return CFrame.new(from)
	end
	local up = math.abs(d.Unit.Y) > .99 and Vector3.zAxis or Vector3.yAxis
	return CFrame.lookAt(from, to, up)
end

-- a straight move from one framing to another over [t0, t1] (smoothstep), holding before / after
function Cinema.Dolly(fromCF: CFrame, toCF: CFrame, t1: number?, t0: number?): (number) -> CFrame
	local a, b = t0 or 0, math.max((t0 or 0) + .01, t1 or 1)
	return function(t: number): CFrame
		return fromCF:Lerp(toCF, smooth((t - a) / (b - a)))
	end
end

-- an orbit around `center` from angle a0 to a1 (radians, 0 = +X, counter-clockwise seen from above) over `duration`
-- seconds at `radius` / `height`, looking at center + lookOffset
function Cinema.Orbit(center: Vector3, radius: number, height: number, a0: number, a1: number, duration: number,
	lookOffset: Vector3?): (number) -> CFrame
	local target = center + (lookOffset or Vector3.zero)
	return function(t: number): CFrame
		local a = a0 + (a1 - a0) * smooth(t / math.max(.01, duration))
		local pos = center + Vector3.new(math.cos(a) * radius, height, math.sin(a) * radius)
		return Cinema.LookAt(pos, target)
	end
end

-- keyframes {{t, CFrame}, ...} (sorted or not): smoothstep between neighbours, held at both ends
function Cinema.Path(keys: { { any } }): (number) -> CFrame
	local list = table.clone(keys)
	table.sort(list, function(a, b)
		return a[1] < b[1]
	end)
	return function(t: number): CFrame
		if t <= list[1][1] then
			return list[1][2]
		end
		for i = 1, #list - 1 do
			local a, b = list[i], list[i + 1]
			if t <= b[1] then
				return a[2]:Lerp(b[2], smooth((t - a[1]) / math.max(.001, b[1] - a[1])))
			end
		end
		return list[#list][2]
	end
end

---------------------------------------------------------------------------------------------------------------------
-- the cinematic runner
---------------------------------------------------------------------------------------------------------------------
local active: any = nil

function Cinema.Busy(): (boolean, string?)
	return active ~= nil, active and active.Id or nil
end
function Cinema.Current(): any
	return active
end
function Cinema.Cancel(reason: string?)
	local a = active
	if a then
		a.Finish(false, reason or "Cancelled")
	end
end

-- why a cinematic may not start now (nil = it may)
function Cinema.Blocked(opts: { [string]: any }?): string?
	local o = opts or {}
	if active and not o.Preempt then
		return "Busy"
	end
	local h = humanoid()
	if o.LockControls ~= false and h and h.Health <= 0 then
		return "Dead"
	end
	if o.Force then
		return nil
	end
	local cam = workspace.CurrentCamera
	if o.Shot ~= nil and (not cam or cam.CameraType ~= Enum.CameraType.Custom) then
		return "Camera"
	end
	if miningActive() then
		return "Mining"
	end
	if menuOpen() then
		return "Menu"
	end
	return nil
end

local function letterbox(run: any)
	local pg = playerGui()
	if not pg then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "DOGROTS_Cinema"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = Cinema.DisplayOrder
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g:SetAttribute("NoTranslate", true)
	g:SetAttribute("CinemaKeep", true)
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.None
	end)
	local bars = {}
	for i, y in ipairs({ 0, 1 }) do
		local b = Instance.new("Frame")
		b.Name = i == 1 and "Top" or "Bottom"
		b.BorderSizePixel = 0
		b.BackgroundColor3 = Color3.new(0, 0, 0)
		b.AnchorPoint = Vector2.new(0, y)
		b.Position = UDim2.fromScale(0, y)
		b.Size = UDim2.fromScale(1, 0)
		b.Active = false
		b.Parent = g
		bars[i] = b
	end
	local skip = Instance.new("TextLabel")
	skip.Name = "Skip"
	skip.BackgroundTransparency = 1
	skip.FontFace = FONT
	skip.TextColor3 = C3(200, 190, 230)
	skip.TextTransparency = 1
	skip.TextScaled = true
	skip.TextXAlignment = Enum.TextXAlignment.Right
	skip:SetAttribute("NoTranslate", true)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local pad = UserInputService.GamepadEnabled and not touch and not UserInputService.MouseEnabled
	skip.Text = touch and L("TAP TO SKIP", "НАЖМИ, ЧТОБЫ ПРОПУСТИТЬ")
		or pad and L("PRESS (A) TO SKIP", "НАЖМИ (A), ЧТОБЫ ПРОПУСТИТЬ")
		or L("CLICK OR PRESS A KEY TO SKIP", "КЛИКНИ ИЛИ НАЖМИ КЛАВИШУ, ЧТОБЫ ПРОПУСТИТЬ")
	skip.AnchorPoint = Vector2.new(1, .5)
	skip.Position = UDim2.new(1, -20, .5, 0)
	skip.Size = UDim2.new(.6, 0, .36, 0)
	skip.Parent = bars[2]
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = 20
	limit.MinTextSize = 10
	limit.Parent = skip
	g.Parent = pg
	run.Bars, run.SkipLabel, run.Letterbox = bars, skip, g
	for _, b in ipairs(bars) do
		tween(b, .45, { Size = UDim2.fromScale(1, Cinema.LetterboxScale) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
	table.insert(run.Undo, function()
		for _, b in ipairs(bars) do
			if b.Parent then
				tween(b, .4, { Size = UDim2.fromScale(1, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end
		if skip.Parent then
			tween(skip, .2, { TextTransparency = 1 })
		end
		task.delay(.45, function()
			g:Destroy()
		end)
	end)
end

local function depthOfField(run: any, cam: Camera)
	if quality() == "Low" then
		return
	end
	local mining = Lighting:FindFirstChild("DOGROTS_MiningFocus")
	if mining and mining:IsA("DepthOfFieldEffect") and mining.Enabled then
		mining.Enabled = false
		table.insert(run.Undo, function()
			if mining.Parent then
				mining.Enabled = true
			end
		end)
	end
	local old = cam:FindFirstChild("DOGROTS_CinemaFocus")
	if old then
		old:Destroy()
	end
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "DOGROTS_CinemaFocus"
	dof.FarIntensity = 0
	dof.NearIntensity = 0
	dof.FocusDistance = 40
	dof.InFocusRadius = 30
	dof.Parent = cam
	run.DoF = dof
	table.insert(run.Undo, function()
		if dof.Parent then
			tween(dof, .4, { FarIntensity = 0, NearIntensity = 0 })
			task.delay(.45, function()
				dof:Destroy()
			end)
		end
	end)
end

local function applyFocus(run: any, cam: Camera, t: number, k: number)
	local dof = run.DoF
	local focus = run.Opts.Focus
	if not dof or not focus then
		return
	end
	if type(focus) == "function" then
		local ok, f = pcall(focus, t)
		focus = ok and f or nil
	end
	if type(focus) ~= "table" then
		return
	end
	local dist = tonumber(focus.Distance)
	if not dist and typeof(focus.Target) == "Vector3" then
		dist = (cam.CFrame.Position - focus.Target).Magnitude
	end
	dof.FocusDistance = math.clamp(dist or 40, 0, 200)
	dof.InFocusRadius = math.clamp(tonumber(focus.Radius) or 14, 0, 50)
	dof.FarIntensity = math.clamp((tonumber(focus.Far) or .35) * k, 0, 1)
	dof.NearIntensity = math.clamp((tonumber(focus.Near) or .1) * k, 0, 1)
end

function Cinema.Play(opts: { [string]: any }): (any, string?)
	local o = type(opts) == "table" and opts or {}
	local id = tostring(o.Id or "Cinema")
	if active and o.Preempt then
		active.Finish(false, "Cancelled")
	end
	local blocked = Cinema.Blocked(o)
	if blocked then
		if type(o.OnDone) == "function" then
			task.spawn(pcall, o.OnDone, false, blocked, nil)
		end
		return nil, blocked
	end
	local duration = math.max(.1, tonumber(o.Duration) or 4)
	local rm = reducedMotion()
	local run: any = {
		Id = id, Opts = o, Undo = {}, Finished = false, Done = newSignal(), StartedAt = os.clock(), Duration = duration,
		Timeline = {}, Next = 1, Skippable = o.Skippable ~= false, SkipAfter = tonumber(o.SkipAfter) or .5,
		Reduced = rm, Returning = nil,
	}
	local handle: any = run
	active = run

	-- teardown: every undo newest first, each protected; runs once
	local function teardown()
		for i = #run.Undo, 1, -1 do
			local ok, err = pcall(run.Undo[i])
			if not ok then
				warnOnce("undo" .. i, tostring(err))
			end
		end
		table.clear(run.Undo)
	end
	local function finish(ok: boolean, reason: string)
		if run.Finished then
			return
		end
		run.Finished = true
		run.Reason = reason
		if active == run then
			active = nil
		end
		teardown()
		if type(o.OnDone) == "function" then
			local okCall, err = pcall(o.OnDone, ok, reason, handle)
			if not okCall then
				warnOnce("ondone" .. id, tostring(err))
			end
		end
		run.Done:_Fire(ok, reason)
	end
	run.Finish = finish

	local function skip(reason: string)
		if run.Finished or run.Returning then
			return
		end
		if type(o.OnSkip) == "function" then
			local ok, err = pcall(o.OnSkip, handle)
			if not ok then
				warnOnce("onskip" .. id, tostring(err))
			end
		end
		-- the remaining Always entries still happen (state the story needs)
		for i = run.Next, #run.Timeline do
			local entry = run.Timeline[i]
			if entry.Always then
				local ok, err = pcall(entry.Fn, handle)
				if not ok then
					warnOnce("tl" .. id .. i, tostring(err))
				end
			end
		end
		run.Next = #run.Timeline + 1
		run.Skipped = reason
		-- a short glide back to the player's camera (instant for reduced motion / no shot)
		if run.Scripted and not rm then
			run.Returning = { T0 = os.clock(), Dur = .3, From = run.LastCF, Reason = reason }
		else
			finish(true, reason)
		end
	end

	function handle.Cancel()
		finish(false, "Cancelled")
	end
	function handle.Skip()
		skip("Skipped")
	end
	function handle.Elapsed(): number
		return os.clock() - run.StartedAt
	end
	function handle.Running(): boolean
		return not run.Finished
	end

	local ok, err = pcall(function()
		-- the timeline, sorted
		for _, entry in ipairs(type(o.Timeline) == "table" and o.Timeline or {}) do
			if type(entry) == "table" and type(entry[1]) == "number" and type(entry[2]) == "function" then
				table.insert(run.Timeline, { T = entry[1], Fn = entry[2], Always = entry.Always == true })
			end
		end
		table.sort(run.Timeline, function(a, b)
			return a.T < b.T
		end)
		-- the gui attribute every guide / tutorial blocked() check reads
		local main = mainGui()
		if main then
			main:SetAttribute("CinemaActive", true)
			main:SetAttribute("CinemaId", id)
			table.insert(run.Undo, function()
				if main.Parent and main:GetAttribute("CinemaId") == id then
					main:SetAttribute("CinemaActive", nil)
					main:SetAttribute("CinemaId", nil)
				end
			end)
		end
		-- watchers: death, character removal, a menu opening mid-shot
		local h = humanoid()
		if h then
			local c = h.Died:Connect(function()
				task.defer(finish, false, "Died")
			end)
			table.insert(run.Undo, function()
				c:Disconnect()
			end)
		end
		local cr = player.CharacterRemoving:Connect(function()
			task.defer(finish, false, "Character")
		end)
		table.insert(run.Undo, function()
			cr:Disconnect()
		end)
		if not o.Force and main then
			local mc = main.AttributeChanged:Connect(function(name)
				if (name == "OpenMenu" or name == "ModalOwnerCount") and menuOpen() and not run.Finished then
					task.defer(skip, "Menu")
				end
			end)
			table.insert(run.Undo, function()
				mc:Disconnect()
			end)
		end
		-- audio duck
		if o.Duck ~= false then
			local m = mixer()
			if m then
				local reason = "Cinema:" .. id
				m.Duck(reason, o.Duck or "Cinematic", .8)
				table.insert(run.Undo, function()
					m.Release(reason, 1.2)
				end)
			end
		end
		-- controls + interface
		if o.LockControls ~= false then
			Cinema.LockControls("Cinema:" .. id)
			table.insert(run.Undo, function()
				Cinema.Unlock("Cinema:" .. id)
			end)
		end
		if o.HideUI ~= false then
			Cinema.HideUI("Cinema:" .. id)
			table.insert(run.Undo, function()
				Cinema.ShowUI("Cinema:" .. id)
			end)
		end
		if o.Letterbox ~= false then
			letterbox(run)
		end
		-- a fade the cinematic started is lifted with it
		table.insert(run.Undo, function()
			if fadeFrame and fadeFrame.Parent and fadeFrame.BackgroundTransparency < .999 and run.UsedFade then
				Cinema.Fade(0, .35)
			end
		end)
		function handle.Fade(alpha: number, dur: number?, fadeOpts: any)
			run.UsedFade = true
			Cinema.Fade(alpha, dur, fadeOpts)
		end
		-- the camera
		local cam = workspace.CurrentCamera
		run.Camera = cam
		if cam then
			run.StartCFrame = cam.CFrame
			run.LastCF = cam.CFrame
			run.StartFov = cam.FieldOfView
			if o.Focus then
				depthOfField(run, cam)
			end
		end
		if cam and o.Shot ~= nil then
			run.Scripted = true
			local prevType = cam.CameraType
			local prevSubject = cam.CameraSubject
			cam.CameraType = Enum.CameraType.Scriptable
			table.insert(run.Undo, function()
				local c = workspace.CurrentCamera
				if not c then
					return
				end
				if c.CameraType == Enum.CameraType.Scriptable then
					c.CameraType = prevType ~= Enum.CameraType.Scriptable and prevType or Enum.CameraType.Custom
				end
				local hum = humanoid()
				if prevSubject and prevSubject.Parent then
					c.CameraSubject = prevSubject
				elseif hum then
					c.CameraSubject = hum
				end
				if run.StartFov then
					c.FieldOfView = run.StartFov
				end
			end)
		elseif cam and o.Fov ~= nil then
			table.insert(run.Undo, function()
				local c = workspace.CurrentCamera
				if c and run.StartFov then
					tween(c, .4, { FieldOfView = run.StartFov })
				end
			end)
		end
		-- skip input
		local inputConn = UserInputService.InputBegan:Connect(function(input, gp)
			if not run.Skippable or run.Finished or os.clock() - run.StartedAt < run.SkipAfter then
				return
			end
			local t = input.UserInputType
			local okKey = (t == Enum.UserInputType.Keyboard and not gp and input.KeyCode ~= Enum.KeyCode.Unknown)
				or (t == Enum.UserInputType.MouseButton1 and not gp) or t == Enum.UserInputType.Touch
				or (t == Enum.UserInputType.Gamepad1 and (input.KeyCode == Enum.KeyCode.ButtonA or input.KeyCode == Enum.KeyCode.ButtonB
					or input.KeyCode == Enum.KeyCode.ButtonStart))
			if okKey then
				skip("Skipped")
			end
		end)
		table.insert(run.Undo, function()
			inputConn:Disconnect()
		end)
		-- the frame loop (Camera + 1: FX.Shake / Impulse at +2 stay offsets on a freshly written camera)
		local name = Cinema.RenderName
		pcall(function()
			RunService:UnbindFromRenderStep(name)
		end)
		local blendIn = rm and 0 or math.max(0, tonumber(o.BlendIn) or .9)
		local blendOut = rm and 0 or math.max(0, tonumber(o.BlendOut) or .8)
		local cutEvery = math.max(.4, tonumber(o.CutEvery) or 1.6)
		local lastT = 0
		RunService:BindToRenderStep(name, Cinema.Priority, function()
			if run.Finished then
				return
			end
			local now = os.clock()
			local t = now - run.StartedAt
			local dt = math.max(0, t - lastT)
			lastT = t
			local c = workspace.CurrentCamera
			-- the skip hint
			if run.SkipLabel and run.Skippable and not run.HintShown and t >= run.SkipAfter then
				run.HintShown = true
				tween(run.SkipLabel, .4, { TextTransparency = .25 })
			end
			-- timeline
			while run.Next <= #run.Timeline and run.Timeline[run.Next].T <= t and not run.Returning do
				local entry = run.Timeline[run.Next]
				run.Next += 1
				local okT, errT = pcall(entry.Fn, handle)
				if not okT then
					warnOnce("tl" .. id .. run.Next, tostring(errT))
				end
				if run.Finished then
					return
				end
			end
			-- the return glide after a skip
			if run.Returning then
				local r = run.Returning
				local k = smooth((now - r.T0) / r.Dur)
				if c and run.Scripted and r.From and run.StartCFrame then
					c.CFrame = r.From:Lerp(run.StartCFrame, k)
				end
				if k >= 1 then
					finish(true, r.Reason)
				end
				return
			end
			if c then
				-- the shot
				if run.Scripted then
					local sampleT = rm and math.floor(t / cutEvery) * cutEvery or t
					local okS, shotCF = pcall(o.Shot, math.min(sampleT, duration), dt)
					if okS and typeof(shotCF) == "CFrame" then
						run.ShotCF = shotCF
					elseif not okS then
						warnOnce("shot" .. id, tostring(shotCF))
					end
					local goal = run.ShotCF or run.LastCF or c.CFrame
					local k = 1
					if blendIn > 0 and t < blendIn then
						k = smooth(t / blendIn)
					end
					if blendOut > 0 and t > duration - blendOut then
						k = math.min(k, smooth((duration - t) / blendOut))
					end
					local cf = (k < 1 and run.StartCFrame) and run.StartCFrame:Lerp(goal, k) or goal
					c.CFrame = cf
					run.LastCF = cf
				end
				-- the lens
				local fov = o.Fov
				if type(fov) == "function" then
					local okF, v = pcall(fov, t)
					fov = okF and v or nil
				end
				if type(fov) == "number" and run.StartFov then
					local k = 1
					if blendIn > 0 and t < blendIn then
						k = smooth(t / blendIn)
					end
					if blendOut > 0 and t > duration - blendOut then
						k = math.min(k, smooth((duration - t) / blendOut))
					end
					c.FieldOfView = math.clamp(run.StartFov + (fov - run.StartFov) * k, 20, 100)
				end
				local fk = 1
				if t < .6 then
					fk = smooth(t / .6)
				elseif t > duration - .5 then
					fk = smooth((duration - t) / .5)
				end
				applyFocus(run, c, t, fk)
			end
			if t >= duration then
				finish(true, "Done")
			end
		end)
		table.insert(run.Undo, function()
			RunService:UnbindFromRenderStep(name)
		end)
		-- belt and braces: whatever happens to the frame loop, the cinematic ends
		task.delay(duration + 3, function()
			if not run.Finished then
				warnOnce("watchdog" .. id, "cinematic " .. id .. " did not finish on time; restoring")
				finish(true, "Done")
			end
		end)
	end)
	if not ok then
		warnOnce("build" .. id, tostring(err))
		finish(false, "Error")
		return nil, "Error"
	end
	return handle
end

---------------------------------------------------------------------------------------------------------------------
-- Start (HalloweenClient boot): optional; also cancels a running cinematic on respawn and keeps the control lock honest
---------------------------------------------------------------------------------------------------------------------
function Cinema.Start(c: any)
	ctx = c
	if c and c.Shared then
		sharedMod = c.Shared
	end
	if c and c.FX then
		fxMod = c.FX
	end
	-- a respawn never inherits a lock that a dead cinematic forgot (every reason is released by its teardown; this only
	-- re-syncs the PlayerModule state after the new character arrives)
	player.CharacterAdded:Connect(function()
		task.defer(function()
			pcall(syncControls)
		end)
	end)
	if c and c.Bus and c.Bus.On then
		-- other systems can stop a cinematic without requiring this module
		c.Bus.On("CinemaCancel", function(data)
			Cinema.Cancel(type(data) == "table" and data.Reason or "Cancelled")
		end)
	end
end

return Cinema
