Config = {}

-- Prints extra info to the F8 / server console. Setup errors are always printed.
Config.Debug = false

-- "en", "sv" or "auto" (follows the replicated ox:locale convar: setr ox:locale "sv")
Config.Locale = "en"

-- "auto" (detected by the server: qbx_core, es_extended, qb-core), "esx", "qb", "qbx" or "custom"
Config.Framework = "auto"

-- "auto" (ox_target, then qb-target, else [E] + text UI), "ox_target", "qb-target" or "none" ([E] + text UI).
-- The repair is requested from the driver seat. If your target resource can't be used in a vehicle
-- (qb-target with Config.DisableInVehicle = true), set this to "none".
Config.Target = "auto"

-- What a repair costs. 0 makes it free.
Config.Price = 5000

-- Where the price is paid from: "cash", "bank" or "auto" (cash when the player has enough, otherwise bank)
Config.Account = "auto"

-- Jobs that count as mechanics. The NPC mechanic only works while at most Config.MaxMechanicsOnDuty
-- players with one of these jobs are on duty.
Config.MechanicJobs = { "mechanic", "mecano" }

-- 0 = the NPC refuses as soon as one player mechanic is on duty
Config.MaxMechanicsOnDuty = 0

-- Only count mechanics that are on duty (QBCore / QBox duty, ESX job.onDuty where your ESX version has it).
-- false counts every player with a mechanic job.
Config.CountOnlyOnDuty = true

-- How long a repair takes, in seconds
Config.RepairDuration = 20

-- Seconds after a finished repair before the same player can pay for the next one
Config.Cooldown = 60

-- Move the vehicle onto the location's coords and heading when the repair starts (lines it up with the mechanic)
Config.SnapVehicle = true

-- The player steps out and the vehicle is locked while the mechanic works (the 1.x behaviour).
-- false: the player stays in the driver seat.
Config.LeaveVehicle = true

-- Draw a ground marker where the vehicle has to stand
Config.DrawMarkers = true

--[[
  Repair locations. Each key is the location id.
  label  = title of the confirm dialog
  coords = vec4 where the vehicle stands during the repair (x, y, z, heading)
  radius = how close (meters) the vehicle has to be to coords (checked on the server)
  ped    = the mechanic: { model, coords = vec4 (his post), workCoords = vec4 (where he works on the vehicle,
           optional) }, or false for none
  blip   = { sprite, colour, scale } or false for no map blip
]]
Config.Locations = {
    burton = {
        label = "Mechanic",
        coords = vec4(-364.15, -147.94, 38.24, 210.0),
        radius = 3.0,
        ped = {
            model = "s_m_y_xmech_01",
            coords = vec4(-357.92, -151.78, 37.25, 30.0),
            workCoords = vec4(-363.03, -150.32, 37.23, 30.0),
        },
        blip = { sprite = 544, colour = 0, scale = 0.7 },
    },
}
