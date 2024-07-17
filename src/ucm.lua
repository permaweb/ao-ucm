local json = require('json')
local bint = require('.bint')(256)

local ao
local success, aoModule = pcall(require, 'ao')
if success then
	ao = aoModule
else
	ao = {
		send = function(msg)
			-- print(msg.Action .. ' ' .. (msg.Tags.Quantity or ''))
		end
	}
end

local utils = require('utils')

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
if not ListedOrders then ListedOrders = {} end
if not ExecutedOrders then ExecutedOrders = {} end
if not SalesByAddress then SalesByAddress = {} end
if not PurchasesByAddress then PurchasesByAddress = {} end

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

					table.insert(ListedOrders, {
						OrderId = args.orderId,
						DominantToken = validPair[1],
						SwapToken = validPair[2],
						Sender = args.sender,
						Receiver = nil,
						Quantity = tostring(args.quantity),
						Price = tostring(args.price),
						Timestamp = args.timestamp
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
			local remainingQuantity = tostring(bint(args.quantity))

			-- The dominant token from the pair, it will always be the first one
			local dominantToken = Orderbook[pairIndex].Pair[1]

			for _, currentOrderEntry in ipairs(currentOrders) do
				-- Price of the current order reversed to the input token
				local reversePrice = 1 / tonumber(currentOrderEntry.Price)

				if orderType == 'Limit' and args.price and tonumber(args.price) ~= reversePrice then
					-- Continue if the current order price matches the input order price and it is a limit order
					table.insert(updatedOrderbook, currentOrderEntry)
				else
					-- The input order creator receives this many tokens from the current order
					local receiveFromCurrent = 0

					-- Set the total amount of tokens to be received
					fillAmount = math.ceil(remainingQuantity * (tonumber(args.price) or reversePrice))
					if args.transferDenomination and bint(args.transferDenomination) > bint(1) then
						-- fillAmount = math.floor(remainingQuantity * (tonumber(args.price) or reversePrice))
						if fillAmount > 0 then fillAmount = bint(fillAmount) * bint(args.transferDenomination) end
					end

					if fillAmount <= tonumber(currentOrderEntry.Quantity) then
						-- The input order will be completely filled
						-- Calculate the receiving amount
						receiveFromCurrent = math.ceil(remainingQuantity * reversePrice)

						if args.transferDenomination and bint(args.transferDenomination) > bint(1) then
							-- receiveFromCurrent = math.floor(remainingQuantity * reversePrice)
							receiveFromCurrent = bint(receiveFromCurrent) * bint(args.transferDenomination)
						end

						-- Reduce the current order quantity
						currentOrderEntry.Quantity = tostring(bint(currentOrderEntry.Quantity) - fillAmount)
						-- print(currentOrderEntry.Quantity)

						-- Fill the remaining tokens
						receiveAmount = receiveAmount + receiveFromCurrent

						-- Send tokens to the current order creator
						if bint(remainingQuantity) > bint(0) then
							-- TODO
							-- print('remaining quantity')
							-- print(tostring(remainingQuantity))
							ao.send({
								Target = currentToken,
								Action = 'Transfer',
								Tags = {
									Recipient = currentOrderEntry.Creator,
									Quantity = tostring(remainingQuantity)
								}
							})
						end

						-- There are no tokens left in the order to be matched
						remainingQuantity = tostring(bint(0))
					else
						-- The input order will be partially filled
						-- Calculate the receiving amount
						receiveFromCurrent = tonumber(currentOrderEntry.Quantity) or 0

						print('Receive from current')
						print(receiveFromCurrent)

						-- if args.transferDenomination and bint(args.transferDenomination) > bint(1) then
						-- 	receiveFromCurrent = bint(receiveFromCurrent) * bint(args.transferDenomination)
						-- end

						-- Add all the tokens from the current order to fill the input order
						receiveAmount = bint(receiveAmount) + bint(receiveFromCurrent)

						-- TODO
						print('Receive amount')
						print(receiveAmount)

						-- The amount the current order creator will receive
						local sendAmount = receiveFromCurrent * bint(currentOrderEntry.Price)
						if args.transferDenomination and bint(args.transferDenomination) > bint(1) then
							sendAmount = math.floor(bint(sendAmount) / bint(args.transferDenomination))

							-- TODO
							print('Send amount')
							print(sendAmount)
						end

						-- Reduce the remaining tokens to be matched by the amount the user is going to receive from this order
						remainingQuantity = tostring(bint(remainingQuantity) - bint(sendAmount))

						-- TODO
						print('Send amount')
						print(tostring(sendAmount))

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
					if bint(receiveFromCurrent) > bint(0) then
						table.insert(matches,
							{
								Id = currentOrderEntry.Id,
								Quantity = tostring(receiveFromCurrent),
								Price =
									dominantPrice
							})

						-- Save executed order
						table.insert(ExecutedOrders, {
							OrderId = currentOrderEntry.Id,
							DominantToken = validPair[2],
							SwapToken = validPair[1],
							Sender = currentOrderEntry.Creator,
							Receiver = args.sender,
							Quantity = tostring(receiveFromCurrent),
							Price = dominantPrice,
							Timestamp = args.timestamp
						})

						-- Update user sales
						if not SalesByAddress[currentOrderEntry.Creator] then
							SalesByAddress[currentOrderEntry.Creator] = 0
						end
						SalesByAddress[currentOrderEntry.Creator] = SalesByAddress[currentOrderEntry.Creator] + 1

						if not PurchasesByAddress[args.sender] then
							PurchasesByAddress[args.sender] = 0
						end
						PurchasesByAddress[args.sender] = PurchasesByAddress[args.sender] + 1

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
					if bint(currentOrderEntry.Quantity) ~= bint(0) then
						currentOrderEntry.Quantity = tostring(currentOrderEntry.Quantity)
						table.insert(updatedOrderbook, currentOrderEntry)
					end
				end
			end

			-- If the input order is not completely filled, push it to the orderbook if it is a limit order or return the funds
			if bint(remainingQuantity) > bint(0) then
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
					-- Return the funds
					-- TODO
					-- print('remaining quantity')
					-- print(remainingQuantity)

					ao.send({
						Target = currentToken,
						Action = 'Transfer',
						Tags = {
							Recipient = args.sender,
							Quantity = tostring(remainingQuantity)
						}
					})
				end
			end

			-- TODO
			-- print('receive amount')
			-- print(receiveAmount)
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
					local volume = bint(match.Quantity)
					local price = bint(match.Price)

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
			else
				Orderbook[pairIndex].PriceData = nil
			end

			ao.send({ Target = args.sender, Action = 'Action-Response', Tags = { Status = 'Success', Message = 'Order created!', Handler = 'Create-Order' } })
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
