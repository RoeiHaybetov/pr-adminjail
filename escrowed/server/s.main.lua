AJ = AJ or {}

local Util, Access, Jail, Db, Log = AJ.Util, AJ.Access, AJ.Jail, AJ.Db, AJ.Log

-- ----------------------------------------------------------------------------
-- Config sanity — say what is wrong at boot instead of failing mid-sentence.

local function checkConfig()
    local problems = 0
    local function bad(msg) problems = problems + 1; AJ.Print('^1config: ' .. msg .. '^0') end

    if not Config.Yards[Config.Sentence.defaultYard] then
        bad(('Config.Sentence.defaultYard = %q is not a yard'):format(tostring(Config.Sentence.defaultYard)))
    end
    for key, yard in pairs(Config.Yards) do
        if not yard.spawn or not yard.leash or not yard.leash.center then bad(('yard %s needs spawn and leash'):format(key)) end
        if not yard.spots or #yard.spots == 0 then bad(('yard %s has no task spots'):format(key)) end
        if yard.bucket == 0 then bad(('yard %s uses bucket 0 — use bucket mode "public" for the main world instead'):format(key)) end
        if yard.leash and yard.leash.center then
            local function inside(c) return AJ.Util.Dist2D(c, yard.leash.center) <= yard.leash.radius end
            if yard.spawn and not inside(yard.spawn) then bad(('yard %s: spawn is outside its own leash'):format(key)) end
            for i, spot in ipairs(yard.spots or {}) do
                if not inside(spot.coords) then bad(('yard %s: spot %d is outside the leash'):format(key, i)) end
            end
            for i, d in ipairs(yard.dropoffs or {}) do
                if not inside(d) then bad(('yard %s: dropoff %d is outside the leash'):format(key, i)) end
            end
        end
    end
    for key, job in pairs(Config.Jobs) do
        if type(job.stages) ~= 'table' or #job.stages == 0 then bad(('job %s has no stages'):format(key)) end
        for i, stage in ipairs(job.stages or {}) do
            if type(stage.durationMs) ~= 'number' or stage.durationMs < 1000 then
                bad(('job %s stage %d needs durationMs >= 1000'):format(key, i))
            end
        end
    end
    if Config.Buckets.solitaryFrom > Config.Buckets.solitaryTo then bad('Buckets.solitaryFrom > solitaryTo') end
    return problems == 0
end

-- ----------------------------------------------------------------------------
-- Boot

CreateThread(function()
    if GetConvar('onesync', 'off') == 'off' then
        AJ.Print('^1OneSync is OFF. The jail checks positions and buckets on the server and needs OneSync.^0')
    end

    MySQL.ready(function()
        if not Db.Ensure() then
            AJ.Print('^1database unavailable — the jail is NOT running.^0')
            return
        end
        checkConfig()
        Access.Load()
        Access.Report()
        Log.Ready()
        Jail.Boot()
        AJ.Print(('ready · framework: %s'):format(AJ.Fw.Flavour()))
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= AJ.RESOURCE then return end
    Jail.Shutdown()
end)

AddEventHandler('playerDropped', function(reason)
    local source = source
    Jail.Dropped(source, reason)
    AJ.Identity.Forget(source)
    AJ.Tasks.Forget(source)
    AJ.Fw.Forget(source)
    Util.ClearRate(source)
end)

RegisterNetEvent(AJ.Event.READY, function()
    AJ.Fw.MarkReady(source)
end)

RegisterNetEvent(AJ.Event.DIED, function()
    local source = source
    if not Util.Rate(source, 'died') then return end
    Jail.Died(source)
end)

-- ----------------------------------------------------------------------------
-- Commands. Registered unrestricted; every handler checks access itself.

local function deny(source, key)
    if source == 0 then AJ.Print('this command is in-game only') return end
    AJ.Notify(source, key, nil, 'error')
end

local function gate(source, perm)
    if source == 0 then return nil end
    if not Util.Rate(source, 'cmd') then return nil end
    local actor, why = AJ.PanelGate(source)
    if not actor then deny(source, why) return nil end
    if perm and not Access.Can(actor, perm) then deny(source, 'error.no_permission') return nil end
    return actor
end

RegisterCommand(Config.Commands.panel, function(source)
    if not gate(source) then return end
    TriggerClientEvent(AJ.Event.PANEL, source)
end, false)

RegisterCommand(Config.Commands.jail, function(source, args)
    local actor = gate(source, 'jail')
    if not actor then return end

    local target = Util.Int(args[1], 1)
    local tasks = Util.Int(args[2], Config.Sentence.minTasks, actor.maxTasks)
    local reason = Util.Trim(table.concat(args, ' ', 3), Config.Sentence.reasonMaxLength)

    if not target or not tasks then
        AJ.Notify(source, 'cmd.jail_usage', { Config.Commands.jail, actor.maxTasks }, 'error')
        return
    end
    if not AJ.Online(target) then return deny(source, 'error.player_offline') end
    if reason == '' then
        if Config.Sentence.reasonRequired then return deny(source, 'error.reason_required') end
        reason = 'No reason given'
    end

    local ok, result = Jail.Create(actor, { source = target }, {
        tasks = tasks, yard = Config.Sentence.defaultYard, mode = Config.Buckets.default, reason = reason,
    })
    if not ok then return deny(source, result) end
    AJ.Notify(source, 'cmd.jailed', { GetPlayerName(target) or target, tasks }, 'success')
end, false)

RegisterCommand(Config.Commands.unjail, function(source, args)
    local actor = gate(source, 'release')
    if not actor then return end

    local target = Util.Int(args[1], 1)
    local reason = Util.Trim(table.concat(args, ' ', 2), Config.Sentence.reasonMaxLength)
    if not target then
        AJ.Notify(source, 'cmd.unjail_usage', { Config.Commands.unjail }, 'error')
        return
    end

    local s = Jail.ForSource(target) or (AJ.Online(target) and Jail.Find(AJ.Identity.Get(target)))
    if not s then return deny(source, 'error.no_sentence') end

    local ok, why = Access.MayTouch(actor, s)
    if not ok then return deny(source, why) end

    if reason == '' then
        if Config.Sentence.reasonRequired then return deny(source, 'error.reason_required') end
        reason = 'No reason given'
    end

    Jail.End(s, 'release', actor, reason)
    AJ.Notify(source, 'cmd.released', { s.name }, 'success')
end, false)

RegisterCommand(Config.Commands.tasks, function(source)
    if source == 0 then return end
    local s = Jail.ForSource(source)
    if not s then return AJ.Notify(source, 'jail.not_jailed', nil, 'inform') end
    AJ.Notify(source, 'jail.left', { Jail.Left(s), s.total }, 'inform')
end, false)

RegisterCommand(Config.Commands.spot, function(source)
    if source == 0 then return end
    local actor = Access.Get(source)
    if not actor or not actor.isOwner then return deny(source, 'error.no_permission') end
    TriggerClientEvent(AJ.Event.SPOT, source)
end, false)

-- ----------------------------------------------------------------------------
-- Exports for your other resources (read-only).

exports('IsJailed', function(source)
    return Jail.ForSource(tonumber(source) or -1) ~= nil
end)

exports('GetSentence', function(source)
    local s = Jail.ForSource(tonumber(source) or -1)
    return s and Jail.StatePayload(s) or nil
end)
