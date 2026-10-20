-- Global Fix 1: a non-modal, progression-aware tutorial for the full DOGROTS loop.
local Players=game:GetService('Players')
local RS=game:GetService('ReplicatedStorage')
local Http=game:GetService('HttpService')
local UIS=game:GetService('UserInputService')
local GuiService=game:GetService('GuiService')
local Guide={}
local controller

-- Active Mining has its own LocalScript (StarterPlayerScripts.MiningClient). Strength is a branch of the
-- UPGRADE TREE; the mutation lab is the nuclear tower (step 13).

local LAST=17
local cards={
 [0]={Title='WELCOME TO DOGROTS',Icon='Dogs',Body='You start with Cash and an empty yard. This guide walks you through the real loop: your dogs dig, you sell, level up, grow the UPGRADE TREE and mine ore in your own quarry.',Button='START THE GUIDE'},
 [1]={Title='1 · BUY YOUR FIRST DOG',Icon='Dogs',Body="Walk to THE DOG's tongue and buy an affordable dog. Every dog is a worker for your yard; rarer dogs cost much more and become long-term goals.",Button='SHOW THE DOG',Destination='THE DOG'},
 [2]={Title='2 · PUT THE DOG TO WORK',Icon='Yard',Body='Back in your yard, walk up to an empty kennel and assign the dog to a dig slot. Only assigned dogs dig.',Button='SHOW MY YARD',Destination='Your yard'},
 [3]={Title='3 · WAIT FOR A DIG',Icon='Inventory',Body='Dogs dig in cycles. Ordinary finds fill your yard storage, rare discoveries go to your INVENTORY. A dog never digs a layer you have not unlocked.',Button='VIEW MY DOGS',Page='Dogs'},
 [4]={Title='4 · SELL YOUR FINDS',Icon='Coins',Body='Take ordinary finds to the Collector in your yard and sell them. Cash comes from the loop: dig → collect → sell → reinvest.',Button='SHOW COLLECTOR',Destination='Collector'},
 [5]={Title='5 · REACH LEVEL 2',Icon='Star',Body='XP comes from dog digs, selling, mining ore, unlocking depths and buying upgrades. Reach Level 2: higher levels open deeper layers and stronger upgrades.',Button='VIEW MY DOGS',Page='Dogs'},
 [6]={Title='6 · GROW YOUR UPGRADE TREE',Icon='Records',Body='Open the UPGRADE TREE with the button below or in MY YARD. Tap a glowing node, read its bonus and press BUY. Every node has a Cash price and a level requirement.',Button='OPEN UPGRADE TREE',Page='UpgradeTree'},
 [7]={Title='7 · MINE ORE IN YOUR QUARRY',Icon='Dig',Body='The ore quarry is next to your kennels. Buy a pickaxe at the PICKAXES stall: it goes to your inventory, so you can hold it anywhere. Then mine: tap each ring when it shrinks onto the target. Every hit pays Coins.',Button='SHOW ORE QUARRY',Destination='MiningCorner'},
 [8]={Title='8 · BUILD YOUR STRENGTH',Icon='EnergySnack',Body='Strength is part of the UPGRADE TREE now: buy a node of the STRENGTH branch (start with IRON GRIP). Better pickaxes need both Coins and Strength, and Strength makes every hit hit harder.',Button='OPEN STRENGTH BRANCH',Page='UpgradeTree'},
 [9]={Title='9 · PICKAXES & ORES',Icon='Dig',Body='16 pickaxes and 12 ores. Every pickaxe has its own look and swing; cheap ones need many hits, better ones add crits, combos, extra rings, ore luck and bonus Coins. Ores reroll from Limestone to the rare Void Crystal.',Button='CONTINUE',Info=true},
 [10]={Title='10 · DOG LINE + DEPTHS',Icon='Bones',Body='THE DOG tongue is where you expand your team with new dogs; prices rise sharply with rarity. Layers are hard progression gates: Caverns opens at Level 5, then Ancient Ruins, Cursed Depths and THE VOID. Dogs can never pull loot from a layer you have not unlocked.',Button='OPEN LAYERS & CONTINUE',Page='Layers',Info=true},
 [11]={Title='11 · LUCKY BLOCKS',Icon='RareBlock',Body='Lucky Blocks can be bought from the tongue and placed on Lucky Pads in your yard. Higher tiers cost much more and contain stronger reward pools.',Button='SHOW THE TONGUE & CONTINUE',Destination='THE DOG',Info=true},
 [12]={Title='12 · DOG-O-MATIC',Icon='RewardMachine',Body='DOG-O-MATIC spends DOG TOKENS for a random prize. A free token refills five hours after use; paid token bundles are optional. Keep one free inventory slot before spinning.',Button='OPEN DOG-O-MATIC & CONTINUE',Page='RewardMachine',Info=true},
 [13]={Title='13 · NUCLEAR MUTATION TOWER',Icon='Lab',Body='The Lab is a giant nuclear cooling tower now. At its console press START MUTATION, pick a dog and watch the show: a reroll can make it Shiny, Golden, Corrupted, Glitched or Void, each with its own glow and income bonus. The first try is free.',Button='SHOW THE TOWER & CONTINUE',Destination='Mutation lab',Info=true},
 [14]={Title='14 · DOGDEX & MUSEUM',Icon='DogDex',Body='DogDex tracks what you have discovered. Museum progress, sets, records and collection milestones give you reasons to hunt beyond raw Cash.',Button='OPEN DOGDEX & CONTINUE',Page='DogDex',Info=true},
 [15]={Title='15 · SAFE PLAYER TRADING',Icon='Trade',Body='Trading unlocks at Level 5 for both players. Invite a player, put dogs, items and artifacts on YOUR side, check the value bar, press READY, then HOLD CONFIRM after the short safety timer. Any change resets READY.',Button='OPEN TRADE & CONTINUE',Page='Trade',Info=true},
 [16]={Title='16 · EVENTS & RETURN REWARDS',Icon='Events',Body='Events are bonuses, not free-money farms: stay active and dig to qualify. EVENTS also holds Daily Rewards and playtime milestones. Offline income is only a small welcome-back bonus.',Button='OPEN EVENTS & CONTINUE',Page='Events',Info=true},
 [17]={Title='YOU KNOW THE WHOLE LOOP',Icon='Star',Body='Buy dogs → assign → dig → sell → level up → upgrade → unlock depth. Between dog cycles, mine ore in your quarry, grow Strength in the UPGRADE TREE and buy better pickaxes. Then chase Lucky Blocks, DOG-O-MATIC, the nuclear tower, DogDex, Museum, events and safe trades.',Button='FINISH GUIDE'},
}

function Guide.Replay()if controller then controller.Replay()end end
function Guide.Start(gui,navigation)
 if controller then return controller end
 local U=require(script.Parent.UITheme)
 local player=Players.LocalPlayer
 local remote=RS:WaitForChild('DogEconomyRequest')
 local root=U.New('Frame',{Name='OnboardingGuide',Visible=false,Active=false,BackgroundColor3=U.Colors.panel,BorderSizePixel=0,ZIndex=75},gui)
 U.Round(root,16);U.Stroke(root,U.Colors.edge,3)
 local accent=U.New('Frame',{Name='Accent',BackgroundColor3=U.Colors.blue,BorderSizePixel=0,Position=UDim2.fromOffset(12,12),Size=UDim2.fromOffset(4,40),ZIndex=76},root);U.Round(accent,2)
 local heading=U.Text(root,'',25,8,300,21,13,U.Colors.blue,true);heading.Name='ProgressCaption';heading.ZIndex=77
 local title=U.Text(root,'',25,30,330,30,20,U.Colors.text,true);title.Name='TaskTitle';title.ZIndex=77
 local body=U.Text(root,'',18,68,400,84,15,U.Colors.text,false);body.Name='TaskBody';body.ZIndex=77;body.TextYAlignment=Enum.TextYAlignment.Top
 local iconHolder=U.New('Frame',{Name='TaskIcon',BackgroundTransparency=1,Size=UDim2.fromOffset(42,42),ZIndex=76},root)
 local pending=false;local collapsed=false;local replayStep=nil;local alive=true;local errorText=nil;local lastIcon=nil;local showAfter=os.clock()+2
 local render
 local function stage()return replayStep or math.clamp(tonumber(player:GetAttribute('TutorialStep'))or 0,0,LAST)end
 local function request(action)
  if pending then return end
  pending=true;errorText=nil;render()
  task.spawn(function()
   local id=Http:GenerateGUID(false):gsub('-','')
   local transport,ok=pcall(function()return remote:InvokeServer('Tutorial',{Action=action},id)end)
   if not alive then return end
   pending=false
   if not transport or not ok then errorText='Could not save the guide. Tap again to retry.'end
   render()
  end)
 end
 local myYard
 local function go(card)
  -- The quarry step: the world marker already points at the stall / ore, so a player who is already
  -- in the quarry must not get a waypoint back to the yard entrance.
  local step=stage()
  if step==8 then
   -- STRENGTH: the upgrade tree, opened on its STRENGTH branch when the screen supports a focus
   local ok=pcall(function()
    local screen=require(script.Parent:FindFirstChild('UpgradeTreeScreen'))
    if screen and screen.Open then screen.Open('IronGrip')else error('no screen')end
   end)
   if ok then return end
  end
  if step==7 then
   local yard=myYard();local corner=yard and yard:FindFirstChild('MiningCorner')
   local pad=corner and corner:FindFirstChild('MiningPad')
   local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   if pad and root and pad:IsA('BasePart')and root:IsA('BasePart')and(root.Position-pad.Position).Magnitude<60 then render();return end
  end
  if card.Page then navigation.OpenPage(card.Page)
  elseif card.Destination then navigation.Navigate(card.Destination)end
 end
 local primary=U.Button(root,'Action','',18,166,280,42,function()
  local step=stage();local card=cards[step]
  if replayStep~=nil then
   if replayStep<LAST then replayStep+=1 else replayStep=nil end
   errorText=nil;render();return
  end
  if step==0 then request('Start')
  elseif step==LAST then request('Finish')
  elseif card.Info then request('Next');task.defer(function()go(card)end)
  else go(card)end
 end,U.Colors.green)
 local skip=U.Button(root,'Skip','SKIP',306,166,100,42,function()
  if replayStep~=nil then replayStep=nil;render()else request(stage()==LAST and'Finish'or'Skip')end
 end,U.Colors.blue)
 local collapse=U.Button(root,'Collapse','-',0,0,44,44,function()collapsed=not collapsed;render()end,U.Colors.blue)
 for _,button in ipairs({primary,skip,collapse})do button.ZIndex=77;button.Caption.ZIndex=78 end
 local progress={}
 for i=1,LAST-1 do progress[i]=U.New('Frame',{Name='Step'..i,Size=UDim2.fromOffset(20,4),BackgroundColor3=U.Colors.secondary,BorderSizePixel=0,ZIndex=76},root);U.Round(progress[i],2)end
 local marker=U.New('BillboardGui',{Name='TutorialWorldMarker',Enabled=false,ResetOnSpawn=false,AlwaysOnTop=false,MaxDistance=140,Size=UDim2.fromOffset(220,48),StudsOffsetWorldSpace=Vector3.new(0,5,0),LightInfluence=0},player:WaitForChild('PlayerGui'))
 local markerText=U.Center(marker,'',4,2,212,42,18,U.Colors.gold,true);markerText.TextStrokeTransparency=0;markerText.TextStrokeColor3=U.Colors.edge
 local function part(object)
  if not object then return end
  if object:IsA('BasePart')then return object end
  return object:FindFirstChildWhichIsA('BasePart',true)
 end
 function myYard()
  local map=workspace:FindFirstChild('DOGROTS_District');local yards=map and map:FindFirstChild('04_PlayerYards')
  if not yards then return end
  for _,yard in ipairs(yards:GetChildren())do
   if yard:GetAttribute('OwnerUserId')==player.UserId and yard:GetAttribute('YardId')==player:GetAttribute('YardId')then return yard end
  end
 end
 local function target(step)
  local map=workspace:FindFirstChild('DOGROTS_District')
  if step==1 then local line=map and map:FindFirstChild('03_DogLine');return part(line),'BUY YOUR FIRST DOG'end
  if step==13 then local lab=map and map:FindFirstChild('05_MutationLab');return part(lab and lab:FindFirstChild('InteractionAnchor')),'START MUTATION'end                            
  local yard=myYard();if not yard then return end
  if step==2 or step==3 then return part(yard:FindFirstChild('DigSlot_1',true)or yard),'YOUR DIG KENNEL'end
  if step==4 then return part(yard:FindFirstChild('SellAnchor',true)),'YOUR COLLECTOR'end
  -- step 6 / 8: the UPGRADE TREE is a screen (no world sign any more), so no marker
  -- The quarry step follows the player: the PICKAXES stall -> the ore.
  local corner=yard:FindFirstChild('MiningCorner')
  if step==7 and corner then
   if (player:GetAttribute('MiningPickaxeOwned')or 0)<1 then return part(corner:FindFirstChild('MiningPickaxeShop')),'BUY A PICKAXE'end
   return part(corner:FindFirstChild('MiningOreCore')),'HIT THE ORE'
  end
 end
 render=function()
  if not alive then return end
  local active=replayStep~=nil or player:GetAttribute('TutorialActive')==true
  local modal=gui:GetAttribute('OpenMenu')~=nil or(gui:GetAttribute('ModalOwnerCount')or 0)>0 or gui:GetAttribute('MiningActive')==true
  root.Visible=active and not modal and player:GetAttribute('EconomyReady')==true and os.clock()>=showAfter
  marker.Enabled=false
  if not root.Visible then return end
  local step=stage();local card=cards[step]
  if not card then root.Visible=false;return end
  local left,top,width,height=U.SafeArea(gui);local narrow=width<600;local touch=UIS.TouchEnabled
  local cardW=math.min(narrow and 342 or touch and 380 or 462,width-24);local compact=cardW<410
  local cardH=collapsed and 48 or(compact and 246 or 232);local bottom=touch and height>width and 235 or 16
  root.Size=UDim2.fromOffset(cardW,cardH);root.Position=UDim2.fromOffset(left+math.floor((width-cardW)/2),top+math.max(8,height-bottom-cardH))
  heading.Text=replayStep~=nil and('HOW TO PLAY  '..(step+1)..' / '..(LAST+1))or step==0 and'INTERACTIVE GUIDE' or step==LAST and'GUIDE COMPLETE'or('GUIDE  '..step..' / '..(LAST-1))
  title.Text=card.Title;title.TextSize=compact and 16 or 19;title.Position=UDim2.fromOffset(25,collapsed and 13 or 30);title.Size=UDim2.fromOffset(cardW-(collapsed and 78 or 120),collapsed and 26 or 30)
  heading.Visible=not collapsed;body.Visible=not collapsed;iconHolder.Visible=not collapsed;primary.Visible=not collapsed;skip.Visible=not collapsed
  accent.Position=UDim2.fromOffset(12,collapsed and 10 or 12);accent.Size=UDim2.fromOffset(4,collapsed and 28 or 40)
  collapse.Position=UDim2.fromOffset(cardW-47,2);collapse.Caption.Text=collapsed and'+'or'-';collapse.Caption.TextSize=24
  iconHolder.Position=UDim2.fromOffset(cardW-86,15)
  if card.Icon~=lastIcon then
   iconHolder:ClearAllChildren();local icon=U.Icon(iconHolder,card.Icon,0,0,42)
   for _,child in ipairs(icon:GetDescendants())do if child:IsA('GuiObject')then child.ZIndex=78 end end
   icon.ZIndex=78;lastIcon=card.Icon
  end
  body.Text=errorText or card.Body;body.TextSize=compact and 13 or 15;body.Position=UDim2.fromOffset(18,68);body.Size=UDim2.fromOffset(cardW-36,cardH-132)
  local buttonY=cardH-58;local primaryW=cardW-138
  primary.Position=UDim2.fromOffset(18,buttonY);primary.Size=UDim2.fromOffset(primaryW,42);primary.Caption.Size=UDim2.new(1,-12,1,-4);primary.Caption.TextSize=compact and 12 or 14
  primary.Caption.Text=pending and'SAVING...'or replayStep~=nil and(step==LAST and'DONE'or'NEXT')or card.Button
  skip.Position=UDim2.fromOffset(cardW-112,buttonY);skip.Size=UDim2.fromOffset(94,42);skip.Caption.Size=UDim2.new(1,-12,1,-4);skip.Caption.TextSize=14
  skip.Caption.Text=replayStep~=nil and'CLOSE'or step==LAST and'CLOSE'or'SKIP'
  U.SetButtonEnabled(primary,not pending);U.SetButtonEnabled(skip,not pending)
  local count=LAST-1;local segment=(cardW-36-(count-1)*3)/count
  for i,bar in ipairs(progress)do
   bar.Visible=not collapsed;bar.Position=UDim2.fromOffset(18+(i-1)*(segment+3),cardH-8);bar.Size=UDim2.fromOffset(segment,4)
   bar.BackgroundColor3=step>i and U.Colors.green or step==i and U.Colors.gold or U.Colors.secondary
  end
  if replayStep==nil and not collapsed then
   local object,label=target(step)
   if object then
    -- Mining markers sit above tall props and must stay visible behind the ore pile.
    local mining=step==7
    local board=marker::BillboardGui
    board.AlwaysOnTop=mining
    board.StudsOffsetWorldSpace=Vector3.new(0,mining and(object.Name=='MiningOreCore'and 8 or 4.5)or 5,0)
    marker.Adornee=object;markerText.Text=label;marker.Enabled=true
   end
  end
 end
 local connections={}
 local function connect(signal,callback)table.insert(connections,signal:Connect(callback))end
 for _,name in ipairs({'TutorialStep','TutorialActive','EconomyReady','YardId','MiningPickaxeOwned'})do connect(player:GetAttributeChangedSignal(name),render)end
 for _,name in ipairs({'OpenMenu','ModalOwnerCount','MiningActive'})do connect(gui:GetAttributeChangedSignal(name),render)end
 connect(gui:GetPropertyChangedSignal('AbsoluteSize'),render);connect(GuiService:GetPropertyChangedSignal('TopbarInset'),render);connect(UIS:GetPropertyChangedSignal('TouchEnabled'),render)
 controller={Replay=function()navigation.Close();replayStep=0;collapsed=false;errorText=nil;showAfter=0;render()end}
 connect(gui.Destroying,function()alive=false;marker:Destroy();for _,connection in ipairs(connections)do connection:Disconnect()end;controller=nil end)
 task.spawn(function()while alive and gui.Parent do render();task.wait(.5)end end)
 render();return controller
end
return Guide
