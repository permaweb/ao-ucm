local utils = require('utils')
local bint = require('.bint')(256)
local json = require('JSON')

local dutch_auction = {}

function dutch_auction.calculateDecreaseStep(args)
	local intervalsCount = (bint(args.expirationTime) - bint(args.createdAt)) / bint(args.decreaseInterval)
	local priceDecreaseMax = bint(args.price) - bint(args.minimumPrice)
	return math.floor(priceDecreaseMax / intervalsCount)
end

function dutch_auction.handleArioOrder(args, validPair, pairIndex)
	local decreaseStep = dutch_auction.calculateDecreaseStep(args)

	table.insert(Orderbook[pairIndex].Orders, {
		Id = args.orderId,
		Quantity = tostring(args.quantity),
		OriginalQuantity = tostring(args.quantity),
		Creator = args.sender,
		Token = args.dominantToken,
		DateCreated = args.createdAt,
		Price = args.price and tostring(args.price),
		ExpirationTime = args.expirationTime and tostring(args.expirationTime) or nil,
		Type = 'dutch',
		MinimumPrice = args.minimumPrice and tostring(args.minimumPrice),
		DecreaseInterval = args.decreaseInterval and tostring(args.decreaseInterval),
		DecreaseStep = tostring(decreaseStep),
		Domain = args.domain,
		OwnershipType = args.ownershipType,
		LeaseStartTimestamp = args.leaseStartTimestamp,
		LeaseEndTimestamp = args.leaseEndTimestamp
	})

	-- Send order data to activity tracking process
	local limitDataSuccess, limitData = pcall(function()
		return json.encode({
			Order = {
				Id = args.orderId,
				DominantToken = args.dominantToken,
				SwapToken = args.swapToken,
				Sender = args.sender,
				Receiver = nil,
				Quantity = tostring(args.quantity),
				Price = args.price and tostring(args.price),
				ExpirationTime = args.expirationTime and tostring(args.expirationTime) or nil,
				CreatedAt = args.createdAt,
				OrderType = 'dutch',
				MinimumPrice = args.minimumPrice and tostring(args.minimumPrice),
				DecreaseInterval = args.decreaseInterval and tostring(args.decreaseInterval),
				DecreaseStep = tostring(decreaseStep),
				Domain = args.domain,
				OwnershipType = args.ownershipType,
				LeaseStartTimestamp = args.leaseStartTimestamp,
				LeaseEndTimestamp = args.leaseEndTimestamp
			}
		})
	end)

	ao.send({
		Target = ACTIVITY_PROCESS,
		Action = 'Update-Listed-Orders',
		Data = limitDataSuccess and limitData or ''
	})

	-- Notify sender of successful order creation
	ao.send({
		Target = args.sender,
		Action = 'Order-Success',
		Tags = {
			Status = 'Success',
			OrderId = args.orderId,
			Handler = 'Create-Order',
			DominantToken = args.dominantToken,
			SwapToken = args.swapToken,
			Quantity = tostring(args.quantity),
			Price = args.price and tostring(args.price),
			Message = 'ARIO order added to orderbook for Dutch auction!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = 'dutch',
			Domain = args.domain,
			OwnershipType = args.ownershipType,
			LeaseStartTimestamp = args.leaseStartTimestamp,
			LeaseEndTimestamp = args.leaseEndTimestamp
		}
	})
end

function dutch_auction.handleAntOrder(args, validPair, pairIndex)
	print("handleAntOrder")
	local currentOrders = Orderbook[pairIndex].Orders
	local matches = {}
	local matchedOrderIndex = nil

	-- Attempt to match with existing Dutch orders for immediate trade
	for i, currentOrderEntry in ipairs(currentOrders) do
		-- Check if order has expired
		if currentOrderEntry.ExpirationTime and bint(currentOrderEntry.ExpirationTime) < bint(args.createdAt) then
			-- Skip expired orders
			goto continue
		end

		-- Check if the order is a Dutch auction order
		if currentOrderEntry.Type ~= 'dutch' then
			goto continue
		end

		-- Check if this is the specific order we're looking for
		if currentOrderEntry.Id ~= args.requestedOrderId then
			goto continue
		end

		print("CP1")
		-- Calculate current price based on time passed since order creation
		local timePassed = bint(args.createdAt) - bint(currentOrderEntry.DateCreated)
		print("timePassed", timePassed)
		local intervalsPassed = math.floor(timePassed / bint(currentOrderEntry.DecreaseInterval))
		local intervalsBint = bint(intervalsPassed)
		local decreaseStepBint = bint(currentOrderEntry.DecreaseStep)
		local priceReduction = intervalsBint * decreaseStepBint
		local currentPrice = (currentOrderEntry.Price) - priceReduction
		print("CP2")
		-- Ensure price doesn't go below minimum
		if currentPrice < bint(currentOrderEntry.MinimumPrice) then
			currentPrice = bint(currentOrderEntry.MinimumPrice)
		end
		print("CP3")

		-- Check if the user sent enough ARIO to pay for 1 ANT token at the current Dutch auction price
		if bint(args.quantity) >= currentPrice then
			local fillAmount = bint(1) -- 1 ANT token (always 1 for ANT orders)
			print("CP4")
			-- Validate we have a valid fill amount
			if fillAmount <= bint(0) then
				print("CP5")
				utils.handleError({
					Target = args.sender,
					Action = 'Order-Error',
					Message = 'No amount to fill',
					Quantity = args.quantity,
					TransferToken = args.dominantToken,
					OrderGroupId = args.orderGroupId
				})
				return
			end

			-- Check if sent amount is sufficient for current price

			local requiredAmount = currentPrice
			local sentAmount = bint(args.quantity) -- User pays the current Dutch auction price

			if sentAmount < requiredAmount then
				utils.handleError({
					Target = args.sender,
					Action = 'Order-Error',
					Message = 'Insufficient payment for current Dutch auction price',
					Quantity = args.quantity, -- Refund the ARIO amount that was sent
					TransferToken = args.dominantToken, -- Send to ARIO token process (dominantToken)
					OrderGroupId = args.orderGroupId,
					RequiredAmount = tostring(requiredAmount),
					SentAmount = tostring(sentAmount)
				})
				return
			end

			-- Apply fees and calculate final amounts
			local calculatedSendAmount = utils.calculateSendAmount(requiredAmount)
			local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

			-- Execute token transfers
			utils.executeTokenTransfers(args, currentOrderEntry, validPair, calculatedSendAmount, calculatedFillAmount)

			-- Handle refund if sent amount was more than required
			if sentAmount > requiredAmount then
				local refundAmount = sentAmount - requiredAmount
				ao.send({
					Target = args.dominantToken, -- ARIO token process (dominantToken)
					Action = 'Transfer',
					Tags = {
						Recipient = args.sender,
						Quantity = tostring(refundAmount)
					}
				})
			end

			-- Record the match
			local match = utils.recordMatch(args, currentOrderEntry, validPair, calculatedFillAmount)
			table.insert(matches, match)

			-- Mark the order index for removal
			matchedOrderIndex = i
			break -- Only match with one order, no partial matching
		end

		:: continue ::
	end

	-- Remove the matched order from the orderbook
	if matchedOrderIndex then
		table.remove(Orderbook[pairIndex].Orders, matchedOrderIndex)
	end

	-- Send success response if any matches occurred
	if #matches > 0 then
		ao.send({
			Target = args.sender,
			Action = 'Order-Success',
			Tags = {
				OrderId = args.orderId,
				Status = 'Success',
				Handler = 'Create-Order',
				DominantToken = args.dominantToken,
				SwapToken = args.swapToken,
				Quantity = tostring(args.quantity),
				Price = args.price and tostring(args.price) or 'None',
				Message = 'ANT order executed immediately in Dutch auction!',
				['X-Group-ID'] = args.orderGroupId or 'None',
				OrderType = 'dutch'
			}
		})
	else
		-- No matches found for ANT token - return error
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'No matching Dutch auction orders found for immediate ANT trade - exact quantity match required',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId
		})
		return
	end
end

function dutch_auction.validateDutchParams(args)
	if not args.minimumPrice then
		return false, 'Minimum price must be provided'
	end

	local isValidMinimumPrice, minimumPriceError = utils.checkValidAmount(args.minimumPrice)
	if not isValidMinimumPrice then
		return false, minimumPriceError
	end

	if not args.decreaseInterval then
		return false, 'Decrease interval must be provided'
	end

	local isValidDecreaseInterval, decreaseIntervalError = utils.checkValidAmount(args.decreaseInterval)
	if not isValidDecreaseInterval then
		return false, decreaseIntervalError
	end

	if bint(args.decreaseInterval) >= bint(args.expirationTime) then
		return false, 'Decrease interval must be less than expiration time'
	end

	local decreaseStep = dutch_auction.calculateDecreaseStep(args)

	if decreaseStep < 1 then
		return false, 'Decrease step must be at least 1. Price difference is too small for the given time intervals.'
	end

	return true
end

return dutch_auction