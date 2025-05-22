local json = require('json')
local bint = require('.bint')(256)

CollectionId = CollectionId or ao.env.Process.Tags.CollectionId

if not ListedOrders then ListedOrders = {} end
if not ExecutedOrders then ExecutedOrders = {} end
if not CancelledOrders then CancelledOrders = {} end
if not SalesByAddress then SalesByAddress = {} end
if not PurchasesByAddress then PurchasesByAddress = {} end
if not CurrentListings then CurrentListings = {} end

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

Handlers.add('Info', Handlers.utils.hasMatchingTag('Action', 'Info'), function(msg)
	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode(CurrentListings)
	})
end)

-- Read activity
Handlers.add('Get-Activity', Handlers.utils.hasMatchingTag('Action', 'Get-Activity'), function(msg)
	local decodeCheck, data = utils.decodeMessageData(msg.Data)

	if not data or not decodeCheck then
		ao.send({
			Target = msg.From,
			Action = 'Input-Error'
		})
		return
	end

	local filteredListedOrders = {}
	local filteredExecutedOrders = {}
	local filteredCancelledOrders = {}

	local function filterOrders(orders, assetIdsSet, owner, startDate, endDate)
		local filteredOrders = {}
		for _, order in ipairs(orders) do
			local isAssetMatch = not assetIdsSet or assetIdsSet[order.DominantToken]
			local isOwnerMatch = not owner or order.Sender == owner or order.Receiver == owner

			local isDateMatch = true
			if order.Timestamp and (startDate or endDate) then
				local orderDate = bint(order.Timestamp)

				if startDate then startDate = bint(startDate) end
				if endDate then endDate = bint(endDate) end

				if startDate and orderDate < startDate then
					isDateMatch = false
				end
				if endDate and orderDate > endDate then
					isDateMatch = false
				end
			end

			if isAssetMatch and isOwnerMatch and isDateMatch then
				table.insert(filteredOrders, order)
			end
		end
		return filteredOrders
	end

	local assetIdsSet = nil
	if data.AssetIds and #data.AssetIds > 0 then
		assetIdsSet = {}
		for _, assetId in ipairs(data.AssetIds) do
			assetIdsSet[assetId] = true
		end
	end

	local startDate = nil
	local endDate = nil
	if data.StartDate then startDate = data.StartDate end
	if data.EndDate then endDate = data.EndDate end

	filteredListedOrders = filterOrders(ListedOrders, assetIdsSet, data.Address, startDate, endDate)
	filteredExecutedOrders = filterOrders(ExecutedOrders, assetIdsSet, data.Address, startDate, endDate)
	filteredCancelledOrders = filterOrders(CancelledOrders, assetIdsSet, data.Address, startDate, endDate)

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode({
			ListedOrders = filteredListedOrders,
			ExecutedOrders = filteredExecutedOrders,
			CancelledOrders = filteredCancelledOrders
		})
	})
end)

-- Read order counts by address
Handlers.add('Get-Order-Counts-By-Address', Handlers.utils.hasMatchingTag('Action', 'Get-Order-Counts-By-Address'),
	function(msg)
		local salesByAddress = SalesByAddress
		local purchasesByAddress = PurchasesByAddress

		if msg.Tags.Count then
			local function getTopN(data, n)
				local sortedData = {}
				for k, v in pairs(data) do
					table.insert(sortedData, { key = k, value = v })
				end
				table.sort(sortedData, function(a, b) return a.value > b.value end)
				local topN = {}
				for i = 1, n do
					topN[sortedData[i].key] = sortedData[i].value
				end
				return topN
			end

			salesByAddress = getTopN(SalesByAddress, msg.Tags.Count)
			purchasesByAddress = getTopN(PurchasesByAddress, msg.Tags.Count)
		end

		ao.send({
			Target = msg.From,
			Action = 'Read-Success',
			Data = json.encode({
				SalesByAddress = salesByAddress,
				PurchasesByAddress = purchasesByAddress
			})
		})
	end)

Handlers.add('Get-Sales-By-Address', Handlers.utils.hasMatchingTag('Action', 'Get-Sales-By-Address'), function(msg)
	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode({
			SalesByAddress = SalesByAddress
		})
	})
end)

-- Update-Listed-Orders
Handlers.add('Update-Listed-Orders',
	Handlers.utils.hasMatchingTag('Action', 'Update-Listed-Orders'),
	function(msg)
		if msg.From ~= CollectionId then return end
		local ok, data = utils.decodeMessageData(msg.Data)
		if not ok or not data or not data.Order then return end

		table.insert(ListedOrders, {
			OrderId       = data.Order.Id,
			DominantToken = data.Order.DominantToken,
			SwapToken     = data.Order.SwapToken,
			Sender        = data.Order.Sender,
			Receiver      = nil,
			Quantity      = data.Order.Quantity,
			Price         = data.Order.Price,
			Timestamp     = data.Order.Timestamp,
		})

		local assetId            = data.Order.DominantToken
		local swapToken          = data.Order.SwapToken
		local qtyB               = bint(data.Order.Quantity)
		local priceB             = bint(data.Order.Price)

		CurrentListings[assetId] = CurrentListings[assetId] or {}
		local entry              = CurrentListings[assetId][swapToken]

		if entry then
			-- add quantity and update floorPrice if lower
			local newQty   = bint(entry.quantity) + qtyB
			local newFloor = bint(entry.floorPrice)
			if priceB < newFloor then newFloor = priceB end

			entry.quantity   = tostring(newQty)
			entry.floorPrice = tostring(newFloor)
		else
			-- first listing
			CurrentListings[assetId][swapToken] = {
				quantity   = tostring(qtyB),
				floorPrice = tostring(priceB),
			}
		end
	end
)

-- Update-Executed-Orders
Handlers.add('Update-Executed-Orders',
	Handlers.utils.hasMatchingTag('Action', 'Update-Executed-Orders'),
	function(msg)
		if msg.From ~= CollectionId then return end
		local ok, data = utils.decodeMessageData(msg.Data)
		if not ok or not data or not data.Order then return end

		table.insert(ExecutedOrders, {
			OrderId       = data.Order.MatchId or data.Order.Id,
			DominantToken = data.Order.DominantToken,
			SwapToken     = data.Order.SwapToken,
			Sender        = data.Order.Sender,
			Receiver      = data.Order.Receiver,
			Quantity      = data.Order.Quantity,
			Price         = data.Order.Price,
			Timestamp     = data.Order.Timestamp,
		})

		local assetId   = data.Order.DominantToken
		local swapToken = data.Order.SwapToken
		local execB     = bint(data.Order.Quantity)
		local bucket    = CurrentListings[assetId] and CurrentListings[assetId][swapToken]

		if bucket then
			local rem = bint(bucket.quantity) - execB
			if rem <= bint(0) then
				CurrentListings[assetId][swapToken] = nil
				if next(CurrentListings[assetId]) == nil then
					CurrentListings[assetId] = nil
				end
			else
				bucket.quantity = tostring(rem)
			end
		end

		-- update stats
		SalesByAddress[data.Order.Sender]       = (SalesByAddress[data.Order.Sender] or 0) + 1
		PurchasesByAddress[data.Order.Receiver] = (PurchasesByAddress[data.Order.Receiver] or 0) + 1
	end
)

-- Update-Cancelled-Orders
Handlers.add('Update-Cancelled-Orders',
	Handlers.utils.hasMatchingTag('Action', 'Update-Cancelled-Orders'),
	function(msg)
		if msg.From ~= CollectionId then return end
		local ok, data = utils.decodeMessageData(msg.Data)
		if not ok or not data or not data.Order then return end

		table.insert(CancelledOrders, {
			OrderId       = data.Order.Id,
			DominantToken = data.Order.DominantToken,
			SwapToken     = data.Order.SwapToken,
			Sender        = data.Order.Sender,
			Receiver      = nil,
			Quantity      = data.Order.Quantity,
			Price         = data.Order.Price,
			Timestamp     = data.Order.Timestamp,
		})

		local assetId   = data.Order.DominantToken
		local swapToken = data.Order.SwapToken
		local canB      = bint(data.Order.Quantity)
		local bucket    = CurrentListings[assetId] and CurrentListings[assetId][swapToken]

		if bucket then
			local rem = bint(bucket.quantity) - canB
			if rem <= bint(0) then
				CurrentListings[assetId][swapToken] = nil
				if next(CurrentListings[assetId]) == nil then
					CurrentListings[assetId] = nil
				end
			else
				bucket.quantity = tostring(rem)
			end
		end
	end
)

Handlers.add('Get-Volume', Handlers.utils.hasMatchingTag('Action', 'Get-Volume'),
	function(msg)
		local function validNumber(value)
			return type(value) == 'number' or (type(value) == 'string' and tonumber(value) ~= nil)
		end

		local totalVolume = bint(0)
		for _, order in ipairs(ExecutedOrders) do
			if order.Receiver and order.Quantity and validNumber(order.Quantity) and order.Price and validNumber(order.Price) then
				local price = bint(math.floor(order.Price)) // bint(1000000000000)

				local quantity = bint(math.floor(order.Quantity))
				if msg.Tags.Denomination then
					quantity = quantity // bint(msg.Tags.Denomination)
				end

				totalVolume = totalVolume + quantity * price
			end
		end

		print('Total Volume: ' .. tostring(totalVolume))

		ao.send({
			Target = msg.From,
			Action = 'Volume-Notice',
			Volume = tostring(totalVolume)
		})
	end)

Handlers.add('Get-Most-Traded-Tokens', Handlers.utils.hasMatchingTag('Action', 'Get-Most-Traded-Tokens'),
	function(msg)
		local tokenVolumes = {}

		for _, order in ipairs(ExecutedOrders) do
			if order.DominantToken and order.Quantity and type(order.Quantity) == 'string' then
				local quantity = bint(math.floor(order.Quantity))
				tokenVolumes[order.DominantToken] = (tokenVolumes[order.DominantToken] or bint(0)) + quantity
			end
		end

		local sortedTokens = {}
		for token, volume in pairs(tokenVolumes) do
			table.insert(sortedTokens, { token = token, volume = volume })
		end

		table.sort(sortedTokens, function(a, b) return a.volume > b.volume end)

		local topN = tonumber(msg.Tags.Count) or 10
		local result = {}
		for i = 1, math.min(topN, #sortedTokens) do
			result[i] = {
				Token = sortedTokens[i].token,
				Volume = tostring(sortedTokens[i].volume)
			}
		end

		ao.send({
			Target = msg.From,
			Action = 'Most-Traded-Tokens-Result',
			Data = json.encode(result)
		})
	end)
