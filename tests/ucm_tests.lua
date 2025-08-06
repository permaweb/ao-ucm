package.path = package.path .. ';../src/?.lua'

local ucm = require('ucm')
local utils = require('utils')

-- Global transfer tracking
local transfers = {}

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

-- Test complete createOrder function scenarios
utils.test('should execute immediate trade when selling ARIO to buy ANT with matching ANT order',
	function()
		resetTransfers()
		
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'existing-ant-order',
						Quantity = '1',
						Price = '500000000000',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1722535710966',
						ExpirationTime = '1722535720966',
						Type = 'fixed'
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-order-1',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (selling ARIO)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-seller',
			quantity = 500000000000, -- Send exactly the ARIO amount that matches the ANT sell order price
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			requestedOrderId = 'existing-ant-order' -- Specify which ANT order to buy
		})
		
		-- Validate expected transfers
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '497500000000', -- After fees
				recipient = 'ant-seller',
				target = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
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
		resetTransfers()
		
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
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = '1722535720966' -- Valid expiration time
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
					DateCreated = '1722535710966',
					ExpirationTime = '1722535720966',
					Price = '500000000000',
					Type = 'fixed'
				}
			}
		}
	}
)

utils.test('should reject order with invalid orderType',
	function()
		resetTransfers()
		
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
		
		-- Validate that exactly one refund transfer occurred
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '1000', -- Refund the sent amount
				recipient = 'test-seller',
				target = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return Orderbook
	end,
	{}
)

utils.test('should reject order without ARIO token in trade',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'no-ario-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			swapToken = 'yU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			sender = 'test-seller',
			quantity = 1000,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group'
		})
		
		return Orderbook
	end,
	{}
)

utils.test('should fail when buying ANT with ARIO but no ANT orders exist to match against',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'no-price-ario-order',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			sender = 'test-seller',
			quantity = 500000000000, -- Send ARIO amount
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			requestedOrderId = 'non-existent-order' -- Try to buy a non-existent order
		})
		
		-- Validate that exactly one refund transfer occurred
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '500000000000', -- Refund the sent amount
				recipient = 'test-seller',
				target = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return Orderbook
	end,
	{
		{
			Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
			Orders = {}
		}
	}
)

utils.test('should fail when buying specific ANT with ARIO but only different ANT orders exist',
	function()
		resetTransfers()
		
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
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (using ARIO to buy)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- Specific ANT token (wanting specific ANT)
			sender = 'ario-buyer',
			quantity = 500000000000, -- Send ARIO amount
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			requestedOrderId = 'non-existent-specific-order' -- Try to buy a specific order that doesn't exist
		})
		
		-- Validate that exactly one refund transfer occurred
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '500000000000', -- Refund the sent amount
				recipient = 'ario-buyer',
				target = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
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
			Orders = {} -- No matching ANT orders for the specific token
		}
	}
)

-- Test edge cases
utils.test('should reject order with zero quantity',
	function()
		resetTransfers()
		
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
			orderType = 'fixed',
			orderGroupId = 'test-group'
		})
		
		-- Validate that no transfers occurred (fails early validation)
		local expectedTransfers = {}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return Orderbook
	end,
	{}
)

utils.test('should reject order with negative quantity',
	function()
		resetTransfers()
		
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
			orderType = 'fixed',
			orderGroupId = 'test-group'
		})
		
		-- Validate that no transfers occurred (fails early validation)
		local expectedTransfers = {}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return Orderbook
	end,
	{}
)

utils.test('should reject ANT sell order with quantity greater than 1',
	function()
		resetTransfers()
		
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
			orderType = 'fixed',
			orderGroupId = 'test-group'
		})
		
		-- Validate that exactly one refund transfer occurred
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '2', -- Refund the sent amount
				recipient = 'ant-seller',
				target = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return Orderbook
	end,
	{}
)

utils.test('should reject partial ANT purchase when buying with ARIO',
	function()
		resetTransfers()
		
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
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (using ARIO to buy)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-buyer',
			quantity = 250000000000, -- Wanting to buy 1 ANT when 2 are available - partial purchase should be rejected
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			requestedOrderId = 'existing-ant-order' -- Try to buy the specific order
		})
		
		-- Validate that exactly one refund transfer occurred
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '250000000000', -- Refund the sent amount
				recipient = 'ario-buyer',
				target = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
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
			orderType = 'fixed',
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
			orderType = 'fixed',
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
			orderType = 'fixed',
			orderGroupId = 'test-group'
		})
		
		return Orderbook
	end,
	{}
)

utils.test('should apply correct fees to successful ANT trades when buying with ARIO',
	function()
		resetTransfers()
		
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'existing-ant-order',
						Quantity = '1',
						Price = '1000000000000', -- 1000 ARIO per ANT
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						Type = 'fixed' -- ANT sell order
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-buy-ant-with-fees',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (using ARIO to buy)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-buyer',
			quantity = 1000000000000, -- Send exactly the ARIO amount that matches the ANT sell order price
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			requestedOrderId = 'existing-ant-order' -- Buy the specific ANT order
		})
		
		-- Validate that exactly two transfers occurred for successful trade
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '995000000000', -- After fees
				recipient = 'ant-seller',
				target = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
			},
			{
				action = 'Transfer',
				quantity = '1',
				recipient = 'ario-buyer',
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

utils.test('should handle fee calculation with very small amounts when buying ANT with ARIO',
	function()
		resetTransfers()
		
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'existing-ant-order-small',
						Quantity = '1',
						Price = '1000', -- Very small price
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						Type = 'fixed' -- ANT sell order
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-buy-ant-small-amount',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (using ARIO to buy)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-buyer',
			quantity = 1000, -- Send exactly the ARIO amount that matches the ANT sell order price
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			requestedOrderId = 'existing-ant-order-small' -- Buy the specific small amount order
		})
		
		-- Validate that exactly two transfers occurred for successful trade
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '995', -- After fees
				recipient = 'ant-seller',
				target = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
			},
			{
				action = 'Transfer',
				quantity = '1',
				recipient = 'ario-buyer',
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
utils.test('should not match expired ANT orders',
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
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (using ARIO to buy)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-buyer',
			quantity = 500000000000, -- Send exactly the ARIO amount that matches the ANT sell order price
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			requestedOrderId = 'expired-ant-order' -- Try to buy the expired order
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
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = '1722535720966' -- Add required expiration time
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
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						Type = 'fixed' -- First ANT token
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
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = '1753860134000'
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
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					Type = 'fixed' -- First ANT token
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
					ExpirationTime = '1753860134000',
					Price = '600000000000',
					Type = 'fixed'
				}
			}
		}
	}
)

utils.test('Should reject order with quantity 0 while selling ANT',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order-too-many',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 0, 
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group'
		})
		
		return Orderbook
	end,
	{}
)

utils.test('Should reject order with quantity 0 while buying ANT',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ant-sell-order-too-many',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (selling ARIO)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ant-seller',
			quantity = 0, 
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group'
		})
		
		return Orderbook
	end,
	{}
)

-- Expiration Time Tests
utils.test('should reject order without expiration time',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'no-expiration-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			sender = 'test-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group'
			-- missing expirationTime
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should reject order with expiration time equal to timestamp',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'expired-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			sender = 'test-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = '1722535710966' -- Same as timestamp
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should reject order with expiration time less than timestamp',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'past-expiration-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			sender = 'test-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = '1' -- Earlier than timestamp
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should reject order with invalid expiration time',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'invalid-expiration-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			sender = 'test-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = 'invalid-timestamp'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should accept order with valid expiration time greater than timestamp',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'valid-expiration-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'ant-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = '1722535720966' -- 10 seconds later
		})
		
		return Orderbook
	end,
	{
		{
			Pair = {'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'},
			Orders = {
				{
					Id = 'valid-expiration-order',
					Quantity = '1',
					OriginalQuantity = '1',
					Creator = 'ant-seller',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					DateCreated = '1722535710966',
					Price = '500000000000',
					ExpirationTime = '1722535720966',
					Type = 'fixed'
				}
			}
		}
	}
)

utils.test('should execute immediate trade with valid expiration time when selling ARIO to buy ANT',
	function()
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'existing-ant-order-with-expiration',
						Quantity = '1',
						Price = '500000000000',
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT sell order
						ExpirationTime = '1722535720966',
						Type = 'fixed'
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-order-with-expiration',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (selling ARIO)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-seller',
			quantity = 500000000000, -- Send exactly the ARIO amount that matches the ANT sell order price
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = '1722535720966', -- Valid expiration time
			requestedOrderId = 'existing-ant-order-with-expiration' -- Buy the specific order with expiration
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
						Id = 'existing-ant-order-with-expiration',
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

utils.test('should reject order with zero expiration time',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'zero-expiration-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			sender = 'test-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = '0'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should reject order with negative expiration time',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'negative-expiration-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			sender = 'test-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = '-1722535710966'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should reject order with invalid expiration time',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'invalid-expiration-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			sender = 'test-seller',
			quantity = 1,
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = 'invalid-timestamp'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should reject order with no price specified',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'no-price-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			sender = 'test-seller',
			quantity = 1,
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = '1722535720966'
			-- price is missing
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should reject order with negative price',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'negative-price-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			sender = 'test-seller',
			quantity = 1,
			price = '-500000000000', -- Negative price
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = '1722535720966'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should reject order with zero price',
	function()
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'zero-price-order',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO
			sender = 'test-seller',
			quantity = 1,
			price = '0', -- Zero price
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			expirationTime = '1722535720966'
		})
		
		return Orderbook
	end,
	{
	}
)

utils.test('should reject ARIO dominant order without requestedOrderId',
	function()
		resetTransfers()
		
		Orderbook = {}
		
		ucm.createOrder({
			orderId = 'ario-order-no-requested-id',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (selling ARIO)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-seller',
			quantity = 500000000000, -- Send ARIO amount
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group'
			-- missing requestedOrderId
		})
		
		-- Validate that exactly one refund transfer occurred (tokens were sent, then validation failed)
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '500000000000', -- Refund the sent amount
				recipient = 'ario-seller',
				target = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Return empty orderbook instead of nil to avoid serialization error
		end
		
		return Orderbook
	end,
	{}
)

utils.test('should reject ANT purchase when user sends different ARIO quantity than ANT sell order price',
	function()
		resetTransfers()
		
		Orderbook = {
			{
				Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
				Orders = {
					{
						Id = 'existing-ant-order',
						Quantity = '1',
						Price = '500000000000', -- ANT sell order price
						Creator = 'ant-seller',
						Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
						DateCreated = '1722535710966',
						ExpirationTime = '1722535720966',
						Type = 'fixed'
					}
				}
			}
		}
		
		ucm.createOrder({
			orderId = 'ario-order-wrong-quantity',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (selling ARIO)
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (wanting ANT)
			sender = 'ario-seller',
			quantity = 400000000000, -- Send different ARIO amount than the ANT sell order price
			timestamp = '1722535710966',
			blockheight = '123456789',
			orderType = 'fixed',
			orderGroupId = 'test-group',
			requestedOrderId = 'existing-ant-order' -- Specify which ANT order to buy
		})
		
		-- Validate that exactly one refund transfer occurred
		local expectedTransfers = {
			{
				action = 'Transfer',
				quantity = '400000000000', -- Refund the sent amount
				recipient = 'ario-seller',
				target = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
			}
		}
		
		if not validateTransfers(expectedTransfers) then
			return nil -- Test failed due to transfer mismatch
		end
		
		return Orderbook
	end,
	{
		{
			Pair = {'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'},
			Orders = {
				{
					Id = 'existing-ant-order',
					Quantity = '1',
					Price = '500000000000', -- ANT sell order should remain unchanged
					Creator = 'ant-seller',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					DateCreated = '1722535710966',
					ExpirationTime = '1722535720966',
					Type = 'fixed'
				}
			}
		}
	}
)

utils.testSummary() 