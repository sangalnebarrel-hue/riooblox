-- MineCarve: cuts the mine shafts through the existing ground, reversibly.
-- An axis-aligned block that covers a shaft column (YardFoundation, the island's LivingGround and
-- IslandMass strips, ...) is replaced by up to 4 pieces per hole around the opening: clones of the
-- original (same material, colour, attributes, collision group) with new sizes. The original is
-- never destroyed: it stays in place, hidden (Transparency 1, no collision / queries / shadow),
-- marked with MineCarved = true and its old values in MineCarved* attributes, so Restore() puts
-- the world back exactly. Parts that cannot be cut (rotated, wedges, meshes) are hidden the same
-- way. PlotAppearance re-shows yard parts from their PlotBase* attributes, so a carved
-- YardFoundation keeps PlotBaseTransparency = 1 / PlotBaseCollide = false while it is carved.
local Layout = require(game:GetService("ReplicatedStorage"):WaitForChild("Mine"):WaitForChild("MineLayout"))

local Carve = {}
Carve.Tag = "MineCarvePiece"

local SAVED = { "Transparency", "CanCollide", "CanQuery", "CanTouch", "CastShadow" }

local function hide(part: BasePart)
	if part:GetAttribute("MineCarved") then
		return
	end
	for _, key in SAVED do
		part:SetAttribute("MineCarved" .. key, (part :: any)[key])
	end
	local base = part:GetAttribute("PlotBaseTransparency")
	if base ~= nil then
		part:SetAttribute("MineCarvedPlotBaseTransparency", base)
		part:SetAttribute("MineCarvedPlotBaseCollide", part:GetAttribute("PlotBaseCollide"))
		part:SetAttribute("PlotBaseTransparency", 1)
		part:SetAttribute("PlotBaseCollide", false)
	end
	part:SetAttribute("MineCarved", true)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end
Carve.Hide = hide

-- Can this part be cut into boxes? Plain blocks with a vertical Y axis only.
function Carve.Cuttable(part: Instance): boolean
	if not part:IsA("Part") then
		return false
	end
	local p = part :: Part
	if p.Shape ~= Enum.PartType.Block or p:FindFirstChildWhichIsA("DataModelMesh") then
		return false
	end
	return math.abs(p.CFrame.UpVector.Y) > 0.999
end

-- Pure: the pieces {CFrame, Size} that replace a block of `cf`/`size` around `holes`
-- ({CFrame, Size} columns). nil when the holes are not aligned with the block.
function Carve.Pieces(cf: CFrame, size: Vector3, holes: { any }): { any }?
	local box, local_holes = Layout.LocalHoles(cf, size, holes)
	if not box or not local_holes then
		return nil
	end
	local out = {}
	for _, r in Layout.CarveRects(box, local_holes) do
		local center = Vector3.new((r.X0 + r.X1) / 2, 0, (r.Z0 + r.Z1) / 2)
		table.insert(out, { CFrame = cf * CFrame.new(center), Size = Vector3.new(r.X1 - r.X0, size.Y, r.Z1 - r.Z0) })
	end
	return out
end

-- Cuts one part. Returns the new piece instances (an empty list when the part was only hidden).
function Carve.Apply(part: BasePart, holes: { any }): { BasePart }
	if part:GetAttribute("MineCarved") or part:GetAttribute(Carve.Tag) then
		return {}
	end
	local pieces = Carve.Cuttable(part) and Carve.Pieces(part.CFrame, part.Size, holes) or nil
	local made = {}
	if pieces then
		for i, piece in pieces do
			local clone = part:Clone()
			clone:ClearAllChildren()
			clone.Name = part.Name .. "_MineCut"
			clone.Size = piece.Size
			clone.CFrame = piece.CFrame
			clone:SetAttribute(Carve.Tag, i)
			table.insert(made, clone)
		end
	end
	hide(part)
	for _, clone in made do
		clone.Parent = part.Parent
	end
	return made
end

-- Pieces follow later colour / material changes of their original (yard skins recolour the
-- hidden YardFoundation), one step later so they win over a pass that reset them first.
function Carve.Mirror(part: BasePart, pieces: { BasePart }): { RBXScriptConnection }
	if #pieces == 0 then
		return {}
	end
	local function mirror()
		task.defer(function()
			for _, clone in pieces do
				if clone.Parent then
					clone.Color = part.Color
					clone.Material = part.Material
					clone.MaterialVariant = part.MaterialVariant
				end
			end
		end)
	end
	return {
		part:GetPropertyChangedSignal("Color"):Connect(mirror),
		part:GetPropertyChangedSignal("Material"):Connect(mirror),
	}
end

-- Undo: removes the pieces of a carved original and restores it.
function Carve.Restore(part: BasePart)
	if not part:GetAttribute("MineCarved") then
		return
	end
	local parent = part.Parent
	if parent then
		for _, sibling in parent:GetChildren() do
			if sibling:GetAttribute(Carve.Tag) and sibling.Name == part.Name .. "_MineCut" then
				sibling:Destroy()
			end
		end
	end
	for _, key in SAVED do
		local v = part:GetAttribute("MineCarved" .. key)
		if v ~= nil then
			(part :: any)[key] = v
		end
		part:SetAttribute("MineCarved" .. key, nil)
	end
	local base = part:GetAttribute("MineCarvedPlotBaseTransparency")
	if base ~= nil then
		part:SetAttribute("PlotBaseTransparency", base)
		part:SetAttribute("PlotBaseCollide", part:GetAttribute("MineCarvedPlotBaseCollide"))
		part:SetAttribute("MineCarvedPlotBaseTransparency", nil)
		part:SetAttribute("MineCarvedPlotBaseCollide", nil)
	end
	part:SetAttribute("MineCarved", nil)
end

-- Should a part found in a shaft column be cut (or hidden)? Visible or solid world geometry only.
function Carve.Relevant(part: Instance): boolean
	if not part:IsA("BasePart") or part:IsA("Terrain") then
		return false
	end
	local p = part :: BasePart
	if p:GetAttribute(Carve.Tag) or p:GetAttribute("MineCarved") or p:GetAttribute("MineWorks") then
		return false
	end
	if not p.Anchored then
		return false
	end
	if p.Transparency >= 0.99 and not p.CanCollide then
		return false
	end
	local model = p:FindFirstAncestorWhichIsA("Model")
	if model and model:FindFirstChildOfClass("Humanoid") then
		return false
	end
	return true
end

return Carve
