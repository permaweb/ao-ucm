local bint = require('.bint')(256)
local json = require('json')

if Name ~= 'Rai' then Name = 'Rai' end
if Ticker ~= 'RAI' then Ticker = 'RAI' end
if Denomination ~= 12 then Denomination = 12 end
if not Balances then Balances = { [ao.id] = tostring(bint(10000 * 1e12)) } end

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

-- Read balance (msg.Data - { Target: string })
Handlers.add('Balance', Handlers.utils.hasMatchingTag('Action', 'Balance'), function(msg)
	local decodeCheck, data = decodeMessageData(msg.Data)

	if decodeCheck and data then
		-- Check if target is present
		if not data.Target then
			ao.send({ Target = msg.From, Tags = { Status = 'Error', Message = 'Invalid arguments, required { Target: string }' } })
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
					'Data must be an object - { Target: string }')
			}
		})
	end
end)

-- Read balances
Handlers.add('Balances', Handlers.utils.hasMatchingTag('Action', 'Balances'),
	function(msg) ao.send({ Target = msg.From, Data = json.encode(Balances) }) end)

-- Transfer asset balances (msg.Data - { Recipient: string, Quantity: number })
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
