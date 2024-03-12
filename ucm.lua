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
				-- Ensure the pair does not exist
				for _, existingOrders in ipairs(Orderbook) do
					if (existingOrders.Pair[1] == validPair[1] and existingOrders.Pair[2] == validPair[2]) then
						ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'This pair already exists' } })
						return
					end
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

-- Create order entry in corresponding pair (msg.Data - { Pair: [AssetId, TokenId], AllowTxId, Quantity, Price? })
Handlers.add('Create-Order',
	Handlers.utils.hasMatchingTag('Action', 'Create-Order'), function(msg)
		local decodeCheck, data = decodeMessageData(msg.Data)

		if decodeCheck and data then
			-- Check if all fields are present
			if not data.Pair or not data.AllowTxId or not data.Quantity or not data.Price then
				ao.send({
					Target = msg.From,
					Tags = {
						Status = 'Error',
						Message =
						'Invalid arguments, required { Pair: [AssetId, TokenId], AllowTxId, Quantity, Price }'
					}
				})
				return
			end
			local validPair, pairError = validatePairData(data.Pair)

			if validPair then
				-- Ensure the pair exists
				local pairExists = false
				for _, existingOrders in ipairs(Orderbook) do
					if (existingOrders.Pair[1] == validPair[1] and existingOrders.Pair[2] == validPair[2]) then
						pairExists = true
					end
				end

				if pairExists then
					-- Check if quantity is a valid integer greater than zero
					if not checkValidAmount(data.Quantity) then
						ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Quantity must be an integer greater than zero' } })
						return
					end

					-- Check if price is a valid integer greater than zero
					if not checkValidAmount(data.Price) then
						ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Price must be an integer greater than zero' } })
						return
					end

					-- Check if allow transaction is a valid address
					if not checkValidAddress(data.AllowTxId) then
						ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'AllowTxId must be a valid address' } })
						return
					end

					-- Create order entry with pending status
					local order = {
						AllowTxId = data.AllowTxId,
						Creator = msg.From,
						Quantity = data.Quantity,
						DateCreated = os.time(), -- TODO: returning 0
						Status = 'Pending'
					}

					-- Price is not required for market orders
					if data.Price then order.Price = data.Price end

					local pairIndex = -1
					for i, existingOrders in ipairs(Orderbook) do
						if (existingOrders.Pair[1] == data.Pair[1] and existingOrders.Pair[2] == data.Pair[2]) then
							pairIndex = i
						end
					end

					-- If there are no existing orders against the asset, only push the sell order
					if #Orderbook[pairIndex].Orders <= 0 then
						table.insert(Orderbook[pairIndex].Orders, order)
						-- TODO: price is not required for market orders
						-- Send message to asset process, find claim by AllowTxId and update balances
						ao.send({
							Target = validPair[1],
							Action = 'Claim',
							Data = json.encode({
								Pair = validPair,
								AllowTxId = data.AllowTxId,
								Quantity = data.Quantity,
								Price = data.Price,
								Client = msg.From
							})
						})
						ao.send({ Target = msg.From, Tags = { Status = 'Success', Message = 'Order created with pending status' } })
						return
					end
					-- TODO: If the order has matches, calculate latest price and push logs, then remove from the orders table
					ao.send({ Target = msg.From, Tags = { Status = 'Success', Message = 'Order created with pending status' } })
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
						'Data must be an object - { Pair: [AssetId, TokenId], AllowTxId, Quantity, Price }')
				}
			})
		end
	end)

-- Orderbook: { Pair: [AssetId, TokenId], DateCreated, Orders: { TxId, AllowTxId, Creator, Quantity, Price }[] }[]
-- Get claim processing from asset, return status to sender of create order (client) (msg.Data = { Pair: [AssetId, TokenId], AllowTxId, Quantity, Price?, Client })
Handlers.add('Claim-Evaluated', Handlers.utils.hasMatchingTag('Action', 'Claim-Evaluated'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
		if not data.Pair or not data.AllowTxId or not data.Quantity or not data.Client then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Invalid arguments, required { Pair: [AssetId, TokenId], AllowTxId, Quantity, Price?, Client }' } })
			return
		end

		if msg.Tags['Status'] then
			local claimStatus = msg.Tags['Status']
			-- local claimMessage = msg.Tags['Message']

			local pairIndex = -1
			for i, existingOrders in ipairs(Orderbook) do
				if (existingOrders.Pair[1] == data.Pair[1] and existingOrders.Pair[2] == data.Pair[2]) then
					pairIndex = i
				end
			end

			-- If there are orders against the asset, find the current order by its allow tx and update its status based on claim status
			if pairIndex > -1 and #Orderbook[pairIndex].Orders > 0 then
				local currentIndex = -1
				for i, existingOrders in ipairs(Orderbook[pairIndex].Orders) do
					if (existingOrders.AllowTxId == data.AllowTxId) then
						currentIndex = i
					end
				end

				if currentIndex > -1 then
					if claimStatus == 'Success' then
						Orderbook[pairIndex].Orders[currentIndex].Status = 'Active'
					elseif claimStatus == 'Error' then
						-- print('Error processing claim')
						table.remove(Orderbook[pairIndex].Orders, currentIndex)
						-- ao.send({ Target = data.Client, Tags = { Status = 'Error', Message = claimMessage or 'Error processing claim' } })
					else
						-- Remove order
						-- print('Incorrect response received from claim, aborting order create')
						table.remove(Orderbook[pairIndex].Orders, currentIndex)
						-- ao.send({ Target = data.Client, Tags = { Status = 'Error', Message = claimMessage or 'Incorrect response received from claim, aborting order create' } })
					end
				else
					print('Order by allow not found, aborting')
				end
			end
		end
	else
		ao.send({
			Target = msg.From,
			Tags = {
				Status = 'Error',
				Message = string.format('Failed to parse data, received: %s. %s',
					msg.Data,
					'Data must be an object - { Pair: [AssetId, TokenId], AllowTxId, Quantity, Price?, Client }')
			}
		})
	end
end)

-- Check status of ordfer (msg.Data - { Pair: [AssetId, TokenId], AllowTxId })
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
			local pairIndex = -1
			for i, existingOrders in ipairs(Orderbook) do
				if (existingOrders.Pair[1] == data.Pair[1] and existingOrders.Pair[2] == data.Pair[2]) then
					pairIndex = i
				end
			end

			-- If there are orders against the asset, find the current order by its allow tx and update its status based on claim status
			if pairIndex > -1 and #Orderbook[pairIndex].Orders > 0 then
				local currentIndex = -1
				for i, existingOrders in ipairs(Orderbook[pairIndex].Orders) do
					if (existingOrders.AllowTxId == data.AllowTxId) then
						currentIndex = i
					end
				end

				if currentIndex > -1 then
					if Orderbook[pairIndex].Orders[currentIndex].Status == 'Active' then
						ao.send({ Target = msg.From, Tags = { Status = 'Success', Message = 'Order is active' } })
					elseif Orderbook[pairIndex].Orders[currentIndex].Status == 'Pending' then
						ao.send({ Target = msg.From, Tags = { Status = 'Pending', Message = 'Orderbook claim required' } })
					else
						ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Order is invalid' } })
					end
				else
					ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Order not found' } })
				end
			else
				ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Order not found' } })
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
