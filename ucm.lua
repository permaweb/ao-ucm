local json = require('json')
local bint = require('.bint')(256)

PIXL_PROCESS = '8Lz_BvNqxlhSlyx282o4v7AIwKQpUn-qklhDnHgUWQs'

if Name ~= 'Universal Content Marketplace' then Name = 'Universal Content Marketplace' end

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
if not ListedOrders then ListedOrders = {} end
if not ExecutedOrders then ExecutedOrders = {} end
if not SalesByAddress then SalesByAddress = {} end
if not PurchasesByAddress then PurchasesByAddress = {} end

local function checkValidAddress(address)
	if not address or type(address) ~= 'string' then
		return false
	end

	return string.match(address, "^[%w%-_]+$") ~= nil and #address == 43
end

local function checkValidAmount(data)
	return math.type(tonumber(data)) == 'integer' and bint(data) > 0
end

local function decodeMessageData(data)
	local status, decodedData = pcall(json.decode, data)

	if not status or type(decodedData) ~= 'table' then
		return false, nil
	end

	return true, decodedData
end

local function validatePairData(data)
	-- Check if pair is a table with exactly two elements
	if type(data) ~= 'table' or #data ~= 2 then
		return nil, 'Pair must be a list of exactly two strings - [TokenId, TokenId]'
	end

	-- Check if both elements of the table are strings
	if type(data[1]) ~= 'string' or type(data[2]) ~= 'string' then
		return nil, 'Both pair elements must be strings'
	end

	-- Check if both elements are valid addresses
	if not checkValidAddress(data[1]) or not checkValidAddress(data[2]) then
		return nil, 'Both pair elements must be valid addresses'
	end

	-- Ensure the addresses are not equal
	if data[1] == data[2] then
		return nil, 'Pair addresses cannot be equal'
	end

	return data
end

local function getPairIndex(pair)
	local pairIndex = -1

	for i, existingOrders in ipairs(Orderbook) do
		if (existingOrders.Pair[1] == pair[1] and existingOrders.Pair[2] == pair[2]) or
			(existingOrders.Pair[1] == pair[2] and existingOrders.Pair[2] == pair[1]) then
			pairIndex = i
		end
	end

	return pairIndex
end

local function handleError(args) -- Target, TransferToken, Quantity
	-- If there is a valid quantity then return the funds
	if args.TransferToken and args.Quantity and checkValidAmount(args.Quantity) then
		ao.send({
			Target = args.TransferToken,
			Action = 'Transfer',
			Tags = {
				Recipient = args.Target,
				Quantity = tostring(args.Quantity)
			}
		})
	end
	ao.send({ Target = args.Target, Action = args.Action, Tags = { Status = 'Error', Message = args.Message } })
end

local function createOrder(args) -- orderId, dominantToken, swapToken, sender, quantity, price?, timestamp
	local validPair, pairError = validatePairData({ args.dominantToken, args.swapToken })

	if validPair then
		local currentToken = validPair[1]

		local pairIndex = getPairIndex(validPair)

		if pairIndex == -1 then
			table.insert(Orderbook, { Pair = validPair, Orders = {} })
			pairIndex = getPairIndex(validPair)
		end

		if not checkValidAmount(args.quantity) then
			handleError({
				Target = args.sender,
				Action = 'Validation-Error',
				Message = 'Quantity must be an integer greater than zero',
				Quantity = args.quantity,
				TransferToken = currentToken,
			})
			return
		end

		if args.price and not checkValidAmount(args.price) then
			handleError({
				Target = args.sender,
				Action = 'Validation-Error',
				Message = 'Price must be an integer greater than zero',
				Quantity = args.quantity,
				TransferToken = currentToken,
			})
			return
		end

		if pairIndex > -1 then
			local orderType = nil
			local reverseOrders = {}
			local currentOrders = Orderbook[pairIndex].Orders
			local updatedOrderbook = {}
			local matches = {}

			if args.price then
				orderType = 'Limit'
			else
				orderType = 'Market'
			end

			table.sort(currentOrders, function(a, b)
				if a.Price and b.Price then
					return bint(a.Price) < bint(b.Price)
				else
					return true
				end
			end)

			for _, currentOrderEntry in ipairs(currentOrders) do
				if currentToken ~= currentOrderEntry.Token then
					table.insert(reverseOrders, currentOrderEntry)
				end
			end

			if #reverseOrders <= 0 then
				if orderType ~= 'Limit' then
					handleError({
						Target = args.sender,
						Action = 'Order-Error',
						Message = 'The first order entry must be a limit order',
						Quantity = args.quantity,
						TransferToken = currentToken,
					})
				else
					table.insert(currentOrders, {
						Id = args.orderId,
						Creator = args.sender,
						Quantity = tostring(args.quantity),
						OriginalQuantity = tostring(args.quantity),
						Token = currentToken,
						DateCreated = tostring(args.timestamp),
						Price = tostring(args.price)
					})

					table.insert(ListedOrders, {
						OrderId = args.orderId,
						DominantToken = validPair[1],
						SwapToken = validPair[2],
						Sender = args.sender,
						Receiver = nil,
						Quantity = tostring(args.quantity),
						Price = tostring(args.price),
						Timestamp = args.timestamp
					})

					ao.send({ Target = args.sender, Action = 'Action-Response', Tags = { Status = 'Success', Message = 'Order created!', Handler = 'Create-Order' } })
				end
				return
			end

			local fillAmount = bint(0)
			local receiveAmount = bint(0)
			local remainingQuantity = bint(args.quantity)
			local dominantToken = Orderbook[pairIndex].Pair[1]

			for _, currentOrderEntry in ipairs(currentOrders) do
				local reversePrice = bint(1) / bint(currentOrderEntry.Price)

				if orderType == 'Limit' and args.price and bint(args.price) ~= reversePrice then
					table.insert(updatedOrderbook, currentOrderEntry)
				else
					local receiveFromCurrent = bint(0)

					fillAmount = bint(bint(remainingQuantity) * reversePrice)

					if fillAmount <= bint(currentOrderEntry.Quantity) then
						receiveFromCurrent = bint(remainingQuantity) * reversePrice
						currentOrderEntry.Quantity = bint(currentOrderEntry.Quantity) - fillAmount
						receiveAmount = bint(receiveAmount) + receiveFromCurrent

						if remainingQuantity > bint(0) then
							ao.send({
								Target = currentToken,
								Action = 'Transfer',
								Tags = {
									Recipient = currentOrderEntry.Creator,
									Quantity = tostring(remainingQuantity)
								}
							})
						end

						remainingQuantity = bint(0)
					else
						receiveFromCurrent = bint(currentOrderEntry.Quantity) or bint(0)
						receiveAmount = bint(receiveAmount) + receiveFromCurrent

						local sendAmount = receiveFromCurrent * bint(currentOrderEntry.Price)
						remainingQuantity = bint(remainingQuantity) - sendAmount

						ao.send({
							Target = currentToken,
							Action = 'Transfer',
							Tags = {
								Recipient = currentOrderEntry.Creator,
								Quantity = tostring(sendAmount)
							}
						})

						currentOrderEntry.Quantity = '0'
					end

					local dominantPrice = (dominantToken == currentToken) and (bint(args.price) or reversePrice) or bint(currentOrderEntry.Price)

					if receiveFromCurrent > bint(0) then
						table.insert(matches, {
							Id = currentOrderEntry.Id,
							Quantity = tostring(receiveFromCurrent),
							Price = tostring(dominantPrice)
						})

						table.insert(ExecutedOrders, {
							OrderId = currentOrderEntry.Id,
							DominantToken = validPair[2],
							SwapToken = validPair[1],
							Sender = currentOrderEntry.Creator,
							Receiver = args.sender,
							Quantity = receiveFromCurrent,
							Price = dominantPrice,
							Timestamp = args.timestamp
						})

						if not SalesByAddress[currentOrderEntry.Creator] then
							SalesByAddress[currentOrderEntry.Creator] = 0
						end
						SalesByAddress[currentOrderEntry.Creator] = SalesByAddress[currentOrderEntry.Creator] + 1

						if not PurchasesByAddress[args.sender] then
							PurchasesByAddress[args.sender] = 0
						end
						PurchasesByAddress[args.sender] = PurchasesByAddress[args.sender] + 1

						ao.send({
							Target = PIXL_PROCESS,
							Action = 'Calculate-Streak',
							Tags = {
								Buyer = args.sender
							}
						})
					end

					if bint(currentOrderEntry.Quantity) ~= bint(0) then
						currentOrderEntry.Quantity = tostring(currentOrderEntry.Quantity)
						table.insert(updatedOrderbook, currentOrderEntry)
					end
				end
			end

			if remainingQuantity > bint(0) then
				if orderType == 'Limit' then
					table.insert(updatedOrderbook, {
						Id = args.orderId,
						Quantity = tostring(remainingQuantity),
						OriginalQuantity = tostring(args.quantity),
						Creator = args.sender,
						Token = currentToken,
						DateCreated = tostring(args.timestamp),
						Price = tostring(args.price)
					})
				else
					ao.send({
						Target = currentToken,
						Action = 'Transfer',
						Tags = {
							Recipient = args.sender,
							Quantity = tostring(remainingQuantity)
						}
					})
				end
			end

			ao.send({
				Target = validPair[2],
				Action = 'Transfer',
				Tags = {
					Recipient = args.sender,
					Quantity = tostring(receiveAmount)
				}
			})

			Orderbook[pairIndex].Orders = updatedOrderbook

			if #matches > 0 then
				local sumVolumePrice = 0
				local sumVolume = 0

				for _, match in ipairs(matches) do
					local volume = match.Quantity
					local price = match.Price

					sumVolumePrice = sumVolumePrice + (volume * price)
					sumVolume = sumVolume + volume
				end

				local vwap = sumVolumePrice / sumVolume

				Orderbook[pairIndex].PriceData = {
					Vwap = tostring(vwap),
					Block = tostring(args.blockheight),
					DominantToken = dominantToken,
					MatchLogs = matches
				}
			else
				Orderbook[pairIndex].PriceData = nil
			end

			ao.send({ Target = args.sender, Action = 'Action-Response', Tags = { Status = 'Success', Message = 'Order created!', Handler = 'Create-Order' } })
		else
			handleError({
				Target = args.sender,
				Action = 'Order-Error',
				Message = 'Pair not found',
				Quantity = args.quantity,
				TransferToken = currentToken,
			})
		end
	else
		handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = pairError or 'Error validating pair',
			Quantity = args.Quantity,
			TransferToken = nil,
		})
	end
end


-- Read process state
Handlers.add('Info', Handlers.utils.hasMatchingTag('Action', 'Info'),
	function(msg)
		ao.send({
			Target = msg.From,
			Action = 'Read-Success',
			Data = json.encode({
				Name = Name,
				Orderbook = Orderbook
			})
		})
	end)

-- Add credit notice to the deposits table (Data - { Sender, Quantity })
Handlers.add('Credit-Notice', Handlers.utils.hasMatchingTag('Action', 'Credit-Notice'), function(msg)
	-- local decodeCheck, data = decodeMessageData(msg.Data)

	local data = {
		Sender = msg.Tags.Sender,
		Quantity = msg.Tags.Quantity
	}

	-- Check if all required fields are present
	if not data.Sender or not data.Quantity then
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Tags = {
				Status = 'Error',
				Message =
				'Invalid arguments, required { Sender, Quantity }'
			}
		})
		return
	end

	-- Check if sender is a valid address
	if not checkValidAddress(data.Sender) then
		ao.send({ Target = msg.From, Action = 'Validation-Error', Tags = { Status = 'Error', Message = 'Sender must be a valid address' } })
		return
	end

	-- Check if quantity is a valid integer greater than zero
	if not checkValidAmount(data.Quantity) then
		ao.send({ Target = msg.From, Action = 'Validation-Error', Tags = { Status = 'Error', Message = 'Quantity must be an integer greater than zero' } })
		return
	end

	-- If Order-Action then create the order
	if (Handlers.utils.hasMatchingTag('Action', 'X-Order-Action') and msg.Tags['X-Order-Action'] == 'Create-Order') then
		local orderArgs = {
			orderId = msg.Id,
			dominantToken = msg.From,
			swapToken = msg.Tags['X-Swap-Token'],
			sender = data.Sender,
			quantity = msg.Tags['X-Quantity'],
			timestamp = msg.Timestamp,
			blockheight = msg['Block-Height']
		}

		if msg.Tags['X-Price'] then
			orderArgs.price = msg.Tags['X-Price']
		end

		createOrder(orderArgs)
	end
end)

-- Cancel order by ID (Data - { Pair: [TokenId, TokenId], OrderTxId })
Handlers.add('Cancel-Order', Handlers.utils.hasMatchingTag('Action', 'Cancel-Order'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
		if not data.Pair or not data.OrderTxId then
			ao.send({
				Target = msg.From,
				Action = 'Input-Error',
				Tags = { Status = 'Error', Message = 'Invalid arguments, required { Pair: [TokenId, TokenId], OrderTxId }' }
			})
			return
		end

		-- Check if Pair and OrderTxId are valid
		local validPair, pairError = validatePairData(data.Pair)
		local validOrderTxId = checkValidAddress(data.OrderTxId)

		if not validPair or not validOrderTxId then
			local message = nil

			if not validOrderTxId then message = 'OrderTxId is not a valid address' end
			if not validPair then message = pairError or 'Error validating pair' end

			ao.send({ Target = msg.From, Action = 'Validation-Error', Tags = { Status = 'Error', Message = message or 'Error validating order cancel input' } })
			return
		end
		-- Ensure the pair exists
		local pairIndex = getPairIndex(validPair)

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
				ao.send({ Target = msg.From, Action = 'Action-Response', Tags = { Status = 'Error', Message = pairError or 'Order not found', Handler = 'Cancel-Order' } })
				return
			end

			-- Check if the sender is the order creator
			if msg.From ~= order.Creator then
				ao.send({ Target = msg.From, Action = 'Action-Response', Tags = { Status = 'Error', Message = pairError or 'Unauthorized to cancel this order', Handler = 'Cancel-Order' } })
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
					},
					Data = json.encode({
						Recipient = order.Creator,
						Quantity = order.Quantity
					})
				})

				-- Remove the order from the current table
				table.remove(Orderbook[pairIndex].Orders, orderIndex)

				ao.send({ Target = msg.From, Action = 'Action-Response', Tags = { Status = 'Success', Message = 'Order cancelled', Handler = 'Cancel-Order' } })
			else
				ao.send({ Target = msg.From, Action = 'Action-Response', Tags = { Status = 'Error', Message = pairError or 'Error cancelling order', Handler = 'Cancel-Order' } })
			end
		else
			ao.send({ Target = msg.From, Action = 'Action-Response', Tags = { Status = 'Error', Message = pairError or 'Pair not found', Handler = 'Cancel-Order' } })
		end
	else
		ao.send({
			Target = msg.From,
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
