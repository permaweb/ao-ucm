package.path = package.path .. ';../src/?.lua'

local ucm = require('ucm')
local utils = require('utils')
local json = require('JSON')

-- Global transfer tracking
local transfers = {}
ARIO_TOKEN_PROCESS_ID = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'

-- Capture sent messages for assertions
local sentMessages = {}

-- Mock ao.send for testing
ao = {
	send = function(msg)
		table.insert(sentMessages, msg)
		if msg.Action == 'Transfer' then
			local transfer = {
				action = msg.Action,
				quantity = msg.Tags.Quantity,
				recipient = msg.Tags.Recipient,
				target = msg.Target
			}
			table.insert(transfers, transfer)
			print(msg.Action .. ' ' .. msg.Tags.Quantity .. ' to ' .. msg.Tags.Recipient)
		else
			print(msg.Action)
		end
	 end
}

-- Minimal Handlers mock: store handlers by name when added
Handlers = {
	add = function(name, condition, handler)
		Handlers[name] = handler
	end,
	utils = {
		hasMatchingTag = function(tagName, tagValue)
			return function(msg)
				return msg.Tags and msg.Tags[tagName] == tagValue
			end
		end
	}
}

-- Globals used by the handler
ListedOrders = {}
ExecutedOrders = {}
CancelledOrders = {}
AuctionBids = {}

-- Helper function to reset transfers for each test
local function resetTransfers()
	transfers = {}
	sentMessages = {}
end

-- Helper function to reset state for Get-Order-By-Id tests
local function resetState()
	sentMessages = {}
	ListedOrders = {}
	ExecutedOrders = {}
	CancelledOrders = {}
	AuctionBids = {}
end

-- Helper function to decode data from sent messages
local function decodeDataFromMessage(index)
	if not sentMessages[index] or not sentMessages[index].Data then return nil end
	local ok, decoded = pcall(function()
		return json.decode(sentMessages[index].Data)
	end)
	if ok then return decoded end
	return nil
end

-- Helper function to validate expected transfers
local function validateTransfers(expectedTransfers)
	if not expectedTransfers then
		return true
	end
	
	if #transfers ~= #expectedTransfers then
		print("Transfer count mismatch: expected " .. #expectedTransfers .. ", got " .. #transfers)
		return false
	end
	
	for i, expected in ipairs(expectedTransfers) do
		local actual = transfers[i]
		if not actual then
			print("Missing transfer at index " .. i)
			return false
		end
		
		if actual.action ~= expected.action or 
		   actual.quantity ~= expected.quantity or 
		   actual.recipient ~= expected.recipient or
		   actual.target ~= expected.target then
			print("Transfer mismatch at index " .. i .. ":")
			print("  Expected: " .. expected.action .. " " .. expected.quantity .. " to " .. expected.recipient .. " (target: " .. expected.target .. ")")
			print("  Actual: " .. actual.action .. " " .. actual.quantity .. " to " .. actual.recipient .. " (target: " .. actual.target .. ")")
			return false
		end
	end
	
	return true
end

-- Implement Get-Order-By-Id handler inline for testing (mirrors src/activity.lua logic)
Handlers.add('Get-Order-By-Id', Handlers.utils.hasMatchingTag('Action', 'Get-Order-By-Id'), function(msg)
	local ok, data = pcall(function()
		return json.decode(msg.Data)
	end)

	if not ok or type(data) ~= 'table' or not data.OrderId then
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Message = 'OrderId is required'
		})
		return
	end

	local orderId = data.OrderId
	local currentTimestamp = tonumber(msg.Timestamp) or 0

	local foundOrder = nil
	local orderStatus = nil

	-- Listed orders (active/expired)
	for _, order in ipairs(ListedOrders) do
		if order.OrderId == orderId then
			foundOrder = order
			if order.CreatedAt and order.ExpirationTime then
				local exp = tonumber(order.ExpirationTime)
				if exp and currentTimestamp >= exp then
					orderStatus = 'expired'
				else
					orderStatus = 'active'
				end
			else
				orderStatus = 'active'
			end
			break
		end
	end

	-- Executed orders (settled)
	if not foundOrder then
		for _, order in ipairs(ExecutedOrders) do
			if order.OrderId == orderId then
				foundOrder = order
				orderStatus = 'settled'
				break
			end
		end
	end

	-- Cancelled orders (cancelled)
	if not foundOrder then
		for _, order in ipairs(CancelledOrders) do
			if order.OrderId == orderId then
				foundOrder = order
				orderStatus = 'cancelled'
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

	local response = {
		OrderId = foundOrder.OrderId,
		Status = orderStatus,
		OrderType = foundOrder.OrderType or 'fixed',
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

	if orderStatus == 'settled' then
		response.SettlementDate = foundOrder.CreatedAt
		response.Buyer = foundOrder.Receiver
		response.FinalPrice = foundOrder.Price
		if foundOrder.OrderType == 'english' then
			local bids = AuctionBids[orderId]
			if bids and bids.Settlement then
				response.Settlement = bids.Settlement
			end
		end
	end

	if foundOrder.OrderType == 'english' then
		local bids = AuctionBids[orderId]
		if bids then
			response.Bids = bids.Bids
			response.HighestBid = bids.HighestBid
			response.HighestBidder = bids.HighestBidder
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
	end

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode(response)
	})
end)

utils.test('[ANT SELL] should add ANT sell order to orderbook when selling ANT to buy ARIO with English auction',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
		})
		
		-- Validate that no transfers occurred (just adding to orderbook)
		local expectedTransfers = {}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return Orderbook
	end,
	{
		{
			Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
			Orders = {
				{
					Id = 'ant-sell-order',
					Quantity = '1',
					OriginalQuantity = '1',
					Creator = 'ant-seller',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					DateCreated = '1735689600000',
					ExpirationTime = '1736035200000',
					Price = '500000000000',
					OrderType = 'english'
				}
			}
		}
	}
)

utils.test('[ANT SELL] should pass if expiration time is not provided',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
		})
		
		return Orderbook
	end,
	{
		{
			Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
			Orders = {
				{
					Id = 'ant-sell-order',
					Quantity = '1',
					OriginalQuantity = '1',
					Creator = 'ant-seller',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					DateCreated = '1735689600000',
					ExpirationTime = nil,
					Price = '500000000000',
					OrderType = 'english'
				}
			}
		}
	}
)

utils.test('[ANT SELL] should fail if expiration time is negative',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '-1736035200000'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('[ANT SELL] should fail if expiration time is less than current time',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1735689500000'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('[ANT SELL] should fail if price is not provided',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1735689500000'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('[ANT SELL] should fail if price is negative',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '-500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1735689500000'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('[ANT SELL] should fail if quantity is negative',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = '-1',
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1735689500000'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('[ANT SELL] should fail if quantity is not 1',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 2,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1735689500000'
		})
		
		return Orderbook
	end,
	{
	}
)

-- English Auction Bid Tests

utils.test('[ENGLISH AUCTION] should fail bid with invalid bid amount (negative)',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		-- Create the English auction order first
		ucm.createOrder({
			orderId = 'english-auction-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
		})
		
		-- Try to place invalid bid
		ucm.createOrder({
			orderId = 'bid-1',
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-1',
			quantity = -1000000000, -- Negative quantity should be rejected
			createdAt = '1735689700000',
			orderType = 'english',
			orderGroupId = 'test-group',
					requestedOrderId = 'english-auction-1'
		})
		
		-- Validate that no transfers occurred (invalid bid should be rejected)
		local expectedTransfers = {}		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return {Orderbook = Orderbook, EnglishAuctionBids = EnglishAuctionBids}
	end,
	{
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'english-auction-1',
						Quantity = '1',
						OriginalQuantity = '1',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1736035200000',
						Price = '500000000000',
						Type = 'english',
					}
				}
			}
		},
		EnglishAuctionBids = {}
	}
)

utils.test('[ENGLISH AUCTION] should fail bid with missing orderId',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		-- Create the English auction order first
		ucm.createOrder({
			orderId = 'english-auction-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
		})
		
		-- Try to place bid without orderId
		ucm.createOrder({
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-1',
			quantity = 1000000000,
			createdAt = '1735689700000',
			orderType = 'english',
			orderGroupId = 'test-group',
		})
		
		-- Validate that no transfers occurred (invalid bid should be rejected)
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '1000000000',
				recipient = 'bidder-1',
				target = ARIO_TOKEN_PROCESS_ID
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return {Orderbook = Orderbook, EnglishAuctionBids = EnglishAuctionBids}
	end,
	{
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'english-auction-1',
						Quantity = '1',
						OriginalQuantity = '1',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1736035200000',
						Price = '500000000000',
						Type = 'english',
					}
				}
			}
		},
		EnglishAuctionBids = {}
	}
)

utils.test('[ENGLISH AUCTION] should fail bid on expired auction',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		-- Create the English auction order first (already expired)
		ucm.createOrder({
			orderId = 'english-auction-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1735689700000', -- Expired
		})
		
		-- Try to place bid on expired auction
		ucm.createOrder({
			orderId = 'bid-1',
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-1',
			quantity = 1000000000,
			createdAt = '1735689800000', -- After expiration
			orderType = 'english',
			orderGroupId = 'test-group',
			requestedOrderId = 'english-auction-1'
		})
		
		-- Validate that no transfers occurred (expired auction should be rejected)
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '1000000000',
				recipient = 'bidder-1',
				target = ARIO_TOKEN_PROCESS_ID
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return {Orderbook = Orderbook, EnglishAuctionBids = EnglishAuctionBids}
	end,
	{
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'english-auction-1',
						Quantity = '1',
						OriginalQuantity = '1',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1735689700000',
						Price = '500000000000',
						Type = 'english',
					}
				}
			}
		},
		EnglishAuctionBids = {}
	}
)

utils.test('[ENGLISH AUCTION] should allow first bid on active auction',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		-- Create the English auction order first
		ucm.createOrder({
			orderId = 'english-auction-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
		})
		
		-- Place first bid
		ucm.createOrder({
			orderId = 'bid-1',
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-1',
			quantity = 600000000000,
			createdAt = '1735689700000',
			orderType = 'english',
			orderGroupId = 'test-group',
			requestedOrderId = 'english-auction-1'
		})
		
		-- Validate that no transfers occurred (just placing bid)
		local expectedTransfers = {}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return {Orderbook = Orderbook, EnglishAuctionBids = EnglishAuctionBids}
	end,
	{
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'english-auction-1',
						Quantity = '1',
						OriginalQuantity = '1',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1736035200000',
						Price = '500000000000',
						Type = 'english',
					}
				}
			}
		},
		EnglishAuctionBids = {
			['english-auction-1'] = {
				Bids = {
					{
						Bidder = 'bidder-1',
						Amount = '600000000000',
						Timestamp = '1735689700000',
						OrderId = 'english-auction-1'
					}
				},
				HighestBid = '600000000000',
				HighestBidder = 'bidder-1'
			}
		}
	}
)

utils.test('[ENGLISH AUCTION] should allow second bid and return first bid',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		-- Create the English auction order first
		ucm.createOrder({
			orderId = 'english-auction-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
		})
		
		-- Place first bid
		ucm.createOrder({
			orderId = 'bid-1',
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-1',
			quantity = 600000000000,
			createdAt = '1735689700000',
			orderType = 'english',
			orderGroupId = 'test-group',
			requestedOrderId = 'english-auction-1'
		})
		
		-- Reset transfers for second bid
		resetTransfers()
		
		-- Place second bid
		ucm.createOrder({
			orderId = 'bid-2',
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-2',
			quantity = 2000000000000,
			createdAt = '1735689800000',
			orderType = 'english',
			orderGroupId = 'test-group',
			requestedOrderId = 'english-auction-1'
		})
		
		-- Validate expected transfers (refund to first bidder)
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '600000000000', -- Refund to first bidder
				recipient = 'bidder-1',
				target = ARIO_TOKEN_PROCESS_ID
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return {Orderbook = Orderbook, EnglishAuctionBids = EnglishAuctionBids}
	end,
	{
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'english-auction-1',
						Quantity = '1',
						OriginalQuantity = '1',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1736035200000',
						Price = '500000000000',
						Type = 'english',
					}
				}
			}
		},
		EnglishAuctionBids = {
			['english-auction-1'] = {
				Bids = {
					{
						Bidder = 'bidder-1',
						Amount = '600000000000',
						Timestamp = '1735689700000',
						OrderId = 'english-auction-1'
					},
					{
						Bidder = 'bidder-2',
						Amount = '2000000000000',
						Timestamp = '1735689800000',
						OrderId = 'english-auction-1'
					}
				},
				HighestBid = '2000000000000',
				HighestBidder = 'bidder-2'
			}
		}
	}
)

utils.test('[ENGLISH AUCTION] should fail bid lower than current highest',
	function()
		resetTransfers()
		
		Orderbook = {}
		EnglishAuctionBids = {}
		
		-- Create the English auction order first
		ucm.createOrder({
			orderId = 'english-auction-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
		})
		
		-- Place first bid (above minimum starting price)
		ucm.createOrder({
			orderId = 'bid-1',
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-1',
			quantity = 600000000000, -- Above minimum starting price (500000000000)
			createdAt = '1735689700000',
			orderType = 'english',
			orderGroupId = 'test-group',
			requestedOrderId = 'english-auction-1'
		})
		
		-- Try to place lower bid
		ucm.createOrder({
			orderId = 'bid-2',
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-2',
			quantity = 500000000000, -- Lower than current highest bid (600000000000) but above minimum
			createdAt = '1735689800000',
			orderType = 'english',
			orderGroupId = 'test-group',
			requestedOrderId = 'english-auction-1'
		})
		
		-- Validate that only the rejected bid transfer occurred (lower bid should be rejected)
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '500000000000',
				recipient = 'bidder-2',
				target = ARIO_TOKEN_PROCESS_ID
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return {Orderbook = Orderbook, EnglishAuctionBids = EnglishAuctionBids}
	end,
	{
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'english-auction-1',
						Quantity = '1',
						OriginalQuantity = '1',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1736035200000',
						Price = '500000000000',
						Type = 'english',
					}
				}
			}
		},
		EnglishAuctionBids = {
			['english-auction-1'] = {
				Bids = {
					{
						Bidder = 'bidder-1',
						Amount = '600000000000',
						Timestamp = '1735689700000',
						OrderId = 'english-auction-1'
					}
				},
				HighestBid = '600000000000',
				HighestBidder = 'bidder-1'
			}
		}
	}
)

utils.test('[ENGLISH AUCTION] should settle auction successfully after expiration',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		-- Create the English auction order first (already expired)
		ucm.createOrder({
			orderId = 'english-auction-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1735689700000',
		})
		
		-- Set up existing bids manually since we need to test settlement
		EnglishAuctionBids = {
			['english-auction-1'] = {
				Bids = {
					{
						Bidder = 'bidder-1',
						Amount = '1000000000',
						Timestamp = '1735689700000',
						OrderId = 'english-auction-1'
					},
					{
						Bidder = 'bidder-2',
						Amount = '600000000000',
						Timestamp = '1735689800000',
						OrderId = 'english-auction-1'
					}
				},
				HighestBid = '600000000000',
				HighestBidder = 'bidder-2'
			}
		}
		
		-- Settle the auction
		ucm.settleAuction({
			orderId = 'english-auction-1',
			timestamp = '1735689900000', -- After expiration
			orderGroupId = 'test-group',
		})
		
		-- Validate expected transfers
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '597000000000', -- After fees (600000000000 * 0.995)
				recipient = 'ant-seller',
				target = ARIO_TOKEN_PROCESS_ID
			},
			{
				action = 'Transfer',
				quantity = '1',
				recipient = 'bidder-2',
				target = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return {Orderbook = Orderbook, EnglishAuctionBids = EnglishAuctionBids}
	end,
	{
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {}
			}
		},
		EnglishAuctionBids = {}
	}
)

utils.test('[ENGLISH AUCTION] should fail settlement before expiration',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		-- Create the English auction order first (not expired)
		ucm.createOrder({
			orderId = 'english-auction-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000', -- Not expired
		})
		
		-- Set up existing bids manually since we need to test settlement
		EnglishAuctionBids = {
			['english-auction-1'] = {
				Bids = {
					{
						Bidder = 'bidder-1',
						Amount = '600000000000',
						Timestamp = '1735689700000',
						OrderId = 'english-auction-1'
					}
				},
				HighestBid = '600000000000',
				HighestBidder = 'bidder-1'
			}
		}
		
		-- Try to settle before expiration
		ucm.settleAuction({
			orderId = 'english-auction-1',
			timestamp = '1735689700000', -- Before expiration
			orderGroupId = 'test-group',
		})
		
		-- Validate expected transfers (no transfers should occur)
		local expectedTransfers = {}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return {Orderbook = Orderbook, EnglishAuctionBids = EnglishAuctionBids}
	end,
	{
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'english-auction-1',
						Quantity = '1',
						OriginalQuantity = '1',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1736035200000',
						Price = '500000000000',
						Type = 'english',
					}
				}
			}
		},
		EnglishAuctionBids = {
			['english-auction-1'] = {
				Bids = {
					{
						Bidder = 'bidder-1',
						Amount = '600000000000',
						Timestamp = '1735689700000',
						OrderId = 'english-auction-1'
					}
				},
				HighestBid = '600000000000',
				HighestBidder = 'bidder-1'
			}
		}
	}
)

utils.test('[ENGLISH AUCTION] should fail settlement with no bids',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		-- Create the English auction order first (already expired)
		ucm.createOrder({
			orderId = 'english-auction-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1735689700000', -- Expired
		})
		
		-- No bids
		EnglishAuctionBids = {}
		
		-- Try to settle with no bids
		ucm.settleAuction({
			orderId = 'english-auction-1',
			timestamp = '1735689900000', -- After expiration
			orderGroupId = 'test-group',
		})
		
		-- Validate expected transfers (no transfers should occur)
		local expectedTransfers = {}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return {Orderbook = Orderbook, EnglishAuctionBids = EnglishAuctionBids}
	end,
	{
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'english-auction-1',
						Quantity = '1',
						OriginalQuantity = '1',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1735689700000',
						Price = '500000000000',
						Type = 'english',
					}
				}
			}
		},
		EnglishAuctionBids = {}
	}
)

utils.test('[ENGLISH AUCTION] should fail first bid below minimum price',
	function()
		resetTransfers()

		Orderbook = {}

		-- Create the English auction order first
		ucm.createOrder({
			orderId = 'english-auction-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
		})

		-- Place first bid lower than minimum starting price
		ucm.createOrder({
			orderId = 'bid-1',
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-1',
			quantity = 1000000000, -- Below minimum starting price
			createdAt = '1735689700000',
			orderType = 'english',
			orderGroupId = 'test-group',
			requestedOrderId = 'english-auction-1'
		})

		-- Validate refund occurred
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '1000000000',
				recipient = 'bidder-1',
				target = ARIO_TOKEN_PROCESS_ID
			}
		}

		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end

		return {Orderbook = Orderbook, EnglishAuctionBids = EnglishAuctionBids}
	end,
	{
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'english-auction-1',
						Quantity = '1',
						OriginalQuantity = '1',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1736035200000',
						Price = '500000000000',
						Type = 'english',
					}
				}
			}
		},
		EnglishAuctionBids = {}
	}
)

utils.test('[ENGLISH AUCTION] should fail bid that does not meet minimum 1 ARIO increment',
	function()
		resetTransfers()

		Orderbook = {}

		-- Create the English auction order first
		ucm.createOrder({
			orderId = 'english-auction-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
		})

		-- Place first bid (above minimum starting price)
		ucm.createOrder({
			orderId = 'bid-1',
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-1',
			quantity = 600000000000, -- Above minimum starting price
			createdAt = '1735689700000',
			orderType = 'english',
			orderGroupId = 'test-group',
			requestedOrderId = 'english-auction-1'
		})

		-- Reset transfers for second bid
		resetTransfers()

		-- Try to place bid that's only 1 unit higher (should fail - needs to be at least 1 ARIO higher)
		ucm.createOrder({
			orderId = 'bid-2',
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-2',
			quantity = 600000000001, -- Only 1 unit higher than current bid (600000000000)
			createdAt = '1735689800000',
			orderType = 'english',
			orderGroupId = 'test-group',
			requestedOrderId = 'english-auction-1'
		})

		-- Validate that only the rejected bid transfer occurred (bid should be rejected for not meeting minimum increment)
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '600000000001',
				recipient = 'bidder-2',
				target = ARIO_TOKEN_PROCESS_ID
			}
		}

		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end

		return {Orderbook = Orderbook, EnglishAuctionBids = EnglishAuctionBids}
	end,
	{
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'english-auction-1',
						Quantity = '1',
						OriginalQuantity = '1',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1736035200000',
						Price = '500000000000',
						Type = 'english',
					}
				}
			}
		},
		EnglishAuctionBids = {
			['english-auction-1'] = {
				Bids = {
					{
						Bidder = 'bidder-1',
						Amount = '600000000000',
						Timestamp = '1735689700000',
						OrderId = 'english-auction-1'
					}
				},
				HighestBid = '600000000000',
				HighestBidder = 'bidder-1'
			}
		}
	}
)

utils.test('[ENGLISH AUCTION] should allow bid that meets minimum 1 ARIO increment',
	function()
		resetTransfers()

		Orderbook = {}

		-- Create the English auction order first
		ucm.createOrder({
			orderId = 'english-auction-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			createdAt = '1735689600000',
			blockheight = '123456789',
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
		})

		-- Place first bid (above minimum starting price)
		ucm.createOrder({
			orderId = 'bid-1',
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-1',
			quantity = 600000000000, -- Above minimum starting price
			createdAt = '1735689700000',
			orderType = 'english',
			orderGroupId = 'test-group',
			requestedOrderId = 'english-auction-1'
		})

		-- Reset transfers for second bid
		resetTransfers()

		-- Place bid that meets minimum 1 ARIO increment (exactly 1 ARIO higher)
		ucm.createOrder({
			orderId = 'bid-2',
			targetAuctionId = 'english-auction-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (buying ANT)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			sender = 'bidder-2',
			quantity = 600000001000, -- Exactly 1 ARIO (1000 units) higher than current bid
			createdAt = '1735689800000',
			orderType = 'english',
			orderGroupId = 'test-group',
			requestedOrderId = 'english-auction-1'
		})

		-- Validate expected transfers (refund to first bidder)
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '600000000000', -- Refund to first bidder
				recipient = 'bidder-1',
				target = ARIO_TOKEN_PROCESS_ID
			}
		}

		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end

		return {Orderbook = Orderbook, EnglishAuctionBids = EnglishAuctionBids}
	end,
	{
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'english-auction-1',
						Quantity = '1',
						OriginalQuantity = '1',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1736035200000',
						Price = '500000000000',
						Type = 'english',
					}
				}
			}
		},
		EnglishAuctionBids = {
			['english-auction-1'] = {
				Bids = {
					{
						Bidder = 'bidder-1',
						Amount = '600000000000',
						Timestamp = '1735689700000',
						OrderId = 'english-auction-1'
					},
					{
						Bidder = 'bidder-2',
						Amount = '600000001000',
						Timestamp = '1735689800000',
						OrderId = 'english-auction-1'
					}
				},
				HighestBid = '600000001000',
				HighestBidder = 'bidder-2'
			}
		}
	}
)

utils.test('[ENGLISH AUCTION] Get-Order-By-Id should return correct buyer address for settled auction',
	function()
		resetState()
		
		-- Set up test environment with settled English auction
		Orderbook = {}
		
		-- Create a settled English auction order in ExecutedOrders
		local settledOrder = {
			OrderId = 'english-auction-settled',
			OrderType = 'english',
			DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			SwapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			Sender = 'ant-seller',
			Receiver = 'bidder-winner', -- This should be the buyer
			Quantity = '1',
			Price = '2000000000000', -- Final winning bid amount
			CreatedAt = '1735689900000', -- Settlement timestamp
			Domain = 'test-domain',
			OwnershipType = 'full',
			LeaseStartTimestamp = nil,
			LeaseEndTimestamp = nil
		}
		
		table.insert(ExecutedOrders, settledOrder)
		
		-- Set up auction bids data with settlement information
		AuctionBids = {
			['english-auction-settled'] = {
				Bids = {
					{
						Bidder = 'bidder-1',
						Amount = '1000000000000',
						Timestamp = '1735689700000',
						OrderId = 'english-auction-settled'
					},
					{
						Bidder = 'bidder-winner',
						Amount = '2000000000000',
						Timestamp = '1735689800000',
						OrderId = 'english-auction-settled'
					}
				},
				HighestBid = '2000000000000',
				HighestBidder = 'bidder-winner',
				Settlement = {
					OrderId = 'english-auction-settled',
					Winner = 'bidder-winner',
					WinningBid = '2000000000000',
					Quantity = '1',
					Timestamp = '1735689900000',
					DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					SwapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
				}
			}
		}
		
		-- Mock the Get-Order-By-Id handler call
		local msg = {
			From = 'test-requester',
			Tags = { Action = 'Get-Order-By-Id' },
			Data = json.encode({ OrderId = 'english-auction-settled' }),
			Timestamp = '1735690000000'
		}
		
		-- Call the handler
		Handlers['Get-Order-By-Id'](msg)
		

		
		-- Decode the response
		local response = decodeDataFromMessage(1)
		
		return response
	end,
	{
		OrderId = 'english-auction-settled',
		Status = 'settled',
		Type = 'english',
		CreatedAt = '1735689900000',
		ExpirationTime = nil,
		DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
		SwapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
		Sender = 'ant-seller',
		Receiver = 'bidder-winner', -- This is the buyer
		Quantity = '1',
		Price = '2000000000000',
		Domain = 'test-domain',
		OwnershipType = 'full',
		LeaseStartTimestamp = nil,
		LeaseEndTimestamp = nil,
		SettlementDate = '1735689900000',
		Buyer = 'bidder-winner', -- This should match the highest bidder
		FinalPrice = '2000000000000',
		Bids = {
			{
				Bidder = 'bidder-1',
				Amount = '1000000000000',
				Timestamp = '1735689700000',
				OrderId = 'english-auction-settled'
			},
			{
				Bidder = 'bidder-winner',
				Amount = '2000000000000',
				Timestamp = '1735689800000',
				OrderId = 'english-auction-settled'
			}
		},
		HighestBid = '2000000000000',
		HighestBidder = 'bidder-winner',
		StartingPrice = '2000000000000',
		Settlement = {
			OrderId = 'english-auction-settled',
			Winner = 'bidder-winner',
			WinningBid = '2000000000000',
			Quantity = '1',
			Timestamp = '1735689900000',
			DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			SwapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
		}
	}
)

utils.testSummary()
