
--[[
    Order Book indexing process, used by
    ucm apps to discover a ucm for a given 
    process
]]

if not OrderBooks then OrderBooks = {} end
DEFAULT_ORDERBOOK = 'rQYLK3Dzqhl-t6_BRqZ7yMLZmtvLKxkyIUQlzW8xAXg'

Handlers.add('Index', Handlers.utils.hasMatchingTag('Action', 'Index'),
	function(msg)
    if msg.From ~= msg.Owner then
      print('A Process can only index itself.')
      return
    end

    OrderBooks[msg.From] = msg.Tags['Order-Book']
    print('Process indexed.')
	end
)

Handlers.add('Search', Handlers.utils.hasMatchingTag('Action', 'Search'),
	function(msg)
    local ob = OrderBooks[msg.From]
    if ob == nil then 
      print(DEFAULT_ORDERBOOK)
    else
      print(OrderBooks[msg.From])
    end
	end
)
