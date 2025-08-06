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

-- 96 hrs, step every 1 day, should decrease 4 times for 100000000000
utils.test('should add ANT sell order to orderbook when selling ANT to buy ARIO with Dutch auction',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1, -- 1 ANT token
			price = '500000000000',
			timestamp = '1735689600000',
			blockheight = '123456789',
			orderType = 'dutch',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
			minimumPrice = '100000000000',
			decreaseInterval = '86400000'
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
					Type = 'dutch',
					MinimumPrice = '100000000000',
					DecreaseInterval = '86400000',
					DecreaseStep = '100000000000'
				}
			}
		}
	}
)

-- 24 hrs, step every 1 hour
-- should decrease 50000000000 / 24 = 2083333333 per hour
utils.test('should handle fractional decrease steps correctly in Dutch auction',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'fractional-test-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'fractional-seller',
			quantity = 1,
			price = '100000000000', -- 100 tokens
			timestamp = '1735689600000',
			blockheight = '123456789',
			orderType = 'dutch',
			orderGroupId = 'test-group',
			expirationTime = '1735776000000', -- 24 hours later
			minimumPrice = '50000000000', -- 50 tokens
			decreaseInterval = '3600000' -- 1 hour intervals
		})
		
		return Orderbook
	end,
	{
		{
			Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
			Orders = {
				{
					Id = 'fractional-test-order',
					Quantity = '1',
					OriginalQuantity = '1',
					Creator = 'fractional-seller',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					DateCreated = '1735689600000',
					ExpirationTime = '1735776000000',
					Price = '100000000000',
					Type = 'dutch',
					MinimumPrice = '50000000000',
					DecreaseInterval = '3600000',
					DecreaseStep = '2083333333'
				}
			}
		}
	}
)

utils.test('should fail if decrease interval is greater than expiration time',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1735689600000',
			blockheight = '123456789',
			orderType = 'dutch',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
			minimumPrice = '100000000000',
			decreaseInterval = '1736035200000'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should fail if minimum price is not provided',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1735689600000',
			blockheight = '123456789',
			orderType = 'dutch',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
			decreaseInterval = '1736035200000'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should fail if minimum price is negative',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1735689600000',
			blockheight = '123456789',
			orderType = 'dutch',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
			minimumPrice = '-100000000000',
			decreaseInterval = '1736035200000'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should fail if minimum price is 0',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1735689600000',
			blockheight = '123456789',
			orderType = 'dutch',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
			minimumPrice = '0',
			decreaseInterval = '1736035200000'
		})
		
		return Orderbook
	end,
	{
	}
)


utils.test('should fail if decrease interval is not provided',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1735689600000',
			blockheight = '123456789',
			orderType = 'dutch',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
			minimumPrice = '100000000000'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should fail if decrease interval is negative',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1735689600000',
			blockheight = '123456789',
			orderType = 'dutch',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
			minimumPrice = '100000000000',
			decreaseInterval = '-2'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should fail if decrease interval is 0',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1735689600000',
			blockheight = '123456789',
			orderType = 'dutch',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
			minimumPrice = '100000000000',
			decreaseInterval = '0'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should fail if expiration time is less than timestamp',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1735689600000',
			blockheight = '123456789',
			orderType = 'dutch',
			orderGroupId = 'test-group',
			expirationTime = '1735689500000', -- Earlier than timestamp
			minimumPrice = '100000000000',
			decreaseInterval = '86400000'
		})
		
		return Orderbook
	end,
	{
	}
)

-- 96 hrs, step every 1 day, should decrease 4 times for 100000000000
-- we are buying ANT token after one day, so the price should decrease once
-- the price should be: 500000000000 - 100000000000 = 400000000000
utils.test('[ANT purchase] should match dutch orders after time passes and price decreases',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1, -- 1 ANT token
			price = '500000000000',
			timestamp = '1735689600000',
			blockheight = '123456789',
			orderType = 'dutch',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
			minimumPrice = '100000000000',
			decreaseInterval = '86400000'
		})

		ucm.createOrder({
			orderId = 'ario-sell-order',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (selling ARIO)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-seller',
			quantity = 400000000000,  -- Send the current Dutch auction price (500000000000 - 100000000000)
			timestamp = '1735776001000', -- 1 and 1s day after the ant-sell-order timestamp
			blockheight = '123456790',
			orderType = 'dutch',
			requestedOrderId = 'ant-sell-order' -- Specify which ANT order to buy
		})
		
		-- Validate expected transfers
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '398000000000', -- After fees (400000000000 * 0.995)
				recipient = 'ant-seller',
				target = ARIO_TOKEN_PROCESS_ID
			},
			{
				action = 'Transfer',
				quantity = '1',
				recipient = 'ario-seller',
				target = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return Orderbook
	end,
	{
		{
			Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
			Orders = {
			}
		}
	}
)

utils.test('[ANT purchase] should refund excess ARIO when buyer sends more than required',
	function()
		resetTransfers()
		
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'ant-sell-order',
						Quantity = '1', -- 1 ANT token
						OriginalQuantity = '1',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1736035200000',
						Price = '500000000000',
						Type = 'dutch',
						MinimumPrice = '100000000000',
						DecreaseInterval = '86400000',
						DecreaseStep = '100000000000'
					}
				}
			}
		}

		ucm.createOrder({
			orderId = 'ario-buyer-excess',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (selling ARIO)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-buyer-excess',
			quantity = 500000000000,  -- Send more than the current price of 400000000000
			timestamp = '1735776001000', -- 1 and 1s day after the ant-sell-order timestamp
			blockheight = '123456790',
			orderType = 'dutch',
			requestedOrderId = 'ant-sell-order' -- Specify which ANT order to buy
		})
		
		-- Validate expected transfers
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '398000000000', -- After fees (400000000000 * 0.995)
				recipient = 'ant-seller',
				target = ARIO_TOKEN_PROCESS_ID
			},
			{
				action = 'Transfer',
				quantity = '1',
				recipient = 'ario-buyer-excess',
				target = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
			},
			{
				action = 'Transfer',
				quantity = '100000000000', -- Refund excess (500000000000 - 400000000000)
				recipient = 'ario-buyer-excess',
				target = ARIO_TOKEN_PROCESS_ID
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return Orderbook
	end,
	{
		{
			Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
			Orders = {
			}
		}
	}
)

utils.test('[ANT purchase] should reject order when buyer sends insufficient ARIO',
	function()
		resetTransfers()
		
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'ant-sell-order',
						Quantity = 1, -- 1 ANT token
						OriginalQuantity = '1',
						Price = '500000000000',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1735689600000',
						ExpirationTime = '1736035200000',
						Type = 'dutch',
						MinimumPrice = '100000000000',
						DecreaseInterval = '86400000',
						DecreaseStep = '100000000000'
					}
				}
			}
		}

		ucm.createOrder({
			orderId = 'ario-buyer-insufficient',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (selling ARIO)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-buyer-insufficient',
			quantity = 300000000000,  -- Send less than the current price of 400000000000
			timestamp = '1735776001000', -- 1 and 1s day after the ant-sell-order timestamp
			blockheight = '123456790',
			orderType = 'dutch',
			requestedOrderId = 'ant-sell-order' -- Specify which ANT order to buy
		})
		
		-- Validate expected transfers (should be refund only)
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '300000000000', -- Refund the sent amount
				recipient = 'ario-buyer-insufficient',
				target = ARIO_TOKEN_PROCESS_ID
			}
		}
		
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
					Quantity = 1, -- 1 ANT token
					Price = '500000000000',
					OriginalQuantity = '1',
					Creator = 'ant-seller',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					DateCreated = '1735689600000',
					ExpirationTime = '1736035200000',
					Type = 'dutch',
					MinimumPrice = '100000000000',
					DecreaseInterval = '86400000',
					DecreaseStep = '100000000000'
				}
			}
		}
	}
)

utils.testSummary() 
