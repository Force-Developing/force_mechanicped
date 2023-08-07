ESX = nil

TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

ESX.RegisterServerCallback("force_mechanicped:getMechanicOnline", function(source, cb)
    local players = ESX.GetPlayers()
    local mechanicOnline = 0

	for i=1, #players, 1 do
        local player = ESX.GetPlayerFromId(players[i])
        if player.job.name == 'mecano' then
            mechanicOnline = mechanicOnline + 1
        end
    end
    cb(mechanicOnline)
end)

ESX.RegisterServerCallback("force_mechanicped:getMoney", function(source, cb)
    local player = ESX.GetPlayerFromId(source)

    if player.getMoney() >= Config.RepairPrice then
        cb(true)
        player.removeMoney(Config.RepairPrice)
    elseif player.getAccount('bank').money >= Config.RepairPrice then
        cb(true)
        player.removeAccountMoney('bank', Config.RepairPrice)
    else
        cb(false)
    end
end)