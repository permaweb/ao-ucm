package.path = package.path .. ';../src/?.lua'

-- Mock AO globals
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
		end
	}
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
		if msg.Action == 'Transfer' then
			print(msg.Action .. ' ' .. msg.Tags.Quantity .. ' to ' .. msg.Tags.Recipient)
		elseif msg.Action == 'Order-Error' then
			print(msg.Action .. ': ' .. (msg.Tags.Message or 'unknown error'))
		else
			print(msg.Action)
		end
	 end
}

-- Use valid 43-character addresses (Arweave format)
local BASE_TOKEN = 'BASE_TOKEN_1234567890abcdefghijklmnopqrstuv'
local QUOTE_TOKEN = 'QUOTE_TOKEN_234567890abcdefghijklmnopqrstuv'
local SELLER_1 = 'SELLER_1_34567890abcdefghijklmnopqrstuvwxyz'
local BUYER_1 = 'BUYER_1_234567890abcdefghijklmnopqrstuvwxyz'

utils.test('Create ask with denominations',
	function()
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
			syncState = function() end
		})

		return Orderbook
	end,
	{
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
					Side = 'Ask'
				}
			},
			Bids = {}
		},
	}
)

-- utils.test('Create bid with denominations',
-- 	function()
-- 		Orderbook = {}
-- 		ORDERBOOK_MIGRATED = false

-- 		ucm.createOrder({
-- 			orderId = 'bid-1',
-- 			dominantToken = QUOTE_TOKEN,
-- 			swapToken = BASE_TOKEN,
-- 			sender = BUYER_1,
-- 			quantity = '1000000',
-- 			price = '1000000',
-- 			timestamp = '1722535710966',
-- 			blockheight = '123456789',
-- 			baseTokenDenomination = '1000000000000000000',
-- 			quoteTokenDenomination = '1000000',
-- 			syncState = function() end
-- 		})

-- 		return Orderbook
-- 	end,
-- 	{
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
-- 					Price = '1000000',
-- 					Quantity = '1000000',
-- 					Token = QUOTE_TOKEN,
-- 					Side = 'Bid'
-- 				}
-- 			}
-- 		},
-- 	}
-- )

utils.test('Buy partially matches ask with denominations',
	function()
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
						Side = 'Ask'
					}
				},
				Bids = {}
			}
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
			syncState = function() end
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
			syncState = function() end
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
			syncState = function() end
		})

		return Orderbook
	end,
	{
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
						Id = 'ask-1'
					},
					{
						Quantity = '250000000000000000',
						Price = '1000000',
						Id = 'ask-1'
					},
					{
						Quantity = '250000000000000000',
						Price = '1000000',
						Id = 'ask-1'
					}
				},
				Vwap = '1000000',
				Block = '123456792',
				DominantToken = QUOTE_TOKEN
			}
		}
	}
)

utils.test('Buy fully matches ask with denominations in one order',
	function()
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
						Side = 'Ask'
					}
				},
				Bids = {}
			}
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
			syncState = function() end
		})

		return Orderbook
	end,
	{
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
						Id = 'ask-2'
					}
				},
				Vwap = '1000000',
				Block = '123456790',
				DominantToken = QUOTE_TOKEN
			}
		}
	}
)

-- utils.test('Sell matches bid with denominations',
-- 	function()
-- 		Orderbook = {
-- 			{
-- 				Pair = { BASE_TOKEN, QUOTE_TOKEN },
-- 				Denominations = { '1000000000000000000', '1000000' },
-- 				Asks = {},
-- 				Bids = {
-- 					{
-- 						Creator = BUYER_1,
-- 						DateCreated = '1722535710966',
-- 						Id = 'bid-1',
-- 						OriginalQuantity = '1000000',
-- 						Price = '1000000',
-- 						Quantity = '1000000',
-- 						Token = QUOTE_TOKEN,
-- 						Side = 'Bid'
-- 					}
-- 				}
-- 			}
-- 		}
-- 		ORDERBOOK_MIGRATED = true

-- 		-- Sell 1 base token (1e18 raw) for 1 quote token (1e6 raw)
-- 		ucm.createOrder({
-- 			orderId = 'sell-1',
-- 			dominantToken = BASE_TOKEN,
-- 			swapToken = QUOTE_TOKEN,
-- 			sender = SELLER_1,
-- 			quantity = '1000000000000000000',
-- 			timestamp = '1722535710967',
-- 			blockheight = '123456790',
-- 			syncState = function() end
-- 		})

-- 		return Orderbook
-- 	end,
-- 	{
-- 		{
-- 			Pair = { BASE_TOKEN, QUOTE_TOKEN },
-- 			Denominations = { '1000000000000000000', '1000000' },
-- 			Asks = {},
-- 			Bids = {},
-- 			PriceData = {
-- 				MatchLogs = {
-- 					{
-- 						Quantity = '1000000',
-- 						Price = '1000000',
-- 						Id = 'bid-1'
-- 					}
-- 				},
-- 				Vwap = '1000000',
-- 				Block = '123456790',
-- 				DominantToken = BASE_TOKEN
-- 			}
-- 		}
-- 	}
-- )

utils.testSummary()
