local json = require('json')
local bint = require('.bint')(256)

if Name ~= 'Universal Content Marketplace' then Name = 'Universal Content Marketplace' end

if not ACTIVITY_PROCESS then ACTIVITY_PROCESS = '<ACTIVITY_PROCESS>' end

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

			args.syncState()

			return
		end

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

					args.syncState()

					return
				end

				local calculatedSendAmount = utils.calculateSendAmount(sendAmount)
				local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

				-- Gather all fulfillment fees for buyback
				table.insert(BuybackCaptures, utils.calculateFeeAmount(sendAmount))

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
				timestamp = args.timestamp,
				syncState = args.syncState
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
		local orderArgs = {
			orderId = msg.Id,
			orderGroupId = msg.Tags['X-Group-ID'] or 'None',
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
