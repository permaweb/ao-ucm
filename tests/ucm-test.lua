local bint = require('.bint')(256)

PIXL_PROCESS = 'PIXL_PROCESS'

Orderbook = {}
ListedOrders = {}
ExecutedOrders = {}
SalesByAddress = {}
PurchasesByAddress = {}

local function printColor(text, color)
	local colors = {
		red = "\27[31m",
		green = "\27[32m",
		reset = "\27[0m"
	}
	print(colors[color] .. text .. colors.reset)
end

local function printTable(t, indent)
	local json = ""
	local function serialize(tbl, indentLevel)
		local isArray = #tbl > 0
		local tab = isArray and "[\n" or "{\n"
		local sep = isArray and ",\n" or ",\n"
		local endTab = isArray and "]" or "}"
		indentLevel = indentLevel + 1

		for k, v in pairs(tbl) do
			tab = tab .. string.rep("  ", indentLevel)
			if not isArray then
				tab = tab .. "\"" .. tostring(k) .. "\": "
			end

			if type(v) == "table" then
				tab = tab .. serialize(v, indentLevel) .. sep
			else
				if type(v) == "string" then
					tab = tab .. "\"" .. tostring(v) .. "\"" .. sep
				else
					tab = tab .. tostring(v) .. sep
				end
			end
		end

		if tab:sub(-2) == sep then
			tab = tab:sub(1, -3) .. "\n"
		end

		indentLevel = indentLevel - 1
		tab = tab .. string.rep("  ", indentLevel) .. endTab
		return tab
	end

	json = serialize(t, indent or 0)
	print(json)
end

local function compareTables(t1, t2)
	if type(t1) ~= type(t2) then return false end
	if type(t1) ~= "table" then return t1 == t2 end
	for k, v in pairs(t1) do
		if not compareTables(v, t2[k]) then return false end
	end
	for k, v in pairs(t2) do
		if not compareTables(v, t1[k]) then return false end
	end
	return true
end

local function checkValidAddress(address)
	if not address or type(address) ~= 'string' then
		return false
	end

	return string.match(address, "^[%w%-_]+$") ~= nil and #address == 43
end

local function checkValidAmount(data)
	return math.type(tonumber(data)) == 'integer'
end

local function validatePairData(data)
	-- Check if pair is a table with exactly two elements
	if type(data) ~= 'table' or #data ~= 2 then
		return nil, 'Pair must be a list of exactly two strings - [TokenId, TokenId]'
	end

	-- Check if both elements of the table are strings
	if type(data[1]) ~= 'string' or type(data[2]) ~= 'string' then
		return nil, 'Both pair elements must be strings'
	end

	-- Check if both elements are valid addresses
	if not checkValidAddress(data[1]) or not checkValidAddress(data[2]) then
		return nil, 'Both pair elements must be valid addresses'
	end

	-- Ensure the addresses are not equal
	if data[1] == data[2] then
		return nil, 'Pair addresses cannot be equal'
	end

	return data
end

local function getPairIndex(pair)
	local pairIndex = -1

	for i, existingOrders in ipairs(Orderbook) do
		if (existingOrders.Pair[1] == pair[1] and existingOrders.Pair[2] == pair[2]) or
			(existingOrders.Pair[1] == pair[2] and existingOrders.Pair[2] == pair[1]) then
			pairIndex = i
		end
	end

	return pairIndex
end

local function handleError(args) -- Target, TransferToken, Quantity
	-- If there is a valid quantity then return the funds
	if args.TransferToken and args.Quantity and checkValidAmount(args.Quantity) then
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

ao = {
	send = function(message)
		-- print("Action: " .. message.Action)
	end
}

local function createOrder(args) -- orderId, dominantToken, swapToken, sender, quantity, price?, transferDenomination?, timestamp
	local validPair, pairError = validatePairData({ args.dominantToken, args.swapToken })

	-- If the pair is valid then handle the order and remove the claim status entry
	if validPair then
		-- Get the current token to execute on, it will always be the first in the pair
		local currentToken = validPair[1]

		-- Ensure the pair exists
		local pairIndex = getPairIndex(validPair)

		-- If the pair does not exist yet then add it
		if pairIndex == -1 then
			table.insert(Orderbook, { Pair = validPair, Orders = {} })
			pairIndex = getPairIndex(validPair)
		end

		-- Check if quantity is a valid integer greater than zero
		if not checkValidAmount(args.quantity) then
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
		if args.price and not checkValidAmount(args.price) then
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
			local remainingQuantity = tonumber(args.quantity)

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

					------ TODO ------
					if args.transferDenomination and bint(args.transferDenomination) > bint(1) then
						fillAmount = math.floor(remainingQuantity * (tonumber(args.price) or reversePrice))
						fillAmount = bint(fillAmount) * bint(args.transferDenomination)
					end
					print(fillAmount)
					------------------

					if fillAmount <= tonumber(currentOrderEntry.Quantity) then
						print('Input order will be completely filled')
						-- The input order will be completely filled
						-- Calculate the receiving amount
						receiveFromCurrent = math.ceil(remainingQuantity * reversePrice)

						------ TODO ------
						if args.transferDenomination and bint(args.transferDenomination) > bint(1) then
							receiveFromCurrent = math.floor(remainingQuantity * reversePrice)
							receiveFromCurrent = bint(receiveFromCurrent) * bint(args.transferDenomination)
						end

						print('Receive from current')
						print(receiveFromCurrent)
						------------------

						-- Reduce the current order quantity
						currentOrderEntry.Quantity = tonumber(currentOrderEntry.Quantity) - fillAmount

						-- Fill the remaining tokens
						receiveAmount = receiveAmount + receiveFromCurrent

						print('Receive amount')
						print(receiveAmount)

						-- Send tokens to the current order creator
						if remainingQuantity > 0 then
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
						remainingQuantity = 0
					else
						print('Input order will be partially filled')
						-- The input order will be partially filled
						-- Calculate the receiving amount
						receiveFromCurrent = tonumber(currentOrderEntry.Quantity) or 0
						------ TODO ------
						if args.transferDenomination and bint(args.transferDenomination) > bint(1) then
							receiveFromCurrent = bint(receiveFromCurrent) * bint(args.transferDenomination)
						end

						print('Receive from current')
						print(receiveFromCurrent)
						------------------

						-- Add all the tokens from the current order to fill the input order
						receiveAmount = receiveAmount + receiveFromCurrent

						-- The amount the current order creator will receive
						local sendAmount = receiveFromCurrent * tonumber(currentOrderEntry.Price)

						-- Reduce the remaining tokens to be matched by the amount the user is going to receive from this order
						remainingQuantity = remainingQuantity - sendAmount

						-- Send tokens to the current order creator
						ao.send({
							Target = currentToken,
							Action = 'Transfer',
							Tags = {
								Recipient = currentOrderEntry.Creator,
								Quantity = tostring(sendAmount)
							},
							Data = json.encode({
								Recipient = currentOrderEntry.Creator,
								Quantity = sendAmount
							})
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
						print('Keeping entry in orderbook')

						print('Quantity')
						print(tonumber(currentOrderEntry.Quantity))

						print('Current entry')
						print(currentOrderEntry.Quantity)

						-- Reassign quantity as a string
						currentOrderEntry.Quantity = tostring(currentOrderEntry.Quantity)

						table.insert(updatedOrderbook, currentOrderEntry)
					end
				end
			end

			-- If the input order is not completely filled, push it to the orderbook if it is a limit order or return the funds
			if remainingQuantity > 0 then
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
					ao.send({
						Target = currentToken,
						Action = 'Transfer',
						Tags = {
							Recipient = args.sender,
							Quantity = tostring(remainingQuantity)
						},
						Data = json.encode({
							Recipient = args.sender,
							Quantity = remainingQuantity
						})
					})
				end
			end

			print('Receive amount')
			print(tostring(receiveAmount))

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

for i = 1, 1 do
	local pair = { "j8mX0PcExUwBbyVqIKr3dgYHh7ah4nmpqp60LIpSmTc", "6Wf1kGJ3NKH0E6rDX6WZCx6GigW3NoWjUN7PVOMXBIU" }

	local quantity = math.random(1, 1000000)
	local price = math.random(1, 1000000)

	local limitOrder = {
		orderId = tostring(i * 2 - 1),
		dominantToken = pair[1],
		swapToken = pair[2],
		sender = "User" .. tostring(i * 2 - 1),
		quantity = quantity,
		price = price,
		timestamp = os.time(),
		blockheight = 123456
	}

	local matchingOrder = {
		orderId = tostring(i * 2),
		dominantToken = pair[2],
		swapToken = pair[1],
		sender = "User" .. tostring(i * 2),
		quantity = quantity * price,
		timestamp = os.time() + 1,
		blockheight = 123456
	}

	print("Creating order: " .. limitOrder.orderId)
	createOrder(limitOrder)

	print("Matching order: " .. matchingOrder.orderId)
	createOrder(matchingOrder)

	-- Order was not completely filled
	if #Orderbook[#Orderbook].Orders > 0 then
		printColor('Order failed', 'red')
		printTable(Orderbook[#Orderbook].Orders)
		os.exit(1)
	else
		printColor('Order filled ' .. '(total quantity: ' .. quantity * price .. ')', 'green')
	end
end
