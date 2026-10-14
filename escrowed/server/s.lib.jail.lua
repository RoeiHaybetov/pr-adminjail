AJ = AJ or {}
AJ.Jail = {}

local Jail = AJ.Jail
local Util, Identity, Log, Db = AJ.Util, AJ.Identity, AJ.Log, AJ.Db

--- Active sentences, keyed by id. The database is the source of truth; this is its cache.
local sentences = {}

--- Online inmates, keyed by server id.
---   id          sentence id
---   placedAt    mono time of the last PLACE, nil = not placed yet
---   graceUntil  mono time the leash starts biting again
---   settled     the server has seen them inside the leash since the last placement
---   everSettled the server has seen them inside the leash at least once since attaching —
---               from then on every exit is an escape, even right after a re-placement
---   freeUntil   mono time until which the first exit is forgiven (spawn selectors after a
---               reconnect teleport the ped once; that is not an escape)
---   forced      server force-placements in a row without ever seeing them inside
---   lastPenalty mono time of the last escape penalty
---   deadSince   mono time the server first saw them dead
---   task        the current task (s.lib.tasks.lua)
local inmates = {}

--- Players the join scan has already looked at, keyed by server id.
local scanned = {}

--- Recently disconnected players, newest first — jailable from the panel with their full
--- identifiers even though they are gone.
local recent = {}
local RECENT_MAX = 40

local configuredBuckets = {}

--- Identifiers and solitary buckets held by a Jail.Create that is waiting on the database,
--- so two staff jailing the same person in the same instant cannot create two sentences.
local creating, reservedSolitary = {}, {}

local FREE_EXIT_MS = 300000

-- ----------------------------------------------------------------------------
-- Shape

local function fromRow(row)
    return {
        id = row.id, status = row.status,
        name = row.name,
        ids = {
            name = row.name, char = row.char_name,
            license = row.license, discord = row.discord, steam = row.steam, fivem = row.fivem,
        },
        total = tonumber(row.tasks_total) or 0,
        done = tonumber(row.tasks_done) or 0,
        penalty = tonumber(row.penalty_tasks) or 0,
        escapes = tonumber(row.escapes) or 0,
        yard = row.yard, mode = row.bucket_mode, bucket = tonumber(row.bucket) or 0,
        reason = row.reason,
        staffDiscord = row.staff_discord, staffName = row.staff_name,
        offline = row.offline == 1 or row.offline == true,
        createdAt = row.created_at,
        source = nil,
    }
end

function Jail.Left(s) return math.max(0, s.total - s.done) end

--- Has this person ever actually stood in the yard for this sentence? Only then do they need
--- moving out after a release while they are away.
function Jail.WasInYard(s)
    return not s.offline or s.done > 0 or s.escapes > 0
end

--- What the panel sees about a sentence.
function Jail.Public(s, withIds)
    return {
        id = s.id, name = s.name, char = s.ids.char, source = s.source,
        online = s.source ~= nil,
        total = s.total, done = s.done, left = Jail.Left(s), penalty = s.penalty, escapes = s.escapes,
        yard = s.yard, yardLabel = Config.Yards[s.yard] and Config.Yards[s.yard].label or s.yard,
        mode = s.mode, bucket = s.bucket, reason = s.reason,
        staffName = s.staffName, createdAt = s.createdAt, offline = s.offline,
        discord = s.ids.discord,
        ids = withIds and s.ids or nil,
        task = s.source and inmates[s.source] and inmates[s.source].task
            and AJ.Tasks.Brief(inmates[s.source].task) or nil,
    }
end

function Jail.All() return sentences end
function Jail.Get(id) return sentences[tonumber(id) or -1] end
function Jail.Inmate(source) return inmates[source] end

function Jail.ForSource(source)
    local inmate = inmates[source]
    return inmate and sentences[inmate.id] or nil
end

--- The active sentence of whoever owns these identifiers, if any.
function Jail.Find(ids)
    for _, s in pairs(sentences) do
        for _, kind in ipairs(Identity.MATCH) do
            if ids[kind] and s.ids[kind] == ids[kind] then return s end
        end
    end
    return nil
end

function Jail.Recent() return recent end

-- ----------------------------------------------------------------------------
-- Buckets

local function configureBucket(bucket, yard, mode)
    if bucket == 0 or configuredBuckets[bucket] then return end
    if mode ~= 'yard' and mode ~= 'solitary' then return end
    configuredBuckets[bucket] = true
    if yard.lockdown then SetRoutingBucketEntityLockdownMode(bucket, yard.lockdown) end
    SetRoutingBucketPopulationEnabled(bucket, yard.population == true)
end

local function solitaryBucket(exceptId)
    local used = {}
    for id, s in pairs(sentences) do
        if id ~= exceptId and s.mode == 'solitary' then used[s.bucket] = true end
    end
    local from, to = Config.Buckets.solitaryFrom, Config.Buckets.solitaryTo
    for b = from, to do
        if not used[b] and not reservedSolitary[b] then return b end
    end
    return nil
end

--- Turns (mode, yard, custom number) into a real bucket, or nil + error key.
function Jail.ResolveBucket(mode, yardKey, custom, exceptId)
    local yard = Config.Yards[yardKey]
    if not yard then return nil, 'error.bad_yard' end
    if not Config.Buckets.allowed[mode] then return nil, 'error.bad_bucket_mode' end

    if mode == 'yard' then return yard.bucket end
    if mode == 'public' then return 0 end
    if mode == 'solitary' then
        local b = solitaryBucket(exceptId)
        if not b then return nil, 'error.no_solitary' end
        return b
    end

    local b = Util.Int(custom, Config.Buckets.customMin, Config.Buckets.customMax)
    if not b then return nil, 'error.bad_bucket' end
    return b
end

-- ----------------------------------------------------------------------------
-- Client sync

function Jail.StatePayload(s)
    local yard = Config.Yards[s.yard]
    return {
        id = s.id, total = s.total, done = s.done, left = Jail.Left(s),
        penalty = s.penalty, escapes = s.escapes,
        reason = s.reason, staff = s.staffName,
        yard = s.yard, yardLabel = yard and yard.label or s.yard,
        mode = s.mode, bucket = s.bucket,
        penaltyTasks = Config.AntiEscape.penaltyTasks,
    }
end

function Jail.Sync(s)
    if s.source then TriggerClientEvent(AJ.Event.STATE, s.source, Jail.StatePayload(s)) end
end

--- The server just moved them, so the task's travel-time check restarts from the spawn —
--- otherwise our own teleport would read as theirs.
local function resetTravel(inmate, yard)
    if inmate.task then
        inmate.task.from = yard.spawn
        inmate.task.issuedAt = AJ.Mono()
    end
end

--- `untrusted`: the reason for this move came from the client (a reported death). The ped is
--- still put back, but no anti-escape state is touched — no fresh grace period, no settled
--- reset, no new travel origin — so spamming the event buys nothing.
local function place(source, inmate, s, revive, untrusted)
    local yard = Config.Yards[s.yard]
    if not untrusted then
        inmate.placedAt = AJ.Mono()
        inmate.graceUntil = inmate.placedAt + Config.AntiEscape.placeGraceMs
        inmate.settled = false
        resetTravel(inmate, yard)
    end
    TriggerClientEvent(AJ.Event.PLACE, source, Util.Vec(yard.spawn), revive == true)
end

--- Moves the ped on the server too — a modified client can ignore PLACE.
local function forceToSpawn(source, yard)
    local ped = GetPlayerPed(source)
    if ped == 0 then return end
    local spawn = yard.spawn
    SetEntityCoords(ped, spawn.x, spawn.y, spawn.z, false, false, false, false)
    SetEntityHeading(ped, spawn.w or 0.0)
end

local function cinematic(source, kind, data)
    if Config.Hud.cinematic == false then return end
    TriggerClientEvent(AJ.Event.CINEMATIC, source, kind, data)
end

-- ----------------------------------------------------------------------------
-- Putting a player in and taking them out

--- Puts an online, loaded player into their sentence: bucket, state, placement, task.
function Jail.Attach(source, s, fresh)
    local yard = Config.Yards[s.yard]
    if not yard then
        AJ.Print(('^1sentence #%d points at yard %q which no longer exists — using %q^0')
            :format(s.id, tostring(s.yard), Config.Sentence.defaultYard))
        s.yard = Config.Sentence.defaultYard
        yard = Config.Yards[s.yard]
        Db.UpdateSentence(s.id, { yard = s.yard })
    end

    -- A player can only ever hold one sentence. If a different one was attached, detach it
    -- quietly first (it stays active and re-attaches by identifier).
    local prior = inmates[source]
    if prior and prior.id ~= s.id then
        local other = sentences[prior.id]
        if other then other.source = nil end
        AJ.Tasks.Clear(source)
    end

    s.source = source
    s.offline = false
    inmates[source] = {
        id = s.id, settled = false, everSettled = false, forced = 0, lastPenalty = 0,
        freeUntil = AJ.Mono() + FREE_EXIT_MS,
    }

    configureBucket(s.bucket, yard, s.mode)
    SetPlayerRoutingBucket(source, s.bucket)

    local state = Player(source).state
    state:set('adminJailed', true, true)

    local ped = GetPlayerPed(source)
    if ped ~= 0 and Config.AntiEscape.disarm then RemoveAllPedWeapons(ped, true) end

    Jail.Sync(s)
    place(source, inmates[source], s)

    if fresh then
        cinematic(source, 'sentenced', { tasks = Jail.Left(s), reason = s.reason, staff = s.staffName, yard = yard.label })
    else
        AJ.Notify(source, 'jail.resumed', { Jail.Left(s) }, 'error')
    end

    AJ.Tasks.Assign(source, inmates[source], s)
    AJ.Hook('OnJailed', source, Jail.StatePayload(s))
end

--- Takes an online player out of the yard and drops them at the release point.
local function detach(source, s, how)
    AJ.Tasks.Clear(source)
    inmates[source] = nil
    scanned[source] = nil
    s.source = nil

    SetPlayerRoutingBucket(source, Config.Buckets.releaseBucket or 0)
    Player(source).state:set('adminJailed', false, true)

    TriggerClientEvent(AJ.Event.STATE, source, false)
    TriggerClientEvent(AJ.Event.PLACE, source, Util.Vec(Config.Release.coords), false)
    cinematic(source, how == 'complete' and 'served' or 'released', { tasks = s.done })

    AJ.Hook('OnReleased', source, Jail.StatePayload(s), how)
end

--- Ends a sentence. `how` = 'complete' | 'release'.
function Jail.End(s, how, actor, reason)
    if not sentences[s.id] then return false end
    sentences[s.id] = nil

    local status = how == 'complete' and 'completed' or 'released'
    local online = s.source ~= nil and AJ.Online(s.source)
    local inmateIds = online and Identity.Get(s.source) or s.ids

    -- Online but on a character screen: never touch a multicharacter bucket. Drop them from
    -- the yard now and let the join scan move them out once a character loads.
    if online and not AJ.Fw.IsLoaded(s.source) then
        local src = s.source
        AJ.Tasks.Clear(src)
        inmates[src] = nil
        scanned[src] = nil
        Player(src).state:set('adminJailed', false, true)
        TriggerClientEvent(AJ.Event.STATE, src, false)
        -- OnReleased fires from the join move-out once a character loads, not here.
        s.source = nil
        online = false
    end

    -- Only someone who actually stood in the yard needs moving out on their next join. A
    -- sentence cancelled before it was ever served leaves the player wherever they are.
    Db.UpdateSentence(s.id, {
        status = status, ended_at = AJ.Now(), tasks_done = s.done, tasks_total = s.total,
        ended_by_discord = actor and actor.discord or nil,
        ended_by_name = actor and actor.name and Util.Cut(actor.name, 64) or nil,
        end_reason = reason,
        release_pending = (not online and Jail.WasInYard(s)) and 1 or 0,
    })
    Db.Event(s.id, status, actor, reason or (how == 'complete' and ('served %d tasks'):format(s.done) or nil))

    if online then detach(s.source, s, how) end

    if how == 'complete' then
        Log.Send('complete', {
            title = 'Sentence served',
            description = ('Finished **%d** community-service task(s). Walked out.'):format(s.done),
            inmate = inmateIds, sentenceId = s.id,
            fields = {
                { 'Tasks', ('%d (incl. %d penalty)'):format(s.total, s.penalty) },
                { 'Escape attempts', s.escapes },
                { 'Originally by', s.staffName or '—' },
                { 'Reason', s.reason, false },
            },
        })
    else
        Log.Send('release', {
            title = 'Sentence cancelled',
            description = online and 'Released from the yard.'
                or (Jail.WasInYard(s) and 'Released while offline — moved out on next join.' or 'Released before serving any of it.'),
            inmate = inmateIds, staff = actor and actor.ids or nil, staffRole = 'Released by',
            sentenceId = s.id,
            fields = {
                { 'Progress', ('%d / %d'):format(s.done, s.total) },
                { 'Tasks left', Jail.Left(s) },
                { 'Release reason', reason, false },
                { 'Original reason', s.reason, false },
            },
        })
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Creating

--- target: { source = n } | { ids = snapshot }  (offline)
--- opts:   { tasks, yard, mode, bucket, reason }
function Jail.Create(actor, target, opts)
    local ids, online
    if target.source then
        if not AJ.Online(target.source) then return false, 'error.player_offline' end
        ids, online = Identity.Get(target.source), true
    else
        ids, online = target.ids, false
    end

    local existing = Jail.Find(ids)
    if existing then return false, 'error.already_jailed', existing.id end

    -- Another Create for this person is waiting on the database right now.
    local keys = {}
    for _, kind in ipairs(Identity.MATCH) do
        if ids[kind] then
            local key = kind .. ':' .. ids[kind]
            if creating[key] then return false, 'error.already_jailed', '?' end
            keys[#keys + 1] = key
        end
    end

    local fake = { ids = ids }
    local mayTouch, why = AJ.Access.MayTouch(actor, fake)
    if not mayTouch then return false, why end

    local yardKey = opts.yard or Config.Sentence.defaultYard
    local bucket, err = Jail.ResolveBucket(opts.mode, yardKey, opts.bucket)
    if not bucket then return false, err end

    local loaded = online and AJ.Fw.IsLoaded(target.source)
    local now = AJ.Now()
    local row = {
        status = 'active',
        name = Util.Cut(ids.name or 'unknown', 64), char_name = ids.char and Util.Cut(ids.char, 64) or nil,
        license = ids.license, discord = ids.discord, steam = ids.steam, fivem = ids.fivem,
        tasks_total = opts.tasks, tasks_done = 0, penalty_tasks = 0, escapes = 0,
        yard = yardKey, bucket_mode = opts.mode, bucket = bucket,
        reason = opts.reason, staff_discord = actor.discord, staff_name = Util.Cut(actor.name or '', 64),
        -- 1 until the sentence actually reaches the yard (see Jail.End / release_pending).
        offline = loaded and 0 or 1, release_pending = 0,
        created_at = now, updated_at = now,
    }

    -- Nothing has yielded since Jail.Find: reserve before the database round-trip.
    for i = 1, #keys do creating[keys[i]] = true end
    if opts.mode == 'solitary' then reservedSolitary[bucket] = true end

    local ok, id = pcall(Db.InsertSentence, row)

    for i = 1, #keys do creating[keys[i]] = nil end
    if opts.mode == 'solitary' then reservedSolitary[bucket] = nil end

    if not ok or not id then return false, 'error.database' end
    row.id = id

    local s = fromRow(row)
    sentences[id] = s

    -- The insert yielded: the target may have dropped or gone to a character screen since.
    if loaded and not AJ.Fw.IsLoaded(target.source) then
        loaded = false
        s.offline = true
        Db.UpdateSentence(id, { offline = 1 })
    end
    Db.Event(id, 'jail', actor, ('%d tasks · %s · bucket %d (%s) · %s'):format(opts.tasks, yardKey, bucket, opts.mode, opts.reason))

    if loaded then
        Jail.Attach(target.source, s, true)
    else
        -- Offline (or on a character screen) — the join scan attaches them when they load.
        for src in pairs(scanned) do scanned[src] = nil end
    end

    Log.Send('jail', {
        title = online and 'Player jailed' or 'Offline player jailed',
        description = ('Sentenced to **%d** community-service task(s).'):format(opts.tasks),
        inmate = ids, staff = actor.ids, staffRole = 'Jailed by', sentenceId = id,
        fields = {
            { 'Tasks', opts.tasks },
            { 'Yard', Config.Yards[yardKey].label },
            { 'Bucket', ('%d · %s'):format(bucket, opts.mode) },
            { 'Reason', opts.reason, false },
        },
    })

    return true, s
end

-- ----------------------------------------------------------------------------
-- Changing

--- op: 'add' | 'remove' | 'set' (set = tasks LEFT). Returns ok, err.
function Jail.Modify(actor, s, op, amount, reason)
    local before = Jail.Left(s)
    local left
    if op == 'add' then left = before + amount
    elseif op == 'remove' then left = before - amount
    elseif op == 'set' then left = amount
    else return false, 'error.bad_request' end

    left = math.max(0, left)
    if left > actor.maxTasks and left > before then return false, 'error.over_limit' end

    s.total = s.done + left
    Db.UpdateSentence(s.id, { tasks_total = s.total })
    Db.Event(s.id, 'modify', actor, ('%s %d · %d -> %d left · %s'):format(op, amount, before, left, reason))

    Log.Send('modify', {
        title = 'Sentence changed',
        description = ('Tasks left **%d → %d** (%s %d).'):format(before, left, op, amount),
        inmate = s.source and Identity.Get(s.source) or s.ids, staff = actor.ids, staffRole = 'Changed by',
        sentenceId = s.id,
        fields = { { 'Progress', ('%d / %d'):format(s.done, s.total) }, { 'Reason', reason, false } },
    })

    if s.source then
        AJ.Notify(s.source, left > before and 'jail.tasks_added' or 'jail.tasks_removed', { math.abs(left - before), left },
            left > before and 'error' or 'success')
    end

    if left == 0 then
        -- Staff taking it to zero is a release, not a served sentence.
        Jail.End(s, 'release', actor, reason)
    else
        Jail.Sync(s)
    end
    return true
end

function Jail.Transfer(actor, s, yardKey, mode, custom, reason)
    local bucket, err = Jail.ResolveBucket(mode, yardKey, custom, s.id)
    if not bucket then return false, err end

    local before = ('%s · %d (%s)'):format(s.yard, s.bucket, s.mode)
    s.yard, s.mode, s.bucket = yardKey, mode, bucket
    Db.UpdateSentence(s.id, { yard = yardKey, bucket_mode = mode, bucket = bucket })

    local after = ('%s · %d (%s)'):format(yardKey, bucket, mode)
    Db.Event(s.id, 'transfer', actor, ('%s -> %s · %s'):format(before, after, reason))

    Log.Send('transfer', {
        title = 'Inmate moved',
        description = ('%s → %s'):format(before, after),
        inmate = s.source and Identity.Get(s.source) or s.ids, staff = actor.ids, staffRole = 'Moved by',
        sentenceId = s.id, fields = { { 'Reason', reason, false } },
    })

    if s.source and AJ.Fw.IsLoaded(s.source) then
        Jail.Attach(s.source, s, false)
    elseif s.source then
        -- On a character screen: let go now, the join scan attaches them to the new yard
        -- and bucket once a character loads (and re-sends their state then).
        local src = s.source
        AJ.Tasks.Clear(src)
        inmates[src] = nil
        scanned[src] = nil
        Player(src).state:set('adminJailed', false, true)
        TriggerClientEvent(AJ.Event.STATE, src, false)
        s.source = nil
    end
    return true
end

--- Escape attempt. Adds penalty tasks (rate-limited, capped), logs, and puts them back.
function Jail.Escape(source, kind, detail)
    local inmate, s = inmates[source], Jail.ForSource(source)
    if not inmate or not s then return end

    local now = AJ.Mono()
    local cfg = Config.AntiEscape
    local added = 0

    if now - (inmate.lastPenalty or 0) >= cfg.penaltyCooldownMs then
        inmate.lastPenalty = now
        s.escapes = s.escapes + 1

        local add = cfg.penaltyTasks or 0
        if cfg.maxPenaltyTasks and cfg.maxPenaltyTasks > 0 then
            add = math.max(0, math.min(add, cfg.maxPenaltyTasks - s.penalty))
        end
        if add > 0 then
            s.total, s.penalty, added = s.total + add, s.penalty + add, add
        end

        Db.UpdateSentence(s.id, { tasks_total = s.total, penalty_tasks = s.penalty, escapes = s.escapes })
        Db.Event(s.id, 'escape', nil, ('%s · +%d · %s'):format(kind, added, detail or ''))

        Log.Send('escape', {
            title = 'Escape attempt',
            description = ('**%s** — %s'):format(kind, detail or 'dragged back'),
            inmate = Identity.Get(source), sentenceId = s.id,
            fields = {
                { 'Penalty', added > 0 and ('+%d tasks'):format(added) or 'none (cap reached)' },
                { 'Tasks left', Jail.Left(s) },
                { 'Attempts', s.escapes },
            },
        })

        AJ.Notify(source, added > 0 and 'jail.escape_penalty' or 'jail.escape', { added }, 'error')
        Jail.Sync(s)
    end

    place(source, inmate, s)
    forceToSpawn(source, Config.Yards[s.yard])
end

--- Called by the task module after a task's last stage is accepted.
function Jail.Progress(source, s, jobKey)
    s.done = s.done + 1
    Db.UpdateSentence(s.id, { tasks_done = s.done })

    if Config.Logging.events and Config.Logging.events.progress then
        Log.Send('progress', {
            title = 'Task done',
            description = ('%s — %d / %d'):format(Config.Jobs[jobKey] and Config.Jobs[jobKey].label or jobKey, s.done, s.total),
            sentenceId = s.id, fields = { { 'Inmate', ('%s (ID %d)'):format(s.name, source) } },
        })
    end

    if s.done >= s.total then
        Jail.End(s, 'complete', nil, nil)
        return true
    end
    Jail.Sync(s)
    return false
end

-- ----------------------------------------------------------------------------
-- Watchdog — bucket, leash, vehicles, weapons, death. Every check is server-side.

--- `serverSaw`: the watchdog saw the death itself. A client-reported death is trusted for
--- the revive (worst case: a pointless revive) but not for resetting anti-cheat state.
local function revive(source, inmate, s, serverSaw)
    inmate.deadSince = nil
    AJ.Hook('Revive', source)
    place(source, inmate, s, true, not serverSaw)
    if serverSaw then forceToSpawn(source, Config.Yards[s.yard]) end
end

function Jail.Died(source)
    local inmate, s = inmates[source], Jail.ForSource(source)
    if not inmate or not s then return end
    SetTimeout(2500, function()
        if inmates[source] == inmate then revive(source, inmate, s, false) end
    end)
end

--- The first exit after an attach is forgiven once: spawn selectors and housing scripts move
--- a reconnecting player one time, and that is not them running. They still go back.
local function forgive(source, inmate, s, now, what)
    if now >= (inmate.freeUntil or 0) then return false end
    inmate.freeUntil = 0
    Db.Event(s.id, 'escape', nil, ('%s · forgiven (first exit after joining) · +0'):format(what))
    place(source, inmate, s)
    forceToSpawn(source, Config.Yards[s.yard])
    return true
end

local function watch(source, inmate, s)
    if not AJ.Fw.IsLoaded(source) then
        -- Character screen or logging out — leave them alone, re-place once they load.
        inmate.placedAt = nil
        return
    end

    if not inmate.placedAt then
        -- A character (re)loaded: treat it like a fresh arrival — spawn selectors move them once.
        inmate.everSettled, inmate.forced = false, 0
        inmate.freeUntil = AJ.Mono() + FREE_EXIT_MS
        SetPlayerRoutingBucket(source, s.bucket)
        place(source, inmate, s)
        return
    end

    local ped = GetPlayerPed(source)
    if ped == 0 or not DoesEntityExist(ped) then return end

    local now = AJ.Mono()
    local cfg = Config.AntiEscape
    local yard = Config.Yards[s.yard]

    -- Seen inside once = every later exit counts, even straight after a re-placement.
    local accountable = inmate.settled or inmate.everSettled

    if GetPlayerRoutingBucket(source) ~= s.bucket then
        local was = GetPlayerRoutingBucket(source)
        SetPlayerRoutingBucket(source, s.bucket)
        if accountable and not forgive(source, inmate, s, now, 'bucket') then
            Jail.Escape(source, 'bucket', ('moved to bucket %d'):format(was))
        elseif not accountable then
            place(source, inmate, s)
        end
        return
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        ClearPedTasksImmediately(ped)
        if accountable then Jail.Escape(source, 'vehicle', 'got into a vehicle') end
        return
    end

    if GetEntityHealth(ped) <= 0 then
        inmate.deadSince = inmate.deadSince or now
        if now - inmate.deadSince > 6000 then revive(source, inmate, s, true) end
        return
    end
    inmate.deadSince = nil

    if cfg.disarm and GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED` then
        RemoveAllPedWeapons(ped, true)
    end

    local coords = GetEntityCoords(ped)
    local leash = yard.leash
    local outside = Util.Dist2D(coords, leash.center) > leash.radius or coords.z < leash.center.z - 40.0

    if not outside then
        inmate.settled, inmate.everSettled, inmate.forced = true, true, 0
        -- Inside and quiet for 30 s: they have arrived, the one free exit is gone.
        if inmate.freeUntil > 0 and now - inmate.placedAt > 30000 then inmate.freeUntil = 0 end
        return
    end

    if accountable then
        if now >= inmate.graceUntil and not forgive(source, inmate, s, now, 'leash') then
            Jail.Escape(source, 'leash', ('%.0fm from the yard'):format(Util.Dist2D(coords, leash.center)))
        end
    elseif now - inmate.placedAt >= cfg.forcePlaceAfterMs then
        -- The client never moved itself in. The server does it — and a client that keeps
        -- leaving before the server ever sees it inside is escaping, not lagging.
        inmate.forced = (inmate.forced or 0) + 1
        if inmate.forced >= 3 then
            inmate.forced = 0
            if not forgive(source, inmate, s, now, 'leash') then
                Jail.Escape(source, 'leash', 'never stayed in the yard after being placed')
            end
            return
        end
        forceToSpawn(source, yard)
        inmate.placedAt = now
        inmate.graceUntil = now + cfg.placeGraceMs
        resetTravel(inmate, yard)
        AJ.Debug(('force-placed %d into %s'):format(source, s.yard))
    end
end

local function watchdog()
    while true do
        Wait(Config.AntiEscape.watchdogMs)
        for source, inmate in pairs(inmates) do
            local s = sentences[inmate.id]
            if not AJ.Online(source) then
                inmates[source] = nil
            elseif not s then
                -- Their sentence ended while it was attached elsewhere. Release them properly
                -- instead of leaving a jailed client in a jail bucket.
                AJ.Tasks.Clear(source)
                inmates[source] = nil
                scanned[source] = nil
                Player(source).state:set('adminJailed', false, true)
                TriggerClientEvent(AJ.Event.STATE, source, false)
                if AJ.Fw.IsLoaded(source) then
                    SetPlayerRoutingBucket(source, Config.Buckets.releaseBucket or 0)
                    TriggerClientEvent(AJ.Event.PLACE, source, Util.Vec(Config.Release.coords), false)
                end
            else
                local ok, err = pcall(watch, source, inmate, s)
                if not ok then AJ.Print(('^1watchdog error for %d: %s^0'):format(source, tostring(err))) end
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Join scan — attaches sentences to players once their character is loaded, and moves
-- out anyone whose sentence ended while they were offline.

local function scanOne(source)
    local ids = Identity.Get(source)
    local s = Jail.Find(ids)

    if s then
        -- Already being served by another online session sharing an identifier (same
        -- Discord on two PCs, a ghost session after a crash). One body serves a sentence;
        -- this one is retried every scan and attaches once the other is gone.
        local other = s.source
        if other and other ~= source and AJ.Online(other) and inmates[other] and inmates[other].id == s.id then
            scanned[source] = nil
            return
        end

        -- Staff jailed an owner by licence / Steam / FiveM id while the owner was offline —
        -- protectOwners could not see it then. It can now.
        if Config.Sentence.protectOwners ~= false and AJ.Access.IsOwnerId(ids.discord)
            and not AJ.Access.IsOwnerId(s.staffDiscord) then
            Jail.End(s, 'release', nil, 'owner is protected (jailed by identifier while offline)')
            return
        end

        -- Older ended sentences of this person must not teleport them again later. Not awaited:
        -- nothing may yield between Jail.Find and Jail.Attach.
        Db.ClearPendingFor(ids)

        local wasOffline = s.offline
        Db.BackfillIdentity(s.id, ids)
        for _, kind in ipairs(Identity.MATCH) do s.ids[kind] = s.ids[kind] or ids[kind] end
        s.ids.char = ids.char or s.ids.char
        if s.offline and tostring(s.name):sub(1, 8) == 'offline:' then s.name, s.ids.name = ids.name, ids.name end
        s.offline = false

        Jail.Attach(source, s, wasOffline)
        Db.Event(s.id, 'reconnect', nil, ('%d left'):format(Jail.Left(s)))
        Log.Send('reconnect', {
            title = wasOffline and 'Offline sentence picked up' or 'Inmate reconnected',
            description = ('Back in the yard with **%d** task(s) left.'):format(Jail.Left(s)),
            inmate = ids, sentenceId = s.id,
        })
        return
    end

    for _, row in ipairs(Db.PendingReleases(ids)) do
        Db.ClearPending(row.id)
        SetPlayerRoutingBucket(source, Config.Buckets.releaseBucket or 0)
        TriggerClientEvent(AJ.Event.PLACE, source, Util.Vec(Config.Release.coords), false)
        AJ.Notify(source, row.status == 'completed' and 'jail.served_offline' or 'jail.released_offline', nil, 'success')
        AJ.Hook('OnReleased', source, { id = row.id }, row.status == 'completed' and 'complete' or 'release')
    end
end

local function joinScan()
    while true do
        Wait(2500)
        for _, id in ipairs(GetPlayers()) do
            local source = tonumber(id)
            if source and not inmates[source] and not scanned[source] and AJ.Fw.IsLoaded(source) then
                scanned[source] = true
                local ok, err = pcall(scanOne, source)
                if not ok then AJ.Print(('^1join scan error for %d: %s^0'):format(source, tostring(err))) end
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Lifecycle

function Jail.Dropped(source, reason)
    local ids = Identity.Get(source)
    scanned[source] = nil

    table.insert(recent, 1, {
        token = Util.Token(), ids = Identity.Snapshot(ids), source = source,
        droppedAt = AJ.Now(), reason = Util.Cut(tostring(reason or ''), 120),
    })
    if #recent > RECENT_MAX then recent[#recent] = nil end

    local inmate, s = inmates[source], Jail.ForSource(source)
    if not inmate or not s then return end

    AJ.Tasks.Clear(source)
    inmates[source] = nil

    -- A second session sharing an identifier is not the one serving: nothing to log.
    if s.source ~= source then return end
    s.source = nil

    local add = Config.AntiEscape.disconnectPenaltyTasks or 0
    local cap = Config.AntiEscape.maxPenaltyTasks
    if cap and cap > 0 then add = math.max(0, math.min(add, cap - s.penalty)) end
    if add > 0 then
        s.total, s.penalty = s.total + add, s.penalty + add
        Db.UpdateSentence(s.id, { tasks_total = s.total, penalty_tasks = s.penalty })
    end

    Db.Event(s.id, 'disconnect', nil, ('%s · %d left%s'):format(tostring(reason or ''), Jail.Left(s), add > 0 and (' · +%d'):format(add) or ''))
    Log.Send('disconnect', {
        title = 'Inmate disconnected',
        description = ('Left mid-sentence with **%d** task(s) to go. The sentence waits for them.'):format(Jail.Left(s)),
        inmate = ids, sentenceId = s.id,
        fields = {
            { 'Quit reason', reason, false },
            { 'Penalty', add > 0 and ('+%d tasks'):format(add) or 'none' },
        },
    })
end

function Jail.Boot()
    local rows = Db.ActiveSentences()
    for _, row in ipairs(rows) do
        local s = fromRow(row)
        if not Config.Yards[s.yard] then s.yard = Config.Sentence.defaultYard end
        sentences[s.id] = s
    end
    AJ.Print(('jail: %d active sentence(s) loaded.'):format(#rows))

    CreateThread(watchdog)
    CreateThread(joinScan)
end

--- Resource stopping: put everyone back in the main world so nobody is stranded in an
--- empty bucket. Sentences stay active and re-attach the moment the resource is back.
function Jail.Shutdown()
    for source in pairs(inmates) do
        if AJ.Online(source) then
            SetPlayerRoutingBucket(source, Config.Buckets.releaseBucket or 0)
            Player(source).state:set('adminJailed', false, true)
        end
    end
end
