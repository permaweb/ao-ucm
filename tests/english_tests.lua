package.path = package.path .. ';../src/?.lua'

local ucm = require('ucm')
local utils = require('utils')

-- Global transfer tracking
local transfers = {}
ARIO_TOKEN_PROCESS_ID = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'

-- Mock ao.send for testing
ao = {
	send = function(msg)
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

-- Helper function to reset transfers for each test
local function resetTransfers()
	transfers = {}
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
					Type = 'english',
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
					Type = 'english',
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

utils.testSummary() 
