local bint = require('.bint')(256)
local json = require('json')

local utils = require('utils')

UCM_PROCESS = 'a3jqBgXGAqefY4EHqkMwXhkBSFxZfzVdLU1oMUTQ-1M'

if not ListedOrders then ListedOrders = {} end
if not ExecutedOrders then ExecutedOrders = {} end
if not CancelledOrders then CancelledOrders = {} end
if not ExpiredOrders then ExpiredOrders = {} end
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
	else
		if oc.ExpirationTime then
			oc.EndedAt = oc.ExpirationTime
		end
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


-- Reusable state updater to move expired orders from Listed to Expired
local function updateOrderStates(currentTimestamp)
	local currentTime = math.floor(tonumber(currentTimestamp))
	local remainingListed = {}
	local remainingExpired = ExpiredOrders
	for _, order in ipairs(ListedOrders) do
		local isExpired = false
		if order.ExpirationTime then
			local expirationTime = math.floor(tonumber(order.ExpirationTime))
			-- print('expirationTime')
			-- print(expirationTime)
			-- print(currentTime)
			-- print('--------------------------------')
			if currentTime >= expirationTime then
				if order.OrderType == 'english' then
					local auctionBids = AuctionBids[order.OrderId]
					if (auctionBids and auctionBids.HighestBidder) then
						order.Status = 'ready-for-settlement'
					else
						isExpired = true
						order.Status = 'expired'
					end
				else
					isExpired = true
					order.Status = 'expired'
				end
			end
		end

		if isExpired then
			order.EndedAt = order.ExpirationTime
			table.insert(remainingExpired, order)
		else
			table.insert(remainingListed, order)
		end
	end
	ListedOrders = remainingListed
	ExpiredOrders = remainingExpired
end

-- Get listed orders
Handlers.add('Get-Listed-Orders', Handlers.utils.hasMatchingTag('Action', 'Get-Listed-Orders'), function(msg)
	local page = utils.parsePaginationTags(msg)

	-- Build listed orders with proper status, and keep expired English auctions with winner
	local currentTimestamp = msg.Timestamp
	updateOrderStates(currentTimestamp)
	local ordersArray = {}
	for _, order in pairs(ListedOrders) do
		local orderCopy = utils.deepCopy(order)
		local status = order.Status or 'active'  -- Use the status set by updateOrderStates
		if status == 'active' or status == 'ready-for-settlement' then
			orderCopy = buildOrderResponse(order, status)
			table.insert(ordersArray, orderCopy)
		end
	end


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

	-- Ensure expired orders are moved first
	updateOrderStates(msg.Timestamp)

	local ordersArray = {}
	for _, order in pairs(CancelledOrders) do
		local orderCopy = buildOrderResponse(order, 'cancelled')
		table.insert(ordersArray, orderCopy)
	end

	for _, order in pairs(ExecutedOrders) do
		local orderCopy = buildOrderResponse(order, 'settled')
		table.insert(ordersArray, orderCopy)
	end

	-- Include expired orders
	for _, order in pairs(ExpiredOrders) do
		local orderCopy = buildOrderResponse(order, 'expired')
		table.insert(ordersArray, orderCopy)
	end


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

	-- Ensure expired orders are moved first
	updateOrderStates(msg.Timestamp)
	
	-- Search for the order in all order tables
	local foundOrder = nil
	local orderStatus = nil
	local orderSource = nil

	-- Check ListedOrders (active orders)
	for _, order in ipairs(ListedOrders) do
		if order.OrderId == orderId then
			foundOrder = order
			orderSource = 'ListedOrders'
			orderStatus = order.Status or 'active'  -- Use the status set by updateOrderStates
			break
		end
	end

	-- Check ExecutedOrders (settled orders)
	if not foundOrder then
		for _, order in ipairs(ExecutedOrders) do
			if order.OrderId == orderId then
				foundOrder = order
				orderStatus = 'settled'
				orderSource = 'ExecutedOrders'
				break
			end
		end
	end

	-- Check CancelledOrders (cancelled orders)
	if not foundOrder then
		for _, order in ipairs(CancelledOrders) do
			if order.OrderId == orderId then
				foundOrder = order
				orderStatus = 'cancelled'
				orderSource = 'CancelledOrders'
				break
			end
		end
	end

	-- Check ExpiredOrders (expired orders)
	if not foundOrder then
		for _, order in ipairs(ExpiredOrders) do
			if order.OrderId == orderId then
				foundOrder = order
				orderStatus = 'expired'
				orderSource = 'ExpiredOrders'
				break
			end
		end
	end

	if not foundOrder then
		ao.send({
			Target = msg.From,
			Action = 'Order-Not-Found',
			Message = 'Order with ID ' .. orderId .. ' not found'
		})
		return
	end

	-- Build the response with common fields
	local response =  foundOrder

	response = applyEnglishAuctionFields(response)
	response = normalizeOrderTimestamps(response)

	-- Add status-specific fields
	if orderStatus == 'settled' then
		response.EndedAt = foundOrder.EndedAt and math.floor(tonumber(foundOrder.EndedAt)) or nil
		response.Buyer = foundOrder.Receiver
	elseif orderStatus == 'expired' then
		response.EndedAt = foundOrder.ExpirationTime and math.floor(tonumber(foundOrder.ExpirationTime)) or nil
	elseif orderStatus == 'ready-for-settlement' then
		-- Add settlement-ready specific fields
		local auctionBids = AuctionBids[orderId]
		if auctionBids then
			response.HighestBid = auctionBids.HighestBid
			response.HighestBidder = auctionBids.HighestBidder
			response.CanSettle = true
		end
	elseif orderStatus == 'active' then
		-- No specific fields for active orders
	elseif orderStatus == 'cancelled' then
		response.EndedAt = foundOrder.EndedAt and math.floor(tonumber(foundOrder.EndedAt)) or nil
	end
	if foundOrder.OrderType == 'dutch' then
		response.StartingPrice = foundOrder.Price
		response.MinimumPrice = foundOrder.MinimumPrice
		response.DecreaseInterval = foundOrder.DecreaseInterval
		response.DecreaseStep = foundOrder.DecreaseStep
	elseif foundOrder.OrderType == 'fixed' then
		-- Fixed price orders don't have additional type-specific fields
	end

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

	-- Ensure latest state before reads
	updateOrderStates(msg.Timestamp)

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

	filteredListedOrders = filterOrders(ListedOrders, assetIdsSet, data.Address, startDate, endDate)
	filteredExecutedOrders = filterOrders(ExecutedOrders, assetIdsSet, data.Address, startDate, endDate)
	filteredCancelledOrders = filterOrders(CancelledOrders, assetIdsSet, data.Address, startDate, endDate)

	local function normalizeTimestamps(orders)
		local normalized = {}
		for _, o in ipairs(orders) do
			local oc = utils.deepCopy(o)
			-- Coerce all timestamp fields to integers
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
			else
				if oc.ExpirationTime then
					oc.EndedAt = oc.ExpirationTime
				end
			end
			table.insert(normalized, oc)
		end
		return normalized
	end

	local function attachAuctionFields(orders)
		local withFields = {}
		for _, o in ipairs(orders) do
			local oc = utils.deepCopy(o)
			oc = applyEnglishAuctionFields(oc)
			table.insert(withFields, oc)
		end
		return withFields
	end

	filteredListedOrders = normalizeTimestamps(filteredListedOrders)
	filteredExecutedOrders = normalizeTimestamps(filteredExecutedOrders)
	filteredCancelledOrders = normalizeTimestamps(filteredCancelledOrders)

	-- Add status/type specific fields
	local listedWithFields = attachAuctionFields(filteredListedOrders)
	local executedWithFields = attachAuctionFields(filteredExecutedOrders)
	local cancelledWithFields = attachAuctionFields(filteredCancelledOrders)
	local expiredWithFields = attachAuctionFields(normalizeTimestamps(ExpiredOrders))

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
