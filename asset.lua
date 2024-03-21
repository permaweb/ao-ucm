local bint = require('.bint')(256)
local json = require('json')

if Name ~= 'Asset 1' then Name = 'Asset 1' end
if not Balances then Balances = { [Owner] = '100' } end

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
		return nil, string.format('Failed to parse data, received: %s. %s', msg.Data,
			'Data must be an object - { Recipient, Quantity }')
	end

	-- Check if recipient and quantity are present
	if not data.Recipient or not data.Quantity then
		return nil, 'Invalid arguments, required { Recipient, Quantity }'
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
			Balances = Balances,
		})
	})
end)

-- Transfer balance to recipient (msg.Data - { Recipient, Quantity })
Handlers.add('Transfer', Handlers.utils.hasMatchingTag('Action', 'Transfer'), function(msg)
	local data, error = validateRecipientData(msg)

	if data then
		-- Transfer is valid, calculate balances
		if not Balances[data.Recipient] then
			Balances[data.Recipient] = '0'
		end

		Balances[msg.From] = tostring(bint(Balances[msg.From]) - bint(data.Quantity))
		Balances[data.Recipient] = tostring(bint(Balances[data.Recipient]) + bint(data.Quantity))

		-- If new balance zeroes out then remove it from the table
		if bint(Balances[msg.From]) <= 0 then
			Balances[msg.From] = nil
		end
		if bint(Balances[data.Recipient]) <= 0 then
			Balances[data.Recipient] = nil
		end

		-- Send a credit notice to the recipient
		ao.send({
			Target = data.Recipient,
			Action = 'Credit-Notice',
			Tags = { Status = 'Success', Message = 'Balance transferred' },
			Data = json.encode({
				TransferTxId = msg.Id,
				Sender = msg.From,
				Quantity = tostring(data.Quantity)
			})
		})

		-- Send a debit notice to the sender
		ao.send({
			Target = msg.From,
			Action = 'Debit-Notice',
			Tags = { Status = 'Success', Message = 'Balance transferred' },
			Data = json.encode({
				TransferTxId = msg.Id,
				Recipient = data.Recipient,
				Quantity = tostring(data.Quantity)
			})
		})
	else
		ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = error or 'Error transferring balances' } })
	end
end)
