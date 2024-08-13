package.path = package.path .. ';../src/?.lua'

local ucm = require('ucm')
local utils = require('utils')

Orderbook = {
	-- {
	-- 	Pair = { 'e0T2NT6ka_VIp3hBWbjh6mOIcrUx9Dnj_moGC17hlx0', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
	-- 	Orders = {
	-- 		{
	-- 			Creator = 'VM-MdiAiJBatLtT09hBqoEVzsaKRN5G6un3WQ92fAy4',
	-- 			DateCreated = '1722429830403',
	-- 			Id = 'hwEH2k7ToU7O7EL831obmTVM_MFjjzXPBuTRX3c96Qc',
	-- 			OriginalQuantity = '58',
	-- 			Price = '10444000000000',
	-- 			Quantity = '56',
	-- 			Token = 'e0T2NT6ka_VIp3hBWbjh6mOIcrUx9Dnj_moGC17hlx0'
	-- 		},
	-- 	},
	-- },
	-- {
	-- 	Pair = { 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
	-- 	Orders = {
	-- 		{
	-- 			Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
	-- 			DateCreated = '1722535710966',
	-- 			Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
	-- 			OriginalQuantity = '1',
	-- 			Price = '5000000000000',
	-- 			Quantity = '1',
	-- 			Token = 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE'
	-- 		}
	-- 	},
	-- },
	{
		Pair = { '4LV93HuiNV2szr9PiibI0kUHc073Lvmo5XgvAGh_jN0', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
		Orders = {
			{
				Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
				DateCreated = '1722535710966',
				Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
				OriginalQuantity = '111',
				Price = '88800000000',
				Quantity = '111',
				Token = '4LV93HuiNV2szr9PiibI0kUHc073Lvmo5XgvAGh_jN0'
			}
		},
	},
}

local order

-- order = {
-- 	orderId = tostring(1),
-- 	dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
-- 	swapToken = 'e0T2NT6ka_VIp3hBWbjh6mOIcrUx9Dnj_moGC17hlx0',
-- 	sender = 'User' .. tostring(1),
-- 	quantity = tostring(10444000000000 - 10),
-- 	timestamp = os.time() + 1,
-- 	blockheight = '123456789',
-- 	transferDenomination = '1'
-- }

order = {
	orderId = tostring(1),
	dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
	swapToken = '4LV93HuiNV2szr9PiibI0kUHc073Lvmo5XgvAGh_jN0',
	sender = 'User' .. tostring(1),
	-- quantity = tostring(88800000000 - 1),
	quantity = '1',
	price = tostring(88800000000),
	timestamp = os.time() + 1,
	blockheight = '123456789',
	transferDenomination = '1'
}

ucm.createOrder(order)

utils.printTable(Orderbook)