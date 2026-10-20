-- Presentation and read-only projections for the existing YardPage only.
-- No persistence, purchases, new remotes, or replacement PAWPAD/HUD systems.
local Players = game:GetService("Players")
local Replicated = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local page = script.Parent
local main = page.Parent.Parent.Parent
local grid = page.StatsGrid
local latest = page.LatestFoundCard.Main
local yardViewport = page.YardPreviewPanel.YardViewport
local alive = true
local connections = {}
local function listen(signal, callback)
 local c = signal:Connect(callback)
 table.insert(connections, c)
 return c
end
local function shown() return alive and main.Visible and page.Visible end
-- Income per minute from the server's income model (player attribute IncomePerMinute, kept
-- current by Runtime.Project); the label is translated by Localization.Income.
local IncomeText = require(Replicated:WaitForChild("DogEconomy"):WaitForChild("IncomeText"))
local DiscoveryVisuals = require(Replicated:WaitForChild("DogEconomy"):WaitForChild("DiscoveryVisuals"))
grid.IncomeCard.Label.Text = "Income / min"
local function updateIncome(perMinute)
 perMinute = tonumber(perMinute) or player:GetAttribute("IncomePerMinute")
 if type(perMinute) == "number" then grid.IncomeCard.Value.Text = "$" .. IncomeText.Compact(perMinute) end
end
updateIncome()
listen(player:GetAttributeChangedSignal("IncomePerMinute"), function() updateIncome() end)
local function ownedYard()
 local district = workspace:FindFirstChild("DOGROTS_District")
 local yards = district and district:FindFirstChild("04_PlayerYards")
 if yards then
  for _, yard in ipairs(yards:GetChildren()) do
   if yard:IsA("Model") and yard:GetAttribute("YardId") == player:GetAttribute("YardId")
    and yard:GetAttribute("OwnerUserId") == player.UserId then return yard end
  end
 end
end
local function updateStats()
 local level, capacity = player:GetAttribute("YardLevel"), player:GetAttribute("DogCapacity")
 if type(level) == "number" then grid.LevelCard.Value.Text = tostring(level) end
 local inventory = player:FindFirstChild("DogInventory")
 if inventory and type(capacity) == "number" then
  local count = 0
  for _, entry in ipairs(inventory:GetChildren()) do if entry:IsA("StringValue") then count += 1 end end
  grid.StorageCard.Value.Text = string.format("%d / %d", count, capacity)
 end
 local yard = ownedYard()
 if yard then
  local occupied, total = 0, 0
  for _, slot in ipairs(yard:GetChildren()) do
   if slot.Name:match("^DigSlot_%d+$") then
    if slot:GetAttribute("Unlocked")~=false then total += 1 end
    local uid = slot:GetAttribute("AssignedDogUid")
    if type(uid) == "string" and uid ~= "" and slot:GetAttribute("AssignedOwnerUserId") == player.UserId then occupied += 1 end
   end
  end
  if total > 0 then grid.KennelsCard.Value.Text = string.format("%d / %d", occupied, total) end
 end
end

-- Copy only existing visible geometry. Scripts, prompts, sounds, effects, world UI,
-- and collision helpers never enter a viewport. Original instances stay untouched.
local function geometry(source)
 if not source then return nil end
 local model = Instance.new("Model")
 model.Name = "PreviewModel"
 local count = 0
 for _, part in ipairs(source:GetDescendants()) do
  if part:IsA("BasePart") and part.Transparency < 1 and part.Archivable then
   local copy = part:Clone()
   if copy then
    for _, child in ipairs(copy:GetChildren()) do
     if not child:IsA("DataModelMesh") and not child:IsA("SurfaceAppearance") then child:Destroy() end
    end
    copy.Anchored = true
    copy.CanCollide = false
    copy.CanTouch = false
    copy.CanQuery = false
    copy.Parent = model
    count += 1
   end
  end
 end
 if count == 0 then model:Destroy(); return nil end
 return model
end
local viewModels = {}
local function fit(viewport)
 local model = viewModels[viewport]
 local camera = viewport.CurrentCamera
 if not model or not camera or viewport.AbsoluteSize.Y < 1 then return end
 local aspect = math.max(.2, viewport.AbsoluteSize.X / viewport.AbsoluteSize.Y)
 if viewport ~= yardViewport then DiscoveryVisuals.FrameCamera(camera, model, aspect); return end
 local box, size = model:GetBoundingBox()
 local vertical = math.rad(camera.FieldOfView / 2)
 local angle = math.min(vertical, math.atan(math.tan(vertical) * aspect))
 local direction = Vector3.new(1, 1.05, 1.2).Unit
 local distance = size.Magnitude * .5 / math.sin(angle) * 1.06
 camera.CFrame = CFrame.lookAt(box.Position + direction * distance, box.Position)
 camera.Focus = box
end
local function replacePreview(viewport, model)
 local old = viewModels[viewport]
 if old then old:Destroy() end
 viewModels[viewport] = model
 if not model then return end
 model.Parent = viewport
 if not viewport.CurrentCamera then
  local camera = Instance.new("Camera")
  camera.Name = "PreviewCamera"
  camera.FieldOfView = 35
  camera.Parent = viewport
  viewport.CurrentCamera = camera
 end
 fit(viewport)
end
local lastYard, lastPreviewAt = nil, -math.huge
local function updateYardPreview(force)
 if not shown() then return end
 local yard = ownedYard()
 if not force and yard == lastYard and os.clock() - lastPreviewAt < 20 then return end
 lastYard, lastPreviewAt = yard, os.clock()
 local model = geometry(yard)
 replacePreview(yardViewport, model)
 yardViewport.Placeholder.Visible = model == nil
 yardViewport.YardTag.Text = yard and string.format("YARD %02d", player:GetAttribute("YardId")) or "HOME BASE"
end
local itemViewport = latest.PreviewArea.ItemViewport
local latestUid, latestTime = nil, -math.huge
local function renderDiscovery(found)
 if type(found) ~= "table" or type(found.DisplayName) ~= "string" then
  if latestUid then return end
  latest.ItemName.Text = "Nothing discovered yet"
  latest.ItemInfo.Text = "Your next discovery will appear here."
  latest.ClassLabel.Text = "WAITING FOR A FIND"
  return
 end
 local foundAt = tonumber(found.FoundAt) or 0
 if foundAt < latestTime then return end
 latestTime = foundAt
 latest.ItemName.Text = found.DisplayName
 local info = {}
 if type(found.WeightKg) == "number" then table.insert(info, string.format("%.4g kg", found.WeightKg)) end
 if type(found.WeightTier) == "string" then table.insert(info, found.WeightTier) end
 if type(found.Mutation) == "string" and found.Mutation ~= "NORMAL" then table.insert(info, found.Mutation) end
 latest.ItemInfo.Text = table.concat(info, "  /  ")
 latest.ClassLabel.Text = string.upper(found.Class or "DISCOVERY")
 if latestUid == found.ItemUid and viewModels[itemViewport] then return end
 latestUid = found.ItemUid
 -- The find's own model (recipe or old voxel model, mutation styled); the camera frames it.
 local ok, model = pcall(DiscoveryVisuals.Clone, found, { NoScale = true })
 if not ok then model = nil end
 replacePreview(itemViewport, model)
 latest.PreviewArea.EmptyMark.Visible = model == nil
 latest.PreviewArea.EmptyMark.Text = "?"
end
-- PLOT DECOR (Modules.DecorScreen): one button over the yard preview opens the decorations window.
do
 local panel = page.YardPreviewPanel
 local button = Instance.new("TextButton")
 button.Name = "DecorButton"
 button.AnchorPoint = Vector2.new(1, 0)
 button.Position = UDim2.new(1, -20, 0, 20)
 button.Size = UDim2.fromOffset(150, 40)
 button.BackgroundColor3 = Color3.fromRGB(64, 186, 120)
 button.AutoButtonColor = true
 button.Text = "DECORATE"
 button.TextColor3 = Color3.new(1, 1, 1)
 button.Font = Enum.Font.FredokaOne
 button.TextScaled = true
 button.ZIndex = yardViewport.ZIndex + 5
 local limit = Instance.new("UITextSizeConstraint")
 limit.MaxTextSize = 20
 limit.Parent = button
 local padding = Instance.new("UIPadding")
 padding.PaddingLeft = UDim.new(0, 10)
 padding.PaddingRight = UDim.new(0, 10)
 padding.PaddingTop = UDim.new(0, 6)
 padding.PaddingBottom = UDim.new(0, 6)
 padding.Parent = button
 local corner = Instance.new("UICorner")
 corner.CornerRadius = UDim.new(0, 12)
 corner.Parent = button
 local stroke = Instance.new("UIStroke")
 stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
 stroke.Color = Color3.fromRGB(23, 43, 76)
 stroke.Thickness = 2
 stroke.Parent = button
 button.Parent = panel
 listen(button.Activated, function()
  local ok, N = pcall(require, main.Parent.Modules.GUIIntegration)
  if ok and type(N) == "table" and N.OpenPage then N.OpenPage("Decor") end
 end)
end
listen(yardViewport:GetPropertyChangedSignal("AbsoluteSize"), function() fit(yardViewport) end)
listen(itemViewport:GetPropertyChangedSignal("AbsoluteSize"), function() fit(itemViewport) end)

-- Snapshot is the existing read-only server contract; request only while YARD is
-- visible, at most once per two seconds. Other PAWPAD pages keep their own controller.
local busy, lastRequest = false, -math.huge
local function refresh()
 if not shown() then return end
 updateStats()
 updateYardPreview(false)
 if busy or os.clock() - lastRequest < 2 or not player:GetAttribute("EconomyReady") then return end
 local request = Replicated:FindFirstChild("DogEconomyRequest")
 if not request or not request:IsA("RemoteFunction") then return end
 busy, lastRequest = true, os.clock()
 local ok, success, data = pcall(function() return request:InvokeServer("Snapshot", {}) end)
 busy = false
 if not alive then return end
 if ok and success and type(data) == "table" and type(data.Profile) == "table" then
  if type(data.IncomePerMinute) == "number" then updateIncome(data.IncomePerMinute) end
  renderDiscovery((data.Profile.DiscoveryFeed or {})[1])
 end
end
local function requestRefresh() task.defer(refresh) end
for _, attribute in ipairs({"YardLevel", "DogCapacity", "EconomyReady", "LatestFoundItem", "CurrentLayer"}) do
 listen(player:GetAttributeChangedSignal(attribute), function() updateStats(); requestRefresh() end)
end
listen(player:GetAttributeChangedSignal("YardId"), function()
 lastYard = nil
 replacePreview(yardViewport, nil)
 yardViewport.Placeholder.Visible = true
 updateStats()
 updateYardPreview(true)
end)
listen(main:GetPropertyChangedSignal("Visible"), requestRefresh)
listen(page:GetPropertyChangedSignal("Visible"), requestRefresh)
local boundReveal
local function connectReveal(remote)
 if remote.Name == "DiscoveryReveal" and remote:IsA("RemoteEvent") and remote ~= boundReveal then
  boundReveal = remote
  -- Runtime replays a feed newest-first; do not treat the last replayed event as
  -- the latest find. Snapshot.Profile.DiscoveryFeed[1] is the authoritative order.
  listen(remote.OnClientEvent, requestRefresh)
 end
end
listen(Replicated.ChildAdded, connectReveal)
for _, child in ipairs(Replicated:GetChildren()) do connectReveal(child) end

-- ServiceMenusController owns Upgrades travel and the Layers overlay.
-- Navigation goes through PawpadController's shared open/close owner.
-- GLOBAL DIG is bound once in PawpadController to its existing switch('Events').
-- That is the same page used by the existing GLOBAL DIG world interaction.

local function layout()
 if main:FindFirstChild('ResponsiveScale')then
  require(main.Parent.Modules.UITheme).LayoutYard(page)
  return
 end
 local narrow = page.AbsoluteSize.X < 620
 local actions = page.ActionButtons
 actions.Position = UDim2.fromScale(.015, narrow and .79 or .85)
 actions.Size = UDim2.fromScale(.97, narrow and .17 or .105)
 page.LatestFoundCard.Size = UDim2.fromScale(.97, narrow and .17 or .23)
 for index, name in ipairs({"Upgrades", "DiggingLayers", "GlobalDig"}) do
  local holder = actions[name]
  holder.Position = UDim2.new(narrow and (index == 2 and .515 or 0) or (index - 1) / 3, 0,
   narrow and (index == 3 and .54 or 0) or 0, 0)
  holder.Size = narrow and UDim2.fromScale(index == 3 and 1 or .485, .42)
   or UDim2.new(1 / 3, index == 3 and 0 or -14, 1, 0)
 end
end
listen(page:GetPropertyChangedSignal("AbsoluteSize"), layout)
layout()
updateStats()
task.spawn(function()
 while alive and page.Parent do
  refresh()
  task.wait(8)
 end
end)
-- Cheap replicated-stat update also catches kennel assignment/streaming changes.
task.spawn(function()
 while alive and page.Parent do
  if shown() then updateStats() end
  task.wait(1)
 end
end)
script.Destroying:Connect(function()
 alive = false
 for _, connection in ipairs(connections) do connection:Disconnect() end
 for _, model in pairs(viewModels) do model:Destroy() end
end)
