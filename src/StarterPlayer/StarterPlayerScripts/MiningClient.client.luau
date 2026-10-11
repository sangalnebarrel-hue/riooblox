-- Active Mining client: ore piles on every yard, the timing-circle mining session, the pickaxe
-- market and strength training. Runs in its own LocalScript so a failure here can never take
-- down the main menus (it used to live inside OnboardingGuide).
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local player=Players.LocalPlayer
local playerGui=player:WaitForChild('PlayerGui')

local main=playerGui:FindFirstChild('ScreenGui')
while not main do
 local child=playerGui.ChildAdded:Wait()
 if child.Name=='ScreenGui'then main=child end
end
local modules=main:WaitForChild('Modules')
local mining=RS:WaitForChild('Mining')

local ctx={Player=player,PlayerGui=playerGui,Main=main}
ctx.N=require(modules:WaitForChild('GUIIntegration'))
ctx.U=require(modules:WaitForChild('UITheme'))
ctx.Config=require(RS:WaitForChild('DogEconomy'):WaitForChild('Config'))
ctx.M=ctx.Config.Mining
ctx.Text=require(mining:WaitForChild('MiningText'))
ctx.Models=require(mining:WaitForChild('MiningModels'))
ctx.Rules=require(mining:WaitForChild('MiningRules'))
ctx.Audio=require(mining:WaitForChild('MiningAudio'))
ctx.Remote=RS:WaitForChild('DogEconomyRequest')

-- One self-localized ScreenGui for every mining overlay (DOGROTS_AutoTranslateUI skips it).
local gui=Instance.new('ScreenGui')
gui.Name='MiningGui';gui.ResetOnSpawn=false;gui.DisplayOrder=40;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui:SetAttribute('NoTranslate',true);gui:SetAttribute('KeepFont',true)
gui.Parent=playerGui
ctx.Gui=gui

local function start(name)
 local ok,err=pcall(function()
  local module=require(script:WaitForChild(name))
  ctx[name]=module.new(ctx)
 end)
 if not ok then warn('DOGROTS mining: '..name..' failed to start: '..tostring(err))end
end
for _,name in ipairs({'Net','Anim','FX','Hud','World','Mine','Shop','Gym','Debug'})do start(name)end
if ctx.World and ctx.World.Start then
 local ok,err=pcall(ctx.World.Start);if not ok then warn('DOGROTS mining: world start failed: '..tostring(err))end
end
