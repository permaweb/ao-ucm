local bint = require('.bint')(256)
local json = require('JSON')

local utils = require('utils')

UCM_PROCESS = '<UCM_PROCESS>'

if not ListedOrders then ListedOrders = {} end
if not ExecutedOrders then ExecutedOrders = {} end
if not CancelledOrders then CancelledOrders = {} end
if not SalesByAddress then SalesByAddress = {} end
if not PurchasesByAddress then PurchasesByAddress = {} end
if not AuctionBids then AuctionBids = {} end

-- Get listed orders
Handlers.add('Get-Listed-Orders', Handlers.utils.hasMatchingTag('Action', 'Get-Listed-Orders'), function(msg)
	local page = utils.parsePaginationTags(msg)

	local ordersArray = {}
	for _, order in pairs(ListedOrders) do
		local orderCopy = utils.deepCopy(order)
		table.insert(ordersArray, orderCopy)
	end

	-- Remove expired orders to show just active orders
	local currentTimestamp = msg.Timestamp
	for _, order in pairs(ordersArray) do
		if order.ExpirationTime then
			local expirationTime = bint(order.ExpirationTime)
			if currentTimestamp >= expirationTime then
				-- For English auctions with bids, keep them visible as ready-for-settlement
				if order.OrderType == 'english' then
					local auctionBids = AuctionBids[order.OrderId]
					if not (auctionBids and auctionBids.HighestBidder) then
						ordersArray[order.OrderId] = nil
					end
				else
					ordersArray[order.OrderId] = nil
				end
			end
		end
	end

	local paginatedOrders = utils.paginateTableWithCursor(ordersArray, page.cursor, page.cursorField, page.limit, page.sortBy, page.sortOrder, page.filters)

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode(paginatedOrders)
	})
end)

-- Get completed orders
Handlers.add('Get-Completed-Orders', Handlers.utils.hasMatchingTag('Action', 'Get-Completed-Orders'), function(msg)
	local page = utils.parsePaginationTags(msg)

	local ordersArray = {}
	for _, order in pairs(CancelledOrders) do
		local orderCopy = utils.deepCopy(order)
		orderCopy.Status = 'cancelled'
		table.insert(ordersArray, orderCopy)
	end

	for _, order in pairs(ExecutedOrders) do
		local orderCopy = utils.deepCopy(order)
		orderCopy.Status = 'settled'
		table.insert(ordersArray, orderCopy)
	end

	for _, order in pairs(ListedOrders) do
		-- Add just expired orders
		local currentTimestamp = msg.Timestamp
		if order.ExpirationTime then
			local expirationTime = bint(order.ExpirationTime)
			if currentTimestamp >= expirationTime then
				local orderCopy = utils.deepCopy(order)
				-- Check if it's an English auction with bids (ready-for-settlement)
				if order.OrderType == 'english' then
					local auctionBids = AuctionBids[order.OrderId]
					if auctionBids and auctionBids.HighestBidder then
						orderCopy.Status = 'ready-for-settlement'
					else
						orderCopy.Status = 'expired'
					end
				else
					orderCopy.Status = 'expired'
				end
				table.insert(ordersArray, orderCopy)
			end
		end
	end

	local paginatedOrders = utils.paginateTableWithCursor(ordersArray, page.cursor, page.cursorField, page.limit, page.sortBy, page.sortOrder, page.filters)

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode(paginatedOrders)
	})
end)

-- Get order by ID
Handlers.add('Get-Order-By-Id', Handlers.utils.hasMatchingTag('Action', 'Get-Order-By-Id'), function(msg)
	local decodeCheck, data = utils.decodeMessageData(msg.Data)

	if not decodeCheck or not data.OrderId then
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Message = 'OrderId is required'
		})
		return
	end

	local orderId = data.OrderId
	local currentTimestamp = msg.Timestamp
	
	-- Search for the order in all order tables
	local foundOrder = nil
	local orderStatus = nil
	local orderSource = nil

	-- Check ListedOrders (active orders)
	for _, order in ipairs(ListedOrders) do
		if order.OrderId == orderId then
			foundOrder = order
			orderSource = 'ListedOrders'
			
			-- Check if order has expired
			if order.CreatedAt and order.ExpirationTime then
				local expirationTime = bint(order.ExpirationTime)
				local currentTime = bint(currentTimestamp)
				
				if currentTime >= expirationTime then
					-- Check if it's an English auction with bids
					if order.OrderType == 'english' then
						local auctionBids = AuctionBids[orderId]
						if auctionBids and auctionBids.HighestBidder then
							orderStatus = 'ready-for-settlement'
						else
							orderStatus = 'expired'
						end
					else
						orderStatus = 'expired'
					end
				else
					orderStatus = 'active'
				end
			else
				orderStatus = 'active'
			end
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

	if not foundOrder then
		ao.send({
			Target = msg.From,
			Action = 'Order-Not-Found',
			Message = 'Order with ID ' .. orderId .. ' not found'
		})
		return
	end

	-- Build the response with common fields
	local response = {
		OrderId = foundOrder.OrderId,
		Status = orderStatus,
		Type = foundOrder.OrderType or 'fixed', -- Default to fixed if not specified
		CreatedAt = foundOrder.CreatedAt,
		ExpirationTime = foundOrder.ExpirationTime,
		DominantToken = foundOrder.DominantToken,
		SwapToken = foundOrder.SwapToken,
		Sender = foundOrder.Sender,
		Receiver = foundOrder.Receiver,
		Quantity = foundOrder.Quantity,
		Price = foundOrder.Price,
		Domain = foundOrder.Domain,
		OwnershipType = foundOrder.OwnershipType,
		LeaseStartTimestamp = foundOrder.LeaseStartTimestamp,
		LeaseEndTimestamp = foundOrder.LeaseEndTimestamp
	}

	-- Add status-specific fields
	if orderStatus == 'settled' then
		response.SettlementDate = foundOrder.CreatedAt
		response.Buyer = foundOrder.Receiver
		response.FinalPrice = foundOrder.Price
		
		-- For English auctions, include settlement details
		if foundOrder.OrderType == 'english' then
			local auctionBids = AuctionBids[orderId]
			if auctionBids and auctionBids.Settlement then
				response.Settlement = auctionBids.Settlement
			end
		end
	elseif orderStatus == 'expired' then
		-- No specific fields for expired orders
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
	end

	-- Add type-specific fields
	if foundOrder.OrderType == 'english' then
		-- Get bid information for English auctions
		local auctionBids = AuctionBids[orderId]
		if auctionBids then
			response.Bids = auctionBids.Bids
			response.HighestBid = auctionBids.HighestBid
			response.HighestBidder = auctionBids.HighestBidder
		else
			response.Bids = {}
			response.HighestBid = nil
			response.HighestBidder = nil
		end
		response.StartingPrice = foundOrder.Price
	elseif foundOrder.OrderType == 'dutch' then
		response.StartingPrice = foundOrder.Price
		response.MinimumPrice = foundOrder.MinimumPrice
		response.DecreaseInterval = foundOrder.DecreaseInterval
		response.DecreaseStep = foundOrder.DecreaseStep
	elseif foundOrder.OrderType == 'fixed' then
		-- Fixed price orders don't have additional type-specific fields
	end

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode(response)
	})
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

		foundOrder.EndedAt = data.Order.ExecutionTime
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

		foundOrder.EndedAt = data.Order.CancellationTime
		
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
				WinningBid = data.Settlement.WinningBid,
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
