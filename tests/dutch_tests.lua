package.path = package.path .. ';../src/?.lua'

local ucm = require('ucm')
local utils = require('utils')

ao = {
	send = function(msg)
		if msg.Action == 'Transfer' then
			print(msg.Action .. ' ' .. msg.Tags.Quantity .. ' to ' .. msg.Tags.Recipient)
		else
			print(msg.Action)
		end
	 end
}

-- 96 hrs, step every 1 day, should decrease 4 times for 100000000000
utils.test('should add ANT sell order to orderbook when selling ANT to buy ARIO with Dutch auction',
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
			decreaseInterval = '86400000'
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

utils.testSummary() 
