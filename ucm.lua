local json = require('json')
local bint = require('.bint')(256)

if Name ~= 'Universal Content Marketplace' then
	Name =
	'Universal Content Marketplace'
end
if Ticker ~= 'AOPIXL' then Ticker = 'AOPIXL' end
if Denomination ~= 12 then Denomination = 12 end
if not Balances then Balances = { [ao.id] = tostring(bint(10000 * 1e12)) } end
if not Orderbook then Orderbook = {} end -- { Pair: [AssetId, TokenId], Orders: { TxId, AllowTxId, Creator, Quantity, Price }[] }[]
if not ClaimStatus then ClaimStatus = {} end

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
		return nil, 'Pair must be a list of exactly two strings - [AssetId, TokenId]'
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

local function getOrderEntryIndex(pairIndex, allowTxId)
	local orderEntryIndex = -1

	for i, existingOrderEntry in ipairs(Orderbook[pairIndex].Orders) do
		if (existingOrderEntry.AllowTxId == allowTxId) then
			orderEntryIndex = i
		end
	end

	return orderEntryIndex
end

-- Read process state
Handlers.add('Read', Handlers.utils.hasMatchingTag('Action', 'Read'),
	function(msg)
		ao.send({
			Target = msg.From,
			Data = json.encode({
				Name = Name,
				Balances = Balances,
				Orderbook = Orderbook
			})
		})
	end)

-- Add asset and token to pairs table (msg.Data - [AssetId, TokenId])
Handlers.add('Add-Pair', Handlers.utils.hasMatchingTag('Action', 'Add-Pair'),
	function(msg)
		local decodeCheck, data = decodeMessageData(msg.Data)

		if decodeCheck and data then
			local validPair, error = validatePairData(data)

			if validPair then
				-- Ensure the pair does not exist yet
				local pairIndex = getPairIndex(validPair)

				if pairIndex > -1 then
					ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'This pair already exists' } })
					return
				end

				-- Pair is valid
				table.insert(Orderbook, { Pair = validPair, Orders = {} })
				ao.send({ Target = msg.From, Tags = { Status = 'Success', Message = 'Pair added' } })
			else
				ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = error or 'Error adding pair' } })
			end
		else
			ao.send({
				Target = msg.From,
				Tags = {
					Status = 'Error',
					Message = string.format(
						'Failed to parse data, received: %s. %s.', msg.Data,
						'Data must be an object - [AssetId, TokenId]')
				}
			})
		end
	end)

-- Claim balance from token (msg.Data = { Pair: [AssetId, TokenId], AllowTxId, Quantity })
Handlers.add('Claim', Handlers.utils.hasMatchingTag('Action', 'Claim'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
		if not data.Pair or not data.AllowTxId or not data.Quantity then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Invalid arguments, required { Pair: [AssetId, TokenId], AllowTxId, Quantity }' } })
			return
		end

		-- Check if Pair, AllowTxId and Quantity are valid
		local validPair, pairError = validatePairData(data.Pair)
		local validAllowTxId = checkValidAddress(data.AllowTxId)
		local validQuantity = checkValidAmount(data.Quantity)

		if not validPair or not validAllowTxId or not validQuantity then
			local message = nil

			if not validAllowTxId then message = 'AllowTxId is not a valid address' end
			if not validQuantity then message = 'Quantity must be an integer greater than zero' end
			if not validPair then message = pairError or 'Error validating pair' end

			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = message or 'Error validating claim input' } })
			return
		end
		-- Ensure the pair exists
		local pairIndex = getPairIndex(validPair)

		-- If the pair exists then claim balance from the token, trigger claim evaluated and set claim status
		if pairIndex > -1 then
			ClaimStatus[data.AllowTxId] = {
				Status = 'Pending',
				Message = 'Claim is pending'
			}
			ao.send({
				Target = validPair[1],
				Action = 'Claim',
				Data = json.encode({
					Pair = validPair,
					AllowTxId = data.AllowTxId,
					Quantity = data.Quantity
				})
			})
			ao.send({ Target = msg.From, Tags = { Status = 'Success', Message = pairError or 'Claim sent for processing' } })
		end
	else
		ao.send({
			Target = msg.From,
			Tags = {
				Status = 'Error',
				Message = string.format('Failed to parse data, received: %s. %s',
					msg.Data,
					'Data must be an object - { Pair: [AssetId, TokenId], AllowTxId, Quantity }')
			}
		})
	end
end)

-- Get claim evaluation from asset, update corresponding order status (msg.Data = { Pair: [AssetId, TokenId], AllowTxId, Quantity })
Handlers.add('Claim-Evaluated', Handlers.utils.hasMatchingTag('Action', 'Claim-Evaluated'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
		if not data.Pair or not data.AllowTxId or not data.Quantity then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Invalid arguments, required { Pair: [AssetId, TokenId], AllowTxId, Quantity }' } })
			return
		end
		-- local validPair, pairError = validatePairData(data.Pair)

		-- Check if AllowTxId is a valid address
		if not checkValidAddress(data.AllowTxId) then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'AllowTxId is not a valid address' } })
			return
		end

		local claimStatus = msg.Tags['Status']
		local claimMessage = msg.Tags['Message']

		-- Set claim status to message from asset claim handler
		if claimStatus and claimMessage then
			ClaimStatus[data.AllowTxId] = {
				Status = claimStatus,
				Message = claimMessage
			}
		else
			ClaimStatus[data.AllowTxId] = {
				Status = 'Error',
				Message = 'Failed to evaluate claim'
			}
		end

		-- if validPair then
		-- 	-- Ensure the pair exists
		-- 	local pairIndex = getPairIndex(validPair)

		-- 	if pairIndex > -1 and #Orderbook[pairIndex].Orders > 0 and msg.Tags['Status'] then
		-- 		local claimStatus = msg.Tags['Status']
		-- 		local claimMessage = msg.Tags['Message']
		-- 		-- local orderEntryIndex = getOrderEntryIndex(pairIndex, data.AllowTxId)

		-- 		if orderEntryIndex > -1 then
		-- 			if claimStatus == 'Success' then
		-- 				-- Remove any previous claim evaluation message and set the order to active
		-- 				ClaimStatus[data.AllowTxId] = {
		-- 					Status = 'Complete',
		-- 					Message = 'Claim successfully processed'
		-- 				}
		-- 				-- Orderbook[pairIndex].Orders[orderEntryIndex].ClaimStatus = 'Complete'
		-- 			end
		-- 			if claimStatus == 'Error' then
		-- 				-- Update the claim evaluation message and remove the pending order
		-- 				ClaimStatus[data.AllowTxId] = {
		-- 					Status = 'Error',
		-- 					Message = 'Claim successfully processed'
		-- 				}
		-- 				-- ClaimStatus[data.AllowTxId] = claimMessage
		-- 				-- table.remove(Orderbook[pairIndex].Orders, orderEntryIndex)
		-- 			end
		-- 		end
		-- 	end
		-- else
		-- 	ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = pairError or 'Error validating pair' } })
		-- end
	else
		ao.send({
			Target = msg.From,
			Tags = {
				Status = 'Error',
				Message = string.format('Failed to parse data, received: %s. %s',
					msg.Data,
					'Data must be an object - { Pair: [AssetId, TokenId], AllowTxId, Quantity }')
			}
		})
	end
end)

-- Check the current status of a claim (msg.Data = { AllowTxId })
Handlers.add('Check-Claim-Status', Handlers.utils.hasMatchingTag('Action', 'Check-Claim-Status'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
		if not data.AllowTxId then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Invalid arguments, required { AllowTxId }' } })
			return
		end

		-- Check if AllowTxId is a valid address
		if not checkValidAddress(data.AllowTxId) then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'AllowTxId is not a valid address' } })
			return
		end

		-- Check if claim entry is present
		if not ClaimStatus or not ClaimStatus[data.AllowTxId] or not ClaimStatus[data.AllowTxId].Status or not ClaimStatus[data.AllowTxId].Message then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Claim not found' } })
		end

		ao.send({ Target = msg.From, Tags = { Status = ClaimStatus[data.AllowTxId].Status, Message = ClaimStatus[data.AllowTxId].Message } })
	else
		ao.send({
			Target = msg.From,
			Tags = {
				Status = 'Error',
				Message = string.format('Failed to parse data, received: %s. %s',
					msg.Data,
					'Data must be an object - { AllowTxId }')
			}
		})
	end
end)

-- Handle order entries in corresponding pair (msg.Data - { Pair: [AssetId, TokenId], AllowTxId, Quantity, Price? })
Handlers.add('Create-Order',
	Handlers.utils.hasMatchingTag('Action', 'Create-Order'), function(msg)
		local decodeCheck, data = decodeMessageData(msg.Data)

		if decodeCheck and data then
			-- Check if all required fields are present
			if not data.Pair or not data.AllowTxId or not data.Quantity then
				ao.send({
					Target = msg.From,
					Tags = {
						Status = 'Error',
						Message =
						'Invalid arguments, required { Pair: [AssetId, TokenId], AllowTxId, Quantity, Price? }'
					}
				})
				return
			end
			local validPair, pairError = validatePairData(data.Pair)

			-- TODO: Ensure there is a claim status with this allow
			-- If it is successful then handle the order and remove the claim status entry
			if validPair then
				-- Ensure the pair exists
				local pairIndex = getPairIndex(validPair)

				if pairIndex > -1 then
					-- Check if quantity is a valid integer greater than zero
					if not checkValidAmount(data.Quantity) then
						ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Quantity must be an integer greater than zero' } })
						return
					end

					-- Check if price is a valid integer greater than zero, if it is present
					if data.Price and not checkValidAmount(data.Price) then
						ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Price must be an integer greater than zero' } })
						return
					end

					-- Check if allow transaction is a valid address
					if not checkValidAddress(data.AllowTxId) then
						ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'AllowTxId must be a valid address' } })
						return
					end

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
						if validPair[1] ~= currentOrderEntry.Token and data.AllowTxId ~= currentOrderEntry.AllowTxId then
							table.insert(reverseOrders, currentOrderEntry)
						end
					end

					-- If there are no reverse orders, only push the current order entry, but first check if it is a limit order
					if #reverseOrders <= 0 then
						if orderType ~= 'Limit' then
							ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'The first order entry must be a limit order' } })
						else
							-- { Pair: [AssetId, TokenId], Orders: { Id, AllowTxId, Creator, Quantity, Token, DateCreated, ClaimStatus, OrderStatus, Price? }[] }[]
							-- ClaimStatus: 'Pending' | 'Complete'
							-- OrderStatus: 'Unfulfilled' | 'Fulfilled'
							local orderEntry = {
								Id = msg.Id,
								AllowTxId = data.AllowTxId,
								Creator = msg.From,
								Quantity = data.Quantity,
								Token = validPair[1],
								DateCreated = os.time(), -- TODO: returning 0
								ClaimStatus = 'Pending',
								OrderStatus = 'Unfulfilled',
								Price = data.Price -- Price is ensured because it is a limit order
							}

							table.insert(currentOrders, orderEntry)
							-- Orderbook[pairIndex].Orders = currentOrders
							-- ao.send({
							-- 	Target = validPair[1],
							-- 	Action = 'Claim',
							-- 	Data = json.encode({
							-- 		Pair = validPair,
							-- 		AllowTxId = data.AllowTxId,
							-- 		Quantity = data.Quantity
							-- 	})
							-- })
							ao.send({ Target = msg.From, Tags = { Status = 'Success', Message = 'Order created with pending status' } })
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

					for _, currentOrderEntry in ipairs(currentOrders) do
						if remainingQuantity <= 0 then
							-- Exit if the order is fully matched
							break
						end

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
									print('Execute foreign transfer')
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
								print('Execute foreign transfer')

								-- There are no tokens left in the current order to be matched
								currentOrderEntry.Quantity = 0
							end

							local dominantToken = Orderbook[pairIndex].Pair[1]
							local dominantPrice = (dominantToken == validPair[1]) and
								(data.Price or reversePrice) or currentOrderEntry.Price

							-- If there is a receiving amount then push the match
							if receiveFromCurrent > 0 then
								table.insert(matches,
									{ Id = currentOrderEntry.Id, Quantity = receiveFromCurrent, Price = dominantPrice })
							end

							-- If the current order is not completely filled then keep it in the orderbook
							if currentOrderEntry.Quantity ~= 0 then
								table.insert(updatedOrderbook, currentOrderEntry)
							end
						end

						-- If the claim has been evaluated then remove it
						-- if ClaimStatus[data.AllowTxId].Status ~= 'Pending' then
						-- 	ClaimStatus[data.AllowTxId] = nil
						-- end
					end

					print(currentOrders)

					-- If the input order is not completely filled, push it to the orderbook or return the funds
					if remainingQuantity > 0 then
						if orderType == 'Limit' then
							-- Push it to the orderbook
							table.insert(updatedOrderbook, {
								Price = data.Price or 0,
								Quantity = remainingQuantity,
								OriginalQuantity = data.Quantity,
								Id = msg.Id,
								AllowTxId = data.AllowTxId,
								Creator = msg.From,
								Token = validPair[1],
								DateCreated = os.time(), -- TODO: returning 0
								Status = 'Pending'
							})
						else
							-- Return the funds
							print('Execute foreign transfer')
						end
					end

					-- Send tokens to the input order creator
					print('Execute foreign transfer')

					-- Post match processing
					-- Orderbook[pairIndex].Orders = updatedOrderbook
					print(matches)
					-- ao.send({ Target = msg.From, Tags = { Status = 'Success', Message = 'Order created with pending status' } })
				else
					ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Pair not found' } })
				end
			else
				ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = pairError or 'Error validating pair' } })
			end
		else
			ao.send({
				Target = msg.From,
				Tags = {
					Status = 'Error',
					Message = string.format('Failed to parse data, received: %s. %s',
						msg.Data,
						'Data must be an object - { Pair: [AssetId, TokenId], AllowTxId, Quantity, Price? }')
				}
			})
		end
	end)

-- Check status of order (msg.Data - { Pair: [AssetId, TokenId], AllowTxId })
Handlers.add('Check-Order-Status', Handlers.utils.hasMatchingTag('Action', 'Check-Order-Status'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
		if not data.Pair or not data.AllowTxId then
			ao.send({
				Target = msg.From,
				Tags = {
					Status = 'Error',
					Message =
					'Invalid arguments, required { Pair: [AssetId, TokenId], AllowTxId }'
				}
			})
			return
		end
		local validPair, pairError = validatePairData(data.Pair)

		if validPair then
			-- Ensure the pair exists
			local pairIndex = getPairIndex(validPair)

			-- If there are orders against the asset, find the current order by its allow tx and update its status based on claim status
			if pairIndex > -1 and #Orderbook[pairIndex].Orders > 0 then
				local orderEntryIndex = getOrderEntryIndex(pairIndex, data.AllowTxId)

				if orderEntryIndex > -1 then
					if Orderbook[pairIndex].Orders[orderEntryIndex].Status == 'Active' then
						ao.send({ Target = msg.From, Tags = { Status = 'Success', Message = 'Order is active' } })
					elseif Orderbook[pairIndex].Orders[orderEntryIndex].Status == 'Pending' then
						ao.send({ Target = msg.From, Tags = { Status = 'Pending', Message = 'Orderbook claim required' } })
					else
						ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Order is invalid' } })
					end
				else
					ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = ClaimStatus[data.AllowTxId] or 'Order not found' } })
				end
			else
				ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = ClaimStatus[data.AllowTxId] or 'Order not found' } })
			end
		else
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = pairError or 'Error validating pair' } })
		end
	else
		ao.send({
			Target = msg.From,
			Tags = {
				Status = 'Error',
				Message = string.format('Failed to parse data, received: %s. %s',
					msg.Data,
					'Data must be an object - { Pair: [AssetId, TokenId], AllowTxId }')
			}
		})
	end
end)
