local json = require('json')
local bint = require('.bint')(256)

local utils = {}

-- ARIO token process ID - replace with actual ARIO token process ID
ARIO_TOKEN_PROCESS_ID = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'

function utils.checkValidAddress(address)
	if not address or type(address) ~= 'string' then
		return false
	end

	return string.match(address, '^[%w%-_]+$') ~= nil and #address == 43
end

function utils.checkValidAmount(data)
	return bint(data) > bint(0)
end

function utils.isArioToken(tokenAddress)
	return tokenAddress == ARIO_TOKEN_PROCESS_ID
end

function utils.validateArioSwapToken(tokenAddress)
	-- Allow ARIO tokens in both dominant and swap positions
	-- This enables both selling for ARIO and buying with ARIO
	return true, nil
end

function utils.validateArioInTrade(dominantToken, swapToken)
	-- At least one of the tokens in the trade must be ARIO
	if dominantToken == ARIO_TOKEN_PROCESS_ID or swapToken == ARIO_TOKEN_PROCESS_ID then
		return true, nil
	end
	return false, 'At least one token in the trade must be ARIO'
end

function utils.decodeMessageData(data)
	local status, decodedData = pcall(json.decode, data)

	if not status or type(decodedData) ~= 'table' then
		return false, nil
	end

	return true, decodedData
end

function utils.validatePairData(data)
	if type(data) ~= 'table' or #data ~= 2 then
		return nil, 'Pair must be a list of exactly two strings - [TokenId, TokenId]'
	end

	if type(data[1]) ~= 'string' or type(data[2]) ~= 'string' then
		return nil, 'Both pair elements must be strings'
	end

	if not utils.checkValidAddress(data[1]) or not utils.checkValidAddress(data[2]) then
		return nil, 'Both pair elements must be valid addresses'
	end

	if data[1] == data[2] then
		return nil, 'Pair addresses cannot be equal'
	end

	return data
end

function utils.calculateSendAmount(amount)
	local factor = bint(995)
	local divisor = bint(1000)
	local sendAmount = (bint(amount) * factor) // divisor
	return tostring(sendAmount)
end

function utils.calculateFeeAmount(amount)
	local factor = bint(5)
	local divisor = bint(10000)
	local feeAmount = (bint(amount) * factor) // divisor
	return tostring(feeAmount)
end

function utils.calculateFillAmount(amount)
	return tostring(math.floor(tostring(amount)))
end

function utils.printTable(t, indent)
	local jsonStr = ''
	local function serialize(tbl, indentLevel)
		local isArray = #tbl > 0
		local tab = isArray and '[\n' or '{\n'
		local sep = isArray and ',\n' or ',\n'
		local endTab = isArray and ']' or '}'
		indentLevel = indentLevel + 1

		for k, v in pairs(tbl) do
			tab = tab .. string.rep('  ', indentLevel)
			if not isArray then
				tab = tab .. '\'' .. tostring(k) .. '\': '
			end

			if type(v) == 'table' then
				tab = tab .. serialize(v, indentLevel) .. sep
			else
				if type(v) == 'string' then
					tab = tab .. '\'' .. tostring(v) .. '\'' .. sep
				else
					tab = tab .. tostring(v) .. sep
				end
			end
		end

		if tab:sub(-2) == sep then
			tab = tab:sub(1, -3) .. '\n'
		end

		indentLevel = indentLevel - 1
		tab = tab .. string.rep('  ', indentLevel) .. endTab
		return tab
	end

	jsonStr = serialize(t, indent or 0)
	print(jsonStr)
end

function utils.checkTables(t1, t2)
	if t1 == t2 then return true end
	if type(t1) ~= 'table' or type(t2) ~= 'table' then return false end
	for k, v in pairs(t1) do
		if not utils.checkTables(v, t2[k]) then return false end
	end
	for k in pairs(t2) do
		if t1[k] == nil then return false end
	end
	return true
end

local testResults = {
    total = 0,
    passed = 0,
    failed = 0,
}

function utils.test(description, fn, expected)
    local colors = {
        red = '\27[31m',
        green = '\27[32m',
        blue = '\27[34m',
        reset = '\27[0m',
    }

    testResults.total = testResults.total + 1
    local testIndex = testResults.total

    print('\n' .. colors.blue .. 'Running test ' .. testIndex .. '... ' .. description .. colors.reset)
    local status, result = pcall(fn)
    if not status then
        testResults.failed = testResults.failed + 1
        print(colors.red .. 'Failed - ' .. description .. ' - ' .. result .. colors.reset .. '\n')
    else
        if utils.checkTables(result, expected) then
            testResults.passed = testResults.passed + 1
            print(colors.green .. 'Passed - ' .. description .. colors.reset)
        else
            testResults.failed = testResults.failed + 1
			if type(result) == 'table' and type(expected) == 'table' then
            	print(colors.red .. 'Failed - ' .. description .. colors.reset .. '\n')
            	print(colors.red .. 'Expected' .. colors.reset)
            	utils.printTable(expected)
            	print('\n' .. colors.red .. 'Got' .. colors.reset)
            	utils.printTable(result)
			else
				print(colors.red .. 'Failed - ' .. description .. colors.reset .. '\n')
				print(colors.red .. 'Expected' .. colors.reset)
				print(expected)
				print('\n' .. colors.red .. 'Got' .. colors.reset)
				print(result)
			end
        end
    end
end

function utils.testSummary()
    local colors = {
        red = '\27[31m',
        green = '\27[32m',
        reset = '\27[0m',
    }

    print('\nTest Summary')
    print('Total tests (' .. testResults.total .. ')')
    print('Result: ' .. testResults.passed .. '/' .. testResults.total .. ' tests passed')
    if testResults.passed == testResults.total then
        print(colors.green .. 'All tests passed!' .. colors.reset)
    else
        print(colors.green .. 'Tests passed: ' .. testResults.passed .. '/' .. testResults.total .. colors.reset)
        print(colors.red .. 'Tests failed: ' .. testResults.failed .. '/' .. testResults.total .. colors.reset .. '\n')
    end
end

function utils.checkValidExpirationTime(expirationTime, timestamp)
	-- Check if expiration time is a valid positive integer
	expirationTime = tonumber(expirationTime)
	if not expirationTime or not utils.checkValidAmount(expirationTime) then
		return false, 'Expiration time must be a valid positive integer'
	end
	
	-- Check if expiration time is greater than current timestamp
	local status, result = pcall(function()
		return bint(expirationTime) <= bint(timestamp)
	end)
	
	if not status then
		return false, 'Expiration time must be a valid timestamp'
	end
	
	if result then
		return false, 'Expiration time must be greater than current timestamp'
	end
	
	return true, nil
end


function utils.handleError(args) -- Target, TransferToken, Quantity
	-- If there is a valid quantity then return the funds
	if args.TransferToken and args.Quantity and utils.checkValidAmount(args.Quantity) then
		ao.send({
			Target = args.TransferToken,
			Action = 'Transfer',
			Tags = {
				Recipient = args.Target,
				Quantity = tostring(args.Quantity)
			}
		})
	end
	ao.send({ Target = args.Target, Action = args.Action, Tags = { Status = 'Error', Message = args.Message, ['X-Group-ID'] = args.OrderGroupId } })
end

-- Helper function to execute token transfers
function utils.executeTokenTransfers(args, currentOrderEntry, validPair, calculatedSendAmount, calculatedFillAmount)
	-- Transfer tokens to the seller (order creator)
	ao.send({
		Target = validPair[1],
		Action = 'Transfer',
		Tags = {
			Recipient = currentOrderEntry.Creator,
			Quantity = tostring(calculatedSendAmount)
		}
	})

	-- Transfer swap tokens to the buyer (order sender)
	ao.send({
		Target = args.swapToken,
		Action = 'Transfer',
		Tags = {
			Recipient = args.sender,
			Quantity = tostring(calculatedFillAmount)
		}
	})
end

-- Helper function to record match and send activity data
function utils.recordMatch(args, currentOrderEntry, validPair, calculatedFillAmount)
	-- Record the successful match
	local match = {
		Id = currentOrderEntry.Id,
		Quantity = calculatedFillAmount,
		Price = tostring(currentOrderEntry.Price)
	}

	-- Send match data to activity tracking
	local matchedDataSuccess, matchedData = pcall(function()
		return json.encode({
			Order = {
				Id = currentOrderEntry.Id,
				MatchId = args.orderId,
				DominantToken = validPair[2],
				SwapToken = validPair[1],
				Sender = currentOrderEntry.Creator,
				Receiver = args.sender,
				Quantity = calculatedFillAmount,
				Price = tostring(currentOrderEntry.Price),
				Timestamp = args.timestamp
			}
		})
	end)

	ao.send({
		Target = ACTIVITY_PROCESS,
		Action = 'Update-Executed-Orders',
		Data = matchedDataSuccess and matchedData or ''
	})

	return match
end

return utils
