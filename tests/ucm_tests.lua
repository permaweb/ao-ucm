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
utils.test('should execute immediate trade when selling ARIO to buy ANT with matching ANT order',
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

utils.test('should add ANT sell order to orderbook when selling ANT to buy ARIO',
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

utils.test('should reject order with invalid orderType',
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

utils.test('should reject order without ARIO token in trade',
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

utils.test('should fail when selling ARIO to buy ANT but no matching ANT orders exist',
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
utils.test('should fail when selling ARIO to buy specific ANT but only different ANT orders exist',
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
			},
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {}
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
		},
		{
			Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
			Orders = {}
		}
	}
)

-- Test edge cases
utils.test('should reject order with zero quantity',
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

utils.test('should reject order with negative quantity',
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

utils.test('should handle missing price for ARIO order by using default price',
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
			Orders = {}
		}
	}
)

-- TDD Test Cases
utils.test('should reject ANT sell order with quantity greater than 1',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order-too-many',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 2, -- More than 1 ANT - should be rejected
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

utils.test('should reject partial ANT purchase when selling ARIO',
	function()
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'existing-ant-order',
						Quantity = '2', -- ANT sell order with 2 tokens
						Price = '500000000000',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' -- ANT sell order
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-buy-partial-ant',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (selling ARIO)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-buyer',
			quantity = 1, -- Wanting to buy 1 ANT when 2 are available - partial purchase should be rejected
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
					Id = 'existing-ant-order',
					Quantity = '2', -- ANT sell order should remain unchanged
					Price = '500000000000',
					Creator = 'ant-seller',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
				}
			}
		}
	}
)

-- Token Address Validation Tests
utils.test('should reject orders with invalid token addresses',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'invalid-token-address-order',
			dominantToken = 'invalid-token-address-123', -- Invalid token address
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
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

utils.test('should reject orders with same token addresses',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'same-token-order',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- Same as dominantToken
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

utils.test('should reject orders with malformed token addresses',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'malformed-token-order',
			dominantToken = 'too-short', -- Too short for valid address
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
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

-- Fee Calculation Tests
utils.test('should apply correct fees to successful ANT trades',
	function()
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'existing-ant-order',
						Quantity = '1',
						Price = '1000000000000', -- 1000 ARIO per ANT
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' -- ANT sell order
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-buy-ant-with-fees',
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
			Orders = {}, -- ANT order should be matched and removed
			PriceData = {
				MatchLogs = {
					{
						Id = 'existing-ant-order',
						Quantity = '1',
						Price = '1000000000000'
					}
				},
				Vwap = '1000000000000',
				Block = '123456789',
				DominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
			}
		}
	}
)

utils.test('should handle fee calculation with very small amounts',
	function()
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'existing-ant-order-small',
						Quantity = '1',
						Price = '1000', -- Very small price
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' -- ANT sell order
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-buy-ant-small-amount',
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
			Orders = {}, -- ANT order should be matched and removed
			PriceData = {
				MatchLogs = {
					{
						Id = 'existing-ant-order-small',
						Quantity = '1',
						Price = '1000'
					}
				},
				Vwap = '1000',
				Block = '123456789',
				DominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
			}
		}
	}
)

-- Order Expiration Tests
utils.test('should handle order expiration correctly',
	function()
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'expired-ant-order',
						Quantity = '1',
						Price = '500000000000',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1722535710966',
						ExpirationTime = '1722535710965' -- Expired (past timestamp)
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-buy-expired-ant',
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
					Id = 'expired-ant-order',
					Quantity = '1',
					Price = '500000000000',
					Creator = 'ant-seller',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					DateCreated = '1722535710966',
					ExpirationTime = '1722535710965' -- Expired order should remain (not matched)
				}
			}
		}
	}
)

-- Concurrent Order Tests
utils.test('should handle multiple orders for same pair correctly',
	function()
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'ant-order-1',
						Quantity = '1',
						Price = '500000000000',
						Creator = 'ant-seller-1',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
					},
					{
						Id = 'ant-order-2',
						Quantity = '1',
						Price = '600000000000',
						Creator = 'ant-seller-2',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-buy-ant-multiple-orders',
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
					Id = 'ant-order-2',
					Quantity = '1',
					Price = '600000000000',
					Creator = 'ant-seller-2',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' -- Higher price order should remain
				}
			},
			PriceData = {
				MatchLogs = {
					{
						Id = 'ant-order-1',
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

utils.test('should maintain order priority correctly',
	function()
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'ant-order-older',
						Quantity = '1',
						Price = '500000000000',
						Creator = 'ant-seller-older',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1722535710960' -- Older order
					},
					{
						Id = 'ant-order-newer',
						Quantity = '1',
						Price = '500000000000', -- Same price
						Creator = 'ant-seller-newer',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1722535710965' -- Newer order
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-buy-ant-priority',
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
					Id = 'ant-order-newer',
					Quantity = '1',
					Price = '500000000000',
					Creator = 'ant-seller-newer',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					DateCreated = '1722535710965' -- Newer order should remain
				}
			},
			PriceData = {
				MatchLogs = {
					{
						Id = 'ant-order-older',
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

-- Duplicate ANT Sell Order Tests
utils.test('should reject duplicate ANT sell order for same ANT token',
	function()
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'existing-ant-order',
						Quantity = '1',
						Price = '500000000000',
						Creator = 'ant-seller-1',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' -- ANT already being sold
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'duplicate-ant-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- Same ANT token
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller-2',
			quantity = 1,
			price = '600000000000',
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
					Id = 'existing-ant-order',
					Quantity = '1',
					Price = '500000000000',
					Creator = 'ant-seller-1',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' -- Original order should remain unchanged
				}
			}
		}
	}
)

utils.test('should allow different ANT tokens to be sold simultaneously',
	function()
		Orderbook = {
			{
				Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
				Orders = {
					{
						Id = 'ant-order-1',
						Quantity = '1',
						Price = '500000000000',
						Creator = 'ant-seller-1',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' -- First ANT token
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ant-order-2',
			dominantToken = 'Xd1zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dGdS', -- Different ANT token
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller-2',
			quantity = 1,
			price = '600000000000',
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
					Id = 'ant-order-1',
					Quantity = '1',
					Price = '500000000000',
					Creator = 'ant-seller-1',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' -- First ANT token
				}
			}
		},
		{
			Pair = {'Xd1zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dGdS', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
			Orders = {
				{
					Id = 'ant-order-2',
					Quantity = '1',
					OriginalQuantity = '1',
					Creator = 'ant-seller-2',
					Token = 'Xd1zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dGdS',
					DateCreated = '1722535710966',
					Price = '600000000000'
				}
			}
		}
	}
)

utils.testSummary() 