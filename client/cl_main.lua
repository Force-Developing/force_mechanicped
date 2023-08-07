ESX              = nil
local PlayerData = {}

Citizen.CreateThread(function()
	while ESX == nil do
		TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
		Citizen.Wait(0)
	end
end)

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(xPlayer)
	PlayerData = xPlayer   
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
	PlayerData.job = job
end)

Citizen.CreateThread(function()
	local blip = AddBlipForCoord(Config.MechanicPed.Coords)

	SetBlipSprite(blip, 544)
	SetBlipScale(blip, 0.7)
	SetBlipColour(blip, 0)
	SetBlipAsShortRange(blip, true)

	BeginTextCommandSetBlipName('STRING')
	AddTextComponentSubstringPlayerName("Åke")
	EndTextCommandSetBlipName(blip)

	while true do
		local sleepThread = 500
		local player = PlayerPedId()
		local pCoords = GetEntityCoords(player)

		local pedDst = #(pCoords - Config.MechanicPed.Coords)

		if pedDst < 50 then
			RequestModel(Config.MechanicPed.Model) while not HasModelLoaded(Config.MechanicPed.Model) do Wait(7) end
			if not DoesEntityExist(mechanicPed) then
				mechanicPed = CreatePed(4, Config.MechanicPed.Model, Config.MechanicPed.Coords, Config.MechanicPed.Heading, false, true)
				FreezeEntityPosition(mechanicPed, true)
				SetBlockingOfNonTemporaryEvents(mechanicPed, true)
				SetEntityInvincible(mechanicPed, true)
				ESX.LoadAnimDict("mini@strip_club@idles@bouncer@base")
                TaskPlayAnim(mechanicPed, 'mini@strip_club@idles@bouncer@base', 'base', 1.0, -1.0, -1, 69, 0, 0, 0, 0)
			end
		end

		local vehicleDst = #(pCoords - Config.Vehicle.Coords)

		if vehicleDst < 5.0 and vehicleDst > 1.5 then
			sleepThread = 5

			Funcs.DrawMarker({
				type = 23,
				pos = Config.Vehicle.Coords - vector3(0, 0, 0.95),
				r = 255, g = 0, b = 0,
				sizeX = 3.0, sizeY = 3.0, sizeZ = 1.0
			})
		end

		if vehicleDst < 1.5 then
			sleepThread = 5

			Funcs.DrawMarker({
				type = 23,
				pos = Config.Vehicle.Coords - vector3(0, 0, 0.95),
				r = 0, g = 255, b = 0,
				sizeX = 3.0, sizeY = 3.0, sizeZ = 1.0
			})

			ESX.ShowHelpNotification("~INPUT_PICKUP~ Laga fordon, " .. Config.RepairPrice)

			if IsControlJustPressed(1, 38) then
				ESX.TriggerServerCallback("force_mechanicped:getMechanicOnline", function(data)
					if data > 0 then
						ESX.ShowNotification("Det finns mekaniker vakna!")
					else
						if IsPedInAnyVehicle(player, false) then
							ESX.TriggerServerCallback("force_mechanicped:getMoney", function(data)
								if data then
									local vehicle = GetVehiclePedIsIn(player, false)

									SetEntityCoords(vehicle, Config.Vehicle.Coords, true)
									SetEntityHeading(vehicle, Config.Vehicle.Heading)
									FreezeEntityPosition(vehicle, true)
									SetVehicleDoorOpen(vehicle, 4, false, true)

									FreezeEntityPosition(mechanicPed, false)
									TaskGoStraightToCoord(mechanicPed, Config.MechanicPedRepair.RepairCoords, 1.0, 1.0, Config.MechanicPedRepair.RepairHeading, 1.0)

									TaskLeaveVehicle(player, vehicle, 0)
									SetVehicleDoorsLocked(vehicle, 2)
									FreezeEntityPosition(vehicle, true)

									RequestAnimDict("mini@repair")
									while not HasAnimDictLoaded("mini@repair") do
										Citizen.Wait(0)
									end

									Wait(5000)

									-- exports["btrp_progressbar"]:StartDelayedFunction({
									-- 	["text"] = "Lagar fordon...",
									-- 	["delay"] = 20000
									-- })
									exports["bgrp_progressbar"]:StartProgress("Lagar fordon...", 20000, function() end)
								
									SetEntityCoords(mechanicPed, Config.MechanicPedRepair.RepairCoords, false)
									SetEntityHeading(mechanicPed, Config.MechanicPedRepair.RepairHeading)
								
									TaskPlayAnim(mechanicPed, "mini@repair" ,"fixing_a_ped" ,8.0, -8.0, -1, 1, 0, false, false, false )
									FreezeEntityPosition(mechanicPed, true)
								
									Wait(20000)
								
									SetVehicleFixed(vehicle)
									SetVehicleDeformationFixed(vehicle)
									SetVehicleUndriveable(vehicle, false)
									SetVehicleEngineOn(vehicle,  true,  true)
									FreezeEntityPosition(vehicle, false)
									SetVehicleDoorsLocked(vehicle, 1)
								
									FreezeEntityPosition(mechanicPed, false)
									TaskGoStraightToCoord(mechanicPed, Config.MechanicPed.Coords, 1.0, 1.0, Config.MechanicPed.Heading, 1.0)
								
									Wait(5000)
								
									FreezeEntityPosition(mechanicPed, true)
									SetEntityCoords(mechanicPed, Config.MechanicPed.Coords)
									SetEntityHeading(mechanicPed, Config.MechanicPed.Heading)
								else
									ESX.ShowNotification("Du har inte råd.")
								end
							end)
						else
							ESX.ShowNotification("Du måste vara i ett fordon.")
						end
					end
				end)
			end
		end

		Wait(sleepThread)
	end
end)