local json = require('json')

State = {
    Name = 'Test UCM',
    Balances = {},
    Pairs = {}
}

-- Check valid arweave address
local function check_address(address)
    if not address or type(address) ~= 'string' then
        return false
    end

    local valid_address = string.match(address, "^[%w%-_]+$") ~= nil and #address == 43
    return valid_address
end

-- TODO: message not being sent with error thrown
-- Send a status message to target and throw error if it is an error
local function handle_response(target, response_type, message)
    ao.send({ Target = target, Tags = { Action = response_type, Message = message } })
    if response_type == 'Error' then
        error(message)
    end
end


local function decode_message_data(data)
    local status, decoded_data = pcall(json.decode, data)
    if not status then
        return false, nil
    end
    return true, decoded_data
end

Handlers.add('Read', Handlers.utils.hasMatchingTag('Action', 'Read'), function(msg)
    ao.send({ Target = msg.From, Data = json.encode(State) })
end)

-- msg.Data - ['asset id', 'token id']
Handlers.add('AddPair', Handlers.utils.hasMatchingTag('Action', 'Add-Pair'), function(msg)
    -- Check and parse the message data
    local decode_check, pair = decode_message_data(msg.Data)
    if not decode_check or not pair then
        handle_response(msg.From, 'Error',
            string.format('Failed to parse data, received: %s. %s.', msg.Data, 'Data must be a list of exactly two strings'))
    end

    if pair then
        -- Check if pair is a table with exactly two elements
        if type(pair) ~= 'table' or #pair ~= 2 then
            handle_response(msg.From, 'Error', 'Data must be a list of exactly two strings')
        end

        -- Check if both elements of the table are strings
        if type(pair[1]) ~= 'string' or type(pair[2]) ~= 'string' then
            handle_response(msg.From, 'Error', 'Both elements of the pair must be strings')
        end

        -- Check if both elements are valid addresses
        if not check_address(pair[1]) or not check_address(pair[2]) then
            handle_response(msg.From, 'Error', 'Both elements must be valid addresses')
        end

        -- Ensure the addresses are not equal
        if pair[1] == pair[2] then
            handle_response(msg.From, 'Error', 'Addresses cannot be equal')
        end

        -- Check if the pair already exists
        for _, existingPair in ipairs(State.Pairs) do
            if (existingPair[1] == pair[1] and existingPair[2] == pair[2]) then
                handle_response(msg.From, 'Error', 'This pair already exists')
            end
        end

        -- Pair is valid
        table.insert(State.Pairs, pair)
        handle_response(msg.From, 'Success', 'Pair added')
    end
end)