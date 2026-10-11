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

local ctx:any={Player=player,PlayerGui=playerGui,Main=main}
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

-- Movement lock shared by the mining session and training. Re-enabling waits until no menu is
-- open: GUIIntegration skips its own lock while ours is on, so enabling under a menu would let
-- the player walk around behind it.
local controls=nil
local releasing=false
function ctx.SetControls(enabled)
 if controls==nil then
  local ok,module=pcall(function()
   return require(ctx.Player:WaitForChild('PlayerScripts'):WaitForChild('PlayerModule')):GetControls()
  end)
  controls=ok and module or false
 end
 if not controls then return end
 if not enabled then pcall(function()controls:Disable()end);return end
 if releasing then return end
 releasing=true
 task.spawn(function()
  while main.Parent and main:GetAttribute('OpenMenu')~=nil do task.wait(.1)end
  releasing=false
  local busy=(ctx.Mine and ctx.Mine.Active)or(ctx.Gym and ctx.Gym.Active)
  if not busy then pcall(function()controls:Enable()end)end
 end)
end

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
