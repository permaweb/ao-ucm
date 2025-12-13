package.path = package.path .. ';../src/?.lua'

Handlers = {
	add = function(name, pattern, handler) end,
	prepend = function(name, pattern, handler) end,
	utils = {
		hasMatchingTag = function(tag, value)
			return function(msg)
				return msg.Tags and msg.Tags[tag] == value
			end
		end,
		reply = function(message)
			return function(msg) end
		end,
	},
}

local ucm = {}
local micro_ucm = require('micro_ucm')
ucm.createOrder = micro_ucm.createOrder

local utils = {}
local micro_utils = require('global_utils')
utils.test = micro_utils.test
utils.testSummary = micro_utils.testSummary

ao = {
	send = function(msg)
		print('-------------------- Test Message ---------------------')
		print(msg.Action)
		if msg.Action == 'Transfer' then
			print('Target: ' .. msg.Target)
			print('Recipient: ' .. msg.Tags.Recipient)
			print('Quantity: ' .. msg.Tags.Quantity)
		elseif msg.Action == 'Order-Error' then
			print('Error: ' .. (msg.Tags.Message or 'Unknown Error'))
		end
		print('-------------------------------------------------------\n')
	end,
}

local BASE_TOKEN = 'BASE_TOKEN_1234567890abcdefghijklmnopqrstuv'
local QUOTE_TOKEN = 'QUOTE_TOKEN_234567890abcdefghijklmnopqrstuv'
local SELLER_1 = 'SELLER_1_34567890abcdefghijklmnopqrstuvwxyz'
local BUYER_1 = 'BUYER_1_234567890abcdefghijklmnopqrstuvwxyz'

utils.test('Create ask with denominations', function()
	Orderbook = {}
	ORDERBOOK_MIGRATED = false

	ucm.createOrder({
		orderId = 'ask-1',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = SELLER_1,
		quantity = '1000000000000000000',
		price = '1000000',
		timestamp = '1722535710966',
		blockheight = '123456789',
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {
			{
				Creator = SELLER_1,
				DateCreated = '1722535710966',
				Id = 'ask-1',
				OriginalQuantity = '1000000000000000000',
				Price = '1000000',
				Quantity = '1000000000000000000',
				Token = BASE_TOKEN,
				Side = 'Ask',
			},
		},
		Bids = {},
	},
})

utils.test('Buy partially matches ask with denominations', function()
	Orderbook = {
		{
			Pair = { BASE_TOKEN, QUOTE_TOKEN },
			Denominations = { '1000000000000000000', '1000000' },
			Asks = {
				{
					Creator = SELLER_1,
					DateCreated = '1722535710966',
					Id = 'ask-1',
					OriginalQuantity = '1000000000000000000',
					Price = '1000000',
					Quantity = '1000000000000000000',
					Token = BASE_TOKEN,
					Side = 'Ask',
				},
			},
			Bids = {},
		},
	}
	ORDERBOOK_MIGRATED = true

	-- Buy 0.5 base tokens (0.5e18 raw) for 0.5 quote tokens (0.5e6 raw)
	ucm.createOrder({
		orderId = 'buy-1',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_1,
		quantity = '500000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710967',
		blockheight = '123456790',
		syncState = function() end,
	})

	-- Buy another 0.25 base tokens
	ucm.createOrder({
		orderId = 'buy-2',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_1,
		quantity = '250000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710968',
		blockheight = '123456791',
		syncState = function() end,
	})

	-- Buy final 0.25 base tokens to complete the order
	ucm.createOrder({
		orderId = 'buy-3',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_1,
		quantity = '250000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710969',
		blockheight = '123456792',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {},
		Bids = {},
		PriceData = {
			MatchLogs = {
				{
					Quantity = '500000000000000000',
					Price = '1000000',
					Id = 'ask-1',
				},
				{
					Quantity = '250000000000000000',
					Price = '1000000',
					Id = 'ask-1',
				},
				{
					Quantity = '250000000000000000',
					Price = '1000000',
					Id = 'ask-1',
				},
			},
			Vwap = '1000000',
			Block = '123456792',
			DominantToken = QUOTE_TOKEN,
		},
	},
})

utils.test('Buy fully matches ask with denominations in one order', function()
	Orderbook = {
		{
			Pair = { BASE_TOKEN, QUOTE_TOKEN },
			Denominations = { '1000000000000000000', '1000000' },
			Asks = {
				{
					Creator = SELLER_1,
					DateCreated = '1722535710966',
					Id = 'ask-2',
					OriginalQuantity = '1000000000000000000',
					Price = '1000000',
					Quantity = '1000000000000000000',
					Token = BASE_TOKEN,
					Side = 'Ask',
				},
			},
			Bids = {},
		},
	}
	ORDERBOOK_MIGRATED = true

	-- Buy 1 full base token (1e18 raw) for 1 quote token (1e6 raw)
	ucm.createOrder({
		orderId = 'buy-full',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_1,
		quantity = '1000000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710967',
		blockheight = '123456790',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {},
		Bids = {},
		PriceData = {
			MatchLogs = {
				{
					Quantity = '1000000000000000000',
					Price = '1000000',
					Id = 'ask-2',
				},
			},
			Vwap = '1000000',
			Block = '123456790',
			DominantToken = QUOTE_TOKEN,
		},
	},
})

utils.test('Create bid with denominations', function()
	Orderbook = {}
	ORDERBOOK_MIGRATED = false

	ucm.createOrder({
		orderId = 'bid-1',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_1,
		quantity = '1000000',
		price = '1000000',
		timestamp = '1722535710966',
		blockheight = '123456789',
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {},
		Bids = {
			{
				Creator = BUYER_1,
				DateCreated = '1722535710966',
				Id = 'bid-1',
				OriginalQuantity = '1000000',
				Price = '1000000',
				Quantity = '1000000',
				Token = QUOTE_TOKEN,
				Side = 'Bid',
			},
		},
	},
})

utils.test('Sell partially matches bid with denominations', function()
	Orderbook = {
		{
			Pair = { BASE_TOKEN, QUOTE_TOKEN },
			Denominations = { '1000000000000000000', '1000000' },
			Asks = {},
			Bids = {
				{
					Creator = BUYER_1,
					DateCreated = '1722535710966',
					Id = 'bid-1',
					OriginalQuantity = '1000000',
					Price = '1000000',
					Quantity = '1000000',
					Token = QUOTE_TOKEN,
					Side = 'Bid',
				},
			},
		},
	}
	ORDERBOOK_MIGRATED = true

	-- Sell 0.5 base tokens (0.5e18 raw) for 0.5 quote tokens (0.5e6 raw)
	ucm.createOrder({
		orderId = 'sell-1',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = SELLER_1,
		quantity = '500000000000000000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710967',
		blockheight = '123456790',
		syncState = function() end,
	})

	-- Sell another 0.25 base tokens
	ucm.createOrder({
		orderId = 'sell-2',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = SELLER_1,
		quantity = '250000000000000000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710968',
		blockheight = '123456791',
		syncState = function() end,
	})

	-- Sell final 0.25 base tokens to complete the bid
	ucm.createOrder({
		orderId = 'sell-3',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = SELLER_1,
		quantity = '250000000000000000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710969',
		blockheight = '123456792',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {},
		Bids = {},
		PriceData = {
			MatchLogs = {
				{
					Quantity = '500000',
					Price = '1000000',
					Id = 'bid-1',
				},
				{
					Quantity = '250000',
					Price = '1000000',
					Id = 'bid-1',
				},
				{
					Quantity = '250000',
					Price = '1000000',
					Id = 'bid-1',
				},
			},
			Vwap = '1000000',
			Block = '123456792',
			DominantToken = BASE_TOKEN,
		},
	},
})

utils.test('Sell fully matches bid with denominations in one order', function()
	Orderbook = {
		{
			Pair = { BASE_TOKEN, QUOTE_TOKEN },
			Denominations = { '1000000000000000000', '1000000' },
			Asks = {},
			Bids = {
				{
					Creator = BUYER_1,
					DateCreated = '1722535710966',
					Id = 'bid-2',
					OriginalQuantity = '1000000',
					Price = '1000000',
					Quantity = '1000000',
					Token = QUOTE_TOKEN,
					Side = 'Bid',
				},
			},
		},
	}
	ORDERBOOK_MIGRATED = true

	-- Sell 1 full base token (1e18 raw) for 1 quote token (1e6 raw)
	ucm.createOrder({
		orderId = 'sell-full',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = SELLER_1,
		quantity = '1000000000000000000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710967',
		blockheight = '123456790',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {},
		Bids = {},
		PriceData = {
			MatchLogs = {
				{
					Quantity = '1000000',
					Price = '1000000',
					Id = 'bid-2',
				},
			},
			Vwap = '1000000',
			Block = '123456790',
			DominantToken = BASE_TOKEN,
		},
	},
})

utils.test('Multiple asks at different prices - bid matches best price first', function()
	Orderbook = {
		{
			Pair = { BASE_TOKEN, QUOTE_TOKEN },
			Denominations = { '1000000000000000000', '1000000' },
			Asks = {
				{
					Creator = SELLER_1,
					DateCreated = '1722535710966',
					Id = 'ask-expensive',
					OriginalQuantity = '500000000000000000',
					Price = '2000000',
					Quantity = '500000000000000000',
					Token = BASE_TOKEN,
					Side = 'Ask',
				},
				{
					Creator = SELLER_1,
					DateCreated = '1722535710967',
					Id = 'ask-cheap',
					OriginalQuantity = '500000000000000000',
					Price = '1000000',
					Quantity = '500000000000000000',
					Token = BASE_TOKEN,
					Side = 'Ask',
				},
			},
			Bids = {},
		},
	}
	ORDERBOOK_MIGRATED = true

	-- Buy with quote tokens - should match cheaper ask first
	ucm.createOrder({
		orderId = 'buy-smart',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_1,
		quantity = '500000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710968',
		blockheight = '123456790',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {
			{
				Creator = SELLER_1,
				DateCreated = '1722535710966',
				Id = 'ask-expensive',
				OriginalQuantity = '500000000000000000',
				Price = '2000000',
				Quantity = '500000000000000000',
				Token = BASE_TOKEN,
				Side = 'Ask',
			},
		},
		Bids = {},
		PriceData = {
			MatchLogs = {
				{
					Quantity = '500000000000000000',
					Price = '1000000',
					Id = 'ask-cheap',
				},
			},
			Vwap = '1000000',
			Block = '123456790',
			DominantToken = QUOTE_TOKEN,
		},
	},
})

utils.test('Multiple bids at different prices - ask matches best price first', function()
	Orderbook = {
		{
			Pair = { BASE_TOKEN, QUOTE_TOKEN },
			Denominations = { '1000000000000000000', '1000000' },
			Asks = {},
			Bids = {
				{
					Creator = BUYER_1,
					DateCreated = '1722535710966',
					Id = 'bid-low',
					OriginalQuantity = '500000',
					Price = '1000000',
					Quantity = '500000',
					Token = QUOTE_TOKEN,
					Side = 'Bid',
				},
				{
					Creator = BUYER_1,
					DateCreated = '1722535710967',
					Id = 'bid-high',
					OriginalQuantity = '1000000',
					Price = '2000000',
					Quantity = '1000000',
					Token = QUOTE_TOKEN,
					Side = 'Bid',
				},
			},
		},
	}
	ORDERBOOK_MIGRATED = true

	-- Sell base tokens - should match higher bid first
	ucm.createOrder({
		orderId = 'sell-smart',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = SELLER_1,
		quantity = '500000000000000000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710968',
		blockheight = '123456790',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {},
		Bids = {
			{
				Creator = BUYER_1,
				DateCreated = '1722535710966',
				Id = 'bid-low',
				OriginalQuantity = '500000',
				Price = '1000000',
				Quantity = '500000',
				Token = QUOTE_TOKEN,
				Side = 'Bid',
			},
		},
		PriceData = {
			MatchLogs = {
				{
					Quantity = '1000000',
					Price = '2000000',
					Id = 'bid-high',
				},
			},
			Vwap = '2000000',
			Block = '123456790',
			DominantToken = BASE_TOKEN,
		},
	},
})

utils.test('Market order spans multiple limit orders with VWAP calculation', function()
	Orderbook = {
		{
			Pair = { BASE_TOKEN, QUOTE_TOKEN },
			Denominations = { '1000000000000000000', '1000000' },
			Asks = {
				{
					Creator = SELLER_1,
					DateCreated = '1722535710966',
					Id = 'ask-1',
					OriginalQuantity = '300000000000000000',
					Price = '1000000',
					Quantity = '300000000000000000',
					Token = BASE_TOKEN,
					Side = 'Ask',
				},
				{
					Creator = SELLER_1,
					DateCreated = '1722535710967',
					Id = 'ask-2',
					OriginalQuantity = '300000000000000000',
					Price = '1500000',
					Quantity = '300000000000000000',
					Token = BASE_TOKEN,
					Side = 'Ask',
				},
				{
					Creator = SELLER_1,
					DateCreated = '1722535710968',
					Id = 'ask-3',
					OriginalQuantity = '400000000000000000',
					Price = '2000000',
					Quantity = '400000000000000000',
					Token = BASE_TOKEN,
					Side = 'Ask',
				},
			},
			Bids = {},
		},
	}
	ORDERBOOK_MIGRATED = true

	-- Buy enough to sweep first two asks
	ucm.createOrder({
		orderId = 'buy-sweep',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_1,
		quantity = '750000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710969',
		blockheight = '123456790',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {
			{
				Creator = SELLER_1,
				DateCreated = '1722535710968',
				Id = 'ask-3',
				OriginalQuantity = '400000000000000000',
				Price = '2000000',
				Quantity = '400000000000000000',
				Token = BASE_TOKEN,
				Side = 'Ask',
			},
		},
		Bids = {},
		PriceData = {
			MatchLogs = {
				{
					Quantity = '300000000000000000',
					Price = '1000000',
					Id = 'ask-1',
				},
				{
					Quantity = '300000000000000000',
					Price = '1500000',
					Id = 'ask-2',
				},
			},
			Vwap = '1250000',
			Block = '123456790',
			DominantToken = QUOTE_TOKEN,
		},
	},
})

utils.test('Create limit bid order - should not execute immediately', function()
	Orderbook = {
		{
			Pair = { BASE_TOKEN, QUOTE_TOKEN },
			Denominations = { '1000000000000000000', '1000000' },
			Asks = {
				{
					Creator = SELLER_1,
					DateCreated = '1722535710966',
					Id = 'ask-1',
					OriginalQuantity = '1000000000000000000',
					Price = '2000000',
					Quantity = '1000000000000000000',
					Token = BASE_TOKEN,
					Side = 'Ask',
				},
			},
			Bids = {},
		},
	}
	ORDERBOOK_MIGRATED = true

	-- Place limit bid below market - should be added to orderbook
	ucm.createOrder({
		orderId = 'limit-bid',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_1,
		quantity = '1000000',
		price = '1000000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710967',
		blockheight = '123456790',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {
			{
				Creator = SELLER_1,
				DateCreated = '1722535710966',
				Id = 'ask-1',
				OriginalQuantity = '1000000000000000000',
				Price = '2000000',
				Quantity = '1000000000000000000',
				Token = BASE_TOKEN,
				Side = 'Ask',
			},
		},
		Bids = {
			{
				Creator = BUYER_1,
				DateCreated = '1722535710967',
				Id = 'limit-bid',
				OriginalQuantity = '1000000',
				Price = '1000000',
				Quantity = '1000000',
				Token = QUOTE_TOKEN,
				Side = 'Bid',
			},
		},
	},
})

utils.test('Create limit ask order - should not execute immediately', function()
	Orderbook = {
		{
			Pair = { BASE_TOKEN, QUOTE_TOKEN },
			Denominations = { '1000000000000000000', '1000000' },
			Asks = {},
			Bids = {
				{
					Creator = BUYER_1,
					DateCreated = '1722535710966',
					Id = 'bid-1',
					OriginalQuantity = '500000',
					Price = '1000000',
					Quantity = '500000',
					Token = QUOTE_TOKEN,
					Side = 'Bid',
				},
			},
		},
	}
	ORDERBOOK_MIGRATED = true

	-- Place limit ask above market - should be added to orderbook
	ucm.createOrder({
		orderId = 'limit-ask',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = SELLER_1,
		quantity = '1000000000000000000',
		price = '2000000',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710967',
		blockheight = '123456790',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {
			{
				Creator = SELLER_1,
				DateCreated = '1722535710967',
				Id = 'limit-ask',
				OriginalQuantity = '1000000000000000000',
				Price = '2000000',
				Quantity = '1000000000000000000',
				Token = BASE_TOKEN,
				Side = 'Ask',
			},
		},
		Bids = {
			{
				Creator = BUYER_1,
				DateCreated = '1722535710966',
				Id = 'bid-1',
				OriginalQuantity = '500000',
				Price = '1000000',
				Quantity = '500000',
				Token = QUOTE_TOKEN,
				Side = 'Bid',
			},
		},
	},
})

-- utils.test('Limit order partially fills existing opposite order', function()
-- 	Orderbook = {
-- 		{
-- 			Pair = { BASE_TOKEN, QUOTE_TOKEN },
-- 			Denominations = { '1000000000000000000', '1000000' },
-- 			Asks = {},
-- 			Bids = {
-- 				{
-- 					Creator = BUYER_1,
-- 					DateCreated = '1722535710966',
-- 					Id = 'bid-1',
-- 					OriginalQuantity = '1000000',
-- 					Price = '1500000',
-- 					Quantity = '1000000',
-- 					Token = QUOTE_TOKEN,
-- 					Side = 'Bid',
-- 				},
-- 			},
-- 		},
-- 	}
-- 	ORDERBOOK_MIGRATED = true

-- 	-- Place limit ask that will partially match bid and add remainder to book
-- 	ucm.createOrder({
-- 		orderId = 'limit-ask-partial',
-- 		dominantToken = BASE_TOKEN,
-- 		swapToken = QUOTE_TOKEN,
-- 		sender = SELLER_1,
-- 		quantity = '1500000000000000000',
-- 		price = '1000000',
-- 		baseToken = BASE_TOKEN,
-- 		quoteToken = QUOTE_TOKEN,
-- 		baseTokenDenomination = '1000000000000000000',
-- 		quoteTokenDenomination = '1000000',
-- 		timestamp = '1722535710967',
-- 		blockheight = '123456790',
-- 		syncState = function() end,
-- 	})

-- 	return Orderbook
-- end, {
-- 	{
-- 		Pair = { BASE_TOKEN, QUOTE_TOKEN },
-- 		Denominations = { '1000000000000000000', '1000000' },
-- 		Asks = {
-- 			{
-- 				Creator = SELLER_1,
-- 				DateCreated = '1722535710967',
-- 				Id = 'limit-ask-partial',
-- 				OriginalQuantity = '1500000000000000000',
-- 				Price = '1000000',
-- 				Quantity = '1500000000000000000',
-- 				Token = BASE_TOKEN,
-- 				Side = 'Ask',
-- 			},
-- 		},
-- 		Bids = {},
-- 	},
-- })

utils.test('Reverse pair order still matches correctly', function()
	Orderbook = {
		{
			Pair = { BASE_TOKEN, QUOTE_TOKEN },
			Denominations = { '1000000000000000000', '1000000' },
			Asks = {
				{
					Creator = SELLER_1,
					DateCreated = '1722535710966',
					Id = 'ask-1',
					OriginalQuantity = '1000000000000000000',
					Price = '1000000',
					Quantity = '1000000000000000000',
					Token = BASE_TOKEN,
					Side = 'Ask',
				},
			},
			Bids = {},
		},
	}
	ORDERBOOK_MIGRATED = true

	-- Create order with reversed pair - should still find and match
	ucm.createOrder({
		orderId = 'buy-reversed',
		baseToken = QUOTE_TOKEN,
		quoteToken = BASE_TOKEN,
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_1,
		quantity = '500000',
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710967',
		blockheight = '123456790',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {
			{
				Creator = SELLER_1,
				DateCreated = '1722535710966',
				Id = 'ask-1',
				OriginalQuantity = '1000000000000000000',
				Price = '1000000',
				Quantity = '500000000000000000',
				Token = BASE_TOKEN,
				Side = 'Ask',
			},
		},
		Bids = {},
		PriceData = {
			MatchLogs = {
				{
					Quantity = '500000000000000000',
					Price = '1000000',
					Id = 'ask-1',
				},
			},
			Vwap = '1000000',
			Block = '123456790',
			DominantToken = QUOTE_TOKEN,
		},
	},
})

utils.test('Small denomination token trades correctly', function()
	Orderbook = {}
	ORDERBOOK_MIGRATED = false
	local SMALL_DENOM_TOKEN = 'SMALL_TOKEN_234567890abcdefghijklmnopqrstuv'

	-- Create ask with small denomination (6 decimals like USDC)
	ucm.createOrder({
		orderId = 'small-ask',
		dominantToken = SMALL_DENOM_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = SELLER_1,
		quantity = '1000000',
		price = '2000000',
		timestamp = '1722535710966',
		blockheight = '123456789',
		baseTokenDenomination = '1000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Market buy the small denom token
	ucm.createOrder({
		orderId = 'small-buy',
		dominantToken = QUOTE_TOKEN,
		swapToken = SMALL_DENOM_TOKEN,
		baseToken = SMALL_DENOM_TOKEN,
		quoteToken = QUOTE_TOKEN,
		sender = BUYER_1,
		quantity = '2000000',
		baseTokenDenomination = '1000000',
		quoteTokenDenomination = '1000000',
		timestamp = '1722535710967',
		blockheight = '123456790',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { 'SMALL_TOKEN_234567890abcdefghijklmnopqrstuv', QUOTE_TOKEN },
		Denominations = { '1000000', '1000000' },
		Asks = {},
		Bids = {},
		PriceData = {
			MatchLogs = {
				{
					Quantity = '1000000',
					Price = '2000000',
					Id = 'small-ask',
				},
			},
			Vwap = '2000000',
			Block = '123456790',
			DominantToken = QUOTE_TOKEN,
		},
	},
})

utils.test('AO / PI Swap', function()
	Orderbook = {
		{
			Denominations = { '1000000000000', '1000000000000' },
			Asks = {
				{
					DateCreated = 1765529905661,
					Side = 'Ask',
					Id = 'niVwMC2kELg1qS6kvolNo2nz9GTOAOKd4V_riJx1bPk',
					OriginalQuantity = '500000000000000',
					Price = '25000000000000',
					Token = '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
					Quantity = '498980000000002',
					Creator = 'DhaSTjlyuZOOfskuAiQwzIAEgXyhVMa25bWk_F7voQ8',
				},
				{
					DateCreated = 1765531231351,
					Side = 'Ask',
					Id = 'V7H4anicJrO8XiFPKua49Bk1hHseWuTJVtloE2QIBXs',
					OriginalQuantity = '800000000000000',
					Price = '25000000000000',
					Token = '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
					Quantity = '800000000000000',
					Creator = 'lXA-GI--oey6v1wwh_7-tjL-MCaOhTkSedB0La85tak',
				},
				{
					DateCreated = 1765531294604,
					Side = 'Ask',
					Id = 'zLH8yusPmFDj8h_QWGazdoMNresi3y6eFCsCvO89zI0',
					OriginalQuantity = '1000000000000000',
					Price = '26500000000000',
					Token = '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
					Quantity = '1000000000000000',
					Creator = 'lXA-GI--oey6v1wwh_7-tjL-MCaOhTkSedB0La85tak',
				},
				{
					DateCreated = 1765529882996,
					Side = 'Ask',
					Id = 'js-ov0M4mHV7qjfsSTTDLrF2tm4YkKSIy6fttaohG7g',
					OriginalQuantity = '500000000000000',
					Price = '27000000000000',
					Token = '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
					Quantity = '500000000000000',
					Creator = 'DhaSTjlyuZOOfskuAiQwzIAEgXyhVMa25bWk_F7voQ8',
				},
				{
					DateCreated = 1765531322885,
					Side = 'Ask',
					Id = 'dBb_5O2XI0PLdVCnj6xh95YZ5XECW5hEEC2RTjVV2LI',
					OriginalQuantity = '720000000000000',
					Price = '27500000000000',
					Token = '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
					Quantity = '720000000000000',
					Creator = 'lXA-GI--oey6v1wwh_7-tjL-MCaOhTkSedB0La85tak',
				},
				{
					DateCreated = 1765622490633,
					Side = 'Ask',
					Id = 'xxsgQQRv2gZ63qxnpZS_V-oxInIIGIVYTGtgIph59p8',
					OriginalQuantity = '10000000000',
					Price = '24990000000000',
					Token = '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
					Quantity = '10000000000',
					Creator = 'kRdpOYaT5pUUiNFDaUymqO1VcybZpAfNPnNdls-A134',
				},
			},
			PriceData = {
				Block = '1814304',
				Vwap = '25000000000000',
				MatchLogs = {
					{
						Price = '2000000000000',
						Id = 'RipjPYYDtpS2B1I59noH26e2lz4FT_WfWJX0At-Lth8',
						Quantity = '100000000000',
					},
					{
						Price = '2000000000000',
						Id = 'RipjPYYDtpS2B1I59noH26e2lz4FT_WfWJX0At-Lth8',
						Quantity = '50000000000',
					},
					{
						Price = '28880000000000',
						Id = 'eSV2IXDcrYeG0yQb1uaohBbo_p-W8xvYzewljmCNHlg',
						Quantity = '30000000000',
					},
					{
						Price = '28880000000000',
						Id = 'eSV2IXDcrYeG0yQb1uaohBbo_p-W8xvYzewljmCNHlg',
						Quantity = '100000000',
					},
					{
						Price = '28880000000000',
						Id = 'eSV2IXDcrYeG0yQb1uaohBbo_p-W8xvYzewljmCNHlg',
						Quantity = '100000000',
					},
					{
						Price = '10000000000000',
						Id = 'lgHOQhyJZaJIyaYoASmy_u--KRyxjHASbAH_unwsilA',
						Quantity = '100000000000',
					},
					{
						Price = '28880000000000',
						Id = 'eSV2IXDcrYeG0yQb1uaohBbo_p-W8xvYzewljmCNHlg',
						Quantity = '10000000',
					},
					{
						Price = '25000000000000',
						Id = 'niVwMC2kELg1qS6kvolNo2nz9GTOAOKd4V_riJx1bPk',
						Quantity = '1000000000000',
					},
				},
				DominantToken = '4hXj_E-5fAKmo4E8KjgQvuDJKAFk9P2grhycVmISDLs',
			},
			Pair = { '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc', '4hXj_E-5fAKmo4E8KjgQvuDJKAFk9P2grhycVmISDLs' },
			Bids = {
				{
					DateCreated = 1765533178213,
					Side = 'Bid',
					Id = 'f0YSeFUhX0ykHFzkYyhg3k4BmESq2dV1lo-D_Rqpzd8',
					OriginalQuantity = '90000000000000',
					Price = '18000000000000',
					Token = '4hXj_E-5fAKmo4E8KjgQvuDJKAFk9P2grhycVmISDLs',
					Quantity = '90000000000000',
					Creator = '9zP1F75QN0c2I1Vdjqnby14Pr7NNPgBcnJN6rAMeCks',
				},
				{
					DateCreated = 1765532477773,
					Side = 'Bid',
					Id = 'puriasPfRIFBJXO9_hp0xWI6SvhYEb55jLX3UkXQPYU',
					OriginalQuantity = '75000000000000',
					Price = '15000000000000',
					Token = '4hXj_E-5fAKmo4E8KjgQvuDJKAFk9P2grhycVmISDLs',
					Quantity = '75000000000000',
					Creator = '9zP1F75QN0c2I1Vdjqnby14Pr7NNPgBcnJN6rAMeCks',
				},
			},
		},
	}

	ucm.createOrder({
		orderId = 'DFwheoWn-xchN2ddvO07yA9bmzl1k70thTJd--aPA1w',
		dominantToken = '4hXj_E-5fAKmo4E8KjgQvuDJKAFk9P2grhycVmISDLs',
		swapToken = '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
		sender = 'e1cRutVtigwF1PsPUhTiRF7ndNjWrn1tr223UuQC_FE',
		quantity = '289999999999999',
		timestamp = '1722535710966',
		blockheight = '123456789',
		baseTokenDenomination = '1000000000000',
		quoteTokenDenomination = '1000000000000',
		syncState = function() end,
	})

	return Orderbook
end, {

	{
		Bids = {
			{
				Token = '4hXj_E-5fAKmo4E8KjgQvuDJKAFk9P2grhycVmISDLs',
				Side = 'Bid',
				DateCreated = 1765533178213,
				OriginalQuantity = '90000000000000',
				Creator = '9zP1F75QN0c2I1Vdjqnby14Pr7NNPgBcnJN6rAMeCks',
				Quantity = '90000000000000',
				Price = '18000000000000',
				Id = 'f0YSeFUhX0ykHFzkYyhg3k4BmESq2dV1lo-D_Rqpzd8',
			},
			{
				Token = '4hXj_E-5fAKmo4E8KjgQvuDJKAFk9P2grhycVmISDLs',
				Side = 'Bid',
				DateCreated = 1765532477773,
				OriginalQuantity = '75000000000000',
				Creator = '9zP1F75QN0c2I1Vdjqnby14Pr7NNPgBcnJN6rAMeCks',
				Quantity = '75000000000000',
				Price = '15000000000000',
				Id = 'puriasPfRIFBJXO9_hp0xWI6SvhYEb55jLX3UkXQPYU',
			},
		},

		Asks = {
			{
				Token = '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
				Side = 'Ask',
				DateCreated = 1765531231351,
				OriginalQuantity = '800000000000000',
				Creator = 'lXA-GI--oey6v1wwh_7-tjL-MCaOhTkSedB0La85tak',
				Quantity = '788409996000001',
				Price = '25000000000000',
				Id = 'V7H4anicJrO8XiFPKua49Bk1hHseWuTJVtloE2QIBXs',
			},
			{
				Token = '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
				Side = 'Ask',
				DateCreated = 1765529905661,
				OriginalQuantity = '500000000000000',
				Creator = 'DhaSTjlyuZOOfskuAiQwzIAEgXyhVMa25bWk_F7voQ8',
				Quantity = '498980000000002',
				Price = '25000000000000',
				Id = 'niVwMC2kELg1qS6kvolNo2nz9GTOAOKd4V_riJx1bPk',
			},
			{
				Token = '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
				Side = 'Ask',
				DateCreated = 1765531294604,
				OriginalQuantity = '1000000000000000',
				Creator = 'lXA-GI--oey6v1wwh_7-tjL-MCaOhTkSedB0La85tak',
				Quantity = '1000000000000000',
				Price = '26500000000000',
				Id = 'zLH8yusPmFDj8h_QWGazdoMNresi3y6eFCsCvO89zI0',
			},
			{
				Token = '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
				Side = 'Ask',
				DateCreated = 1765529882996,
				OriginalQuantity = '500000000000000',
				Creator = 'DhaSTjlyuZOOfskuAiQwzIAEgXyhVMa25bWk_F7voQ8',
				Quantity = '500000000000000',
				Price = '27000000000000',
				Id = 'js-ov0M4mHV7qjfsSTTDLrF2tm4YkKSIy6fttaohG7g',
			},
			{
				Token = '0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
				Side = 'Ask',
				DateCreated = 1765531322885,
				OriginalQuantity = '720000000000000',
				Creator = 'lXA-GI--oey6v1wwh_7-tjL-MCaOhTkSedB0La85tak',
				Quantity = '720000000000000',
				Price = '27500000000000',
				Id = 'dBb_5O2XI0PLdVCnj6xh95YZ5XECW5hEEC2RTjVV2LI',
			},
		},

		Denominations = {
			'1000000000000',
			'1000000000000',
		},

		Pair = {
			'0syT13r0s0tgPmIed95bJnuSqaD29HQNN8D3ElLSrsc',
			'4hXj_E-5fAKmo4E8KjgQvuDJKAFk9P2grhycVmISDLs',
		},

		PriceData = {
			DominantToken = '4hXj_E-5fAKmo4E8KjgQvuDJKAFk9P2grhycVmISDLs',
			MatchLogs = {
				{
					Id = 'RipjPYYDtpS2B1I59noH26e2lz4FT_WfWJX0At-Lth8',
					Price = '2000000000000',
					Quantity = '100000000000',
				},
				{
					Id = 'RipjPYYDtpS2B1I59noH26e2lz4FT_WfWJX0At-Lth8',
					Price = '2000000000000',
					Quantity = '50000000000',
				},
				{
					Id = 'eSV2IXDcrYeG0yQb1uaohBbo_p-W8xvYzewljmCNHlg',
					Price = '28880000000000',
					Quantity = '30000000000',
				},
				{
					Id = 'eSV2IXDcrYeG0yQb1uaohBbo_p-W8xvYzewljmCNHlg',
					Price = '28880000000000',
					Quantity = '100000000',
				},
				{
					Id = 'eSV2IXDcrYeG0yQb1uaohBbo_p-W8xvYzewljmCNHlg',
					Price = '28880000000000',
					Quantity = '100000000',
				},
				{
					Id = 'lgHOQhyJZaJIyaYoASmy_u--KRyxjHASbAH_unwsilA',
					Price = '10000000000000',
					Quantity = '100000000000',
				},
				{
					Id = 'eSV2IXDcrYeG0yQb1uaohBbo_p-W8xvYzewljmCNHlg',
					Price = '28880000000000',
					Quantity = '10000000',
				},
				{
					Id = 'niVwMC2kELg1qS6kvolNo2nz9GTOAOKd4V_riJx1bPk',
					Price = '25000000000000',
					Quantity = '1000000000000',
				},
				{
					Id = 'xxsgQQRv2gZ63qxnpZS_V-oxInIIGIVYTGtgIph59p8',
					Price = '24990000000000',
					Quantity = '10000000000',
				},
				{
					Id = 'V7H4anicJrO8XiFPKua49Bk1hHseWuTJVtloE2QIBXs',
					Price = '25000000000000',
					Quantity = '11590003999999',
				},
			},
			Block = '123456789',
			Vwap = '24999991379313',
		},
	},
})

utils.test('Large quantities - stress test with extreme values', function()
	Orderbook = {}
	ORDERBOOK_MIGRATED = true

	local WHALE_SELLER = 'WHALE_SELLER_4567890abcdefghijklmnopqrstuvwx'
	local WHALE_BUYER = 'WHALE_BUYER__4567890abcdefghijklmnopqrstuvwx'

	-- Create an ask with an absurdly large quantity (1 trillion tokens with 18 decimals)
	ucm.createOrder({
		orderId = 'ask-trillion',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = WHALE_SELLER,
		quantity = '1000000000000000000000000000000', -- 1 trillion tokens (1e30)
		price = '5000000000000', -- 5 million quote per base token
		timestamp = '1722535710966',
		blockheight = '123456789',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Create a bid with absurdly large quote amount (100 billion quote tokens)
	ucm.createOrder({
		orderId = 'bid-billion',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = WHALE_BUYER,
		quantity = '100000000000000000', -- 100 billion quote tokens (1e17)
		price = '5000000000000',
		timestamp = '1722535710967',
		blockheight = '123456790',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Execute a market buy to clear the entire ask (needs massive quote amount)
	ucm.createOrder({
		orderId = 'market-buy-trillion',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = WHALE_BUYER,
		quantity = '5000000000000000000000000000000', -- 5 quintillion quote tokens
		timestamp = '1722535710968',
		blockheight = '123456791',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	ucm.createOrder({
		orderId = 'market-sell-huge',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = WHALE_SELLER,
		quantity = '100000000000000000000000', -- 100,000 base tokens (massive excess to clear bid)
		timestamp = '1722535710969',
		blockheight = '123456792',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {},
		Bids = {},
		PriceData = {
			Vwap = '5000000000000',
			Block = '123456792',
			DominantToken = BASE_TOKEN,
			MatchLogs = {
				{
					Id = 'ask-trillion',
					Price = '5000000000000',
					Quantity = '1000000000000000000000000000000',
				},
				{
					Id = 'bid-billion',
					Price = '5000000000000',
					Quantity = '100000000000000000',
				},
			},
		},
	},
})

utils.test('Small quantities - micro quantities test', function()
	Orderbook = {}
	ORDERBOOK_MIGRATED = true

	local MICRO_SELLER = 'MICRO_SELLER_4567890abcdefghijklmnopqrstuvwx'
	local MICRO_BUYER = 'MICRO_BUYER__4567890abcdefghijklmnopqrstuvwx'

	-- Create an ask with extremely small quantity (1 wei = smallest unit)
	ucm.createOrder({
		orderId = 'ask-micro-1',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = MICRO_SELLER,
		quantity = '1',
		price = '1000000',
		timestamp = '1722535710966',
		blockheight = '123456789',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Create another ask with 100 wei
	ucm.createOrder({
		orderId = 'ask-micro-2',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = MICRO_SELLER,
		quantity = '100',
		price = '1000000',
		timestamp = '1722535710967',
		blockheight = '123456790',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Create a bid with very small quote amount (10 wei)
	ucm.createOrder({
		orderId = 'bid-micro-1',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = MICRO_BUYER,
		quantity = '10',
		price = '1000000',
		timestamp = '1722535710968',
		blockheight = '123456791',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Market sell to clear the bid (very small amount)
	ucm.createOrder({
		orderId = 'market-sell-micro',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = MICRO_SELLER,
		quantity = '10000000000000000',
		timestamp = '1722535710969',
		blockheight = '123456792',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Market buy to clear remaining asks (with rounding considerations)
	ucm.createOrder({
		orderId = 'market-buy-micro',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = MICRO_BUYER,
		quantity = '1000000',
		timestamp = '1722535710970',
		blockheight = '123456793',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {},
		Bids = {},
		PriceData = {
			Vwap = '1000000',
			Block = '123456793',
			DominantToken = QUOTE_TOKEN,
			MatchLogs = {
				{
					Id = 'bid-micro-1',
					Price = '1000000',
					Quantity = '10',
				},
				{
					Id = 'ask-micro-1',
					Price = '1000000',
					Quantity = '1',
				},
				{
					Id = 'ask-micro-2',
					Price = '1000000',
					Quantity = '100',
				},
			},
		},
	},
})

utils.test('Full - Multiple random orders with complete matching', function()
	-- Define 5 different addresses for buyers and sellers
	local SELLER_A = 'SELLER__A34567890abcdefghijklmnopqrstuvwxyz'
	local SELLER_B = 'SELLER__B34567890abcdefghijklmnopqrstuvwxyz'
	local SELLER_C = 'SELLER__C34567890abcdefghijklmnopqrstuvwxyz'
	local BUYER_X = 'BUYER___X34567890abcdefghijklmnopqrstuvwxyz'
	local BUYER_Y = 'BUYER___Y34567890abcdefghijklmnopqrstuvwxyz'

	-- Start with empty orderbook
	Orderbook = {}
	ORDERBOOK_MIGRATED = true

	-- Create various sized ask orders (very small to very large quantities)
	-- Small ask at low price
	ucm.createOrder({
		orderId = 'ask-small-1',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = SELLER_A,
		quantity = '100000000000000', -- 0.1 tokens
		price = '1000000',
		timestamp = '1722535710966',
		blockheight = '123456789',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Very large ask at medium price
	ucm.createOrder({
		orderId = 'ask-large-1',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = SELLER_B,
		quantity = '50000000000000000000', -- 50 tokens
		price = '1500000',
		timestamp = '1722535710967',
		blockheight = '123456790',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Medium ask at high price
	ucm.createOrder({
		orderId = 'ask-medium-1',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = SELLER_C,
		quantity = '5000000000000000000', -- 5 tokens
		price = '2000000',
		timestamp = '1722535710968',
		blockheight = '123456791',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Create various sized bid orders
	-- Large bid at high price
	ucm.createOrder({
		orderId = 'bid-large-1',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_X,
		quantity = '75000000', -- 75 quote tokens
		price = '1500000',
		timestamp = '1722535710969',
		blockheight = '123456792',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Small bid at low price
	ucm.createOrder({
		orderId = 'bid-small-1',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_Y,
		quantity = '100000', -- 0.1 quote tokens
		price = '1000000',
		timestamp = '1722535710970',
		blockheight = '123456793',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Very large bid at medium price
	ucm.createOrder({
		orderId = 'bid-huge-1',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_X,
		quantity = '10000000', -- 10 quote tokens
		price = '2000000',
		timestamp = '1722535710971',
		blockheight = '123456794',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Now execute market orders to clear all remaining orders
	-- Market sell to clear all bids
	ucm.createOrder({
		orderId = 'market-sell-clear',
		dominantToken = BASE_TOKEN,
		swapToken = QUOTE_TOKEN,
		sender = SELLER_A,
		quantity = '100000000000000000000', -- 100 tokens (more than enough)
		timestamp = '1722535710972',
		blockheight = '123456795',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	-- Market buy to clear all asks
	ucm.createOrder({
		orderId = 'market-buy-clear',
		dominantToken = QUOTE_TOKEN,
		swapToken = BASE_TOKEN,
		sender = BUYER_Y,
		quantity = '200000000', -- 200 quote tokens (more than enough)
		timestamp = '1722535710973',
		blockheight = '123456796',
		baseToken = BASE_TOKEN,
		quoteToken = QUOTE_TOKEN,
		baseTokenDenomination = '1000000000000000000',
		quoteTokenDenomination = '1000000',
		syncState = function() end,
	})

	return Orderbook
end, {
	{
		Pair = { BASE_TOKEN, QUOTE_TOKEN },
		Denominations = { '1000000000000000000', '1000000' },
		Asks = {},
		Bids = {},
		PriceData = {
			Vwap = '1545453',
			Block = '123456796',
			DominantToken = QUOTE_TOKEN,
			MatchLogs = {
				{
					Id = 'bid-huge-1',
					Price = '2000000',
					Quantity = '10000000',
				},
				{
					Id = 'bid-large-1',
					Price = '1500000',
					Quantity = '75000000',
				},
				{
					Id = 'bid-small-1',
					Price = '1000000',
					Quantity = '100000',
				},
				{
					Id = 'ask-small-1',
					Price = '1000000',
					Quantity = '100000000000000',
				},
				{
					Id = 'ask-large-1',
					Price = '1500000',
					Quantity = '50000000000000000000',
				},
				{
					Id = 'ask-medium-1',
					Price = '2000000',
					Quantity = '5000000000000000000',
				},
			},
		},
	},
})

utils.testSummary()
