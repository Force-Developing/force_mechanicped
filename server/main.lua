local RESOURCE = GetCurrentResourceName()
-- Extra meters on top of a location's radius (the vehicle's position on the server lags a little behind)
local DISTANCE_MARGIN = 2.0
-- The player has to stay this close to the location until the repair is finished
local PLAYER_RANGE = 25.0
-- A finish request may arrive this much before the repair time is up (network and frame timing)
local FINISH_EARLY_MS = 1500
-- A repair that was never finished or cancelled is refunded and forgotten after its duration plus this
local REPAIR_TTL_MS = 60000

local repairs = {}    -- [source] = { location = id, vehicle = entity, netId, startedAt, amount, account }
local lastRepair = {} -- [source] = GetGameTimer() of the last finished repair
local mechanicJobs = {}

local function toVector3(v)
  return vector3(v.x + 0.0, v.y + 0.0, v.z + 0.0)
end

local function prepareConfig()
  -- Accepts { "mechanic" } and { mechanic = true }
  if type(Config.MechanicJobs) == "table" then
    for key, value in pairs(Config.MechanicJobs) do
      if type(value) == "string" then mechanicJobs[value] = true
      elseif type(key) == "string" and value then mechanicJobs[key] = true end
    end
  end
  if next(mechanicJobs) == nil then
    Log("warn", "Config.MechanicJobs is empty: the NPC mechanic works no matter who is on duty")
  end
  if Config.Account ~= "auto" and Config.Account ~= "cash" and Config.Account ~= "bank" then
    Log("error", ("Unknown Config.Account '%s', using \"auto\""):format(tostring(Config.Account)))
    Config.Account = "auto"
  end
end

--- Mechanics on duty, or nil when the framework bridge failed
--- @return number|nil
local function mechanicsOnDuty()
  if next(mechanicJobs) == nil then return 0 end
  local ok, count = pcall(CountMechanics, mechanicJobs, Config.CountOnlyOnDuty ~= false)
  if not ok or type(count) ~= "number" then
    Log("error", ("Counting the mechanics on duty failed: %s"):format(tostring(count)))
    return nil
  end
  return count
end

--- Gives the money of a repair back. Errors are always printed with the amount, so it can be refunded by hand.
local function refund(source, repair, why)
  if not repair or not repair.amount or repair.amount <= 0 then return end
  local ok, added = pcall(AddMoney, source, repair.account, repair.amount)
  if ok and added then
    Debug("info", "Refunded $%s (%s) to %s: %s", repair.amount, repair.account, tostring(GetPlayerName(source)), why)
    if GetPlayerName(source) then
      lib.notify(source, { description = locale("refunded", repair.amount), type = "inform" })
    end
    return
  end
  Log("error", ("Could not refund $%s (%s) to player %s (%s) after: %s%s"):format(repair.amount, repair.account,
    tostring(source), tostring(GetPlayerName(source)), why, ok and "" or (" (" .. tostring(added) .. ")")))
end

--- Forgets the player's repair (refunding it) when it outlived its duration
local function expireRepair(source)
  local running = repairs[source]
  if running and GetGameTimer() - running.startedAt > GetRepairDuration() + REPAIR_TTL_MS then
    repairs[source] = nil
    refund(source, running, "the repair was never finished")
  end
end

--- Everything that doesn't depend on the vehicle: framework, running repair, cooldown, mechanics on duty
--- @return boolean ok, string|nil reason
local function checkAvailable(source)
  if not IsFrameworkReady() then return false, "not_ready" end
  expireRepair(source)
  if repairs[source] then return false, "busy" end
  local cooldown = (tonumber(Config.Cooldown) or 0) * 1000
  if lastRepair[source] and GetGameTimer() - lastRepair[source] < cooldown then return false, "cooldown" end
  local mechanics = mechanicsOnDuty()
  if not mechanics then return false, "not_ready" end
  if mechanics > (tonumber(Config.MaxMechanicsOnDuty) or 0) then return false, "mechanics_online" end
  return true
end

--- The vehicle behind netId, if the player sits in its driver seat and it stands at the location
--- @return number|nil vehicle, string|nil reason
local function drivenVehicleAt(source, location, netId)
  if type(netId) ~= "number" then return nil, "no_vehicle" end
  local ped = GetPlayerPed(source)
  if not ped or ped == 0 then return nil, "no_vehicle" end
  local vehicle = NetworkGetEntityFromNetworkId(netId)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then
    return nil, "no_vehicle"
  end
  if GetVehiclePedIsIn(ped, false) ~= vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped then
    return nil, "no_vehicle"
  end
  if #(GetEntityCoords(vehicle) - toVector3(location.coords)) > location.radius + DISTANCE_MARGIN then
    return nil, "too_far"
  end
  return vehicle
end

--- Takes the price from the configured account ("auto": cash first, then bank)
--- @return boolean paid, string accountOrReason
local function charge(source, price)
  local accounts = Config.Account == "auto" and { "cash", "bank" } or { Config.Account }
  local loaded = false
  for _, account in ipairs(accounts) do
    local ok, balance = pcall(GetMoney, source, account)
    if not ok then
      Log("error", ("Reading the %s balance failed: %s"):format(account, tostring(balance)))
    elseif type(balance) == "number" then
      loaded = true
      if balance >= price then
        local okRemove, removed = pcall(RemoveMoney, source, account, price)
        if okRemove and removed then return true, account end
        if not okRemove then Log("error", ("Taking %s money failed: %s"):format(account, tostring(removed))) end
      end
    end
  end
  return false, loaded and "no_money" or "not_ready"
end

-- Whether the NPC can be used right now (for the prompt; start checks everything again)
lib.callback.register(RESOURCE .. ":server:status", function(source, locationId)
  if not GetLocation(locationId) then return false, "repair_failed" end
  local ok, reason = checkAvailable(source)
  return ok, reason, GetPrice()
end)

lib.callback.register(RESOURCE .. ":server:start", function(source, locationId, netId)
  local location = GetLocation(locationId)
  if not location then return false, "repair_failed" end
  local ok, reason = checkAvailable(source)
  if not ok then return false, reason end

  local vehicle, why = drivenVehicleAt(source, location, netId)
  if not vehicle then return false, why end

  local price = GetPrice()
  local account
  if price > 0 then
    local paid, result = charge(source, price)
    if not paid then return false, result end
    account = result
  end

  repairs[source] = {
    location = location.id, vehicle = vehicle, netId = netId, startedAt = GetGameTimer(), amount = price, account = account,
  }
  Debug("info", "%s paid $%s (%s) for a repair at %s", GetPlayerName(source), price, tostring(account), location.id)
  return true, GetRepairDuration(), price
end)

--- @return boolean ok, string|nil reason
local function validateFinish(source, repair, netId)
  local elapsed = GetGameTimer() - repair.startedAt
  if netId ~= repair.netId or elapsed < GetRepairDuration() - FINISH_EARLY_MS then return false, "repair_failed" end
  if elapsed > GetRepairDuration() + REPAIR_TTL_MS then return false, "repair_failed" end
  local location = GetLocation(repair.location)
  if not location then return false, "repair_failed" end
  local vehicle = repair.vehicle
  if not DoesEntityExist(vehicle) or NetworkGetEntityFromNetworkId(netId) ~= vehicle then return false, "no_vehicle" end
  local spot = toVector3(location.coords)
  if #(GetEntityCoords(vehicle) - spot) > location.radius + DISTANCE_MARGIN then return false, "too_far" end
  local ped = GetPlayerPed(source)
  if not ped or ped == 0 or #(GetEntityCoords(ped) - spot) > PLAYER_RANGE then return false, "too_far" end
  return true
end

lib.callback.register(RESOURCE .. ":server:finish", function(source, netId)
  local repair = repairs[source]
  if not repair then return false, "repair_failed" end
  -- One finish per start, whatever the outcome
  repairs[source] = nil

  local ok, reason = validateFinish(source, repair, netId)
  if not ok then
    refund(source, repair, "finish rejected: " .. tostring(reason))
    return false, reason
  end
  lastRepair[source] = GetGameTimer()
  Debug("info", "%s finished a repair at %s", GetPlayerName(source), repair.location)
  return true
end)

RegisterNetEvent(RESOURCE .. ":server:cancel", function()
  local src = source
  local repair = repairs[src]
  repairs[src] = nil
  refund(src, repair, "cancelled")
end)

AddEventHandler("playerDropped", function()
  local src = source
  local repair = repairs[src]
  repairs[src] = nil
  lastRepair[src] = nil
  -- The framework may have unloaded the player already; refund() then prints the amount
  refund(src, repair, "the player left during the repair")
end)

AddEventHandler("onResourceStop", function(resource)
  if resource ~= RESOURCE then return end
  for src, repair in pairs(repairs) do
    repairs[src] = nil
    refund(src, repair, "the resource stopped during the repair")
  end
end)

-- Refunds repairs whose client never reported back (crash, timeout)
CreateThread(function()
  while true do
    Wait(5000)
    for src in pairs(repairs) do expireRepair(src) end
  end
end)

--- Number of players with a mechanic job (on duty when Config.CountOnlyOnDuty), as the NPC sees it
exports("getMechanicsOnDuty", function()
  return mechanicsOnDuty() or 0
end)

prepareConfig()
