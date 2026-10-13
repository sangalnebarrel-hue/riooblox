-- Studio-only test panel for Active Mining (F8). Talks to ServerScriptService.MiningStudioTest,
-- which exists only in Studio and only edits an unpublished preview's memory profile.
local RunService=game:GetService('RunService')
local UIS=game:GetService('UserInputService')
local Debug={}

function Debug.new(ctx)
 local self:any={}
 if not RunService:IsStudio()then return self end
 local U=ctx.U
 local panel=Instance.new('Frame');panel.Name='MiningStudioPanel';panel.AnchorPoint=Vector2.new(0,.5);panel.Position=UDim2.new(0,16,.5,0)
 panel.Size=UDim2.fromOffset(250,330);panel.BackgroundColor3=Color3.fromRGB(255,251,242);panel.Visible=false;panel.ZIndex=180;panel.Parent=ctx.Gui
 U.Round(panel,12);U.Stroke(panel,U.Colors.edge,3)
 local title=U.Text(panel,'MINING TEST (F8)',12,6,226,26,18,U.Colors.text,true);title.ZIndex=181
 local status=U.Text(panel,'',12,296,226,28,12,U.Colors.muted);status.ZIndex=181
 local actions={{'cash','+1M Coins'},{'cash100','+100M Coins'},{'strength','+100 Strength'},{'all','All pickaxes + weights'},
  {'rare','Next ore: Void Crystal'},{'layers','Unlock all dig layers'},{'reset','Reset mining'}}
 for i,row in ipairs(actions)do
  local b=U.Button(panel,'Debug'..row[1],row[2],12,36+(i-1)*37,226,32,function()
   local remote=game:GetService('ReplicatedStorage'):FindFirstChild('Mining')and game:GetService('ReplicatedStorage').Mining:FindFirstChild('MiningStudioControl')
   if not remote then status.Text='Server test hook missing';return end
   local ok,res,msg=pcall(function()return remote:InvokeServer(row[1])end)
   status.Text=tostring(ok and msg or res)
  end,row[1]=='reset'and U.Colors.red or U.Colors.blue)
  b.ZIndex=182
  for _,d in ipairs(b:GetDescendants())do if d:IsA('GuiObject')then d.ZIndex=183 end end
 end
 UIS.InputBegan:Connect(function(input,processed)
  if not processed and input.KeyCode==Enum.KeyCode.F8 then panel.Visible=not panel.Visible end
 end)
 return self
end

return Debug
