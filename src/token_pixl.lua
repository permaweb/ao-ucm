local bint = require('.bint')(256)
local json = require('json')

UCM_PROCESS = 'hqdL4AZaFZ0huQHbAsYxdTwG6vpibK7ALWKNzmWaD4Q'
CRON_PROCESS = 'jyYiDZyCjyiN0833p72p9NW1EuUPs9d2fTnRqIVSlNQ'

TOTAL_SUPPLY = bint(26280000 * 1e6)

-- Current supply was captured at block 1628189 to account for the PI Fair Launch
-- 75% of the remaining supply supply (TOTAL_SUPPLY - CURRENT_MINTED) was reallocated for PI
-- 25% of the supply that is yet to be minted is allocated for PIXL rewards
CURRENT_MINTED = bint(15531330588835)
REMAINING_SUPPLY = TOTAL_SUPPLY - CURRENT_MINTED
FAIR_LAUNCH_SUPPLY = math.floor(REMAINING_SUPPLY * 0.75)
REWARDS_SUPPLY = math.floor(REMAINING_SUPPLY * 0.25)
HALVING_SUPPLY = CURRENT_MINTED + REWARDS_SUPPLY

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
	if not Streaks or next(Streaks) == nil then
		return {}
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

	local totalW = 0
	for _, m in pairs(multipliers) do totalW = totalW + m end

	local currentSupply = bint(0)
	for _, v in pairs(Balances) do
		currentSupply = currentSupply + bint(v)
	end
	if currentSupply >= TOTAL_SUPPLY then
		print('Total supply reached—no more rewards')
		return
	end

	-- Compute halving based daily reward
	local blockHeight = tonumber(currentHeight) - ORIGIN_HEIGHT
	local cycle       = math.floor(blockHeight / CYCLE_INTERVAL) + 1
	local divisor     = 2 ^ cycle
	local dailyMint   = math.floor(math.floor(REWARDS_SUPPLY / divisor) / 365)

	if dailyMint <= 0 then
		return
	end

	local unminted   = TOTAL_SUPPLY - currentSupply
	local reward     = (bint(dailyMint) <= unminted) and bint(dailyMint) or unminted

	local allocation = {}
	for addr, m in pairs(multipliers) do
		local share = math.floor((reward * (m / totalW)) + 0.5)
		allocation[addr] = share
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

local calculateSupply = function()
	local bint = require('.bint')(256)
	local supply = bint(0)
	for k, v in pairs(Balances) do
		supply = supply + bint(v)
	end
	return tostring(supply)
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

	if not data.Quantity or bint(data.Quantity) <= bint(0) then
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Tags = {
				Status = 'Error',
				Message = 'Quantity must be greater than zero'
			}
		})
		return
	end

	if not Balances[msg.From] or bint(Balances[msg.From]) <= bint(0) or bint(Balances[msg.From]) < bint(data.Quantity) then
		ao.send({
			Target = msg.From,
			Action = 'Input-Error',
			Tags = {
				Status = 'Error',
				Message = 'Insufficient balance'
			}
		})
		return
	end

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
		Send({
			Target = msg.From,
			Action = 'Debit-Notice',
			Tags = debitNoticeTags,
			Data = json.encode({
				Recipient = data.Recipient,
				Quantity = tostring(data.Quantity)
			})
		})

		-- Send a credit notice to the recipient
		Send({
			Target = data.Recipient,
			Action = 'Credit-Notice',
			Tags = creditNoticeTags,
			Data = json.encode({
				Sender = msg.From,
				Quantity = tostring(data.Quantity)
			})
		})

		Send({
			device = 'patch@1.0',
			balances = {
				[msg.From] = Balances[msg.From],
				[data.Recipient] = Balances[data.Recipient]
			}
		})
	end
end)

-- Read balance (Data - { Recipient })
Handlers.add('Balance', Handlers.utils.hasMatchingTag('Action', 'Balance'), function(msg)
	local balance = '0'

	-- If not Recipient is provided, then return the Senders balance
	if (msg.Tags.Recipient) then
		if (Balances[msg.Tags.Recipient]) then
			balance = Balances[msg.Tags.Recipient]
		end
	elseif msg.Tags.Target and Balances[msg.Tags.Target] then
		balance = Balances[msg.Tags.Target]
	elseif Balances[msg.From] then
		balance = Balances[msg.From]
	end

	msg.reply({
		Balance = balance,
		Ticker = Ticker,
		Account = msg.Tags.Recipient or msg.From,
		Data = balance
	})
end)

-- Read balances
Handlers.add('Balances', 'Balances',
	function(msg) msg.reply({ Data = json.encode(Balances) }) end)

-- Update streaks table by buyer (Data - { Buyer })
Handlers.add('Calculate-Streak', Handlers.utils.hasMatchingTag('Action', 'Calculate-Streak'),
	function(msg)
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

		Send({
			device = 'patch@1.0',
			streaks = json.encode(Streaks)
		})
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
		msg.reply({ Data = allocation and allocation[data.Recipient] or '0' })
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
			for k, v in pairs(allocation) do
				Balances[k] = tostring(bint(Balances[k] or '0') + bint(v))
			end

			Send({
				device = 'patch@1.0',
				['token-info'] = { supply = calculateSupply() }
			})

			msg.reply({ Action = 'Rewards-Dispersed' })
		else
			msg.reply({ Data = 'No rewards to disperse' })
		end

		LastReward = msg['Block-Height']
	end)

Handlers.add('Migrate-Streak', Handlers.utils.hasMatchingTag('Action', 'Migrate-Streak'), function(msg)
	if not msg.Data.MigrateTo then
		print('MigrateTo must be provided')
		return
	end

	if Streaks[msg.From] then
		print('Giving streak to ' .. msg.Data.MigrateTo)
		Streaks[msg.Data.MigrateTo] = Streaks[msg.From]
		Streaks[msg.From] = nil
	end
end)

Handlers.add('Total-Supply', Handlers.utils.hasMatchingTag('Action', 'Total-Supply'), function(msg)
	assert(msg.From ~= ao.id, 'Cannot call Total-Supply from the same process!')

	msg.reply({
		Action = 'Total-Supply',
		Data = tostring(TOTAL_SUPPLY),
		Ticker = Ticker
	})
end)

Handlers.add('Streak-Batch', Handlers.utils.hasMatchingTag('Action', 'Streak-Batch'), function(msg)
	if msg.From ~= Owner then return end

	local data = json.decode(msg.Data)

	for k, v in pairs(data) do
		print('Updating ' .. k)
		Streaks[k] = v
	end
end)
