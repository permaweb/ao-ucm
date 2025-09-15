local json = require('JSON')
local bint = require('.bint')(256)

local utils = {}
if not AccruedFeesAmount then AccruedFeesAmount = 0 end

-- CHANGEME
ARIO_TOKEN_PROCESS_ID = 'agYcCFJtrMG6cqMuZfskIkFTGvUPddICmtQSBIoPdiA'

TREASURY_ADDRESS = 'cqnFNTEDGuWOOpnrrdoQZ262Be8e_kGT2na-BlGFyks'

function utils.checkValidAddress(address)
	if not address or type(address) ~= 'string' then
		return false
	end

	return string.match(address, '^[%w%-_]+$') ~= nil and #address == 43
end

function utils.checkValidAmount(data)
	return bint(data) > bint(0)
end

function utils.isArioToken(tokenAddress)
	return tokenAddress == ARIO_TOKEN_PROCESS_ID
end

function utils.validateArioSwapToken(tokenAddress)
	-- Allow ARIO tokens in both dominant and swap positions
	-- This enables both selling for ARIO and buying with ARIO
	return true, nil
end

function utils.validateArioInTrade(dominantToken, swapToken)
	-- At least one of the tokens in the trade must be ARIO
	if dominantToken == ARIO_TOKEN_PROCESS_ID or swapToken == ARIO_TOKEN_PROCESS_ID then
		return true, nil
	end
	return false, 'At least one token in the trade must be ARIO'
end

function utils.decodeMessageData(data)
	local status, decodedData = pcall(json.decode, data)

	if not status or type(decodedData) ~= 'table' then
		return false, nil
	end

	return true, decodedData
end

function utils.validatePairData(data)
	if type(data) ~= 'table' or #data ~= 2 then
		print('Pair must be a list of exactly two strings - [TokenId, TokenId]')
		return nil, 'Pair must be a list of exactly two strings - [TokenId, TokenId]'
	end

	if type(data[1]) ~= 'string' or type(data[2]) ~= 'string' then
		print('Both pair elements must be strings')
		return nil, 'Both pair elements must be strings'
	end

	if not utils.checkValidAddress(data[1]) or not utils.checkValidAddress(data[2]) then
		print('Both pair elements must be valid addresses')
		return nil, 'Both pair elements must be valid addresses'
	end

	if data[1] == data[2] then
		print('Pair addresses cannot be equal')
		return nil, 'Pair addresses cannot be equal'
	end

	return data
end

function utils.calculateSendAmount(amount)
	local factor = bint(995)
	local divisor = bint(1000)
	local sendAmount = (bint(amount) * factor) // divisor
	return tostring(sendAmount)
end

function utils.calculateFeeAmount(amount)
	local factor = bint(5)
	local divisor = bint(10000)
	local feeAmount = (bint(amount) * factor) // divisor
	return tostring(feeAmount)
end

function utils.calculateFillAmount(amount)
	return tostring(math.floor(tostring(amount)))
end

function utils.printTable(t, indent)
	local jsonStr = ''
	local function serialize(tbl, indentLevel)
		local isArray = #tbl > 0
		local tab = isArray and '[\n' or '{\n'
		local sep = isArray and ',\n' or ',\n'
		local endTab = isArray and ']' or '}'
		indentLevel = indentLevel + 1

		for k, v in pairs(tbl) do
			tab = tab .. string.rep('  ', indentLevel)
			if not isArray then
				tab = tab .. '\'' .. tostring(k) .. '\': '
			end

			if type(v) == 'table' then
				tab = tab .. serialize(v, indentLevel) .. sep
			else
				if type(v) == 'string' then
					tab = tab .. '\'' .. tostring(v) .. '\'' .. sep
				else
					tab = tab .. tostring(v) .. sep
				end
			end
		end

		if tab:sub(-2) == sep then
			tab = tab:sub(1, -3) .. '\n'
		end

		indentLevel = indentLevel - 1
		tab = tab .. string.rep('  ', indentLevel) .. endTab
		return tab
	end

	jsonStr = serialize(t, indent or 0)
	print(jsonStr)
end

function utils.checkTables(t1, t2)
	if t1 == t2 then return true end
	if type(t1) ~= 'table' or type(t2) ~= 'table' then return false end
	for k, v in pairs(t1) do
		if not utils.checkTables(v, t2[k]) then return false end
	end
	for k in pairs(t2) do
		if t1[k] == nil then return false end
	end
	return true
end

local testResults = {
    total = 0,
    passed = 0,
    failed = 0,
}

function utils.test(description, fn, expected)
    local colors = {
        red = '\27[31m',
        green = '\27[32m',
        blue = '\27[34m',
        reset = '\27[0m',
    }

    testResults.total = testResults.total + 1
    local testIndex = testResults.total

    print('\n' .. colors.blue .. 'Running test ' .. testIndex .. '... ' .. description .. colors.reset)
    local status, result = pcall(fn)
    if not status then
        testResults.failed = testResults.failed + 1
        print(colors.red .. 'Failed - ' .. description .. ' - ' .. result .. colors.reset .. '\n')
    else
        if utils.checkTables(result, expected) then
            testResults.passed = testResults.passed + 1
            print(colors.green .. 'Passed - ' .. description .. colors.reset)
        else
            testResults.failed = testResults.failed + 1
			if type(result) == 'table' and type(expected) == 'table' then
            	print(colors.red .. 'Failed - ' .. description .. colors.reset .. '\n')
            	print(colors.red .. 'Expected' .. colors.reset)
            	utils.printTable(expected)
            	print('\n' .. colors.red .. 'Got' .. colors.reset)
            	utils.printTable(result)
			else
				print(colors.red .. 'Failed - ' .. description .. colors.reset .. '\n')
				print(colors.red .. 'Expected' .. colors.reset)
				print(expected)
				print('\n' .. colors.red .. 'Got' .. colors.reset)
				print(result)
			end
        end
    end
end

function utils.testSummary()
    local colors = {
        red = '\27[31m',
        green = '\27[32m',
        reset = '\27[0m',
    }

    print('\nTest Summary')
    print('Total tests (' .. testResults.total .. ')')
    print('Result: ' .. testResults.passed .. '/' .. testResults.total .. ' tests passed')
    if testResults.passed == testResults.total then
        print(colors.green .. 'All tests passed!' .. colors.reset)
    else
        print(colors.green .. 'Tests passed: ' .. testResults.passed .. '/' .. testResults.total .. colors.reset)
        print(colors.red .. 'Tests failed: ' .. testResults.failed .. '/' .. testResults.total .. colors.reset .. '\n')
        os.exit(1)
    end
end

function utils.checkValidExpirationTime(expirationTime, timestamp)
	-- If expiration time is nil, return true
	if not expirationTime then
		return true, nil
	end

	-- Check if expiration time is a valid positive integer
	expirationTime = tonumber(expirationTime)
	if not expirationTime or not utils.checkValidAmount(expirationTime) then
		return false, 'Expiration time must be a valid positive integer'
	end

	-- Check if expiration time is greater than current timestamp
	local status, result = pcall(function()
		return bint(expirationTime) <= bint(timestamp)
	end)

	if not status then
		return false, 'Expiration time must be a valid timestamp'
	end

	if result then
		return false, 'Expiration time must be greater than current timestamp'
	end

	return true, nil
end


function utils.handleError(args) -- Target, TransferToken, Quantity
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
	ao.send({ Target = args.Target, Action = args.Action, Tags = { Status = 'Error', Message = args.Message, ['X-Group-ID'] = args.OrderGroupId } })
end

-- Helper function to execute token transfers
function utils.executeTokenTransfers(args, currentOrderEntry, validPair, calculatedSendAmount, calculatedFillAmount)
	-- Optionally record fee (difference between original send amount and calculated amount)
	if args and args.originalSendAmount then
		local ok1, orig = pcall(function() return bint(args.originalSendAmount) end)
		local ok2, calc = pcall(function() return bint(calculatedSendAmount) end)
		if ok1 and ok2 and orig > calc then
			local fee = orig - calc
			AccruedFeesAmount = AccruedFeesAmount + tonumber(tostring(fee))
		end
	end

	-- Transfer tokens to the seller (order creator)
	ao.send({
		Target = validPair[1],
		Action = 'Transfer',
		Tags = {
			Recipient = currentOrderEntry.Creator,
			Quantity = tostring(calculatedSendAmount)
		}
	})

	-- Transfer swap tokens to the buyer (order sender)
	ao.send({
		Target = args.swapToken,
		Action = 'Transfer',
		Tags = {
			Recipient = args.sender,
			Quantity = tostring(calculatedFillAmount)
		}
	})
end

-- Helper function to record match and send activity data
function utils.recordMatch(args, currentOrderEntry, validPair, calculatedFillAmount)
	-- Record the successful match
	local match = {
		Id = currentOrderEntry.Id,
		Quantity = calculatedFillAmount,
		Price = tostring(currentOrderEntry.Price)
	}

	-- Send match data to activity tracking
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
				--Use executionPrice if it exists for dutch order, otherwise original price.
				Price = args.executionPrice or tostring(currentOrderEntry.Price),
				CreatedAt = args.createdAt,
				EndedAt = args.createdAt,
				ExecutionTime = args.createdAt
			}
		})
	end)

	ao.send({
		Target = ACTIVITY_PROCESS,
		Action = 'Update-Executed-Orders',
		Data = matchedDataSuccess and matchedData or ''
	})

	return match
end

--- @class PaginationTag
--- @field cursor string nil The cursor to paginate from
--- @field limit number The limit of results to return
--- @field sortBy string nil The field to sort by
--- @field sortOrder string The order to sort by
--- @field filters table nil Optional filters to apply

--- Parses the pagination tags from a message
--- @param msg table The message provided to a handler (see ao docs for more info)
--- @return PaginationTags paginationTags - the pagination tags
function utils.parsePaginationTags(msg)
	local cursor = msg.Tags.Cursor
	local limit = tonumber(msg.Tags["Limit"]) or 100
	assert(limit <= 1000, "Limit must be less than or equal to 1000")
	local sortOrder = msg.Tags["Sort-Order"] and string.lower(msg.Tags["Sort-Order"]) or "desc"
	assert(sortOrder == "asc" or sortOrder == "desc", "Invalid sortOrder: expected 'asc' or 'desc'")
	local sortBy = msg.Tags["Sort-By"]
	local filters = utils.safeDecodeJson(msg.Tags.Filters)
	assert(msg.Tags.Filters == nil or filters ~= nil, "Invalid JSON supplied in Filters tag")
	return {
		cursor = cursor,
		limit = limit,
		sortBy = sortBy,
		sortOrder = sortOrder,
		filters = filters,
	}
end

--- Paginate a table with a cursor
--- @param tableArray table The table to paginate
--- @param cursor string number nil The cursor to paginate from (optional)
--- @param cursorField string nil The field to use as the cursor or nil for lists of primitives
--- @param limit number The limit of items to return
--- @param sortBy string nil The field to sort by. Nil if sorting by the primitive items themselves.
--- @param sortOrder string The order to sort by ("asc" or "desc")
--- @param filters table nil Optional filter table
--- @return PaginatedTable paginatedTable - the paginated table result
function utils.paginateTableWithCursor(tableArray, cursor, cursorField, limit, sortBy, sortOrder, filters)
	local filterFn = nil
	if type(filters) == "table" then
		filterFn = utils.createFilterFunction(filters)
	end

	local filteredArray = filterFn
			and utils.filterArray(tableArray, function(_, value)
				return filterFn(value)
			end)
		or tableArray

	assert(sortOrder == "asc" or sortOrder == "desc", "Invalid sortOrder: expected 'asc' or 'desc'")
	
	-- Default to sorting by CreatedAt if no sortBy is specified
	if not sortBy then
		sortBy = "CreatedAt"
	end
	
	local sortFields = { { order = sortOrder, field = sortBy } }
	if cursorField ~= nil and cursorField ~= sortBy then
		-- Tie-breaker to guarantee deterministic pagination
		table.insert(sortFields, { order = "asc", field = cursorField })
	end
	local sortedArray = utils.sortTableByFields(filteredArray, sortFields)

	if not sortedArray or #sortedArray == 0 then
		return {
			items = {},
			limit = limit,
			totalItems = 0,
			sortBy = sortBy,
			sortOrder = sortOrder,
			nextCursor = nil,
			hasMore = false,
		}
	end

	local startIndex = 1

	if cursor then
		-- Advance using consistent cursor field
		local cursorKey = cursorField or sortBy or "CreatedAt"
		local lastIndex = nil
		for i, obj in ipairs(sortedArray) do
			local value = cursorKey and obj[cursorKey] or obj
			if tostring(value) == tostring(cursor) then
				lastIndex = i
			end
		end
		if lastIndex then
			startIndex = lastIndex + 1
		end
	end

	local items = {}
	local endIndex = math.min(startIndex + limit - 1, #sortedArray)

	for i = startIndex, endIndex do
		table.insert(items, sortedArray[i])
	end

	local nextCursor = nil
	if endIndex < #sortedArray then
		local cursorKey = cursorField or sortBy or 'CreatedAt'
		nextCursor = tostring(sortedArray[endIndex][cursorKey])
	end

	return {
		items = items,
		limit = limit,
		totalItems = #sortedArray,
		sortBy = sortBy,
		sortOrder = sortOrder,
		nextCursor = nextCursor, -- the last item in the current page
		hasMore = nextCursor ~= nil,
	}
end

function utils.createLookupTable(tbl, valueFn)
	local lookupTable = {}
	valueFn = valueFn or function()
		return true
	end
	for key, value in pairs(tbl or {}) do
		lookupTable[value] = valueFn(key, value)
	end
	return lookupTable
end

--- Deep copies a table with optional exclusion of specified fields, including nested fields
--- Preserves proper sequential ordering of array tables when some of the excluded nested keys are array indexes
--- @generic T: table|nil
--- @param original T The table to copy
--- @param excludedFields table|nil An array of keys or dot-separated key paths to exclude from the deep copy
--- @return T The deep copy of the table or nil if the original is nil
function utils.deepCopy(original, excludedFields)
	if not original then
		return nil
	end

	if type(original) ~= "table" then
		return original
	end

	-- Fast path: If no excluded fields, copy directly
	if not excludedFields or #excludedFields == 0 then
		local copy = {}
		for key, value in pairs(original) do
			if type(value) == "table" then
				copy[key] = utils.deepCopy(value) -- Recursive copy for nested tables
			else
				copy[key] = value
			end
		end
		return copy
	end

	-- If excludes are provided, create a lookup table for excluded fields
	local excluded = utils.createLookupTable(excludedFields)

	-- Helper function to check if a key path is excluded
	local function isExcluded(keyPath)
		for excludedKey in pairs(excluded) do
			if keyPath == excludedKey or keyPath:match("^" .. excludedKey .. "%.") then
				return true
			end
		end
		return false
	end

	-- Recursive function to deep copy with nested field exclusion
	local function deepCopyHelper(orig, path)
		if type(orig) ~= "table" then
			return orig
		end

		local result = {}
		local isArray = true

		-- Check if all keys are numeric and sequential
		for key in pairs(orig) do
			if type(key) ~= "number" or key % 1 ~= 0 then
				isArray = false
				break
			end
		end

		if isArray then
			-- Collect numeric keys in sorted order for sequential reindexing
			local numericKeys = {}
			for key in pairs(orig) do
				table.insert(numericKeys, key)
			end
			table.sort(numericKeys)

			local index = 1
			for _, key in ipairs(numericKeys) do
				local keyPath = path and (path .. "." .. key) or tostring(key)
				if not isExcluded(keyPath) then
					result[index] = deepCopyHelper(orig[key], keyPath) -- Sequentially reindex
					index = index + 1
				end
			end
		else
			-- Handle non-array tables (dictionaries)
			for key, value in pairs(orig) do
				local keyPath = path and (path .. "." .. key) or key
				if not isExcluded(keyPath) then
					result[key] = deepCopyHelper(value, keyPath)
				end
			end
		end

		return result
	end

	-- Use the exclusion-aware deep copy helper
	return deepCopyHelper(original, nil)
end

--- Safely decodes a JSON string
--- @param jsonString string|nil The JSON string to decode
--- @return table|nil decodedJson - the decoded JSON or nil if the string is nil or the decoding fails
function utils.safeDecodeJson(jsonString)
	if not jsonString then
		return nil
	end
	local status, result = pcall(json.decode, jsonString)
	if not status then
		return nil
	end
	return result
end

--- Sorts a table by multiple fields with specified orders for each field.
--- Supports tables of non-table values by using `nil` as a field name.
--- Each field is provided as a table with 'field' (string|nil) and 'order' ("asc" or "desc").
--- Supports nested fields using dot notation.
--- @param prevTable table The table to sort
--- @param fields table A list of fields with order specified, e.g., { { field = "name", order = "asc" } }
--- @return table sortedTable - the sorted table
function utils.sortTableByFields(prevTable, fields)
	-- Handle sorting for non-table values with possible nils
	if fields[1].field == nil then
		-- Separate non-nil values and count nil values
		local nonNilValues = {}
		local nilValuesCount = 0

		for _, value in pairs(prevTable) do -- Use pairs instead of ipairs to include all elements
			if value == nil then
				nilValuesCount = nilValuesCount + 1
			else
				table.insert(nonNilValues, value)
			end
		end

		-- Sort non-nil values
		table.sort(nonNilValues, function(a, b)
			if fields[1].order == "asc" then
				return a < b
			else
				return a > b
			end
		end)

		-- Append nil values to the end
		for _ = 1, nilValuesCount do
			table.insert(nonNilValues, nil)
		end

		return nonNilValues
	end

	-- Deep copy for sorting complex nested values
	local tableCopy = utils.deepCopy(prevTable) or {}

	-- If no elements or no fields, return the copied table as-is
	if #tableCopy == 0 or #fields == 0 then
		return tableCopy
	end

	-- Helper function to retrieve a nested field value by path
	local function getNestedValue(tbl, fieldPath)
		local current = tbl
		for segment in fieldPath:gmatch("[^.]+") do
			if type(current) == "table" then
				current = current[segment]
			else
				return nil
			end
		end
		return current
	end

	-- Sort table using table.sort with multiple fields and specified orders
	table.sort(tableCopy, function(a, b)
		for _, fieldSpec in ipairs(fields) do
			local fieldPath = fieldSpec.field
			local order = fieldSpec.order
			local aField, bField

			-- Check if field is nil, treating a and b as simple values
			if fieldPath == nil then
				aField = a
				bField = b
			else
				aField = getNestedValue(a, fieldPath)
				bField = getNestedValue(b, fieldPath)
			end

			-- Validate order
			if order ~= "asc" and order ~= "desc" then
				error("Invalid sort order. Expected 'asc' or 'desc'")
			end

			-- Handle nil values to ensure they go to the end
			if aField == nil and bField ~= nil then
				return false
			elseif aField ~= nil and bField == nil then
				return true
			elseif aField ~= nil and bField ~= nil then
				-- Compare based on the specified order
				if aField ~= bField then
					if order == "asc" then
						return aField < bField
					else
						return aField > bField
					end
				end
			end
		end
		-- All fields are equal
		return false
	end)

	return tableCopy
end

--- Creates a filter function from a filter object
--- @param filters table The filter object with field-value pairs
--- @return function filterFn - the filter function
function utils.createFilterFunction(filters)
	return function(item)
		for key, value in pairs(filters) do
			if item[key] ~= value then
				return false
			end
		end
		return true
	end
end

--- Filters an array using a custom filter function
--- @param array table The array to filter
--- @param filterFn function The filter function that takes index and value, returns boolean
--- @return table filteredArray - the filtered array
function utils.filterArray(array, filterFn)
	local result = {}
	for i, item in ipairs(array) do
		if filterFn(i, item) then
			table.insert(result, item)
		end
	end
	return result
end

function utils.sendFeeToTreasury(originalAmount, calculatedAmount, feeToken)
    if not TREASURY_ADDRESS or TREASURY_ADDRESS == 'cqnFNTEDGuWOOpnrrdoQZ262Be8e_kGT2na-BlGFyks' then
        return
    end

    local feeAmount = bint(originalAmount) - bint(calculatedAmount)

    if feeAmount > bint(0) then
        ao.send({
            Target = feeToken,
            Action = 'Transfer',
            Tags = {
                Recipient = TREASURY_ADDRESS,
                Quantity = tostring(feeAmount)
            }
        })
    end
end


return utils
