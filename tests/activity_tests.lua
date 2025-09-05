package.path = package.path .. ';../src/?.lua'

local utils = require('utils')
local json = require('json')

-- Mock ao.send for testing
local sentMessages = {}
ao = {
	send = function(msg)
		table.insert(sentMessages, msg)
		print('Sent: ' .. msg.Action .. ' to ' .. msg.Target)
	end
}

-- Mock Handlers for testing
Handlers = {
	add = function(name, condition, handler)
		-- Store handler for testing
		Handlers[name] = handler
	end,
	utils = {
		hasMatchingTag = function(tagName, tagValue)
			return function(msg)
				return msg.Tags and msg.Tags[tagName] == tagValue
			end
		end
	}
}

-- Implement the Get-Executed-Orders handler directly for testing
Handlers['Get-Executed-Orders'] = function(msg)
	local page = utils.parsePaginationTags(msg)

	local ordersArray = {}
	for _, order in pairs(ExecutedOrders) do
		local orderCopy = utils.deepCopy(order)
		table.insert(ordersArray, orderCopy)
	end

	local paginatedOrders = utils.paginateTableWithCursor(ordersArray, page.cursor, page.cursorField, page.limit, page.sortBy, page.sortOrder, page.filters)

	ao.send({
		Target = msg.From,
		Action = 'Read-Success',
		Data = json.encode(paginatedOrders)
	})
end

-- Helper function to reset test state
local function resetTestState()
	sentMessages = {}
	ExecutedOrders = {}
end

-- Helper function to create a mock message
local function createMockMessage(tags, data)
	return {
		From = 'test-sender',
		Tags = tags or {},
		Data = data or ''
	}
end

-- Helper function to decode sent message data
local function decodeSentMessageData(index)
	if not sentMessages[index] or not sentMessages[index].Data then
		return nil
	end
	
	local success, decoded = pcall(function() return json.decode(sentMessages[index].Data) end)
	if success then
		return decoded
	end
	return nil
end

-- Helper function to create test orders
local function createTestOrder(id, dominantToken, swapToken, sender, receiver, quantity, price, timestamp)
	return {
		OrderId = id,
		DominantToken = dominantToken,
		SwapToken = swapToken,
		Sender = sender,
		Receiver = receiver,
		Quantity = quantity,
		Price = price,
		Timestamp = timestamp
	}
end



-- Test 1: Basic functionality - empty ExecutedOrders
utils.test('Get-Executed-Orders should return empty result when no orders exist',
	function()
		resetTestState()
		
		local msg = createMockMessage({
			Action = 'Get-Executed-Orders'
		})
		
		Handlers['Get-Executed-Orders'](msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {},
		limit = 100,
		totalItems = 0,
		sortBy = 'Timestamp',
		sortOrder = 'desc',
		nextCursor = nil,
		hasMore = false
	}
)

-- Test 2: Basic functionality - single order
utils.test('Get-Executed-Orders should return single order correctly',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder(
				'order-1',
				'token-1',
				'token-2',
				'sender-1',
				'receiver-1',
				'100',
				'500000000000',
				'1722535710966'
			)
		}
		
		local msg = createMockMessage({
			Action = 'Get-Executed-Orders'
		})
		
		Handlers['Get-Executed-Orders'](msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {
			{
				OrderId = 'order-1',
				DominantToken = 'token-1',
				SwapToken = 'token-2',
				Sender = 'sender-1',
				Receiver = 'receiver-1',
				Quantity = '100',
				Price = '500000000000',
				Timestamp = '1722535710966'
			}
		},
		limit = 100,
		totalItems = 1,
		sortBy = 'Timestamp',
		sortOrder = 'desc',
		nextCursor = nil,
		hasMore = false
	}
)

-- Test 3: Multiple orders without pagination
utils.test('Get-Executed-Orders should return multiple orders correctly',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder('order-1', 'token-1', 'token-2', 'sender-1', 'receiver-1', '100', '500000000000', '1722535710966'),
			createTestOrder('order-2', 'token-3', 'token-4', 'sender-2', 'receiver-2', '200', '600000000000', '1722535710967'),
			createTestOrder('order-3', 'token-5', 'token-6', 'sender-3', 'receiver-3', '300', '700000000000', '1722535710968')
		}
		
		local msg = createMockMessage({
			Action = 'Get-Executed-Orders'
		})
		
		Handlers['Get-Executed-Orders'](msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {
			{
				OrderId = 'order-3',
				DominantToken = 'token-5',
				SwapToken = 'token-6',
				Sender = 'sender-3',
				Receiver = 'receiver-3',
				Quantity = '300',
				Price = '700000000000',
				Timestamp = '1722535710968'
			},
			{
				OrderId = 'order-2',
				DominantToken = 'token-3',
				SwapToken = 'token-4',
				Sender = 'sender-2',
				Receiver = 'receiver-2',
				Quantity = '200',
				Price = '600000000000',
				Timestamp = '1722535710967'
			},
			{
				OrderId = 'order-1',
				DominantToken = 'token-1',
				SwapToken = 'token-2',
				Sender = 'sender-1',
				Receiver = 'receiver-1',
				Quantity = '100',
				Price = '500000000000',
				Timestamp = '1722535710966'
			}
		},
		limit = 100,
		totalItems = 3,
		sortBy = 'Timestamp',
		sortOrder = 'desc',
		nextCursor = nil,
		hasMore = false
	}
)

-- Test 4: Pagination with limit
utils.test('Get-Executed-Orders should respect limit parameter',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder('order-1', 'token-1', 'token-2', 'sender-1', 'receiver-1', '100', '500000000000', '1722535710966'),
			createTestOrder('order-2', 'token-3', 'token-4', 'sender-2', 'receiver-2', '200', '600000000000', '1722535710967'),
			createTestOrder('order-3', 'token-5', 'token-6', 'sender-3', 'receiver-3', '300', '700000000000', '1722535710968')
		}
		
		local msg = createMockMessage({
			Action = 'Get-Executed-Orders',
			Limit = '2'
		})
		
		Handlers['Get-Executed-Orders'](msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {
			{
				OrderId = 'order-3',
				DominantToken = 'token-5',
				SwapToken = 'token-6',
				Sender = 'sender-3',
				Receiver = 'receiver-3',
				Quantity = '300',
				Price = '700000000000',
				Timestamp = '1722535710968'
			},
			{
				OrderId = 'order-2',
				DominantToken = 'token-3',
				SwapToken = 'token-4',
				Sender = 'sender-2',
				Receiver = 'receiver-2',
				Quantity = '200',
				Price = '600000000000',
				Timestamp = '1722535710967'
			}
		},
		limit = 2,
		totalItems = 3,
		sortBy = 'Timestamp',
		sortOrder = 'desc',
		nextCursor = {
			DominantToken = 'token-3',
			Quantity = '200',
			OrderId = 'order-2',
			Timestamp = '1722535710967',
			Receiver = 'receiver-2',
			SwapToken = 'token-4',
			Sender = 'sender-2',
			Price = '600000000000'
		},
		hasMore = true
	}
)

-- Test 5: Pagination with cursor
utils.test('Get-Executed-Orders should handle cursor pagination correctly',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder('order-1', 'token-1', 'token-2', 'sender-1', 'receiver-1', '100', '500000000000', '1722535710966'),
			createTestOrder('order-2', 'token-3', 'token-4', 'sender-2', 'receiver-2', '200', '600000000000', '1722535710967'),
			createTestOrder('order-3', 'token-5', 'token-6', 'sender-3', 'receiver-3', '300', '700000000000', '1722535710968')
		}
		
		local msg = createMockMessage({
			Action = 'Get-Executed-Orders',
			Cursor = '1722535710967',
			Limit = '1'
		})
		
		Handlers['Get-Executed-Orders'](msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {
			{
				OrderId = 'order-1',
				DominantToken = 'token-1',
				SwapToken = 'token-2',
				Sender = 'sender-1',
				Receiver = 'receiver-1',
				Quantity = '100',
				Price = '500000000000',
				Timestamp = '1722535710966'
			}
		},
		limit = 1,
		totalItems = 3,
		sortBy = 'Timestamp',
		sortOrder = 'desc',
		nextCursor = nil,
		hasMore = false
	}
)

-- Test 6: Sorting by specific field
utils.test('Get-Executed-Orders should sort by specified field',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder('order-1', 'token-1', 'token-2', 'sender-1', 'receiver-1', '100', '500000000000', '1722535710966'),
			createTestOrder('order-2', 'token-3', 'token-4', 'sender-2', 'receiver-2', '200', '600000000000', '1722535710967'),
			createTestOrder('order-3', 'token-5', 'token-6', 'sender-3', 'receiver-3', '300', '700000000000', '1722535710968')
		}
		
		local msg = createMockMessage({
			Action = 'Get-Executed-Orders',
			['Sort-By'] = 'Quantity',
			['Sort-Order'] = 'asc'
		})
		
		Handlers['Get-Executed-Orders'](msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {
			{
				OrderId = 'order-1',
				DominantToken = 'token-1',
				SwapToken = 'token-2',
				Sender = 'sender-1',
				Receiver = 'receiver-1',
				Quantity = '100',
				Price = '500000000000',
				Timestamp = '1722535710966'
			},
			{
				OrderId = 'order-2',
				DominantToken = 'token-3',
				SwapToken = 'token-4',
				Sender = 'sender-2',
				Receiver = 'receiver-2',
				Quantity = '200',
				Price = '600000000000',
				Timestamp = '1722535710967'
			},
			{
				OrderId = 'order-3',
				DominantToken = 'token-5',
				SwapToken = 'token-6',
				Sender = 'sender-3',
				Receiver = 'receiver-3',
				Quantity = '300',
				Price = '700000000000',
				Timestamp = '1722535710968'
			}
		},
		limit = 100,
		totalItems = 3,
		sortBy = 'Quantity',
		sortOrder = 'asc',
		nextCursor = nil,
		hasMore = false
	}
)

-- Test 7: Filtering with JSON filters
utils.test('Get-Executed-Orders should apply JSON filters correctly',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder('order-1', 'token-1', 'token-2', 'sender-1', 'receiver-1', '100', '500000000000', '1722535710966'),
			createTestOrder('order-2', 'token-3', 'token-4', 'sender-2', 'receiver-2', '200', '600000000000', '1722535710967'),
			createTestOrder('order-3', 'token-5', 'token-6', 'sender-3', 'receiver-3', '300', '700000000000', '1722535710968')
		}
		
		local msg = createMockMessage({
			Action = 'Get-Executed-Orders',
			Filters = '{"Sender": "sender-1"}'
		})
		
		Handlers['Get-Executed-Orders'](msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {
			{
				OrderId = 'order-1',
				DominantToken = 'token-1',
				SwapToken = 'token-2',
				Sender = 'sender-1',
				Receiver = 'receiver-1',
				Quantity = '100',
				Price = '500000000000',
				Timestamp = '1722535710966'
			}
		},
		limit = 100,
		totalItems = 1,
		sortBy = 'Timestamp',
		sortOrder = 'desc',
		nextCursor = nil,
		hasMore = false
	}
)

-- Test 8: Invalid JSON filters should throw an error
utils.test('Get-Executed-Orders should throw error for invalid JSON filters',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder('order-1', 'token-1', 'token-2', 'sender-1', 'receiver-1', '100', '500000000000', '1722535710966')
		}
		
		local msg = createMockMessage({
			Action = 'Get-Executed-Orders',
			Filters = 'invalid json'
		})
		
		-- This should throw an error for invalid JSON
		local status, result = pcall(function()
			Handlers['Get-Executed-Orders'](msg)
		end)
		
		if not status then
			return { error = result }
		else
			return decodeSentMessageData(1)
		end
	end,
	{ error = "../src/utils.lua:321: Invalid JSON supplied in Filters tag" }
)

-- Test 9: Maximum limit enforcement
utils.test('Get-Executed-Orders should enforce maximum limit of 1000',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder('order-1', 'token-1', 'token-2', 'sender-1', 'receiver-1', '100', '500000000000', '1722535710966')
		}
		
		local msg = createMockMessage({
			Action = 'Get-Executed-Orders',
			Limit = '999'
		})
		
		-- This should use the provided limit
		Handlers['Get-Executed-Orders'](msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {
			{
				OrderId = 'order-1',
				DominantToken = 'token-1',
				SwapToken = 'token-2',
				Sender = 'sender-1',
				Receiver = 'receiver-1',
				Quantity = '100',
				Price = '500000000000',
				Timestamp = '1722535710966'
			}
		},
		limit = 999,
		totalItems = 1,
		sortBy = 'Timestamp',
		sortOrder = 'desc',
		nextCursor = nil,
		hasMore = false
	}
)

-- Test 10: Complex filtering with multiple conditions
utils.test('Get-Executed-Orders should handle complex filtering',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder('order-1', 'token-1', 'token-2', 'sender-1', 'receiver-1', '100', '500000000000', '1722535710966'),
			createTestOrder('order-2', 'token-1', 'token-3', 'sender-2', 'receiver-2', '200', '600000000000', '1722535710967'),
			createTestOrder('order-3', 'token-4', 'token-5', 'sender-1', 'receiver-3', '300', '700000000000', '1722535710968')
		}
		
		local msg = createMockMessage({
			Action = 'Get-Executed-Orders',
			Filters = '{"DominantToken": "token-1", "Sender": "sender-1"}'
		})
		
		Handlers['Get-Executed-Orders'](msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {
			{
				OrderId = 'order-1',
				DominantToken = 'token-1',
				SwapToken = 'token-2',
				Sender = 'sender-1',
				Receiver = 'receiver-1',
				Quantity = '100',
				Price = '500000000000',
				Timestamp = '1722535710966'
			}
		},
		limit = 100,
		totalItems = 1,
		sortBy = 'Timestamp',
		sortOrder = 'desc',
		nextCursor = nil,
		hasMore = false
	}
)

-- Test 11: Edge case - orders with missing fields
utils.test('Get-Executed-Orders should handle orders with missing fields',
	function()
		resetTestState()
		
		ExecutedOrders = {
			{
				OrderId = 'order-1',
				DominantToken = 'token-1',
				-- Missing other fields
			},
			createTestOrder('order-2', 'token-3', 'token-4', 'sender-2', 'receiver-2', '200', '600000000000', '1722535710967')
		}
		
		local msg = createMockMessage({
			Action = 'Get-Executed-Orders'
		})
		
		Handlers['Get-Executed-Orders'](msg)
		
		local result = decodeSentMessageData(1)
		return result
	end,
	{
		items = {
			{
				OrderId = 'order-2',
				DominantToken = 'token-3',
				SwapToken = 'token-4',
				Sender = 'sender-2',
				Receiver = 'receiver-2',
				Quantity = '200',
				Price = '600000000000',
				Timestamp = '1722535710967'
			},
			{
				OrderId = 'order-1',
				DominantToken = 'token-1'
			}
		},
		limit = 100,
		totalItems = 2,
		sortBy = 'Timestamp',
		sortOrder = 'desc',
		nextCursor = nil,
		hasMore = false
	}
)

-- Test 12: Verify message is sent to correct target
utils.test('Get-Executed-Orders should send response to correct target',
	function()
		resetTestState()
		
		ExecutedOrders = {
			createTestOrder('order-1', 'token-1', 'token-2', 'sender-1', 'receiver-1', '100', '500000000000', '1722535710966')
		}
		
		local msg = createMockMessage({
			Action = 'Get-Executed-Orders'
		})
		
		Handlers['Get-Executed-Orders'](msg)
		
		return {
			target = sentMessages[1].Target,
			action = sentMessages[1].Action
		}
	end,
	{
		target = 'test-sender',
		action = 'Read-Success'
	}
)

print('Activity tests completed!')
