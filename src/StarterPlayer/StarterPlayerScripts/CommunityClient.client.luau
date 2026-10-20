-- DEVELOPER MAILBOX window of the Welcome Hub (ScreenGui "CommunityServices", DisplayOrder 70) and the client side of
-- the DOG SHELTER prompt.
--  * The DOG SHELTER is the Kit window Modules.ShelterScreen (GUIIntegration.kitScreens.Shelter): the server opens it
--    with DogEconomyOpen('Shelter'); ShelterScreen.Watch() opens it at once on the local PromptTriggered and
--    localizes the prompt. An old server's CommunityOpen('Shelter') is routed to the same window.
--  * The mailbox (FeedbackPrompt / CommunityOpen('Feedback')): write a message to the developers; developers also
--    get the inbox. It takes navigation as owner 'Community' (prompts and movement lock while it is open) and closes
--    on ×, Escape, gamepad B, another menu, respawn or walking more than 23 studs away. The walk-away check is
--    pcall'd and streaming-safe (FindFirstChild), so one missing part never stops it (A07 D10).
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local main = playerGui:FindFirstChild("ScreenGui")
while not main do
	local child = playerGui.ChildAdded:Wait()
	if child.Name == "ScreenGui" then
		main = child
	end
end
local modules = main:WaitForChild("Modules")
local N = require(modules:WaitForChild("GUIIntegration"))
local U = require(modules.UITheme)

-- DOG SHELTER: the Kit window watches its prompt (instant open + Russian prompt text).
task.spawn(function()
	local module = modules:WaitForChild("ShelterScreen", 30)
	if not module then
		warn("DOGROTS community: Modules.ShelterScreen missing")
		return
	end
	local ok, screen = pcall(require, module)
	if ok and type(screen) == "table" and type(screen.Watch) == "function" then
		local watched, err = pcall(screen.Watch)
		if not watched then
			warn("DOGROTS shelter watch: " .. tostring(err))
		end
	else
		warn("DOGROTS community: ShelterScreen failed to load: " .. tostring(screen))
	end
end)

local palette = { Navy = U.Colors.purple, Cream = U.Colors.text, Gold = U.Colors.purple, Teal = U.Colors.green, Muted = U.Colors.muted }
local mode, busy, epoch, draft, token, inboxDay = nil, false, 0, "", nil, 0
local W, H = 740, 570
local gui = Instance.new("ScreenGui")
gui.Name = "CommunityServices"
gui.ResetOnSpawn = false
gui.DisplayOrder = 70
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Enabled = false
gui.Parent = player.PlayerGui
local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end
local root = new("Frame", { Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(740, 570), BackgroundColor3 = Color3.fromRGB(255, 251, 242), BorderSizePixel = 0 }, gui)
new("UICorner", { CornerRadius = UDim.new(0, 14) }, root)
new("UIStroke", { Color = U.Colors.edge, Thickness = 3 }, root)
local scale = new("UIScale", {}, root)
-- Phones (narrow OR short screens, like Kit.Layout): the window keeps its 740 x 570 design and scales into the safe
-- area; the × button and the action buttons stay at least ~44 px tall on a landscape phone.
local function resize()
	local _, _, width, height = U.SafeArea(gui)
	local factor = math.max(0.45, math.min(1, (width - 20) / W, (height - 20) / H))
	scale.Scale = factor
	root.Size = UDim2.fromOffset(W, H)
	root.Position = U.SafePosition(gui, W, H, factor, 10)
end
local function text(parent, value, x, y, w, h, size, color)
	return U.Text(parent, value, x, y, w, h, size, color or palette.Cream)
end
local function button(parent, value, x, y, w, h, callback, color)
	local close = value == "×"
	local b = U.Button(parent, "Action", value, x, y, w, h, callback and function()
		if not busy or close then
			callback()
		end
	end or nil, color or palette.Teal)
	b:SetAttribute("RequestAction", not close)
	b:SetAttribute("IntrinsicEnabled", callback ~= nil)
	U.SetButtonEnabled(b, callback ~= nil and (not busy or close))
	return b
end
local title = text(root, "DEVELOPER MAILBOX", 24, 16, 610, 38, 26, palette.Gold)
local description = text(root, "", 24, 61, 685, 49, 16, palette.Muted)
local content = new("Frame", { Position = UDim2.fromOffset(24, 119), Size = UDim2.fromOffset(692, 381), BackgroundTransparency = 1 }, root)
local status = text(root, "", 24, 511, 692, 43, 15, palette.Gold)
local function close()
	epoch += 1
	gui.Enabled = false
	mode = nil
	busy = false
	if N.Owner == "Community" then
		N.Close()
	end
end
local closeButton = button(root, "×", 670, 12, 56, 50, close, U.Colors.red)
UIS.InputBegan:Connect(function(input, processed)
	if not gui.Enabled then
		return
	end
	-- Escape (keyboard) and B (gamepad) close the mailbox; a focused text box keeps Escape for itself.
	if input.KeyCode == Enum.KeyCode.ButtonB or (input.KeyCode == Enum.KeyCode.Escape and not processed) then
		if UIS:GetFocusedTextBox() and input.KeyCode ~= Enum.KeyCode.ButtonB then
			return
		end
		close()
	end
end)
main:GetAttributeChangedSignal("OpenMenu"):Connect(function()
	if gui.Enabled and N.Owner ~= "Community" then
		gui.Enabled = false
		epoch += 1
		mode = nil
		busy = false
	end
end)
local function layout()
	resize()
	-- The × stays a >= 44 px touch target on screen whatever the window scale.
	local closeSize = math.clamp(math.ceil(46 / math.max(0.1, scale.Scale)), 50, 96)
	closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	closeButton.Position = UDim2.fromOffset(W - closeSize - 14, 10)
	title.Size = UDim2.fromOffset(W - closeSize - 60, 42)
	description.Size = UDim2.fromOffset(W - 48, 49)
	content.Size = UDim2.fromOffset(W - 48, H - 189)
	status.Position = UDim2.fromOffset(24, H - 59)
	status.Size = UDim2.fromOffset(W - 48, 43)
end
local function controls()
	for _, b in ipairs(root:GetDescendants()) do
		if b:IsA("GuiButton") and b:GetAttribute("RequestAction") then
			U.SetButtonEnabled(b, not busy and b:GetAttribute("IntrinsicEnabled") == true)
		end
	end
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
layout()
local function clear()
	for _, c in content:GetChildren() do
		c:Destroy()
	end
end
local function request(remote, action, args, callback)
	if busy then
		return
	end
	busy = true
	controls()
	status.Text = "Please wait..."
	local id = epoch
	task.spawn(function()
		local transport, ok, data = pcall(function()
			return remote:InvokeServer(action, args)
		end)
		if epoch ~= id or not gui.Enabled then
			return
		end
		busy = false
		controls()
		if not transport or not ok then
			status.Text = transport and tostring(data) or "Connection interrupted. Please try again."
			return
		end
		status.Text = ""
		callback(data)
	end)
end
local showFeedback, showInbox
showInbox = function()
	request(RS.CommunityFeedbackRequest, "Read", { Day = inboxDay }, function(data)
		clear()
		description.Text = "DEVELOPER INBOX · " .. data.Date .. (data.Preview and " · LOCAL TEST" or " · Saved player messages")
		button(content, "WRITE A MESSAGE", 0, 0, 240, 44, function()
			showFeedback()
		end)
		button(content, "PREVIOUS DAY", 270, 0, 195, 44, function()
			inboxDay = math.min(6, inboxDay + 1)
			showInbox()
		end)
		button(content, "NEXT DAY", 480, 0, 212, 44, function()
			inboxDay = math.max(0, inboxDay - 1)
			showInbox()
		end)
		local sc = new("ScrollingFrame", { Position = UDim2.fromOffset(0, 56), Size = UDim2.fromOffset(692, 325), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.fromOffset(0, #data.Rows * 180) }, content)
		if #data.Rows == 0 then
			text(sc, "No messages for this day.", 12, 35, 650, 60, 21)
		end
		for i, row in ipairs(data.Rows) do
			local card = new("Frame", { Position = UDim2.fromOffset(0, (i - 1) * 180), Size = UDim2.fromOffset(676, 168), BackgroundColor3 = U.Colors.light, BorderSizePixel = 0 }, sc)
			text(card, "User " .. row.UserId .. " · " .. os.date("!%H:%M UTC", row.At), 12, 8, 650, 24, 14, palette.Gold)
			local body = text(card, row.Text, 12, 38, 650, 118, 16)
			body.TextYAlignment = Enum.TextYAlignment.Top
		end
	end)
end
showFeedback = function(access)
	clear()
	description.Text = "Share an idea, wish or problem with the developers. 10–500 characters. One message per minute."
	local box = new("TextBox", { Name = "MessageDraft", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(692, 242), BackgroundColor3 = U.Colors.light, BorderSizePixel = 0, Text = draft, PlaceholderText = "What would you like to see in DOGROTS?", PlaceholderColor3 = palette.Muted, TextColor3 = palette.Cream, TextSize = 20, TextWrapped = true, MultiLine = true, ClearTextOnFocus = false, Font = Enum.Font.FredokaOne, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, content)
	new("UIPadding", { PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, box)
	new("UICorner", { CornerRadius = UDim.new(0, 9) }, box)
	local count = text(content, "", 0, 248, 692, 30, 15, palette.Muted)
	local function updateDraft()
		if #box.Text > 2000 then
			box.Text = box.Text:sub(1, 2000)
		end
		if box.Text ~= draft then
			token = nil
		end
		draft = box.Text
		local n = utf8.len(draft) or 0
		count.Text = n .. " / 500 characters"
		count.TextColor3 = n > 500 and Color3.fromRGB(255, 133, 116) or palette.Muted
	end
	box:GetPropertyChangedSignal("Text"):Connect(updateDraft)
	updateDraft()
	button(content, "SEND TO DEVELOPERS", 0, 295, 430, 52, function()
		local n = utf8.len(draft) or 0
		if n < 10 or n > 500 then
			status.Text = "Write 10–500 characters before sending."
			return
		end
		token = token or Http:GenerateGUID(false):gsub("-", "")
		local submitted = draft
		request(RS.CommunityFeedbackRequest, "Send", { Text = draft, Token = token }, function(result)
			if draft == submitted then
				draft = ""
				token = nil
				box.Text = ""
			end
			status.Text = result.Message
		end)
	end)
	local function developerButton(info)
		if info.Developer then
			button(content, "DEVELOPER INBOX", 444, 295, 248, 52, function()
				showInbox()
			end, palette.Navy)
		end
		if info.Preview then
			status.Text = "Studio preview: messages exist only for this test session."
		end
	end
	if access then
		developerButton(access)
	else
		request(RS.CommunityFeedbackRequest, "Access", {}, developerButton)
	end
end

local function openShelter()
	-- The shelter is a Kit window: the same route as the server's DogEconomyOpen('Shelter').
	local ok, err = pcall(N.OpenPage, "Shelter")
	if not ok then
		warn("DOGROTS shelter open: " .. tostring(err))
	end
end

local function openMailbox()
	if gui.Enabled and mode == "Feedback" then
		return -- the local prompt open and the server's CommunityOpen both arrive
	end
	close()
	epoch += 1
	mode = "Feedback"
	N.Acquire("Community", "Feedback")
	gui.Enabled = true
	title.Text = "DEVELOPER MAILBOX"
	status.Text = ""
	layout()
	showFeedback()
	-- A disabled ScreenGui may not yet have its final AbsoluteSize on the first frame.
	task.defer(function()
		if gui.Parent and gui.Enabled and mode == "Feedback" then
			layout()
		end
	end)
end

RS:WaitForChild("CommunityOpen").OnClientEvent:Connect(function(kind)
	if kind == "Shelter" then
		openShelter()
	elseif kind == "Feedback" then
		openMailbox()
	end
end)

local function mailboxBody(): BasePart?
	local district = workspace:FindFirstChild("DOGROTS_District")
	local hub = district and district:FindFirstChild("32_WelcomeHub")
	local mailbox = hub and hub:FindFirstChild("DeveloperMailbox")
	local body = mailbox and mailbox:FindFirstChild("MailboxBody")
	if body and body:IsA("BasePart") then
		return body
	end
	return nil
end

game:GetService("ProximityPromptService").PromptTriggered:Connect(function(prompt, who)
	if who and who ~= player then
		return
	end
	local body = mailboxBody()
	if body and prompt == body:FindFirstChild("FeedbackPrompt") then
		openMailbox()
	end
end)

-- Walk-away close (0.5 s): pcall'd, FindFirstChild only.
task.spawn(function()
	while gui.Parent do
		task.wait(0.5)
		if gui.Enabled then
			local ok, err = pcall(function()
				local target = mailboxBody()
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if not target or not hrp or not hrp:IsA("BasePart") or (hrp.Position - target.Position).Magnitude > 23 then
					close()
				end
			end)
			if not ok then
				warn("DOGROTS mailbox: " .. tostring(err))
			end
		end
	end
end)
