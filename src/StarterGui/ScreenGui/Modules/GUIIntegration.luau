-- The PAWPAD navigation owner. All presentation lives under one ScreenGui.
-- [WP-D2] Navigation state that other systems read is derived, never saved and restored (A07 D5, A04 §8):
--  * ProximityPromptService.Enabled == (N.Owner == 'HUD'): every prompt works whenever no menu owns the screen;
--  * movement: ref-counted control locks by reason (N.LockControls / N.UnlockControls); a non-HUD owner holds the
--    'Menu' lock. Controls are enabled again only when the last lock goes and only if a lock disabled them, so a
--    guide or a cinematic using the same locks never fights a menu;
--  * N.Acquire always ends consistent: each presentation step is isolated, the state steps always run;
--  * a 1 s watchdog: a non-HUD owner whose surface (window, page, panel, overlay) has been invisible for 2 s gives
--    navigation back to the HUD (N.Close), and the HUD state re-asserts the prompts invariant. Owners register their
--    surface check with N.RegisterSurface(owner, fn); an owner without one is never auto-closed.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local UIS=game:GetService('UserInputService')
local Actions=game:GetService('ContextActionService')
local Prompts=game:GetService('ProximityPromptService')
local player=Players.LocalPlayer
local gui=script.Parent.Parent
local Theme=require(script.Parent.UITheme);Theme.ApplyShell(gui);Theme.ApplyStandalone(gui)
local Sound=require(script.Parent.Kit.Sound)
local N={Owner='HUD',ModalOwnerCount=0,WorldRewardHandlers={},Pending={},RewardEpoch=0,SeenRewards={}}
local screens,switchPage,serviceOpen,inventoryReward,pageDialog
local main=gui:WaitForChild('MainWindow');local pages=main.Content.PageContainer
local staticPages={Yard=true,Dogs=true,DogDex=true,Trade=true,Shop=true,Events=true,Discoveries=true,Inventory=true}
local aliases={Pawpad='Yard',Economy='Yard',ItemSets='Yard',['Your yard']='Yard',['Global dig']='Events',Coins='Shop',Level='Upgrades',SlotDogs='Dogs',OwnedBlocks='Inventory',LuckyBlocks='Inventory'}
local services={DogTraining='DogTraining',Upgrades='Upgrades',Layers='Layers',Collector='Seller',Seller='Seller'}
-- UPGRADE TREE: DogTraining, Upgrades, Level, UpgradeTree and Estate all open Modules.UpgradeTreeScreen
-- (ServiceMenusController.open routes them; Estate focuses the yard-stage node).
services.UpgradeTree='UpgradeTree';services.Estate='Estate'
local connections={}
local function connect(event,fn)local c=event:Connect(fn);table.insert(connections,c);return c end
local function ready()return screens and switchPage and serviceOpen and inventoryReward end
local function dispatch(fn)if ready()then fn()else table.insert(N.Pending,fn)end end
local function flush()if ready()then local pending=N.Pending;N.Pending={};for _,fn in ipairs(pending)do fn()end end end
local function mapOverlay()local guide=gui:FindFirstChild('DistrictGuide');return guide and guide:FindFirstChild('MapOverlay')end
local playerControls,controlsDisabledByLocks
local controlLocks={} -- [reason]=true
local function lockReasons()
 local list={};for reason in pairs(controlLocks)do table.insert(list,reason)end;table.sort(list);return list
end
local function applyControls()
 pcall(function()local reasons=lockReasons();gui:SetAttribute('ControlLocks',#reasons>0 and table.concat(reasons,',')or nil)end)
 if not playerControls then return end
 local ok,err=pcall(function()
  if next(controlLocks)~=nil then
   if not controlsDisabledByLocks and playerControls.controlsEnabled~=false then playerControls:Disable();controlsDisabledByLocks=true end
  elseif controlsDisabledByLocks then
   controlsDisabledByLocks=false;playerControls:Enable()
  end
 end)
 if not ok then warn('DOGROTS navigation controls: '..tostring(err))end
end
-- Ref-counted movement lock (reason: any string, e.g. 'Menu', 'HalloweenGuide', 'Cinema').
function N.LockControls(reason)controlLocks[tostring(reason or 'Lock')]=true;applyControls()end
function N.UnlockControls(reason)controlLocks[tostring(reason or 'Lock')]=nil;applyControls()end
function N.ControlsLocked(reason)if reason~=nil then return controlLocks[tostring(reason)]==true end;return next(controlLocks)~=nil end
function N.ControlLockReasons()return lockReasons()end
-- Prompts, the menu lock and the movement sink follow N.Owner (never a saved boolean).
local function applyNavigation()
 local hud=N.Owner=='HUD'
 local ok,err=pcall(function()Prompts.Enabled=hud end)
 if not ok then warn('DOGROTS navigation prompts: '..tostring(err))end
 controlLocks.Menu=(not hud)or nil
 applyControls()
 ok,err=pcall(function()
  if hud then
   Actions:UnbindAction('PawpadMovement')
  else
   Actions:BindActionAtPriority('PawpadMovement',function()return Enum.ContextActionResult.Sink end,false,2500,
    Enum.PlayerActions.CharacterForward,Enum.PlayerActions.CharacterBackward,Enum.PlayerActions.CharacterLeft,Enum.PlayerActions.CharacterRight,Enum.PlayerActions.CharacterJump)
  end
 end)
 if not ok then warn('DOGROTS navigation movement sink: '..tostring(err))end
end
task.spawn(function()
 local module=player:WaitForChild('PlayerScripts'):WaitForChild('PlayerModule',15)
 if not module then return end
 local ok,controls=pcall(function()return require(module):GetControls()end)
 if ok and controls then playerControls=controls;applyControls()end
end)
local function step(name,fn)
 local ok,err=pcall(fn)
 if not ok then warn('DOGROTS navigation ('..name..'): '..tostring(err))end
end
N.AcquireCount=0
function N.Acquire(owner,page)
 local previousOwner=N.Owner
 if type(owner)~='string'or owner==''then owner='HUD'end
 N.Owner=owner
 N.AcquireCount+=1
 -- Navigation owns one window family; nested dialogs borrow that owner.
 N.ModalOwnerCount=owner=='HUD'and 0 or 1
 step('ModalOwnerCount',function()gui:SetAttribute('ModalOwnerCount',N.ModalOwnerCount)end)
 applyNavigation()
 step('toast',function()if owner~='RewardMachineWorld'then local toast=gui:FindFirstChild('RewardMachineRewardToast');if toast then toast:Destroy()end end end)
 step('screens',function()if screens then screens:Hide()end end)
 step('reward',function()
  local reward=gui:FindFirstChild('RewardReveal')
  if reward and owner~='HUD'then reward:Destroy()end
 end)
 step('map',function()local map=mapOverlay();if map and owner~='Map'then map.Visible=false end end)
 -- Hide UI (StarterPlayerScripts.HideUI): any menu brings the interface back.
 step('UIHidden',function()if owner~='HUD'and gui:GetAttribute('UIHidden')then gui:SetAttribute('UIHidden',nil)end end)
 -- One open / close sound for every menu family (kit windows play the same cue; Kit.Sound drops the repeat).
 step('sound',function()if previousOwner=='HUD'and owner~='HUD'then Sound.Play('Open')elseif previousOwner~='HUD'and owner=='HUD'then Sound.Play('Close')end end)
 step('shell',function()
  main.Visible=false;gui.ServiceMenus.Visible=false;gui.Backdrop.Visible=owner~='HUD';gui.HUD.Visible=owner=='HUD'and not gui:GetAttribute('UIHidden')
 end)
 step('InventoryToast',function()gui.InventoryToast.Visible=false end)
 step('pages',function()
  for _,p in ipairs(pages:GetChildren())do if p:IsA('GuiObject')then p.Visible=false end end
  local keyboard=pages:FindFirstChild('SearchKeyboard');if keyboard then keyboard.Visible=false end
 end)
 step('OpenMenu',function()
  gui:SetAttribute('OpenMenu',owner~='HUD'and(page or owner)or nil)
  gui:SetAttribute('MenuFamily',owner~='HUD'and owner or nil)
  gui:SetAttribute('RewardMachineWorldOpen',owner=='RewardMachineWorld')
 end)
 return true
end
function N.Close()N.Acquire('HUD')end
function N.DismissDialog()
 if screens and screens.worldRewardMachine and screens.state.WorldOddsOpen then screens.state.WorldOddsOpen=false;screens:Render();return true end
 if screens and screens.dialog then screens:Dismiss();return true end
 if N.Owner=='Page'and pageDialog then return pageDialog()==true end
 return false
end
function N.Back()
 if N.DismissDialog()then return end
 N.Close()
end
-- The genetics lab is a kit window, not a Menus page (it needs no registered screens): the mutation machine
-- (Modules.MutationLabScreen) while LabConfig.SimpleMode is on, else the old five-procedure Modules.LabScreen.
local function openLab()local ok,err=pcall(function()local simple=require(game:GetService('ReplicatedStorage'):WaitForChild('LabConfig')).SimpleMode==true;require(script.Parent:WaitForChild(simple and'MutationLabScreen'or'LabScreen')).Open()end);if not ok then warn('Lab window: '..tostring(err))end end
function N.OpenPage(page,message)
 if page=='Roulette'then page='RewardMachine'end -- Pre-refactor navigation alias.
 page=aliases[page]or page
 if page=='Equipment'then local ok,screen=pcall(require,script.Parent.Equipment.EquipmentScreen);if ok then screen.Open(message)else warn('DOGROTS equipment screen: '..tostring(screen))end;return end
 if page=='Lab'then openLab();return end
 if page=='Lab'or page=='Shop'or page=='Events'or(gui:GetAttribute('CompactMenus')and(page=='Dogs'or page=='Yard'or page=='DogDex'or page=='Trade'))then N.OpenScreen(page);return end
 if services[page]then N.OpenService(services[page]);return end
 if not staticPages[page]then N.OpenScreen(page);return end
 dispatch(function()
  N.Acquire('Page',page);switchPage(page)
  if N.Owner~='Page'then return end
  main.Visible=true
  if message then local panel=pages:FindFirstChild(page..'Page');local label=panel and panel:FindFirstChild('Status');if label then label.Text=tostring(message)end end
 end)
end
function N.OpenScreen(page,state)
 if page=='Roulette'then page='RewardMachine'end -- Pre-refactor navigation alias.
 if page=='Lab'then openLab();return end
 if page=='Feedback'then N.Close();N.Navigate(page);return end
 if page=='Collector'or page=='Seller'then N.OpenService('Seller');return end
 if page=='Equipment'then local ok,screen=pcall(require,script.Parent.Equipment.EquipmentScreen);if ok then screen.Open()end;return end
 dispatch(function()
  if page=='RewardMachine'then
   N.Acquire('RewardMachineWorld','RewardMachine');gui.Backdrop.Visible=false
   if state then for k,v in pairs(state)do screens.state[k]=v end end
   screens:MountWorldRewardMachine();return
  end
  N.Acquire('Screen',page)
  if state then for k,v in pairs(state)do screens.state[k]=v end end
  main.Visible=true;screens:Mount(page)
 end)
end
function N.OpenService(page,context)dispatch(function()serviceOpen(page,context)end)end
connect(gui:GetAttributeChangedSignal('CompactMenus'),function()
 local page=gui:GetAttribute('OpenMenu')
 if page and(page=='Yard'or page=='Dogs'or page=='DogDex'or page=='Trade')then task.defer(function()N.OpenPage(page)end)end
end)
function N.ShowService(page)
 N.Acquire('Service',page)
 for _,panel in ipairs(gui.ServiceMenus:GetChildren())do if panel:IsA('Frame')and panel:GetAttribute('ServicePanel')then panel.Visible=panel.Name==page end end
 gui.ServiceMenus.Visible=true
end
function N.BeginReward(receipt)
 if receipt and N.SeenRewards[receipt]then return end
 if receipt then N.SeenRewards[receipt]=true end
 N.RewardEpoch+=1;N.RewardAt=os.clock();N.Acquire('Reward','Reward')
return N.RewardEpoch
end
function N.EndReward(epoch)if N.Owner=='Reward'and N.RewardEpoch==epoch then N.Close()end end
function N.RegisterSource(_,callback)switchPage=callback;N.Close();flush()end
function N.RegisterMenus(manager)screens=manager;flush()end
function N.RegisterServices(callback)serviceOpen=callback;flush()end
function N.RegisterInventory(callback)inventoryReward=callback;flush()end
function N.RegisterPageDialog(callback)pageDialog=callback end
function N.SubscribeWorldReward(callback)table.insert(N.WorldRewardHandlers,callback)end
function N.Notify(message)dispatch(function()inventoryReward({Message=message})end)end
local travelBusy=false
function N.Travel(destination)
 if destination~='Lab'and destination~='Museum'then return end
 if travelBusy then return end
 N.Close()
 if switchPage then switchPage('Yard')end -- Reset tab visuals without opening MainWindow.
 travelBusy=true
 task.spawn(function()
  local id=game:GetService('HttpService'):GenerateGUID(false):gsub('-','')
  local transport,ok,result=pcall(function()return RS.DogEconomyRequest:InvokeServer('DistrictTravel',{Destination=destination},id)end)
  travelBusy=false
  if not transport or not ok then N.Notify(transport and result or'Travel unavailable. Please retry.')end
 end)
end

function N.Navigate(destination)N.Close();gui.NavigateDistrict:Fire(destination)end
local function remote(name)local r=RS:WaitForChild(name,30);assert(r,'Missing remote '..name);return r end
connect(remote('DogEconomyOpen').OnClientEvent,function(page,message)
 if type(page)~='string'then return end
 if page=='Trade'then N.OpenScreen('Trade')else N.OpenPage(page,message)end
end)
connect(remote('DogKennelOpen').OnClientEvent,function(slot,yardId)
 local own=player:GetAttribute('YardId')
 if own and(not yardId or yardId==own)and type(slot)=='string'and slot:match('^DigSlot_[1-5]$')then N.OpenService('Kennels',{Slot=slot,YardId=own})end
end)
connect(remote('RewardPresentation').OnClientEvent,function(data)
 if type(data)~='table'then return end
 if data.PromptFeedback then require(script.Parent.PromptFeedback).Show(data.PromptFeedback);return end
 for _,fn in ipairs(N.WorldRewardHandlers)do task.spawn(fn,data)end
 dispatch(function()
  if data.Cue then require(RS.WorldSound).Cue(data.Cue)end
  if data.LuckyOffer then N.OpenScreen('LuckyOdds',{LuckyOffer=data,BlockOddsUid=false,BlockOddsTier=data.Tier,BlockOddsPage=1,BlockMessage=false})end
  if data.PadSelector then N.OpenScreen('LuckyPad',{LuckyPad={Slot=data.Slot,YardId=data.YardId}})end
  if data.OpenedBlock then
   player:SetAttribute('LuckyBlockOpeningUid',nil);player:SetAttribute('LuckyBlockOpeningTier',nil);player:SetAttribute('LuckyBlockOpeningAt',nil)
   require(script.Parent.RewardScreens).Present({U=require(script.Parent.UITheme),State=screens.state},data.OpenedBlock)
   task.defer(function()screens:Fetch(true)end)
  end
  inventoryReward({Message=not data.OpenedBlock and(data.Message or data.Announcement or(data.Credits and 'Lucky Blocks added to Inventory'))or nil})
 end)
end)
connect(UIS.InputBegan,function(input,processed)
 if UIS:GetFocusedTextBox()then return end
 if input.KeyCode==Enum.KeyCode.Escape then
  if not N.DismissDialog()and N.Owner~='HUD'then N.Close()end
  return
 end
 if processed then return end
 local keyboard=pages:FindFirstChild('SearchKeyboard');if keyboard and keyboard.Visible then return end
 if input.KeyCode==Enum.KeyCode.P then if N.Owner=='HUD'then N.OpenPage('Yard')else N.Close()end
 elseif input.KeyCode==Enum.KeyCode.B then if gui:GetAttribute('OpenMenu')=='Inventory'then N.Close()else N.OpenPage('Inventory')end end
end)
local function watchGuide(guide)
 if guide.Name~='DistrictGuide'then return end
 local function attach(map)
  if map.Name~='MapOverlay'then return end
  connect(map:GetPropertyChangedSignal('Visible'),function()if map.Visible then N.Acquire('Map','Map')elseif N.Owner=='Map'then N.Close()end end)
 end
 for _,child in ipairs(guide:GetChildren())do attach(child)end
 connect(guide.ChildAdded,attach)
end
for _,child in ipairs(gui:GetChildren())do watchGuide(child)end
connect(gui.ChildAdded,watchGuide)
connect(player.CharacterRemoving,N.Close)
connect(gui.Destroying,function()
 table.clear(controlLocks);applyControls();pcall(function()Prompts.Enabled=true end);pcall(function()Actions:UnbindAction('PawpadMovement')end)
 for _,c in ipairs(connections)do c:Disconnect()end;table.clear(N.Pending)
end)
-- MY DOGS and the DOGDEX are kit windows on every device (Modules.DogsScreen / DogdexScreen); the static
-- DogsPage / DogDexPage stay hidden. state: the legacy Menus fields (SelectedDog, SelectedDexIndex/Bonus).
local function dogScreens(page,state)
 if page~='Dogs'and page~='DogDetail'and page~='DogDex'and page~='DexEntry'then return false end
 local isDex=page=='DogDex'or page=='DexEntry'
 local ok,screen=pcall(require,script.Parent:FindFirstChild(isDex and 'DogdexScreen'or'DogsScreen'))
 if not ok or type(screen)~='table'then warn('DOGROTS dog screens unavailable: '..tostring(screen));return false end
 local legacy=type(state)=='table'and state or(screens and screens.state)or {}
 if page=='DexEntry'then
  local id=screen.ResolveEntry(legacy,state==nil)
  if id then screen.OpenEntry(id)else screen.Open()end
 elseif page=='DogDex'then screen.Open()
 else screen.Open({Uid=page=='DogDetail'and legacy.SelectedDog or nil})end
 return true
end
do
 -- Wraps the two entry points (every caller goes through the N table, so all routes are covered).
 local openPage,openScreen=N.OpenPage,N.OpenScreen
 function N.OpenPage(page,message)
  if dogScreens(aliases[page]or page,nil)then return end
  return openPage(page,message)
 end
 function N.OpenScreen(page,state)
  if dogScreens(page,state)then return end
  return openScreen(page,state)
 end
end
-- Kit windows of the big overhaul (docs/OVERHAUL.md). Every N.OpenPage / N.OpenScreen route for
-- these keys opens Modules.<module>.Open(arg) (arg: the page message or the screen state). A module
-- that is missing or fails to load leaves the legacy route in place.
local kitScreens={Inventory='InventoryScreen',Trade='TradeScreen',Navigate='NavigatorScreen',Titles='TitlesScreen',
 Showcase='ShowcaseScreen',Decor='DecorScreen',Mine='MineScreen',Halloween='HalloweenScreen'}
kitScreens.Shelter='ShelterScreen' -- [WP-D2] DOG SHELTER (DogEconomyOpen('Shelter') from the ShelterPrompt)
N.KitScreens=kitScreens
local function kitScreen(page,arg)
 local name=kitScreens[aliases[page]or page];if not name then return false end
 local module=script.Parent:FindFirstChild(name);if not module then return false end
 local ok,screen=pcall(require,module)
 if not ok or type(screen)~='table'or type(screen.Open)~='function'then warn('DOGROTS '..name..': '..tostring(screen));return false end
 local opened,err=pcall(screen.Open,arg,page);if not opened then warn('DOGROTS '..name..' open: '..tostring(err))end
 return true
end
do
 local openPage,openScreen=N.OpenPage,N.OpenScreen
 function N.OpenPage(page,message)
  if kitScreen(page,message)then return end
  return openPage(page,message)
 end
 function N.OpenScreen(page,state)
  if kitScreen(page,state)then return end
  return openScreen(page,state)
 end
end
-- Watchdog [WP-D2] ------------------------------------------------------------------------------
-- Is the current owner's surface on screen? Unknown owners count as visible (never auto-closed).
local playerGui=player:FindFirstChildOfClass('PlayerGui')
local function kitWindowVisible()
 local layer=playerGui and playerGui:FindFirstChild('KitWindows')
 if not(layer and layer:IsA('LayerCollector')and layer.Enabled)then return false end
 for _,child in ipairs(layer:GetChildren())do if child:IsA('GuiObject')and child.Visible then return true end end
 return false
end
N.Surfaces={
 Kit=kitWindowVisible,
 Page=function()return main.Visible end,
 Screen=function()return main.Visible end,
 Service=function()return gui.ServiceMenus.Visible end,
 Map=function()local map=mapOverlay();return map~=nil and map.Visible end,
 Community=function()local g=playerGui and playerGui:FindFirstChild('CommunityServices');return g~=nil and g:IsA('LayerCollector')and g.Enabled end,
 RewardMachineWorld=function()local panel=gui:FindFirstChild('RewardMachineWorldPanel');return panel~=nil and panel.Visible end,
 -- Reward cards live in RewardReveal; cinematics that borrow the Reward owner (lab machines) have no overlay of their
 -- own, so a reward owner counts as shown for a grace period after BeginReward.
 Reward=function()
  if gui:FindFirstChild('RewardReveal')then return true end
  local top=playerGui and playerGui:FindFirstChild('KitOverlay')
  if top and top:FindFirstChild('LabSkip')then return true end
  return os.clock()-(N.RewardAt or 0)<45
 end,
}
function N.RegisterSurface(owner,fn)if type(owner)=='string'and type(fn)=='function'then N.Surfaces[owner]=fn end end
N.WatchdogGrace=2
-- The invariant of the Studio probe (docs/halloween2/SHELTER_TEST.md): OpenMenu==nil <=> the HUD owns navigation
-- <=> ProximityPromptService.Enabled and no Menu control lock.
function N.Invariant()
 local openMenu=gui:GetAttribute('OpenMenu')
 if N.Owner=='HUD'then
  if openMenu~=nil then return false,'HUD owner with OpenMenu='..tostring(openMenu)end
  if not Prompts.Enabled then return false,'HUD owner with ProximityPromptService disabled'end
  if controlLocks.Menu then return false,'HUD owner holds the Menu control lock'end
  return true,'HUD'
 end
 if openMenu==nil then return false,'owner '..tostring(N.Owner)..' without OpenMenu'end
 return true,tostring(N.Owner)..':'..tostring(openMenu)
end
task.spawn(function()
 local hiddenSince,seen=nil,-1
 while gui.Parent do
  task.wait(1)
  local ok,err=pcall(function()
   if seen~=N.AcquireCount then seen=N.AcquireCount;hiddenSince=nil end
   local consistent,why=N.Invariant()
   if N.Owner=='HUD'then
    hiddenSince=nil
    if not consistent then
     warn('DOGROTS navigation watchdog: '..why..'; restoring the HUD state')
     if gui:GetAttribute('OpenMenu')~=nil then N.Close()else applyNavigation()end
    end
    return
   end
   local visible=consistent
   local check=N.Surfaces[N.Owner]
   if visible and check then local okCheck,value=pcall(check);visible=(not okCheck)or value==true end
   if visible or UIS:GetFocusedTextBox()then hiddenSince=nil;return end
   hiddenSince=hiddenSince or os.clock()
   if os.clock()-hiddenSince>=N.WatchdogGrace then
    warn('DOGROTS navigation watchdog: '..tostring(N.Owner)..' has no visible surface ('..tostring(why)..'); back to the HUD')
    hiddenSince=nil
    N.Close()
   end
  end)
  if not ok then warn('DOGROTS navigation watchdog: '..tostring(err))end
 end
end)
Theme.AttachNavigation(gui,N);Theme.BindStandalone(gui,N)
 require(script.Parent.BuffHUD).Start(gui)
require(script.Parent.OnboardingGuide).Start(gui,N)
return N
