local bint = require('.bint')(256)
local json = require('json')

local utils = require('utils')

if Name ~= 'ANT Marketplace' then Name = 'ANT Marketplace' end

-- CHANGEME
ACTIVITY_PROCESS = '7_psKu3QHwzc2PFCJk2lEwyitLJbz6Vj7hOcltOulj4'

-- Orderbook {
-- 	Pair [TokenId, TokenId],
-- 	Orders {
-- 		Id,
-- 		Creator,
-- 		Quantity,
-- 		OriginalQuantity,
-- 		Token,
-- 		DateCreated,
-- 		Price
-- 		ExpirationTime
-- 	} []
-- } []

if not Orderbook then Orderbook = {} end

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

-- Helper function to validate order parameters
local function validateOrderParams(args)
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
		return nil
	end

	-- Ensure ARIO token is involved in the trade (marketplace requirement)
	local isArioValid, arioError = utils.validateArioInTrade(args.dominantToken, args.swapToken)
	if not isArioValid then
		handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = arioError or 'Invalid trade - ARIO must be involved',
			Quantity = args.quantity,
			TransferToken = nil,
			OrderGroupId = args.orderGroupId
		})
		return nil
	end

	-- Validate quantity is positive integer
	if not utils.checkValidAmount(args.quantity) then
		handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Quantity must be an integer greater than zero',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return nil
	end

	-- Validate ANT token quantity must be exactly 1 when selling ANT
	if not utils.isArioToken(args.dominantToken) and args.quantity ~= 1 then
		handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'ANT tokens can only be sold in quantities of exactly 1',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return nil
	end

	-- Validate orderType is supported
	if not args.orderType or args.orderType ~= "fixed" then
		handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Order type must be "fixed"',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return nil
	end

	-- Validate expiration time only when selling ANT (not when buying ANT with ARIO)
	if not utils.isArioToken(args.dominantToken) then
		-- Expiration time is required when selling ANT
		if not args.expirationTime then
			handleError({
				Target = args.sender,
				Action = 'Validation-Error',
				Message = 'Expiration time is required when selling ANT tokens',
				Quantity = args.quantity,
				TransferToken = validPair[1],
				OrderGroupId = args.orderGroupId
			})
			return nil
		end

		if not args.price then
			handleError({
				Target = args.sender,
				Action = 'Validation-Error',
				Message = 'Price is required when selling ANT tokens',
				Quantity = args.quantity,
				TransferToken = validPair[1],
				OrderGroupId = args.orderGroupId
			})
			return nil
		end
		
		-- Validate expiration time is valid
		local isValidExpiration, expirationError = utils.checkValidExpirationTime(args.expirationTime, args.timestamp)
		if not isValidExpiration then
			handleError({
				Target = args.sender,
				Action = 'Validation-Error',
				Message = expirationError,
				Quantity = args.quantity,
				TransferToken = validPair[1],
				OrderGroupId = args.orderGroupId
			})
			return nil
		end

		local isValidPrice, priceError = utils.checkValidAmount(args.price)
		if not isValidPrice then
			handleError({
				Target = args.sender,
				Action = 'Validation-Error',
				Message = priceError,
				Quantity = args.quantity,
				TransferToken = validPair[1],
				OrderGroupId = args.orderGroupId
			})
			return nil
		end
	
	end

	return validPair
end

-- Helper function to ensure trading pair exists in orderbook
local function ensurePairExists(validPair)
	local pairIndex = ucm.getPairIndex(validPair)

	-- Create new pair entry if it doesn't exist
	if pairIndex == -1 then
		table.insert(Orderbook, { Pair = validPair, Orders = {} })
		pairIndex = ucm.getPairIndex(validPair)
	end

	return pairIndex
end

-- Helper function to handle ARIO token orders: we are selling ANT token, so we need to add to orderbook
local function handleArioOrder(args, validPair, pairIndex)
	-- Check if this ANT token is already being sold (prevent duplicate ANT sell orders)
	if not utils.isArioToken(args.dominantToken) then
		local currentOrders = Orderbook[pairIndex].Orders
		for _, existingOrder in ipairs(currentOrders) do
			if existingOrder.Token == args.dominantToken then
				handleError({
					Target = args.sender,
					Action = 'Validation-Error',
					Message = 'This ANT token is already being sold - cannot create duplicate sell order',
					Quantity = args.quantity,
					TransferToken = validPair[1],
					OrderGroupId = args.orderGroupId
				})
				return
			end
		end
	end

	-- Add the new order to the orderbook (buy now functionality)
	table.insert(Orderbook[pairIndex].Orders, {
		Id = args.orderId,
		Quantity = tostring(args.quantity),
		OriginalQuantity = tostring(args.quantity),
		Creator = args.sender,
		Token = validPair[1],
		DateCreated = args.timestamp,
		Price = args.price and tostring(args.price),
		ExpirationTime = args.expirationTime and tostring(args.expirationTime) or nil
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
				Timestamp = args.timestamp
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
			Message = 'ARIO order added to orderbook for buy now!',
			['X-Group-ID'] = args.orderGroupId
		}
	})
end

-- Helper function to execute token transfers
local function executeTokenTransfers(args, currentOrderEntry, validPair, calculatedSendAmount, calculatedFillAmount)
	-- Transfer tokens to the seller (order creator)
	ao.send({
		Target = validPair[1],
		Action = 'Transfer',
		Tags = {
			Recipient = currentOrderEntry.Creator,
			Quantity = tostring(calculatedSendAmount)
		}
	})

	-- Transfer swap tokens to the buyer (order sender)
	ao.send({
		Target = args.swapToken,
		Action = 'Transfer',
		Tags = {
			Recipient = args.sender,
			Quantity = tostring(calculatedFillAmount)
		}
	})
end

-- Helper function to record match and send activity data
local function recordMatch(args, currentOrderEntry, validPair, calculatedFillAmount)
	-- Record the successful match
	local match = {
		Id = currentOrderEntry.Id,
		Quantity = calculatedFillAmount,
		Price = tostring(currentOrderEntry.Price)
	}

	-- Send match data to activity tracking
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

	return match
end

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

-- Helper function to handle ANT token orders: we are buying ANT token, so we need to match with an existing ANT sell order or fail
local function handleAntOrder(args, validPair, pairIndex)
	local currentOrders = Orderbook[pairIndex].Orders
	local matches = {}
	local matchedOrderIndex = nil

	-- Attempt to match with existing orders for immediate trade
	for i, currentOrderEntry in ipairs(currentOrders) do
		-- Check if order has expired
		if currentOrderEntry.ExpirationTime and bint(currentOrderEntry.ExpirationTime) < bint(args.timestamp) then
			-- Skip expired orders
			goto continue
		end
		
		-- Check if we can still fill and the order has remaining quantity
		if bint(args.quantity) > bint(0) and bint(currentOrderEntry.Quantity) > bint(0) then
			-- For ANT tokens, only allow complete trades - no partial amounts
			local fillAmount, sendAmount

			-- Check if the order quantity matches exactly what we want to buy
			if bint(currentOrderEntry.Quantity) == bint(args.quantity) then
				fillAmount = bint(args.quantity)
				sendAmount = fillAmount * bint(currentOrderEntry.Price)

				-- Validate we have a valid fill amount
				if fillAmount <= bint(0) then
					handleError({
						Target = args.sender,
						Action = 'Order-Error',
						Message = 'No amount to fill',
						Quantity = args.quantity,
						TransferToken = validPair[1],
						OrderGroupId = args.orderGroupId
					})
					return
				end

				-- Apply fees and calculate final amounts
				local calculatedSendAmount = utils.calculateSendAmount(sendAmount)
				local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

				-- Execute token transfers
				executeTokenTransfers(args, currentOrderEntry, validPair, calculatedSendAmount, calculatedFillAmount)

				-- Record the match
				local match = recordMatch(args, currentOrderEntry, validPair, calculatedFillAmount)
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

	-- Update VWAP and get total volume
	local sumVolume = updateVwapData(pairIndex, matches, args, validPair[1])

	-- Send success response if any matches occurred
	if sumVolume > 0 then
		ao.send({
			Target = args.sender,
			Action = 'Order-Success',
			Tags = {
				OrderId = args.orderId,
				Status = 'Success',
				Handler = 'Create-Order',
				DominantToken = validPair[1],
				SwapToken = args.swapToken,
				Quantity = tostring(sumVolume),
				Price = args.price and tostring(args.price) or 'None',
				Message = 'ANT order executed immediately!',
				['X-Group-ID'] = args.orderGroupId or 'None'
			}
		})
	else
		-- No matches found for ANT token - return error
		handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'No matching orders found for immediate ANT trade - exact quantity match required',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return
	end
end

function ucm.createOrder(args)
	-- Validate order parameters
	-- TODO: Order type is added, but not used yet - add it's usage with a new order type
	local validPair = validateOrderParams(args)
	if not validPair then
		return
	end

	-- Ensure trading pair exists in orderbook
	local pairIndex = ensurePairExists(validPair)

	if pairIndex > -1 then
		-- Check if the desired token is ARIO (add to orderbook) or ANT (immediate trade only)
		local isBuyingAnt = utils.isArioToken(args.dominantToken) -- If dominantToken is ARIO, we're buying ANT
		local isBuyingArio = not isBuyingAnt -- If dominantToken is not ARIO, we're selling ANT

		-- Handle ANT token orders - check for immediate trades only, don't add to orderbook
		if isBuyingAnt then
			handleAntOrder(args, validPair, pairIndex)
			return
		end

		-- Handle ARIO token orders - add to orderbook for buy now
		if isBuyingArio then
			handleArioOrder(args, validPair, pairIndex)
			return
		end

		-- Placeholder for future order type handling
		handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Order type not implemented yet',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return

	else
		-- Pair not found in orderbook (shouldn't happen after creation)
		handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Pair not found',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
	end
end

return ucm
