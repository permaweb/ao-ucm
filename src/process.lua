local json = require('json')

local ucm = require('ucm')
local utils = require('utils')

-- CHANGEME
ACTIVITY_PROCESS = 'Jj8LhgFLmCE_BAMys_zoTDRx8eYXsSl3-BMBIov8n9E'
ARIO_TOKEN_PROCESS_ID = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA'

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
		-- Validate that at least one token in the trade is ARIO
		local isArioValid, arioError = utils.validateArioInTrade(msg.From, msg.Tags['X-Swap-Token'])
		if not isArioValid then
			ao.send({
				Target = msg.From,
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
			createdAt = msg.Timestamp,
			blockheight = msg['Block-Height'],
			orderType = msg.Tags['X-Order-Type'] or 'fixed',
			expirationTime = msg.Tags['X-Expiration-Time'] and tonumber(msg.Tags['X-Expiration-Time']),
			minimumPrice = msg.Tags['X-Minimum-Price'],
			decreaseInterval = msg.Tags['X-Decrease-Interval'],
			requestedOrderId = msg.Tags['X-Requested-Order-Id'],
			domain = domain
		}

		if msg.Tags['X-Price'] then
			orderArgs.price = msg.Tags['X-Price']
		end
		if msg.Tags['X-Transfer-Denomination'] then
			orderArgs.transferDenomination = msg.Tags['X-Transfer-Denomination']
		end

		if msg.Tags['X-Swap-Token'] == ARIO_TOKEN_PROCESS_ID then
			-- Fetch domain from ARIO token process
			local domainPaginatedRecords = ao.send({
				Target = ARIO_TOKEN_PROCESS_ID,
				Action = "Paginated-Records",
				Data = "",
				Tags = {
					Action = "Paginated-Records",
					Filters = string.format("{\"processId\":[\"%s\"]}", msg.From)
				}
			}).receive()
			
			local decodeCheck, domainData = utils.decodeMessageData(domainPaginatedRecords.Data)
			local domain = domainData.items[1].name
			local ownershipType = domainData.items[1].type

			if ownershipType == "lease" then
				orderArgs.leaseStartTimestamp = domainData.items[1].startTimestamp
				orderArgs.leaseEndTimestamp = domainData.items[1].endTimestamp
			end
			orderArgs.domain = domain
			orderArgs.ownershipType = ownershipType
		end

		ucm.createOrder(orderArgs)
	end
end)

Handlers.add('Cancel-Order', Handlers.utils.hasMatchingTag('Action', 'Cancel-Order'), function(msg)
	local decodeCheck, data = utils.decodeMessageData(msg.Data)

	if decodeCheck and data then
		if not data.OrderId then
			ao.send({
				Target = msg.From,
				Action = 'Input-Error',
				Tags = { Status = 'Error', Message = 'Invalid arguments, required { OrderId }' }
			})
			return
		end

		-- Get order info from activity process
		local activityQuery = ao.send({
			Target = ACTIVITY_PROCESS,
			Action = 'Get-Order-By-Id',
			Data = json.encode({ OrderId = data.OrderId }),
			Tags = {
				Action = 'Get-Order-By-Id',
				OrderId = data.OrderId,
				Functioninvoke = "true"
			}
		}).receive()

		local activityDecodeCheck, activityData = utils.decodeMessageData(activityQuery.Data)
		if not activityDecodeCheck or not activityData then
			ao.send({
				Target = msg.From,
				Action = 'Action-Response',
				Tags = { Status = 'Error', Message = 'Order not found', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' }
			})
			return
		end

		-- Check if the sender is the order creator
		if msg.From ~= activityData.Sender then
			ao.send({
				Target = msg.From,
				Action = 'Action-Response',
				Tags = { Status = 'Error', Message = 'Unauthorized to cancel this order', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' }
			})
			return
		end

		-- Block cancellation of English auctions that have bids
		if activityData.OrderType == 'english' and activityData.Bids and #activityData.Bids > 0 then
			ao.send({
				Target = msg.From,
				Action = 'Action-Response',
				Tags = {
					Status = 'Error',
					Message = 'You cannot cancel an English auction that has bids',
					['X-Group-ID'] = data['X-Group-ID'] or 'None',
					Handler = 'Cancel-Order'
				}
			})
			return
		end

		if activityData.Status ~= 'active' and activityData.Status ~= 'expired' then
			ao.send({
				Target = msg.From,
				Action = 'Action-Response',
				Tags = { Status = 'Error', Message = 'Order cannot be cancelled because it is not active or expired', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' }
			})
			return
		end

		-- Find and remove order from orderbook
		local orderFound = false
		for pairIdx, pairData in ipairs(Orderbook) do
			for orderIdx, currentOrderEntry in ipairs(pairData.Orders) do
				if data.OrderId == currentOrderEntry.Id then
					-- Return funds to the creator
					ao.send({
						Target = currentOrderEntry.Token,
						Action = 'Transfer',
						Tags = {
							Recipient = currentOrderEntry.Creator,
							Quantity = currentOrderEntry.Quantity
						}
					})

					-- Remove the order from the orderbook
					table.remove(Orderbook[pairIdx].Orders, orderIdx)
					orderFound = true
					break
				end
			end
			if orderFound then break end
		end

		if orderFound then
			ao.send({
				Target = msg.From,
				Action = 'Action-Response',
				Tags = { Status = 'Success', Message = 'Order cancelled', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' }
			})

			-- Notify activity process of cancellation
			local cancelledDataSuccess, cancelledData = pcall(function()
				return json.encode({
					Order = {
						Id = data.OrderId,
						DominantToken = activityData.DominantToken,
						SwapToken = activityData.SwapToken,
						Sender = msg.From,
						Receiver = nil,
						Quantity = tostring(activityData.Quantity),
						Price = tostring(activityData.Price),
						CreatedAt = msg.Timestamp,
						EndedAt = msg.Timestamp,
						CancellationTime = msg.Timestamp
					}
				})
			end)

			ao.send({
				Target = ACTIVITY_PROCESS,
				Action = 'Update-Cancelled-Orders',
				Data = cancelledDataSuccess and cancelledData or ''
			})
		else
			ao.send({
				Target = msg.From,
				Action = 'Action-Response',
				Tags = { Status = 'Error', Message = 'Order not found in orderbook', ['X-Group-ID'] = data['X-Group-ID'] or 'None', Handler = 'Cancel-Order' }
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
					'Data must be an object - { OrderId }')
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
						CreatedAt = order.CreatedAt
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

Handlers.add('Settle-Auction', Handlers.utils.hasMatchingTag('Action', 'Settle-Auction'), function(msg)
	print('Settling auctionXXX')
	local decodeCheck, data = utils.decodeMessageData(msg.Data)
	
	if not decodeCheck or not data.OrderId then
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Tags = { Status = 'Error', Message = 'OrderId is required' }
		})
		return
	end
	
	-- Check if order is ready for settlement by querying activity process
	local activityQuery = ao.send({
		Target = ACTIVITY_PROCESS,
		Action = 'Get-Order-By-Id',
		Tags = {
			Action = 'Get-Order-By-Id',
			OrderId = data.OrderId,
			Functioninvoke = "true"
		}
	}).receive()
	
	local activityDecodeCheck, activityData = utils.decodeMessageData(activityQuery.Data)
	if not activityDecodeCheck or not activityData then
		ao.send({
			Target = msg.From,
			Action = 'Settlement-Error',
			Tags = { Status = 'Error', Message = 'Failed to query order status' }
		})
		return
	end
	
	-- Check if order is ready for settlement
	print('Activity data: ')
	print(activityData)
	if activityData.Status ~= 'ready-for-settlement' then
		ao.send({
			Target = msg.From,
			Action = 'Settlement-Error',
			Tags = { 
				Status = 'Error', 
				Message = 'Order is not ready for settlement. Status: ' .. tostring(activityData.Status),
				CurrentStatus = tostring(activityData.Status)
			}
		})
		return
	end
	
	local settleArgs = {
		orderId = data.OrderId,
		sender = msg.From,
		timestamp = msg.Timestamp,
		orderGroupId = msg.Tags['X-Group-ID'] or 'None',
		dominantToken = data.DominantToken,
		swapToken = data.SwapToken
	}
	
	ucm.settleAuction(settleArgs)
	print('Settled auction')
end)

Handlers.add('Debit-Notice', Handlers.utils.hasMatchingTag('Action', 'Debit-Notice'), function(msg) end)

Handlers.add('Withdraw-Fees', Handlers.utils.hasMatchingTag('Action', 'Withdraw-Fees'), function(msg)
	-- Only the process owner can withdraw fees
	if msg.From ~= msg.Owner then
		ao.send({ Target = msg.From, Action = 'Validation-Error', Tags = { Status = 'Error', Message = 'Unauthorized: only process owner can withdraw fees' } })
		return
	end

	local amount = AccruedFeesAmount
	if not amount or amount == 0 then
		return
	end

	-- transfer fees to requester
	ao.send({
		Target = ARIO_TOKEN_PROCESS_ID,
		Action = 'Transfer',
		Tags = {
			Recipient = msg.From,
			Quantity = tostring(amount)
		}
	})

	AccruedFeesAmount = 0
end)
