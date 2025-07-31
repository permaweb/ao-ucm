local bint = require('.bint')(256)
local json = require('json')

local utils = require('utils')

local english_auction = {}

-- Helper function to handle ARIO token orders: we are selling ANT token, so we need to add to orderbook
function english_auction.handleArioOrder(args, validPair, pairIndex)
	-- Add the new order to the orderbook (buy now functionality)
	table.insert(Orderbook[pairIndex].Orders, {
		Id = args.orderId,
		Quantity = tostring(args.quantity),
		OriginalQuantity = tostring(args.quantity),
		Creator = args.sender,
		Token = validPair[1],
		DateCreated = args.timestamp,
		Price = args.price and tostring(args.price),
		ExpirationTime = args.expirationTime and tostring(args.expirationTime) or nil,
		Type = 'english'
	})

	-- Send order data to activity tracking process
	local limitDataSuccess, limitData = pcall(function()
		return json.encode({
			Order = {
				Id = args.orderId,
				DominantToken = validPair[1],
				SwapToken = validPair[2],
				Sender = args.sender,
				Receiver = nil,
				Quantity = tostring(args.quantity),
				Price = args.price and tostring(args.price),
				Timestamp = args.timestamp,
				OrderType = 'english'
			}
		})
	end)

	ao.send({
		Target = ACTIVITY_PROCESS,
		Action = 'Update-Listed-Orders',
		Data = limitDataSuccess and limitData or ''
	})

	-- Notify sender of successful order creation
	ao.send({
		Target = args.sender,
		Action = 'Order-Success',
		Tags = {
			Status = 'Success',
			OrderId = args.orderId,
			Handler = 'Create-Order',
			DominantToken = validPair[1],
			SwapToken = args.swapToken,
			Quantity = tostring(args.quantity),
			Price = args.price and tostring(args.price),
			Message = 'ARIO order added to orderbook for English auction!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = 'english'
		}
	})
end

return english_auction
