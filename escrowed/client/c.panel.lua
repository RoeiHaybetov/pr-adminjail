AJ = AJ or {}

local Cl = AJ.Cl
local open = false

local function close()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'panel', data = false })
end

RegisterNetEvent(AJ.Event.PANEL, function()
    if open then return end
    open = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'panel', data = true, locales = Cl.Locales() })
end)

--- The panel's single door. The server re-checks who is calling on every request; this only
--- relays `action` + `payload` and never decides anything itself.
RegisterNUICallback('panel', function(data, cb)
    if not open or type(data) ~= 'table' or type(data.action) ~= 'string' then
        return cb({ ok = false, error = 'error.generic' })
    end
    local ok, result = pcall(lib.callback.await, AJ.Callback.PANEL, false, data.action, data.payload)
    cb(ok and type(result) == 'table' and result or { ok = false, error = 'error.generic' })
end)

RegisterNUICallback('close', function(_, cb)
    close()
    cb({ ok = true })
end)

RegisterNUICallback('copy', function(data, cb)
    if type(data) == 'table' and type(data.text) == 'string' and #data.text <= 256 then
        lib.setClipboard(data.text)
    end
    cb({ ok = true })
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= AJ.RESOURCE then return end
    if open then SetNuiFocus(false, false) end
end)
