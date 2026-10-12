-- EQUIPMENT in the world (server):
--  * worn accessories: every equipped player accessory is a small model built from parts
--    (EquipmentVisuals) welded to the character, so everyone sees it. Rebuilt when the equipped
--    set changes (Runtime.Project bumps the InventoryRevision attribute) and on respawn; the
--    models live inside the character, so a respawn or leaving cleans them up.
--  * the Paw Market UPGRADES building is the EQUIPMENT shop: its signs are relabelled (the Model
--    keeps its name, scripts index it) and a few display pieces stand on its counters.
-- Started by ServerScriptService.EquipmentAvatar.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local E = require(RS.DogEconomy.EquipmentDefinitions)
local Visuals = require(RS.DogEconomy.EquipmentVisuals)
local Accessories = require(RS.DogEconomy.BonusSources.Accessories)

local W = { Started = false, Applied = {}, Views = nil :: any }
W.Prefix = "DOGROTS_Accessory_"
-- Most parts one worn set may use (four slots).
W.MaxParts = 28

-- The profile view of a player (Runtime.Views by default; tests inject their own).
local function profileOf(player: Player): any
	if not W.Views then
		local ok, runtime = pcall(require, script.Parent.Runtime)
		if not ok or type(runtime.Views) ~= "table" then
			return nil
		end
		W.Views = runtime.Views
	end
	return W.Views[player.UserId]
end

-- "Hat=RoyalCrown:<uid>|Face=..." for the equipped accessories (stable order).
function W.Signature(p: any): string
	local worn = Accessories.Equipped(p)
	local parts = {}
	for _, slot in ipairs(E.Slots) do
		local a = worn[slot]
		if a then
			table.insert(parts, slot .. "=" .. tostring(a.Id) .. ":" .. tostring(a.Uid))
		end
	end
	return table.concat(parts, "|")
end

-- Where a slot sits on a character: part, offset CFrame, scale.
function W.AttachPoint(character: Model, slot: string): (BasePart?, CFrame?, number)
	if slot == "Hat" or slot == "Face" then
		local head = character:FindFirstChild("Head")
		if not (head and head:IsA("BasePart")) then
			return nil, nil, 1
		end
		local scale = math.clamp(head.Size.Y / 1.2, 0.5, 3)
		if slot == "Hat" then
			return head, CFrame.new(0, head.Size.Y / 2, 0), scale
		end
		return head, CFrame.new(0, head.Size.Y * 0.06, -head.Size.Z / 2), scale
	elseif slot == "Back" then
		local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
		if not (torso and torso:IsA("BasePart")) then
			return nil, nil, 1
		end
		return torso, CFrame.new(0, torso.Size.Y * 0.08, torso.Size.Z / 2), math.clamp(torso.Size.X / 2, 0.5, 3)
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil, nil, 1
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local drop = root.Size.Y / 2 + 2
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		drop = root.Size.Y / 2 + math.max(0, humanoid.HipHeight)
	end
	return root, CFrame.new(0, -drop + 0.06, 0), 1
end

-- Builds one accessory on a character. Returns the model (nil when the rig lacks the part).
function W.Wear(character: Model, slot: string, def: any): Model?
	local part, offset, scale = W.AttachPoint(character, slot)
	if not part or not offset then
		return nil
	end
	local model = Visuals.Build(def, { World = true, Scale = scale })
	if not model then
		return nil
	end
	model.Name = W.Prefix .. slot
	model:SetAttribute("AccessoryId", def.Id)
	for _, piece in ipairs(model:GetChildren()) do
		if piece:IsA("BasePart") then
			local local_ = piece.CFrame
			piece.CFrame = part.CFrame * offset * local_
			local weld = Instance.new("Weld")
			weld.Part0 = part
			weld.Part1 = piece
			weld.C0 = offset * local_
			weld.C1 = CFrame.identity
			weld.Parent = piece
		end
	end
	model.Parent = character
	return model
end

function W.Clear(character: Model)
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Model") and string.sub(child.Name, 1, #W.Prefix) == W.Prefix then
			child:Destroy()
		end
	end
end

-- Makes the character wear exactly the equipped set (no work when nothing changed).
function W.Apply(player: Player, force: boolean?)
	local character = player.Character
	if not character or not character.Parent then
		return
	end
	local p = profileOf(player)
	if type(p) ~= "table" then
		return
	end
	local signature = W.Signature(p)
	local applied = W.Applied[player]
	if not force and applied and applied.Character == character and applied.Signature == signature then
		return
	end
	W.Clear(character)
	local worn = Accessories.Equipped(p)
	local parts = 0
	for _, slot in ipairs(E.Slots) do
		local a = worn[slot]
		local def = a and E.AccessoryById[a.Id]
		if def and parts + #def.Look.Parts <= W.MaxParts then
			local model = W.Wear(character, slot, def)
			if model then
				parts += #def.Look.Parts
			end
		end
	end
	W.Applied[player] = { Character = character, Signature = signature }
end

-- Signs of the Paw Market UPGRADES building (relative path -> text). AutoTranslate translates
-- workspace SurfaceGuis (Localization.Equipment has the Russian entries).
W.Signs = {
	{ { "Architecture", "FacadeName" }, "EQUIPMENT" },
	{ { "Interior", "ServiceTerminal", "TerminalScreen" }, "EQUIPMENT TERMINAL" },
	{ { "Interior", "BackIdentity" }, "GEAR UP YOUR PACK" },
	{ { "Interior", "UpgradeCategories" }, "PLAYER ACCESSORIES · DOG ARTIFACTS\r\nCASES" },
	{ { "Interior", "EngineeringWorkbench", "WorkbenchLabel" }, "DOG ARTIFACTS" },
	{ { "Interior", "KennelEngineering", "KennelLabel" }, "PLAYER ACCESSORIES" },
	{ { "Interior", "StorageEngineering", "StorageLabel" }, "CASES" },
}

local function find(root: Instance, path: { string }): Instance?
	local node: Instance? = root
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

function W.Relabel(shop: Instance): number
	local changed = 0
	for _, row in ipairs(W.Signs) do
		local part = find(shop, row[1])
		for _, gui in ipairs(part and part:GetChildren() or {}) do
			if gui:IsA("SurfaceGui") then
				for _, label in ipairs(gui:GetChildren()) do
					if label:IsA("TextLabel") then
						label.Text = row[2]
						changed += 1
					end
				end
			end
		end
	end
	shop:SetAttribute("EquipmentShop", true)
	return changed
end

-- A display piece standing on a counter, turned to the middle of the shop (bounds are in the
-- model's own, already scaled, units).
local function display(folder: Instance, model: Model?, bounds: any, at: Vector3, facing: Vector3)
	if not model or not bounds then
		return
	end
	local base = CFrame.lookAt(at, Vector3.new(facing.X, at.Y, facing.Z))
	for _, piece in ipairs(model:GetChildren()) do
		if piece:IsA("BasePart") then
			piece.Anchored = true
			piece.CFrame = base * CFrame.new(-bounds.Center) * piece.CFrame
		end
	end
	model.Parent = folder
end

function W.Dress(shop: Instance): Instance?
	local interior = shop:FindFirstChild("Interior")
	local zone = shop:FindFirstChild("ShopInteriorZone")
	if not interior or not (zone and zone:IsA("BasePart")) or interior:FindFirstChild("EquipmentDisplays") then
		return nil
	end
	local folder = Instance.new("Model")
	folder.Name = "EquipmentDisplays"
	local middle = zone.Position
	local worktop = find(interior, { "EngineeringWorkbench", "Worktop" })
	if worktop and worktop:IsA("BasePart") then
		local at = (worktop.CFrame * CFrame.new(3.8, worktop.Size.Y / 2 + 0.95, -1.2)).Position
		local model, bounds = Visuals.Build("MidasBell", { World = true, Scale = 0.75 })
		display(folder, model, bounds, at, middle)
	end
	local cap = find(interior, { "KennelEngineering", "TimberCap" })
	local kennel = find(interior, { "KennelEngineering", "KennelSample" })
	if cap and cap:IsA("BasePart") then
		local top = cap.Position.Y + 4.6
		if kennel and kennel:IsA("Model") then
			local ok, cf, size = pcall(function()
				return kennel:GetBoundingBox()
			end)
			if ok and cf then
				top = cf.Position.Y + size.Y / 2
			end
		end
		local model, bounds = Visuals.Build("RoyalCrown", { World = true, Scale = 1.3 })
		display(folder, model, bounds, Vector3.new(cap.Position.X, top + 1.2, cap.Position.Z), middle)
	end
	local plinth = find(interior, { "StorageEngineering", "TimberCap" })
	if plinth and plinth:IsA("BasePart") then
		local at = (plinth.CFrame * CFrame.new(-3.1, plinth.Size.Y / 2 + 0.68, 0)).Position
		local model, bounds = Visuals.Case("RelicChest", { World = true, Scale = 0.7 })
		display(folder, model, bounds, at, middle)
	end
	folder.Parent = interior
	return folder
end

local function watch(player: Player)
	local connections = {}
	local function apply()
		task.defer(function()
			if player.Parent then
				W.Apply(player)
			end
		end)
	end
	table.insert(connections, player:GetAttributeChangedSignal("InventoryRevision"):Connect(apply))
	table.insert(connections, player.CharacterAdded:Connect(function(character)
		-- The rig's parts load with the character; wait for the head before dressing it.
		task.spawn(function()
			character:WaitForChild("Head", 10)
			character:WaitForChild("HumanoidRootPart", 10)
			if player.Parent and player.Character == character then
				W.Apply(player, true)
			end
		end)
	end))
	W.Applied[player] = W.Applied[player] or {}
	W.Applied[player].Connections = connections
	apply()
end

function W.Start()
	if W.Started then
		return
	end
	W.Started = true
	task.spawn(function()
		local map = workspace:WaitForChild("DOGROTS_District", 60)
		local shops = map and map:WaitForChild("11_Shops", 60)
		local shop = shops and shops:WaitForChild("UPGRADES", 60)
		if shop then
			W.Relabel(shop)
			local ok, err = pcall(W.Dress, shop)
			if not ok then
				warn("DOGROTS equipment shop displays: " .. tostring(err))
			end
		end
	end)
	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local applied = W.Applied[player]
		for _, connection in ipairs(applied and applied.Connections or {}) do
			connection:Disconnect()
		end
		W.Applied[player] = nil
	end)
end

return W
