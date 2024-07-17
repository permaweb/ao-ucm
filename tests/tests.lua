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
	local pair = { "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY", "xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10" }

	-- local quantity = math.random(1, 1000000000000)
	-- local price = math.random(1, 1000000000000)

	local quantity = 555000000000
	local price = 555000000000

	-- local matchQuantity = tostring(bint(quantity) * bint(price))
	local matchQuantity = '470000000000'

	-- local limitOrder = {
	-- 	orderId = tostring(i * 2 - 1),
	-- 	dominantToken = pair[1],
	-- 	swapToken = pair[2],
	-- 	sender = 'User' .. tostring(i * 2 - 1),
	-- 	quantity = tostring(quantity),
	-- 	price = tostring(price),
	-- 	timestamp = os.time(),
	-- 	blockheight = '123456789',
	-- 	transferDenomination = '1000000000000'
	-- }

	Orderbook = {
		{
			Orders = {
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "50000000000000",
				Price = "9500000000",
				Id = "IM2m5a15oEzUfBACXpI6aeJSgEkS3tAcFPfVFaXad90",
				Creator = "xMt2cwM3we0nFGEQQ7jimjB0NwfKiKu2WOvDziMLB2I",
				DateCreated = "1721146313391",
				Quantity = "9000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "35000000000000",
				Price = "9500000000",
				Id = "QKUzY6myxG9qqjzSAUtMRL6_Emc-8GkM3OIfdhytYlk",
				Creator = "xMt2cwM3we0nFGEQQ7jimjB0NwfKiKu2WOvDziMLB2I",
				DateCreated = "1721178962648",
				Quantity = "35000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "10000000000000",
				Price = "10000000000",
				Id = "inm3EZHmPdo8_XPq-wNYuLDvevvwqq7sKSk84x6AunY",
				Creator = "CNTVc6TTie7QzK2lLl_GIOFwiC0sI39gvNXd3lutnr8",
				DateCreated = "1721087087204",
				Quantity = "8000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "20000000000000",
				Price = "10000000000",
				Id = "UoVT-AMcvcnf-Ol6_9kb_ljJ-PWu2taaSuRCFQK6S1E",
				Creator = "qMgsmMLPO97_9hkIHindsase983HjyZ9azYDyav6a8E",
				DateCreated = "1720875848055",
				Quantity = "5000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "10000000000000",
				Price = "20000000000",
				Id = "KH72a7jxud7wmrBEfjsv13flhvdzqCpGgwVIy5snHII",
				Creator = "CNTVc6TTie7QzK2lLl_GIOFwiC0sI39gvNXd3lutnr8",
				DateCreated = "1721087140904",
				Quantity = "10000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "20000000000000",
				Price = "20000000000",
				Id = "jubTWizBsS-6lHbwbz3vb3qSeBlHHxx6JddVEy7Zrjk",
				Creator = "hmb0_s6O8-v_VN3g03J-EwK2CSHwfuXvvwXcdGtMAVs",
				DateCreated = "1721047282390",
				Quantity = "20000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "10000000000000",
				Price = "30000000000",
				Id = "fTenOhq7KsZQdw-7GvWRs9ktyEn9nP3HHmILqmAe9vY",
				Creator = "VBM6vjz-wAUfeJkh9ZDfCSkLiYn3wANUJxQfYTW2tbI",
				DateCreated = "1720886020380",
				Quantity = "10000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "10000000000000",
				Price = "50000000000",
				Id = "udFX9FHbTBhfkey77zQ96DEQwKSQclyk8jffwvIZ1Sw",
				Creator = "JMS7P_To_Rs7c5WCATyHonAdFw_HvY2oyPWD07fbzMQ",
				DateCreated = "1720822421408",
				Quantity = "10000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "10000000000000",
				Price = "50000000000",
				Id = "ovnU6XPsdRYwE6W66Ms5zUZuoAx-mEieYMcpVqxFED0",
				Creator = "y1jKMd4rvYWYVjT_JQkr5dG4x4SpQVPHtSKP8untC84",
				DateCreated = "1720857818939",
				Quantity = "10000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "15000000000000",
				Price = "50000000000",
				Id = "-2DhEL903tu8ICMYsPumFDWR5gSclc21zhT13Unh1ic",
				Creator = "RDUTGmMSDBtjclDOUWp_sJ2flqIsR4Pu7lqz4Yq8JN4",
				DateCreated = "1720836370631",
				Quantity = "15000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "50000000000000",
				Price = "50000000000",
				Id = "pX3a0mhtCClw4mMnDjfkCsHJFF-drRJexLaUuRzb-00",
				Creator = "mtybGGg4lbiRjoDOnPDIMTfTOF6xV2yGejZSAAaTAM4",
				DateCreated = "1720880447056",
				Quantity = "50000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "15000000000000",
				Price = "70000000000",
				Id = "cHycZh66i5KnHLbCOxKlchZgFefil0Oo8ZyVUeAJAzQ",
				Creator = "RDUTGmMSDBtjclDOUWp_sJ2flqIsR4Pu7lqz4Yq8JN4",
				DateCreated = "1720836904803",
				Quantity = "15000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "10000000000000",
				Price = "100000000000",
				Id = "9-wQH1bKyihCJ9kbNWlg3CnIws1Qr3umBmmYrwgAh-g",
				Creator = "JMS7P_To_Rs7c5WCATyHonAdFw_HvY2oyPWD07fbzMQ",
				DateCreated = "1720822124954",
				Quantity = "10000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "50000000000000",
				Price = "100000000000",
				Id = "MSJBah_6eCjB9j1lZ7HUwfiSkSFW-MoJsSPlZPXF3p8",
				Creator = "mtybGGg4lbiRjoDOnPDIMTfTOF6xV2yGejZSAAaTAM4",
				DateCreated = "1720880643058",
				Quantity = "50000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "50000000000000",
				Price = "800000000000",
				Id = "o0_C920_Pc32wwjKbvR2QTjojY0SagSg6SvYPsyLmDk",
				Creator = "mtybGGg4lbiRjoDOnPDIMTfTOF6xV2yGejZSAAaTAM4",
				DateCreated = "1720880694676",
				Quantity = "50000000000000"
			 },
			 {
				Token = "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY",
				OriginalQuantity = "100000000000000",
				Price = "1000000000000",
				Id = "TjMjv8ZxxXldT1pwD7l6z9sZm7nlTIGJzD68JPiEe6A",
				Creator = "HNacF-BA63GH7uKZskwj8y9I7RIKJq20LDDUR1eC8xs",
				DateCreated = "1720822750067",
				Quantity = "100000000000000"
			 }
			},
			Pair = { "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY", "xU9zFkq3X2ZQ6olwNVvr1vUWIjc3kXTWr7xKQD6dh10" },
		}
	}

	local matchingOrder = {
		orderId = tostring(i * 2),
		dominantToken = pair[2],
		swapToken = pair[1],
		sender = "User" .. tostring(i * 2),
		quantity = matchQuantity,
		timestamp = os.time() + 1,
		blockheight = '123456789',
		transferDenomination = '1000000000000'
	}

	-- ucm.createOrder(limitOrder)
	ucm.createOrder(matchingOrder)
	printTable(Orderbook)

	-- Order was not completely filled
	-- if #Orderbook[#Orderbook].Orders > 0 then
	-- 	printColor('Order failed', 'red')
	-- 	printTable(Orderbook[#Orderbook].Orders)
	-- 	os.exit(1)
	-- else
	-- 	printColor('Order ' .. i .. ' filled ' .. '(total quantity: ' .. matchQuantity .. ')', 'green')
	-- end
end
