local bint = require('.bint')(256)
local json = require('json')

UCM_PROCESS = 'hqdL4AZaFZ0huQHbAsYxdTwG6vpibK7ALWKNzmWaD4Q'
CRON_PROCESS = 'jyYiDZyCjyiN0833p72p9NW1EuUPs9d2fTnRqIVSlNQ'

TOTAL_SUPPLY = bint(26280000 * 1e6)
HALVING_SUPPLY = TOTAL_SUPPLY * 0.9
ORIGIN_HEIGHT = 1232228
DAY_INTERVAL = 720
CYCLE_INTERVAL = DAY_INTERVAL * 365

if Name ~= 'PIXL Token' then Name = 'PIXL Token' end
if Ticker ~= 'PIXL' then Ticker = 'PIXL' end
if not Balances then Balances = {} end
if Denomination ~= 6 then Denomination = 6 end
if not Logo then Logo = 'czR2tJmSr7upPpReXu6IuOc2H7RuHRRAhI7DXAUlszU' end
if not LastReward then LastReward = 0 end

-- Streaks { [Profile]: { Days, LastHeight } }
if not Streaks then Streaks = {} end

local function checkValidAddress(address)
	if not address or type(address) ~= 'string' then
		return false
	end

	return string.match(address, '^[%w%-_]+$') ~= nil and #address == 43
end

local function checkValidAmount(data)
	return bint(data) > bint(0)
end

local function getAllocation(currentHeight)
	if next(Streaks) == nil then
		return nil
	end

	local reward = 0
	local current = 0

	for _, v in pairs(Balances) do
		current = current + v
	end

	if current >= HALVING_SUPPLY then
		if not Balances[Owner] then
			Balances[Owner] = '0'
		end
	end

	local blockHeight = tonumber(currentHeight) - ORIGIN_HEIGHT
	local currentCycle = math.floor(blockHeight / CYCLE_INTERVAL) + 1
	local divisor = 2 ^ currentCycle

	reward = math.floor(math.floor(HALVING_SUPPLY / divisor) / 365)

	if reward <= 0 then
		return nil
	end

	local multipliers = {}

	for k, v in pairs(Streaks) do
		if v.days > 0 and v.days < 31 then
			local multiplier = v.days - 1
			multipliers[k] = 1 + multiplier * 0.1
		elseif v.days >= 31 then
			local multiplier = 30
			multipliers[k] = 1 + multiplier * 0.1
		end

		local heightDiff = tonumber(currentHeight) - tonumber(v.lastHeight)

		if heightDiff > (DAY_INTERVAL * 2) then
			Streaks[k] = nil
		end
	end

	-- Calculate the total balance
	local total = 0
	for _, v in pairs(multipliers) do
		if v > 0 then
			total = total + v
		end
	end

	-- Initialize allocation table
	local allocation = {}

	-- Calculate the allocation for each balance
	for address, multiplier in pairs(multipliers) do
		if multiplier >= 1 then
			local pct = (multiplier / total) * 100
			local amount = math.floor(reward * (pct / 100) + 0.5) -- Round to the nearest integer

			allocation[address] = (allocation[address] or 0) + amount
		end
	end

	return allocation
end

function Trusted(msg)
	local mu = 'fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY'
	if msg.Owner == mu then
		return false
	end
	if msg.From == msg.Owner then
		return false
	end
	return true
end

Handlers.prepend('qualify message',
	Trusted,
	function(msg)
		print('This Msg is not trusted!')
	end
)

local function patchReply(msg)
	if not msg.reply then
		msg.reply = function(replyMsg)
			replyMsg.Target = msg['Reply-To'] or (replyMsg.Target or msg.From)
			replyMsg['X-Reference'] = msg['X-Reference'] or msg.Reference or ''
			replyMsg['X-Origin'] = msg['X-Origin'] or ''

			return ao.send(replyMsg)
		end
	end
end

Handlers.prepend('_patch_reply', function(msg) return 'continue' end, patchReply)

-- Read process state
Handlers.add('Info', Handlers.utils.hasMatchingTag('Action', 'Info'),
	function(msg)
		msg.reply({
			Name = Name,
			Ticker = Ticker,
			Logo = Logo,
			Denomination = tostring(Denomination)
		})
	end)

-- Get streaks table
Handlers.add('Get-Streaks', Handlers.utils.hasMatchingTag('Action', 'Get-Streaks'),
	function(msg)
		msg.reply({
			Data = json.encode({ Streaks = Streaks })
		})
	end)

-- Transfer balance to recipient (Data - { Recipient, Quantity })
Handlers.add('Transfer', Handlers.utils.hasMatchingTag('Action', 'Transfer'), function(msg)
	local data = {
		Recipient = msg.Tags.Recipient,
		Quantity = msg.Tags.Quantity
	}

	if checkValidAddress(data.Recipient) and checkValidAmount(data.Quantity) and bint(data.Quantity) <= bint(Balances[msg.From]) then
		-- Transfer is valid, calculate balances
		if not Balances[data.Recipient] then
			Balances[data.Recipient] = '0'
		end

		Balances[msg.From] = tostring(bint(Balances[msg.From]) - bint(data.Quantity))
		Balances[data.Recipient] = tostring(bint(Balances[data.Recipient]) + bint(data.Quantity))

		-- If new balance zeroes out then remove it from the table
		if bint(Balances[msg.From]) <= 0 then
			Balances[msg.From] = nil
		end
		if bint(Balances[data.Recipient]) <= 0 then
			Balances[data.Recipient] = nil
		end

		local debitNoticeTags = {
			Status = 'Success',
			Message = 'Balance transferred, debit notice issued',
			Recipient = msg.Tags.Recipient,
			Quantity = msg.Tags.Quantity,
		}

		local creditNoticeTags = {
			Status = 'Success',
			Message = 'Balance transferred, credit notice issued',
			Sender = msg.From,
			Quantity = msg.Tags.Quantity,
		}

		for tagName, tagValue in pairs(msg) do
			if string.sub(tagName, 1, 2) == 'X-' then
				debitNoticeTags[tagName] = tagValue
				creditNoticeTags[tagName] = tagValue
			end
		end

		-- Send a debit notice to the sender
		msg.reply({
			Target = msg.From,
			Action = 'Debit-Notice',
			Tags = debitNoticeTags,
			Data = json.encode({
				Recipient = data.Recipient,
				Quantity = tostring(data.Quantity)
			})
		})

		-- Send a credit notice to the recipient
		msg.reply({
			Target = data.Recipient,
			Action = 'Credit-Notice',
			Tags = creditNoticeTags,
			Data = json.encode({
				Sender = msg.From,
				Quantity = tostring(data.Quantity)
			})
		})
	end
end)

-- Read balance (Data - { Recipient })
Handlers.add('Balance', Handlers.utils.hasMatchingTag('Action', 'Balance'), function(msg)
	local data = {
		Recipient = msg.Tags.Recipient
	}

	-- Check if target is present
	if not data.Recipient then
		ao.send({ Target = msg.From, Action = 'Input-Error', Tags = { Status = 'Error', Message = 'Invalid arguments, required { Recipient }' } })
		return
	end

	-- Check if target is a valid address
	if not checkValidAddress(data.Recipient) then
		ao.send({ Target = msg.From, Action = 'Validation-Error', Tags = { Status = 'Error', Message = 'Recipient is not a valid address' } })
		return
	end

	local balance = Balances[data.Recipient] or '0'

	msg.reply({
		Balance = balance,
		Ticker = Ticker,
		Account = data.Recipient or msg.From,
		Data = balance
	})
end)

-- Read balances
Handlers.add('Balances', 'Balances',
	function(msg) msg.reply({ Data = json.encode(Balances) }) end)

-- Update streaks table by buyer (Data - { Buyer })
Handlers.add('Calculate-Streak', Handlers.utils.hasMatchingTag('Action', 'Calculate-Streak'),
	function(msg)
		if msg.From ~= UCM_PROCESS then
			return
		end

		local data = {
			Buyer = msg.Tags.Buyer
		}

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

		if not checkValidAddress(data.Buyer) then
			return
		end

		if not Streaks[data.Buyer] or Streaks[data.Buyer].days <= 0 then
			Streaks[data.Buyer] = {
				days = 1,
				lastHeight = msg['Block-Height']
			}
		else
			local heightDiff = tonumber(msg['Block-Height']) - tonumber(Streaks[data.Buyer].lastHeight)

			if heightDiff > DAY_INTERVAL and heightDiff <= (DAY_INTERVAL * 2) then
				Streaks[data.Buyer] = {
					days = tonumber(Streaks[data.Buyer].days) + 1,
					lastHeight = msg['Block-Height']
				}
			end
			if heightDiff > (DAY_INTERVAL * 2) then
				Streaks[data.Buyer] = {
					days = 0,
					lastHeight = msg['Block-Height']
				}
			end
		end
	end)

-- Trigger rewards dispersement
Handlers.add('Read-Current-Rewards', Handlers.utils.hasMatchingTag('Action', 'Read-Current-Rewards'),
	function(msg)
		local data = {
			Recipient = msg.Tags.Recipient
		}

		-- Check if target is present
		if not data.Recipient then
			ao.send({ Target = msg.From, Action = 'Input-Error', Tags = { Status = 'Error', Message = 'Invalid arguments, required { Recipient }' } })
			return
		end

		-- Check if target is a valid address
		if not checkValidAddress(data.Recipient) then
			ao.send({ Target = msg.From, Action = 'Validation-Error', Tags = { Status = 'Error', Message = 'Recipient is not a valid address' } })
			return
		end

		-- Initialize allocation table
		local allocation = getAllocation(msg['Block-Height'])

		if allocation and allocation[data.Recipient] then
			msg.reply({ Data = allocation[data.Recipient] })
		end
	end)

-- Trigger rewards dispersement
Handlers.add('Run-Rewards', Handlers.utils.hasMatchingTag('Action', 'Run-Rewards'),
	function(msg)
		if msg.From ~= CRON_PROCESS then
			msg.reply({ Action = 'Unauthorized' })
			return
		end

		if (tonumber(msg['Block-Height']) - LastReward) < DAY_INTERVAL then
			msg.reply({ Action = 'Invalid-Reward-Interval' })
			return
		end

		-- Initialize allocation table
		local allocation = getAllocation(msg['Block-Height'])

		if allocation then
			-- Update balances
			for k, v in pairs(allocation) do
				if not Balances[k] then
					Balances[k] = '0'
				end
				Balances[k] = tostring(bint(Balances[k] + bint(v)))
			end

			LastReward = msg['Block-Height']
		end

		msg.reply({ Action = 'Rewards-Dispersed' })
	end)

Handlers.add('Total-Supply', Handlers.utils.hasMatchingTag('Action', 'Total-Supply'), function(msg)
	assert(msg.From ~= ao.id, 'Cannot call Total-Supply from the same process!')

	msg.reply({
		Action = 'Total-Supply',
		Data = tostring(TOTAL_SUPPLY),
		Ticker = Ticker
	})
end)
