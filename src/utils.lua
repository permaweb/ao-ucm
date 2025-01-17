local json = require('json')
local bint = require('.bint')(256)

local utils = {}

function utils.checkValidAddress(address)
	if not address or type(address) ~= 'string' then
		return false
	end

	return string.match(address, '^[%w%-_]+$') ~= nil and #address == 43
end

function utils.checkValidAmount(data)
	return bint(data) > bint(0)
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
            print(colors.red .. 'Failed - ' .. description .. colors.reset .. '\n')
            print(colors.red .. 'Expected' .. colors.reset)
            utils.printTable(expected)
            print('\n' .. colors.red .. 'Got' .. colors.reset)
            utils.printTable(result)
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

return utils
