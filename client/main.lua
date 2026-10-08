local RESOURCE = GetCurrentResourceName()
local CALLBACK_TIMEOUT = 15000
local PED_DISTANCE = 60.0
local MARKER_DISTANCE = 15.0
local WALK_TIMEOUT = 6000
local LEAVE_TIMEOUT = 4000
local KEY_E = 38
local HOOD = 4
local ANIM_DICT, ANIM_NAME = "mini@repair", "fixing_a_ped"
local IDLE_DICT, IDLE_NAME = "mini@strip_club@idles@bouncer@base", "base"

local peds = {}        -- [location id] = mechanic ped handle
local pedWanted = {}   -- [location id] = true while the player is near the ped
local blips = {}       -- [location id] = blip handle
local points = {}      -- lib.points
local oxZones = {}     -- ox_target zone ids
local qbZones = {}     -- qb-target zone names
local shownText = nil  -- key of the text UI this resource shows
local requesting = false -- status check / confirm dialog / start request in progress
local repairing = nil  -- { location = table, vehicle = handle, lockStatus = number|nil } while a repair runs
local lastKeyPress = 0

local function notify(message, notifyType)
  lib.notify({ description = message, type = notifyType or "inform" })
end

local function showText(key, text)
  if shownText == key then return end
  lib.showTextUI(text)
  shownText = key
end

local function hideText(key)
  if not shownText or (key and shownText ~= key) then return end
  lib.hideTextUI()
  shownText = nil
end

local function playerLoaded()
  local ok, loaded = pcall(IsPlayerLoaded)
  return ok and loaded == true
end

--- The vehicle the player drives, or nil
local function driverVehicle()
  local vehicle = cache.vehicle
  if not vehicle or vehicle == 0 or cache.seat ~= -1 or not DoesEntityExist(vehicle) then return nil end
  return vehicle
end

local function atLocation(location, vehicle)
  local c = location.coords
  return #(GetEntityCoords(vehicle) - vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0)) <= location.radius + 1.0
end

--- lib.callback with its own timeout (ox_lib waits 5 minutes and throws). Returns nil when the server didn't answer.
local function awaitServer(name, ...)
  local p = promise.new()
  local settled = false
  local function settle(value)
    if settled then return end
    settled = true
    p:resolve(value)
  end
  lib.callback(name, false, function(...)
    settle({ n = select("#", ...), ... })
  end, ...)
  SetTimeout(CALLBACK_TIMEOUT, function() settle(false) end)
  local result = Citizen.Await(p)
  if not result then return nil end
  return table.unpack(result, 1, result.n)
end

-------------------------------------------------------------------------------------------------------------------
-- Mechanic ped and blip
-------------------------------------------------------------------------------------------------------------------

local function deletePed(id)
  local ped = peds[id]
  peds[id] = nil
  if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
end

--- Idle pose at his post (the 1.x bouncer stance)
local function pedIdle(ped)
  local ok, err = pcall(lib.requestAnimDict, IDLE_DICT, 5000)
  if not ok then return Debug("error", "Idle animation could not be loaded: %s", tostring(err)) end
  if not DoesEntityExist(ped) then return end
  TaskPlayAnim(ped, IDLE_DICT, IDLE_NAME, 8.0, -8.0, -1, 1, 0, false, false, false)
  RemoveAnimDict(IDLE_DICT)
end

local function spawnPed(location)
  local id = location.id
  if peds[id] and DoesEntityExist(peds[id]) then return end
  local model = joaat(location.ped.model)
  local ok, err = pcall(lib.requestModel, model, 10000)
  if not ok then
    Debug("error", "Location '%s': ped model '%s' could not be loaded: %s", id, tostring(location.ped.model), tostring(err))
    return
  end
  -- The player may have walked away while the model loaded
  if not pedWanted[id] or (peds[id] and DoesEntityExist(peds[id])) then
    SetModelAsNoLongerNeeded(model)
    return
  end
  local c = location.ped.coords
  local ped = CreatePed(4, model, c.x + 0.0, c.y + 0.0, c.z + 0.0, location.ped.heading, false, false)
  SetModelAsNoLongerNeeded(model)
  FreezeEntityPosition(ped, true)
  SetEntityInvincible(ped, true)
  SetBlockingOfNonTemporaryEvents(ped, true)
  SetPedCanRagdoll(ped, false)
  peds[id] = ped
  if not repairing or repairing.location.id ~= id then pedIdle(ped) end
end

--- Walks the ped to coords (gives up after WALK_TIMEOUT) and freezes it there
local function walkPed(ped, coords, heading, keepGoing)
  if not ped or not DoesEntityExist(ped) then return end
  ClearPedTasks(ped)
  FreezeEntityPosition(ped, false)
  TaskGoStraightToCoord(ped, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, 1.0, WALK_TIMEOUT, heading, 0.2)
  local deadline = GetGameTimer() + WALK_TIMEOUT
  while DoesEntityExist(ped) and GetGameTimer() < deadline and keepGoing() do
    local pos = GetEntityCoords(ped)
    if math.abs(pos.x - coords.x) < 0.5 and math.abs(pos.y - coords.y) < 0.5 then break end
    Wait(100)
  end
  if not DoesEntityExist(ped) then return end
  SetEntityHeading(ped, heading)
  FreezeEntityPosition(ped, true)
end

local function pedStartWork(location, job)
  local ped = peds[location.id]
  local work = location.ped and location.ped.workCoords
  if not work or not ped then return end
  walkPed(ped, work, location.ped.workHeading, function() return repairing == job end)
  if repairing ~= job or not DoesEntityExist(ped) then return end
  local ok, err = pcall(lib.requestAnimDict, ANIM_DICT, 5000)
  if not ok then return Debug("error", "Repair animation could not be loaded: %s", tostring(err)) end
  TaskPlayAnim(ped, ANIM_DICT, ANIM_NAME, 8.0, -8.0, -1, 1, 0, false, false, false)
  RemoveAnimDict(ANIM_DICT)
end

local function pedBackToPost(location)
  local ped = peds[location.id]
  if not location.ped or not ped or not DoesEntityExist(ped) then return end
  ClearPedTasks(ped)
  CreateThread(function()
    if not location.ped.workCoords then return pedIdle(ped) end
    walkPed(ped, location.ped.coords, location.ped.heading, function() return repairing == nil end)
    if repairing == nil and peds[location.id] == ped then pedIdle(ped) end
  end)
end

local function addBlip(location)
  local data = location.blip
  if not data then return end
  local c = location.coords
  local blip = AddBlipForCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
  SetBlipSprite(blip, tonumber(data.sprite) or 544)
  SetBlipColour(blip, tonumber(data.colour) or 0)
  SetBlipScale(blip, (tonumber(data.scale) or 0.7) + 0.0)
  SetBlipAsShortRange(blip, true)
  BeginTextCommandSetBlipName("STRING")
  AddTextComponentSubstringPlayerName(type(data.label) == "string" and data.label or locale("blip"))
  EndTextCommandSetBlipName(blip)
  blips[location.id] = blip
end

-------------------------------------------------------------------------------------------------------------------
-- Repair
-------------------------------------------------------------------------------------------------------------------

local function takeControl(vehicle)
  if NetworkHasControlOfEntity(vehicle) then return true end
  local deadline = GetGameTimer() + 2000
  while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < deadline do
    NetworkRequestControlOfEntity(vehicle)
    Wait(50)
  end
  return NetworkHasControlOfEntity(vehicle)
end

--- Lines the vehicle up, turns the engine off, freezes it, opens the hood and (Config.LeaveVehicle) lets the
--- player step out and locks the doors
local function prepareVehicle(job)
  local location, vehicle = job.location, job.vehicle
  if Config.SnapVehicle then
    local c = location.coords
    SetEntityCoords(vehicle, c.x + 0.0, c.y + 0.0, c.z + 0.0, false, false, false, false)
    if location.heading then SetEntityHeading(vehicle, location.heading) end
    SetVehicleOnGroundProperly(vehicle)
  end
  -- auto-start stays enabled, so throttle starts the engine again if the repair is cancelled in the driver seat
  SetVehicleEngineOn(vehicle, false, true, false)
  FreezeEntityPosition(vehicle, true)
  SetVehicleDoorOpen(vehicle, HOOD, false, false)

  if not Config.LeaveVehicle then return end
  TaskLeaveVehicle(cache.ped, vehicle, 0)
  local deadline = GetGameTimer() + LEAVE_TIMEOUT
  while IsPedInVehicle(PlayerPedId(), vehicle, false) and GetGameTimer() < deadline and repairing == job do Wait(100) end
  if repairing ~= job or IsPedInVehicle(PlayerPedId(), vehicle, false) then return end
  job.lockStatus = GetVehicleDoorLockStatus(vehicle)
  SetVehicleDoorsLocked(vehicle, 2)
end

--- Undoes prepareVehicle and sends the mechanic back. Safe to call more than once.
local function exitRepair()
  local job = repairing
  if not job then return end
  repairing = nil
  local vehicle = job.vehicle
  if vehicle and DoesEntityExist(vehicle) then
    FreezeEntityPosition(vehicle, false)
    SetVehicleDoorShut(vehicle, HOOD, false)
    if job.lockStatus then SetVehicleDoorsLocked(vehicle, job.lockStatus) end
  end
  pedBackToPost(job.location)
end

local function fixVehicle(vehicle)
  if not DoesEntityExist(vehicle) then return end
  if not takeControl(vehicle) then Debug("warn", "No network control of the vehicle, the repair may not sync") end
  SetVehicleFixed(vehicle)
  SetVehicleDeformationFixed(vehicle)
  SetVehicleEngineHealth(vehicle, 1000.0)
  SetVehicleBodyHealth(vehicle, 1000.0)
  SetVehiclePetrolTankHealth(vehicle, 1000.0)
  SetVehicleUndriveable(vehicle, false)
  SetVehicleEngineOn(vehicle, true, true, false)
end

local function condition(vehicle)
  local engine = math.max(0, math.floor((GetVehicleEngineHealth(vehicle) or 0) / 10))
  local body = math.max(0, math.floor((GetVehicleBodyHealth(vehicle) or 0) / 10))
  return engine, body
end

--- Checks with the server, asks the player to confirm the price and starts the repair
--- @return boolean|nil started, number|nil durationMs, number|nil netId
local function confirmAndStart(location, vehicle)
  local available, reason, price = awaitServer(RESOURCE .. ":server:status", location.id)
  if available == nil then return notify(locale("server_no_response"), "error") end
  if not available then return notify(locale(type(reason) == "string" and reason or "repair_failed", GetPrice()), "error") end

  price = tonumber(price) or GetPrice()
  local seconds = math.floor(GetRepairDuration() / 1000)
  local engine, body = condition(vehicle)
  local content = price > 0 and locale("confirm_content", price, seconds, engine, body)
      or locale("confirm_content_free", seconds, engine, body)
  local answer = lib.alertDialog({ header = location.label, content = content, centered = true, cancel = true })
  if answer ~= "confirm" then return end

  -- the player may have driven off while the dialog was open
  if driverVehicle() ~= vehicle or not atLocation(location, vehicle) then return notify(locale("too_far"), "error") end
  local netId = VehToNet(vehicle)
  local ok, result, paid = awaitServer(RESOURCE .. ":server:start", location.id, netId)
  if ok == nil then return notify(locale("server_no_response"), "error") end
  if not ok then return notify(locale(type(result) == "string" and result or "repair_failed", price), "error") end
  if (tonumber(paid) or 0) > 0 then notify(locale("paid", paid)) end
  return true, tonumber(result) or GetRepairDuration(), netId
end

local function runRepair(location, vehicle, duration, netId)
  local job = { location = location, vehicle = vehicle }
  repairing = job

  local finished = false
  local okRun, err = pcall(function()
    CreateThread(function() pedStartWork(location, job) end)
    prepareVehicle(job)
    if repairing ~= job then return end
    finished = lib.progressBar({
      duration = duration,
      label = locale("repairing"),
      useWhileDead = false,
      canCancel = true,
      disable = { move = true, car = true, combat = true },
    })
  end)
  if not okRun then Debug("error", "Repair failed: %s", tostring(err)) end
  -- the resource was stopped, or something else ended the repair
  if repairing ~= job then return end

  if not finished then
    TriggerServerEvent(RESOURCE .. ":server:cancel")
    exitRepair()
    return notify(locale("cancelled"), "error")
  end

  local okFinish, done, reason = pcall(awaitServer, RESOURCE .. ":server:finish", netId)
  if okFinish and done then
    fixVehicle(vehicle)
    exitRepair()
    return notify(locale("repaired"), "success")
  end
  exitRepair()
  if not okFinish or done == nil then
    -- unknown outcome: tell the server to give the money back if it still holds the repair
    TriggerServerEvent(RESOURCE .. ":server:cancel")
    return notify(locale("server_no_response"), "error")
  end
  notify(locale(type(reason) == "string" and reason or "repair_failed"), "error")
end

--- Asks the NPC mechanic at a location to repair the vehicle the player drives. Yields; call it from a thread.
--- The server checks the mechanics on duty, the money, the vehicle, the distance, the repair time and the cooldown.
--- @param locationId string
function RequestRepair(locationId)
  local location = GetLocation(locationId)
  if not location or requesting then return end
  if repairing then return notify(locale("busy"), "error") end
  if not IsFrameworkReady() or not playerLoaded() then return notify(locale("not_ready"), "error") end
  local vehicle = driverVehicle()
  if not vehicle or not NetworkGetEntityIsNetworked(vehicle) then return notify(locale("no_vehicle"), "error") end
  if not atLocation(location, vehicle) then return notify(locale("too_far"), "error") end

  requesting = true
  local ok, started, duration, netId = pcall(confirmAndStart, location, vehicle)
  requesting = false
  if not ok then
    Debug("error", "Starting a repair failed: %s", tostring(started))
    return notify(locale("server_no_response"), "error")
  end
  if started then runRepair(location, vehicle, duration, netId) end
end

-------------------------------------------------------------------------------------------------------------------
-- World: ped, blip, marker, target zones / [E] points
-------------------------------------------------------------------------------------------------------------------

local function drawMarker(coords, size, r, g, b)
  DrawMarker(1, coords.x, coords.y, coords.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, size, size, 0.6, r, g, b, 90,
    false, false, 2, false, nil, nil, false)
end

local function request(id)
  CreateThread(function() RequestRepair(id) end)
end

local function addTarget(location)
  local target = GetTargetSystem()
  local name = ("%s:%s"):format(RESOURCE, location.id)
  local coords = vector3(location.coords.x + 0.0, location.coords.y + 0.0, location.coords.z + 0.0)
  local function canInteract() return not repairing and not requesting and driverVehicle() ~= nil and playerLoaded() end
  local function open() request(location.id) end

  if target == "ox_target" then
    oxZones[#oxZones + 1] = exports.ox_target:addSphereZone({
      coords = coords,
      radius = location.radius,
      options = { {
        name = name, icon = "fa-solid fa-wrench", label = locale("target_label"), distance = location.radius + 2.0,
        canInteract = canInteract, onSelect = open,
      } },
    })
  elseif target == "qb-target" then
    exports["qb-target"]:AddCircleZone(name, coords, location.radius, { name = name, debugPoly = false, useZ = true }, {
      options = { { icon = "fas fa-wrench", label = locale("target_label"), canInteract = canInteract, action = open } },
      distance = location.radius + 2.0,
    })
    qbZones[#qbZones + 1] = name
  end
end

local function addTargets()
  oxZones, qbZones = {}, {}
  for _, location in pairs(Config.Locations) do
    local ok, err = pcall(addTarget, location)
    if not ok then Log("error", ("Location '%s': adding the target zone failed: %s"):format(location.id, tostring(err))) end
  end
end

local function setupLocation(location)
  local id = location.id

  if location.ped then
    points[#points + 1] = lib.points.new({
      coords = vector3(location.ped.coords.x + 0.0, location.ped.coords.y + 0.0, location.ped.coords.z + 0.0),
      distance = PED_DISTANCE,
      onEnter = function()
        pedWanted[id] = true
        -- loading the model yields; don't block the points loop
        CreateThread(function() spawnPed(location) end)
      end,
      onExit = function()
        pedWanted[id] = false
        deletePed(id)
      end,
    })
  end

  local hasTarget = GetTargetSystem() ~= "none"
  local textKey = "repair:" .. id
  points[#points + 1] = lib.points.new({
    coords = vector3(location.coords.x + 0.0, location.coords.y + 0.0, location.coords.z + 0.0),
    distance = math.max(location.radius, MARKER_DISTANCE),
    nearby = function(p)
      if repairing or requesting or not playerLoaded() then return hideText(textKey) end
      local inside = p.currentDistance <= location.radius
      local vehicle = driverVehicle()
      if Config.DrawMarkers then
        if inside and vehicle then drawMarker(location.coords, location.radius * 2.0, 60, 200, 90)
        else drawMarker(location.coords, location.radius * 2.0, 40, 120, 255) end
      end
      if hasTarget then return end
      if not inside or not vehicle then return hideText(textKey) end
      showText(textKey, locale("textui"))
      if IsControlJustReleased(0, KEY_E) and GetGameTimer() - lastKeyPress > 500 then
        lastKeyPress = GetGameTimer()
        hideText(textKey)
        request(id)
      end
    end,
    onExit = function() hideText(textKey) end,
  })
end

exports("requestRepair", function(locationId)
  request(locationId)
end)

for _, location in pairs(Config.Locations) do
  local ok, err = pcall(addBlip, location)
  if not ok then Log("error", ("Location '%s': the blip could not be created: %s"):format(tostring(location.id), tostring(err))) end
end

local targetsAdded = false

OnEnvironmentReady(function()
  for _, location in pairs(Config.Locations) do
    local ok, err = pcall(setupLocation, location)
    if not ok then Log("error", ("Location '%s' could not be set up: %s"):format(tostring(location.id), tostring(err))) end
  end

  local target = GetTargetSystem()
  if target == "none" then return end
  -- The client starts resources in server.cfg order: a target ensured after this resource isn't running here yet
  CreateThread(function()
    local nextWarning = GetGameTimer() + 10000
    while GetResourceState(target) ~= "started" do
      Wait(250)
      if GetGameTimer() >= nextWarning then
        Log("warn", ("Still waiting for %s to start on this client."):format(target))
        nextWarning = GetGameTimer() + 10000
      end
    end
    if targetsAdded then return end
    targetsAdded = true
    addTargets()
    Debug("info", "Repair target zones added (%s)", target)
  end)
end)

-- A restarted target resource has forgotten our zones
AddEventHandler("onClientResourceStart", function(resource)
  if not targetsAdded or resource ~= GetTargetSystem() then return end
  addTargets()
end)

AddEventHandler("onResourceStop", function(resource)
  if resource ~= RESOURCE then return end
  hideText()
  if requesting then pcall(function() lib.closeAlertDialog() end) end
  -- the progress bar runs in ox_lib and would keep the controls disabled
  if repairing then pcall(lib.cancelProgress) end
  exitRepair()
  for id in pairs(peds) do deletePed(id) end
  for _, blip in pairs(blips) do RemoveBlip(blip) end
  for _, point in ipairs(points) do point:remove() end
  -- the target resources may be stopped already; nothing to clean up then
  for _, zone in ipairs(oxZones) do pcall(function() exports.ox_target:removeZone(zone) end) end
  for _, name in ipairs(qbZones) do pcall(function() exports["qb-target"]:RemoveZone(name) end) end
end)
