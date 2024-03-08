local json = require('json')
local bint = require('.bint')(256)

if Name ~= 'Universal Content Marketplace' then
	Name =
	'Universal Content Marketplace'
end
if Ticker ~= 'AOPIXL' then Ticker = 'AOPIXL' end
if Denomination ~= 12 then Denomination = 12 end
if not Balances then Balances = { [ao.id] = tostring(bint(10000 * 1e12)) } end
if not Pairs then Pairs = {} end -- { Ids: [AssetId, TokenId], DateCreated, Orders: { TxId, AllowTxId, Quantity, Price, DateCreated }[] }[]

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
				Pairs = Pairs
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
				for _, existingPair in ipairs(Pairs) do
					if (existingPair.Ids[1] == validPair[1] and existingPair.Ids[2] == validPair[2]) then
						ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'This pair already exists' } })
						return
					end
				end

				-- Pair is valid
				table.insert(Pairs, { Ids = validPair, Orders = {} })
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

-- Create order entry in corresponding pair (msg.Data - { Pair: [AssetId, TokenId], AllowTxId, Quantity, Price })
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
				for _, existingPair in ipairs(Pairs) do
					if (existingPair.Ids[1] == validPair[1] and existingPair.Ids[2] == validPair[2]) then
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

					-- Send message to asset process, find claim by tx id and update balances (+= msg.From), if claim.To ~= msg.From error out, listen in asset for Claim action
					ao.send({
						Target = validPair[1],
						Action = 'Claim',
						Data = json.encode({
							AllowTxId = data.AllowTxId,
							Quantity = data.Quantity,
							Client = msg.From
						})
					})
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
						'Data must be an object - { Pair: [AssetId: string, TokenId: string], AllowTxId: string, Quantity: number, Price: number }')
				}
			})
		end
	end)

-- Get claim processing from asset, return status to sender of create order (client) (msg.Data = { Client })
Handlers.add('Claim-Evaluated', Handlers.utils.hasMatchingTag('Action', 'Claim-Evaluated'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
		if not data.Client then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Invalid arguments, required { Client }' } })
			return
		end

		if msg.Tags['Status'] then
			local claimStatus = msg.Tags['Status']
			local claimMessage = msg.Tags['Message']

			if claimStatus == 'Success' then
				-- TODO: match and add order object to pair
				ao.send({ Target = data.Client, Tags = { Status = 'Success', Message = 'Order created' } })
			elseif claimStatus == 'Error' then
				ao.send({ Target = data.Client, Tags = { Status = 'Error', Message = claimMessage or 'Error processing claim' } })
			else
				ao.send({ Target = data.Client, Tags = { Status = 'Error', Message = claimMessage or 'Incorrect response received from claim, aborting order create' } })
			end
		else
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'No response received from claim, aborting order create' } })
		end
	else
		ao.send({
			Target = msg.From,
			Tags = {
				Status = 'Error',
				Message = string.format('Failed to parse data, received: %s. %s',
					msg.Data,
					'Data must be an object - { Client }')
			}
		})
	end
end)
