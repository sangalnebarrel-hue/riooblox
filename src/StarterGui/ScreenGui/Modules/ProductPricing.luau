local RS = game:GetService("ReplicatedStorage")
local Marketplace = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local Price = require(RS.PriceFormat)

local P = {
	Cache = {},
	Loading = {},
	Retry = {},
	Busy = false,
}

local CACHE_SECONDS = 60
local RETRY_SECONDS = 5

local function redraw(c, parent)
	if parent and parent.Parent then
		c.Draw()
	end
end

local function loadPrice(c, parent, product)
	local id = product.Id

	if P.Loading[id] then
		return
	end

	if os.clock() < (P.Retry[id] or 0) then
		return
	end

	P.Loading[id] = true

	task.spawn(function()
		local ok, info = pcall(function()
			return Marketplace:GetProductInfoAsync(
				id,
				Enum.InfoType.Product
			)
		end)

		P.Loading[id] = nil

		if ok
			and type(info) == "table"
			and type(info.PriceInRobux) == "number"
			and info.PriceInRobux > 0 then

			P.Cache[id] = {
				Price = info.PriceInRobux,
				At = os.clock(),
			}

			P.Retry[id] = nil

			print(
				("[DOGROTS Paw Market] Product %d ready: R$%d")
					:format(id, info.PriceInRobux)
			)
		else
			P.Retry[id] = os.clock() + RETRY_SECONDS

			warn(
				("[DOGROTS Paw Market] Product %d price lookup failed: %s")
					:format(id, tostring(info))
			)

			task.delay(RETRY_SECONDS, function()
				if parent and parent.Parent then
					loadPrice(c, parent, product)
					redraw(c, parent)
				end
			end)
		end

		redraw(c, parent)
	end)
end

function P.Quote(c, parent, product)
	if type(product.Id) ~= "number" or product.Id <= 0 then
		return "ROBUX · COMING SOON", nil
	end

	if product.Enabled == false then
		return "ROBUX · NOT ON SALE", nil
	end

	local id = product.Id
	local entry = P.Cache[id]

	if entry and os.clock() - entry.At > CACHE_SECONDS then
		P.Cache[id] = nil
		entry = nil
	end

	if not entry then
		loadPrice(c, parent, product)
	end

	local function purchase()
		if P.Busy then
			return
		end

		P.Busy = true

		task.spawn(function()
			local transport, ok, result = pcall(function()
				return RS.RewardRequest:InvokeServer(
					product.Route or "CommerceProduct",
					{Key = product.Key}
				)
			end)

			if transport
				and ok
				and type(result) == "table"
				and result.ProductId == id then

				local shown, promptError = pcall(function()
					Marketplace:PromptProductPurchase(Player, id)
				end)

				if not shown then
					warn(
						"[DOGROTS Paw Market] Prompt failed:",
						promptError
					)

					c.State.CommerceMessage =
						"Purchase unavailable. Please try again."
				else
					c.State.CommerceMessage = nil
				end
			else
				c.State.CommerceMessage =
					transport
					and tostring(result)
					or "Connection interrupted. Please try again."
			end

			P.Busy = false
			redraw(c, parent)
		end)
	end

	if entry then
		return "BUY · " .. Price.Robux(entry.Price), purchase
	end

	-- Цена ещё загружается, но покупку не блокируем.
	-- Само окно Roblox всё равно покажет точную цену.
	if P.Loading[id] then
		return "BUY · CHECKING PRICE", purchase
	end

	return "BUY · ROBUX", purchase
end

Marketplace.PromptProductPurchaseFinished:Connect(function()
	P.Busy = false
end)

return P