-- Plot decorations in the world (data: Economy.Features.Decor, catalog and slots:
-- ReplicatedStorage.DogEconomy.DecorCatalog, models: ReplicatedStorage.Decor.DecorModels).
--   W.Frame(yard)        yard frame and mirror sign (PlotAppearance.Frame + the kennel side), also
--                        published as yard attributes PlotFrame (CFrame) / PlotMirror (1 | -1) so
--                        clients place slot markers without waiting for streamed parts
--   W.Reconcile(yard, p) yard.PlotDecor follows p.Decor.Placed; only changed slots are rebuilt
--   W.Clear(yard)        removes every decoration (the yard has no owner any more)
-- yard.PlotDecor is a sibling of PlotDevelopment, so stage / skin rebuilds (PlotAppearance.Apply)
-- never touch it. Each decoration is its own Atomic model named after its slot; the yard
-- attribute Decor_<slot> = decoration id tells clients (markers, prompts) what is placed.
local RS=game:GetService('ReplicatedStorage')
local Catalog=require(RS.DogEconomy.DecorCatalog)
local A=require(RS.PlotAppearance)
local W={Started=false}
local frames=setmetatable({},{__mode='k'})
local models=nil
local function Models()
 if models==nil then
  local ok,m=pcall(function()return require(RS:WaitForChild('Decor'):WaitForChild('DecorModels'))end)
  models=ok and m or false
  if not ok then warn('DOGROTS decor models: '..tostring(m))end
 end
 return models or nil
end
function W.Frame(yard)
 local cached=frames[yard]
 if cached then return cached[1],cached[2]end
 local ok,f=pcall(A.Frame,yard)
 if not ok then return nil,1 end
 local sx=1;local first=yard:FindFirstChild('DigSlot_1');local pit=first and first:FindFirstChild('DarkExcavation')
 if pit and f:PointToObjectSpace(pit.Position).X>0 then sx=-1 end
 frames[yard]={f,sx}
 yard:SetAttribute('PlotFrame',f);yard:SetAttribute('PlotMirror',sx)
 return f,sx
end
local function folder(yard)
 local root=yard:FindFirstChild('PlotDecor')
 if not root then
  root=Instance.new('Model');root.Name='PlotDecor'
  pcall(function()root.ModelStreamingMode=Enum.ModelStreamingMode.Default end)
  root.Parent=yard
 end
 return root
end
local function build(yard,slot,id)
 local M=Models();local f,sx=W.Frame(yard)
 if not M or not f then return nil end
 local ok,model=pcall(M.Get,id)
 if not ok or not model then warn('DOGROTS decor '..tostring(id)..': '..tostring(model));return nil end
 model.Name=slot.Id;model:SetAttribute('DecorId',id);model:SetAttribute('DecorSlot',slot.Id)
 pcall(function()model.ModelStreamingMode=Enum.ModelStreamingMode.Atomic end)
 model:PivotTo(Catalog.SlotCFrame(f,sx,slot))
 return model
end
function W.Reconcile(yard,p)
 local data=type(p)=='table'and p.Decor
 local placed=type(data)=='table'and type(data.Placed)=='table'and data.Placed or {}
 local root=yard:FindFirstChild('PlotDecor')
 for _,slot in ipairs(Catalog.Slots)do
  local id=placed[slot.Id];if not Catalog.Get(id)then id=nil end
  local current=root and root:FindFirstChild(slot.Id)
  if(current and current:GetAttribute('DecorId'))~=id then
   if current then current:Destroy()end
   if id then
    local model=build(yard,slot,id)
    if model then root=root or folder(yard);model.Parent=root end
   end
  end
  local key='Decor_'..slot.Id
  if yard:GetAttribute(key)~=id then yard:SetAttribute(key,id)end
 end
end
function W.Clear(yard)
 local root=yard:FindFirstChild('PlotDecor');if root then root:Destroy()end
 for _,slot in ipairs(Catalog.Slots)do yard:SetAttribute('Decor_'..slot.Id,nil)end
end
function W.Start()
 if W.Started then return end;W.Started=true
 local map=workspace:FindFirstChild('DOGROTS_District');local yards=map and map:FindFirstChild('04_PlayerYards')
 for _,yard in ipairs(yards and yards:GetChildren()or {})do if yard:GetAttribute('YardId')then W.Frame(yard)end end
end
return W
