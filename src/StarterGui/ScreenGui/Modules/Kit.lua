-- DOGROTS UI kit: one look and one behaviour for every new or reworked screen (Lab, upgrade tree,
-- equipment shop, dog artifacts, Dogdex, item collection, trades, showcase editor, decor
-- placement, events). Client-only. Documentation with examples: docs/UIKIT.md.
--
--   local Kit = require(gui.Modules.Kit)
--   local win = Kit.Window.new({Key = "Lab", Title = "GENETICS LAB", Accent = Kit.Theme.Colors.purple,
--     Tabs = {{Id = "dogs", Text = "DOGS"}, {Id = "recipes", Text = "RECIPES"}}})
--   local grid = Kit.CardGrid(win:Page("dogs"), {Kind = "Dog", Map = toCard, OnClick = pick})
--   grid:SetItems(dogs)
--   win:Open()
local Theme = require(script.Theme)
local Format = require(script.Format)
local Layout = require(script.Layout)
local Lang = require(script.Lang)
local Signal = require(script.Signal)
local Maid = require(script.Maid)
local Motion = require(script.Motion)
local Sound = require(script.Sound)
local Base = require(script.Base)
local Overlay = require(script.Overlay)
local Nav = require(script.Nav)
local Button = require(script.Button)
local Controls = require(script.Controls)
local Display = require(script.Display)
local Feedback = require(script.Feedback)
local Virtual = require(script.Virtual)
local Preview = require(script.Preview)
local Cards = require(script.Cards)
local Modal = require(script.Modal)
local Window = require(script.Window)

Overlay.TopWindow = Window.Top

local Kit = {}
Kit.Version = 2 -- 2: Kit.Sound, hover glow, tab underline (same API as 1)

-- Tokens and pure helpers.
Kit.Theme = Theme
Kit.Format = Format
Kit.Layout = Layout
Kit.Signal = Signal
Kit.Maid = Maid
Kit.Motion = Motion
Kit.Sound = Sound -- UI sound cues: Kit.Sound.Play("Click"), Attach(button), SetEnabled(on)
Kit.Words = Lang.Words

-- Language: "ru" | "en", a self-localized pick, and kit-internal words (AutoTranslate).
function Kit.Lang(): string
	return Lang.Get()
end
function Kit.T(en: string, ru: string?): string
	return Lang.T(en, ru)
end
Kit.Word = Lang.Word

-- Server clock (unix seconds) without polling.
Kit.Now = Display.Now

-- Instance helpers.
Kit.New = Base.New
Kit.Text = Base.Text
Kit.Icon = Base.Icon
Kit.Corner = Base.Corner
Kit.Stroke = Base.Stroke
Kit.Padding = Base.Padding

-- Windows and overlays.
Kit.Window = Window
Kit.Modal = Modal.new
Kit.Confirm = Modal.Confirm
Kit.Alert = Modal.Alert
Kit.Toast = Feedback.Toast
Kit.Tooltip = Feedback.Tooltip
Kit.LongPress = Feedback.LongPress

-- Controls.
Kit.Button = Button.new
Kit.Tabs = Controls.Tabs.new
Kit.SearchBox = Controls.SearchBox.new
Kit.Chips = Controls.Chips.new
Kit.SortSelect = Controls.SortSelect.new

-- Display.
Kit.Pill = Display.Pill
Kit.Badge = Display.Badge
Kit.RarityTag = Display.RarityTag
Kit.VariantTag = Display.VariantTag
Kit.MutationTag = Display.MutationTag
Kit.ProgressBar = Display.ProgressBar
Kit.StatRow = Display.StatRow
Kit.Countdown = Display.Countdown
Kit.EmptyState = Display.EmptyState

-- Lists and cards.
Kit.VirtualGrid = Virtual.Grid.new
Kit.VirtualList = Virtual.List
Kit.DogCard = Cards.DogCard
Kit.ItemCard = Cards.ItemCard
Kit.CardGrid = Cards.Grid
Kit.Preview = Preview

-- Integration hooks.
Kit.SetNavigation = Nav.Set -- override the navigation owner (tests / tools); false = none
Kit.Overlay = Overlay

-- Counters for tests and debugging.
function Kit.Stats(): any
	local toasts, queued = Feedback.ToastCount()
	return {
		Windows = Window.Count(),
		Modals = Modal.Count(),
		Overlays = Overlay.Count(),
		Toasts = toasts,
		ToastQueue = queued,
		Countdowns = Display.ActiveCountdowns(),
		Preview = Preview.Stats(),
		Sound = Sound.Stats(),
	}
end

return Kit
