local bint = require('.bint')(256)
local json = require('json')

local ao
local success, aoModule = pcall(require, 'ao')
if success then
	ao = aoModule
else
	ao = {
		send = function(msg) print(msg.Action) end
	}
end

local utils = require('utils')

ACTIVITY_PROCESS = 'SNDvAf2RF-jhPmRrGUcs_b1nKlzU6vamN9zl0e9Zi4c'
PIXL_PROCESS = 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo'

if Name ~= 'Universal Content Marketplace' then Name = 'Universal Content Marketplace' end

-- Orderbook {
-- 	Pair [TokenId, TokenId],
-- 	Orders {
-- 		Id,
-- 		Creator,
-- 		Quantity,
-- 		OriginalQuantity,
-- 		Token,
-- 		DateCreated,
-- 		Price?
-- 	} []
-- } []

if not Orderbook then Orderbook = {} end

local ucm = {}

local function handleError(args) -- Target, TransferToken, Quantity
	-- If there is a valid quantity then return the funds
	if args.TransferToken and args.Quantity and utils.checkValidAmount(args.Quantity) then
		ao.send({
			Target = args.TransferToken,
			Action = 'Transfer',
			Tags = {
				Recipient = args.Target,
				Quantity = tostring(args.Quantity)
			}
		})
	end
	ao.send({ Target = args.Target, Action = args.Action, Tags = { Status = 'Error', Message = args.Message } })
end

function ucm.getPairIndex(pair)
	local pairIndex = -1

	for i, existingOrders in ipairs(Orderbook) do
		if (existingOrders.Pair[1] == pair[1] and existingOrders.Pair[2] == pair[2]) or
			(existingOrders.Pair[1] == pair[2] and existingOrders.Pair[2] == pair[1]) then
			pairIndex = i
		end
	end

	return pairIndex
end

function ucm.createOrder(args)
	local validPair, pairError = utils.validatePairData({ args.dominantToken, args.swapToken })

	if not validPair then
		handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = pairError or 'Error validating pair',
			Quantity = args.quantity,
			TransferToken = nil,
		})
		return
	end

	local currentToken = validPair[1]
	local pairIndex = ucm.getPairIndex(validPair)

	if pairIndex == -1 then
		table.insert(Orderbook, { Pair = validPair, Orders = {} })
		pairIndex = ucm.getPairIndex(validPair)
	end

	if not utils.checkValidAmount(args.quantity) then
		handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Quantity must be an integer greater than zero',
			Quantity = args.quantity,
			TransferToken = currentToken,
		})
		return
	end

	if args.price and not utils.checkValidAmount(args.price) then
		handleError({
			Target = args.sender,
			Action = 'Validation-Error',
			Message = 'Price must be an integer greater than zero',
			Quantity = args.quantity,
			TransferToken = currentToken,
		})
		return
	end

	if pairIndex > -1 then
		local orderType = args.price and 'Limit' or 'Market'
		local remainingQuantity = bint(args.quantity)
		local currentOrders = Orderbook[pairIndex].Orders
		local updatedOrderbook = {}
		local matches = {}

		-- Sort order entries based on price
		table.sort(currentOrders, function(a, b)
			return bint(a.Price) < bint(b.Price)
		end)

		-- Log
		print('Order type: ' .. orderType)
		print('Input quantity: ' .. tostring(remainingQuantity))

		for _, currentOrderEntry in ipairs(currentOrders) do
			if currentToken ~= currentOrderEntry.Token then
				local fillAmount, receiveFromCurrent

				-- Calculate the minimum required amount to buy at least one share
				local minRequiredAmount = bint(currentOrderEntry.Price)

				-- If the buyer's remaining quantity is less than the minimum required amount, skip this order
				if remainingQuantity < minRequiredAmount then
					table.insert(updatedOrderbook, currentOrderEntry)
				else
					-- Calculate how many shares can be bought with the remaining quantity
					fillAmount = remainingQuantity // bint(currentOrderEntry.Price)

					-- Ensure the fill amount does not exceed the available quantity in the order
					if fillAmount > bint(currentOrderEntry.Quantity) then
						fillAmount = bint(currentOrderEntry.Quantity)
					end

					-- Calculate the total cost for the fill amount
					receiveFromCurrent = fillAmount * bint(currentOrderEntry.Price)

					-- Subtract the used quantity from the buyer's remaining quantity
					remainingQuantity = remainingQuantity - receiveFromCurrent
					currentOrderEntry.Quantity = tostring(bint(currentOrderEntry.Quantity) - fillAmount)

					-- Log
					print('Fill amount: ' .. tostring(fillAmount))
					print('Total cost: ' .. tostring(receiveFromCurrent))
					print('Remaining order quantity: ' .. tostring(currentOrderEntry.Quantity))

					local calculatedSendAmount = utils.calculateSendAmount(receiveFromCurrent)

					-- Send tokens to the current order creator
					ao.send({
						Target = currentToken,
						Action = 'Transfer',
						Tags = {
							Recipient = currentOrderEntry.Creator,
							Quantity = calculatedSendAmount
						}
					})

					-- Send swap tokens to the input order creator
					ao.send({
						Target = args.swapToken,
						Action = 'Transfer',
						Tags = {
							Recipient = args.sender,
							Quantity = tostring(fillAmount)
						}
					})

					-- Record the match
					table.insert(matches, {
						Id = currentOrderEntry.Id,
						Quantity = tostring(fillAmount),
						Price = tostring(currentOrderEntry.Price)
					})

					-- If there are remaining shares in the current order, keep it in the order book
					if bint(currentOrderEntry.Quantity) > bint(0) then
						table.insert(updatedOrderbook, currentOrderEntry)
					end
				end
			else
				-- If the token does match the current token, just add the order back
				table.insert(updatedOrderbook, currentOrderEntry)
			end
		end

		-- If there is remaining quantity from the incoming order and it's a limit order, add it to the order book
		if remainingQuantity > bint(0) and orderType == 'Limit' then
			table.insert(updatedOrderbook, {
				Id = args.orderId,
				Quantity = tostring(remainingQuantity),
				OriginalQuantity = tostring(args.quantity),
				Creator = args.sender,
				Token = currentToken,
				DateCreated = tostring(args.timestamp),
				Price = tostring(args.price),
			})

			local limitDataSuccess, limitData = pcall(function()
				return json.encode({
					Order = {
						Id = args.orderId,
						DominantToken = validPair[1],
						SwapToken = validPair[2],
						Sender = args.sender,
						Receiver = nil,
						Quantity = tostring(remainingQuantity),
						Price = tostring(args.price),
						Timestamp = tostring(args.timestamp)
					}
				})
			end)

			ao.send({
				Target = ACTIVITY_PROCESS,
				Action = 'Update-Listed-Orders',
				Data = limitDataSuccess and limitData or ''
			})
		end

		-- Update the order book with remaining and new orders
		Orderbook[pairIndex].Orders = updatedOrderbook

		if #matches > 0 then
			local sumVolumePrice, sumVolume = 0, 0
			for _, match in ipairs(matches) do
				local volume = tonumber(match.Quantity)
				local price = tonumber(match.Price)
				sumVolumePrice = sumVolumePrice + (volume * price)
				sumVolume = sumVolume + volume
			end

			local vwap = sumVolumePrice / sumVolume
			Orderbook[pairIndex].PriceData = {
				Vwap = tostring(vwap),
				Block = tostring(args.blockheight),
				DominantToken = currentToken,
				MatchLogs = matches
			}

			ao.send({
				Target = args.sender,
				Action = 'Action-Response',
				Tags = { Status = 'Success', Message = 'Order created!', Handler = 'Create-Order' }
			})
		end
	else
		handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = 'Pair not found',
			Quantity = args.quantity,
			TransferToken = currentToken,
		})
	end
end

return ucm
