local json = require('json')
local bint = require('.bint')(256)

UCM_PROCESS = 'fzRGvSW2oSop9xGLxs5mcaRtCbrbug8imI_uRZHKdiU'

-- Streaks { [Profile]: { Days, LastHeight } }

if not Streaks then Streaks = {} end

local function checkValidAddress(address)
	if not address or type(address) ~= 'string' then
		return false
	end

	return string.match(address, "^[%w%-_]+$") ~= nil and #address == 43
end

local function decodeMessageData(data)
	local status, decodedData = pcall(json.decode, data)

	if not status or type(decodedData) ~= 'table' then
		return false, nil
	end

	return true, decodedData
end

Handlers.add('Info', Handlers.utils.hasMatchingTag('Action', 'Info'),
	function(msg)
		ao.send({
			Target = msg.From,
			Action = 'Read-Success',
			Data = json.encode({
				Streaks = Streaks
			})
		})
	end)

-- Add credit notice to the deposits table (Data - { Buyer })
Handlers.add('Calculate-Streak', Handlers.utils.hasMatchingTag('Action', 'Calculate-Streak'),
	function(msg)
		if msg.From ~= UCM_PROCESS then
			return
		end

		local decodeCheck, data = decodeMessageData(msg.Data)

		if decodeCheck and data then
			-- Check if all required fields are present
			if not data.Buyer then
				ao.send({
					Target = msg.From,
					Action = 'Input-Error',
					Tags = {
						Status = 'Error',
						Message =
						'Invalid arguments, required { Buyer }'
					}
				})
				return
			end

			-- Check if buyer is a valid address
			if not checkValidAddress(data.Buyer) then
				return
			end

			if not Streaks[data.Buyer] then
				Streaks[data.Buyer] = {
					days = 1,
					lastHeight = msg['Block-Height']
				}
			else
				local heightDiff = tonumber(msg['Block-Height']) - tonumber(Streaks[data.Buyer].lastHeight)

				if heightDiff > 720 and heightDiff <= 1440 then
					Streaks[data.Buyer] = {
						days = tonumber(Streaks[data.Buyer].days) + 1,
						lastHeight = msg['Block-Height']
					}
				end
				if heightDiff > 1440 then
					Streaks[data.Buyer] = {
						days = 1,
						lastHeight = msg['Block-Height']
					}
				end
			end
		else
			return
		end
	end)