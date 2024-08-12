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

	local function filterOrders(orders, assetIdsSet, owner)
		local filteredOrders = {}
		for _, order in ipairs(orders) do
			local isAssetMatch = not assetIdsSet or assetIdsSet[order.DominantToken]
			local isOwnerMatch = not owner or order.Sender == owner or order.Receiver == owner

			if isAssetMatch and isOwnerMatch then
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

	filteredListedOrders = filterOrders(ListedOrders, assetIdsSet, data.Address)
	filteredExecutedOrders = filterOrders(ExecutedOrders, assetIdsSet, data.Address)
	filteredCancelledOrders = filterOrders(CancelledOrders, assetIdsSet, data.Address)

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
