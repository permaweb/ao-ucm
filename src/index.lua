local json = require('json')

-- Orderbooks {
-- Id
-- FloorPrice
-- }[]

if not Orderbooks then Orderbooks = {} end

Handlers.add('Info', 'Info',
	function(msg)
		msg.reply({ Data = json.encode({ Orderbooks = Orderbooks }) })
	end)

Handlers.add('Update-Index', 'Update-Index',
	function(msg)
		print(msg.OrderbookId)
		print(msg.FloorPrice)
	end)
