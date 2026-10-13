-- The PAWPAD navigation owner. All presentation lives under one ScreenGui.
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
local playerControls,controlsDisabledByUI
local promptsBeforeMenu
local function menuControls(active)
 if active then
  if promptsBeforeMenu==nil then promptsBeforeMenu=Prompts.Enabled end
  Prompts.Enabled=false
 elseif promptsBeforeMenu~=nil then
  Prompts.Enabled=promptsBeforeMenu;promptsBeforeMenu=nil
 end
 if not playerControls then return end
 if active and not controlsDisabledByUI then
  if playerControls.controlsEnabled~=false then playerControls:Disable();controlsDisabledByUI=true end
 elseif not active and controlsDisabledByUI then
  controlsDisabledByUI=false;playerControls:Enable()
 end
end
task.spawn(function()
 local module=player:WaitForChild('PlayerScripts'):WaitForChild('PlayerModule',15)
 if not module then return end
 local ok,controls=pcall(function()return require(module):GetControls()end)
 if ok and controls then playerControls=controls;menuControls(N.ModalOwnerCount>0)end
end)
function N.Acquire(owner,page)
 local previousOwner=N.Owner
	N.Owner=owner
 -- Navigation owns one window family; nested dialogs borrow that owner.
 N.ModalOwnerCount=owner=='HUD'and 0 or 1
 gui:SetAttribute('ModalOwnerCount',N.ModalOwnerCount)
 menuControls(N.ModalOwnerCount>0)
 if owner~='RewardMachineWorld'then local toast=gui:FindFirstChild('RewardMachineRewardToast');if toast then toast:Destroy()end end
	if owner == 'HUD' then
		Actions:UnbindAction('PawpadMovement')
	else
		Actions:BindActionAtPriority(
			'PawpadMovement',
			function()
				return Enum.ContextActionResult.Sink
			end,
			false,
			2500,
			Enum.PlayerActions.CharacterForward,
			Enum.PlayerActions.CharacterBackward,
			Enum.PlayerActions.CharacterLeft,
			Enum.PlayerActions.CharacterRight,
			Enum.PlayerActions.CharacterJump
		)
	end
 if screens then screens:Hide()end
	local reward = gui:FindFirstChild('RewardReveal')

	if reward and owner ~= 'HUD' then
		reward:Destroy()
	end
 local map=mapOverlay();if map and owner~='Map'then map.Visible=false end
 -- Hide UI (StarterPlayerScripts.HideUI): any menu brings the interface back.
 if owner~='HUD'and gui:GetAttribute('UIHidden')then gui:SetAttribute('UIHidden',nil)end
 -- One open / close sound for every menu family (kit windows play the same cue; Kit.Sound drops the repeat).
 if previousOwner=='HUD'and owner~='HUD'then Sound.Play('Open')elseif previousOwner~='HUD'and owner=='HUD'then Sound.Play('Close')end
 main.Visible=false;gui.ServiceMenus.Visible=false;gui.Backdrop.Visible=owner~='HUD';gui.HUD.Visible=owner=='HUD'and not gui:GetAttribute('UIHidden')
 gui.InventoryToast.Visible=false
 for _,p in ipairs(pages:GetChildren())do if p:IsA('GuiObject')then p.Visible=false end end
 local keyboard=pages:FindFirstChild('SearchKeyboard');if keyboard then keyboard.Visible=false end
 gui:SetAttribute('OpenMenu',owner~='HUD'and(page or owner)or nil)
 gui:SetAttribute('MenuFamily',owner~='HUD'and owner or nil)
 gui:SetAttribute('RewardMachineWorldOpen',owner=='RewardMachineWorld')
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
 N.RewardEpoch+=1;N.Acquire('Reward','Reward')
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
connect(gui.Destroying,function()menuControls(false);Actions:UnbindAction('PawpadMovement');for _,c in ipairs(connections)do c:Disconnect()end;table.clear(N.Pending)end)
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
 Showcase='ShowcaseScreen',Decor='DecorScreen',Mine='MineScreen'}
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
Theme.AttachNavigation(gui,N);Theme.BindStandalone(gui,N)
 require(script.Parent.BuffHUD).Start(gui)
require(script.Parent.OnboardingGuide).Start(gui,N)
return N
