local bint = require('.bint')(256)
local json = require('json')

local utils = require('utils')

UCM_PROCESS = 'a3jqBgXGAqefY4EHqkMwXhkBSFxZfzVdLU1oMUTQ-1M'

if not ListedOrders then ListedOrders = {} end
if not ExecutedOrders then ExecutedOrders = {} end
if not CancelledOrders then CancelledOrders = {} end
if not SalesByAddress then SalesByAddress = {} end
if not PurchasesByAddress then PurchasesByAddress = {} end
if not AuctionBids then AuctionBids = {} end

-- Normalize timestamp fields for a single order copy
local function normalizeOrderTimestamps(oc)
	if oc.CreatedAt then
		oc.CreatedAt = math.floor(tonumber(oc.CreatedAt))
	end
	if oc.ExpirationTime then
		oc.ExpirationTime = math.floor(tonumber(oc.ExpirationTime))
	end
	if oc.LeaseStartTimestamp then
		oc.LeaseStartTimestamp = math.floor(tonumber(oc.LeaseStartTimestamp))
	end
	if oc.LeaseEndTimestamp then
		oc.LeaseEndTimestamp = math.floor(tonumber(oc.LeaseEndTimestamp))
	end
	if oc.EndedAt then
		oc.EndedAt = math.floor(tonumber(oc.EndedAt))
	end
	return oc
end

-- Helper: attach english-auction fields onto a single order-like table
local function applyEnglishAuctionFields(orderCopy)
	if orderCopy and orderCopy.OrderType == 'english' then
		local auctionBids = AuctionBids[orderCopy.OrderId]
		orderCopy.StartingPrice = orderCopy.StartingPrice or orderCopy.Price
		if auctionBids then
			orderCopy.Bids = auctionBids.Bids
			orderCopy.HighestBid = auctionBids.HighestBid
			orderCopy.HighestBidder = auctionBids.HighestBidder
			if auctionBids.Settlement then
				orderCopy.Settlement = auctionBids.Settlement
			end
		else
			orderCopy.Bids = {}
			orderCopy.HighestBid = orderCopy.HighestBid or nil
			orderCopy.HighestBidder = orderCopy.HighestBidder or nil
		end
	end
	return orderCopy
end


-- Build a normalized order response with optional status and english auction fields
local function buildOrderResponse(order, status)
	local oc = utils.deepCopy(order)
	if status then
		oc.Status = status
	end
	oc = normalizeOrderTimestamps(oc)
	oc = applyEnglishAuctionFields(oc)
	return oc
end


-- Pure status computation for orders currently in ListedOrders
local function computeListedStatus(order, now)
	local status = 'active'
	local endedAt = nil
	if order.ExpirationTime then
		local expirationTime = math.floor(tonumber(order.ExpirationTime))
		if now >= expirationTime then
			if order.OrderType == 'english' then
				local auctionBids = AuctionBids[order.OrderId]
				if auctionBids and auctionBids.HighestBidder then
					status = 'ready-for-settlement'
				else
					status = 'expired'
					endedAt = expirationTime
				end
			else
				status = 'expired'
				endedAt = expirationTime
			end
		end
	end
	return status, endedAt
end

-- Decorate orders with normalized timestamps, auction fields, and type-specific extras
local function decorateOrder(order, status)
	local oc = utils.deepCopy(order)
	if status then oc.Status = status end
	oc = normalizeOrderTimestamps(oc)
	oc = applyEnglishAuctionFields(oc)
	if status == 'settled' then
		oc.Buyer = oc.Receiver
		if order.OrderType == 'dutch' or order.OrderType == 'fixed' then
			oc.FinalPrice = oc.Price
		end
	elseif status == 'expired' and oc.ExpirationTime and not oc.EndedAt then
		oc.EndedAt = oc.ExpirationTime
	end
	
	return oc
end

-- Filter orders by domain name substring
local function filterOrdersByName(ordersArray, nameFilter)
	if not nameFilter or nameFilter == '' then
		return ordersArray
	end
	
	local needle = string.lower(nameFilter)
	return utils.filterArray(ordersArray, function(_, oc)
		if not oc.Domain or type(oc.Domain) ~= 'string' then 
			return false 
		end
		return string.find(string.lower(oc.Domain), needle, 1, true) ~= nil
	end)
end

-- Build a unified, pure snapshot of all orders at a given time without mutating globals
local function getListedSnapshot(now)
	local active, ready, expired = {}, {}, {}
	for _, order in ipairs(ListedOrders) do
		local status, endedAt = computeListedStatus(order, now)
		local oc = decorateOrder(order, status)
		if endedAt then oc.EndedAt = endedAt end
		if status == 'active' then table.insert(active, oc)
		elseif status == 'ready-for-settlement' then table.insert(ready, oc)
		elseif status == 'expired' then table.insert(expired, oc)
		end
	end
	return active, ready, expired
end

local function getExecutedSnapshot()
	local executed = {}
	for _, order in ipairs(ExecutedOrders) do
		local oc = decorateOrder(order, 'settled')
		oc.EndedAt = oc.EndedAt or order.EndedAt or order.ExecutionTime
		table.insert(executed, oc)
	end
	return executed
end

local function getCancelledSnapshot()
	local cancelled = {}
	for _, order in ipairs(CancelledOrders) do
		local oc = decorateOrder(order, 'cancelled')
		oc.EndedAt = oc.EndedAt or order.EndedAt or order.CancellationTime
		table.insert(cancelled, oc)
	end
	return cancelled
end


-- Reusable state updater to move expired orders from Listed to Expired
-- updateOrderStates removed: we compute status on the fly for reads

-- Get listed orders
Handlers.add('Get-Listed-Orders', Handlers.utils.hasMatchingTag('Action', 'Get-Listed-Orders'), function(msg)
	local page = utils.parsePaginationTags(msg)

	local now = math.floor(tonumber(msg.Timestamp))
	local active, ready = getListedSnapshot(now)
	local ordersArray = {}
	for _, oc in ipairs(active) do table.insert(ordersArray, oc) end
	for _, oc in ipairs(ready) do table.insert(ordersArray, oc) end

	-- Apply name filter if provided
	ordersArray = filterOrdersByName(ordersArray, msg.Tags.Namefilter)

	local paginatedOrders = utils.paginateTableWithCursor(ordersArray, page.cursor, 'CreatedAt', page.limit, page.sortBy, page.sortOrder, page.filters)

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode(paginatedOrders)
	})
end)

-- Get completed orders
Handlers.add('Get-Completed-Orders', Handlers.utils.hasMatchingTag('Action', 'Get-Completed-Orders'), function(msg)
	local page = utils.parsePaginationTags(msg)

	local now = math.floor(tonumber(msg.Timestamp))
	local cancelled = getCancelledSnapshot()
	local settled = getExecutedSnapshot()
	local _, _, expired = getListedSnapshot(now)
	local ordersArray = {}
	for _, oc in ipairs(cancelled) do table.insert(ordersArray, oc) end
	for _, oc in ipairs(settled) do table.insert(ordersArray, oc) end
	for _, oc in ipairs(expired) do table.insert(ordersArray, oc) end

	-- Apply name filter if provided
	ordersArray = filterOrdersByName(ordersArray, msg.Tags.Namefilter)

	local paginatedOrders = utils.paginateTableWithCursor(ordersArray, page.cursor, 'CreatedAt', page.limit, page.sortBy, page.sortOrder, page.filters)

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode(paginatedOrders)
	})
end)

-- Get order by ID
Handlers.add('Get-Order-By-Id', Handlers.utils.hasMatchingTag('Action', 'Get-Order-By-Id'), function(msg)
	local orderId = msg.Tags.Orderid or msg.Tags.OrderId
	local decodeCheck, data = utils.decodeMessageData(msg.Data)
	
	if (not decodeCheck or not data) and not orderId then
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Message = 'OrderId is required'
		})
		return
	end
	if data and data.OrderId then
		orderId = data.OrderId
	end
	
	-- Final check		-- For English auctions, prefer Settlement.WinningBid; otherwise use recorded Price
	if not orderId then
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Message = 'OrderId is required'
		})
		return
	end

	local now = math.floor(tonumber(msg.Timestamp))
	local active, ready, expired = getListedSnapshot(now)
	local listedById = {}
	for _, oc in ipairs(active) do listedById[oc.OrderId] = oc end
	for _, oc in ipairs(ready) do listedById[oc.OrderId] = oc end
	for _, oc in ipairs(expired) do listedById[oc.OrderId] = oc end

	local executed = getExecutedSnapshot()
	local cancelled = getCancelledSnapshot()
	local executedById, cancelledById = {}, {}
	for _, oc in ipairs(executed) do executedById[oc.OrderId] = oc end
	for _, oc in ipairs(cancelled) do cancelledById[oc.OrderId] = oc end

	local foundOrder = cancelledById[orderId] or executedById[orderId] or listedById[orderId]
	local orderStatus = foundOrder and foundOrder.Status or nil

	if not foundOrder then
		ao.send({
			Target = msg.From,
			Action = 'Order-Not-Found',
			Message = 'Order with ID ' .. orderId .. ' not found'
		})
		return
	end

	-- foundOrder is already decorated by snapshot
	local response = foundOrder

	if msg.Tags.Functioninvoke or msg.Tags.FunctionInvoke then
		msg.reply({Data = json.encode(response)})
	else
		ao.send({
			Target = msg.From,
			Action = 'Read-Success',
			Data = json.encode(response)
		})
	end

end)

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

	local now = math.floor(tonumber(msg.Timestamp))
	local active, ready, expired = getListedSnapshot(now)
	local executed = getExecutedSnapshot()
	local cancelled = getCancelledSnapshot()

	local filteredListedOrders = {}
	local filteredExecutedOrders = {}
	local filteredCancelledOrders = {}

	local function filterOrders(orders, assetIdsSet, owner, startDate, endDate)
		local filteredOrders = {}
		for _, order in ipairs(orders) do
			local isAssetMatch = not assetIdsSet or assetIdsSet[order.DominantToken]
			local isOwnerMatch = not owner or order.Sender == owner or order.Receiver == owner

			local isDateMatch = true
			if order.CreatedAt and (startDate or endDate) then
				local orderDate = bint(order.CreatedAt)

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

	local baseListed = {}
	for _, oc in ipairs(active) do table.insert(baseListed, oc) end
	for _, oc in ipairs(ready) do table.insert(baseListed, oc) end
	filteredListedOrders = filterOrders(baseListed, assetIdsSet, data.Address, startDate, endDate)
	filteredExecutedOrders = filterOrders(executed, assetIdsSet, data.Address, startDate, endDate)
	filteredCancelledOrders = filterOrders(cancelled, assetIdsSet, data.Address, startDate, endDate)

	-- All orders already decorated/normalized by snapshot
	local listedWithFields = filteredListedOrders
	local executedWithFields = filteredExecutedOrders
	local cancelledWithFields = filteredCancelledOrders
	-- Expired are from snapshot as well (no filter applied previously); apply filters if provided
	local expiredBase = expired
	local expiredWithFields = filterOrders(expiredBase, assetIdsSet, data.Address, startDate, endDate)

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode({
			ListedOrders = listedWithFields,
			ExecutedOrders = executedWithFields,
			CancelledOrders = cancelledWithFields,
			ExpiredOrders = expiredWithFields,
			ActiveOrders = listedWithFields,
			SettledOrders = executedWithFields,
			CancelledOrdersList = cancelledWithFields,
			ExpiredOrdersList = expiredWithFields
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

		-- Debug: warn when critical executed fields are missing in payload
		if not data.Order.Receiver then
			print('WARN(Update-Executed-Orders): Receiver is nil for OrderId ' .. tostring(data.Order.Id))
		end
		if not data.Order.Price then
			print('WARN(Update-Executed-Orders): Price is nil for OrderId ' .. tostring(data.Order.Id))
		end

		-- Search for the order in ListedOrders
		local foundOrder = nil
		-- Find the order in ListedOrders and remove it
		for i, order in ipairs(ListedOrders) do
			if order.OrderId == data.Order.Id then
				foundOrder = order
				table.remove(ListedOrders, i)
				break
			end
		end

		foundOrder.EndedAt = data.Order.EndedAt or data.Order.ExecutionTime
		-- Merge execution payload fields to ensure buyer/price are recorded
		foundOrder.DominantToken = data.Order.DominantToken or foundOrder.DominantToken
		foundOrder.SwapToken = data.Order.SwapToken or foundOrder.SwapToken
		foundOrder.Sender = data.Order.Sender or foundOrder.Sender
		foundOrder.Receiver = data.Order.Receiver or foundOrder.Receiver
		foundOrder.Quantity = data.Order.Quantity or foundOrder.Quantity
		foundOrder.Price = data.Order.Price or foundOrder.Price

		-- Debug: warn if after merge Receiver/Price are still nil
		if not foundOrder.Receiver then
			print('WARN(Update-Executed-Orders): Merged order still has nil Receiver for OrderId ' .. tostring(data.Order.Id))
		end
		if not foundOrder.Price then
			print('WARN(Update-Executed-Orders): Merged order still has nil Price for OrderId ' .. tostring(data.Order.Id))
		end
		-- Add the order to ExecutedOrders
		table.insert(ExecutedOrders, foundOrder)

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
			CreatedAt = data.Order.CreatedAt,
			Domain = data.Order.Domain,
			OrderType = data.Order.OrderType,
			MinimumPrice = data.Order.MinimumPrice,
			DecreaseInterval = data.Order.DecreaseInterval,
			DecreaseStep = data.Order.DecreaseStep,
			ExpirationTime = data.Order.ExpirationTime,
			OwnershipType = data.Order.OwnershipType,
			LeaseStartTimestamp = data.Order.LeaseStartTimestamp,
			LeaseEndTimestamp = data.Order.LeaseEndTimestamp
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

		-- Search for the order in ListedOrders
		local foundOrder = nil

		-- Find the order in ListedOrders and remove it
		for i, order in ipairs(ListedOrders) do
			if order.OrderId == data.Order.Id then
				foundOrder = order
				table.remove(ListedOrders, i)
				break
			end
		end

		foundOrder.EndedAt = data.Order.EndedAt or data.Order.CancellationTime
		
		-- Add the order to CancelledOrders
		table.insert(CancelledOrders, foundOrder)
	end)

Handlers.add('Update-Auction-Bids', Handlers.utils.hasMatchingTag('Action', 'Update-Auction-Bids'),
	function(msg)
		if msg.From ~= UCM_PROCESS then
			return
		end

		local decodeCheck, data = utils.decodeMessageData(msg.Data)

		if not decodeCheck or not data.Bid then
			return
		end

		local orderId = data.Bid.OrderId
		if not AuctionBids[orderId] then
			AuctionBids[orderId] = {
				Bids = {},
				HighestBid = nil,
				HighestBidder = nil
			}
		end

		-- Add the new bid
		table.insert(AuctionBids[orderId].Bids, {
			Bidder = data.Bid.Bidder,
			Amount = data.Bid.Amount,
			Timestamp = data.Bid.Timestamp,
			OrderId = data.Bid.OrderId
		})

		-- Update highest bid if this is higher
		if not AuctionBids[orderId].HighestBid or bint(data.Bid.Amount) > bint(AuctionBids[orderId].HighestBid) then
			AuctionBids[orderId].HighestBid = data.Bid.Amount
			AuctionBids[orderId].HighestBidder = data.Bid.Bidder
		end
	end)

Handlers.add('Update-Auction-Settlement', Handlers.utils.hasMatchingTag('Action', 'Update-Auction-Settlement'),
	function(msg)
		if msg.From ~= UCM_PROCESS then
			return
		end

		local decodeCheck, data = utils.decodeMessageData(msg.Data)

		if not decodeCheck or not data.Settlement then
			return
		end

		-- Add settlement information to the auction bids
		local orderId = data.Settlement.OrderId
		if AuctionBids[orderId] then
			AuctionBids[orderId].Settlement = {
				Winner = data.Settlement.Winner,
				Quantity = data.Settlement.Quantity,
				Timestamp = data.Settlement.Timestamp
			}
		end
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

Handlers.add('Get-Activity-Lengths', Handlers.utils.hasMatchingTag('Action', 'Get-Activity-Lengths'), function(msg)
	local function countTableEntries(tbl)
		local count = 0
		for _ in pairs(tbl) do
			count = count + 1
		end
		return count
	end

	ao.send({
		Target = msg.From,
		Action = 'Table-Lengths-Result',
		Data = json.encode({
			ListedOrders = #ListedOrders,
			ExecutedOrders = #ExecutedOrders,
			CancelledOrders = #CancelledOrders,
			SalesByAddress = countTableEntries(SalesByAddress),
			PurchasesByAddress = countTableEntries(PurchasesByAddress)
		})
	})
end)

Handlers.add('Migrate-Activity-Dryrun', Handlers.utils.hasMatchingTag('Action', 'Migrate-Activity-Dryrun'), function(msg)
	local orderTable = {}
	local orderType = msg.Tags['Order-Type']
	local stepBy = tonumber(msg.Tags['Step-By'])
	local ordersToUse
	if orderType == 'ListedOrders' then
		orderTable = table.move(
			ListedOrders,
			tonumber(msg.Tags.StartIndex),
			tonumber(msg.Tags.StartIndex) + stepBy,
			1,
			orderTable
		)
	elseif orderType == 'ExecutedOrders' then
		orderTable = table.move(
			ExecutedOrders,
			tonumber(msg.Tags.StartIndex),
			tonumber(msg.Tags.StartIndex) + stepBy,
			1,
			orderTable
		)
	elseif orderType == 'CancelledOrders' then
		orderTable = table.move(
			CancelledOrders,
			tonumber(msg.Tags.StartIndex),
			tonumber(msg.Tags.StartIndex) + stepBy,
			1,
			orderTable
		)
	else
		print('Invalid Order-Type: ' .. orderType)
		return
	end
end)

Handlers.add('Migrate-Activity', Handlers.utils.hasMatchingTag('Action', 'Migrate-Activity'), function(msg)
	if msg.From ~= ao.id and msg.From ~= Owner then return end
	print('Starting migration process...')

	local function sendBatch(orders, orderType, startIndex)
		local batch = {}

		for i = startIndex, math.min(startIndex + 29, #orders) do
			table.insert(batch, {
				OrderId = orders[i].OrderId or '',
				DominantToken = orders[i].DominantToken or '',
				SwapToken = orders[i].SwapToken or '',
				Sender = orders[i].Sender or '',
				Receiver = orders[i].Receiver or nil,
				Quantity = orders[i].Quantity and tostring(orders[i].Quantity) or '0',
				Price = orders[i].Price and tostring(orders[i].Price) or '0',
				Timestamp = orders[i].Timestamp or ''
			})
		end

		if #batch > 0 then
			print('Sending ' .. orderType .. ' Batch: ' .. #batch .. ' orders starting at index ' .. startIndex)

			local success, encoded = pcall(json.encode, batch)
			if not success then
				print('Failed to encode batch: ' .. tostring(encoded))
				return
			end

			ao.send({
				Target = '7_psKu3QHwzc2PFCJk2lEwyitLJbz6Vj7hOcltOulj4',
				Action = 'Migrate-Activity-Batch',
				Tags = {
					['Order-Type'] = orderType,
					['Start-Index'] = tostring(startIndex)
				},
				Data = encoded
			})
		end
	end

	local orderType = msg.Tags['Order-Type']
	if not orderType then
		print('No Order-Type specified in message tags')
		return
	end

	local orderTable
	if orderType == 'ListedOrders' then
		orderTable = ListedOrders
	elseif orderType == 'ExecutedOrders' then
		orderTable = ExecutedOrders
	elseif orderType == 'CancelledOrders' then
		orderTable = CancelledOrders
	else
		print('Invalid Order-Type: ' .. orderType)
		return
	end

	print('Starting ' .. orderType .. 'Orders migration (total: ' .. #orderTable .. ')')
	sendBatch(orderTable, orderType, tonumber(msg.Tags.StartIndex))
	print('Migration initiation completed')
end)

Handlers.add('Migrate-Activity-Batch', Handlers.utils.hasMatchingTag('Action', 'Migrate-Activity-Batch'), function(msg)
	if msg.Owner ~= Owner then
		print('Rejected batch: unauthorized sender')
		return
	end

	local decodeCheck, data = utils.decodeMessageData(msg.Data)
	if not decodeCheck or not data then
		print('Failed to decode batch data')
		return
	end

	local orderType = msg.Tags['Order-Type']
	local startIndex = tonumber(msg.Tags['Start-Index'])
	if not orderType or not startIndex then
		print('Missing required tags in batch message')
		return
	end

	print('Processing ' .. orderType .. ' batch: ' .. #data .. ' orders at index ' .. startIndex)

	-- Select the appropriate table based on order type
	local targetTable
	if orderType == 'ListedOrders' then
		targetTable = ListedOrders
	elseif orderType == 'ExecutedOrders' then
		targetTable = ExecutedOrders
	elseif orderType == 'CancelledOrders' then
		targetTable = CancelledOrders
	else
		print('Invalid order type: ' .. orderType)
		return
	end

	local existingOrders = {}
	for _, order in ipairs(targetTable) do
		if order.OrderId then
			existingOrders[order.OrderId] = true
		end
	end

	-- Insert only non-duplicate orders
	local insertedCount = 0
	for _, order in ipairs(data) do
		if order.OrderId and not existingOrders[order.OrderId] then
			table.insert(targetTable, order)
			existingOrders[order.OrderId] = true
			insertedCount = insertedCount + 1
		end
	end

	print('Successfully processed ' .. orderType .. ' batch of ' .. #data .. ' orders')

	ao.send({
		Target = msg.From,
		Action = 'Batch-Processed'
	})
end)

Handlers.add('Migrate-Activity-Stats', Handlers.utils.hasMatchingTag('Action', 'Migrate-Activity-Stats'), function(msg)
	if msg.From ~= '7_psKu3QHwzc2PFCJk2lEwyitLJbz6Vj7hOcltOulj4' then
		print('Rejected stats: unauthorized sender')
		return
	end

	local decodeCheck, stats = utils.decodeMessageData(msg.Data)
	if not decodeCheck or not stats then
		print('Failed to decode stats data')
		return
	end

	print('Processing address statistics...')

	-- Update the tables
	if stats.SalesByAddress then
		SalesByAddress = stats.SalesByAddress
	end

	if stats.PurchasesByAddress then
		PurchasesByAddress = stats.PurchasesByAddress
	end

	print('Successfully processed address statistics')
end)
