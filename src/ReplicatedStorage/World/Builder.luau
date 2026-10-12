-- Turns World.Spec lists into Instances. Works on the server (collisions, shared geometry) and on
-- the client (decor, effects); everything is built detached and parented once.
--
--   local model = Builder.Build(specs, anchorCFrame, {
--       Name = "ShowcaseStand", Parent = folder,
--       BuilderId = "Showcase", LayoutVersion = 3,   -- attributes on the model (PartCount too)
--       StreamingMode = "Atomic",                      -- "Atomic" | "Persistent" | "PersistentPerPlayer" | "Nonatomic" | "Default"
--       PersistentPlayer = player,                     -- with "PersistentPerPlayer" and a Parent (server only)
--       FXManaged = true,                              -- WorldDetailQuality leaves its lights / emitters alone
--       Lod = { Near = 80, Far = 200 },                -- tags the model DOGROTS_Lod (Perf.Lod tag path)
--       Attributes = { Owner = userId },
--   })
--   local model, rebuilt = Builder.EnsureBuilt(parent, "MiningCorner", 24, function()
--       return Builder.Build(layout(), anchor, { BuilderId = "MiningCorner" }) -- unparented
--   end)  -- reuses a child with the same LayoutVersion, otherwise destroys it and builds again
--
-- Part defaults: Anchored; CanCollide / CanQuery / CanTouch false unless the spec asks; smooth
-- surfaces. CastShadow, when the spec leaves it nil: off for Neon / Glass / ForceField, for parts
-- at least half transparent and for parts smaller than Builder.ShadowMinSize studs in every
-- dimension (the place already has ~12 800 shadow casters), on otherwise.
-- Streaming properties are set in pcall (Studio / older engines warn instead of failing).
local Builder = {}

Builder.ShadowMinSize = 4
Builder.LodTag = "DOGROTS_Lod"

local NO_SHADOW_MATERIALS = { Neon = true, Glass = true, ForceField = true }
local PART_ONLY = {
	Class = true, Shape = true, Name = true, Size = true, CFrame = true, Color = true, Material = true,
	Transparency = true, Reflectance = true, CastShadow = true, CanCollide = true, CanQuery = true,
	CanTouch = true, Anchored = true, Tags = true, Attributes = true, Props = true, Children = true,
}
local CHILD_RESERVED = { Class = true, Name = true, Children = true, Tags = true, Attributes = true, Attachment0 = true, Attachment1 = true }

local function enumItem(enum: any, name: string): any
	local ok, item = pcall(function()
		return enum[name]
	end)
	return ok and item or nil
end

function Builder.Material(name: string?): Enum.Material
	return (name and enumItem(Enum.Material, name)) or Enum.Material.SmoothPlastic
end

-- Sets one property; a string given for an enum property is converted by name.
local function set(instance: Instance, key: string, value: any)
	local target: any = instance
	if type(value) == "string" then
		local ok, current = pcall(function()
			return target[key]
		end)
		if ok and typeof(current) == "EnumItem" then
			local item = enumItem(current.EnumType, value)
			if item then
				value = item
			end
		end
	end
	local ok, err = pcall(function()
		target[key] = value
	end)
	if not ok then
		warn(string.format("World.Builder: %s.%s not set: %s", instance.ClassName, key, tostring(err)))
	end
end

local function decorate(instance: Instance, spec: any)
	for _, tag in ipairs(spec.Tags or {}) do
		instance:AddTag(tag)
	end
	for key, value in pairs(spec.Attributes or {}) do
		instance:SetAttribute(key, value)
	end
end

function Builder.CastShadow(spec: any): boolean
	if spec.CastShadow ~= nil then
		return spec.CastShadow == true
	end
	if NO_SHADOW_MATERIALS[spec.Material or ""] or (spec.Transparency or 0) >= 0.5 then
		return false
	end
	local size = spec.Size or Vector3.one
	return math.max(size.X, size.Y, size.Z) >= Builder.ShadowMinSize
end

-- context = {Attachments = {[name] = Attachment}, Beams = {{Beam, name0, name1}}}
local function buildChild(spec: any, parent: Instance, context: any): Instance
	local instance = Instance.new(spec.Class)
	instance.Name = spec.Name or spec.Class
	for key, value in pairs(spec) do
		if not CHILD_RESERVED[key] then
			set(instance, key, value)
		end
	end
	decorate(instance, spec)
	if instance:IsA("Attachment") then
		context.Attachments[instance.Name] = instance
	elseif instance:IsA("Beam") then
		table.insert(context.Beams, { instance, spec.Attachment0, spec.Attachment1 })
	end
	for _, child in ipairs(spec.Children or {}) do
		buildChild(child, instance, context)
	end
	instance.Parent = parent
	return instance
end

-- One part (unparented) at anchor * spec.CFrame.
function Builder.Part(spec: any, anchor: CFrame?, context: any?): BasePart
	local ctx = context or { Attachments = {}, Beams = {} }
	local part: any = Instance.new(spec.Class or "Part")
	part.Name = spec.Name or part.ClassName
	if part:IsA("Part") and spec.Shape then
		part.Shape = enumItem(Enum.PartType, spec.Shape) or Enum.PartType.Block
	end
	part.Size = spec.Size or Vector3.one
	part.CFrame = (anchor or CFrame.identity) * (spec.CFrame or CFrame.identity)
	part.Color = spec.Color or Color3.fromRGB(163, 162, 165)
	part.Material = Builder.Material(spec.Material)
	part.Transparency = spec.Transparency or 0
	part.Reflectance = spec.Reflectance or 0
	part.Anchored = spec.Anchored ~= false
	part.CanCollide = spec.CanCollide == true
	part.CanQuery = spec.CanQuery == true
	part.CanTouch = spec.CanTouch == true
	part.CastShadow = Builder.CastShadow(spec)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(spec.Props or {}) do
		set(part, key, value)
	end
	for key in pairs(spec) do
		if not PART_ONLY[key] then
			warn("World.Builder: unknown part key " .. tostring(key) .. " on " .. part.Name .. " (use Props)")
		end
	end
	decorate(part, spec)
	for _, child in ipairs(spec.Children or {}) do
		buildChild(child, part, ctx)
	end
	return part
end

local function linkBeams(context: any)
	for _, row in ipairs(context.Beams) do
		local beam: any = row[1]
		local a0, a1 = context.Attachments[row[2]], context.Attachments[row[3]]
		if a0 and a1 then
			beam.Attachment0, beam.Attachment1 = a0, a1
		else
			warn("World.Builder: beam " .. beam.Name .. " has a missing attachment (" .. tostring(row[2]) .. ", " .. tostring(row[3]) .. ")")
		end
	end
end

-- Sets ModelStreamingMode by name without failing where it is unsupported (warns instead).
function Builder.SetStreaming(model: Model, mode: string): boolean
	local item = enumItem(Enum.ModelStreamingMode, mode)
	local ok, err = pcall(function()
		(model :: any).ModelStreamingMode = item
	end)
	if not (item and ok) then
		warn("World.Builder: ModelStreamingMode " .. tostring(mode) .. " not set on " .. model.Name .. ": " .. tostring(err))
		return false
	end
	return true
end

-- Server only: keeps a PersistentPerPlayer model streamed in for `player` (warns where unsupported).
function Builder.AddPersistentPlayer(model: Model, player: Player): boolean
	local ok, err = pcall(function()
		(model :: any):AddPersistentPlayer(player)
	end)
	if not ok then
		warn("World.Builder: AddPersistentPlayer failed for " .. model.Name .. ": " .. tostring(err))
	end
	return ok
end

export type Options = {
	Name: string?,
	Parent: Instance?,
	BuilderId: string?,
	LayoutVersion: any?,
	StreamingMode: string?,
	PersistentPlayer: Player?,
	FXManaged: boolean?,
	Lod: { Near: number?, Far: number?, Cull: boolean? }?,
	Attributes: { [string]: any }?,
}

-- Builds `specs` at anchorCFrame into a Model (WorldPivot = the anchor). Parents it once at the end.
function Builder.Build(specs: { any }, anchorCFrame: CFrame?, options: Options?): Model
	local o: any = options or {}
	local anchor = anchorCFrame or CFrame.identity
	local model = Instance.new("Model")
	model.Name = o.Name or o.BuilderId or "Built"
	local context = { Attachments = {}, Beams = {} }
	local count = 0
	for _, spec in ipairs(specs) do
		local part = Builder.Part(spec, anchor, context)
		part.Parent = model
		count += 1
	end
	linkBeams(context)
	model.WorldPivot = anchor
	model:SetAttribute("BuilderId", o.BuilderId or model.Name)
	if o.LayoutVersion ~= nil then
		model:SetAttribute("LayoutVersion", o.LayoutVersion)
	end
	model:SetAttribute("PartCount", count)
	if o.FXManaged then
		model:SetAttribute("FXManaged", true)
	end
	for key, value in pairs(o.Attributes or {}) do
		model:SetAttribute(key, value)
	end
	if o.Lod then
		if o.Lod.Near then
			model:SetAttribute("LodNear", o.Lod.Near)
		end
		if o.Lod.Far then
			model:SetAttribute("LodFar", o.Lod.Far)
		end
		if o.Lod.Cull then
			model:SetAttribute("LodCull", true)
		end
		model:AddTag(Builder.LodTag)
	end
	if o.StreamingMode then
		Builder.SetStreaming(model, o.StreamingMode)
	end
	if o.Parent then
		model.Parent = o.Parent
		if o.PersistentPlayer and o.StreamingMode == "PersistentPerPlayer" then
			Builder.AddPersistentPlayer(model, o.PersistentPlayer)
		end
	end
	return model
end

-- Idempotent build: a child `name` of `parent` with LayoutVersion == version is reused; any other
-- child of that name is destroyed and buildFn() (which returns an unparented Model) replaces it.
-- Returns the model and whether it was (re)built.
function Builder.EnsureBuilt(parent: Instance, name: string, version: any, buildFn: () -> Model): (Model, boolean)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Model") and existing:GetAttribute("LayoutVersion") == version then
		return existing, false
	end
	if existing then
		existing:Destroy()
	end
	local model = buildFn()
	model.Name = name
	if model:GetAttribute("LayoutVersion") == nil then
		model:SetAttribute("LayoutVersion", version)
	end
	model.Parent = parent
	return model, true
end

return Builder
