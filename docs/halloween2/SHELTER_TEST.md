# DOG SHELTER — end-to-end test (Studio) · WP-D2

What changed (A07 D1-D16, DESIGN §15.1) and how to prove in Studio that the shelter opens and sells every time, on
desktop, phone and gamepad, after respawns and after Halloween overlays. The automated half runs in Lune:

```
lune run tests/shelter_e2e.luau      # 15 cases: List -> Quote -> Sell -> flush -> reload on a new server, protections,
                                     # hold-to-confirm, server-time expiry, visit rule, receipts, localization
```

## 1. What the player sees now

| Piece | Where | Behaviour |
|---|---|---|
| Prompt | `32_WelcomeHub.DogShelter.SellAnchor.ShelterPrompt` | **HoldDuration 0** (server sets it at runtime), Russian text on RU clients. Opens the window at once (local `PromptTriggered`) and again through the server's `DogEconomyOpen("Shelter")` (ignored for 2 s after a local open). |
| Window | `Modules.ShelterScreen` (Kit window `Shelter`, DisplayOrder 60) | List panel (count, worth, ALL / SELLABLE / PROTECTED chips, SELLABLE FIRST / RARITY / PRICE sort, virtual card list with 3D previews only for rows in view) + detail panel (preview, catalog value × 25% × bonus, PROTECTED + reason, REVIEW SALE → CONFIRM SALE). Phones: full-screen sheet; the detail slides up over the list (BACK). |
| Confirm | detail action bar | Price held for the server TTL (45 s, counted on the local monotonic clock). **Hold-to-confirm (1.2 s)** for Mythic / Secret dogs and every event dog; the server refuses those without `Confirm = true`. |
| States | over the list | LOADING → list; RETRYING (one automatic retry after 0.75 s for a lagged visit / loading profile / empty request bucket / no reply); COULD NOT LOAD + RETRY; NO DOGS YET; VISIT THE DOG SHELTER + SHOW THE WAY (opened far away). |
| Close | X, Escape, gamepad B, walking away (> 24 studs and outside the hall, two polls), respawn, another menu | Escape / B first cancel the confirm step, then close the phone sheet, then the window. |
| Mailbox | `CommunityClient` (`CommunityServices`, DisplayOrder 70) | Unchanged feature; × is ≥ 44 px on screen; gamepad B closes; walk-away loop is pcall'd. |

Server (`Economy.ShelterService`): visit = within **26 studs** of SellAnchor **or inside the shelter hall box**
(`ReplicatedStorage.DogEconomy.ShelterConfig`), separate messages for an unready profile ("Please wait for your
profile") and the rate limit ("Too many requests; wait a moment"), quotes carry `TTL` / `Expires` (server clock),
Favorite dogs are protected, one broken dog row cannot break the list, a sale records `Stats.Sale` + `LastSaleAt`
(+ player attribute `LastShelterSaleAt`) and releases the dog's artifacts (`Rules.Features.Normalize`). A Sell retried
with the same token is answered from the transaction receipt (never paid twice).

Navigation (`Modules.GUIIntegration`): `ProximityPromptService.Enabled == (N.Owner == "HUD")` (derived, never
saved/restored); movement locks are ref-counted by reason (`N.LockControls / N.UnlockControls`, the menu holds
`"Menu"`, the Halloween guide `"HalloweenGuide"`); `N.Acquire` always ends consistent; a 1 s watchdog sends a
non-HUD owner whose surface has been invisible for 2 s back to the HUD. The Halloween reward card is DisplayOrder 74.

## 2. Setup

1. Open `place/DOGROTS_HALLOWEEN_NIGHT_OF_THE_BURIED_MOON.rbxl` built with `tools/place_build.luau` (unpublished →
   `GameId == 0` → memory store, "LOCAL STUDIO PREVIEW" warning).
2. **Test → Clients and Servers**: 1 server + 2 players (real replication; the second player is for trades).
3. Studio Settings → Network → **Incoming Replication Lag 0.25** (reproduces the old "sometimes does not open").
4. Seed dogs: paste into a **temporary Script** in ServerScriptService (not the command bar: command-bar `require`
   does not share the game's module instances), Play, then delete the script:

```lua
local E = game.ServerScriptService.Economy
local rt, R = require(E.Runtime), require(E.Rules)
game.Players.PlayerAdded:Connect(function(plr)
	repeat task.wait(1) until rt.Ready(plr)
	local k = "p:" .. plr.UserId
	print(rt.Tx:Run({ k }, function(v)
		local p = v[k]
		p.Upgrades.DogStorage = math.max(p.Upgrades.DogStorage or 0, 4) -- room for 100 dogs
		local ids = { "Breadog", "Sausagedog", "KingCorgi", "Cerberdog", "HW_PumpkinPup", "HW_EclipseDog", "Potatodog" }
		for i = 1, 40 do
			local uid = (game.HttpService:GenerateGUID(false):gsub("-", ""))
			local d = R.Mint(p, ids[i % #ids + 1], uid, { Minted = 0 }, os.time(), math.random, "Test", nil, true)
			if i == 1 then d.Locked = true end
			if i == 2 then d.Favorite = true end
			if i == 3 then d.Variant = "Golden"; d.Mastery = 50; d.AscensionLevel = 1 end
		end
		R.Validate(p)
		return "seeded"
	end))
	rt.Refresh(plr)
	_G.ShelterRT = rt
end)
```

(For 150+ dogs raise `DogStorage` further: capacity = min(250, 20 + 20 × DogStorage).)

## 3. The invariant probe (run on every client, keep it running for the whole session)

Paste into the **client** command bar. It prints a line whenever the navigation state is inconsistent and once a
second confirms the state while it changes. With nothing open it must read `HUD nil true -`:

```lua
local g = game.Players.LocalPlayer.PlayerGui.ScreenGui
local N = require(g.Modules.GUIIntegration)
local PPS = game:GetService("ProximityPromptService")
local last
task.spawn(function()
	while task.wait(1) do
		local open = g:GetAttribute("OpenMenu")
		local locks = g:GetAttribute("ControlLocks") or "-"
		local line = string.format("%s %s %s %s", N.Owner, tostring(open), tostring(PPS.Enabled), locks)
		if open == nil and not PPS.Enabled then
			warn("INVARIANT BROKEN: OpenMenu == nil but ProximityPromptService.Enabled == false · " .. line)
		end
		local ok, why = N.Invariant()
		if not ok then warn("INVARIANT BROKEN: " .. why) end
		if line ~= last then print("nav:", line); last = line end
	end
end)
```

Pass criterion for every step below: no `INVARIANT BROKEN` line, and after closing whatever was open the probe
prints `nav: HUD nil true -` within 2 s (the watchdog) — **without pressing Escape** (touch players have none).

## 4. Procedure

### 4.1 Happy path (desktop)
1. Press M → Dog Shelter → SHOW THE WAY; walk in; press E once (no hold). The window opens instantly: LOADING, then
   the list. Probe while open: `nav: Kit Shelter false Menu` (prompts off and movement locked by the menu only).
2. Rows: SELLABLE first, cheapest first. Chips show counts; the header shows "SELLABLE n · WORTH x".
3. Click a dog → only that card restyles (no flicker of the other previews); detail shows CATALOG VALUE, SHELTER
   RATE ×25%, BONUS (the Golden M50 A1 dog: ×1.41, "Variant +30% · Mastery +7.5% · Ascension +3%"), YOU RECEIVE.
4. REVIEW SALE → CONFIRM SALE + CANCEL, hint "Price held for 00:44" counting down.
5. CONFIRM → toast "<dog> found a new home! +N Coins", NEW HOME FOUND banner, `leaderstats.Coins` +N, the next dog
   selected, the list refreshed (count −1). `Players.<p>.DogInventory.<uid>` is gone; MY DOGS no longer lists it.
6. Server command bar: `print(_G.ShelterRT.Tx.Dirty["p:<userId>"])` → `true`; after ≤ 60 s autosave → `nil`.
7. Close with X → probe back to `HUD nil true -`.

### 4.2 Protections and confirmations
| Action | Expected |
|---|---|
| Select the locked / favorite dog | PROTECTED · LOCKED (🔒) / FAVORITE (❤️) card, reason text, button disabled |
| Assign a dog to a kennel, display a dog, buy a dog (walking) | PROTECTED · IN KENNEL / ON DISPLAY / WORKING |
| Open a trade with player 2 | every row PROTECTED · IN TRADE; REVIEW refuses with "Finish your trade first" |
| Review a Cerberdog / HW_EclipseDog / HW_PumpkinPup | gold CONFIRM SALE with "✋ HOLD TO CONFIRM · 00:44"; a tap does nothing, a 1.2 s hold sells |
| Review, wait 45 s | "PRICE EXPIRED", REVIEW AGAIN re-quotes |
| Set the **device clock** 5 minutes ahead (phone / emulator), review, confirm within 45 s | sells (the old window expired every quote) |
| Review, then favourite the dog in MY DOGS (other client tab) and confirm | toast "Remove this dog from favorites first", back to REVIEW SALE, list refreshed |
| Equip an artifact on a dog, sell it, open EQUIPMENT | the artifact is in the bag and can be salvaged at once |

### 4.3 The reported bug ("sometimes the shelter does not open")
Run each, then check the probe and that E / tap opens the shelter at once:
1. **Lag**: replication lag 0.25, sprint in (×3 speed buff if available) and press E at the prompt edge → the window
   opens; if the server saw you outside it shows RETRYING… once and then the list (never a stuck "Loading").
2. **Respawn**: reset the character with the window open → it closes (probe `HUD nil true -`), sprint back from the
   spawn, open again.
3. **After the Halloween reward card**: F7 → TEST REWARD CARD, close it, walk to the shelter → opens. With the card
   still up, the card (DisplayOrder 74) draws above the Kit window; closing it leaves the shelter usable.
4. **After the brew finale**: F7 → TEST BREW FINALE, let it play, walk to the shelter → opens.
5. **Halloween onboarding**: F7 → GUIDE AGAIN (resets `Onboarded`), rejoin, then enter the Dead Yard **with HIDE UI on**: the guide starts
   paused (no camera lock, you can walk); show the UI → the card appears with its camera shot. Open the HALLOWEEN
   window mid-card → camera back, controls stay locked by the menu (`ControlLocks = Menu`); close it → the card
   resumes. Walk out of the Dead Yard mid-guide → the card disappears and the camera is yours; walk back → it resumes
   at the same card.
6. **Stale owner**: client command bar `require(game.Players.LocalPlayer.PlayerGui.ScreenGui.Modules.GUIIntegration).Acquire("Kit", "Ghost")`
   (an owner with no window) → within 2-3 s the watchdog warns "Kit has no visible surface" and the probe returns to
   `HUD nil true -`; the shelter prompt works again.
7. HALLOWEEN window open/close incl. the DogDex tab; Lucky Block opening (reward owner) → probe returns to HUD.

### 4.4 Mobile (Device emulator: iPhone 14 portrait and landscape, iPad)
1. Tap the prompt once (no hold) → the window is a full-screen sheet; header X ≥ 44 px.
2. Portrait: list only; tapping a dog slides the detail sheet up (BACK at the top-left, scrim behind). CONFIRM /
   CANCEL ≥ 46 px. Landscape ≥ 600 px wide: list and detail side by side.
3. A player with 150+ dogs: scrolling stays smooth (only the visible rows build 3D previews, 2 per frame); tapping a
   dog responds within a frame (no list rebuild).
4. Walk away with the window open (virtual joystick is locked while a menu is open: close, walk, reopen) — no Esc is
   ever needed.

### 4.5 Gamepad (Xbox controller in Studio)
1. Open with ButtonX at the prompt; the first card is selected; D-pad moves through the list.
2. ButtonA on a card selects it (phone: opens the sheet, the action button takes the selection).
3. ButtonB: cancels a review first, then closes the sheet, then the window.
4. Hold ButtonA on a gold CONFIRM SALE for 1.2 s to sell a hold-to-confirm dog.

### 4.6 Persistence
1. Sell a dog, wait for the autosave (or leave): rejoin (Stop / Play) → the dog is still gone, the coins are kept,
   `Stats.TotalSellValue` and `LastSaleAt` are set (the rebuilt tutorial's sale step reads `LastSaleAt`).
2. Two servers (publish to a test place): sell on server A, leave, join server B → same result (the E2E test runs
   exactly this with a fake DataStore and a second Transactions/Engine instance).

## 5. Remote contract (`ReplicatedStorage.ShelterRequest:InvokeServer(action, args)` → `true, data | false, message`)

| action | args | data |
|---|---|---|
| `List` | `{}` | `{Rows, Count, Sellable, Total, Rate, TTL, HoldSeconds, ServerNow}`; row = `{Uid, DogId, Name, Rarity, Variant, Mastery, AscensionLevel, Locked, Favorite, State, AssignedSlot, Edition, SerialNumber, PaidRandom, Rank, Event, Price, Breakdown{Base, Rate, Bonus, Variant, Mastery, Ascension, Price}, Eligible, Reason?, Protection?, NeedsHold}` |
| `Quote` | `{Uid}` | row + `{Token (32 hex), TTL, Expires (server os.time), ServerNow}` |
| `Sell` | `{Token, Confirm?}` | `{Message, Cash, Uid, Name, DogId, Balance}` |

Protection codes: `Missing Trade Locked Favorite Kennel Working Display Listing Reserved Error`. Messages and their
Russian text: `Economy.ShelterRules.Messages`, `ReplicatedStorage.Localization.Shelter`.
