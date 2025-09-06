local bint = require('.bint')(256)
local json = require('json')

local utils = require('utils')

local fixed_price = {}

-- Helper function to update VWAP data
local function updateVwapData(pairIndex, matches, args, currentToken)
	local sumVolumePrice, sumVolume = 0, 0
	if #matches > 0 then
		for _, match in ipairs(matches) do
			local volume = bint(match.Quantity)
			local price = bint(match.Price)
			sumVolumePrice = sumVolumePrice + (volume * price)
			sumVolume = sumVolume + volume
		end

		-- Calculate and store VWAP
		local vwap = sumVolumePrice / sumVolume
		Orderbook[pairIndex].PriceData = {
			Vwap = tostring(math.floor(vwap)),
			Block = tostring(args.blockheight),
			DominantToken = currentToken,
			MatchLogs = matches
		}
	end

	return sumVolume
end
-- Helper function to handle ARIO token orders: we are selling ANT token, so we need to add to orderbook
function fixed_price.handleArioOrder(args, validPair, pairIndex)
	-- Add the new order to the orderbook (buy now functionality)
	table.insert(Orderbook[pairIndex].Orders, {
		Id = args.orderId,
		Quantity = tostring(args.quantity),
		OriginalQuantity = tostring(args.quantity),
		Creator = args.sender,
		Token = args.dominantToken,
		DateCreated = args.createdAt,
		Price = args.price and tostring(args.price),
		ExpirationTime = args.expirationTime,
		OrderType = 'fixed',
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
				CreatedAt = args.createdAt,
				OrderType = 'fixed',
				Domain = args.domain,
				ExpirationTime = args.expirationTime,
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
			Message = 'ARIO order added to orderbook for buy now!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = 'fixed',
			Domain = args.domain,
			ExpirationTime = args.expirationTime,
			OwnershipType = args.ownershipType,
			LeaseStartTimestamp = args.leaseStartTimestamp,
			LeaseEndTimestamp = args.leaseEndTimestamp
		}
	})
end

-- Helper function to handle ANT token orders: we are buying ANT token, so we need to match with an existing ANT sell order or fail
function fixed_price.handleAntOrder(args, validPair, pairIndex)
	local currentOrders = Orderbook[pairIndex].Orders
	local matches = {}
	local matchedOrderIndex = nil

	-- Attempt to match with existing orders for immediate trade
	for i, currentOrderEntry in ipairs(currentOrders) do
		-- Check if order has expired
		if currentOrderEntry.ExpirationTime and bint(currentOrderEntry.ExpirationTime) < bint(args.createdAt) then
			-- Skip expired orders
			goto continue
		end

		-- Check if the order is a fixed order
		if currentOrderEntry.OrderType ~= 'fixed' then
			goto continue
		end

		-- Check if this is the specific order we're looking for
		if currentOrderEntry.Id ~= args.requestedOrderId then
			goto continue
		end

		-- Check if we can still fill and the order has remaining quantity
		if bint(args.quantity) > bint(0) and bint(currentOrderEntry.Quantity) > bint(0) then
			-- For ANT tokens, only allow complete trades - no partial amounts
			local fillAmount, sendAmount

			-- Accept sent amount >= listed price; refund any excess
			local requiredAmount = bint(currentOrderEntry.Price)
			local sentAmount = bint(args.quantity)
			if sentAmount >= requiredAmount then
				-- User buys 1 ANT token
				fillAmount = bint(1) -- always 1 for ANT orders

				-- Validate we have a valid fill amount
				if fillAmount <= bint(0) then
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

				-- Apply fees and calculate final amounts based on required amount
				local calculatedSendAmount = utils.calculateSendAmount(requiredAmount)
				local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

				-- Execute token transfers
				utils.executeTokenTransfers(args, currentOrderEntry, validPair, calculatedSendAmount, calculatedFillAmount)

				-- Refund any excess ARIO sent over the required amount
				if sentAmount > requiredAmount then
					local refundAmount = sentAmount - requiredAmount
					ao.send({
						Target = args.dominantToken,
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
			-- If ARIO amount is less than price, skip and continue searching
		end

		::continue::
	end

	-- Remove the matched order from the orderbook
	if matchedOrderIndex then
		table.remove(Orderbook[pairIndex].Orders, matchedOrderIndex)
	end

	-- Update VWAP and get total volume
	local sumVolume = updateVwapData(pairIndex, matches, args, args.dominantToken)

	-- Send success response if any matches occurred
	if sumVolume > 0 then
		ao.send({
			Target = args.sender,
			Action = 'Order-Success',
			Tags = {
				OrderId = args.orderId,
				Status = 'Success',
				Handler = 'Create-Order',
				DominantToken = args.dominantToken,
				SwapToken = args.swapToken,
				Quantity = tostring(sumVolume),
				Price = args.price and tostring(args.price) or 'None',
				Message = 'ANT order executed immediately!',
				['X-Group-ID'] = args.orderGroupId or 'None'
			}
		})
	else
		-- No matches found for ANT token - return error
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'No matching orders found for immediate ANT trade - exact ARIO amount match required',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId
		})
		return
	end
end

return fixed_price
