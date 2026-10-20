-- The main DOGROTS tutorial entry point (kept for its callers: GUIIntegration starts it once per session, Settings →
-- HOW TO PLAY replays it). Since tutorial v4 (docs/halloween2/TUTORIAL.md) everything the player sees is
-- Modules.TutorialDirector: the step card, the camera focus, the highlight, SHOW THE WAY and the world marker.
local Guide = {}

local function director(): any
	local module = script.Parent:FindFirstChild("TutorialDirector")
	if not module then
		return nil
	end
	local ok, value = pcall(require, module)
	if ok and type(value) == "table" then
		return value
	end
	warn("DOGROTS tutorial director: " .. tostring(value))
	return nil
end

-- HOW TO PLAY: the director's cards in replay mode (client only, no server requests).
function Guide.Replay()
	local D = director()
	if D then
		D.Replay()
	end
end

-- gui: the main ScreenGui; navigation: GUIIntegration's N. Returns the director's controller (nil if it failed).
function Guide.Start(gui: any, navigation: any): any
	local D = director()
	if not D then
		return nil
	end
	local ok, controller = pcall(D.Start, gui, navigation)
	if not ok then
		warn("DOGROTS tutorial director start: " .. tostring(controller))
		return nil
	end
	return controller
end

return Guide
