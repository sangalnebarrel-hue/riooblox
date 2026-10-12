local Players=game:GetService('Players')
local Run=game:GetService('RunService')
local StarterGui=game:GetService('StarterGui')
local player=Players.LocalPlayer;local gui=script.Parent
local N=require(gui.Modules.GUIIntegration)
local playerListVisible=false
pcall(function()StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,false)end)
local menus=require(gui.Modules.Menus).new(gui,{
 openMap=function()N.Close();gui.ToggleDistrictMap:Fire()end,
 navigate=N.Navigate,
 -- ReducedMotion is shared with Perf.Quality (which may set it from the saved or system setting).
 settings=function()return{motion=player:GetAttribute('ReducedMotion')~=true,players=playerListVisible}end,
 setting=function(key)
  if key=='Motion'then player:SetAttribute('ReducedMotion',player:GetAttribute('ReducedMotion')~=true)
  elseif key=='World Event FX'then local levels={'High','Medium','Low'};local current=player:GetAttribute('WorldEventFX')or'High';player:SetAttribute('WorldEventFX',levels[(table.find(levels,current)or 1)%3+1])
  elseif key=='Leaderboard'then playerListVisible=not playerListVisible;pcall(function()StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,playerListVisible)end)end
 end,
})
N.RegisterMenus(menus)
local elapsed=0
local c=Run.Heartbeat:Connect(function(dt)elapsed+=dt;if elapsed<.5 then return end;elapsed=0;menus:Update()end)
gui.Destroying:Connect(function()c:Disconnect()end)
