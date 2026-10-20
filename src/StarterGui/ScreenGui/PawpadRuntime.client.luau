local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local StarterGui=game:GetService('StarterGui')
local player=Players.LocalPlayer;local gui=script.Parent
local N=require(gui.Modules.GUIIntegration)
local playerListVisible=false
-- One reduced-motion switch (Kit.Motion, world effects): the in-game Motion toggle, seeded from Roblox's setting.
local reducedMotion=player:GetAttribute('ReducedMotion')==true
if not reducedMotion then local ok,value=pcall(function()return game:GetService('GuiService').ReducedMotionEnabled end);if ok and value==true then reducedMotion=true;player:SetAttribute('ReducedMotion',true)end end
pcall(function()StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,false)end);require(gui.Modules.UITheme).RequestHUDLayout(gui)
local menus=require(gui.Modules.Menus).new(gui,{
 openMap=function()N.Close();gui.ToggleDistrictMap:Fire()end,
 navigate=N.Navigate,
 settings=function()return{motion=not reducedMotion,players=playerListVisible,sounds=player:GetAttribute('UISounds')~=false}end,
 setting=function(key)
  if key=='Motion'then reducedMotion=not reducedMotion;player:SetAttribute('ReducedMotion',reducedMotion)
  elseif key=='World Event FX'then local levels={'High','Medium','Low'};local current=player:GetAttribute('WorldEventFX')or'High';player:SetAttribute('WorldEventFX',levels[(table.find(levels,current)or 1)%3+1])
  elseif key=='Leaderboard'then playerListVisible=not playerListVisible;pcall(function()StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,playerListVisible)end)
   require(gui.Modules.UITheme).RequestHUDLayout(gui) -- the HUD cluster moves out of the leaderboard's way
  elseif key=='UI Sounds'then player:SetAttribute('UISounds',player:GetAttribute('UISounds')==false)
  end
 end,
})
N.RegisterMenus(menus)
local elapsed=0
local c=Run.Heartbeat:Connect(function(dt)elapsed+=dt;if elapsed<.5 then return end;elapsed=0;menus:Update()end)
gui.Destroying:Connect(function()c:Disconnect()end)
