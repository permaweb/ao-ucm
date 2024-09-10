package.path = package.path .. ';../src/?.lua'

local ucm = require('ucm')
local utils = require('utils')

Orderbook = {
	{
		Pair = { 'pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
		Orders = {
			{
				Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
				DateCreated = '1722535710966',
				Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
				OriginalQuantity = '400000000000000',
				Price = '500000000',
				Quantity = '400000000000000',
				Token = 'pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY'
			},
			{
				Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
				DateCreated = '1722535710966',
				Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
				OriginalQuantity = '400000000000000',
				Price = '500000000',
				Quantity = '400000000000000',
				Token = 'pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY'
			}
		},
	},
	-- {
	-- 	Pair = { 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
	-- 	Orders = {
	-- 		{
	-- 			Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
	-- 			DateCreated = '1722535710966',
	-- 			Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
	-- 			OriginalQuantity = '10',
	-- 			Price = '100',
	-- 			Quantity = '10',
	-- 			Token = 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE'
	-- 		},
	-- 		{
	-- 			Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
	-- 			DateCreated = '1722535710966',
	-- 			Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
	-- 			OriginalQuantity = '10',
	-- 			Price = '100',
	-- 			Quantity = '10',
	-- 			Token = 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE'
	-- 		},
	-- 	},
	-- },
}

local order

order = {
	orderId = tostring(1),
	dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
	swapToken = 'pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY',
	sender = 'User' .. tostring(1),
	quantity = tostring(200000000000),
	timestamp = os.time() + 1,
	blockheight = '123456789',
	transferDenomination = '1000000000000'
}

-- order = {
-- 	orderId = tostring(1),
-- 	dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
-- 	swapToken = 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE',
-- 	sender = 'User' .. tostring(1),
-- 	quantity = '1500',
-- 	timestamp = os.time() + 1,
-- 	blockheight = '123456789',
-- }

ucm.createOrder(order)

utils.printTable(Orderbook)