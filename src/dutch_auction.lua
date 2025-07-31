local utils = require('utils')
local bint = require('.bint')(256)
local json = require('json')

local dutch_auction = {}

function dutch_auction.handleArioOrder(args, validPair, pairIndex)
    local intervals = (bint(args.expirationTime) - bint(args.timestamp)) / bint(args.decreaseInterval)
    local priceDecreaseMax = bint(args.price) - bint(args.minimumPrice)
    local decreaseStep = math.floor(priceDecreaseMax / intervals)

    table.insert(Orderbook[pairIndex].Orders, {
		Id = args.orderId,
		Quantity = tostring(args.quantity),
		OriginalQuantity = tostring(args.quantity),
		Creator = args.sender,
		Token = validPair[1],
		DateCreated = args.timestamp,
		Price = args.price and tostring(args.price),
		ExpirationTime = args.expirationTime and tostring(args.expirationTime) or nil,
        Type = 'dutch',
        MinimumPrice = args.minimumPrice and tostring(args.minimumPrice),
        DecreaseInterval = args.decreaseInterval and tostring(args.decreaseInterval),
        DecreaseStep = tostring(decreaseStep)
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
				OrderType = 'dutch',
				MinimumPrice = args.minimumPrice and tostring(args.minimumPrice),
				DecreaseInterval = args.decreaseInterval and tostring(args.decreaseInterval),
				DecreaseStep = tostring(decreaseStep)
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
			Message = 'ARIO order added to orderbook for buy now!',
			['X-Group-ID'] = args.orderGroupId,
			OrderType = 'dutch'
		}
	})
end

function dutch_auction.validateDutchParams(args)
    if not args.minimumPrice then
		return false, 'Minimum price must be provided'
	end

	local isValidMinimumPrice, minimumPriceError = utils.checkValidAmount(args.minimumPrice)
	if not isValidMinimumPrice then
		return false, minimumPriceError
	end

    if not args.decreaseInterval then
        return false, 'Decrease interval must be provided'
    end

	local isValidDecreaseInterval, decreaseIntervalError = utils.checkValidAmount(args.decreaseInterval)
	if not isValidDecreaseInterval then
		return false, decreaseIntervalError
	end

    if bint(args.decreaseInterval) >= bint(args.expirationTime) then
        return false, 'Decrease interval must be less than expiration time'
    end

    return true
end

return dutch_auction