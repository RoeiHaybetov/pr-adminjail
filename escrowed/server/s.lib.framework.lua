AJ = AJ or {}
AJ.Fw = {}

local Fw = AJ.Fw

local flavour, core

local function started(resource)
    local state = GetResourceState(resource)
    return state == 'started' or state == 'starting'
end

local function resolve()
    if flavour then return flavour end

    local forced = Config.Framework
    if forced == 'qbx' or forced == 'qb' or forced == 'esx' or forced == 'standalone' then
        flavour = forced
    elseif started('qbx_core') then
        flavour = 'qbx'
    elseif started('qb-core') then
        flavour = 'qb'
    elseif started('es_extended') then
        flavour = 'esx'
    else
        flavour = 'standalone'
    end

    if flavour == 'qb' then
        local ok, obj = pcall(function() return exports['qb-core']:GetCoreObject() end)
        core = ok and obj or nil
    elseif flavour == 'esx' then
        local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
        core = ok and obj or nil
    end

    return flavour
end

function Fw.Flavour()
    return resolve()
end

local function player(source)
    local f = resolve()
    local ok, p = pcall(function()
        if f == 'qbx' then return exports.qbx_core:GetPlayer(source) end
        if f == 'qb' then return core and core.Functions.GetPlayer(source) end
        if f == 'esx' then return core and core.GetPlayerFromId(source) end
    end)
    return ok and p or nil
end

--- True once a CHARACTER is loaded. A player sitting on a multicharacter screen is not
--- loaded, so the jail never pulls anyone out of character selection.
local readyStandalone, joinedAt = {}, {}

AddEventHandler('playerJoining', function()
    joinedAt[source] = GetGameTimer()
end)

function Fw.IsLoaded(source)
    if not AJ.Online(source) then return false end
    if resolve() ~= 'standalone' then return player(source) ~= nil end

    -- Standalone has no "character loaded" signal. The client's READY is the fast path, but
    -- a client that never sends it is not let off: 45 s after joining with a ped, it counts.
    if readyStandalone[source] then return true end
    if GetPlayerPed(source) == 0 then return false end
    local t = joinedAt[source]
    return t == nil or GetGameTimer() - t > 45000
end

function Fw.MarkReady(source)
    readyStandalone[source] = true
end

function Fw.Forget(source)
    readyStandalone[source] = nil
    joinedAt[source] = nil
end

--- Character name, when the framework has one. Logs show this next to the FiveM name.
function Fw.CharName(source)
    local f = resolve()
    local p = player(source)
    if not p then return nil end

    if f == 'esx' then
        local ok, name = pcall(function() return p.getName() end)
        return ok and type(name) == 'string' and name ~= '' and name or nil
    end

    local info = p.PlayerData and p.PlayerData.charinfo
    if type(info) == 'table' and info.firstname then
        return ('%s %s'):format(info.firstname, info.lastname or '')
    end
    return nil
end
