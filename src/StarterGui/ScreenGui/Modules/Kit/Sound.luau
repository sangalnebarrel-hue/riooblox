-- Kit interface sounds: forwards to ReplicatedStorage.UISound (hover / press on buttons, open /
-- close on windows, tab changes) and stays silent when it cannot be loaded. A window created with
-- Sound = false marks its root UISoundOff, which silences everything inside it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Sound = {}

local module: any = nil
local function uiSound(): any
	if module == nil then
		module = false
		local found = ReplicatedStorage:FindFirstChild("UISound")
		if found and found:IsA("ModuleScript") then
			local ok, value = pcall(require, found)
			if ok and type(value) == "table" then
				module = value
			end
		end
	end
	return module
end

-- Plays `cue` unless `from` (or an ancestor) has UISoundOff.
function Sound.Play(cue: string, from: Instance?)
	local ui = uiSound()
	if ui then
		ui.Play(cue, { From = from })
	end
end

-- A hold-to-confirm button sounds when the hold starts (and completes) instead of on Activated:
-- HoldBinding is its Bind options (its Hover choice kept, false included; no Press), PressCue the
-- cue for the hold start (nil = silent). sound = the Button's Sound prop.
function Sound.HoldBinding(sound: any): any
	if sound == false then
		return false
	end
	local hover = nil
	if type(sound) == "table" then
		hover = sound.Hover
	end
	return { Hover = hover, Press = false }
end

function Sound.PressCue(sound: any): string?
	local press = if type(sound) == "table" then sound.Press else nil
	if sound == false or press == false then
		return nil
	end
	return if type(press) == "string" then press else "Press"
end

-- Hover / press sounds on a button; options = false (silent), nil / true (the default cues) or
-- {Hover = cue | false, Press = cue | false}.
function Sound.Bind(button: GuiButton, maid: any, options: any?)
	local ui = uiSound()
	if ui and options ~= false then
		maid:Give(ui.Bind(button, if type(options) == "table" then options else nil))
	end
end

return Sound
