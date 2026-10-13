local C=require(game.ReplicatedStorage.LabConfig)
local Access=require(game.ReplicatedStorage.LabAccess)
local G=require(game.ReplicatedStorage.LabGenetics)
local R=require(script.Parent.Rules)
local L=require(script.Parent.LabRules)
local State=require(script.Parent.LabState)
local S={Quotes={},Pulse=0}
local function runtime()return require(script.Parent.Runtime)end
-- LabConfig.SimpleMode (the NUCLEAR MUTATION MACHINE, docs/LAB.md): the lab only rerolls one dog's variant
-- (Procedure 'Mutation' with its usual costs, odds, first free try, cooldown and held confirmation). The
-- other procedures stay in LabRules for SimpleMode=false (the old lab window) and are refused here.
local SIMPLE_KEYS={Procedure=true,Uids=true,PrimaryUid=true}
function S.Simple()return C.SimpleMode==true end
function S.Visit(player)
 R.Check(Access.CanUse(player),S.Simple()and'Walk up to the Mutation Machine console'or'Enter Mutation Lab and approach the genetics terminal')
end
-- Everything the lab window needs besides the snapshot: cooldown, the variant rows a reroll uses (world
-- event and the player's DogMutation bonus included) so the client shows the real odds, and whether the
-- first try is free. SimpleMode adds Odds (rows as percentages with the income bonus) and Costs; the old
-- window also gets the recipe book.
function S.Info(player)
 S.Visit(player);local rt=runtime();local p=rt.Engine:Get(player.UserId);rt.Engine:Authorize(p,player.UserId)
 local l=State.Normalize(p);local now=os.time()
 local info={Tier=l.Tier,Level=p.Level,Cooldown=math.max(0,C.Cooldown-(now-l.LastAt)),CooldownEndsAt=l.LastAt+C.Cooldown,
  Now=now,VariantRows=L.Rows(p,now),TutorialComplete=l.TutorialComplete==true,Simple=S.Simple()}
 if info.Simple then
  local odds=G.Chances(info.VariantRows,nil,C.Stability.Mutation,0)
  for i,row in odds do row.Bonus=info.VariantRows[i]and info.VariantRows[i].Bonus or 0 end
  info.Odds=odds;info.Costs=R.Copy(C.Costs.Mutation);info.Machine=R.Copy(C.Machine)
 else
  info.Recipes=L.Catalog(p,now)
 end
 return info
end
-- Players near the machine see a short public effect (Modules.LabPresentation) when someone mutates a dog:
-- replicated attributes on the lab model, MachinePulse last (clients react to it).
function S.Announce(player,result)
 pcall(function()
  local lab=Access.Model();if not lab then return end
  local d=type(result)=='table'and result.Dog
  S.Pulse+=1
  lab:SetAttribute('MachinePulseUser',player.UserId)
  lab:SetAttribute('MachinePulseVariant',type(d)=='table'and tostring(d.Variant or'Normal')or'Normal')
  lab:SetAttribute('MachinePulseAt',workspace:GetServerTimeNow())
  lab:SetAttribute('MachinePulse',S.Pulse)
 end)
end
-- LabCommit {Token, Confirm=true, Acknowledge}: a plan with valuable dogs needs Acknowledge (true or the plan
-- token), which the client sends only after the held confirmation. Typed (the old typed phrase) still works.
function S.Request(player,action,a,receipt)
 local rt=runtime();S.Visit(player)
 R.Check(not rt.Engine.TradeByUser[player.UserId],'Finish or cancel your trade before using the lab')
 if action=='LabInfo'then return true,S.Info(player)end
 if action=='LabPreview'then
  if S.Simple()then
   R.Check(type(a)=='table'and a.Procedure=='Mutation','The Mutation Machine only rerolls mutations')
   for k in a do R.Check(SIMPLE_KEYS[k],'The Mutation Machine takes only a dog')end
  end
  local p=rt.Engine:Get(player.UserId);rt.Engine:Authorize(p,player.UserId)
  local plan=L.Preview(p,a,os.time());local token=rt.Engine.Guid()
  S.Quotes[player.UserId]={Token=token,Args=R.Copy(a),Plan=plan,Expires=os.time()+C.QuoteSeconds}
  local public=L.Public(plan);public.Token=token;public.Expires=os.time()+C.QuoteSeconds
  return true,public
 end
 R.Check(action=='LabCommit','Unknown lab action')
 for k in a do R.Check(k=='Token'or k=='Confirm'or k=='Typed'or k=='Acknowledge','Unsupported confirmation parameter')end
 R.Check(type(a.Token)=='string'and #a.Token==32 and a.Confirm==true,'Review and confirm the experiment')
 local p=rt.Engine:Get(player.UserId);rt.Engine:Authorize(p,player.UserId);State.Normalize(p)
 for _,r in p.Lab.History do if r.Token==a.Token then return true,R.Copy(r)end end
 local quote=S.Quotes[player.UserId]
 R.Check(quote and quote.Token==a.Token and quote.Expires>os.time(),'Preview expired; review a fresh experiment')
 R.Check(not S.Simple()or quote.Plan.Procedure=='Mutation','The Mutation Machine only rerolls mutations')
 local keys={'p:'..player.UserId};local output=quote.Plan.RecipeId~='ASCEND'and quote.Plan.OutputDogId
 if output then table.insert(keys,'supply:'..output)end
 local uid=rt.Engine.Guid();local now=os.time();local fresh=false
 local ok,result=rt.Tx:Run(keys,function(v)
  fresh=false
  local p=v['p:'..player.UserId];rt.Engine:Authorize(p,player.UserId);R.Normalize(p,player.UserId,now)
  S.Visit(player)
  R.Check(not rt.Engine.TradeByUser[player.UserId],'Finish your trade first')
  for _,r in p.Lab.History do if r.Token==a.Token then return R.Copy(r)end end
  R.Check(quote.Expires>now,'Preview expired')
  local plan=L.Preview(p,quote.Args,now)
  R.Check(plan.Signature==quote.Plan.Signature,'Dog, material or odds changed. Review a fresh preview.')
  R.Check(not plan.HighValue or a.Acknowledge==true or a.Acknowledge==a.Token or(type(a.Typed)=='string'and a.Typed==plan.Confirmation),'Confirm these valuable dogs first')
  local supply={}
  if output then supply=v['supply:'..output]or{};v['supply:'..output]=supply end
  fresh=true
  return L.Apply(p,plan,now,rt.Engine.Random,uid,supply,a.Token)
 end,receipt)
 if ok then
  S.Quotes[player.UserId]=nil
  if fresh then S.Announce(player,result)end
 end
 return ok,result
end
function S.TryOpen(player)
 local rt=runtime()
 if not rt.Ready(player)or not Access.CanUse(player)or not rt.Allow(player,1)then return false end
 game.ReplicatedStorage.DogEconomyOpen:FireClient(player,'Lab');return true
end
function S.Start()
 if S.Started then return end;S.Started=true
 local lab=Access.Model();local anchor=lab:WaitForChild('InteractionAnchor')
 local simple=S.Simple()
 -- LabPrompt.client shows it only within reach (LabAccess) and words it in Russian (the Simple attribute
 -- picks the machine's words).
 local p=Instance.new('ProximityPrompt');p.Name='GeneticsPrompt'
 p.ActionText=simple and'ACTIVATE'or'USE GENETICS LAB';p.ObjectText=simple and'MUTATION MACHINE'or'GENETICS TERMINAL'
 p.HoldDuration=simple and .25 or .15;p.MaxActivationDistance=C.Distance;p.RequiresLineOfSight=true;p:SetAttribute('Simple',simple);p.Parent=anchor
 p.Triggered:Connect(S.TryOpen)
 game.Players.PlayerRemoving:Connect(function(player)S.Quotes[player.UserId]=nil end)
end
return S
