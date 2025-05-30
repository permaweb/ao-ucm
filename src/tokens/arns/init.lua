-- arns-token-1.lua
-- ao process id: V3oans_J8Iip3XXZcXTF4X0AbmiL3BpvFEoeCfVXVs4
local json = require('json')

Name = Name or "Arweave Name Token"
Ticker = Ticker or "ANT"
Description = Description or "This is an Arweave Name Token."
Keywords = Keywords or {}
Logo = Logo or ""
Denomination = Denomination or 0
TotalSupply = TotalSupply or 1
Owner = Owner or ao.env.Process.Owner
Controllers = Controllers or { Owner }
Records = Records or {}
Balances = Balances or { [Owner] = 1 }

-- Helper function to normalize tags
local function normalizeTags(tags)
  local normalized = {}
  for k, v in pairs(tags) do
    -- Preserve original case for X-AN-Reason
    if k == "X-AN-Reason" then
      normalized[k] = v
    else
      normalized[k:lower()] = v
    end
  end
  return normalized
end

-- Sync state on spawn and update cache
local function syncState()
  local stateData = {
    Name = Name,
    Ticker = Ticker,
    Description = Description,
    Keywords = Keywords,
    Logo = Logo,
    Denomination = Denomination,
    TotalSupply = TotalSupply,
    Owner = Owner,
    Controllers = Controllers,
    Records = Records,
    Balances = Balances
  }
  
  -- Send state to patch device for caching
  ao.send({
    device = 'patch@1.0',
    cache = {
      state = stateData,
      results = json.encode(stateData)
    }
  })
  
  return stateData
end

-- Initial sync
InitialSync = InitialSync or 'INCOMPLETE'
if InitialSync == 'INCOMPLETE' then
  syncState()
  InitialSync = 'COMPLETE'
end

local function isController(addr)
  if addr == Owner then return true end
  for _, v in ipairs(Controllers) do
    if v == addr then return true end
  end
  return false
end

Handlers.add('Set-Name', Handlers.utils.hasMatchingTag('Action', 'Set-Name'), function(msg)
  local tags = normalizeTags(msg.Tags)
  if not isController(msg.From) then
    ao.send({ Target = msg.From, Action = 'Invalid-Set-Name-Notice', Error = 'Set-Name-Error', Data = 'Not authorized', ['Message-Id'] = msg.Id })
    return
  end
  Name = tags.Name or Name
  syncState()
  ao.send({ Target = msg.From, Action = 'Set-Name-Notice', Data = json.encode({ Name = Name }) })
end)

Handlers.add('Set-Ticker', Handlers.utils.hasMatchingTag('Action', 'Set-Ticker'), function(msg)
  if not isController(msg.From) then
    ao.send({ Target = msg.From, Action = 'Invalid-Set-Ticker-Notice', Error = 'Set-Ticker-Error', Data = 'Not authorized', ['Message-Id'] = msg.Id })
    return
  end
  Ticker = msg.Tags.Ticker or Ticker
  syncState()
  ao.send({ Target = msg.From, Action = 'Set-Ticker-Notice', Data = json.encode({ Ticker = Ticker }) })
end)

Handlers.add('Set-Description', Handlers.utils.hasMatchingTag('Action', 'Set-Description'), function(msg)
  if not isController(msg.From) then
    ao.send({ Target = msg.From, Action = 'Invalid-Set-Description-Notice', Error = 'Set-Description-Error', Data = 'Not authorized', ['Message-Id'] = msg.Id })
    return
  end
  Description = msg.Tags.Description or Description
  syncState()
  ao.send({ Target = msg.From, Action = 'Set-Description-Notice', Data = json.encode({ Description = Description }) })
end)

Handlers.add('Set-Keywords', Handlers.utils.hasMatchingTag('Action', 'Set-Keywords'), function(msg)
  if not isController(msg.From) then
    ao.send({ Target = msg.From, Action = 'Invalid-Set-Keywords-Notice', Error = 'Set-Keywords-Error', Data = 'Not authorized', ['Message-Id'] = msg.Id })
    return
  end
  local success, result = pcall(json.decode, msg.Tags.Keywords or '{}')
  if success and type(result) == 'table' then
    Keywords = result
    syncState()
    ao.send({ Target = msg.From, Action = 'Set-Keywords-Notice', Data = json.encode({ Keywords = Keywords }) })
  else
    ao.send({ Target = msg.From, Action = 'Invalid-Set-Keywords-Notice', Error = 'Set-Keywords-Error', Data = 'Invalid keywords', ['Message-Id'] = msg.Id })
  end
end)

Handlers.add('Transfer', Handlers.utils.hasMatchingTag('Action', 'Transfer'), function(msg)
  if msg.From ~= Owner then
    ao.send({ Target = msg.From, Action = 'Invalid-Transfer-Notice', Error = 'Transfer-Error', Data = 'Not owner', ['Message-Id'] = msg.Id })
    return
  end
  local recipient = msg.Tags.Recipient
  if not recipient then
    ao.send({ Target = msg.From, Action = 'Invalid-Transfer-Notice', Error = 'Transfer-Error', Data = 'Recipient required', ['Message-Id'] = msg.Id })
    return
  end
  Balances[Owner] = nil
  Balances[recipient] = 1
  Owner = recipient
  Controllers = {}
  syncState()
  ao.send({ Target = msg.From, Action = 'Debit-Notice', Recipient = recipient, Quantity = 1 })
  ao.send({ Target = recipient, Action = 'Credit-Notice', Sender = msg.From, Quantity = 1 })
end)

Handlers.add('Info', Handlers.utils.hasMatchingTag('Action', 'Info'), function(msg)
  local stateData = syncState()
  ao.send({
    Target = msg.From,
    Action = 'Info-Notice',
    Data = json.encode({
      Name = stateData.Name,
      Ticker = stateData.Ticker,
      Description = stateData.Description,
      Keywords = stateData.Keywords,
      Logo = stateData.Logo,
      Denomination = tostring(stateData.Denomination),
      TotalSupply = tostring(stateData.TotalSupply),
      Owner = stateData.Owner
    })
  })
end)

Handlers.add('State', Handlers.utils.hasMatchingTag('Action', 'State'), function(msg)
  local stateData = syncState()
  ao.send({
    Target = msg.From,
    Action = 'State-Notice',
    Data = json.encode(stateData)
  })
end)

Handlers.add('Balance', Handlers.utils.hasMatchingTag('Action', 'Balance'), function(msg)
  local target = msg.Tags.Recipient or msg.From
  local stateData = syncState()
  ao.send({ Target = msg.From, Action = 'Balance-Notice', Data = tostring(stateData.Balances[target] or 0) })
end)

Handlers.add('Balances', Handlers.utils.hasMatchingTag('Action', 'Balances'), function(msg)
  local stateData = syncState()
  ao.send({ Target = msg.From, Action = 'Balances-Notice', Data = json.encode(stateData.Balances) })
end)

Handlers.add('Total-Supply', Handlers.utils.hasMatchingTag('Action', 'Total-Supply'), function(msg)
  local stateData = syncState()
  ao.send({ Target = msg.From, Action = 'Total-Supply-Notice', Data = tostring(stateData.TotalSupply) })
end)
