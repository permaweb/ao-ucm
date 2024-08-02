local bint = require('.bint')(256)
local json = require('json')

local ao
local success, aoModule = pcall(require, 'ao')
if success then
	ao = aoModule
else
	ao = {
		send = function(msg) print(msg.Action .. ': ' .. (msg.Tags and msg.Tags.Message or 'None')) end
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

function ucm.createOrder(args) -- orderId, dominantToken, swapToken, sender, quantity, price?, transferDenomination?, timestamp
	local validPair, pairError = utils.validatePairData({ args.dominantToken, args.swapToken })

	-- If the pair is valid then handle the order and remove the claim status entry
	if validPair then
		-- Get the current token to execute on, it will always be the first in the pair
		local currentToken = validPair[1]

		-- Ensure the pair exists
		local pairIndex = ucm.getPairIndex(validPair)

		-- If the pair does not exist yet then add it
		if pairIndex == -1 then
			table.insert(Orderbook, { Pair = validPair, Orders = {} })
			pairIndex = ucm.getPairIndex(validPair)
		end

		-- Check if quantity is a valid integer greater than zero
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

		-- Log
		print('Input quantity: ' .. args.quantity)

		-- Check if price is a valid integer greater than zero, if it is present
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
			-- Find order matches and update the orderbook
			local orderType = nil
			local reverseOrders = {}
			local currentOrders = Orderbook[pairIndex].Orders
			local updatedOrderbook = {}
			local matches = {}

			-- Determine order type based on if price is passed
			if args.price then
				orderType = 'Limit'
			else
				orderType = 'Market'
			end

			-- Sort order entries based on price
			table.sort(currentOrders, function(a, b)
				if a.Price and b.Price then
					return bint(a.Price) < bint(b.Price)
				else
					return true
				end
			end)

			-- Find reverse orders for potential matches
			for _, currentOrderEntry in ipairs(currentOrders) do
				if currentToken ~= currentOrderEntry.Token then
					table.insert(reverseOrders, currentOrderEntry)
				end
			end

			-- If there are no reverse orders, only push the current order entry, but first check if it is a limit order
			if #reverseOrders <= 0 then
				if orderType ~= 'Limit' then
					handleError({
						Target = args.sender,
						Action = 'Order-Error',
						Message = 'The first order entry must be a limit order',
						Quantity = args.quantity,
						TransferToken = currentToken,
					})
				else
					table.insert(currentOrders, {
						Id = args.orderId,
						Creator = args.sender,
						Quantity = tostring(args.quantity),
						OriginalQuantity = tostring(args.quantity),
						Token = currentToken,
						DateCreated = tostring(args.timestamp),
						Price = tostring(args.price) -- Price is ensured because it is a limit order
					})

					local listedDataSuccess, listedData = pcall(function()
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
						Data = listedDataSuccess and listedData or ''
					})

					ao.send({ Target = args.sender, Action = 'Action-Response', Tags = { Status = 'Success', Message = 'Order created!', Handler = 'Create-Order' } })
				end
				return
			end

			-- The total amount of tokens the user would receive if it is a market order
			-- This changes for each order in the orderbook
			-- If it is a limit order, it will always be the same
			local fillAmount = 0

			-- The total amount of tokens the user of the input order will receive
			local receiveAmount = 0

			-- The remaining tokens to be matched with an order
			local remainingQuantity = args.quantity

			-- Log
			print('Remaining quantity: ' .. remainingQuantity)

			-- The dominant token from the pair, it will always be the first one
			local dominantToken = Orderbook[pairIndex].Pair[1]

			for _, currentOrderEntry in ipairs(currentOrders) do
				-- Price of the current order reversed to the input token

				-- TODO
				local reversePrice = 1 / tonumber(currentOrderEntry.Price)

				-- Log
				print('ReversePrice: ' .. reversePrice)
				print('Formatted: ' .. string.format("%.12f", reversePrice))

				if orderType == 'Limit' and args.price and tonumber(args.price) ~= reversePrice then
					-- Continue if the current order price matches the input order price and it is a limit order
					table.insert(updatedOrderbook, currentOrderEntry)
				else
					-- The input order creator receives this many tokens from the current order
					local receiveFromCurrent = 0

					-- Log
					print('Price: ' .. (args.price or 'None'))

					-- Calculate the fill amount
					local priceToUse = tonumber(args.price) or reversePrice
					print('Price to use: ' .. string.format("%.12f", priceToUse))
					print('Type of priceToUse:', type(priceToUse))

					local nonRoundedFillAmount = tonumber(remainingQuantity) * priceToUse
					print('Remaining Quantity: ' .. remainingQuantity)
					print('Type of remainingQuantity:', type(remainingQuantity))
					print('Non rounded fill amount: ' .. string.format("%.12f", nonRoundedFillAmount))
					print('Type of nonRoundedFillAmount:', type(nonRoundedFillAmount))

					-- Additional diagnostic logging
					print('Remaining Quantity (raw):', remainingQuantity)
					print('Price to use (raw):', priceToUse)
					print('Non rounded fill amount (raw):', nonRoundedFillAmount)
					print('Type of nonRoundedFillAmount (raw):', type(nonRoundedFillAmount))

					-- Check the exact bit representation of the floating point number (if possible)
					local function toBits(num)
						local t = {}
						while num > 0 do
							rest = math.fmod(num, 2)
							t[#t + 1] = rest
							num = (num - rest) / 2
						end
						return t
					end

					local bits = toBits(nonRoundedFillAmount)
					print('Bits of nonRoundedFillAmount:', table.concat(bits))

					-- -- Explicitly print the value before flooring
					print('Value before flooring (tostring): ' .. tostring(nonRoundedFillAmount))
					print('Value before flooring (string.format): ' .. string.format("%.12f", nonRoundedFillAmount))

					fillAmount = math.floor(nonRoundedFillAmount)
					print('Fill amount (math.floor): ' .. fillAmount)
					print('Type of fillAmount:', type(fillAmount))

					if args.transferDenomination and bint(args.transferDenomination) > bint(1) then
						if fillAmount > 0 then fillAmount = bint(fillAmount) * bint(args.transferDenomination) end
					end

					-- Log
					print('Current order quantity: ' .. tostring(currentOrderEntry.Quantity))

					if fillAmount <= tonumber(currentOrderEntry.Quantity) then
						-- The input order will be completely filled
						-- Calculate the receiving amount
						receiveFromCurrent = math.floor(remainingQuantity * reversePrice)

						if args.transferDenomination and bint(args.transferDenomination) > bint(1) then
							receiveFromCurrent = bint(receiveFromCurrent) * bint(args.transferDenomination)
						end

						-- Log
						print('Receive from current: ' .. tostring(receiveFromCurrent))

						-- Reduce the current order quantity
						currentOrderEntry.Quantity = tostring(bint(currentOrderEntry.Quantity) - fillAmount)

						-- Fill the remaining tokens
						receiveAmount = receiveAmount + receiveFromCurrent

						-- Log
						print('Receive amount: ' .. tostring(receiveAmount))

						-- Log
						print('Remaining quantity: ' .. tonumber(remainingQuantity))

						-- Send tokens to the current order creator
						if tonumber(remainingQuantity) > 0 and tonumber(tostring(receiveAmount)) > 0 then
							ao.send({
								Target = currentToken,
								Action = 'Transfer',
								Tags = {
									Recipient = currentOrderEntry.Creator,
									Quantity = tostring(remainingQuantity)
								}
							})
						else
							-- Log
							print('Order not filled, returning funds')
							print('Current token: ' .. currentToken)
							print('Sender: ' .. args.sender)
							print('Remaining quantity: ' .. tostring(remainingQuantity))

							-- Return the funds
							handleError({
								Target = args.sender,
								Action = 'Order-Error',
								Message = 'No orders to fulfill, returning funds',
								Quantity = args.quantity,
								TransferToken = currentToken,
							})
						end

						-- There are no tokens left in the order to be matched
						remainingQuantity = tostring(bint(0))
					else
						-- The input order will be partially filled
						-- Calculate the receiving amount
						receiveFromCurrent = tonumber(currentOrderEntry.Quantity) or 0

						-- Add all the tokens from the current order to fill the input order
						receiveAmount = bint(receiveAmount) + bint(receiveFromCurrent)

						-- The amount the current order creator will receive
						local sendAmount = receiveFromCurrent * bint(currentOrderEntry.Price)
						if args.transferDenomination and bint(args.transferDenomination) > bint(1) then
							sendAmount = math.floor(bint(sendAmount) / bint(args.transferDenomination))
						end

						-- Reduce the remaining tokens to be matched by the amount the user is going to receive from this order
						remainingQuantity = tostring(bint(remainingQuantity) - bint(sendAmount))

						-- Send tokens to the current order creator
						ao.send({
							Target = currentToken,
							Action = 'Transfer',
							Tags = {
								Recipient = currentOrderEntry.Creator,
								Quantity = tostring(sendAmount)
							}
						})

						-- There are no tokens left in the current order to be matched
						currentOrderEntry.Quantity = 0
					end

					-- Calculate the dominant token price
					local dominantPrice = (dominantToken == currentToken) and
						(args.price or reversePrice) or currentOrderEntry.Price

					-- If there is a receiving amount then push the match
					if tonumber(tostring(receiveFromCurrent)) > (0) then
						table.insert(matches,
							{
								Id = currentOrderEntry.Id,
								Quantity = tostring(receiveFromCurrent),
								Price =
									dominantPrice
							})

						local executedDataSuccess, executedData = pcall(function()
							return json.encode({
								Order = {
									Id = currentOrderEntry.Id,
									DominantToken = validPair[2],
									SwapToken = validPair[1],
									Sender = currentOrderEntry.Creator,
									Receiver = args.sender,
									Quantity = tostring(receiveFromCurrent),
									Price = dominantPrice,
									Timestamp = args.timestamp
								}
							})
						end)

						ao.send({
							Target = ACTIVITY_PROCESS,
							Action = 'Update-Executed-Orders',
							Data = executedDataSuccess and executedData or ''
						})

						-- Calculate streaks
						ao.send({
							Target = PIXL_PROCESS,
							Action = 'Calculate-Streak',
							Tags = {
								Buyer = args.sender
							}
						})
					end

					-- If the current order is not completely filled then keep it in the orderbook
					if tonumber(currentOrderEntry.Quantity) ~= tonumber(0) then
						currentOrderEntry.Quantity = tostring(currentOrderEntry.Quantity)
						table.insert(updatedOrderbook, currentOrderEntry)
					end
				end
			end

			-- If the input order is not completely filled, push it to the orderbook if it is a limit order or return the funds
			if tonumber(remainingQuantity) > (0) then
				if orderType == 'Limit' then
					-- Push it to the orderbook
					table.insert(updatedOrderbook, {
						Id = args.orderId,
						Quantity = tostring(remainingQuantity),
						OriginalQuantity = tostring(args.quantity),
						Creator = args.sender,
						Token = currentToken,
						DateCreated = tostring(args.timestamp),
						Price = tostring(args.price), -- Price is ensured because it is a limit order
					})
				else
					-- Log
					print('Order not filled, returning funds')
					print('Current token: ' .. currentToken)
					print('Sender: ' .. args.sender)
					print('Remaining quantity: ' .. remainingQuantity)

					-- Return the funds
					handleError({
						Target = args.sender,
						Action = 'Order-Error',
						Message = 'No orders to fulfill, returning funds',
						Quantity = args.quantity,
						TransferToken = currentToken,
					})
				end
			end

			-- Send swap tokens to the input order creator
			ao.send({
				Target = args.swapToken,
				Action = 'Transfer',
				Tags = {
					Recipient = args.sender,
					Quantity = tostring(receiveAmount)
				}
			})

			-- Post match processing
			Orderbook[pairIndex].Orders = updatedOrderbook

			if #matches > 0 then
				-- Calculate the volume weighted average price
				-- (Volume1 * Price1 + Volume2 * Price2 + ...) / (Volume1 + Volume2 + ...)
				local sumVolumePrice = 0
				local sumVolume = 0

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
					DominantToken = dominantToken,
					MatchLogs = matches
				}

				-- TODO: Handle sell
				ao.send({ Target = args.sender, Action = 'Action-Response', Tags = { Status = 'Success', Message = 'Order created!', Handler = 'Create-Order' } })
			else
				Orderbook[pairIndex].PriceData = nil
				ao.send({ Target = args.sender, Action = 'Action-Response', Tags = { Status = 'Error', Message = 'No orders to fulfill', Handler = 'Create-Order' } })
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
	else
		handleError({
			Target = args.sender,
			Action = 'Order-Error',
			Message = pairError or 'Error validating pair',
			Quantity = args.Quantity,
			TransferToken = nil, -- Pair can not be validated, no token to return
		})
	end
end

return ucm
