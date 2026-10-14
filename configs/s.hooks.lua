--[[
    pr — ADMINJAIL hooks

    Server-only, open source, yours to edit. These are the few places where the jail has to
    talk to the rest of your server. Every hook runs inside a pcall: a broken hook is logged
    and skipped, it never breaks a sentence.
]]

Hooks = Hooks or {}

local function started(resource)
    return GetResourceState(resource) == 'started'
end

--- Bring a dead inmate back. Called when an inmate dies inside the yard (rare — inmates are
--- invincible by default). The client also resurrects itself locally after this, so this
--- only needs to clear your medical script's own "dead" state.
function Hooks.Revive(source)
    if started('qbx_medical') then
        local ok = pcall(function() exports.qbx_medical:Revive(source) end)
        if not ok then TriggerClientEvent('qbx_medical:client:playerRevived', source) end
    end
    if started('qb-ambulancejob') then
        TriggerClientEvent('hospital:client:Revive', source)
    end
    if started('esx_ambulancejob') then
        TriggerClientEvent('esx_ambulancejob:revive', source)
    end
    if started('wasabi_ambulance') then
        TriggerClientEvent('wasabi_ambulance:revive', source)
    end
end

--- Runs after a player is placed into the yard (fresh sentence, reconnect or transfer).
--- `sentence` is a read-only copy: id, total, done, left, penalty, escapes, reason, staff,
--- yard, yardLabel, mode, bucket.
function Hooks.OnJailed(source, sentence)
    -- e.g. TriggerClientEvent('my-phone:client:disable', source, true)
end

--- Runs after a player leaves the yard, served or released — including a player released
--- while on a character screen, and one moved out on join after a release while offline
--- (then `sentence` only has `id`). `how` is 'complete' or 'release'.
function Hooks.OnReleased(source, sentence, how)
    -- e.g. TriggerClientEvent('my-phone:client:disable', source, false)
end
