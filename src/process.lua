local json = require('json')

local ucm = require('ucm')
local utils = require('utils')

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

Handlers.prepend('qualify message',
	Trusted,
	function(msg)
		print('This Msg is not trusted!')
	end
)

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

Handlers.add('Get-Orderbook-By-Pair', Handlers.utils.hasMatchingTag('Action', 'Get-Orderbook-By-Pair'),
	function(msg)
		if not msg.Tags.DominantToken or not msg.Tags.SwapToken then return end
		local pairIndex = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })

		if pairIndex > -1 then
			ao.send({
				Target = msg.From,
				Action = 'Read-Success',
				Data = json.encode({ Orderbook = Orderbook[pairIndex] })
			})
		end
	end)

Handlers.add('Credit-Notice', Handlers.utils.hasMatchingTag('Action', 'Credit-Notice'), function(msg)
	if not msg.Tags['X-Dominant-Token'] or msg.From ~= msg.Tags['X-Dominant-Token'] then return end

	local data = {
		Sender = msg.Tags.Sender,
		Quantity = msg.Tags.Quantity
	}

	-- Check if sender is a valid address
	if not utils.checkValidAddress(data.Sender) then
		ao.send({ Target = msg.From, Action = 'Validation-Error', Tags = { Status = 'Error', Message = 'Sender must be a valid address' } })
		return
	end

	-- Check if quantity is a valid integer greater than zero
	if not utils.checkValidAmount(data.Quantity) then
		ao.send({ Target = msg.From, Action = 'Validation-Error', Tags = { Status = 'Error', Message = 'Quantity must be an integer greater than zero' } })
		return
	end

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
			blockheight = msg['Block-Height']
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

Handlers.add('Migrate-Listings', Handlers.utils.hasMatchingTag('Action', 'Migrate-Listings'), function(msg)
	if not msg.Data.MigrateTo then
		print('MigrateTo must be provided')
		return
	end

	for _, pair in ipairs(Orderbook) do
		for _, existingOrder in ipairs(pair.Orders) do
			if existingOrder.Creator == msg.From then
				print('Changing order creator to ' .. msg.Data.MigrateTo)
				existingOrder.Creator = msg.Data.MigrateTo
			end
		end
	end
end)

Handlers.add('Cancel-Order', Handlers.utils.hasMatchingTag('Action', 'Cancel-Order'), function(msg)
	local decodeCheck, data = utils.decodeMessageData(msg.Data)

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
		local validPair, pairError = utils.validatePairData(data.Pair)
		local validOrderTxId = utils.checkValidAddress(data.OrderTxId)

		if not validPair or not validOrderTxId then
			local message = nil

			if not validOrderTxId then message = 'OrderTxId is not a valid address' end
			if not validPair then message = pairError or 'Error validating pair' end

			ao.send({ Target = msg.From, Action = 'Validation-Error', Tags = { Status = 'Error', Message = message or 'Error validating order cancel input' } })
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
				ao.send({ Target = msg.From, Action = 'Action-Response', Tags = { Status = 'Error', Message = pairError or 'Order not found', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' } })
				return
			end

			-- Check if the sender is the order creator
			if msg.From ~= order.Creator then
				ao.send({ Target = msg.From, Action = 'Action-Response', Tags = { Status = 'Error', Message = pairError or 'Unauthorized to cancel this order', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' } })
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

				ao.send({ Target = msg.From, Action = 'Action-Response', Tags = { Status = 'Success', Message = 'Order cancelled', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' } })

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
				ao.send({ Target = msg.From, Action = 'Action-Response', Tags = { Status = 'Error', Message = pairError or 'Error cancelling order', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' } })
			end
		else
			ao.send({ Target = msg.From, Action = 'Action-Response', Tags = { Status = 'Error', Message = pairError or 'Pair not found', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' } })
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

Handlers.add('Read-Orders', Handlers.utils.hasMatchingTag('Action', 'Read-Orders'), function(msg)
	if msg.From == ao.id then
		local readOrders = {}
		local pairIndex = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })

		print('Pair index: ' .. pairIndex)

		if pairIndex > -1 then
			for i, order in ipairs(Orderbook[pairIndex].Orders) do
				if not msg.Tags.Creator or order.Creator == msg.Tags.Creator then
					table.insert(readOrders, {
						index = i,
						id = order.Id,
						creator = order.Creator,
						quantity = order.Quantity,
						price = order.Price,
						timestamp = order.Timestamp
					})
				end
			end

			ao.send({
				Target = msg.From,
				Action = 'Read-Orders-Response',
				Data = json.encode(readOrders)
			})
		end
	end
end)

Handlers.add('Read-Pair', Handlers.utils.hasMatchingTag('Action', 'Read-Pair'), function(msg)
	local pairIndex = ucm.getPairIndex({ msg.Tags.DominantToken, msg.Tags.SwapToken })
	if pairIndex > -1 then
		ao.send({
			Target = msg.From,
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

Handlers.add('Get-Active-Pairs', Handlers.utils.hasMatchingTag('Action', 'Get-Active-Pairs'), function(msg)
	local activePairs = {}

	for _, pair in ipairs(Orderbook) do
		if #pair.Orders > 0 then
			table.insert(activePairs, {
				DominantToken = pair.DominantToken,
				SwapToken = pair.SwapToken,
				OrderCount = #pair.Orders
			})

			-- print(pair.Orders)
		end
	end

	print(#activePairs .. ' active pairs found')

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode({ ActivePairs = activePairs })
	})
end)
