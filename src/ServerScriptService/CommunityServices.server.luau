-- Community services of the WELCOME HUB.
--  * DOG SHELTER: ReplicatedStorage.ShelterRequest -> Economy.ShelterService (List / Quote / Sell). The prompt
--    DogShelter.SellAnchor.ShelterPrompt opens the Kit window Modules.ShelterScreen through
--    DogEconomyOpen('Shelter') (GUIIntegration.kitScreens.Shelter). Its HoldDuration is forced to 0 at runtime: a
--    quick tap on a phone must open the window, which has its own review + confirm (A07 D11). ShelterService still
--    validates the visit, the ownership and the price of every request.
--  * DEVELOPER MAILBOX: ReplicatedStorage.CommunityFeedbackRequest -> DeveloperInbox; FeedbackPrompt opens the
--    mailbox window of CommunityClient through CommunityOpen('Feedback').
-- Every lookup of the hub is FindFirstChild / WaitForChild based and pcall'd: a missing piece of the hub disables
-- that one service with a warning instead of killing the script.
local RS = game:GetService("ReplicatedStorage")
local shelter = require(script.Parent.Economy.ShelterService)
local inbox = require(script.Parent.DeveloperInbox)
local hub = workspace:WaitForChild("DOGROTS_District"):WaitForChild("32_WelcomeHub")

local function safe(fn, ...)
	local ok, success, result = pcall(fn, ...)
	if not ok then
		return false, tostring(success)
	end
	return success, result
end

RS:WaitForChild("ShelterRequest").OnServerInvoke = function(p, a, b)
	return safe(shelter.Request, p, a, b)
end

local function mailboxBody(): BasePart?
	local mailbox = hub:FindFirstChild("DeveloperMailbox")
	local body = mailbox and mailbox:FindFirstChild("MailboxBody")
	return body and body:IsA("BasePart") and body or nil
end

RS:WaitForChild("CommunityFeedbackRequest").OnServerInvoke = function(p, action, a)
	if not require(script.Parent.Economy.Runtime).Allow(p, 1) then
		return false, "Please wait"
	end
	local near = require(script.Parent.Economy.YardCommerce).Near(p, mailboxBody(), 18)
	if not near then
		return false, "Visit the developer mailbox first"
	end
	return safe(inbox.Request, p, action, a)
end

-- DOG SHELTER prompt -> Kit window (DogEconomyOpen). The old CommunityOpen route stays as a fallback for a place
-- without the economy remote.
task.spawn(function()
	local building = hub:WaitForChild("DogShelter", 60)
	local anchor = building and building:WaitForChild("SellAnchor", 60)
	local prompt = anchor and anchor:WaitForChild("ShelterPrompt", 60)
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		warn("DOGROTS community: DogShelter.SellAnchor.ShelterPrompt missing; the shelter cannot be opened")
		return
	end
	prompt.HoldDuration = 0 -- [WP-D2] A07 D11: the window confirms the sale itself
	local open = RS:WaitForChild("DogEconomyOpen", 30)
	prompt.Triggered:Connect(function(p)
		if open and open:IsA("RemoteEvent") then
			open:FireClient(p, "Shelter")
		else
			local legacy = RS:FindFirstChild("CommunityOpen")
			if legacy and legacy:IsA("RemoteEvent") then
				legacy:FireClient(p, "Shelter")
			end
		end
	end)
end)

task.spawn(function()
	local mailbox = hub:WaitForChild("DeveloperMailbox", 60)
	local body = mailbox and mailbox:WaitForChild("MailboxBody", 60)
	local prompt = body and body:WaitForChild("FeedbackPrompt", 60)
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		warn("DOGROTS community: DeveloperMailbox.MailboxBody.FeedbackPrompt missing")
		return
	end
	prompt.Triggered:Connect(function(p)
		if require(script.Parent.Economy.YardCommerce).Near(p, body, 18) then
			RS.CommunityOpen:FireClient(p, "Feedback")
		end
	end)
end)

print("DOGROTS_COMMUNITY_SERVICES_READY")
