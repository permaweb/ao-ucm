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
	return tostring(math.floor(tonumber(tostring(amount)) * 0.995))
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

return utils
