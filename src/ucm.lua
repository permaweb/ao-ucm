local bint = require('.bint')(256)
local json = require('json')

local utils = require('utils')

if Name ~= 'Universal Content Marketplace' then Name = 'Universal Content Marketplace' end

ACTIVITY_PROCESS = '7_psKu3QHwzc2PFCJk2lEwyitLJbz6Vj7hOcltOulj4'
PIXL_PROCESS = 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo'
DEFAULT_SWAP_TOKEN = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'

-- Orderbook {
-- 	Pair [TokenId, TokenId],
-- 	Orders {
-- 		Id,
-- 		Creator,
-- 		Quantity,
-- 		OriginalQuantity,
-- 		Token,
-- 		DateCreated,
-- 		Price?
-- 	} []
-- } []

if not Orderbook then Orderbook = {} end
if not BuybackCaptures then BuybackCaptures = {} end

local ucm = {}

local function handleError(args) -- Target, TransferToken, Quantity
	-- If there is a valid quantity then return the funds
	if args.TransferToken and args.Quantity and utils.checkValidAmount(args.Quantity) then
		ao.send({
			Target = args.TransferToken,
			Action = 'Transfer',
			Tags = {
				Recipient = args.Target,
				Quantity = tostring(args.Quantity)
			}
		})
	end
	ao.send({ Target = args.Target, Action = args.Action, Tags = { Status = 'Error', Message = args.Message, ['X-Group-ID'] = args.OrderGroupId } })
end

function ucm.getPairIndex(pair)
	local pairIndex = -1

	for i, existingOrders in ipairs(Orderbook) do
		if (existingOrders.Pair[1] == pair[1] and existingOrders.Pair[2] == pair[2]) or
			(existingOrders.Pair[1] == pair[2] and existingOrders.Pair[2] == pair[1]) then
			pairIndex = i
		end
	end

	return pairIndex
end

function ucm.createOrder(args)
	local validPair, pairError = utils.validatePairData({ args.dominantToken, args.swapToken })

	if not validPair then
		handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = pairError or 'Error validating pair',
			Quantity = args.quantity,
			TransferToken = nil,
			OrderGroupId = args.orderGroupId
		})
		return
	end

	local currentToken = validPair[1]
	local pairIndex = ucm.getPairIndex(validPair)

	if pairIndex == -1 then
		table.insert(Orderbook, { Pair = validPair, Orders = {} })
		pairIndex = ucm.getPairIndex(validPair)
	end

	if not utils.checkValidAmount(args.quantity) then
		handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Quantity must be an integer greater than zero',
			Quantity = args.quantity,
			TransferToken = currentToken,
			OrderGroupId = args.orderGroupId
		})
		return
	end

	if args.price and not utils.checkValidAmount(args.price) then
		handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Price must be an integer greater than zero',
			Quantity = args.quantity,
			TransferToken = currentToken,
			OrderGroupId = args.orderGroupId
		})
		return
	end

	if pairIndex > -1 then
		local orderType

		if args.price then
			orderType = 'Limit'
		else
			orderType = 'Market'
		end

		local remainingQuantity = bint(args.quantity)
		local currentOrders = Orderbook[pairIndex].Orders
		local updatedOrderbook = {}
		local matches = {}

		-- Sort order entries based on price
		table.sort(currentOrders, function(a, b)
			return bint(a.Price) < bint(b.Price)
		end)

		-- If the incoming order is a limit order, add it to the order book
		if orderType == 'Limit' then
			table.insert(currentOrders, {
				Id = args.orderId,
				Quantity = tostring(args.quantity),
				OriginalQuantity = tostring(args.quantity),
				Creator = args.sender,
				Token = currentToken,
				DateCreated = args.timestamp,
				Price = tostring(args.price),
			})

			local limitDataSuccess, limitData = pcall(function()
				return json.encode({
					Order = {
						Id = args.orderId,
						DominantToken = validPair[1],
						SwapToken = validPair[2],
						Sender = args.sender,
						Receiver = nil,
						Quantity = tostring(args.quantity),
						Price = tostring(args.price),
						Timestamp = args.timestamp
					}
				})
			end)

			ao.send({
				Target = ACTIVITY_PROCESS,
				Action = 'Update-Listed-Orders',
				Data = limitDataSuccess and limitData or ''
			})

			ao.send({
				Target = args.sender,
				Action = 'Order-Success',
				Tags = {
					Status = 'Success',
					OrderId = args.orderId,
					Handler = 'Create-Order',
					DominantToken = currentToken,
					SwapToken = args.swapToken,
					Quantity = tostring(args.quantity),
					Price = tostring(args.price),
					Message = 'Order created successfully!',
					['X-Group-ID'] = args.orderGroupId
				}
			})

			return
		end

		-- Log
		-- print('Order type: ' .. orderType)
		-- print('Match ID: ' .. args.orderId)
		-- print('Swap token: ' .. args.swapToken)
		-- print('Order recipient: ' .. args.sender)
		-- print('Input quantity: ' .. tostring(remainingQuantity))

		for _, currentOrderEntry in ipairs(currentOrders) do
			if remainingQuantity > bint(0) and bint(currentOrderEntry.Quantity) > bint(0) then
				local fillAmount, sendAmount

				local transferDenomination = args.transferDenomination and bint(args.transferDenomination) > bint(1)

				-- Calculate how many shares can be bought with the remaining quantity
				if transferDenomination then
					fillAmount = remainingQuantity // bint(currentOrderEntry.Price)
				else
					fillAmount = math.floor(remainingQuantity / bint(currentOrderEntry.Price))
				end

				-- Calculate the total cost for the fill amount
				sendAmount = fillAmount * bint(currentOrderEntry.Price)

				-- Adjust the fill amount to not exceed the order's available quantity
				local quantityCheck = bint(currentOrderEntry.Quantity)
				if transferDenomination then
					quantityCheck = quantityCheck // bint(args.transferDenomination)
				end

				if sendAmount > (quantityCheck * bint(currentOrderEntry.Price)) then
					sendAmount = bint(currentOrderEntry.Quantity) * bint(currentOrderEntry.Price)
					if transferDenomination then
						sendAmount = sendAmount // bint(args.transferDenomination)
					end
				end

				-- Handle tokens with a denominated value
				if transferDenomination then
					if fillAmount > bint(0) then fillAmount = fillAmount * bint(args.transferDenomination) end
				end

				-- Ensure the fill amount does not exceed the available quantity in the order
				if fillAmount > bint(currentOrderEntry.Quantity) then
					fillAmount = bint(currentOrderEntry.Quantity)
				end

				-- Subtract the used quantity from the buyer's remaining quantity
				if transferDenomination then
					remainingQuantity = remainingQuantity -
						(fillAmount // bint(args.transferDenomination) * bint(currentOrderEntry.Price))
				else
					remainingQuantity = remainingQuantity - fillAmount * bint(currentOrderEntry.Price)
				end

				currentOrderEntry.Quantity = tostring(bint(currentOrderEntry.Quantity) - fillAmount)

				if fillAmount <= bint(0) then
					handleError({
						Target = args.sender,
						Action = 'Order-Error',
						Message = 'No amount to fill',
						Quantity = args.quantity,
						TransferToken = currentToken,
						OrderGroupId = args.orderGroupId
					})
					return
				end

				local calculatedSendAmount = utils.calculateSendAmount(sendAmount)
				local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

				-- Gather all fulfillment fees for buyback
				table.insert(BuybackCaptures, utils.calculateFeeAmount(sendAmount))

				-- Log
				-- print('Order creator: ' .. currentOrderEntry.Creator)
				-- print('Fill amount (to buyer): ' .. tostring(fillAmount))
				-- print('Send amount (to seller): ' .. tostring(calculatedSendAmount) .. ' (0.5% fee captured)')
				-- print('Remaining fill quantity (purchase amount): ' .. tostring(remainingQuantity))
				-- print('Remaining order quantity (listing): ' .. tostring(currentOrderEntry.Quantity) .. '\n')

				-- Send tokens to the current order creator
				ao.send({
					Target = currentToken,
					Action = 'Transfer',
					Tags = {
						Recipient = currentOrderEntry.Creator,
						Quantity = tostring(calculatedSendAmount)
					}
				})

				-- Send swap tokens to the input order creator
				ao.send({
					Target = args.swapToken,
					Action = 'Transfer',
					Tags = {
						Recipient = args.sender,
						Quantity = tostring(calculatedFillAmount)
					}
				})

				-- Record the match
				table.insert(matches, {
					Id = currentOrderEntry.Id,
					Quantity = calculatedFillAmount,
					Price = tostring(currentOrderEntry.Price)
				})

				local matchedDataSuccess, matchedData = pcall(function()
					return json.encode({
						Order = {
							Id = currentOrderEntry.Id,
							MatchId = args.orderId,
							DominantToken = validPair[2],
							SwapToken = validPair[1],
							Sender = currentOrderEntry.Creator,
							Receiver = args.sender,
							Quantity = calculatedFillAmount,
							Price = tostring(currentOrderEntry.Price),
							Timestamp = args.timestamp
						}
					})
				end)

				ao.send({
					Target = ACTIVITY_PROCESS,
					Action = 'Update-Executed-Orders',
					Data = matchedDataSuccess and matchedData or ''
				})

				-- Calculate streaks
				ao.send({
					Target = PIXL_PROCESS,
					Action = 'Calculate-Streak',
					Tags = {
						Buyer = args.sender
					}
				})

				-- If there are remaining shares in the current order, keep it in the order book
				if bint(currentOrderEntry.Quantity) > bint(0) then
					table.insert(updatedOrderbook, currentOrderEntry)
				end
			else
				if bint(currentOrderEntry.Quantity) > bint(0) then
					table.insert(updatedOrderbook, currentOrderEntry)
				end
			end
		end

		-- Execute PIXL buyback
		if orderType == 'Market' and #BuybackCaptures > 0 and currentToken == DEFAULT_SWAP_TOKEN and args.sender ~= ao.id then
			ucm.executeBuyback({
				orderId = args.orderId,
				blockheight = args.blockheight,
				timestamp = args.timestamp
			})
		end

		-- Update the order book with remaining and new orders
		Orderbook[pairIndex].Orders = updatedOrderbook

		local sumVolumePrice, sumVolume = 0, 0
		if #matches > 0 then
			for _, match in ipairs(matches) do
				local volume = bint(match.Quantity)
				local price = bint(match.Price)
				sumVolumePrice = sumVolumePrice + (volume * price)
				sumVolume = sumVolume + volume
			end

			local vwap = sumVolumePrice / sumVolume
			Orderbook[pairIndex].PriceData = {
				Vwap = tostring(math.floor(vwap)),
				Block = tostring(args.blockheight),
				DominantToken = currentToken,
				MatchLogs = matches
			}
		end

		Send({ device = 'patch@1.0', [orderbooks[args.dominantToken .. '/' .. args.swapToken]] = json.encode(Orderbook[pairIndex]) })

		if sumVolume > 0 then
			ao.send({
				Target = args.sender,
				Action = 'Order-Success',
				Tags = {
					OrderId = args.orderId,
					Status = 'Success',
					Handler = 'Create-Order',
					DominantToken = currentToken,
					SwapToken = args.swapToken,
					Quantity = tostring(sumVolume),
					Price = args.price and tostring(args.price) or 'None',
					Message = 'Order created successfully!',
					['X-Group-ID'] = args.orderGroupId or 'None'
				}
			})
		else
			handleError({
				Target = args.sender,
				Action = 'Order-Error',
				Message = 'No amount to fill',
				Quantity = args.quantity,
				TransferToken = currentToken,
				OrderGroupId = args.orderGroupId
			})
			return
		end
	else
		handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Pair not found',
			Quantity = args.quantity,
			TransferToken = currentToken,
			OrderGroupId = args.orderGroupId
		})
	end
end

function ucm.executeBuyback(args)
	local pixlDenomination = 1000000
	local pixlPairIndex = ucm.getPairIndex({ DEFAULT_SWAP_TOKEN, PIXL_PROCESS })

	if pixlPairIndex > -1 then
		local pixlOrderbook = Orderbook[pixlPairIndex].Orders

		if pixlOrderbook and #pixlOrderbook > 0 then
			table.sort(pixlOrderbook, function(a, b)
				local priceA = bint(a.Price)
				local priceB = bint(b.Price)
				if priceA == priceB then
					local quantityA = bint(a.Quantity)
					local quantityB = bint(b.Quantity)
					return quantityA < quantityB
				end
				return priceA < priceB
			end)

			local buybackAmount = bint(0)

			for _, quantity in ipairs(BuybackCaptures) do
				buybackAmount = buybackAmount + bint(quantity)
			end

			local minQuantity = bint(pixlOrderbook[1].Price)
			local maxQuantity = bint(0)

			for _, order in ipairs(pixlOrderbook) do
				maxQuantity = maxQuantity + ((bint(order.Quantity) // bint(pixlDenomination)) *
					bint(order.Price))
			end

			if buybackAmount < minQuantity then
				return
			end

			if buybackAmount > maxQuantity then
				buybackAmount = maxQuantity
			end

			ucm.createOrder({
				orderId = args.orderId,
				dominantToken = DEFAULT_SWAP_TOKEN,
				swapToken = PIXL_PROCESS,
				sender = ao.id,
				quantity = tostring(buybackAmount),
				timestamp = args.timestamp,
				blockheight = args.blockheight,
				transferDenomination = tostring(pixlDenomination)
			})

			BuybackCaptures = {}
		end
	end
end

return ucm
