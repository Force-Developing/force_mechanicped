-- Runs once force_mechanicped knows the framework is "esx" (Config.Framework, or detected by the server).
-- Keep your code inside this function.
RegisterFramework("esx", function()
  local ESX
  local resource = GetFrameworkResource() or "es_extended"
  -- Loaded again when es_extended restarts: the old shared object points at the stopped resource
  LoadFrameworkObject(resource, function()
    return exports[resource]:getSharedObject()
  end, function(obj)
    ESX = obj
  end)

  -- Config.Account names -> ESX account names
  local ACCOUNTS = { cash = "money", bank = "bank" }

  local function getAccount(source, account)
    local xPlayer = ESX and ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end
    local name = ACCOUNTS[account] or account
    return xPlayer, xPlayer.getAccount(name), name
  end

  --- @param source number
  --- @param account "cash"|"bank"
  --- @return number|nil balance, nil when the player isn't loaded
  function GetMoney(source, account)
    local _, data = getAccount(source, account)
    return data and tonumber(data.money) or nil
  end

  --- @return boolean removed
  function RemoveMoney(source, account, amount)
    local xPlayer, data, name = getAccount(source, account)
    if not data or (tonumber(data.money) or 0) < amount then return false end
    xPlayer.removeAccountMoney(name, amount, "Mechanic repair")
    return true
  end

  --- @return boolean added
  function AddMoney(source, account, amount)
    local xPlayer, data, name = getAccount(source, account)
    if not data then return false end
    xPlayer.addAccountMoney(name, amount, "Mechanic repair refund")
    return true
  end

  --- Players with one of the mechanic jobs (on duty when onlyOnDuty and the ESX version has job.onDuty)
  --- @param jobs table<string, true>
  --- @param onlyOnDuty boolean
  --- @return number
  function CountMechanics(jobs, onlyOnDuty)
    if not ESX then return 0 end
    local players = {}
    if ESX.GetExtendedPlayers then
      players = ESX.GetExtendedPlayers()
    else
      for _, id in ipairs(ESX.GetPlayers()) do players[#players + 1] = ESX.GetPlayerFromId(id) end
    end
    local count = 0
    for _, xPlayer in pairs(players) do
      local job = type(xPlayer) == "table" and xPlayer.job
      if type(job) == "table" and jobs[job.name] and (not onlyOnDuty or job.onDuty ~= false) then
        count = count + 1
      end
    end
    return count
  end
end)
