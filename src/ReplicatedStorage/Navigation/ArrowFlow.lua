-- Navigation.ArrowFlow: where the ground arrows of "SHOW THE WAY" stand and how bright they are
-- (pure maths, tested by tests/navigation.luau; drawn by Navigation.PathGuide).
--   * Arrows sit on a lattice fixed to the route (every Spacing studs), shifted by a phase that
--     grows with time, so they glide towards the target while the ground stays put.
--   * Only the window [progress + Near, progress + Far] is drawn (never more than Max arrows);
--     arrows fade in / out over Fade studs at both ends and stop EndGap studs before the goal.
--   * A brightness wave runs along the route faster than the arrows (WaveSpeed).
--   * Static = true (Reduced Motion): no phase, no wave, constant brightness.
local ArrowFlow = {}

ArrowFlow.Defaults = {
	Spacing = 5, -- studs between arrows
	Near = 10, -- first arrow this far ahead of the player
	Far = 90, -- last arrow
	Max = 16, -- pool size (2 neon bars per arrow)
	Speed = 6, -- arrow glide, studs per second
	WaveSpeed = 28, -- brightness wave, studs per second
	WaveLength = 30, -- distance between two brightness crests
	Fade = 6, -- fade-in / fade-out band at the window ends
	EndGap = 3, -- free space before the goal (the final pointer takes over)
	Static = false,
}

-- Low quality: half the arrows over half the distance (same spacing, same look up close).
ArrowFlow.Low = { Max = 8, Far = 50 }

function ArrowFlow.Config(overrides: any?): any
	local cfg = table.clone(ArrowFlow.Defaults)
	for key, value in pairs(overrides or {}) do
		cfg[key] = value
	end
	return cfg
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Layout(length, progress, time, cfg) -> {{S, Alpha, Glow}} sorted by S (nearest first).
--   length    route length (studs), progress  the player's arc length on the route,
--   time      seconds (any clock), cfg       ArrowFlow.Config(...)
function ArrowFlow.Layout(length: number, progress: number, time: number, cfg: any): { any }
	local out = {}
	local spacing = math.max(0.5, cfg.Spacing)
	local first = math.max(0, progress) + cfg.Near
	local last = math.min(length - cfg.EndGap, math.max(0, progress) + cfg.Far)
	if last <= first then
		return out
	end
	local phase = cfg.Static and 0 or (time * cfg.Speed) % spacing
	local k = math.ceil((first - phase) / spacing - 1e-9)
	local s = k * spacing + phase
	while s <= last + 1e-9 and #out < cfg.Max do
		local fadeIn = cfg.Fade > 0 and smooth((s - first) / cfg.Fade) or 1
		local fadeOut = cfg.Fade > 0 and smooth((last - s) / cfg.Fade) or 1
		-- The window's far end does not fade when it is the goal itself (arrows lead right up to it).
		if last < math.max(0, progress) + cfg.Far - 1e-6 then
			fadeOut = 1
		end
		local glow = 0.35
		if not cfg.Static then
			local wave = 0.5 + 0.5 * math.cos(2 * math.pi * (s - time * cfg.WaveSpeed) / cfg.WaveLength)
			glow = wave ^ 3
		end
		table.insert(out, { S = s, Alpha = math.min(fadeIn, fadeOut), Glow = glow })
		s += spacing
	end
	return out
end

return ArrowFlow
