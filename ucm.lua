local json = require('json')
local bint = require('.bint')(256)

if Name ~= 'Universal Content Marketplace' then Name = 'Universal Content Marketplace' end

-- Orderbook {
-- 	Pair [TokenId, TokenId],
-- 	Orders {
-- 		Id,
-- 		DepositTxId,
-- 		Creator,
-- 		Quantity,
-- 		OriginalQuantity,
-- 		Token,
-- 		DateCreated,
-- 		Price?
-- 	} []
-- } []

if not Orderbook then Orderbook = {} end

-- Deposits {
-- 	Owner {
-- 		DepositTxId,
-- 		Quantity
-- 	} []
-- } []

if not Deposits then Deposits = {} end

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

local function getDepositIndex(owner, depositTxId)
	local depositIndex = -1

	if not Deposits[owner] then return depositIndex end
	for i, existingDeposit in ipairs(Deposits[owner]) do
		if (existingDeposit.DepositTxId == depositTxId) then
			depositIndex = i
		end
	end

	return depositIndex
end

local function handleRemoveDeposit(target, depositTxId)
	-- If there is an open deposit then remove it
	-- Check if the deposit entry exists by index
	if target and checkValidAddress(target) and depositTxId and checkValidAddress(depositTxId) then
		local depositIndex = getDepositIndex(target, depositTxId)

		if Deposits[target] and Deposits[target][depositIndex] then
			table.remove(Deposits[target], depositIndex)

			-- If the owner no longer has any deposits then remove the entry
			if #Deposits[target] <= 0 then
				Deposits[target] = nil
			end
		end
	end
end

local function handleError(args) -- Target, DepositTxId, TransferToken, Quantity
	-- If the deposit entry is present then remove it
	handleRemoveDeposit(args.Target, args.DepositTxId)

	-- If there is a valid quantity then return the funds
	if args.TransferToken and args.Quantity and checkValidAmount(args.Quantity) then
		ao.send({
			Target = args.TransferToken,
			Action = 'Transfer',
			Data = json.encode({
				Recipient = args.Target,
				Quantity = args.Quantity
			})
		})
	end
	ao.send({ Target = args.Target, Action = args.Action, Tags = { Status = 'Error', Message = args.Message } })
end

-- Read process state
Handlers.add('Info', Handlers.utils.hasMatchingTag('Action', 'Info'),
	function(msg)
		ao.send({
			Target = msg.From,
			Action = 'Read-Success',
			Data = json.encode({
				Name = Name,
				Orderbook = Orderbook,
				Deposits = Deposits
			})
		})
	end)

-- Add credit notice to the deposits table (Data - { Sender, Quantity })
Handlers.add('Credit-Notice', Handlers.utils.hasMatchingTag('Action', 'Credit-Notice'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
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

		-- If the sender has no open deposits then create a table entry
		if not Deposits[data.Sender] then Deposits[data.Sender] = {} end

		-- Enter the transfer information into the deposits table
		table.insert(Deposits[data.Sender], {
			DepositTxId = msg['Pushed-For'],
			Quantity = tostring(data.Quantity),
		})
	else
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Tags = {
				Status = 'Error',
				Message = string.format(
					'Failed to parse data, received: %s. %s.', msg.Data,
					'Data must be an object - { Sender, Quantity }')
			}
		})
	end
end)

-- Check the status of a transfer credit by DepositTxId (Data - { Pair: [TokenId, TokenId], DepositTxId, Quantity })
Handlers.add('Check-Deposit-Status', Handlers.utils.hasMatchingTag('Action', 'Check-Deposit-Status'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
		-- Check if all required fields are present
		if not data.Pair or not data.DepositTxId or not data.Quantity then
			ao.send({
				Target = msg.From,
				Action = 'Input-Error',
				Tags = {
					Status = 'Error',
					Message =
					'Invalid arguments, required { Pair: [TokenId, TokenId], DepositTxId, Quantity }'
				}
			})
			return
		end
		local validPair, pairError = validatePairData(data.Pair)

		if validPair then
			-- Get the current token to execute on, it will always be the first in the pair
			local currentToken = validPair[1]

			-- Check if deposit transaction is a valid address
			if not checkValidAddress(data.DepositTxId) then
				handleError({
					Target = msg.From,
					Action = 'Validation-Error',
					Message = 'DepositTxId must be a valid address',
					Quantity = data.Quantity,
					TransferToken = currentToken,
					DepositTxId = data.DepositTxId
				})
				return
			end

			-- Check if quantity is a valid integer greater than zero
			if not checkValidAmount(data.Quantity) then
				handleError({
					Target = msg.From,
					Action = 'Validation-Error',
					Message = 'Quantity must be an integer greater than zero',
					Quantity = data.Quantity,
					TransferToken = currentToken,
					DepositTxId = data.DepositTxId
				})
				return
			end

			-- Check if the deposit exists
			local depositIndex = getDepositIndex(msg.From, data.DepositTxId)

			if depositIndex > -1 then
				ao.send({ Target = msg.From, Action = 'Deposit-Status-Evaluated', Tags = { Status = 'Success', Message = 'Deposit is complete' } })
			else
				handleError({
					Target = msg.From,
					Action = 'Deposit-Status-Evaluated',
					Message = 'Deposit not found',
					Quantity = data.Quantity,
					TransferToken = currentToken,
					DepositTxId = data.DepositTxId
				})
			end
		else
			handleError({
				Target = msg.From,
				Action = 'Deposit-Status-Evaluated',
				Message = pairError or 'Error validating pair',
				Quantity = data.Quantity,
				TransferToken = nil, -- Pair can not be validated, no token to return
				DepositTxId = data.DepositTxId
			})
		end
	else
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Tags = {
				Status = 'Error',
				Message = string.format(
					'Failed to parse data, received: %s. %s.', msg.Data,
					'Data must be an object - { Pair: [TokenId, TokenId], DepositTxId, Quantity }')
			}
		})
	end
end)

-- Handle order entries in corresponding pair (Data - { Pair: [TokenId, TokenId], DepositTxId, Quantity, Price? })
Handlers.add('Create-Order',
	Handlers.utils.hasMatchingTag('Action', 'Create-Order'), function(msg)
		local decodeCheck, data = decodeMessageData(msg.Data)

		if decodeCheck and data then
			-- Check if all required fields are present
			if not data.Pair or not data.DepositTxId or not data.Quantity then
				ao.send({
					Target = msg.From,
					Action = 'Input-Error',
					Tags = {
						Status = 'Error',
						Message =
						'Invalid arguments, required { Pair: [TokenId, TokenId], DepositTxId, Quantity, Price? }'
					}
				})
				return
			end
			local validPair, pairError = validatePairData(data.Pair)

			-- If the pair is valid then handle the order and remove the claim status entry
			if validPair then
				-- Get the current token to execute on, it will always be the first in the pair
				local currentToken = validPair[1]

				-- Check if the deposit entry exists by index
				local depositIndex = getDepositIndex(msg.From, data.DepositTxId)

				-- Ensure the pair exists
				local pairIndex = getPairIndex(validPair)

				-- If the pair does not exist yet then add it
				if pairIndex == -1 then
					table.insert(Orderbook, { Pair = validPair, Orders = {} })
					pairIndex = getPairIndex(validPair)
				end

				-- Check if deposit transaction is a valid address
				if not checkValidAddress(data.DepositTxId) then
					handleError({
						Target = msg.From,
						Action = 'Validation-Error',
						Message = 'DepositTxId must be a valid address',
						Quantity = data.Quantity,
						TransferToken = currentToken,
						DepositTxId = data.DepositTxId
					})
					return
				end

				-- Check if quantity is a valid integer greater than zero
				if not checkValidAmount(data.Quantity) then
					handleError({
						Target = msg.From,
						Action = 'Validation-Error',
						Message = 'Quantity must be an integer greater than zero',
						Quantity = data.Quantity,
						TransferToken = currentToken,
						DepositTxId = data.DepositTxId
					})
					return
				end

				-- Check if price is a valid integer greater than zero, if it is present
				if data.Price and not checkValidAmount(data.Price) then
					handleError({
						Target = msg.From,
						Action = 'Validation-Error',
						Message = 'Price must be an integer greater than zero',
						Quantity = data.Quantity,
						TransferToken = currentToken,
						DepositTxId = data.DepositTxId
					})
					return
				end

				-- Check if the deposit entry exists
				if depositIndex == -1 then
					handleError({
						Target = msg.From,
						Action = 'Deposit-Error',
						Message = 'Deposit not found',
						Quantity = data.Quantity,
						TransferToken = currentToken,
						DepositTxId = data.DepositTxId
					})
					return
				end

				if pairIndex > -1 then
					-- Find order matches and update the orderbook
					local orderType = nil
					local reverseOrders = {}
					local currentOrders = Orderbook[pairIndex].Orders
					local updatedOrderbook = {}
					local matches = {}

					-- Determine order type based on if price is passed
					if data.Price then
						orderType = 'Limit'
					else
						orderType = 'Market'
					end

					-- Sort order entries based on price
					table.sort(currentOrders, function(a, b)
						if a.Price and b.Price then
							return bint(a.Price) < bint(b.Price)
						else
							return true
						end
					end)

					-- Find reverse orders for potential matches
					for _, currentOrderEntry in ipairs(currentOrders) do
						if currentToken ~= currentOrderEntry.Token and data.DepositTxId ~= currentOrderEntry.DepositTxId then
							table.insert(reverseOrders, currentOrderEntry)
						end
					end

					-- If there are no reverse orders, only push the current order entry, but first check if it is a limit order
					if #reverseOrders <= 0 then
						if orderType ~= 'Limit' then
							handleError({
								Target = msg.From,
								Action = 'Order-Error',
								Message = 'The first order entry must be a limit order',
								Quantity = data.Quantity,
								TransferToken = currentToken,
								DepositTxId = data.DepositTxId
							})
						else
							table.insert(currentOrders, {
								Id = msg.Id,
								DepositTxId = data.DepositTxId,
								Creator = msg.From,
								Quantity = tostring(data.Quantity),
								OriginalQuantity = tostring(data.Quantity),
								Token = currentToken,
								DateCreated = tostring(msg.Timestamp),
								Price = tostring(data.Price) -- Price is ensured because it is a limit order
							})

							-- Remove the deposit entry
							handleRemoveDeposit(msg.From, data.DepositTxId)

							ao.send({ Target = msg.From, Action = 'Order-Success', Tags = { Status = 'Success', Message = 'Order created' } })
						end
						return
					end

					-- The total amount of tokens the user would receive if it is a market order
					-- This changes for each order in the orderbook
					-- If it is a limit order, it will always be the same
					local fillAmount = 0

					-- The total amount of tokens the user of the input order will receive
					local receiveAmount = 0

					-- The remaining tokens to be matched with an order
					local remainingQuantity = tonumber(data.Quantity)

					-- The dominant token from the pair, it will always be the first one
					local dominantToken = Orderbook[pairIndex].Pair[1]

					for _, currentOrderEntry in ipairs(currentOrders) do
						-- Price of the current order reversed to the input token
						local reversePrice = 1 / tonumber(currentOrderEntry.Price)

						if orderType == 'Limit' and data.Price and tonumber(data.Price) ~= reversePrice then
							-- Continue if the current order price matches the input order price and it is a limit order
							table.insert(updatedOrderbook, currentOrderEntry)
						else
							-- The input order creator receives this many tokens from the current order
							local receiveFromCurrent = 0

							-- Set the total amount of tokens to be received
							fillAmount = math.floor(remainingQuantity * (tonumber(data.Price) or reversePrice))

							if fillAmount <= tonumber(currentOrderEntry.Quantity) then
								-- The input order will be completely filled
								-- Calculate the receiving amount
								receiveFromCurrent = math.floor(remainingQuantity * reversePrice)

								-- Reduce the current order quantity
								currentOrderEntry.Quantity = tonumber(currentOrderEntry.Quantity) - fillAmount

								-- Fill the remaining tokens
								receiveAmount = receiveAmount + receiveFromCurrent

								-- Send tokens to the current order creator
								if remainingQuantity > 0 then
									ao.send({
										Target = currentToken,
										Action = 'Transfer',
										Data = json.encode({
											Recipient = currentOrderEntry.Creator,
											Quantity = remainingQuantity
										})
									})
								end

								-- There are no tokens left in the order to be matched
								remainingQuantity = 0
							else
								-- The input order will be partially filled
								-- Calculate the receiving amount
								receiveFromCurrent = tonumber(currentOrderEntry.Quantity) or 0

								-- Add all the tokens from the current order to fill the input order
								receiveAmount = receiveAmount + receiveFromCurrent

								-- The amount the current order creator will receive
								local sendAmount = receiveFromCurrent * tonumber(currentOrderEntry.Price)

								-- Reduce the remaining tokens to be matched by the amount the user is going to receive from this order
								remainingQuantity = remainingQuantity - sendAmount
								
								-- Send tokens to the current order creator
								ao.send({
									Target = currentToken,
									Action = 'Transfer',
									Data = json.encode({
										Recipient = currentOrderEntry.Creator,
										Quantity = sendAmount
									})
								})

								-- There are no tokens left in the current order to be matched
								currentOrderEntry.Quantity = 0
							end

							-- Calculate the dominant token price
							local dominantPrice = (dominantToken == currentToken) and
								(data.Price or reversePrice) or currentOrderEntry.Price

							-- If there is a receiving amount then push the match
							if receiveFromCurrent > 0 then
								table.insert(matches,
									{
										Id = currentOrderEntry.Id,
										Quantity = tostring(receiveFromCurrent),
										Price =
											dominantPrice
									})
							end

							-- If the current order is not completely filled then keep it in the orderbook
							if tonumber(currentOrderEntry.Quantity) ~= 0 then
								-- Reassign quantity as a string
								currentOrderEntry.Quantity = tostring(currentOrderEntry.Quantity)

								table.insert(updatedOrderbook, currentOrderEntry)
							end
						end

						-- Remove the deposit entry
						handleRemoveDeposit(msg.From, data.DepositTxId)
					end

					-- If the input order is not completely filled, push it to the orderbook if it is a limit order or return the funds
					if remainingQuantity > 0 then
						if orderType == 'Limit' then
							-- Push it to the orderbook
							table.insert(updatedOrderbook, {
								Id = msg.Id,
								DepositTxId = data.DepositTxId,
								Quantity = tostring(remainingQuantity),
								OriginalQuantity = tostring(data.Quantity),
								Creator = msg.From,
								Token = currentToken,
								DateCreated = tostring(msg.Timestamp),
								Price = tostring(data.Price), -- Price is ensured because it is a limit order
							})
						else
							-- Return the funds
							ao.send({
								Target = currentToken,
								Action = 'Transfer',
								Data = json.encode({
									Recipient = msg.From,
									Quantity = remainingQuantity
								})
							})
						end
					end

					-- Send transfer tokens to the input order creator
					ao.send({
						Target = validPair[2],
						Action = 'Transfer',
						Data = json.encode({
							Recipient = msg.From,
							Quantity = receiveAmount
						})
					})

					-- Post match processing
					Orderbook[pairIndex].Orders = updatedOrderbook

					-- TODO: error if maxPrice < maxBid

					if #matches > 0 then
						-- Calculate the volume weighted average price
						-- (Volume1 * Price1 + Volume2 * Price2 + ...) / (Volume1 + Volume2 + ...)
						local sumVolumePrice = 0
						local sumVolume = 0

						for _, match in ipairs(matches) do
							local volume = tonumber(match.Quantity)
							local price = tonumber(match.Price)

							sumVolumePrice = sumVolumePrice + (volume * price)
							sumVolume = sumVolume + volume
						end

						local vwap = sumVolumePrice / sumVolume

						Orderbook[pairIndex].PriceData = {
							Vwap = tostring(vwap),
							Block = tostring(msg['Block-Height']),
							DominantToken = dominantToken,
							MatchLogs = matches
						}
					else
						Orderbook[pairIndex].PriceData = nil
					end

					-- If orders and price data are both empty in the pair then remove it -- TODO

					ao.send({ Target = msg.From, Action = 'Order-Success', Tags = { Status = 'Success', Message = 'Order created' } })
				else
					handleError({
						Target = msg.From,
						Action = 'Order-Error',
						Message = 'Pair not found',
						Quantity = data.Quantity,
						TransferToken = currentToken,
						DepositTxId = data.DepositTxId
					})
				end
			else
				handleError({
					Target = msg.From,
					Action = 'Order-Error',
					Message = pairError or 'Error validating pair',
					Quantity = data.Quantity,
					TransferToken = nil, -- Pair can not be validated, no token to return
					DepositTxId = data.DepositTxId
				})
			end
		else
			ao.send({
				Target = msg.From,
				Action = 'Input-Error',
				Tags = {
					Status = 'Error',
					Message = string.format('Failed to parse data, received: %s. %s',
						msg.Data,
						'Data must be an object - { Pair: [TokenId, TokenId], DepositTxId, Quantity, Price? }')
				}
			})
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
				ao.send({ Target = msg.From, Action = 'Order-Cancel-Error', Tags = { Status = 'Error', Message = pairError or 'Order not found' } })
				return
			end

			-- Check if the sender is the order creator
			if msg.From ~= order.Creator then
				ao.send({ Target = msg.From, Action = 'Order-Cancel-Error', Tags = { Status = 'Error', Message = pairError or 'Sender is not the creator of the order' } })
				return
			end

			if order and orderIndex > -1 then
				-- Return funds to the creator
				ao.send({
					Target = order.Token,
					Action = 'Transfer',
					Data = json.encode({
						Recipient = order.Creator,
						Quantity = order.Quantity
					})
				})

				-- Remove the order from the current table
				table.remove(Orderbook[pairIndex].Orders, orderIndex)

				ao.send({ Target = msg.From, Action = 'Order-Cancel-Success', Tags = { Status = 'Success', Message = pairError or 'Order cancelled' } })
			else
				ao.send({ Target = msg.From, Action = 'Order-Cancel-Error', Tags = { Status = 'Error', Message = pairError or 'Error cancelling order' } })
			end
		else
			ao.send({ Target = msg.From, Action = 'Order-Cancel-Error', Tags = { Status = 'Error', Message = pairError or 'Pair not found' } })
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
