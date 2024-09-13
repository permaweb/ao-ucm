package.path = package.path .. ';../src/?.lua'

local ucm = require('ucm')
local utils = require('utils')

utils.test('Single order fully matched',
	function()
		Orderbook = {
			{
				Pair = { 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
				Orders = {
					{
						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
						DateCreated = '1722535710966',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
						OriginalQuantity = '1000',
						Price = '500000000000',
						Quantity = '1000',
						Token = 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE'
					}
				},
			},
		}

		ucm.createOrder({
			orderId = tostring(1),
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			swapToken = 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE',
			sender = 'User' .. tostring(1),
			quantity = tostring(500000000000000),
			timestamp = os.time() + 1,
			blockheight = '123456789',
		})

		return Orderbook
	end,
	{
		{
			Pair = { 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			Orders = {},
			PriceData = {
				MatchLogs = {
					{
						Quantity = '1000',
						Price = '500000000000',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'
					}
				},
				Vwap = '500000000000',
				Block = '123456789',
				DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
			}
		}
	}
)

utils.test('Single order partially matched',
	function()
		Orderbook = {
			{
				Pair = { 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
				Orders = {
					{
						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
						DateCreated = '1722535710966',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
						OriginalQuantity = '1000',
						Price = '500000000000',
						Quantity = '1000',
						Token = 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE'
					}
				},
			},
		}

		ucm.createOrder({
			orderId = tostring(1),
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			swapToken = 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE',
			sender = 'User' .. tostring(1),
			quantity = tostring(500000000000),
			timestamp = os.time() + 1,
			blockheight = '123456789',
		})

		return Orderbook
	end,
	{
		{
			Pair = { 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			Orders = {
				{
					Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
					DateCreated = '1722535710966',
					Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
					OriginalQuantity = '1000',
					Price = '500000000000',
					Quantity = '999',
					Token = 'j6pqhdn5wtfFwgt0aG6dHijX398OpINT9BIcVbSrMKE'
				}
			},
			PriceData = {
				MatchLogs = {
					{
						Quantity = '1',
						Price = '500000000000',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'
					}
				},
				Vwap = '500000000000',
				Block = '123456789',
				DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
			}
		}
	}
)

utils.test('Single order fully matched (denominated)',
	function()
		Orderbook = {
			{
				Pair = { 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
				Orders = {
					{
						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
						DateCreated = '1722535710966',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
						OriginalQuantity = '1000000',
						Price = '500000000000',
						Quantity = '1000000',
						Token = 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo'
					}
				},
			},
		}

		ucm.createOrder({
			orderId = tostring(1),
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			swapToken = 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo',
			sender = 'User' .. tostring(1),
			quantity = tostring(500000000000),
			timestamp = os.time() + 1,
			blockheight = '123456789',
			transferDenomination = '1000000'
		})

		return Orderbook
	end,
	{
		{
			Pair = { 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			Orders = {},
			PriceData = {
				MatchLogs = {
					{
						Quantity = '1000000',
						Price = '500000000000',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'
					}
				},
				Vwap = '500000000000',
				Block = '123456789',
				DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
			}
		}
	}
)

utils.test('Single order partially matched (denominated)',
	function()
		Orderbook = {
			{
				Pair = { 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
				Orders = {
					{
						Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
						DateCreated = '1722535710966',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
						OriginalQuantity = '10000000',
						Price = '500000000000',
						Quantity = '10000000',
						Token = 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo'
					}
				},
			},
		}

		ucm.createOrder({
			orderId = tostring(1),
			dominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
			swapToken = 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo',
			sender = 'User' .. tostring(1),
			quantity = tostring(500000000000),
			timestamp = os.time() + 1,
			blockheight = '123456789',
			transferDenomination = '1000000'
		})

		return Orderbook
	end,
	{
		{
			Pair = { 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			Orders = {
				{
					Creator = 'LNtQf8SGZbHPeoksAqnVKfZvuGNgX4eH-xQYsFt_w-k',
					DateCreated = '1722535710966',
					Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE',
					OriginalQuantity = '10000000',
					Price = '500000000000',
					Quantity = '9000000',
					Token = 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo'
				}
			},
			PriceData = {
				MatchLogs = {
					{
						Quantity = '1000000',
						Price = '500000000000',
						Id = 'N5vr71SXaEYsdVoVCEB5qOTjHNwyQVwGvJxBh_kgTbE'
					}
				},
				Vwap = '500000000000',
				Block = '123456789',
				DominantToken = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'
			}
		}
	}
)

utils.testSummary()