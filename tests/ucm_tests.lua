package.path = package.path .. ';../src/?.lua'

local ucm = require('ucm')
local utils = require('utils')

-- Mock ao.send for testing
ao = {
	send = function(msg)
		if msg.Action == 'Transfer' then
			print(msg.Action .. ' ' .. msg.Tags.Quantity .. ' to ' .. msg.Tags.Recipient)
		else
			print(msg.Action)
		end
	 end
}

-- Test complete createOrder function scenarios
utils.test('createOrder - ARIO token order (buy now)',
	function()
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'existing-ant-order',
						Quantity = '1',
						Price = '500000000000',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' -- ANT sell order
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-order-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (selling ARIO)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'buy-now',
			orderGroupId = 'test-group'
		})
		
		return Orderbook
	end,
	{
		{
			Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
			Orders = {}, -- ANT order should be matched and removed
			PriceData = {
				MatchLogs = {
					{
						Id = 'existing-ant-order',
						Quantity = '1',
						Price = '500000000000'
					}
				},
				Vwap = '500000000000',
				Block = '123456789',
				DominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
			}
		}
	}
)

utils.test('createOrder - ANT token order (add to orderbook)',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'buy-now',
			orderGroupId = 'test-group'
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
					DateCreated = '1722535710966',
					Price = '500000000000'
				}
			}
		}
	}
)

utils.test('createOrder - invalid orderType',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'invalid-order',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			sender = 'test-seller',
			quantity = 1000,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'limit', -- Invalid order type
			orderGroupId = 'test-group'
		})
		
		return Orderbook
	end,
	{}
)

utils.test('createOrder - missing ARIO token',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'no-ario-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			swapToken = 'some-other-token',
			sender = 'test-seller',
			quantity = 1000,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'buy-now',
			orderGroupId = 'test-group'
		})
		
		return Orderbook
	end,
	{}
)

utils.test('createOrder - ANT token with no matching orders',
	function()
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'existing-ario-order',
						Quantity = '2',
						Price = '500000000000',
						Creator = 'ario-seller',
						Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8' -- ARIO sell order
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-buy-ant-order',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (selling ARIO)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-buyer',
			quantity = 1,
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'buy-now',
			orderGroupId = 'test-group'
		})
		
		return Orderbook
	end,
	{
		{
			Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
			Orders = {
				{
					Id = 'existing-ario-order',
					Quantity = '2',
					Price = '500000000000',
					Creator = 'ario-seller',
					Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8' -- ARIO sell order should remain unchanged
				}
			}
		}
	}
)


-- FIXME
utils.test('createOrder - ANT token with different ANT address',
	function()
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'different-ant-token-address'},
				Orders = {
					{
						Id = 'existing-ant-order',
						Quantity = '1',
						Price = '500000000000',
						Creator = 'ant-seller',
						Token = 'different-ant-token-address' -- Different ANT token address
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-buy-specific-ant-order',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (selling ARIO)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- Specific ANT token (wanting specific ANT)
			sender = 'ario-buyer',
			quantity = 1,
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'buy-now',
			orderGroupId = 'test-group'
		})
		
		return Orderbook
	end,
	{
		{
			Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'different-ant-token-address'},
			Orders = {
				{
					Id = 'existing-ant-order',
					Quantity = '1',
					Price = '500000000000',
					Creator = 'ant-seller',
					Token = 'different-ant-token-address' -- Different ANT token should remain unchanged
				}
			}
		}
	}
)

-- Test edge cases
utils.test('createOrder - zero quantity',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'zero-quantity-order',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			sender = 'test-seller',
			quantity = 0, -- Invalid quantity
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'buy-now',
			orderGroupId = 'test-group'
		})
		
		return Orderbook
	end,
	{}
)

utils.test('createOrder - negative quantity',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'negative-quantity-order',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			sender = 'test-seller',
			quantity = -100, -- Invalid quantity
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'buy-now',
			orderGroupId = 'test-group'
		})
		
		return Orderbook
	end,
	{}
)

utils.test('createOrder - missing price for ARIO order',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'no-price-ario-order',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			sender = 'test-seller',
			quantity = 1000,
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'buy-now',
			orderGroupId = 'test-group'
		})
		
		return Orderbook
	end,
	{
		{
			Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
			Orders = {
				{
					Id = 'no-price-ario-order',
					Quantity = '1000',
					OriginalQuantity = '1000',
					Creator = 'test-seller',
					Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
					DateCreated = '1722535710966',
					Price = '0'
				}
			}
		}
	}
)

utils.testSummary() 