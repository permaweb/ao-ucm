local bint = require('.bint')(256)
local json = require('json')

local utils = require('utils')

if Name ~= 'Universal Content Marketplace' then Name = 'Universal Content Marketplace' end

ACTIVITY_PROCESS = '7_psKu3QHwzc2PFCJk2lEwyitLJbz6Vj7hOcltOulj4'
PIXL_PROCESS = 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo'
DEFAULT_SWAP_TOKEN = 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10'

VOUCH_PROCESS = 'ZTTO02BL2P-lseTLUgiIPD9d0CF1sc4LbMA2AQ7e9jo'
VOUCHER_WHITELIST = {
	-- Vouch-X
	['Ax_uXyLQBPZSQ15movzv9-O1mDo30khslqN64qD27Z8'] = true,
	-- Vouch-Gitcoin-Passport
	['k6p1MtqYhQQOuTSfN8gH7sQ78zlHavt8dCDL88btn9s'] = true,
	-- Vouch-AO-Balance
	['QeXDjjxcui7W2xU08zOlnFwBlbiID4sACpi0tSS3VgY'] = true,
	-- Vouch-wAR-Stake
	['3y0YE11i21hpP8UY0Z1AVhtPoJD4V_AbEBx-g0j9wRc'] = true,
}
VOUCH_SCORE = 2

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
	-- print('Handling order error...')
	if args.TransferToken and args.Quantity and utils.checkValidAmount(args.Quantity) then
		-- print('Returning funds...')
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

function GetVouchScoreUsd(walletId)
	ao.send({
		Target = VOUCH_PROCESS,
		Tags = {
			Action = 'Get-Vouches',
			ID = walletId,
		}
	})

	local resp = Handlers.receive({
		From = VOUCH_PROCESS,
		Action = 'VouchDAO.Vouches',
		ID = walletId,
	})

	local success, data = pcall(json.decode, resp.Data)
	if not success or type(data) ~= 'table' then
		-- print('Invalid data: ' .. resp.Data)
		return 0
	end

	local vouches = data['Vouchers']
	if vouches == nil then
		-- print('No Vouchers')
		return 0
	end

	local score = 0
	for voucher, vouch in pairs(vouches) do
		if VOUCHER_WHITELIST[voucher] then
			local vouchFor = vouch['Vouch-For']
			if vouchFor ~= walletId then
				-- print(voucher .. ' has Vouch-For mismatch, expected: ' .. walletId .. ', got: ' .. vouchFor)
			else
				-- 1.34-USD -> 1.34
				local valueStr = string.match(vouch.Value, '([%d%.]+)-USD')
				local value = tonumber(valueStr)
				if valueStr == nil or value == nil then
					-- print(voucher .. ' has invalid value: ' .. vouch.Value)
				else
					score = score + value
				end
			end
		end
	end

	return score
end

function ucm.createOrder(args, msg)
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
		local orderType

		if args.price then
			orderType = 'Limit'
		else
			orderType = 'Market'
		end

		local remainingQuantity = bint(args.quantity)
		local currentOrders = Orderbook[pairIndex].Orders
		local updatedOrderbook = {}
		local matches = {}

		-- Sort order entries based on price
		table.sort(currentOrders, function(a, b)
			return bint(a.Price) < bint(b.Price)
		end)

		-- If the incoming order is a limit order, add it to the order book
		if orderType == 'Limit' then
			table.insert(currentOrders, {
				Id = args.orderId,
				Quantity = tostring(args.quantity),
				OriginalQuantity = tostring(args.quantity),
				Creator = args.sender,
				Token = currentToken,
				DateCreated = args.timestamp,
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
						Quantity = tostring(args.quantity),
						Price = tostring(args.price),
						Timestamp = args.timestamp
					}
				})
			end)

			ao.send({
				Target = ACTIVITY_PROCESS,
				Action = 'Update-Listed-Orders',
				Data = limitDataSuccess and limitData or ''
			})

			ao.send({
				Target = args.sender,
				Action = 'Order-Success',
				Tags = {
					Status = 'Success',
					Handler = 'Create-Order',
					DominantToken = currentToken,
					SwapToken = args.swapToken,
					Quantity = tostring(args.quantity),
					Price = tostring(args.price),
					Message = 'Order created!'
				}
			})

			return
		end

		-- Log
		-- print('Order type: ' .. orderType)
		-- print('Match ID: ' .. args.orderId)
		-- print('Swap token: ' .. args.swapToken)
		-- print('Order recipient: ' .. args.sender)
		-- print('Input quantity: ' .. tostring(remainingQuantity))

		for _, currentOrderEntry in ipairs(currentOrders) do
			if remainingQuantity > bint(0) and bint(currentOrderEntry.Quantity) > bint(0) then
				local fillAmount, sendAmount

				local transferDenomination = args.transferDenomination and bint(args.transferDenomination) > bint(1)

				-- Calculate how many shares can be bought with the remaining quantity
				if transferDenomination then
					fillAmount = remainingQuantity // bint(currentOrderEntry.Price)
				else
					fillAmount = math.floor(remainingQuantity / bint(currentOrderEntry.Price))
				end

				-- Calculate the total cost for the fill amount
				sendAmount = fillAmount * bint(currentOrderEntry.Price)

				-- Adjust the fill amount to not exceed the order's available quantity
				local quantityCheck = bint(currentOrderEntry.Quantity)
				if transferDenomination then
					quantityCheck = quantityCheck // bint(args.transferDenomination)
				end

				if sendAmount > (quantityCheck * bint(currentOrderEntry.Price)) then
					sendAmount = bint(currentOrderEntry.Quantity) * bint(currentOrderEntry.Price)
					if transferDenomination then
						sendAmount = sendAmount // bint(args.transferDenomination)
					end
				end

				-- Handle tokens with a denominated value
				if transferDenomination then
					if fillAmount > bint(0) then fillAmount = fillAmount * bint(args.transferDenomination) end
				end

				-- Ensure the fill amount does not exceed the available quantity in the order
				if fillAmount > bint(currentOrderEntry.Quantity) then
					fillAmount = bint(currentOrderEntry.Quantity)
				end

				-- Subtract the used quantity from the buyer's remaining quantity
				if transferDenomination then
					remainingQuantity = remainingQuantity -
						(fillAmount // bint(args.transferDenomination) * bint(currentOrderEntry.Price))
				else
					remainingQuantity = remainingQuantity - fillAmount * bint(currentOrderEntry.Price)
				end

				currentOrderEntry.Quantity = tostring(bint(currentOrderEntry.Quantity) - fillAmount)

				if fillAmount <= bint(0) then
					handleError({
						Target = args.sender,
						Action = 'Order-Error',
						Message = 'No amount to fill',
						Quantity = args.quantity,
						TransferToken = currentToken,
					})
					return
				end

				local calculatedSendAmount = utils.calculateSendAmount(sendAmount)
				local calculatedFillAmount = utils.calculateFillAmount(fillAmount)

				-- Log
				-- print('Order creator: ' .. currentOrderEntry.Creator)
				-- print('Fill amount (to buyer): ' .. tostring(fillAmount))
				-- print('Send amount (to seller): ' .. tostring(calculatedSendAmount) .. ' (0.5% fee captured)')
				-- print('Remaining fill quantity (purchase amount): ' .. tostring(remainingQuantity))
				-- print('Remaining order quantity (listing): ' .. tostring(currentOrderEntry.Quantity) .. '\n')

				-- Send tokens to the current order creator
				ao.send({
					Target = currentToken,
					Action = 'Transfer',
					Tags = {
						Recipient = currentOrderEntry.Creator,
						Quantity = tostring(calculatedSendAmount)
					}
				})

				-- Send swap tokens to the input order creator
				ao.send({
					Target = args.swapToken,
					Action = 'Transfer',
					Tags = {
						Recipient = args.sender,
						Quantity = tostring(calculatedFillAmount)
					}
				})

				-- Record the match
				table.insert(matches, {
					Id = currentOrderEntry.Id,
					Quantity = calculatedFillAmount,
					Price = tostring(currentOrderEntry.Price)
				})

				local matchedDataSuccess, matchedData = pcall(function()
					return json.encode({
						Order = {
							Id = currentOrderEntry.Id,
							MatchId = args.orderId,
							DominantToken = validPair[2],
							SwapToken = validPair[1],
							Sender = currentOrderEntry.Creator,
							Receiver = args.sender,
							Quantity = calculatedFillAmount,
							Price = tostring(currentOrderEntry.Price),
							Timestamp = args.timestamp
						}
					})
				end)

				ao.send({
					Target = ACTIVITY_PROCESS,
					Action = 'Update-Executed-Orders',
					Data = matchedDataSuccess and matchedData or ''
				})

				-- ao.send({
				-- 	Target = msg.Tags.Sender,
				-- 	Action = 'Info'
				-- })

				-- local resp = Handlers.receive({
				-- 	From = msg.Tags.Sender,
				-- 	Action = 'Read-Success'
				-- })

				-- local success, rData = pcall(json.decode, resp.Data)
				-- if not success or type(rData) ~= 'table' then
				-- 	ao.send({
				-- 		Target = msg.From,
				-- 		Action = 'Transfer',
				-- 		Tags = {
				-- 			Recipient = msg.Tags.Sender,
				-- 			Quantity = msg.Tags.Quantity
				-- 		}
				-- 	})
				-- 	return print('Invalid vouch data: ' .. resp.Data)
				-- end

				-- local profileWallet = rData.Owner

				-- local score = GetVouchScoreUsd(profileWallet)

				-- if score >= VOUCH_SCORE then
				-- Calculate streaks
				ao.send({
					Target = PIXL_PROCESS,
					Action = 'Calculate-Streak',
					Tags = {
						Buyer = args.sender
					}
				})
				-- end

				-- Get balance notice and execute PIXL buyback
				if orderType == 'Market' and currentToken == DEFAULT_SWAP_TOKEN and args.sender ~= ao.id then
					ao.send({ Target = DEFAULT_SWAP_TOKEN, Action = 'Balance', Recipient = ao.id })
				end

				-- If there are remaining shares in the current order, keep it in the order book
				if bint(currentOrderEntry.Quantity) > bint(0) then
					table.insert(updatedOrderbook, currentOrderEntry)
				end
			else
				if bint(currentOrderEntry.Quantity) > bint(0) then
					table.insert(updatedOrderbook, currentOrderEntry)
				end
			end
		end

		-- Update the order book with remaining and new orders
		Orderbook[pairIndex].Orders = updatedOrderbook

		local sumVolumePrice, sumVolume = 0, 0
		if #matches > 0 then
			for _, match in ipairs(matches) do
				local volume = bint(match.Quantity)
				local price = bint(match.Price)
				sumVolumePrice = sumVolumePrice + (volume * price)
				sumVolume = sumVolume + volume
			end

			local vwap = sumVolumePrice / sumVolume
			Orderbook[pairIndex].PriceData = {
				Vwap = tostring(math.floor(vwap)),
				Block = tostring(args.blockheight),
				DominantToken = currentToken,
				MatchLogs = matches
			}
		end

		if sumVolume > 0 then
			ao.send({
				Target = args.sender,
				Action = 'Order-Success',
				Tags = {
					Status = 'Success',
					Handler = 'Create-Order',
					DominantToken = currentToken,
					SwapToken = args.swapToken,
					Quantity = tostring(sumVolume),
					Price = args.price and tostring(args.price) or 'None',
					Message = 'Order created!',
				}
			})
		else
			handleError({
				Target = args.sender,
				Action = 'Order-Error',
				Message = 'No amount to fill',
				Quantity = args.quantity,
				TransferToken = currentToken,
			})
			return
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

function ucm.executeBuyback(args, msg)
	local pixlPairIndex = ucm.getPairIndex({ DEFAULT_SWAP_TOKEN, PIXL_PROCESS })

	if pixlPairIndex > -1 then
		if Orderbook[pixlPairIndex].Orders and #Orderbook[pixlPairIndex].Orders > 0 then
			-- Calculate buyback amount
			local buybackAmount = bint(0)
			for _, order in ipairs(Orderbook[pixlPairIndex].Orders) do
				buybackAmount = buybackAmount + ((bint(order.Quantity) * bint(order.Price)) // bint(1000000))

				-- if bint(args.quantity) >= buybackAmount then
				-- 	print('Buyback amount met: ' .. tostring(buybackAmount))
				-- 	break
				-- end

				if buybackAmount >= bint(args.quantity) then
					buybackAmount = bint(args.quantity)
					-- print('Buyback amount met: ' .. tostring(buybackAmount))
					break
				end
			end

			-- print('Quantity: ' .. tostring(args.quantity))
			-- print('Buyback amount: ' .. tostring(buybackAmount))
			if buybackAmount > bint(0) and bint(args.quantity) >= bint(buybackAmount) and bint(buybackAmount) >= bint(Orderbook[pixlPairIndex].Orders[1].Price) then
				-- print('Executing buyback...')
				-- Execute buyback
				ucm.createOrder({
					orderId = args.orderId,
					dominantToken = DEFAULT_SWAP_TOKEN,
					swapToken = PIXL_PROCESS,
					sender = ao.id,
					quantity = tostring(buybackAmount),
					timestamp = args.timestamp,
					blockheight = args.blockheight,
					transferDenomination = '1000000'
				}, msg)
			end
		end
	end
end

return ucm
