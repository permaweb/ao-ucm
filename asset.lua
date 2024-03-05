local bint = require('.bint')(256)
local json = require('json')

if Name ~= 'Asset 1' then Name = 'Asset 1' end
if Ticker ~= 'ATOMIC' then Ticker = 'ATOMIC' end
if not Balances then Balances = { [ao.id] = '100' } end
if not Claimable then Claimable = {} end

local function checkValidAddress(address)
    if not address or type(address) ~= 'string' then
        return false
    end

    local valid_address = string.match(address, "^[%w%-_]+$") ~= nil and #address == 43
    return valid_address
end

local function decodeMessageData(data)
    local status, decoded_data = pcall(json.decode, data)
    if not status then
        return false, nil
    end
    return true, decoded_data
end

local function validateRecipientData(msg)
    -- Check and parse the message data (TODO: check no data passed '2345')
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
    if math.type(tonumber(data.Quantity)) ~= 'integer' or bint(data.Quantity) <= 0 then
        return nil, 'Quantity must be an integer greater than zero'
    end

    -- Recipient cannot be caller
    if msg.From == data.Recipient then
        return nil, 'Recipient cannot be caller'
    end

    -- Caller does not have a balance
    if not Balances[msg.From] then
        return nil, 'Caller does not have a balance'
    end

    -- Caller does not have enough balance
    if bint(Balances[msg.From]) < bint(data.Quantity) then
        return nil, 'Caller does not have enough balance'
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
            Balances = Balances,
            Claimable = Claimable
        })
    })
end)

-- Transfer asset balances (msg.Data - { Recipient: string, Quantity: number })
Handlers.add('Transfer', Handlers.utils.hasMatchingTag('Action', 'Transfer'), function(msg)
    local data, error = validateRecipientData(msg)
    if not data then
        ao.send({ Target = msg.From, Tags = { Action = 'Error', Message = error or 'Error transferring balances' } })
    end

    if data then
        -- Transfer is valid, calculate balances
        if not Balances[data.Recipient] then
            Balances[data.Recipient] = '0'
        end
        Balances[msg.From] = tostring(bint(Balances[msg.From]) - bint(data.Quantity))
        Balances[data.Recipient] = tostring(bint(Balances[data.Recipient]) + bint(data.Quantity))
        ao.send({ Target = msg.From, Tags = { Action = 'Success', Message = 'Balance transferred' } })
    end
end)

-- Allow recipient to claim balance (msg.Data - { Recipient: string, Quantity: number })
Handlers.add('Allow', Handlers.utils.hasMatchingTag('Action', 'Allow'), function(msg)
    local data, error = validateRecipientData(msg)
    if not data then
        ao.send({ Target = msg.From, Tags = { Action = 'Error', Message = error or 'Error creating allow' } })
    end

    if data then
        -- Allow is valid, transfer to claimable table
        if not Balances[msg.From] then
            Balances[msg.From] = '0'
        end
        Balances[msg.From] = tostring(bint(Balances[msg.From]) - bint(data.Quantity))
        table.insert(Claimable, {
            From = msg.From,
            To = data.Recipient,
            Qty = tostring(bint(data.Quantity)),
            TxId = msg.Id
        })
        ao.send({ Target = msg.From, Tags = { Action = 'Success', Message = 'Allow created' } })
    end
end)

-- Cancel allow by Tx Id (msg.Data = { TxId: string })
Handlers.add('Cancel-Allow', Handlers.utils.hasMatchingTag('Action', 'Cancel-Allow'), function(msg)
    local decodeCheck, data = decodeMessageData(msg.Data)
    if not decodeCheck or not data then
        ao.send({
            Target = msg.From,
            Tags = {
                Action = 'Error',
                Message = string.format('Failed to parse data, received: %s. %s.', msg.Data,
                    'Data must be an object - { TxId: string }')
            }
        })
        return
    end

    if data then
        -- Check if TxId is present
        if not data.TxId then
            ao.send({ Target = msg.From, Tags = { Action = 'Error', Message = 'Invalid arguments, required { TxId: string }' } })
            return
        end

        -- Check if TxId is a valid address
        if not checkValidAddress(data.TxId) then
            ao.send({ Target = msg.From, Tags = { Action = 'Error', Message = 'TxId must be a valid address' } })
            return
        end

        local existingAllow = nil
        for _, allow in ipairs(Claimable) do
            if allow.TxId == data.TxId then
                existingAllow = allow
            end
        end

        -- Allow not found
        if not existingAllow then
            ao.send({ Target = msg.From, Tags = { Action = 'Error', Message = 'Allow not found' } })
            return
        else
            -- Allow is not addressed to caller
            if existingAllow.From ~= msg.From then
                ao.send({ Target = msg.From, Tags = { Action = 'Error', Message = 'Allow is not addressed to caller' } })
                return
            end

            -- Allow is valid, return balances and remove from Claimable
            if not Balances[msg.From] then
                Balances[msg.From] = '0'
            end
            Balances[msg.From] = tostring(bint(Balances[msg.From]) + bint(existingAllow.Qty))
            for i, allow in ipairs(Claimable) do
                if allow.txId == data.txId then
                    table.remove(Claimable, i)
                end
            end
            ao.send({ Target = msg.From, Tags = { Action = 'Success', Message = 'Allow removed' } })
        end
    end
end)
