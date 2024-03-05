local json = require('json')

if Name ~= 'Universal Content Marketplace' then Name = 'Universal Content Marketplace' end
if not Balances then Balances = {} end
if not Pairs then Pairs = {} end

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

-- Read process state
Handlers.add('Read', Handlers.utils.hasMatchingTag('Action', 'Read'), function(msg)
    ao.send({
        Target = msg.From,
        Data = json.encode({
            Name = Name,
            Balances = Balances,
            Pairs = Pairs
        })
    })
end)

-- Add asset and token to Pairs table (msg.Data - [Asset-Id: string, Token-Id: string])
Handlers.add('Add-Pair', Handlers.utils.hasMatchingTag('Action', 'Add-Pair'), function(msg)
    -- Check and parse the message data
    local decodeCheck, pair = decodeMessageData(msg.Data)
    if not decodeCheck or not pair then
        ao.send({
            Target = msg.From,
            Tags = {
                Action = 'Error',
                Message = string.format('Failed to parse data, received: %s. %s.', msg.Data,
                    'Data must be an object - [Asset-Id, Token-Id]')
            }
        })
        return
    end

    if pair then
        -- Check if pair is a table with exactly two elements
        if type(pair) ~= 'table' or #pair ~= 2 then
            ao.send({ Target = msg.From, Tags = { Action = 'Error', Message = 'Data must be a list of exactly two strings - [Asset-Id, Token-Id]' } })
            return
        end
        
        -- Check if both elements of the table are strings
        if type(pair[1]) ~= 'string' or type(pair[2]) ~= 'string' then
            ao.send({ Target = msg.From, Tags = { Action = 'Error', Message = 'Both elements of the pair must be strings' } })
            return
        end

        -- Check if both elements are valid addresses
        if not checkValidAddress(pair[1]) or not checkValidAddress(pair[2]) then
            ao.send({ Target = msg.From, Tags = { Action = 'Error', Message = 'Both elements must be valid addresses' } })
            return
        end

        -- Ensure the addresses are not equal
        if pair[1] == pair[2] then
            ao.send({ Target = msg.From, Tags = { Action = 'Error', Message = 'Addresses cannot be equal' } })
            return
        end

        -- Check if the pair already exists
        for _, existingPair in ipairs(Pairs) do
            if (existingPair[1] == pair[1] and existingPair[2] == pair[2]) then
                ao.send({ Target = msg.From, Tags = { Action = 'Error', Message = 'This pair already exists' } })
                return
            end
        end

        -- Pair is valid
        table.insert(Pairs, pair)
        ao.send({ Target = msg.From, Tags = { Action = 'Success', Message = 'Pair added' } })
    end
end)
