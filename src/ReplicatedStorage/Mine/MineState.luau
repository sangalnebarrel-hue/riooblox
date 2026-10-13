-- MineState: the client-side bridge between the mine controller (StarterPlayerScripts.MineClient)
-- and the elevator window (ScreenGui.Modules.MineScreen). Client only; both require this module,
-- so they share one table.
--   MineState.Location            {YardId, Layer, Kind}: where the local player is (Kind "Shaft" |
--                                 "Level" | nil = on the surface / elsewhere)
--   MineState.Riding              true during an elevator ride
--   MineState.Ride(yardId, layer) -> ok, message   set by MineClient (nil until it has started)
--   MineState.Changed             fires (location) when Location or Riding change
local State = {}

local changed = Instance.new("BindableEvent")
State.Changed = changed.Event
State.Location = { YardId = nil, Layer = 1, Kind = nil }
State.Riding = false
State.Ride = nil :: ((yardId: any, layer: number) -> (boolean, string?))?

function State.Set(location: any, riding: boolean?)
	local old = State.Location
	local moved = location ~= nil and (location.YardId ~= old.YardId or location.Layer ~= old.Layer or location.Kind ~= old.Kind)
	if location then
		State.Location = location
	end
	local ridingChanged = riding ~= nil and riding ~= State.Riding
	if riding ~= nil then
		State.Riding = riding
	end
	if moved or ridingChanged then
		changed:Fire(State.Location)
	end
end

return State
