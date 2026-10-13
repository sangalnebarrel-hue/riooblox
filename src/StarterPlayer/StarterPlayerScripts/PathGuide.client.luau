-- SHOW THE WAY: starts the client route guide (ReplicatedStorage.Navigation.PathGuide: glowing
-- ground arrows, final pointer, pooled parts) and binds N to the "WHERE TO GO?" navigator window
-- (Modules.NavigatorScreen through GUIIntegration's Navigate route). DistrictGuide turns every
-- NavigateDistrict "SHOW THE WAY" into a route; docs/NAVIGATION.md.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local PathGuide = require(ReplicatedStorage:WaitForChild("Navigation"):WaitForChild("PathGuide"))
PathGuide.Start()

-- GUIIntegration is required on demand only (PawpadRuntime owns its first require).
local function navigation(): any
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	local gui = playerGui and playerGui:FindFirstChild("ScreenGui")
	local modules = gui and gui:FindFirstChild("Modules")
	local module = modules and modules:FindFirstChild("GUIIntegration")
	if not module then
		return nil, gui
	end
	local ok, N = pcall(require, module)
	return ok and N or nil, gui
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.KeyCode ~= Enum.KeyCode.N or UserInputService:GetFocusedTextBox() then
		return
	end
	local N, gui = navigation()
	if not N then
		return
	end
	if gui and gui:GetAttribute("OpenMenu") == "Navigate" then
		N.Close()
	else
		N.OpenPage("Navigate")
	end
end)
