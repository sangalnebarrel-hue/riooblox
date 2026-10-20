-- Physical representatives of the same configured reward types shown by the server.
local V={};local RS=game:GetService('ReplicatedStorage')
-- NIGHT OF THE BURIED MOON reward rows (Pumpkin Lucky Blocks, cauldron, quests): decorations, pickaxe skins,
-- candy and event-mutated finds. nil when the art module is missing (callers fall back to the name).
local function eventArt(row)
 if row.Kind=='Decor'then
  local folder=RS:FindFirstChild('Decor');local module=folder and folder:FindFirstChild('DecorModels')
  return module and require(module).Get(row.Id)or nil
 elseif row.Kind=='Skin'then
  local folder=RS:FindFirstChild('Halloween');local module=folder and folder:FindFirstChild('PickaxeSkins')
  if not module then return nil end
  local Skins=require(module);return Skins.Build and Skins.Build(row.Id)or nil
 elseif row.Kind=='Candy'then
  local folder=RS:FindFirstChild('Halloween');local models=folder and folder:FindFirstChild('Models');local module=models and models:FindFirstChild('Pumpkin')
  if not module then return nil end
  local P=require(module);local m=Instance.new('Model');m.Name='CandyPile'
  for i,col in ipairs({Color3.fromRGB(255,128,24),Color3.fromRGB(122,62,200),Color3.fromRGB(120,255,110),Color3.fromRGB(255,80,120)})do
   local candy=P.Candy(col);candy:PivotTo(CFrame.new((i-2.5)*.9,math.abs(i-2.5)*-.3+.6,(i%2)*.5)*CFrame.Angles(0,i*.9,(i%2)*.4));candy.Parent=m
   if not m.PrimaryPart then m.PrimaryPart=candy.PrimaryPart end
  end
  return m
 elseif row.Kind=='Mutation'and type(row.Item)=='table'then
  return require(RS.DogEconomy.DiscoveryVisuals).Clone(row.Item)
 end
 return nil
end
function V.Build(row)
 -- Finds use the same model as everywhere else (DiscoveryVisuals: recipe model or the old one).
 if row.Kind=='Item'then return require(RS.DogEconomy.DiscoveryVisuals).Clone({ItemId=row.Id,Mutation=row.Mutation or'NORMAL'})end
 if row.Kind=='Decor'or row.Kind=='Skin'or row.Kind=='Candy'or row.Kind=='Mutation'then
  local ok,model=pcall(eventArt,row)
  if ok and model then return model end
  if row.Kind~='Candy'then return nil end
 end
 local model=Instance.new('Model');model.Name=row.Name or row.Kind or 'Reward'
 local function part(name,size,pos,color,shape)
  local p=Instance.new('Part');p.Name=name;p.Size=size;p.Position=pos;p.Color=color;p.Material=Enum.Material.SmoothPlastic;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false;p.Parent=model
  if shape then p.Shape=shape end;model.PrimaryPart=model.PrimaryPart or p;return p
 end
 if row.Kind=='Cash'then
  for i=0,3 do local coin=part('Coin',Vector3.new(.35,3,3),Vector3.new(i%2*.9,i*.38,0),Color3.fromRGB(245,187,48),Enum.PartType.Cylinder);coin.Orientation=Vector3.new(0,0,90)
   part('CoinEmblem',Vector3.new(.8,.08,.8),Vector3.new(i%2*.9,i*.38+.21,0),Color3.fromRGB(255,224,110))end
 elseif row.Kind=='Bones'then
  part('BoneShaft',Vector3.new(3.5,.7,.8),Vector3.zero,Color3.fromRGB(231,224,197))
  for _,x in ipairs({-1.9,1.9})do for _,z in ipairs({-.4,.4})do part('BoneKnuckle',Vector3.new(.9,1,.8),Vector3.new(x,0,z),Color3.fromRGB(245,237,212))end end
 elseif row.Kind=='Boost'then
  local pack=part('EnergySnack',Vector3.new(2.8,3.5,1.3),Vector3.new(0,1,0),Color3.fromRGB(202,129,52))
  part('GoldSeal',Vector3.new(2.9,.4,1.4),Vector3.new(0,2.9,0),Color3.fromRGB(251,210,100))
  local g=Instance.new('SurfaceGui');g.Face=Enum.NormalId.Front;g.CanvasSize=Vector2.new(220,180);g.LightInfluence=0;g.Parent=pack
  local text=Instance.new('TextLabel');text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1;text.Text='ENERGY\nSNACK';text.TextScaled=true;text.Font=Enum.Font.FredokaOne;text.TextColor3=Color3.fromRGB(65,43,30);text.Parent=g
 else model:Destroy();return nil end
 return model
end
return V
