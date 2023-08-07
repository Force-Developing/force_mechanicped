Funcs = {}

Funcs.DrawMarker = function(markerData)
    DrawMarker(markerData['type'] or 1, markerData['pos'] or vector3(0.0, 0.0, 0.0), 0.0, 0.0, 0.0, (markerData['type'] == 6 and -90.0 or markerData['rotate'] and -180.0) or 0.0, 0.0, 0.0, markerData['sizeX'] or 1.0, markerData['sizeY'] or 1.0, markerData['sizeZ'] or 1.0, markerData['r'] or 1.0, markerData['g'] or 1.0, markerData['b'] or 1.0, 100, markerData['bob'] and true or false, false, 2, false, false, false, false)
end

Funcs.BlipDetails = function(blipName, blipText, color, route)
    BeginTextCommandSetBlipName("STRING")
    SetBlipColour(blipName, color)
    AddTextComponentString(blipText)
    SetBlipRoute(blipName, route)
    EndTextCommandSetBlipName(blipName)
end

Funcs.Draw3DText = function(coords, text)
    local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z)
    
    SetTextScale(0.38, 0.38)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 200)
    SetTextEntry("STRING")
    SetTextCentre(1)

    AddTextComponentString(text)
    DrawText(_x, _y)

    local factor = string.len(text) / 370
    DrawRect(_x, _y + 0.0125, 0.015 + factor, 0.03, 41, 11, 41, 68)
end