--!strict
-- DecorIdle: the pure maths of plot-decoration idle animations. Recipes in ReplicatedStorage.Decor.DecorModels put
-- the attributes on a part or a sub-model, StarterPlayerScripts.PlotCosmetics plays them on the client, and
-- tests/underyard_cosmetics.luau checks every pose with the same functions. No services, no state.
--   IdleAnim    "Swing" | "Sway" | "Bob" | "Spin"  move the parts about a pivot
--               "Flicker" | "Pulse" | "Blink"      glow / visibility only (nothing moves)
--   IdlePivot   CFrame in the decoration's model space (its Root at the build origin)
--   IdleAxis    "X" | "Y" | "Z" axis of the pivot     IdleAmp     degrees | studs (Bob) | 0..1 strength
--   IdlePeriod  seconds per cycle / turn / blink gap  IdlePhase   0..1        IdleTurn   Bob yaw (degrees)
--
--   DecorIdle.Spec(inst, rootCFrame?) -> Spec?        the track of one tagged instance (nil when untagged)
--   DecorIdle.Delta(spec, t) -> CFrame                 model-space transform of the moving parts at time t
--   DecorIdle.Glow(spec, t, seed?) -> (fade, light)    LocalTransparencyModifier and light-brightness factor
--   DecorIdle.Samples(spec, n?) -> { number }          times that cover the whole motion (QA, tests)
local DecorIdle = {}

export type Spec = {
	Kind: string,
	Moves: boolean,
	Pivot: CFrame,
	Axis: Vector3,
	Amp: number,
	Period: number,
	Phase: number,
	Turn: number,
}

DecorIdle.Moves = { Swing = true, Sway = true, Bob = true, Spin = true }
DecorIdle.Looks = { Flicker = true, Pulse = true, Blink = true }
DecorIdle.Defaults = {
	Swing = { Axis = "X", Amp = 12, Period = 2.6 },
	Sway = { Axis = "Z", Amp = 4, Period = 4.5 },
	Bob = { Axis = "Y", Amp = 0.25, Period = 3 },
	Spin = { Axis = "Y", Amp = 0, Period = 10 },
	Flicker = { Axis = "Y", Amp = 0.5, Period = 1 },
	Pulse = { Axis = "Y", Amp = 0.5, Period = 2.4 },
	Blink = { Axis = "Y", Amp = 1, Period = 4 },
}
DecorIdle.BlinkTime = 0.13 -- seconds the eyes stay shut

local AXES = { X = Vector3.new(1, 0, 0), Y = Vector3.new(0, 1, 0), Z = Vector3.new(0, 0, 1) }
local TAU = math.pi * 2

local function number(inst: Instance, key: string, default: number): number
	local v = inst:GetAttribute(key)
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return default
end

-- Centre of the box around the parts of a group, as a plain translation (pure maths: also works in Lune).
local function centre(inst: Instance): CFrame
	local lo, hi
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d.CFrame.Position
			lo = lo and lo:Min(p) or p
			hi = hi and hi:Max(p) or p
		end
	end
	return lo and CFrame.new((lo + hi) / 2) or CFrame.new()
end

-- The track of a tagged part or group; rootCFrame turns a default pivot into model space.
function DecorIdle.Spec(inst: Instance, rootCFrame: CFrame?): Spec?
	local kind = inst:GetAttribute("IdleAnim")
	if type(kind) ~= "string" then
		return nil
	end
	local defaults = DecorIdle.Defaults[kind]
	if not defaults then
		return nil
	end
	local pivot = inst:GetAttribute("IdlePivot")
	if typeof(pivot) ~= "CFrame" then
		local world = if inst:IsA("BasePart") then (inst :: BasePart).CFrame else centre(inst)
		pivot = (rootCFrame or CFrame.new()):ToObjectSpace(world)
	end
	local axisName = inst:GetAttribute("IdleAxis")
	local axis = AXES[if type(axisName) == "string" then axisName else defaults.Axis] or AXES[defaults.Axis]
	return {
		Kind = kind,
		Moves = DecorIdle.Moves[kind] == true,
		Pivot = pivot :: CFrame,
		Axis = axis,
		Amp = number(inst, "IdleAmp", defaults.Amp),
		Period = math.max(0.2, number(inst, "IdlePeriod", defaults.Period)),
		Phase = number(inst, "IdlePhase", 0),
		Turn = number(inst, "IdleTurn", 0),
	}
end

-- Movement in pivot space at time t (seconds).
local function offset(spec: Spec, t: number): CFrame
	local phase = TAU * (t / spec.Period + spec.Phase)
	if spec.Kind == "Spin" then
		return CFrame.fromAxisAngle(spec.Axis, phase % TAU)
	elseif spec.Kind == "Bob" then
		local lift = CFrame.new(spec.Axis * (spec.Amp * math.sin(phase)))
		if spec.Turn ~= 0 then
			return lift * CFrame.fromAxisAngle(Vector3.new(0, 1, 0), math.rad(spec.Turn) * math.sin(phase * 0.5 + 0.7))
		end
		return lift
	elseif spec.Kind == "Sway" then
		-- two incommensurate waves: a branch in the wind never repeats exactly; |sum| <= 1
		return CFrame.fromAxisAngle(spec.Axis, math.rad(spec.Amp) * (0.72 * math.sin(phase) + 0.28 * math.sin(phase * 2.3 + 1.1)))
	elseif spec.Kind == "Swing" then
		return CFrame.fromAxisAngle(spec.Axis, math.rad(spec.Amp) * math.sin(phase))
	end
	return CFrame.new()
end

-- Model-space transform that takes a moving part from its rest CFrame to its pose at time t:
-- pose (world) = root.CFrame * Delta(spec, t) * rest (model space).
function DecorIdle.Delta(spec: Spec, t: number): CFrame
	if not spec.Moves then
		return CFrame.new()
	end
	return spec.Pivot * offset(spec, t) * spec.Pivot:Inverse()
end

-- Glow tracks: (LocalTransparencyModifier 0..1, light brightness factor 0..1) at time t; seed decorrelates parts.
function DecorIdle.Glow(spec: Spec, t: number, seed: number?): (number, number)
	local amp = math.clamp(spec.Amp, 0, 1)
	if spec.Kind == "Flicker" then
		local p = TAU * spec.Phase + (seed or 0)
		local f = math.clamp(0.5 + 0.28 * math.sin(t * 11.3 + p) + 0.14 * math.sin(t * 23.7 + p * 2.1) + 0.08 * math.sin(t * 5.3 + p * 3.7), 0, 1)
		return amp * 0.55 * f, 1 - amp * 0.5 * f
	elseif spec.Kind == "Pulse" then
		local low = 0.5 - 0.5 * math.sin(TAU * (t / spec.Period + spec.Phase))
		return amp * 0.8 * low, 1 - amp * 0.6 * low
	elseif spec.Kind == "Blink" then
		local cycles = t / spec.Period + spec.Phase
		local into = (cycles % 1) * spec.Period
		local shut = into < DecorIdle.BlinkTime
		-- every third cycle blinks twice
		if not shut and math.floor(cycles) % 3 == 0 then
			shut = into > 0.3 and into < 0.3 + DecorIdle.BlinkTime
		end
		if shut then
			return 1, 0
		end
		return 0, 1
	end
	return 0, 1
end

-- Times that cover a track's whole range of poses (n samples over several cycles; a full turn for Spin).
function DecorIdle.Samples(spec: Spec, n: number?): { number }
	local count = n or 48
	local span = spec.Kind == "Sway" and spec.Period * 3 or spec.Period
	local out = {}
	for i = 0, count - 1 do
		table.insert(out, span * i / count)
	end
	return out
end

return DecorIdle
