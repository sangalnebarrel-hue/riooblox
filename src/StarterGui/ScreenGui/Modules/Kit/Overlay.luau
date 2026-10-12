-- Kit ScreenGui layers and the stack of dismissible overlays (modals, dropdowns). Escape and
-- gamepad B dismiss the top entry before anything else closes.
local Theme = require(script.Parent.Theme)
local Base = require(script.Parent.Base)

local Overlay = {}

-- Windows (DisplayOrder 60), modals (62, above windows), toasts / tooltips (95).
function Overlay.Windows(): ScreenGui
	return Base.Layer("KitWindows", Theme.Layer.Windows)
end

function Overlay.Modals(): ScreenGui
	return Base.Layer("KitModals", Theme.Layer.Modals)
end

function Overlay.Top(): ScreenGui
	return Base.Layer("KitOverlay", Theme.Layer.Overlay)
end

export type Entry = {
	Dismiss: (reason: string) -> (),
	Owner: any?, -- the window that was on top when it opened (closing it dismisses the entry)
	Kind: string?,
}

local entries: { Entry } = {}

-- Set by Kit: the kit window on top. Overlays opened over a window close with it.
Overlay.TopWindow = function(): any
	return nil
end

function Overlay.Push(entry: Entry): Entry
	if entry.Owner == nil then
		entry.Owner = Overlay.TopWindow()
	end
	table.insert(entries, entry)
	return entry
end

function Overlay.Remove(entry: Entry)
	local index = table.find(entries, entry)
	if index then
		table.remove(entries, index)
	end
end

-- Dismisses the most recent entry. Returns true when there was one.
function Overlay.DismissTop(reason: string?): boolean
	local entry = entries[#entries]
	if not entry then
		return false
	end
	table.remove(entries, #entries)
	task.spawn(entry.Dismiss, reason or "escape")
	return true
end

-- Dismisses every entry opened over `owner` (a window that is closing).
function Overlay.DismissOwned(owner: any, reason: string?)
	for i = #entries, 1, -1 do
		local entry = entries[i]
		if entry.Owner == owner then
			table.remove(entries, i)
			task.spawn(entry.Dismiss, reason or "owner")
		end
	end
end

function Overlay.Count(kind: string?): number
	if not kind then
		return #entries
	end
	local n = 0
	for _, entry in ipairs(entries) do
		if entry.Kind == kind then
			n += 1
		end
	end
	return n
end

-- A popup anchored under (or above) `anchor`, in the anchor's own ScreenGui so positions match.
-- Returns the panel frame (w x h) and the full-screen catcher behind it; clicking the catcher
-- calls onOutside.
function Overlay.Popup(anchor: GuiObject, w: number, h: number, onOutside: () -> ()): (any, any)
	local layer: any = anchor:FindFirstAncestorWhichIsA("LayerCollector") or Overlay.Top()
	local catcher = Base.New("TextButton", {
		Name = "KitPopupCatcher",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 900,
		Selectable = false,
	}, layer)
	catcher.Activated:Connect(onOutside)
	local screen = layer.AbsoluteSize
	local pos = anchor.AbsolutePosition
	local size = anchor.AbsoluteSize
	local x = math.clamp(pos.X + size.X - w, 8, math.max(8, screen.X - w - 8))
	local below = pos.Y + size.Y + 6
	local y = below
	if below + h > screen.Y - 8 then
		y = math.max(8, pos.Y - h - 6)
	end
	local panel = Base.New("Frame", {
		Name = "KitPopup",
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundColor3 = Theme.White,
		BorderSizePixel = 0,
		ZIndex = 901,
		Active = true,
	}, layer)
	Base.Corner(panel, Theme.Radius.Field)
	Base.Stroke(panel, Theme.Colors.edge, 2)
	return panel, catcher
end

return Overlay
