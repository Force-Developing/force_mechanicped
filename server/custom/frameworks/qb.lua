-- Runs once force_mechanicped knows the framework is "qb" (Config.Framework, or detected by the server).
-- Keep your code inside this function.
RegisterFramework("qb", function()
  local QBCore
  local resource = GetFrameworkResource() or "qb-core"
  -- Loaded again when qb-core restarts: the old core object points at the stopped resource
  LoadFrameworkObject(resource, function()
    return exports[resource]:GetCoreObject()
  end, function(obj)
    QBCore = obj
  end)

  local function getPlayer(source)
    return QBCore and QBCore.Functions.GetPlayer(source)
  end

  --- @param source number
  --- @param account "cash"|"bank"
  --- @return number|nil balance, nil when the player isn't loaded
  function GetMoney(source, account)
    local player = getPlayer(source)
    local money = player and player.PlayerData and player.PlayerData.money
    return type(money) == "table" and tonumber(money[account]) or nil
  end

  --- @return boolean removed
  function RemoveMoney(source, account, amount)
    local player = getPlayer(source)
    -- qb-core lets the bank go negative, so the balance is checked here
    if not player or (GetMoney(source, account) or 0) < amount then return false end
    return player.Functions.RemoveMoney(account, amount, "mechanic-repair") ~= false
  end

  --- @return boolean added
  function AddMoney(source, account, amount)
    local player = getPlayer(source)
    if not player then return false end
    return player.Functions.AddMoney(account, amount, "mechanic-repair-refund") ~= false
  end

  --- Players with one of the mechanic jobs (on duty when onlyOnDuty)
  --- @param jobs table<string, true>
  --- @param onlyOnDuty boolean
  --- @return number
  function CountMechanics(jobs, onlyOnDuty)
    if not QBCore then return 0 end
    local count = 0
    for _, player in pairs(QBCore.Functions.GetQBPlayers() or {}) do
      local job = player.PlayerData and player.PlayerData.job
      if type(job) == "table" and jobs[job.name] and (not onlyOnDuty or job.onduty) then count = count + 1 end
    end
    return count
  end
end)
