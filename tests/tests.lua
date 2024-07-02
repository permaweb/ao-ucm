package.path = package.path .. ";../src/?.lua"

local bint = require('.bint')(256)

local ucm = require('ucm')

local function printColor(text, color)
	local colors = {
		red = "\27[31m",
		green = "\27[32m",
		reset = "\27[0m"
	}
	print(colors[color] .. text .. colors.reset)
end

local function printTable(t, indent)
	local jsonStr = ""
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

	jsonStr = serialize(t, indent or 0)
	print(jsonStr)
end

for i = 1, 1000 do
	local pair = { "j8mX0PcExUwBbyVqIKr3dgYHh7ah4nmpqp60LIpSmTc", "6Wf1kGJ3NKH0E6rDX6WZCx6GigW3NoWjUN7PVOMXBIU" }

	local quantity = math.random(1, 1000000000000)
	local price = math.random(1, 1000000000000)

	local matchQuantity = tostring(bint(quantity) * bint(price))

	local limitOrder = {
		orderId = tostring(i * 2 - 1),
		dominantToken = pair[1],
		swapToken = pair[2],
		sender = 'User' .. tostring(i * 2 - 1),
		quantity = tostring(quantity),
		price = tostring(price),
		timestamp = os.time(),
		blockheight = '123456789',
		transferDenomination = '1000000'
	}

	local matchingOrder = {
		orderId = tostring(i * 2),
		dominantToken = pair[2],
		swapToken = pair[1],
		sender = "User" .. tostring(i * 2),
		quantity = matchQuantity,
		timestamp = os.time() + 1,
		blockheight = '123456789',
		transferDenomination = '1000000'
	}

	ucm.createOrder(limitOrder)
	ucm.createOrder(matchingOrder)

	-- Order was not completely filled
	if #Orderbook[#Orderbook].Orders > 0 then
		printColor('Order failed', 'red')
		printTable(Orderbook[#Orderbook].Orders)
		os.exit(1)
	else
		printColor('Order ' .. i .. ' filled ' .. '(total quantity: ' .. matchQuantity .. ')', 'green')
	end
end
