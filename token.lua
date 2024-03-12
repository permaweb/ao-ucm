local bint = require('.bint')(256)
local json = require('json')

if Name ~= 'Rai' then Name = 'Rai' end
if Ticker ~= 'RAI' then Ticker = 'RAI' end
if Denomination ~= 12 then Denomination = 12 end
if not Balances then Balances = { [Owner] = tostring(bint(10000 * 1e12)) } end
if not Claimable then Claimable = {} end

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

local function validateRecipientData(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if not decodeCheck or not data then
		return nil, string.format('Failed to parse data, received: %s. %s.', msg.Data,
			'Data must be an object - { Recipient: string, Quantity: number }')
	end

	-- Check if recipient and quantity are present
	if not data.Recipient or not data.Quantity then
		return nil, 'Invalid arguments, required { Recipient: string, Quantity: number }'
	end

	-- Check if recipient is a valid address
	if not checkValidAddress(data.Recipient) then
		return nil, 'Recipient must be a valid address'
	end

	-- Check if quantity is a valid integer greater than zero
	if not checkValidAmount(data.Quantity) then
		return nil, 'Quantity must be an integer greater than zero'
	end

	-- Recipient cannot be sender
	if msg.From == data.Recipient then
		return nil, 'Recipient cannot be sender'
	end

	-- Sender does not have a balance
	if not Balances[msg.From] then
		return nil, 'Sender does not have a balance'
	end

	-- Sender does not have enough balance
	if bint(Balances[msg.From]) < bint(data.Quantity) then
		return nil, 'Sender does not have enough balance'
	end

	return data
end

-- Read process state
Handlers.add('Read', Handlers.utils.hasMatchingTag('Action', 'Read'), function(msg)
	ao.send({
		Target = msg.From,
		Data = json.encode({
			Name = Name,
			Ticker = Ticker,
			Denomination = Denomination,
			Balances = Balances,
		})
	})
end)

-- Transfer balance to recipient (msg.Data - { Recipient: string, Quantity: number })
Handlers.add('Transfer', Handlers.utils.hasMatchingTag('Action', 'Transfer'), function(msg)
	local data, error = validateRecipientData(msg)

	if data then
		-- Transfer is valid, calculate balances
		if not Balances[data.Recipient] then
			Balances[data.Recipient] = '0'
		end
		Balances[msg.From] = tostring(bint(Balances[msg.From]) - bint(data.Quantity))
		Balances[data.Recipient] = tostring(bint(Balances[data.Recipient]) + bint(data.Quantity))
		ao.send({ Target = msg.From, Tags = { Status = 'Success', Message = 'Balance transferred' } })
	else
		ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = error or 'Error transferring balances' } })
	end
end)

-- Allow recipient to claim balance (msg.Data - { Recipient, Quantity })
Handlers.add('Allow', Handlers.utils.hasMatchingTag('Action', 'Allow'), function(msg)
	local data, error = validateRecipientData(msg)

	if data then
		-- Allow is valid, transfer to claimable table
		if not Balances[msg.From] then
			Balances[msg.From] = '0'
		end
		Balances[msg.From] = tostring(bint(Balances[msg.From]) - bint(data.Quantity))
		table.insert(Claimable, {
			From = msg.From,
			To = data.Recipient,
			Quantity = tostring(bint(data.Quantity)),
			TxId = msg.Id
		})
		ao.send({ Target = msg.From, Tags = { Status = 'Success', Message = 'Allow created' } })
	else
		ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = error or 'Error creating allow' } })
	end
end)

-- Cancel allow by TxId (msg.Data = { TxId })
Handlers.add('Cancel-Allow', Handlers.utils.hasMatchingTag('Action', 'Cancel-Allow'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
		-- Check if TxId is present
		if not data.TxId then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Invalid arguments, required { TxId: string }' } })
			return
		end

		-- Check if TxId is a valid address
		if not checkValidAddress(data.TxId) then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'TxId is not a valid address' } })
			return
		end

		local existingAllow = nil
		local existingAllowIndex = nil

		for i, allow in ipairs(Claimable) do
			if allow.TxId == data.TxId then
				existingAllow = allow
				existingAllowIndex = i
			end
		end

		-- Allow not found
		if not existingAllow then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Allow not found' } })
			return
		else
			-- Allow is not addressed to sender
			if existingAllow.From ~= msg.From then
				ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Allow is not addressed to sender' } })
				return
			end

			-- Allow is valid, return balances and remove from Claimable
			if not Balances[msg.From] then
				Balances[msg.From] = '0'
			end
			Balances[msg.From] = tostring(bint(Balances[msg.From]) + bint(existingAllow.Quantity))
			table.remove(Claimable, existingAllowIndex)
			ao.send({ Target = msg.From, Tags = { Status = 'Success', Message = 'Allow removed' } })
		end
	else
		ao.send({
			Target = msg.From,
			Tags = {
				Status = 'Error',
				Message = string.format('Failed to parse data, received: %s. %s.', msg.Data,
					'Data must be an object - { TxId: string }')
			}
		})
	end
end)

-- Claim balance (msg.Data - { Pair: [AssetId, TokenId], AllowTxId })
Handlers.add('Claim', Handlers.utils.hasMatchingTag('Action', 'Claim'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
		if not data.Pair or not data.AllowTxId or not data.Quantity then
			ao.send({
				Target = msg.From,
				Action = 'Claim-Evaluated',
				Tags = { Status = 'Error', Message = 'Invalid arguments, required { Pair: [AssetId, TokenId], AllowTxId, Quantity }' }
			})
			return
		end

		-- Check if AllowTxId, Quantity, and Client are all valid
		local validAllowTxId = checkValidAddress(data.AllowTxId)
		local validQuantity = checkValidAmount(data.Quantity)

		if not validAllowTxId or not validQuantity then
			local message = nil

			if not validAllowTxId then message = 'AllowTxId is not a valid address' end
			if not validQuantity then message = 'Quantity must be an integer greater than zero' end

			ao.send({
				Target = msg.From,
				Action = 'Claim-Evaluated',
				Tags = { Status = 'Error', Message = message or 'Error validating claim input' },
			})
			return
		end

		local existingAllow = nil
		local existingAllowIndex = nil

		for i, allow in ipairs(Claimable) do
			if allow.TxId == data.AllowTxId then
				existingAllow = allow
				existingAllowIndex = i
			end
		end

		local orderEntry = {
			Pair = data.Pair,
			AllowTxId = data.AllowTxId,
			Quantity = data.Quantity
		}

		-- Allow not found
		if not existingAllow then
			ao.send({
				Target = msg.From,
				Action = 'Claim-Evaluated',
				Tags = { Status = 'Error', Message = 'Allow not found' },
				Data = json.encode(orderEntry)
			})
			return
		end

		local allowedClaim = msg.From == existingAllow.To
		local allowedQuantity = bint(data.Quantity) == bint(existingAllow.Quantity)

		if not allowedClaim or not allowedQuantity then
			local message = nil

			if not allowedClaim then message = 'Sender does not have permission to claim this balance' end
			if not allowedQuantity then message = 'Quantity input is not equal to allow quantity' end

			ao.send({
				Target = msg.From,
				Action = 'Claim-Evaluated',
				Tags = { Status = 'Error', Message = message or 'Error verifying claim input' },
				Data = json.encode(orderEntry)
			})
			return
		end

		-- Claim is valid, transfer balances
		if not Balances[msg.From] then
			Balances[msg.From] = '0'
		end
		Balances[msg.From] = tostring(bint(Balances[msg.From]) + bint(existingAllow.Quantity))
		table.remove(Claimable, existingAllowIndex)

		ao.send({
			Target = msg.From,
			Action = 'Claim-Evaluated',
			Tags = { Status = 'Success', Message = 'Claim successfully processed' },
			Data = json.encode(orderEntry)
		})
	else
		ao.send({
			Target = msg.From,
			Action = 'Claim-Evaluated',
			Tags = { Status = 'Error', Message = 'Invalid arguments, required { Pair: [AssetId, TokenId], AllowTxId, Quantity }' }
		})
	end
end)

-- Read balance (msg.Data - { Target })
Handlers.add('Balance', Handlers.utils.hasMatchingTag('Action', 'Balance'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
		-- Check if target is present
		if not data.Target then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Invalid arguments, required { Target }' } })
			return
		end

		-- Check if target is a valid address
		if not checkValidAddress(data.Target) then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Target is not a valid address' } })
			return
		end

		-- Check if target has a balance
		if not Balances[data.Target] then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Target does not have a balance' } })
			return
		end

		ao.send({ Target = msg.From, Data = Balances[data.Target] })
	else
		ao.send({
			Target = msg.From,
			Tags = {
				Status = 'Error',
				Message = string.format('Failed to parse data, received: %s. %s', msg.Data,
					'Data must be an object - { Target }')
			}
		})
	end
end)

-- Read balances
Handlers.add('Balances', Handlers.utils.hasMatchingTag('Action', 'Balances'),
	function(msg) ao.send({ Target = msg.From, Data = json.encode(Balances) }) end)