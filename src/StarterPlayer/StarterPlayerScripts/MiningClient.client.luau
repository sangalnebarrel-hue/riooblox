-- Active Mining client: ore piles on every yard, the timing-circle mining session, the pickaxe
-- market and strength training. Runs in its own LocalScript so a failure here can never take
-- down the main menus (it used to live inside OnboardingGuide).
-- Start-up order: the world (ore piles + prompt handling) comes first and does not depend on the
-- PAWPAD menu modules, so a slow or failing menu module can never hide the ore or break E.
-- Every failure is reported with "DOGROTS mining:" in Output, and on screen in Studio.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local RunService=game:GetService('RunService')
local player=Players.LocalPlayer
local playerGui=player:WaitForChild('PlayerGui')
local STUDIO=RunService:IsStudio()

-- DIAGNOSTICS ------------------------------------------------------------------------------------
local panel=nil
local lines={}
local function report(message)
 warn('DOGROTS mining: '..message)
 if not STUDIO then return end
 table.insert(lines,message)
 if not panel then
  local g=Instance.new('ScreenGui');g.Name='MiningDiagnostics';g.ResetOnSpawn=false;g.DisplayOrder=200;g:SetAttribute('NoTranslate',true)
  local l=Instance.new('TextLabel');l.Name='Errors';l.AnchorPoint=Vector2.new(0,1);l.Position=UDim2.new(0,8,1,-8);l.Size=UDim2.new(.6,0,0,140)
  l.BackgroundColor3=Color3.fromRGB(60,10,20);l.BackgroundTransparency=.15;l.TextColor3=Color3.new(1,1,1);l.TextSize=13
  l.Font=Enum.Font.Code;l.TextWrapped=true;l.TextXAlignment=Enum.TextXAlignment.Left;l.TextYAlignment=Enum.TextYAlignment.Top
  l:SetAttribute('NoTranslate',true);l.Parent=g;g.Parent=playerGui;panel=l
 end
 panel.Text='[Studio] DOGROTS mining problems (see Output):\n'..table.concat(lines,'\n',math.max(1,#lines-6))
end
-- WaitForChild that says what it is waiting for instead of hanging silently.
local function need(parent,name)
 local child=parent:WaitForChild(name,12)
 if not child then
  report('still waiting for '..parent:GetFullName()..'.'..name)
  child=parent:WaitForChild(name)
 end
 return child
end
local function load(label,fn)
 local ok,result=xpcall(fn,function(e)return tostring(e)..'\n'..debug.traceback()end)
 if not ok then report(label..' failed: '..tostring(result));return nil end
 return result
end

local main=playerGui:FindFirstChild('ScreenGui')
while not main do
 local child=playerGui.ChildAdded:Wait()
 if child.Name=='ScreenGui'then main=child end
end
local mining=need(RS,'Mining')

local ctx:any={Player=player,PlayerGui=playerGui,Main=main,Report=report}
function ctx.Log(message)if STUDIO then print('DOGROTS mining: '..message)end end
ctx.Config=load('Config',function()return require(need(need(RS,'DogEconomy'),'Config'))end)
ctx.M=ctx.Config and ctx.Config.Mining
ctx.Text=load('MiningText',function()return require(need(mining,'MiningText'))end)
ctx.Models=load('MiningModels',function()return require(need(mining,'MiningModels'))end)
ctx.Rules=load('MiningRules',function()return require(need(mining,'MiningRules'))end)
ctx.Audio=load('MiningAudio',function()return require(need(mining,'MiningAudio'))end)
ctx.Remote=need(RS,'DogEconomyRequest')
if not(ctx.M and ctx.Text and ctx.Models and ctx.Rules and ctx.Audio)then
 report('shared mining modules missing; mining is disabled');return
end
local modules=need(main,'Modules')
ctx.U=load('UITheme',function()return require(need(modules,'UITheme'))end)
if not ctx.U then
 -- Fonts and colours are all the world view needs; menus report their own failure below.
 local C=Color3.fromRGB
 ctx.U={FontFace=Font.fromEnum(Enum.Font.FredokaOne),Colors={edge=C(23,43,76),text=C(23,43,76),muted=C(83,112,150),gold=C(249,180,35),
  blue=C(38,164,243),green=C(125,219,48),red=C(247,73,112),purple=C(161,103,242),panel=C(255,255,255),secondary=C(220,237,253)}}
end

-- One self-localized ScreenGui for every mining overlay (DOGROTS_AutoTranslateUI skips it).
local gui=Instance.new('ScreenGui')
gui.Name='MiningGui';gui.ResetOnSpawn=false;gui.DisplayOrder=40;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui:SetAttribute('NoTranslate',true);gui:SetAttribute('KeepFont',true)
gui.Parent=playerGui
ctx.Gui=gui

-- Movement lock shared by the mining session and training. Re-enabling waits until no menu is
-- open: GUIIntegration skips its own lock while ours is on, so enabling under a menu would let
-- the player walk around behind it.
-- A PAWPAD menu is open. GUIIntegration's navigation owner is the authority (the OpenMenu
-- attribute can be set briefly by other scripts); the attribute is the fallback without it.
function ctx.MenuOpen()
 local N=ctx.N
 if N and N.Owner~=nil and not N.Stub then return N.Owner~='HUD'end
 return main:GetAttribute('OpenMenu')~=nil
end
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
  while main.Parent and ctx.MenuOpen()do task.wait(.1)end
  releasing=false
  local busy=(ctx.Mine and ctx.Mine.Active)or(ctx.Gym and ctx.Gym.Active)
  if not busy then pcall(function()controls:Enable()end)end
 end)
end

local function start(name)
 local module=load(name..' module',function()return require(need(script,name))end)
 if not module then return end
 ctx[name]=load(name,function()return module.new(ctx)end)
end
-- World first: ore piles and prompt handling never wait for the menu modules.
for _,name in ipairs({'Net','Anim','FX','Hud','World'})do start(name)end
if ctx.World and ctx.World.Start then load('World.Start',ctx.World.Start)end
-- The pickaxe market borrows PAWPAD navigation; without it the market still opens on its own.
ctx.N=load('GUIIntegration',function()return require(need(modules,'GUIIntegration'))end)
if not ctx.N then
 local N={Owner='HUD',ModalOwnerCount=0,Stub=true}
 function N.Acquire(owner)N.Owner=owner end
 function N.Close()N.Owner='HUD'end
 ctx.N=N
end
for _,name in ipairs({'Mine','Shop','Gym','Debug'})do start(name)end
local started={}
for _,name in ipairs({'Net','Anim','FX','Hud','World','Mine','Shop','Gym','Debug'})do if ctx[name]then table.insert(started,name)end end
ctx.Log('client started: '..table.concat(started,', '))
