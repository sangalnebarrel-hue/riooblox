-- The pickaxe in the inventory (ServerScriptService.MiningWorld gives every owner of a pickaxe a
-- Tool in the Backpack / hotbar). The Tool is only the hotbar entry: the pickaxe you see is the
-- model "MiningHeldPickaxe" the server welds to the character (hand or back, Models.Mount), which
-- PickFX animates (living pickaxes) and gives a swing trail. This client side:
--   Equip()   draws it from the backpack into the hand (a mining session calls it on start)
--   clicking with the pickaxe in the hand outside a session swings it; close to your own ore it
--   starts mining right away
--   equipping / unequipping moves the welded model to the hand / back at once (the server writes
--   the same joint a round trip later and stays the authority)
--   first person: the pickaxe in your hand stays visible (the camera fades the body, see below)
--   Studio only: reports a held pickaxe that does not move with its limb
--   sounds (MiningAudio, the pickaxe's sound kit): the swish of a swing, the draw on equip, a
--   holster click on unequip and, for Laughsaw / TV-Head / Scarlet Anime Scythe / Twin Claws / Butterfly Catcher / LEGO Hand / Pickaxe 67 / Rotten Slime Slug / Toothy Alarm Clock / Zombie-Frankenstein / Clown Chronomord / Nasty Octopus / Hand of Fate, a faint idle loop while it is held
--   inspect (pickaxes with Inspect=true: TV-Head, Gummy Horror, Ponycorn, Scarlet Anime Scythe, Twin Claws, Butterfly Catcher, Laughsaw, LEGO Hand, Pickaxe 67, Rotten Slime Slug, Toothy Alarm Clock, Zombie-Frankenstein, Clown Chronomord, Nasty Octopus, Hand of Fate): T / gamepad Y / a touch button while it is in
--   the hand and no session runs: the inspect pose (Anim), its look (PickFX) and sound (Audio)
local Players=game:GetService('Players')
local RunService=game:GetService('RunService')
local ContextActionService=game:GetService('ContextActionService')
local Tool={}
local Skins=(function()local ok,m=pcall(function()return require(game:GetService('ReplicatedStorage'):WaitForChild('Halloween',10):WaitForChild('PickaxeSkins',10))end);if ok and type(m)=='table'then return m end;return{For=function(_,d)return d end}end)() -- Halloween pickaxe skins (cosmetic visual def)

function Tool.new(ctx)
 local self:any={}
 local player=ctx.Player
 local function isPick(c)return c:IsA('Tool')and c:GetAttribute('MiningPickaxeTool')==true end
 local function defOf(tool)return Skins.For(player,ctx.M.Pickaxes[tool:GetAttribute('Level')or 1]or ctx.M.Pickaxes[1])end
 local function find()
  local character=player.Character
  for _,holder in ipairs({character,player:FindFirstChildOfClass('Backpack')})do
   if holder then for _,c in ipairs(holder:GetChildren())do if isPick(c)then return c end end end
  end
  return nil
 end
 self.Find=find
 function self.Held()
  local tool=find();return tool~=nil and tool.Parent==player.Character
 end
 function self.Equip()
  local tool=find();local character=player.Character
  local hum=character and character:FindFirstChildOfClass('Humanoid')
  if tool and hum and hum.Health>0 and tool.Parent~=character then hum:EquipTool(tool)end
 end

 -- The server-welded model of the local character and its joint (nil while there is none).
 local function heldJoint()
  local character=player.Character
  local held=character and character:FindFirstChild('MiningHeldPickaxe')
  local handle=held and held:IsA('Model')and(held.PrimaryPart or held:FindFirstChild('Handle'))
  local grip=handle and handle:FindFirstChild('HandGrip')
  if not(grip and grip:IsA('Weld'))then return nil end
  return held,handle,grip,character
 end
 -- Local prediction of MiningWorld.syncHeld: the same limb and offset (Models.MountJoint), written
 -- only on this client; the server's write of the same values follows.
 local function predict(mount)
  local held,_,grip,character=heldJoint()
  if not(held and ctx.Models and ctx.Models.MountJoint)then return end
  local limb,c0=ctx.Models.MountJoint(character,mount,held)
  if limb and(grip.Part0~=limb or grip.C0~=c0)then grip.C0=c0;grip.Part0=limb end
 end
 local function sessionLive()
  if ctx.Mine and ctx.Mine.Active then return true end
  if ctx.HalloweenStrike and ctx.HalloweenStrike.Active then return true end
  local ok,now=pcall(function()return workspace:GetServerTimeNow()end)
  return(player:GetAttribute('MiningActiveUntil')or 0)>=(ok and now or os.time())
 end

 -- INSPECT -----------------------------------------------------------------------------------
 local INSPECT_ACTION='DOGROTS_InspectPickaxe'
 local inspectBound=false
 local lastInspect=0
 local inspectHinted=false
 local function stopInspect()
  if ctx.Anim and ctx.Anim.CancelInspect then ctx.Anim.CancelInspect()end
  if ctx.PickFX and ctx.PickFX.Inspect then ctx.PickFX.Inspect(player.Character,0)end
 end
 local function onInspect(_,state)
  if state~=Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
  local tool=find()
  if not(tool and tool.Parent==player.Character)then return Enum.ContextActionResult.Pass end
  if(ctx.Mine and ctx.Mine.Active)or(ctx.HalloweenStrike and ctx.HalloweenStrike.Active)or(ctx.MenuOpen and ctx.MenuOpen())then return Enum.ContextActionResult.Pass end
  local def=defOf(tool)
  if not def.Inspect then return Enum.ContextActionResult.Pass end
  local length=(ctx.Anim and ctx.Anim.INSPECT_TIME)or 2.6
  if os.clock()-lastInspect<length+.1 then return Enum.ContextActionResult.Sink end
  lastInspect=os.clock()
  if ctx.Anim and ctx.Anim.Inspect then ctx.Anim.Inspect(nil,def.Swing)end
  if ctx.PickFX and ctx.PickFX.Inspect then ctx.PickFX.Inspect(player.Character,length)end
  if ctx.Audio then ctx.Audio.Pickaxe('Inspect',def)end
  return Enum.ContextActionResult.Sink
 end
 -- Bound only while an inspectable pickaxe is in the hand (frees T / Y for everything else).
 local function syncInspect()
  local tool=find()
  local want=tool~=nil and tool.Parent==player.Character and defOf(tool).Inspect==true
  if want==inspectBound then return end
  inspectBound=want
  if want then
   ContextActionService:BindAction(INSPECT_ACTION,onInspect,true,Enum.KeyCode.T,Enum.KeyCode.ButtonY)
   local ru=ctx.Text and ctx.Text.IsRussian and ctx.Text.IsRussian()
   pcall(function()ContextActionService:SetTitle(INSPECT_ACTION,ru and'ОСМОТР'or'INSPECT')end)
   pcall(function()ContextActionService:SetPosition(INSPECT_ACTION,UDim2.new(1,-170,1,-150))end)
   if not inspectHinted and ctx.Hud and ctx.Hud.Toast and ctx.U then
    inspectHinted=true
    task.delay(.8,function()
     if inspectBound then ctx.Hud.Toast(ru and'Нажми T, чтобы осмотреть кирку'or'Press T to inspect your pickaxe',ctx.U.Colors.green,4)end
    end)
   end
  else
   ContextActionService:UnbindAction(INSPECT_ACTION)
   stopInspect()
  end
 end
 self.SyncInspect=syncInspect

 local wired=setmetatable({},{__mode='k'})
 local lastSwing=0
 local function wire(tool)
  if wired[tool]then return end
  wired[tool]=true
  tool.Activated:Connect(function()
   if(ctx.Mine and ctx.Mine.Active)or(ctx.HalloweenStrike and ctx.HalloweenStrike.Active)then return end
   if os.clock()-lastSwing<.32 then return end
   lastSwing=os.clock()
   if ctx.PickFX and ctx.PickFX.Inspect then ctx.PickFX.Inspect(player.Character,0)end -- a swing ends an inspect
   local def=Skins.For(player,ctx.M.Pickaxes[tool:GetAttribute('Level')or 1])
   if ctx.Anim then ctx.Anim.Swing(1,nil,def and def.Swing)end
   if ctx.PickFX then ctx.PickFX.HitPulse(player.Character,.8)end
   if ctx.Audio then ctx.Audio.Pickaxe('Swing',def,nil,{Air=true})end -- timed to the animation
   -- In reach of your own ore: start a mining session.
   local corner=ctx.World and ctx.World.MyCorner and ctx.World.MyCorner()
   local core=corner and corner:FindFirstChild('MiningOreCore')
   local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   if core and root and core:IsA('BasePart')and(root.Position-core.Position).Magnitude<16 and ctx.Mine and not(ctx.MenuOpen and ctx.MenuOpen())then
    task.delay(.25,function()if not ctx.Mine.Active then ctx.Mine.Enter(corner)end end)
   end
  end)
  tool.Equipped:Connect(function()
   local held=heldJoint()
   if held then pcall(predict,held:GetAttribute('Grip')=='Glove'and'Glove'or'Hand')end
   if ctx.Audio then local def=defOf(tool);ctx.Audio.Pickaxe('Draw',def);ctx.Audio.StartIdle(def)end
   task.defer(syncInspect)
  end)
  tool.Unequipped:Connect(function()
   task.defer(syncInspect)
   if ctx.Audio then
    ctx.Audio.StopIdle()
    -- The holster click only when it went back into the hotbar (not when the character is removed).
    task.defer(function()if tool.Parent and tool.Parent:IsA('Backpack')then ctx.Audio.Play('Holster')end end)
   end
   -- Back to the back, as the server will do: not while a session keeps it in the hand, not for
   -- the claws (the server removes them) and not under a worn Back accessory (removed as well).
   local held,_,_,character=heldJoint()
   if not held or held:GetAttribute('Grip')=='Glove'or sessionLive()then return end
   if character:FindFirstChild('DOGROTS_Accessory_Back')then return end
   pcall(predict,'Back')
  end)
  if ctx.Audio then
   -- Removed while held (level 0, character destroyed): the idle loop goes with it. A new level
   -- while held (the Tool is renamed in place, no re-equip): the new pickaxe's idle loop.
   tool.AncestryChanged:Connect(function()if not tool:IsDescendantOf(game)then ctx.Audio.StopIdle()end end)
   tool:GetAttributeChangedSignal('Level'):Connect(function()
    if player.Character and tool.Parent==player.Character then ctx.Audio.StartIdle(defOf(tool))end
   end)
  end
  do
   tool.AncestryChanged:Connect(function()task.defer(syncInspect)end)
   tool:GetAttributeChangedSignal('Level'):Connect(function()task.defer(syncInspect)end)
  end
 end
 local function watch(holder)
  if not holder then return end
  for _,c in ipairs(holder:GetChildren())do if isPick(c)then wire(c)end end
  holder.ChildAdded:Connect(function(c)if isPick(c)then task.defer(wire,c)end end)
 end
 local function onCharacter(character)
  task.defer(syncInspect)
  watch(character)
  task.spawn(function()watch(player:WaitForChild('Backpack',10))end)
 end
 if player.Character then onCharacter(player.Character)end
 player.CharacterAdded:Connect(onCharacter)
 -- The idle loop of a held pickaxe stops on death and respawn (a dead character keeps its Tool).
 if ctx.Audio then
  local function hookDeath(character)
   local hum=character:FindFirstChildOfClass('Humanoid')or character:WaitForChild('Humanoid',10)
   if hum and hum:IsA('Humanoid')then hum.Died:Connect(function()ctx.Audio.StopIdle()end)end
  end
  if player.Character then task.spawn(hookDeath,player.Character)end
  player.CharacterAdded:Connect(function(character)task.spawn(hookDeath,character)end)
  player.CharacterRemoving:Connect(function()ctx.Audio.StopIdle()end)
 end
 -- FIRST PERSON --------------------------------------------------------------------------------
 -- Zoomed into first person, the default camera's TransparencyController fades every part of the
 -- local character (LocalTransparencyModifier -> 1) except the parts inside a Tool, which is why
 -- hats vanish and tools stay. The pickaxe you see is a character child, not inside the Tool, so it
 -- would vanish with the body while the hotbar shows it held. While it sits in a hand, this undoes
 -- that fade right after the camera's update (one render priority later, before the frame is
 -- drawn). Only the camera's own fade is undone (the pickaxe at the same value as the limb it is
 -- welded to; the controller writes one value to the whole body), so a scene that hides just the
 -- pickaxe (the lab cinematic) keeps it hidden. On the back it fades with the body, like an
 -- accessory. Cost: a few property reads per frame; in full first person the controller rewrites
 -- the body every frame, so the pickaxe's parts are rewritten every frame too (from a cached list).
 local HAND_LIMBS={RightHand=true,LeftHand=true,['Right Arm']=true,['Left Arm']=true} -- Models.Mounts Hand / Glove / GloveL
 local HELD_NAMES={'MiningHeldPickaxe','MiningHeldPickaxeL'}
 local revealed={} -- held name -> the model whose camera fade this client undid (dropped with it)
 local looks={} -- held name -> {Model=, List=its BaseParts and Decals, Stale=}
 local function looksOf(name,model)
  local entry=looks[name]
  if entry and entry.Model==model and not entry.Stale then return entry.List end
  local list={}
  for _,d in ipairs(model:GetDescendants())do if d:IsA('BasePart')or d:IsA('Decal')then table.insert(list,d)end end
  entry={Model=model,List=list,Stale=false};looks[name]=entry
  local function stale()entry.Stale=true end
  model.DescendantAdded:Once(stale);model.DescendantRemoving:Once(stale)
  return list
 end
 local function fadeTo(name,model,value)
  for _,d in ipairs(looksOf(name,model))do if d.LocalTransparencyModifier~=value then d.LocalTransparencyModifier=value end end
 end
 local function keepVisible()
  local character=player.Character;if not character then return end
  for _,name in ipairs(HELD_NAMES)do
   local held=character:FindFirstChild(name)
   if revealed[name]and revealed[name]~=held then revealed[name]=nil end
   if looks[name]and looks[name].Model~=held then looks[name]=nil end
   local handle=held and held:IsA('Model')and(held.PrimaryPart or held:FindFirstChild('Handle'))
   local grip=handle and handle:IsA('BasePart')and handle:FindFirstChild('HandGrip')
   local limb=grip and grip:IsA('Weld')and grip.Part0
   if limb and limb:IsA('BasePart')then
    local body,own=limb.LocalTransparencyModifier,handle.LocalTransparencyModifier
    if HAND_LIMBS[limb.Name]then -- in a hand (also a client-side prediction a round trip early)
     if own>0 and math.abs(own-body)<.005 then fadeTo(name,held,0);revealed[name]=held end
    elseif revealed[name]then -- moved to the back: fade like the body again
     revealed[name]=nil
     if body>0 and own==0 then fadeTo(name,held,body)end
    end
   end
  end
 end
 local fpWarned=false
 RunService:BindToRenderStep('DOGROTS_HeldPickaxeFirstPerson',Enum.RenderPriority.Camera.Value+1,function()
  local ok,err=pcall(keepVisible)
  if not ok and not fpWarned then fpWarned=true;if ctx.Report then ctx.Report('held pickaxe first person: '..tostring(err))end end
 end)

 -- First pickaxe ever: say once where it went.
 local announced=false
 player:GetAttributeChangedSignal('MiningPickaxeOwned'):Connect(function()
  if announced then return end
  local owned=player:GetAttribute('MiningPickaxeOwned')or 0
  if owned==1 and ctx.Hud then
   announced=true
   task.delay(1.2,function()ctx.Hud.Toast(ctx.Text.Get('TOOL_EQUIP_HINT'),ctx.U.Colors.gold,5)end)
  end
 end)

 -- STUDIO DIAGNOSTIC (developer-facing, not translated): the held pickaxe must move with its limb.
 -- Two failed checks in a row (4 s, so a rebuild in progress never counts) report it once through
 -- ctx.Report (Output + the Studio panel) until it is attached again.
 if RunService:IsStudio()then
  task.spawn(function()
   local misses,reported=0,false
   while true do
    task.wait(2)
    local problem=nil
    local ok,err=pcall(function()
     local held,handle,grip,character=heldJoint()
     local hum=character and character:FindFirstChildOfClass('Humanoid')
     local root=character and character:FindFirstChild('HumanoidRootPart')
     if not(held and root and hum and hum.Health>0)then return end
     local limb=grip.Part0
     local attached=handle.AssemblyRootPart==root.AssemblyRootPart
     local dist=(limb and limb:IsA('BasePart'))and(handle.CFrame.Position-limb.CFrame.Position).Magnitude or math.huge
     if not attached or dist>4 or not(limb and limb.Parent==character)then
      problem=('held pickaxe detached: mount=%s limb=%s dist=%.1f sameAssembly=%s'):format(
       tostring(held:GetAttribute('Mount')),limb and limb:GetFullName()or'none',dist,tostring(attached))
     end
    end)
    if not ok then problem='held pickaxe check failed: '..tostring(err)end
    misses=problem and misses+1 or 0
    if problem and misses>=2 and not reported then
     reported=true
     if ctx.Report then ctx.Report(problem)end
    elseif not problem and reported then
     reported=false
     if ctx.Log then ctx.Log('held pickaxe attached again')end
    end
   end
  end)
 end
 return self
end

return Tool
