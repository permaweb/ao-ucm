local json = require('JSON')
local bint = require('.bint')(256)

if Name ~= 'ANT Marketplace' then Name = 'ANT Marketplace' end

-- CHANGEME
ACTIVITY_PROCESS = '7_psKu3QHwzc2PFCJk2lEwyitLJbz6Vj7hOcltOulj4'
ARIO_TOKEN_PROCESS_ID = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'

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
-- 		Type
-- 		MinimumPrice (dutch)
-- 		DecreaseInterval (dutch)
-- 		DecreaseStep (dutch)
-- 	} []
-- } []

if not Orderbook then Orderbook = {} end

local fixed_price = {}
local dutch_auction = {}
local english_auction = {}
local utils = {}
local ucm = {}

-- utils.lua
--------------------------------

function utils.checkValidAddress(address)
	if not address or type(address) ~= 'string' then
		return false
	end

	return string.match(address, '^[%w%-_]+$') ~= nil and #address == 43
end

function utils.checkValidAmount(data)
	return bint(data) > bint(0)
end

function utils.isArioToken(tokenAddress)
	return tokenAddress == ARIO_TOKEN_PROCESS_ID
end

function utils.validateArioSwapToken(tokenAddress)
	-- Allow ARIO tokens in both dominant and swap positions
	-- This enables both selling for ARIO and buying with ARIO
	return true, nil
end

function utils.validateArioInTrade(dominantToken, swapToken)
	-- At least one of the tokens in the trade must be ARIO
	if dominantToken == ARIO_TOKEN_PROCESS_ID or swapToken == ARIO_TOKEN_PROCESS_ID then
		return true, nil
	end
	return false, 'At least one token in the trade must be ARIO'
end

function utils.decodeMessageData(data)
	local status, decodedData = pcall(json.decode, data)

	if not status or type(decodedData) ~= 'table' then
		return false, nil
	end

	return true, decodedData
end

function utils.validatePairData(data)
	if type(data) ~= 'table' or #data ~= 2 then
		return nil, 'Pair must be a list of exactly two strings - [TokenId, TokenId]'
	end

	if type(data[1]) ~= 'string' or type(data[2]) ~= 'string' then
		return nil, 'Both pair elements must be strings'
	end

	if not utils.checkValidAddress(data[1]) or not utils.checkValidAddress(data[2]) then
		return nil, 'Both pair elements must be valid addresses'
	end

	if data[1] == data[2] then
		return nil, 'Pair addresses cannot be equal'
	end

	return data
end

function utils.calculateSendAmount(amount)
	local factor = bint(995)
	local divisor = bint(1000)
	local sendAmount = (bint(amount) * factor) // divisor
	return tostring(sendAmount)
end

function utils.calculateFeeAmount(amount)
	local factor = bint(5)
	local divisor = bint(10000)
	local feeAmount = (bint(amount) * factor) // divisor
	return tostring(feeAmount)
end

function utils.calculateFillAmount(amount)
	return tostring(math.floor(tostring(amount)))
end

function utils.printTable(t, indent)
	local jsonStr = ''
	local function serialize(tbl, indentLevel)
		local isArray = #tbl > 0
		local tab = isArray and '[\n' or '{\n'
		local sep = isArray and ',\n' or ',\n'
		local endTab = isArray and ']' or '}'
		indentLevel = indentLevel + 1

		for k, v in pairs(tbl) do
			tab = tab .. string.rep('  ', indentLevel)
			if not isArray then
				tab = tab .. '\'' .. tostring(k) .. '\': '
			end

			if type(v) == 'table' then
				tab = tab .. serialize(v, indentLevel) .. sep
			else
				if type(v) == 'string' then
					tab = tab .. '\'' .. tostring(v) .. '\'' .. sep
				else
					tab = tab .. tostring(v) .. sep
				end
			end
		end

		if tab:sub(-2) == sep then
			tab = tab:sub(1, -3) .. '\n'
		end

		indentLevel = indentLevel - 1
		tab = tab .. string.rep('  ', indentLevel) .. endTab
		return tab
	end

	jsonStr = serialize(t, indent or 0)
	print(jsonStr)
end

function utils.checkTables(t1, t2)
	if t1 == t2 then return true end
	if type(t1) ~= 'table' or type(t2) ~= 'table' then return false end
	for k, v in pairs(t1) do
		if not utils.checkTables(v, t2[k]) then return false end
	end
	for k in pairs(t2) do
		if t1[k] == nil then return false end
	end
	return true
end

local testResults = {
    total = 0,
    passed = 0,
    failed = 0,
}

function utils.test(description, fn, expected)
    local colors = {
        red = '\27[31m',
        green = '\27[32m',
        blue = '\27[34m',
        reset = '\27[0m',
    }

    testResults.total = testResults.total + 1
    local testIndex = testResults.total

    print('\n' .. colors.blue .. 'Running test ' .. testIndex .. '... ' .. description .. colors.reset)
    local status, result = pcall(fn)
    if not status then
        testResults.failed = testResults.failed + 1
        print(colors.red .. 'Failed - ' .. description .. ' - ' .. result .. colors.reset .. '\n')
    else
        if utils.checkTables(result, expected) then
            testResults.passed = testResults.passed + 1
            print(colors.green .. 'Passed - ' .. description .. colors.reset)
        else
            testResults.failed = testResults.failed + 1
            print(colors.red .. 'Failed - ' .. description .. colors.reset .. '\n')
            print(colors.red .. 'Expected' .. colors.reset)
            utils.printTable(expected)
            print('\n' .. colors.red .. 'Got' .. colors.reset)
            utils.printTable(result)
        end
    end
end

function utils.testSummary()
    local colors = {
        red = '\27[31m',
        green = '\27[32m',
        reset = '\27[0m',
    }

    print('\nTest Summary')
    print('Total tests (' .. testResults.total .. ')')
    print('Result: ' .. testResults.passed .. '/' .. testResults.total .. ' tests passed')
    if testResults.passed == testResults.total then
        print(colors.green .. 'All tests passed!' .. colors.reset)
    else
        print(colors.green .. 'Tests passed: ' .. testResults.passed .. '/' .. testResults.total .. colors.reset)
        print(colors.red .. 'Tests failed: ' .. testResults.failed .. '/' .. testResults.total .. colors.reset .. '\n')
    end
end

function utils.checkValidExpirationTime(expirationTime, timestamp)
	-- Check if expiration time is a valid positive integer
	expirationTime = tonumber(expirationTime)
	if not expirationTime or not utils.checkValidAmount(expirationTime) then
		return false, 'Expiration time must be a valid positive integer'
	end

	-- Check if expiration time is greater than current timestamp
	local status, result = pcall(function()
		return bint(expirationTime) <= bint(timestamp)
	end)

	if not status then
		return false, 'Expiration time must be a valid timestamp'
	end

	if result then
		return false, 'Expiration time must be greater than current timestamp'
	end

	return true, nil
end


function utils.handleError(args) -- Target, TransferToken, Quantity
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

-- Helper function to execute token transfers
function utils.executeTokenTransfers(args, currentOrderEntry, validPair, calculatedSendAmount, calculatedFillAmount)
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
function utils.recordMatch(args, currentOrderEntry, validPair, calculatedFillAmount)
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

-- fixed_price.lua
--------------------------------

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
		Token = validPair[1],
		DateCreated = args.timestamp,
		Price = args.price and tostring(args.price),
		ExpirationTime = args.expirationTime and tostring(args.expirationTime) or nil,
		Type = 'fixed'
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
			['X-Group-ID'] = args.orderGroupId,
			OrderType = 'fixed'
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
		if currentOrderEntry.ExpirationTime and bint(currentOrderEntry.ExpirationTime) < bint(args.timestamp) then
			-- Skip expired orders
			goto continue
		end

		-- Check if the order is a fixed order
		if currentOrderEntry.Type ~= 'fixed' then
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

			-- Check if the user's ARIO amount matches the ANT sell order price exactly
			if bint(args.quantity) == bint(currentOrderEntry.Price) then
				-- User wants to buy 1 ANT token
				fillAmount = bint(1) -- 1 ANT token (always 1 for ANT orders)
				-- User pays the exact amount of ARIO specified in the ANT sell order
				sendAmount = bint(args.quantity)

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

				-- Apply fees and calculate final amounts
				local calculatedSendAmount = utils.calculateSendAmount(sendAmount)
				local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

				-- Execute token transfers
				utils.executeTokenTransfers(args, currentOrderEntry, validPair, calculatedSendAmount, calculatedFillAmount)

				-- Record the match
				local match = utils.recordMatch(args, currentOrderEntry, validPair, calculatedFillAmount)
				table.insert(matches, match)

				-- Mark the order index for removal
				matchedOrderIndex = i
				break -- Only match with one order, no partial matching
			end
			-- If ARIO amount doesn't match ANT sell order price exactly, skip this order and continue searching
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
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'No matching orders found for immediate ANT trade - exact ARIO amount match required',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return
	end
end

-- dutch_auction.lua
--------------------------------

function dutch_auction.calculateDecreaseStep(args)
    local intervalsCount = (bint(args.expirationTime) - bint(args.timestamp)) / bint(args.decreaseInterval)
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

    local decreaseStep = dutch_auction.calculateDecreaseStep(args)

    if decreaseStep < 1 then
        return false, 'Decrease step must be at least 1. Price difference is too small for the given time intervals.'
    end

    return true
end


-- english_auction.lua
--------------------------------

-- Helper function to handle ARIO token orders: we are selling ANT token, so we need to add to orderbook
function english_auction.handleArioOrder(args, validPair, pairIndex)
	-- Add the new order to the orderbook (buy now functionality)
	table.insert(Orderbook[pairIndex].Orders, {
		Id = args.orderId,
		Quantity = tostring(args.quantity),
		OriginalQuantity = tostring(args.quantity),
		Creator = args.sender,
		Token = validPair[1],
		DateCreated = args.timestamp,
		Price = args.price and tostring(args.price),
		ExpirationTime = args.expirationTime and tostring(args.expirationTime) or nil,
		Type = 'english'
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
				OrderType = 'english'
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
			Message = 'ARIO order added to orderbook for English auction!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = 'english'
		}
	})
end

-- ucm.lua
--------------------------------

function ucm.getPairIndex(pair)
	local pairIndex = -1

	for i, existingOrders in ipairs(Orderbook) do
		if (existingOrders.Pair[1] == pair[1] and existingOrders.Pair[2] == pair[2]) or
			(existingOrders.Pair[1] == pair[2] and existingOrders.Pair[2] == pair[1]) then
			pairIndex = i
			break
		end
	end

	return pairIndex
end

-- Helper function to validate ANT dominant token orders (selling ANT for ARIO)
local function validateAntDominantOrder(args, validPair)
	-- ANT tokens can only be sold in quantities of exactly 1
	if bint(args.quantity) ~= bint(1) then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'ANT tokens can only be sold in quantities of exactly 1',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return false
	end

	-- Expiration time is required when selling ANT
	if not args.expirationTime then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Expiration time is required when selling ANT tokens',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return false
	end

	-- Price is required when selling ANT
	if not args.price then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Price is required when selling ANT tokens',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return false
	end

	-- Validate expiration time is valid
	local isValidExpiration, expirationError = utils.checkValidExpirationTime(args.expirationTime, args.timestamp)
	if not isValidExpiration then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = expirationError,
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return false
	end

	-- Validate price is valid
	local isValidPrice, priceError = utils.checkValidAmount(args.price)
	if not isValidPrice then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = priceError,
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return false
	end

	return true
end

-- Helper function to validate ARIO dominant token orders (buying ANT with ARIO)
local function validateArioDominantOrder(args, validPair)
	-- Currently no specific validation rules for ARIO dominant orders
	-- All general validations (quantity, pair, etc.) are handled in validateOrderParams
	-- This function is a placeholder for future ARIO-specific validation rules

	return true
end

-- Helper function to validate order parameters
local function validateOrderParams(args)
	-- 1. Check pair data
	local validPair, pairError = utils.validatePairData({ args.dominantToken, args.swapToken })
	if not validPair then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = pairError or 'Error validating pair',
			Quantity = args.quantity,
			TransferToken = nil,
			OrderGroupId = args.orderGroupId
		})
		return nil
	end

	-- 2. Validate ARIO is in trade (marketplace requirement)
	local isArioValid, arioError = utils.validateArioInTrade(args.dominantToken, args.swapToken)
	if not isArioValid then
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = arioError or 'Invalid trade - ARIO must be involved',
			Quantity = args.quantity,
			TransferToken = nil,
			OrderGroupId = args.orderGroupId
		})
		return nil
	end

	-- 3. Check quantity is positive integer
	if not utils.checkValidAmount(args.quantity) then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Quantity must be an integer greater than zero',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return nil
	end

	-- 4. Check order type is supported
	if not args.orderType or args.orderType ~= "fixed" and args.orderType ~= "dutch" and args.orderType ~= "english" then
		utils.handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Order type must be "fixed" or "dutch" or "english"',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
		return nil
	end
	-- 5. Check if it's ANT dominant (selling ANT) or ARIO dominant (buying ANT)
	local isAntDominant = not utils.isArioToken(args.dominantToken)

	if isAntDominant then
		-- ANT dominant: validate ANT-specific requirements
		if not validateAntDominantOrder(args, validPair) then
			utils.handleError({
				Target = args.sender,
				Action = 'Validation-Error',
				Message = 'Error validating ANT dominant order',
				Quantity = args.quantity,
				TransferToken = validPair[1],
				OrderGroupId = args.orderGroupId
			})
			return nil
		end

		-- Dutch auction specific validation
		if args.orderType == "dutch" then
			local isValidDutch, dutchError = dutch_auction.validateDutchParams(args)
			if not isValidDutch then
				utils.handleError({
					Target = args.sender,
					Action = 'Validation-Error',
					Message = dutchError,
					Quantity = args.quantity,
					TransferToken = validPair[1],
					OrderGroupId = args.orderGroupId
				})
				return nil
			end
		end

	else
		-- ARIO dominant: validate ARIO-specific requirements
		if not validateArioDominantOrder(args, validPair) then
			utils.handleError({
				Target = args.sender,
				Action = 'Validation-Error',
				Message = 'Error validating ARIO dominant order',
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

local function handleAntOrderAuctions(args, validPair, pairIndex)
	if args.orderType == "fixed" then
		fixed_price.handleAntOrder(args, validPair, pairIndex)
	elseif args.orderType == "dutch" then
		dutch_auction.handleAntOrder(args, validPair, pairIndex)
	else
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Order type not implemented yet',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
	end
end

local function handleArioOrderAuctions(args, validPair, pairIndex)

	-- Check if the desired token is already being sold (prevent duplicate sell orders)
	local currentOrders = Orderbook[pairIndex].Orders
	for _, existingOrder in ipairs(currentOrders) do
		if existingOrder.Token == args.dominantToken then
			utils.handleError({
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

	if args.orderType == "fixed" then
		fixed_price.handleArioOrder(args, validPair, pairIndex)
	elseif args.orderType == "dutch" then
		dutch_auction.handleArioOrder(args, validPair, pairIndex)
	elseif args.orderType == "english" then
		english_auction.handleArioOrder(args, validPair, pairIndex)
	else
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Order type not implemented yet',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
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
			handleAntOrderAuctions(args, validPair, pairIndex)
			return
		end

		-- Handle ARIO token orders - add to orderbook for buy now
		if isBuyingArio then
			handleArioOrderAuctions(args, validPair, pairIndex)
			return
		end

		-- Placeholder for future order type handling
		utils.handleError({
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
		utils.handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Pair not found',
			Quantity = args.quantity,
			TransferToken = validPair[1],
			OrderGroupId = args.orderGroupId
		})
	end
end

--------------------------------

local function getState()
    return {
		Name = Name,
		Orderbook = Orderbook,
		ActivityProcess = ACTIVITY_PROCESS
	}
end

local function syncState()
    Send({ device = 'patch@1.0', orderbook = json.encode(getState()) })
end

function Trusted(msg)
	local mu = 'fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY'
	if msg.Owner == mu then
		return false
	end
	if msg.From == msg.Owner then
		return false
	end
	return true
end

Handlers.prepend('Qualify-Message', Trusted, function(msg)
	print('Message from ' .. msg.From .. ' is not trusted')
end)

Handlers.add('Info', 'Info', function(msg)
	msg.reply({ Data = json.encode(getState()) })
end)

Handlers.add('Get-Orderbook-By-Pair', 'Get-Orderbook-By-Pair',
	function(msg)
		if not msg.Tags.DominantToken or not msg.Tags.SwapToken then return end
		local pairIndex = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })

		if pairIndex > -1 then
			msg.reply({ Data = json.encode({ Orderbook = Orderbook[pairIndex] }) })
		end
	end)

Handlers.add('Credit-Notice', 'Credit-Notice', function(msg)
	if not msg.Tags['X-Dominant-Token'] or msg.From ~= msg.Tags['X-Dominant-Token'] then return end

	local data = {
		Sender = msg.Tags.Sender,
		Quantity = msg.Tags.Quantity
	}

	-- Check if sender is a valid address
	if not utils.checkValidAddress(data.Sender) then
		msg.reply({ Action = 'Validation-Error', Tags = { Status = 'Error', Message = 'Sender must be a valid address' } })
		return
	end

	-- Check if quantity is a valid integer greater than zero
	if not utils.checkValidAmount(data.Quantity) then
		msg.reply({ Action = 'Validation-Error', Tags = { Status = 'Error', Message = 'Quantity must be an integer greater than zero' } })
		return
	end

	-- Check if all required fields are present
	if not data.Sender or not data.Quantity then
		msg.reply({
			Action = 'Input-Error',
			Tags = {
				Status = 'Error',
				Message =
				'Invalid arguments, required { Sender, Quantity }'
			}
		})
		return
	end

	-- If Order-Action then create the order
	if (Handlers.utils.hasMatchingTag('Action', 'X-Order-Action') and msg.Tags['X-Order-Action'] == 'Create-Order') then
		-- Validate that at least one token in the trade is ARIO
		local isArioValid, arioError = utils.validateArioInTrade(msg.From, msg.Tags['X-Swap-Token'])
		if not isArioValid then
			msg.reply({
				Action = 'Validation-Error',
				Tags = { Status = 'Error', Message = arioError or 'At least one token in the trade must be ARIO' }
			})
			return
		end

		local orderArgs = {
			orderId = msg.Id,
			orderGroupId = msg.Tags['X-Group-ID'] or 'None',
			dominantToken = msg.From,
			swapToken = msg.Tags['X-Swap-Token'],
			sender = data.Sender,
			quantity = msg.Tags.Quantity,
			timestamp = msg.Timestamp,
			blockheight = msg['Block-Height'],
			syncState = syncState,
			orderType = msg.Tags['X-Order-Type'] or 'fixed',
			expirationTime = msg.Tags['X-Expiration-Time'],
			minimumPrice = msg.Tags['X-Minimum-Price'],
			decreaseInterval = msg.Tags['X-Decrease-Interval'],
			requestedOrderId = msg.Tags['X-Requested-Order-Id']
		}

		if msg.Tags['X-Price'] then
			orderArgs.price = msg.Tags['X-Price']
		end
		if msg.Tags['X-Transfer-Denomination'] then
			orderArgs.transferDenomination = msg.Tags['X-Transfer-Denomination']
		end

		if msg.Tags['X-Requested-Order-ID'] then
			orderArgs.requestedOrderId = msg.Tags['X-Requested-Order-ID']
		end

		ucm.createOrder(orderArgs)
	end
end)

Handlers.add('Cancel-Order', 'Cancel-Order', function(msg)
	local decodeCheck, data = utils.decodeMessageData(msg.Data)

	if decodeCheck and data then
		if not data.Pair or not data.OrderTxId then
			msg.reply({
				Action = 'Input-Error',
				Tags = { Status = 'Error', Message = 'Invalid arguments, required { Pair: [TokenId, TokenId], OrderTxId }' }
			})
			return
		end

		-- Check if Pair and OrderTxId are valid
		local validPair, pairError = utils.validatePairData(data.Pair)
		local validOrderTxId = utils.checkValidAddress(data.OrderTxId)

		if not validPair or not validOrderTxId then
			local message = nil

			if not validOrderTxId then message = 'OrderTxId is not a valid address' end
			if not validPair then message = pairError or 'Error validating pair' end

			msg.reply({ Action = 'Validation-Error', Tags = { Status = 'Error', Message = message or 'Error validating order cancel input' } })
			return
		end

		-- Ensure the pair exists
		local pairIndex = ucm.getPairIndex(validPair)

		-- If the pair exists then search for the order based on OrderTxId
		if pairIndex > -1 then
			local order = nil
			local orderIndex = nil

			for i, currentOrderEntry in ipairs(Orderbook[pairIndex].Orders) do
				if data.OrderTxId == currentOrderEntry.Id then
					order = currentOrderEntry
					orderIndex = i
				end
			end

			-- The order is not found
			if not order then
				msg.reply({ Action = 'Action-Response', Tags = { Status = 'Error', Message = pairError or 'Order not found', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' } })
				return
			end

			-- Check if the sender is the order creator
			if msg.From ~= order.Creator then
				msg.reply({ Action = 'Action-Response', Tags = { Status = 'Error', Message = pairError or 'Unauthorized to cancel this order', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' } })
				return
			end

			if order and orderIndex > -1 then
				-- Return funds to the creator
				ao.send({
					Target = order.Token,
					Action = 'Transfer',
					Tags = {
						Recipient = order.Creator,
						Quantity = order.Quantity
					}
				})

				-- Remove the order from the current table
				table.remove(Orderbook[pairIndex].Orders, orderIndex)
				msg.reply({ Action = 'Action-Response', Tags = { Status = 'Success', Message = 'Order cancelled', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' } })
				syncState()

				local cancelledDataSuccess, cancelledData = pcall(function()
					return json.encode({
						Order = {
							Id = data.OrderTxId,
							DominantToken = validPair[1],
							SwapToken = validPair[2],
							Sender = msg.From,
							Receiver = nil,
							Quantity = tostring(order.Quantity),
							Price = tostring(order.Price),
							Timestamp = msg.Timestamp
						}
					})
				end)

				ao.send({
					Target = ACTIVITY_PROCESS,
					Action = 'Update-Cancelled-Orders',
					Data = cancelledDataSuccess and cancelledData or ''
				})
			else
				msg.reply({ Action = 'Action-Response', Tags = { Status = 'Error', Message = pairError or 'Error cancelling order', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' } })
			end
		else
			msg.reply({ Action = 'Action-Response', Tags = { Status = 'Error', Message = pairError or 'Pair not found', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' } })
		end
	else
		msg.reply({
			Action = 'Input-Error',
			Tags = {
				Status = 'Error',
				Message = string.format('Failed to parse data, received: %s. %s',
					msg.Data,
					'Data must be an object - { Pair: [TokenId, TokenId], OrderTxId }')
			}
		})
	end
end)

Handlers.add('Read-Orders', 'Read-Orders', function(msg)
	if msg.From == ao.id then
		local readOrders = {}
		local pairIndex = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })

		if pairIndex > -1 then
			for i, order in ipairs(Orderbook[pairIndex].Orders) do
				if not msg.Tags.Creator or order.Creator == msg.Tags.Creator then
					table.insert(readOrders, {
						Index = i,
						Id = order.Id,
						Creator = order.Creator,
						Quantity = order.Quantity,
						Price = order.Price,
						Timestamp = order.Timestamp
					})
				end
			end

			msg.reply({
				Action = 'Read-Orders-Response',
				Data = json.encode(readOrders)
			})
		end
	end
end)

Handlers.add('Read-Pair', Handlers.utils.hasMatchingTag('Action', 'Read-Pair'), function(msg)
	local pairIndex = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })
	if pairIndex > -1 then
		msg.reply({
			Action = 'Read-Success',
			Data = json.encode({
				Pair = tostring(pairIndex),
				Orderbook =
					Orderbook[pairIndex]
			})
		})
	end
end)

Handlers.add('Debit-Notice', Handlers.utils.hasMatchingTag('Action', 'Debit-Notice'), function(msg) end)
