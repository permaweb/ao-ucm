local bint = require('.bint')(256)
local json = require('json')

local utils = require('utils')

UCM_PROCESS = 'U3TjJAZWJjlWBB4KAXSHKzuky81jtyh0zqH8rUL4Wd0'

if not ListedOrders then ListedOrders = {} end
if not ExecutedOrders then ExecutedOrders = {} end
if not CancelledOrders then CancelledOrders = {} end
if not SalesByAddress then SalesByAddress = {} end
if not PurchasesByAddress then PurchasesByAddress = {} end

-- Read activity
Handlers.add('Get-Activity', Handlers.utils.hasMatchingTag('Action', 'Get-Activity'), function(msg)
	local decodeCheck, data = utils.decodeMessageData(msg.Data)

	if not decodeCheck then
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

	local function limitResults(orders)
		if #orders > 1000 then
			return { table.unpack(orders, 1, 1000) }
		end
		return orders
	end

	filteredListedOrders = limitResults(filteredListedOrders)
	filteredExecutedOrders = limitResults(filteredExecutedOrders)
	filteredCancelledOrders = limitResults(filteredCancelledOrders)

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

Handlers.add('Update-Executed-Orders', Handlers.utils.hasMatchingTag('Action', 'Update-Executed-Orders'),
	function(msg)
		if msg.From ~= UCM_PROCESS then
			return
		end

		local decodeCheck, data = utils.decodeMessageData(msg.Data)

		if not decodeCheck or not data.Order then
			return
		end

		table.insert(ExecutedOrders, {
			OrderId = data.Order.Id,
			DominantToken = data.Order.DominantToken,
			SwapToken = data.Order.SwapToken,
			Sender = data.Order.Sender,
			Receiver = data.Order.Receiver,
			Quantity = data.Order.Quantity,
			Price = data.Order.Price,
			Timestamp = data.Order.Timestamp
		})

		if not SalesByAddress[data.Order.Sender] then
			SalesByAddress[data.Order.Sender] = 0
		end
		SalesByAddress[data.Order.Sender] = SalesByAddress[data.Order.Sender] + 1

		if not PurchasesByAddress[data.Order.Receiver] then
			PurchasesByAddress[data.Order.Receiver] = 0
		end
		PurchasesByAddress[data.Order.Receiver] = PurchasesByAddress[data.Order.Receiver] + 1
	end)

Handlers.add('Update-Listed-Orders', Handlers.utils.hasMatchingTag('Action', 'Update-Listed-Orders'),
	function(msg)
		if msg.From ~= UCM_PROCESS then
			return
		end

		local decodeCheck, data = utils.decodeMessageData(msg.Data)

		if not decodeCheck or not data.Order then
			return
		end

		table.insert(ListedOrders, {
			OrderId = data.Order.Id,
			DominantToken = data.Order.DominantToken,
			SwapToken = data.Order.SwapToken,
			Sender = data.Order.Sender,
			Receiver = nil,
			Quantity = data.Order.Quantity,
			Price = data.Order.Price,
			Timestamp = data.Order.Timestamp
		})
	end)

Handlers.add('Update-Cancelled-Orders', Handlers.utils.hasMatchingTag('Action', 'Update-Cancelled-Orders'),
	function(msg)
		if msg.From ~= UCM_PROCESS then
			return
		end

		local decodeCheck, data = utils.decodeMessageData(msg.Data)

		if not decodeCheck or not data.Order then
			return
		end

		table.insert(CancelledOrders, {
			OrderId = data.Order.Id,
			DominantToken = data.Order.DominantToken,
			SwapToken = data.Order.SwapToken,
			Sender = data.Order.Sender,
			Receiver = nil,
			Quantity = data.Order.Quantity,
			Price = data.Order.Price,
			Timestamp = data.Order.Timestamp
		})
	end)

Handlers.add('Get-UCM-Purchase-Amount', Handlers.utils.hasMatchingTag('Action', 'Get-UCM-Purchase-Amount'),
	function(msg)
		local totalBurnAmount = bint(0)
		for _, order in ipairs(ExecutedOrders) do
			if order.Receiver == UCM_PROCESS then
				totalBurnAmount = totalBurnAmount + bint(order.Quantity)
			end
		end

		ao.send({
			Target = msg.From,
			Action = 'UCM-Purchase-Amount-Notice',
			BurnAmount = tostring(totalBurnAmount)
		})
	end)

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
				if order.DominantToken == 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo' then
					quantity = quantity // bint(1000000)
				end
				if order.DominantToken == 'pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY' then
					quantity = quantity // bint(1000000000000)
				end
				if order.DominantToken == 'Btm_9_fvwb7eXbQ2VswA4V19HxYWnFsYRB4gIl3Dahw' then
					quantity = quantity // bint(1000000000000)
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
