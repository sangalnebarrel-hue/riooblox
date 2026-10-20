-- Studio-only test panel for Active Mining (F8). Talks to ServerScriptService.MiningStudioTest,
-- which exists only in Studio and only edits an unpublished preview's memory profile.
-- 'Pickaxe sounds' runs on this client only: every press plays the next pickaxe's sound kit
-- (MiningAudio: Draw, Swing, Hit, Perfect, Crit, Break), so all 16 can be heard without buying them.
local RunService=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local Debug={}

function Debug.new(ctx)
 local self:any={}
 if not RunService:IsStudio()then return self end
 local U=ctx.U
 local panel=Instance.new('Frame');panel.Name='MiningStudioPanel';panel.AnchorPoint=Vector2.new(0,.5);panel.Position=UDim2.new(0,16,.5,0)
 panel.Size=UDim2.fromOffset(250,367);panel.BackgroundColor3=Color3.fromRGB(255,251,242);panel.Visible=false;panel.ZIndex=180;panel.Parent=ctx.Gui
 U.Round(panel,12);U.Stroke(panel,U.Colors.edge,3)
 local title=U.Text(panel,'MINING TEST (F8)',12,6,226,26,18,U.Colors.text,true);title.ZIndex=181
 local status=U.Text(panel,'',12,333,226,28,12,U.Colors.muted);status.ZIndex=181
 local actions={{'cash','+1M Coins'},{'cash100','+100M Coins'},{'strength','Max a STRENGTH node'},{'all','All pickaxes + max Strength'},
  {'rare','Next ore: Void Crystal'},{'layers','Unlock all dig layers'},{'reset','Reset mining'},
  {'sounds',ctx.Text and ctx.Text.L and ctx.Text.L('Pickaxe sounds','Звуки кирок')or'Pickaxe sounds'}}
 local soundKit,soundRun=0,nil
 local function playKit()
  local list=ctx.M and ctx.M.Pickaxes
  if not(ctx.Audio and ctx.Audio.Pickaxe and list and #list>0)then status.Text='MiningAudio missing';return end
  soundKit=soundKit%#list+1
  local def=list[soundKit]
  local run={};soundRun=run -- a new press cuts the rest of the previous kit
  for i,cue in ipairs({'Draw','Swing','Hit','Perfect','Crit','Break'})do
   task.delay((i-1)*.9,function()if soundRun==run then ctx.Audio.Pickaxe(cue,def)end end)
  end
  status.Text=('%d/%d %s · %s'):format(soundKit,#list,tostring(def.Name),ctx.Audio.Kit and ctx.Audio.Kit(def)or tostring(def.Sound))
 end
 for i,row in ipairs(actions)do
  local b=U.Button(panel,'Debug'..row[1],row[2],12,36+(i-1)*37,226,32,function()
   if row[1]=='sounds'then playKit();return end
   local remote=game:GetService('ReplicatedStorage'):FindFirstChild('Mining')and game:GetService('ReplicatedStorage').Mining:FindFirstChild('MiningStudioControl')
   if not remote then status.Text='Server test hook missing';return end
   local ok,res,msg=pcall(function()return remote:InvokeServer(row[1])end)
   status.Text=tostring(ok and msg or res)
  end,row[1]=='reset'and U.Colors.red or row[1]=='sounds'and U.Colors.gold or U.Colors.blue)
  b.ZIndex=182
  for _,d in ipairs(b:GetDescendants())do if d:IsA('GuiObject')then d.ZIndex=183 end end
 end
 UIS.InputBegan:Connect(function(input,processed)
  if not processed and input.KeyCode==Enum.KeyCode.F8 then panel.Visible=not panel.Visible end
 end)
 return self
end

return Debug
