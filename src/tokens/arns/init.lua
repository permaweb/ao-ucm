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

local function isController(addr)
  if addr == Owner then return true end
  for _, v in ipairs(Controllers) do
    if v == addr then return true end
  end
  return false
end

Handlers.add('Set-Name', Handlers.utils.hasMatchingTag('Action', 'Set-Name'), function(msg)
  if not isController(msg.From) then
    ao.send({ Target = msg.From, Action = 'Invalid-Set-Name-Notice', Error = 'Set-Name-Error', Data = 'Not authorized', ['Message-Id'] = msg.Id })
    return
  end
  Name = msg.Tags.Name or Name
  ao.send({ Target = msg.From, Action = 'Set-Name-Notice', Data = json.encode({ Name = Name }) })
end)

Handlers.add('Set-Ticker', Handlers.utils.hasMatchingTag('Action', 'Set-Ticker'), function(msg)
  if not isController(msg.From) then
    ao.send({ Target = msg.From, Action = 'Invalid-Set-Ticker-Notice', Error = 'Set-Ticker-Error', Data = 'Not authorized', ['Message-Id'] = msg.Id })
    return
  end
  Ticker = msg.Tags.Ticker or Ticker
  ao.send({ Target = msg.From, Action = 'Set-Ticker-Notice', Data = json.encode({ Ticker = Ticker }) })
end)

Handlers.add('Set-Description', Handlers.utils.hasMatchingTag('Action', 'Set-Description'), function(msg)
  if not isController(msg.From) then
    ao.send({ Target = msg.From, Action = 'Invalid-Set-Description-Notice', Error = 'Set-Description-Error', Data = 'Not authorized', ['Message-Id'] = msg.Id })
    return
  end
  Description = msg.Tags.Description or Description
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
  ao.send({ Target = msg.From, Action = 'Debit-Notice', Recipient = recipient, Quantity = 1 })
  ao.send({ Target = recipient, Action = 'Credit-Notice', Sender = msg.From, Quantity = 1 })
end)

Handlers.add('Info', Handlers.utils.hasMatchingTag('Action', 'Info'), function(msg)
  ao.send({
    Target = msg.From,
    Action = 'Info-Notice',
    Data = json.encode({
      Name = Name,
      Ticker = Ticker,
      Description = Description,
      Keywords = Keywords,
      Logo = Logo,
      Denomination = tostring(Denomination),
      TotalSupply = tostring(TotalSupply),
      Owner = Owner
    })
  })
end)

Handlers.add('State', Handlers.utils.hasMatchingTag('Action', 'State'), function(msg)
  ao.send({
    Target = msg.From,
    Action = 'State-Notice',
    Data = json.encode({
      Records = Records,
      Controllers = Controllers,
      Balances = Balances,
      Owner = Owner,
      Name = Name,
      Ticker = Ticker,
      Logo = Logo,
      Description = Description,
      Keywords = Keywords,
      Denomination = Denomination,
      TotalSupply = TotalSupply
    })
  })
end)

Handlers.add('Balance', Handlers.utils.hasMatchingTag('Action', 'Balance'), function(msg)
  local target = msg.Tags.Recipient or msg.From
  ao.send({ Target = msg.From, Action = 'Balance-Notice', Data = tostring(Balances[target] or 0) })
end)

Handlers.add('Balances', Handlers.utils.hasMatchingTag('Action', 'Balances'), function(msg)
  ao.send({ Target = msg.From, Action = 'Balances-Notice', Data = json.encode(Balances) })
end)

Handlers.add('Total-Supply', Handlers.utils.hasMatchingTag('Action', 'Total-Supply'), function(msg)
  ao.send({ Target = msg.From, Action = 'Total-Supply-Notice', Data = tostring(TotalSupply) })
end)
