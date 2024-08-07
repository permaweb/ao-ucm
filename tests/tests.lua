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

for i = 1, 1 do
	Orderbook = {
		{
			Pair = { 'e0T2NT6ka_VIp3hBWbjh6mOIcrUx9Dnj_moGC17hlx0', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			Orders = {
				{
					Creator = "VM-MdiAiJBatLtT09hBqoEVzsaKRN5G6un3WQ92fAy4",
					DateCreated = "1722429830403",
					Id = "hwEH2k7ToU7O7EL831obmTVM_MFjjzXPBuTRX3c96Qc",
					OriginalQuantity = "58",
					Price = "10444000000000",
					Quantity = "56",
					Token = "e0T2NT6ka_VIp3hBWbjh6mOIcrUx9Dnj_moGC17hlx0"
				},
			},
		},
		{
			Pair = { 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo', 'xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10' },
			Orders = {
				{
					Creator = "RZrD7mS8Ih7ExGUmTeUkD57NX1XcKZNQ19r0gSnq_08",
					DateCreated = "1722428783509",
					Id = "SDg7KoNnBJNd5VaXCn_sRaL4j4AFKCO_rz-D3Vwe5fc",
					OriginalQuantity = "1000000000",
					Price = "1800000000",
					Quantity = "453000000",
					Token = "DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo"
				}
			}
		}
	}

	local matchingOrder = {
		orderId = tostring(i * 2),
		dominantToken ='xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10',
		swapToken = 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo',
		sender = "User" .. tostring(i * 2),
		quantity = '1000000000',
		timestamp = os.time() + 1,
		blockheight = '123456789',
		transferDenomination = '1000000'
	}

	-- ucm.createOrder(limitOrder)
	ucm.createOrder(matchingOrder)
	-- printTable(Orderbook)

	-- Order was not completely filled
	-- if #Orderbook[#Orderbook].Orders > 0 then
	-- 	printColor('Order failed', 'red')
	-- 	printTable(Orderbook[#Orderbook].Orders)
	-- 	os.exit(1)
	-- else
	-- 	printColor('Order ' .. i .. ' filled ' .. '(total quantity: ' .. matchQuantity .. ')', 'green')
	-- end
end
