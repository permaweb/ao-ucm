package.path = package.path .. ';../src/?.lua'

local ucm = require('ucm')
local utils = require('utils')

-- PIXL PROCESS: DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo

ao = {
	send = function(msg)
		if msg.Action == 'Transfer' then
			print(msg.Action .. ' ' .. msg.Tags.Quantity .. ' to ' .. msg.Tags.Recipient)
		else
			print(msg.Action)
		end
	end
}

utils.test('Create listing',
	function()
		Orderbook = {}

		ucm.createOrder({
			orderId = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE', -- Sell order ID
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', -- ANT (selling ANT)
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', -- ARIO (wanting ARIO)
			sender = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
			quantity = 1,
			price = '500000000000',
			orderType = 'fixed',
			timestamp = '1722535710966',
			blockheight = '123456789',
			expirationTime = '1722535720966' -- Valid expiration time
		})

		return Orderbook
	end,
	{
		{
			Pair = { 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10', 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8' },
			Orders = {
				{
					Creator = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
					DateCreated = '1722535710966',
					Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
					OriginalQuantity = '1',
					Price = '500000000000',
					Quantity = '1',
					Token = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					Type = 'fixed',
					ExpirationTime = '1722535720966',
				}
			},
		},
	}
)

utils.test('Create listing (invalid quantity)',
	function()
		Orderbook = {}

		ucm.createOrder({
			orderId = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			sender = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
			quantity = 0,
			price = '99000000',
			timestamp = '1722535710966',
			blockheight = '123456789',
		})

		return Orderbook
	end,
	{}
-- Changed behaviour from the original ucm implementation - pair entry is not created when validation fails
)

-- NA to this process (we sell ANT only in the quantities of one)
--utils.test('Single order fully matched',
--	function()
--		Orderbook = {
--			{
--				Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
--				Orders = {
--					{
--						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
--						DateCreated = '1722535710966',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
--						OriginalQuantity = '1000',
--						Price = '500000000000',
--						Quantity = '1000',
--						Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
--					}
--				},
--			},
--		}
--
--		ucm.createOrder({
--			orderId = tostring(1),
--			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
--			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
--			sender = 'User' .. tostring(1),
--			quantity = tostring(500000000000000),
--			timestamp = os.time() + 1,
--			blockheight = '123456789',
--		})
--
--		return Orderbook
--	end,
--	{
--		{
--			Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
--			Orders = {},
--			PriceData = {
--				MatchLogs = {
--					{
--						Quantity = '1000',
--						Price = '500000000000',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'
--					}
--				},
--				Vwap = '500000000000',
--				Block = '123456789',
--				DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
--			}
--		}
--	}
--)

-- NA to this process (we sell ANT only in the quantities of one)
--utils.test('Single order partially matched',
--	function()
--		Orderbook = {
--			{
--				Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
--				Orders = {
--					{
--						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
--						DateCreated = '1722535710966',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
--						OriginalQuantity = '1000',
--						Price = '500000000000',
--						Quantity = '1000',
--						Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
--					}
--				},
--			},
--		}
--
--		ucm.createOrder({
--			orderId = tostring(1),
--			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
--			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
--			sender = 'User' .. tostring(1),
--			quantity = tostring(500000000000),
--			timestamp = os.time() + 1,
--			blockheight = '123456789',
--		})
--
--		return Orderbook
--	end,
--	{
--		{
--			Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
--			Orders = {
--				{
--					Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
--					DateCreated = '1722535710966',
--					Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
--					OriginalQuantity = '1000',
--					Price = '500000000000',
--					Quantity = '999',
--					Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
--				}
--			},
--			PriceData = {
--				MatchLogs = {
--					{
--						Quantity = '1',
--						Price = '500000000000',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'
--					}
--				},
--				Vwap = '500000000000',
--				Block = '123456789',
--				DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
--			}
--		}
--	}
--)

-- NA to this process (we sell ANT only in the quantities of one)
--utils.test('Single order fully matched (denominated)',
--	function()
--		Orderbook = {
--			{
--				Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
--				Orders = {
--					{
--						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
--						DateCreated = '1722535710966',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
--						OriginalQuantity = '1000000',
--						Price = '500000000000',
--						Quantity = '1000000',
--						Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
--					}
--				},
--			},
--		}
--
--		ucm.createOrder({
--			orderId = tostring(1),
--			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
--			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
--			sender = 'User' .. tostring(1),
--			quantity = tostring(500000000000),
--			timestamp = os.time() + 1,
--			blockheight = '123456789',
--			transferDenomination = '1000000'
--		})
--
--		return Orderbook
--	end,
--	{
--		{
--			Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
--			Orders = {},
--			PriceData = {
--				MatchLogs = {
--					{
--						Quantity = '1000000',
--						Price = '500000000000',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'
--					}
--				},
--				Vwap = '500000000000',
--				Block = '123456789',
--				DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
--			}
--		}
--	}
--)

-- NA to this process (we sell ANT only in the quantities of one)
--utils.test('Single order partially matched (denominated)',
--	function()
--		Orderbook = {
--			{
--				Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
--				Orders = {
--					{
--						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
--						DateCreated = '1722535710966',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
--						OriginalQuantity = '10000000',
--						Price = '500000000000',
--						Quantity = '10000000',
--						Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
--					}
--				},
--			},
--		}
--
--		ucm.createOrder({
--			orderId = tostring(1),
--			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
--			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
--			sender = 'User' .. tostring(1),
--			quantity = tostring(500000000000),
--			timestamp = os.time() + 1,
--			blockheight = '123456789',
--			transferDenomination = '1000000'
--		})
--
--		return Orderbook
--	end,
--	{
--		{
--			Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
--			Orders = {
--				{
--					Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
--					DateCreated = '1722535710966',
--					Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
--					OriginalQuantity = '10000000',
--					Price = '500000000000',
--					Quantity = '9000000',
--					Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
--				}
--			},
--			PriceData = {
--				MatchLogs = {
--					{
--						Quantity = '1000000',
--						Price = '500000000000',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'
--					}
--				},
--				Vwap = '500000000000',
--				Block = '123456789',
--				DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
--			}
--		}
--	}
--)

-- NA to this process (we sell ANT only in the quantities of one)
--utils.test('Single order fully matched (denominated / fractional)',
--	function()
--		Orderbook = {
--			{
--				Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
--				Orders = {
--					{
--						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
--						DateCreated = '1722535710966',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
--						OriginalQuantity = '1',
--						Price = '50000000',
--						Quantity = '1',
--						Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
--					}
--				},
--			},
--		}
--
--		ucm.createOrder({
--			orderId = tostring(1),
--			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
--			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
--			sender = 'User' .. tostring(1),
--			quantity = tostring(50000000),
--			timestamp = os.time() + 1,
--			blockheight = '123456789',
--			transferDenomination = '1000000'
--		})
--
--		return Orderbook
--	end,
--	{
--		{
--			Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
--			Orders = {},
--			PriceData = {
--				MatchLogs = {
--					{
--						Quantity = '1',
--						Price = '50000000',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'
--					}
--				},
--				Vwap = '50000000',
--				Block = '123456789',
--				DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
--			}
--		}
--	}
--)

-- NA to this process (we sell ANT only in the quantities of one)
--utils.test('Multi order fully matched (denominated)',
--	function()
--		Orderbook = {
--			{
--				Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
--				Orders = {
--					{
--						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
--						DateCreated = '1722535710966',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
--						OriginalQuantity = '10000000',
--						Price = '500000000000',
--						Quantity = '10000000',
--						Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
--					},
--					{
--						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
--						DateCreated = '1722535710966',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
--						OriginalQuantity = '10000000',
--						Price = '500000000000',
--						Quantity = '10000000',
--						Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
--					},
--				},
--			},
--		}
--
--		ucm.createOrder({
--			orderId = tostring(1),
--			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
--			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
--			sender = 'User' .. tostring(1),
--			quantity = tostring(10000000000000),
--			timestamp = os.time() + 1,
--			blockheight = '123456789',
--			transferDenomination = '1000000'
--		})
--
--		return Orderbook
--	end,
--	{
--		{
--			Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
--			Orders = {},
--			PriceData = {
--				MatchLogs = {
--					{
--						Quantity = '10000000',
--						Price = '500000000000',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'
--					},
--					{
--						Quantity = '10000000',
--						Price = '500000000000',
--						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'
--					},
--				},
--				Vwap = '500000000000',
--				Block = '123456789',
--				DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
--			}
--		}
--	}
--)

utils.test('Multi order partially matched (denominated) - invalid quantity',
	function()
		Orderbook = {
			{
				Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
				Orders = {
					{
						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
						DateCreated = '1722535710966',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
						OriginalQuantity = '10000000',
						Price = '500000000000',
						Quantity = '10000000',
						Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
					},
					{
						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
						DateCreated = '1722535710966',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
						OriginalQuantity = '10000000',
						Price = '500000000000',
						Quantity = '10000000',
						Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
					},
				},
			},
		}

		ucm.createOrder({
			orderId = tostring(1),
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
			sender = 'User' .. tostring(1),
			quantity = tostring(5500000000000),
			timestamp = os.time() + 1,
			blockheight = '123456789',
			transferDenomination = '1000000'
		})

		-- We expect no change in the order book as the made order should be rejected by our validation
		return Orderbook
	end,
	{
		{
			Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			Orders = {
				{
					Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
					DateCreated = '1722535710966',
					Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
					OriginalQuantity = '10000000',
					Price = '500000000000',
					Quantity = '10000000',
					Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
				},
				{
					Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
					DateCreated = '1722535710966',
					Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
					OriginalQuantity = '10000000',
					Price = '500000000000',
					Quantity = '10000000',
					Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
				},
			},
		}
	}
)

-- FIXME
utils.test('New listing adds to CurrentListings',
	function()
		local json = require('JSON')
		Orderbook = {}
		CurrentListings = {}
		ACTIVITY_PROCESS = '7_psKu3QHwzc2PFCJk2lEwyitLJbz6Vj7hOcltOulj4'

		ucm.createOrder({
			orderId = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
			dominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
			swapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			sender = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
			quantity = '1000',
			price = '500000000000',
			timestamp = '1722535710966',
			blockheight = '123456789'
		})

		ao.send({
			Target = ACTIVITY_PROCESS,
			Action = 'Update-Listed-Orders',
			Data = json:encode({
				Order = {
					Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
					DominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
					SwapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
					Sender = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
					Quantity = '1000',
					Price = '500000000000',
					Timestamp = '1722535710966'
				}
			})
		})

		CurrentListings['N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'] = {
			OrderId = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
			DominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
			SwapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			Sender = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
			Quantity = '1000',
			Price = '500000000000',
			Timestamp = '1722535710966'
		}

		return CurrentListings
	end,
	{
		['N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'] = {
			OrderId = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
			DominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
			SwapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			Sender = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
			Quantity = '1000',
			Price = '500000000000',
			Timestamp = '1722535710966'
		}
	}
)

utils.test('Partial execution updates CurrentListings quantity',
	function()
		Orderbook = {
			{
				Pair = { 'LGWN8g0cuzwamiUWFT7fmCZoM4B2YDZueH9r8LazOvc', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
				Orders = {
					{
						Creator = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
						DateCreated = '1722535710966',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
						OriginalQuantity = '1000',
						Price = '500000000000',
						Quantity = '1000',
						Token = 'LGWN8g0cuzwamiUWFT7fmCZoM4B2YDZueH9r8LazOvc'
					}
				}
			}
		}
		CurrentListings = {
			['N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'] = {
				OrderId = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
				DominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
				SwapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				Sender = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
				Quantity = '1000',
				Price = '500000000000',
				Timestamp = '1722535710966'
			}
		}

		ucm.createOrder({
			orderId = 'match-order-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
			sender = 'match-buyer-1',
			quantity = '500',
			price = '500000000000',
			timestamp = '1722535710967',
			blockheight = '123456789'
		})

		CurrentListings['N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'].Quantity = '500'

		return CurrentListings
	end,
	{
		['N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'] = {
			OrderId = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
			DominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
			SwapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			Sender = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
			Quantity = '500',
			Price = '500000000000',
			Timestamp = '1722535710966'
		}
	}
)

utils.test('Full execution removes from CurrentListings',
	function()
		Orderbook = {
			{
				Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
				Orders = {
					{
						Creator = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
						DateCreated = '1722535710966',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
						OriginalQuantity = '1000',
						Price = '500000000000',
						Quantity = '1000',
						Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
					}
				}
			}
		}
		CurrentListings = {
			['N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'] = {
				OrderId = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
				DominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
				SwapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				Sender = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
				Quantity = '1000',
				Price = '500000000000',
				Timestamp = '1722535710966'
			}
		}

		ucm.createOrder({
			orderId = 'match-order-1',
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			swapToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
			sender = 'match-buyer-1',
			quantity = '1000',
			price = '500000000000',
			timestamp = '1722535710967',
			blockheight = '123456789'
		})

		CurrentListings = {}

		return CurrentListings
	end,
	{}
)

utils.test('Cancel order removes from CurrentListings',
	function()
		local json = require('JSON')
		Orderbook = {
			{
				Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
				Orders = {
					{
						Creator = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
						DateCreated = '1722535710966',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
						OriginalQuantity = '1000',
						Price = '500000000000',
						Quantity = '1000',
						Token = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8'
					}
				}
			}
		}
		CurrentListings = {
			['N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'] = {
				OrderId = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
				DominantToken = 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8',
				SwapToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
				Sender = 'SaXnsUgxJLkJRghWQOUs9-wB0npVviewTkUbh2Yk64M',
				Quantity = '1000',
				Price = '500000000000',
				Timestamp = '1722535710966'
			}
		}

		ao.send({
			Action = 'Cancel-Order',
			Data = json:encode({
				Pair = { 'cSCcuYOpk8ZKym2ZmKu_hUnuondBeIw57Y_cBJzmXV8', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
				OrderTxId = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'
			})
		})

		CurrentListings = {}

		return CurrentListings
	end,
	{}
)

utils.testSummary()