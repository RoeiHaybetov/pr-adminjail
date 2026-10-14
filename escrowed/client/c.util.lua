AJ = AJ or {}
AJ.Cl = {}

local Cl = AJ.Cl

function Cl.Notify(key, args, kind)
    local ok, text = pcall(function()
        if args and #args > 0 then return locale(key, table.unpack(args)) end
        return locale(key)
    end)
    if not ok or type(text) ~= 'string' then text = key end
    lib.notify({ title = locale('ui.title'), description = text, type = kind or 'inform', duration = 6000 })
end

RegisterNetEvent(AJ.Event.NOTIFY, function(key, args, kind)
    if type(key) ~= 'string' then return end
    Cl.Notify(key, type(args) == 'table' and args or nil, kind)
end)

--- Only the strings the interface needs, flattened (ox_lib already flattens with dots).
function Cl.Locales()
    local out = {}
    for key, text in pairs(lib.getLocales() or {}) do
        if type(text) == 'string' then out[key] = text end
    end
    return out
end

function Cl.LoadModel(name, timeout)
    local hash = type(name) == 'number' and name or joaat(name)
    if not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + (timeout or 5000)
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(0)
    end
    return hash
end

function Cl.LoadDict(dict, timeout)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + (timeout or 5000)
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > deadline then return false end
        Wait(0)
    end
    return true
end

--- A LOCAL (non-networked) prop. It never trips entity lockdown and nobody else sees it.
function Cl.LocalProp(model, coords, placeOnGround)
    local hash = Cl.LoadModel(model)
    if not hash then return nil end
    local obj = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if placeOnGround then PlaceObjectOnGroundProperly(obj) end
    FreezeEntityPosition(obj, true)
    SetEntityCollision(obj, false, false)
    return obj
end

function Cl.AttachProp(ped, def)
    local hash = Cl.LoadModel(def.model)
    if not hash then return nil end
    local c = GetEntityCoords(ped)
    local obj = CreateObject(hash, c.x, c.y, c.z + 0.2, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    local p, r = def.pos or vec3(0, 0, 0), def.rot or vec3(0, 0, 0)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, def.bone or 28422),
        p.x, p.y, p.z, r.x, r.y, r.z, true, true, false, true, 1, true)
    SetEntityCollision(obj, false, false)
    return obj
end

function Cl.Delete(entity)
    if entity and DoesEntityExist(entity) then
        DetachEntity(entity, true, false)
        DeleteEntity(entity)
    end
end

function Cl.Vec(t)
    if not t then return nil end
    return vec3(t.x + 0.0, t.y + 0.0, t.z + 0.0)
end
