-- Glue between kit windows and the game's navigation owner (Modules.GUIIntegration):
--  * a base kit window calls N.Acquire('Kit', key): the HUD and every other menu hide, movement
--    and prompts lock, OpenMenu=key / MenuFamily='Kit' tell other systems a menu is open;
--  * closing it calls N.Close() if the kit still owns navigation;
--  * when navigation moves elsewhere (another menu, a reward, Escape, respawn) OpenMenu changes
--    and Nav.Changed fires: the window manager closes the kit windows;
--  * Escape: GUIIntegration asks N.DismissDialog() first; the kit wraps it so an open kit modal,
--    dropdown or stacked window is dismissed before the base window closes. Gamepad B (which
--    GUIIntegration ignores) is handled here the same way.
local UserInputService = game:GetService("UserInputService")
local Signal = require(script.Parent.Signal)
local Overlay = require(script.Parent.Overlay)

local Nav = {}
Nav.Owner = "Kit" -- N.Owner / MenuFamily while a kit window is open
Nav.Changed = Signal.new() -- OpenMenu changed (fired deferred, compare the current state)
-- Set by Window: closes the top kit window when allowed; allowBase=false keeps the base window
-- (GUIIntegration closes it through N.Close). Returns true when it closed something.
Nav.CloseTop = function(_allowBase: boolean): boolean
	return false
end

local navigation: any = nil
local mainGui: any = nil
local resolved = false
local hookedNavigation: any = nil
local inputConnection: RBXScriptConnection? = nil
local attributeConnection: RBXScriptConnection? = nil

local function install()
	if navigation and hookedNavigation ~= navigation then
		hookedNavigation = navigation
		local original = navigation.DismissDialog
		navigation.DismissDialog = function(...)
			if Overlay.DismissTop("escape") then
				return true
			end
			if Nav.CloseTop(false) then
				return true
			end
			if type(original) == "function" then
				return original(...)
			end
			return false
		end
	end
	if attributeConnection then
		attributeConnection:Disconnect()
		attributeConnection = nil
	end
	if mainGui then
		attributeConnection = mainGui:GetAttributeChangedSignal("OpenMenu"):Connect(function()
			Nav.Changed:Fire()
		end)
	end
	if not inputConnection then
		inputConnection = UserInputService.InputBegan:Connect(function(input)
			local key = input.KeyCode
			-- With GUIIntegration present it owns Escape (through the DismissDialog wrapper).
			local escape = key == Enum.KeyCode.Escape and navigation == nil
			if key ~= Enum.KeyCode.ButtonB and not escape then
				return
			end
			if UserInputService:GetFocusedTextBox() then
				return
			end
			if Overlay.DismissTop("escape") then
				return
			end
			Nav.CloseTop(true)
		end)
	end
end

-- Finds GUIIntegration next to the kit (ScreenGui.Modules.GUIIntegration) once.
function Nav.Resolve(): any
	if not resolved then
		resolved = true
		local kit: any = script.Parent
		local modules: any = kit and kit.Parent
		local module = modules and modules:FindFirstChild("GUIIntegration")
		if module and module:IsA("ModuleScript") then
			local ok, value = pcall(require, module)
			if ok and type(value) == "table" and type((value :: any).Acquire) == "function" then
				navigation = value
				mainGui = modules.Parent
			else
				warn("Kit: GUIIntegration unavailable (" .. tostring(value) .. "); kit windows run without navigation")
			end
		end
		install()
	end
	return navigation
end

-- Overrides the navigation owner (tests, standalone tools). Pass false for none.
function Nav.Set(value: any, gui: Instance?)
	navigation = value or nil
	mainGui = gui
	resolved = true
	install()
end

function Nav.Gui(): Instance?
	Nav.Resolve()
	return mainGui
end

-- Takes navigation for a kit window. Returns false without a navigation owner.
function Nav.Acquire(key: string): boolean
	local n = Nav.Resolve()
	if not n then
		return false
	end
	local ok, err = pcall(n.Acquire, Nav.Owner, key)
	if not ok then
		warn("Kit: N.Acquire failed: " .. tostring(err))
		return false
	end
	-- Kit windows dim the screen themselves; Acquire showed the main GUI backdrop.
	local backdrop = mainGui and mainGui:FindFirstChild("Backdrop")
	if backdrop and backdrop:IsA("GuiObject") then
		backdrop.Visible = false
	end
	return true
end

-- True while the kit owns navigation for `key`.
function Nav.Owns(key: string): boolean
	local n = navigation
	if not n then
		return false
	end
	if n.Owner ~= Nav.Owner then
		return false
	end
	return mainGui == nil or mainGui:GetAttribute("OpenMenu") == key
end

-- Gives navigation back (N.Close -> HUD) if the kit still owns it for `key`.
function Nav.Release(key: string)
	if Nav.Owns(key) then
		local ok, err = pcall(navigation.Close)
		if not ok then
			warn("Kit: N.Close failed: " .. tostring(err))
		end
	end
end

return Nav
