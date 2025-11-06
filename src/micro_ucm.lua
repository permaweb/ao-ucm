local json = require('json')
local bint = require('.bint')(256)

if Name ~= 'Universal Content Marketplace' then Name = 'Universal Content Marketplace' end

if not ACTIVITY_PROCESS then ACTIVITY_PROCESS = '<ACTIVITY_PROCESS>' end

PIXL_PROCESS = 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo'
DEFAULT_SWAP_TOKEN = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'

-- Orderbook {
-- 	Pair [TokenId, TokenId],   -- [Base, Quote]
-- 	Asks {                     -- Selling Base for Quote
-- 		Id,
-- 		Creator,
-- 		Quantity,
-- 		OriginalQuantity,
-- 		Token,
-- 		DateCreated,
-- 		Price,
-- 		Side
-- 	} []
-- 	Bids {                     -- Buying Base with Quote
-- 		Id,
-- 		Creator,
-- 		Quantity,
-- 		OriginalQuantity,
-- 		Token,
-- 		DateCreated,
-- 		Price,
-- 		Side
-- 	} []
-- } []

if not Orderbook then Orderbook = {} end
if not BuybackCaptures then BuybackCaptures = {} end

if not ORDERBOOK_MIGRATED then ORDERBOOK_MIGRATED = false end

local utils = {}
local ucm = {}

function utils.checkValidAddress(address)
	if not address or type(address) ~= 'string' then
		return false
	end

	return string.match(address, '^[%w%-_]+$') ~= nil and #address == 43
end

function utils.checkValidAmount(data)
	return bint(data) > bint(0)
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
	return tostring(amount)
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

function ucm.migrateOrderbook(args)
	for i, pair in ipairs(Orderbook) do
		if pair.Orders and not pair.Asks then
			-- Migrate legacy orders to Asks (all existing orders were listings/asks)
			pair.Asks = {}
			for _, order in ipairs(pair.Orders) do
				order.Side = 'Ask'
				table.insert(pair.Asks, order)
			end
			pair.Bids = {}
			pair.Orders = nil

			print('Migrated pair ' .. i .. ' with ' .. #pair.Asks .. ' orders to Asks')
		end
	end

	args.syncState()
	ORDERBOOK_MIGRATED = true
end

-- -- Normalize a pair to canonical order (sorted)
-- function ucm.normalizePair(pair)
-- 	if pair[1] < pair[2] then
-- 		return { pair[1], pair[2] }
-- 	else
-- 		return { pair[2], pair[1] }
-- 	end
-- end

function ucm.getPairIndex(pair)
	local pairIndex = -1
	local canonicalPair = nil

	for i, existingOrders in ipairs(Orderbook) do
		if (existingOrders.Pair[1] == pair[1] and existingOrders.Pair[2] == pair[2]) or
			(existingOrders.Pair[1] == pair[2] and existingOrders.Pair[2] == pair[1]) then
			pairIndex = i
			canonicalPair = existingOrders.Pair
		end
	end

	return pairIndex, canonicalPair
end

function ucm.determineOrderSide(dominantToken, pair)
	-- If dominant token matches Pair[1] (base), it's an ASK (selling base)
	-- If dominant token matches Pair[2] (quote), it's a BID (buying base with quote)
	if dominantToken == pair[1] then
		return 'Ask'
	elseif dominantToken == pair[2] then
		return 'Bid'
	end
	return nil
end

function ucm.createOrder(args)
	-- Run migration if not yet done
	if not ORDERBOOK_MIGRATED then
		ucm.migrateOrderbook({ syncState = args.syncState })
	end

	-- Priotitize baseToken and quoteToken for pair validation / creation
	-- Fall back to dominantToken and swapToken as they are still valid
	local validPair, pairError = utils.validatePairData({
		args.baseToken or args.dominantToken,
		args.quoteToken or args.swapToken
	})

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
	local pairIndex, canonicalPair = ucm.getPairIndex(validPair)

	-- Use canonical pair from orderbook, or normalize if creating new pair
	if pairIndex == -1 then
		-- Initialize denominations: [base_denomination, quote_denomination]
		local denominations = { '1', '1' } -- Default to 1 if not provided
		if args.baseTokenDenomination then denominations[1] = tostring(args.baseTokenDenomination) end
		if args.quoteTokenDenomination then denominations[2] = tostring(args.quoteTokenDenomination) end

		table.insert(Orderbook, { Pair = validPair, Denominations = denominations, Asks = {}, Bids = {} })
		pairIndex, canonicalPair = ucm.getPairIndex(validPair)
	else
		-- Pair exists: ensure denominations are set (backward compatibility)
		if not Orderbook[pairIndex].Denominations then
			Orderbook[pairIndex].Denominations = { '1', '1' }
		end

		-- Update denominations if they're passed and currently set to default
		if args.baseTokenDenomination and Orderbook[pairIndex].Denominations[1] == '1' then
			Orderbook[pairIndex].Denominations[1] = tostring(args.baseTokenDenomination)
		end
		if args.quoteTokenDenomination and Orderbook[pairIndex].Denominations[2] == '1' then
			Orderbook[pairIndex].Denominations[2] = tostring(args.quoteTokenDenomination)
		end
	end

	if not canonicalPair then
		handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Error retrieving pair',
			Quantity = args.quantity,
			TransferToken = currentToken,
			OrderGroupId = args.orderGroupId
		})
		return
	end

	-- Determine order side using canonical pair
	local orderSide = ucm.determineOrderSide(args.dominantToken, canonicalPair)

	if not orderSide then
		handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Invalid dominant token for pair',
			Quantity = args.quantity,
			TransferToken = args.dominantToken,
			OrderGroupId = args.orderGroupId
		})
		return
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

		-- Get denominations from the pair
		print('DEBUG: Denominations from orderbook:', Orderbook[pairIndex].Denominations[1], Orderbook[pairIndex].Denominations[2])
		local baseDenominationStr = Orderbook[pairIndex].Denominations[1]
		local quoteDenominationStr = Orderbook[pairIndex].Denominations[2]

		-- Safely convert to bint
		local success1, baseDenom = pcall(bint, baseDenominationStr)
		if not success1 then
			print('ERROR converting baseDenomination:', baseDenominationStr)
			baseDenom = bint(1)
		end

		local success2, quoteDenom = pcall(bint, quoteDenominationStr)
		if not success2 then
			print('ERROR converting quoteDenomination:', quoteDenominationStr)
			quoteDenom = bint(1)
		end

		local baseDenomination = baseDenom
		local quoteDenomination = quoteDenom
		print('DEBUG: Converted denominations - base:', tostring(baseDenomination), 'quote:', tostring(quoteDenomination))


		-- Get opposite side for matching
		local matchingSide = (orderSide == 'Bid') and 'Asks' or 'Bids'
		local currentOrders = Orderbook[pairIndex][matchingSide]
		local updatedOrderbook = {}
		local matches = {}
		local finalMatch = false

		-- Sort order entries based on price and order side
		if orderSide == 'Bid' then
			-- For bids, match against lowest asks first
			table.sort(currentOrders, function(a, b)
				return bint(a.Price) < bint(b.Price)
			end)
		else
			-- For asks, match against highest bids first
			table.sort(currentOrders, function(a, b)
				return bint(a.Price) > bint(b.Price)
			end)
		end

		-- If the incoming order is a limit order, add it to the order book
		if orderType == 'Limit' then
			table.insert(Orderbook[pairIndex][orderSide .. 's'], {
				Id = args.orderId,
				Quantity = tostring(args.quantity),
				OriginalQuantity = tostring(args.quantity),
				Creator = args.sender,
				Token = args.dominantToken,
				DateCreated = args.timestamp,
				Price = tostring(args.price),
				Side = orderSide,
			})

			local limitDataSuccess, limitData = pcall(function()
				return json.encode({
					Order = {
						Id = args.orderId,
						DominantToken = canonicalPair[1],
						SwapToken = canonicalPair[2],
						Sender = args.sender,
						Receiver = nil,
						Quantity = tostring(args.quantity),
						Price = tostring(args.price),
						Timestamp = args.timestamp,
						Side = orderSide
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

			args.syncState()

			return
		end

		for orderIndex, currentOrderEntry in ipairs(currentOrders) do
			print('=== Processing order ===')
			print('matchingSide:' .. matchingSide)
			print('remainingQuantity:' .. tostring(remainingQuantity))
			print('order.Price:' .. currentOrderEntry.Price)
			print('order.Quantity:' .. currentOrderEntry.Quantity)
			print('baseDenomination:' .. tostring(baseDenomination))

			if remainingQuantity > bint(0) and bint(currentOrderEntry.Quantity) > bint(0) then
				local fillAmount, sendAmount

				-- Calculate fillAmount and sendAmount based on matching side
				-- Price is stored as: quoteDenomination raw per 1 baseDenomination display
				if matchingSide == 'Asks' then
					print('Matching against Asks')
					-- Matching against asks: remainingQuantity is quote token (raw), fillAmount is base token (raw)
					-- To preserve precision: fillAmount = (remainingQuantity * baseDenomination) / price
					print('Step 1: Multiply before divide to preserve precision')
					local orderPrice = bint(currentOrderEntry.Price)
					print('Step 2: fillAmount = (remainingQuantity * baseDenomination) // price')
					fillAmount = (remainingQuantity * baseDenomination) // orderPrice
					print('fillAmount:' .. tostring(fillAmount))

					-- sendAmount = how much quote token we actually spend (recalculate to handle rounding)
					print('Step 3: Calculate sendAmount = (fillAmount * price) // baseDenomination')
					sendAmount = (fillAmount * orderPrice) // baseDenomination
					print('sendAmount:' .. tostring(sendAmount))
				else
					print('Matching against Bids')
					-- Matching against bids: remainingQuantity is base token (raw), fillAmount is quote token (raw)
					-- fillAmount (quote raw) = (remainingQuantity (base raw) / baseDenomination) * price
					if baseDenomination > bint(1) then
						print('Step 1: baseAmountDisplay = remainingQuantity // baseDenomination')
						local baseAmountDisplay = remainingQuantity // baseDenomination
						print('baseAmountDisplay:' .. tostring(baseAmountDisplay))
						print('Step 2: fillAmount = baseAmountDisplay * bint(price)')
						fillAmount = baseAmountDisplay * bint(currentOrderEntry.Price)
						print('fillAmount:' .. tostring(fillAmount))
					else
						fillAmount = remainingQuantity * bint(currentOrderEntry.Price)
					end
					-- sendAmount = how much base token we actually spend (recalculate to handle rounding)
					print('Step 3: fillAmountDisplay = fillAmount // bint(price)')
					local fillAmountDisplay = fillAmount // bint(currentOrderEntry.Price)
					print('fillAmountDisplay:' .. tostring(fillAmountDisplay))
					print('Step 4: sendAmount = fillAmountDisplay * baseDenomination')
					sendAmount = fillAmountDisplay * baseDenomination
					print('sendAmount:' .. tostring(sendAmount))
				end

				-- Ensure the fill amount does not exceed the available quantity in the order
				if fillAmount > bint(currentOrderEntry.Quantity) then
					fillAmount = bint(currentOrderEntry.Quantity)
					-- Recalculate sendAmount based on adjusted fillAmount
					if matchingSide == 'Asks' then
						sendAmount = (fillAmount * bint(currentOrderEntry.Price)) // baseDenomination
					else
						local fillDisplay = fillAmount // bint(currentOrderEntry.Price)
						sendAmount = fillDisplay * baseDenomination
					end
				end

				-- Subtract the used quantity from the remaining quantity
				print('DEBUG: Before subtraction - remainingQuantity type:' .. type(remainingQuantity))
				print('DEBUG: sendAmount type:' .. type(sendAmount))

				local success, result = pcall(function()
					return remainingQuantity - sendAmount
				end)

				if success then
					remainingQuantity = result
					print('DEBUG: After subtraction - remainingQuantity OK')
					print('DEBUG: remainingQuantity value:' .. tostring(remainingQuantity))
				else
					print('ERROR in subtraction:' .. result)
					print('remainingQuantity was:' .. type(remainingQuantity))
					print('sendAmount was:' .. type(sendAmount))
					break
				end

				local qtySuccess, qtyResult = pcall(function()
					return bint(currentOrderEntry.Quantity) - fillAmount
				end)

				if not qtySuccess then
					print('ERROR updating order quantity:', qtyResult)
					print('currentOrderEntry.Quantity:', currentOrderEntry.Quantity)
					print('fillAmount:', tostring(fillAmount))
					break
				end

				currentOrderEntry.Quantity = tostring(qtyResult)

				-- Check if all quantity consumed after updating the current order
				if remainingQuantity <= bint(0) then
					print('DEBUG: All quantity consumed, will exit matching loop after processing this order')
					finalMatch = true
				end

				if fillAmount <= bint(0) then
					handleError({
						Target = args.sender,
						Action = 'Order-Error',
						Message = 'No amount to fill',
						Quantity = args.quantity,
						TransferToken = currentToken,
						OrderGroupId = args.orderGroupId
					})

					args.syncState()

					return
				end

				local calculatedSendAmount = utils.calculateSendAmount(sendAmount)
				local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

				-- Gather all fulfillment fees for buyback
				table.insert(BuybackCaptures, utils.calculateFeeAmount(sendAmount))

				-- Transfer tokens based on order side
				if orderSide == 'Bid' then
					-- Incoming bid: buyer sends quote token, gets base token from ask
					-- Send quote token (from buyer) to the ask order creator
					ao.send({
						Target = args.dominantToken,
						Action = 'Transfer',
						Tags = {
							Recipient = currentOrderEntry.Creator,
							Quantity = tostring(calculatedSendAmount)
						}
					})

					-- Send base token (from ask) to the buyer
					ao.send({
						Target = currentOrderEntry.Token,
						Action = 'Transfer',
						Tags = {
							Recipient = args.sender,
							Quantity = tostring(calculatedFillAmount)
						}
					})
				else
					-- Incoming ask: seller sends base token, gets quote token from bid
					-- Send quote token (from bid) to the ask order creator (seller)
					ao.send({
						Target = currentOrderEntry.Token,
						Action = 'Transfer',
						Tags = {
							Recipient = args.sender,
							Quantity = tostring(calculatedSendAmount)
						}
					})

					-- Send base token (from seller) to the bid order creator
					ao.send({
						Target = args.dominantToken,
						Action = 'Transfer',
						Tags = {
							Recipient = currentOrderEntry.Creator,
							Quantity = tostring(calculatedFillAmount)
						}
					})
				end

				-- Record the match
				table.insert(matches, {
					Id = currentOrderEntry.Id,
					Quantity = tostring(fillAmount),
					Price = tostring(currentOrderEntry.Price)
				})

				local matchedDataSuccess, matchedData = pcall(function()
					return json.encode({
						Order = {
							Id = currentOrderEntry.Id,
							MatchId = args.orderId,
							DominantToken = canonicalPair[2],
							SwapToken = canonicalPair[1],
							Sender = currentOrderEntry.Creator,
							Receiver = args.sender,
							Quantity = calculatedFillAmount,
							Price = tostring(currentOrderEntry.Price),
							Timestamp = args.timestamp,
							Side = currentOrderEntry.Side,
							IncomingSide = orderSide
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

				-- Break if this was the final match (remainingQuantity exhausted)
				if finalMatch then
					print('DEBUG: Breaking from matching loop - no remaining quantity')
					-- Add all remaining unprocessed orders back to the orderbook
					for i = orderIndex + 1, #currentOrders do
						if bint(currentOrders[i].Quantity) > bint(0) then
							print('DEBUG: Adding unprocessed order', i, 'back to orderbook')
							table.insert(updatedOrderbook, currentOrders[i])
						end
					end
					break
				end
			else
				print(currentOrderEntry)
				if currentOrderEntry.Quantity and bint(currentOrderEntry.Quantity) > bint(0) then
					print('H26')
					table.insert(updatedOrderbook, currentOrderEntry)
				end
			end
		end

		-- -- Execute PIXL buyback
		-- if orderType == 'Market' and #BuybackCaptures > 0 and currentToken == DEFAULT_SWAP_TOKEN and args.sender ~= ao.id then
		-- 	ucm.executeBuyback({
		-- 		orderId = args.orderId,
		-- 		blockheight = args.blockheight,
		-- 		timestamp = args.timestamp,
		-- 		syncState = args.syncState
		-- 	})
		-- end

		-- Update the order book with remaining orders on the matching side
		Orderbook[pairIndex][matchingSide] = updatedOrderbook

		print('DEBUG: Starting PriceData calculation, matches count:', #matches)
		local sumVolumePrice, sumVolume = 0, 0
		local vwap = 0
		if #matches > 0 then
			print('DEBUG: Checking for existing MatchLogs')
			-- Append to existing MatchLogs if they exist
			local existingMatchLogs = {}
			if Orderbook[pairIndex].PriceData and Orderbook[pairIndex].PriceData.MatchLogs then
				existingMatchLogs = Orderbook[pairIndex].PriceData.MatchLogs
				print('DEBUG: Found existing MatchLogs, count:', #existingMatchLogs)
			end

			print('DEBUG: Processing matches for VWAP')
			for i, match in ipairs(matches) do
				print('DEBUG: Processing match', i, 'Quantity:', match.Quantity, 'Price:', match.Price)
				table.insert(existingMatchLogs, match)

				print('DEBUG: Converting to bint')
				local volumeSuccess, volume = pcall(bint, match.Quantity)
				if not volumeSuccess then
					print('ERROR converting volume to bint:', volume)
					break
				end

				local priceSuccess, price = pcall(bint, match.Price)
				if not priceSuccess then
					print('ERROR converting price to bint:', price)
					break
				end

				print('DEBUG: Calculating volume * price')
				local vwapSuccess, vwapProduct = pcall(function()
					return volume * price
				end)

				if not vwapSuccess then
					print('ERROR calculating VWAP - volume * price overflow:', vwapProduct)
					print('volume:', tostring(volume))
					print('price:', tostring(price))
					-- Skip VWAP calculation but continue with match processing
				else
					print('DEBUG: VWAP product calculated:', tostring(vwapProduct))
					sumVolumePrice = sumVolumePrice + vwapProduct
					sumVolume = sumVolume + volume
				end
			end

			print('DEBUG: Calculating final VWAP, sumVolume:', tostring(sumVolume))
			if sumVolume > bint(0) then
				vwap = sumVolumePrice / sumVolume
				print('DEBUG: VWAP calculated:', tostring(vwap))
			end

			print('DEBUG: Creating PriceData object')
			Orderbook[pairIndex].PriceData = {
				Vwap = tostring(math.floor(vwap)),
				Block = tostring(args.blockheight),
				DominantToken = args.dominantToken,
				MatchLogs = existingMatchLogs
			}
			print('DEBUG: PriceData created successfully')
		end

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
					Price = tostring(math.floor(vwap)),
					Message = 'Order created successfully!',
					['X-Group-ID'] = args.orderGroupId or 'None'
				}
			})

			args.syncState()
		else
			handleError({
				Target = args.sender,
				Action = 'Order-Error',
				Message = 'No amount to fill',
				Quantity = args.quantity,
				TransferToken = currentToken,
				OrderGroupId = args.orderGroupId
			})

			args.syncState()

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

function ucm.cancelOrder(args)
	-- Validate pair data
	local validPair, pairError = utils.validatePairData(args.pair)
	if not validPair then
		return false, pairError or 'Error validating pair'
	end

	-- Validate order ID
	if not utils.checkValidAddress(args.orderId) then
		return false, 'OrderId is not a valid address'
	end

	-- Find the pair and get canonical pair
	local pairIndex, canonicalPair = ucm.getPairIndex(validPair)
	if pairIndex == -1 then
		return false, 'Pair not found'
	end

	-- Search for the order in both Asks and Bids
	local order = nil
	local orderIndex = nil
	local orderSide = nil

	for i, currentOrderEntry in ipairs(Orderbook[pairIndex].Asks) do
		if args.orderId == currentOrderEntry.Id then
			order = currentOrderEntry
			orderIndex = i
			orderSide = 'Asks'
			break
		end
	end

	if not order then
		for i, currentOrderEntry in ipairs(Orderbook[pairIndex].Bids) do
			if args.orderId == currentOrderEntry.Id then
				order = currentOrderEntry
				orderIndex = i
				orderSide = 'Bids'
				break
			end
		end
	end

	-- Order not found
	if not order then
		return false, 'Order not found'
	end

	-- Check authorization
	if args.sender ~= order.Creator then
		return false, 'Unauthorized to cancel this order'
	end

	-- Return funds to the creator
	ao.send({
		Target = order.Token,
		Action = 'Transfer',
		Tags = {
			Recipient = order.Creator,
			Quantity = order.Quantity
		}
	})

	-- Remove the order from the orderbook
	table.remove(Orderbook[pairIndex][orderSide], orderIndex)

	-- Notify activity process
	local cancelledDataSuccess, cancelledData = pcall(function()
		return json.encode({
			Order = {
				Id = args.orderId,
				DominantToken = canonicalPair[1],
				SwapToken = canonicalPair[2],
				Sender = args.sender,
				Receiver = nil,
				Quantity = tostring(order.Quantity),
				Price = tostring(order.Price),
				Timestamp = args.timestamp,
				Side = order.Side
			}
		})
	end)

	ao.send({
		Target = ACTIVITY_PROCESS,
		Action = 'Update-Cancelled-Orders',
		Data = cancelledDataSuccess and cancelledData or ''
	})

	-- Sync state
	args.syncState()

	return true, 'Order cancelled successfully'
end

function ucm.executeBuyback(args)
	local pixlDenomination = 1000000
	local pixlPairIndex, _ = ucm.getPairIndex({ DEFAULT_SWAP_TOKEN, PIXL_PROCESS })

	if pixlPairIndex > -1 then
		-- Use Asks side for buyback (buying PIXL tokens from asks)
		local pixlOrderbook = Orderbook[pixlPairIndex].Asks

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
				transferDenomination = tostring(pixlDenomination),
				syncState = args.syncState
			})

			BuybackCaptures = {}
		end
	end
end

local function getState()
	return {
		Name = Name,
		Orderbook = Orderbook,
		ActivityProcess = ACTIVITY_PROCESS
	}
end

local function syncState()
	Send({ device = 'patch@1.0', orderbook = getState() })
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
		local pairIndex, _ = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })

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
		local orderArgs = {
			orderId = msg.Id,
			orderGroupId = msg.Tags['X-Group-ID'] or 'None',
			baseToken = msg.Tags['X-Base-Token'],
			quoteToken = msg.Tags['X-Quote-Token'],
			baseTokenDenomination = msg.Tags['X-Base-Token-Denomination'],
			quoteTokenDenomination = msg.Tags['X-Quote-Token-Denomination'],
			dominantToken = msg.From,
			swapToken = msg.Tags['X-Swap-Token'],
			sender = data.Sender,
			quantity = msg.Tags.Quantity,
			timestamp = msg.Timestamp,
			blockheight = msg['Block-Height'],
			syncState = syncState
		}

		if msg.Tags['X-Price'] then
			orderArgs.price = msg.Tags['X-Price']
		end
		if msg.Tags['X-Transfer-Denomination'] then
			orderArgs.transferDenomination = msg.Tags['X-Transfer-Denomination']
		end

		print(orderArgs)

		ucm.createOrder(orderArgs)
	end
end)

Handlers.add('Cancel-Order', 'Cancel-Order', function(msg)
	local decodeCheck, data = utils.decodeMessageData(msg.Data)

	if not decodeCheck or not data then
		msg.reply({
			Action = 'Input-Error',
			Tags = {
				Status = 'Error',
				Message = string.format('Failed to parse data, received: %s. %s',
					msg.Data,
					'Data must be an object - { Pair: [TokenId, TokenId], OrderTxId }')
			}
		})
		return
	end

	if not data.Pair or not data.OrderTxId then
		msg.reply({
			Action = 'Input-Error',
			Tags = { Status = 'Error', Message = 'Invalid arguments, required { Pair: [TokenId, TokenId], OrderTxId }' }
		})
		return
	end

	-- Call ucm.cancelOrder
	local success, errorMessage = ucm.cancelOrder({
		pair = data.Pair,
		orderId = data.OrderTxId,
		sender = msg.From,
		timestamp = msg.Timestamp,
		syncState = syncState
	})

	if success then
		msg.reply({
			Action = 'Action-Response',
			Tags = {
				Status = 'Success',
				Message = 'Order cancelled',
				['X-Group-ID'] = data['X-Group-ID'] or 'None',
				Handler = 'Cancel-Order'
			}
		})
	else
		msg.reply({
			Action = 'Action-Response',
			Tags = {
				Status = 'Error',
				Message = errorMessage,
				['X-Group-ID'] = data['X-Group-ID'] or 'None',
				Handler = 'Cancel-Order'
			}
		})
	end
end)

Handlers.add('Read-Orders', 'Read-Orders', function(msg)
	if msg.From == ao.id then
		local readOrders = {}
		local pairIndex, _ = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })

		if pairIndex > -1 then
			-- Read from both Asks and Bids
			for i, order in ipairs(Orderbook[pairIndex].Asks) do
				if not msg.Tags.Creator or order.Creator == msg.Tags.Creator then
					table.insert(readOrders, {
						Index = i,
						Id = order.Id,
						Creator = order.Creator,
						Quantity = order.Quantity,
						Price = order.Price,
						Timestamp = order.Timestamp,
						Side = 'Ask'
					})
				end
			end

			for i, order in ipairs(Orderbook[pairIndex].Bids) do
				if not msg.Tags.Creator or order.Creator == msg.Tags.Creator then
					table.insert(readOrders, {
						Index = i,
						Id = order.Id,
						Creator = order.Creator,
						Quantity = order.Quantity,
						Price = order.Price,
						Timestamp = order.Timestamp,
						Side = 'Bid'
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
	local pairIndex, _ = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })
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

Handlers.add('Order-Success', Handlers.utils.hasMatchingTag('Action', 'Order-Success'), function(msg)
	if msg.From == ao.id and
		msg.Tags.DominantToken and msg.Tags.DominantToken == DEFAULT_SWAP_TOKEN and
		msg.Tags.SwapToken and msg.Tags.SwapToken == PIXL_PROCESS then
		if msg.Tags.Quantity and tonumber(msg.Tags.Quantity) > 0 then
			ao.send({
				Target = PIXL_PROCESS,
				Action = 'Transfer',
				Tags = {
					Recipient = string.rep('0', 43),
					Quantity = msg.Tags.Quantity
				}
			})
		end
	end
end)

Handlers.add('Debit-Notice', Handlers.utils.hasMatchingTag('Action', 'Debit-Notice'), function(msg) end)

return ucm
