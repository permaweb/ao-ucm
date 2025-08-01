local utils = require('utils')
local bint = require('.bint')(256)
local json = require('json')

local dutch_auction = {}

function dutch_auction.handleArioOrder(args, validPair, pairIndex)
    local intervals = (bint(args.expirationTime) - bint(args.timestamp)) / bint(args.decreaseInterval)
    local priceDecreaseMax = bint(args.price) - bint(args.minimumPrice)
    local decreaseStep = math.floor(priceDecreaseMax / intervals)

    table.insert(Orderbook[pairIndex].Orders, {
		Id = args.orderId,
		Quantity = tostring(args.quantity),
		OriginalQuantity = tostring(args.quantity),
		Creator = args.sender,
		Token = validPair[1],
		DateCreated = args.timestamp,
		Price = args.price and tostring(args.price),
		ExpirationTime = args.expirationTime and tostring(args.expirationTime) or nil,
        Type = 'dutch',
        MinimumPrice = args.minimumPrice and tostring(args.minimumPrice),
        DecreaseInterval = args.decreaseInterval and tostring(args.decreaseInterval),
        DecreaseStep = tostring(decreaseStep)
	})

    	-- Send order data to activity tracking process
	local limitDataSuccess, limitData = pcall(function()
		return json.encode({
			Order = {
				Id = args.orderId,
				DominantToken = validPair[1],
				SwapToken = validPair[2],
				Sender = args.sender,
				Receiver = nil,
				Quantity = tostring(args.quantity),
				Price = args.price and tostring(args.price),
				Timestamp = args.timestamp,
				OrderType = 'dutch',
				MinimumPrice = args.minimumPrice and tostring(args.minimumPrice),
				DecreaseInterval = args.decreaseInterval and tostring(args.decreaseInterval),
				DecreaseStep = tostring(decreaseStep)
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
			DominantToken = validPair[1],
			SwapToken = args.swapToken,
			Quantity = tostring(args.quantity),
			Price = args.price and tostring(args.price),
			Message = 'ARIO order added to orderbook for Dutch auction!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = 'dutch'
		}
	})
end

function dutch_auction.handleAntOrder(args, validPair, pairIndex)
	local currentOrders = Orderbook[pairIndex].Orders
	local matches = {}
	local matchedOrderIndex = nil

	-- Attempt to match with existing Dutch orders for immediate trade
	for i, currentOrderEntry in ipairs(currentOrders) do
		-- Check if order has expired
		if currentOrderEntry.ExpirationTime and bint(currentOrderEntry.ExpirationTime) < bint(args.timestamp) then
			-- Skip expired orders
			goto continue
		end

		-- Check if the order is a Dutch auction order
		if currentOrderEntry.Type ~= 'dutch' then
			goto continue
		end
		
		-- Check if we can still fill and the order has remaining quantity
		if bint(args.quantity) > bint(0) and bint(currentOrderEntry.Quantity) > bint(0) then
			-- For ANT tokens, only allow complete trades - no partial amounts
			local fillAmount, sendAmount

			-- Check if the order quantity matches exactly what we want to buy
			if bint(currentOrderEntry.Quantity) == bint(args.quantity) then
				-- Calculate current price based on time passed since order creation
				local timePassed = bint(args.timestamp) - bint(currentOrderEntry.DateCreated)
				local intervalsPassed = math.floor(timePassed / bint(currentOrderEntry.DecreaseInterval))
				local priceReduction = intervalsPassed * bint(currentOrderEntry.DecreaseStep)
				local currentPrice = bint(currentOrderEntry.Price) - priceReduction
				
				-- Ensure price doesn't go below minimum
				if currentPrice < bint(currentOrderEntry.MinimumPrice) then
					currentPrice = bint(currentOrderEntry.MinimumPrice)
				end

				fillAmount = bint(args.quantity)
				sendAmount = fillAmount * currentPrice

				-- Validate we have a valid fill amount
				if fillAmount <= bint(0) then
					utils.handleError({
						Target = args.sender,
						Action = 'Order-Error',
						Message = 'No amount to fill',
						Quantity = args.quantity,
						TransferToken = validPair[1],
						OrderGroupId = args.orderGroupId
					})
					return
				end

				-- Check if sent amount is sufficient for current price
				local sentAmount = bint(args.price or 0)
				if sentAmount < sendAmount then
					utils.handleError({
						Target = args.sender,
						Action = 'Order-Error',
						Message = 'Insufficient payment for current Dutch auction price',
						Quantity = args.price, -- Refund the ARIO amount that was sent
						TransferToken = args.swapToken, -- Send to ARIO token process
						OrderGroupId = args.orderGroupId,
						RequiredAmount = tostring(sendAmount),
						SentAmount = tostring(sentAmount)
					})
					return
				end

				-- Apply fees and calculate final amounts
				local calculatedSendAmount = utils.calculateSendAmount(sendAmount)
				local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

				-- Execute token transfers
				utils.executeTokenTransfers(args, currentOrderEntry, validPair, calculatedSendAmount, calculatedFillAmount)

				-- Handle refund if sent amount was more than required
				if sentAmount > sendAmount then
					local refundAmount = sentAmount - sendAmount
					ao.send({
						Target = args.swapToken, -- ARIO token process
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
			-- If quantities don't match exactly, skip this order and continue searching
		end
		
		::continue::
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
				DominantToken = validPair[1],
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
			TransferToken = validPair[1],
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

    return true
end

return dutch_auction