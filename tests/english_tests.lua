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

utils.test('[ANT SELL] should add ANT sell order to orderbook when selling ANT to buy ARIO with English auction',
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
			orderType = 'english',
			orderGroupId = 'test-group',
			expirationTime = '1736035200000',
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
					Type = 'english',
				}
			}
		}
	}
)

utils.test('[ANT SELL] should fail if expiration time is not provided',
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
			orderType = 'english',
			orderGroupId = 'test-group',
		})
		
		return Orderbook
	end,
	{
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
			timestamp = '1735689600000',
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
			timestamp = '1735689600000',
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
			timestamp = '1735689600000',
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
			timestamp = '1735689600000',
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
			timestamp = '1735689600000',
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
			timestamp = '1735689600000',
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

utils.testSummary() 
