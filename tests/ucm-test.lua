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

local function createOrder(args)
	local validPair, pairError = validatePairData({ args.dominantToken, args.swapToken })

	if validPair then
		local currentToken = validPair[1]
		local pairIndex = getPairIndex(validPair)

		if pairIndex == -1 then
			table.insert(Orderbook, { Pair = validPair, Orders = {} })
			pairIndex = getPairIndex(validPair)
		end

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
			local orderType = nil
			local reverseOrders = {}
			local currentOrders = Orderbook[pairIndex].Orders
			local updatedOrderbook = {}
			local matches = {}

			if args.price then
				orderType = 'Limit'
			else
				orderType = 'Market'
			end

			table.sort(currentOrders, function(a, b)
				if a.Price and b.Price then
					return tonumber(a.Price) < tonumber(b.Price)
				else
					return true
				end
			end)

			for _, currentOrderEntry in ipairs(currentOrders) do
				if currentToken ~= currentOrderEntry.Token then
					table.insert(reverseOrders, currentOrderEntry)
				end
			end

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
						Price = tostring(args.price)
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

			local fillAmount = 0
			local receiveAmount = 0
			local remainingQuantity = tonumber(args.quantity)
			local dominantToken = Orderbook[pairIndex].Pair[1]

			for _, currentOrderEntry in ipairs(currentOrders) do
				local reversePrice = 1 / tonumber(currentOrderEntry.Price)

				if orderType == 'Limit' and args.price and tonumber(args.price) ~= reversePrice then
					table.insert(updatedOrderbook, currentOrderEntry)
				else
					local receiveFromCurrent = 0
					fillAmount = math.ceil(remainingQuantity * (tonumber(args.price) or reversePrice))

					if fillAmount <= tonumber(currentOrderEntry.Quantity) then
						receiveFromCurrent = math.ceil(remainingQuantity * reversePrice)
						currentOrderEntry.Quantity = tonumber(currentOrderEntry.Quantity) - fillAmount
						receiveAmount = receiveAmount + receiveFromCurrent

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

						remainingQuantity = 0
					else
						receiveFromCurrent = tonumber(currentOrderEntry.Quantity) or 0
						receiveAmount = receiveAmount + receiveFromCurrent
						local sendAmount = receiveFromCurrent * tonumber(currentOrderEntry.Price)
						remainingQuantity = remainingQuantity - sendAmount

						ao.send({
							Target = currentToken,
							Action = 'Transfer',
							Tags = {
								Recipient = currentOrderEntry.Creator,
								Quantity = tostring(sendAmount)
							},
						})

						currentOrderEntry.Quantity = 0
					end

					local dominantPrice = (dominantToken == currentToken) and (args.price or reversePrice) or
						currentOrderEntry.Price

					if receiveFromCurrent > 0 then
						table.insert(matches, {
							Id = currentOrderEntry.Id,
							Quantity = tostring(receiveFromCurrent),
							Price = dominantPrice
						})

						table.insert(ExecutedOrders, {
							OrderId = currentOrderEntry.Id,
							DominantToken = validPair[2],
							SwapToken = validPair[1],
							Sender = currentOrderEntry.Creator,
							Receiver = args.sender,
							Quantity = receiveFromCurrent,
							Price = dominantPrice,
							Timestamp = args.timestamp
						})

						if not SalesByAddress[currentOrderEntry.Creator] then
							SalesByAddress[currentOrderEntry.Creator] = 0
						end
						SalesByAddress[currentOrderEntry.Creator] = SalesByAddress[currentOrderEntry.Creator] + 1

						if not PurchasesByAddress[args.sender] then
							PurchasesByAddress[args.sender] = 0
						end
						PurchasesByAddress[args.sender] = PurchasesByAddress[args.sender] + 1

						ao.send({
							Target = PIXL_PROCESS,
							Action = 'Calculate-Streak',
							Tags = {
								Buyer = args.sender
							}
						})
					end

					if tonumber(currentOrderEntry.Quantity) ~= 0 then
						currentOrderEntry.Quantity = tostring(currentOrderEntry.Quantity)
						table.insert(updatedOrderbook, currentOrderEntry)
					end
				end
			end

			if remainingQuantity > 0 then
				if orderType == 'Limit' then
					table.insert(updatedOrderbook, {
						Id = args.orderId,
						Quantity = tostring(remainingQuantity),
						OriginalQuantity = tostring(args.quantity),
						Creator = args.sender,
						Token = currentToken,
						DateCreated = tostring(args.timestamp),
						Price = tostring(args.price)
					})
				else
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

			ao.send({
				Target = validPair[2],
				Action = 'Transfer',
				Tags = {
					Recipient = args.sender,
					Quantity = tostring(receiveAmount)
				}
			})

			Orderbook[pairIndex].Orders = updatedOrderbook

			if #matches > 0 then
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
			TransferToken = nil,
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
