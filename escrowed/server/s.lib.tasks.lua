AJ = AJ or {}
AJ.Tasks = {}

local Tasks = AJ.Tasks
local Util, Log, Db = AJ.Util, AJ.Log, AJ.Db

--- Current task per online inmate: { source -> task }. A task is
---   id        random token — the client must echo it, so a forged call needs the token
---   job       key in Config.Jobs
---   stage     index into the job's stages
---   spot      index into the yard's spots
---   dropoff   index into the yard's dropoffs (jobs with a dropoff stage)
---   issuedAt  mono time this stage was handed out
---   from      where the inmate stood when it was handed out (for the travel-time check)
---   startedAt mono time the server accepted START for this stage, or nil
local active = {}

local lastSuspicious = {}

local function contains(list, value)
    for i = 1, #list do if list[i] == value then return true end end
    return false
end

local function needsDropoff(job)
    for _, stage in ipairs(job.stages) do
        if stage.at == 'dropoff' then return true end
    end
    return false
end

local function jobsFor(yard, spot)
    local list = {}
    for key, job in pairs(Config.Jobs) do
        local allowed = not spot.types or contains(spot.types, key)
        if allowed and needsDropoff(job) and (not yard.dropoffs or #yard.dropoffs == 0) then allowed = false end
        if allowed then list[#list + 1] = { key = key, weight = job.weight or 1 } end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

local function nearestDropoff(yard, coords)
    local best, bestDist
    for i, d in ipairs(yard.dropoffs or {}) do
        local dist = Util.Dist(d, coords)
        if not bestDist or dist < bestDist then best, bestDist = i, dist end
    end
    return best
end

local function pedCoords(source)
    local ped = GetPlayerPed(source)
    if ped == 0 then return nil end
    return GetEntityCoords(ped)
end

--- Where the current stage happens.
function Tasks.Target(yard, task)
    local stage = Config.Jobs[task.job].stages[task.stage]
    if stage.at == 'dropoff' and task.dropoff then return yard.dropoffs[task.dropoff] end
    return yard.spots[task.spot].coords
end

function Tasks.Brief(task)
    local job = Config.Jobs[task.job]
    return { label = job and job.label or task.job, icon = job and job.icon or nil, stage = task.stage, stages = job and #job.stages or 1 }
end

--- What the client is told about a task. Durations and skill checks come from the shared
--- config on the client too; the server's copy is the one that is enforced.
function Tasks.Public(yard, task)
    local job = Config.Jobs[task.job]
    local stage = job.stages[task.stage]
    return {
        id = task.id, job = task.job, label = job.label, icon = job.icon,
        stage = task.stage, stages = #job.stages, stageLabel = stage.label or job.label,
        coords = Util.Vec(Tasks.Target(yard, task)),
        spotCoords = Util.Vec(yard.spots[task.spot].coords),
    }
end

local function send(source, yard, task)
    TriggerClientEvent(AJ.Event.TASK, source, task and Tasks.Public(yard, task) or false)
end

function Tasks.Assign(source, inmate, s)
    local yard = Config.Yards[s.yard]
    if not yard or #yard.spots == 0 then return end

    -- Prefer a spot nobody else in this bucket is working, and never the same one twice.
    local taken = {}
    for src, t in pairs(active) do
        if src ~= source and t.bucket == s.bucket and t.yard == s.yard then taken[t.spot] = true end
    end

    local pool = {}
    for i = 1, #yard.spots do
        if i ~= inmate.lastSpot and not taken[i] then pool[#pool + 1] = i end
    end
    if #pool == 0 then
        for i = 1, #yard.spots do if i ~= inmate.lastSpot then pool[#pool + 1] = i end end
    end
    if #pool == 0 then pool[1] = 1 end

    local spotIndex, jobs
    for _ = 1, #pool do
        local pick = table.remove(pool, math.random(1, #pool))
        jobs = jobsFor(yard, yard.spots[pick])
        if #jobs > 0 then spotIndex = pick break end
    end
    if not spotIndex then
        AJ.Print(('^1yard %s has no spot that allows any configured job^0'):format(s.yard))
        return
    end

    local spot = yard.spots[spotIndex]
    local task = {
        id = Util.Token(),
        job = Util.Weighted(jobs).key,
        stage = 1,
        spot = spotIndex,
        dropoff = nearestDropoff(yard, spot.coords),
        issuedAt = AJ.Mono(),
        -- Not yet seen inside the yard = still being placed there: measure from the spawn.
        from = inmate.settled and pedCoords(source) or yard.spawn,
        startedAt = nil,
        bucket = s.bucket, yard = s.yard,
    }

    inmate.lastSpot = spotIndex
    inmate.task = task
    active[source] = task
    send(source, yard, task)
end

--- Sends the current task again — for a client whose scripts started after it was sent.
function Tasks.Resend(source)
    local inmate, s = AJ.Jail.Inmate(source), AJ.Jail.ForSource(source)
    if inmate and inmate.task and s then send(source, Config.Yards[s.yard], inmate.task) end
end

function Tasks.Clear(source)
    active[source] = nil
    local inmate = AJ.Jail.Inmate(source)
    if inmate then inmate.task = nil end
    if AJ.Online(source) then TriggerClientEvent(AJ.Event.TASK, source, false) end
end

-- ----------------------------------------------------------------------------
-- Anti-exploit

local function suspicious(source, s, what)
    Db.Event(s.id, 'suspicious', nil, what)
    local now = AJ.Mono()
    if lastSuspicious[source] and now - lastSuspicious[source] < 5000 then return end
    lastSuspicious[source] = now
    Log.Send('suspicious', {
        title = 'Suspicious task attempt',
        description = what,
        inmate = AJ.Identity.Get(source), sentenceId = s.id,
        fields = { { 'Tasks left', AJ.Jail.Left(s) } },
    })
end

local function context(source, id)
    local inmate, s = AJ.Jail.Inmate(source), AJ.Jail.ForSource(source)
    if not inmate or not s or not inmate.task then return nil, 'task.none' end
    if type(id) ~= 'string' or inmate.task.id ~= id then
        -- A stale id (the task changed a moment ago) is normal; a malformed one is not.
        if type(id) ~= 'string' or not id:match('^%x+$') or #id ~= 16 then
            suspicious(source, s, ('sent a forged task id %q'):format(tostring(id):sub(1, 32)))
        end
        return nil, 'task.none'
    end
    return inmate, s, Config.Yards[s.yard]
end

lib.callback.register(AJ.Callback.START, function(source, id)
    if not Util.Rate(source, 'start') then return { ok = false, error = 'error.slow_down' } end

    local inmate, s, yard = context(source, id)
    if not inmate then return { ok = false, error = s } end
    local task = inmate.task

    local coords = pedCoords(source)
    if not coords then return { ok = false, error = 'task.none' } end

    local ped = GetPlayerPed(source)
    if GetVehiclePedIsIn(ped, false) ~= 0 then return { ok = false, error = 'task.too_far' } end

    local target = Tasks.Target(yard, task)
    if Util.Dist(coords, target) > Config.AntiEscape.stageRadius then
        return { ok = false, error = 'task.too_far' }
    end

    -- Travel time. Nobody runs faster than maxSpeed; getting here sooner is a teleport.
    if task.from then
        local elapsed = AJ.Mono() - task.issuedAt
        local minimum = Util.Dist(task.from, target) / Config.AntiEscape.maxSpeed * 1000 - 1500
        if elapsed < minimum then
            suspicious(source, s, ('reached the task %.0fm away in %.1fs (minimum %.1fs) — teleport? Task re-rolled.')
                :format(Util.Dist(task.from, target), elapsed / 1000, minimum / 1000))
            Tasks.Assign(source, inmate, s)
            return { ok = false, error = 'task.too_fast' }
        end
    end

    task.startedAt = AJ.Mono()
    -- Working a job = really in the yard, not behind a spawn selector: no more free exit.
    inmate.freeUntil = 0
    return { ok = true, durationMs = Config.Jobs[task.job].stages[task.stage].durationMs }
end)

lib.callback.register(AJ.Callback.FINISH, function(source, id)
    if not Util.Rate(source, 'finish') then return { ok = false, error = 'error.slow_down' } end

    local inmate, s, yard = context(source, id)
    if not inmate then return { ok = false, error = s } end
    local task = inmate.task
    local job = Config.Jobs[task.job]
    local stage = job.stages[task.stage]

    if not task.startedAt then
        suspicious(source, s, ('tried to finish "%s" without starting it'):format(job.label))
        return { ok = false, error = 'task.not_started' }
    end

    local now = AJ.Mono()
    local elapsed = now - task.startedAt
    local needed = stage.durationMs - (Config.AntiEscape.timingToleranceMs or 600)
    if elapsed < needed then
        task.startedAt = nil
        suspicious(source, s, ('finished "%s" in %.1fs — it takes %.1fs'):format(job.label, elapsed / 1000, stage.durationMs / 1000))
        return { ok = false, error = 'task.too_quick' }
    end

    local coords = pedCoords(source)
    if not coords or Util.Dist(coords, Tasks.Target(yard, task)) > Config.AntiEscape.stageRadius * 1.5 then
        task.startedAt = nil
        return { ok = false, error = 'task.too_far' }
    end

    if task.stage < #job.stages then
        task.stage = task.stage + 1
        task.startedAt = nil
        task.issuedAt = now
        task.from = coords
        send(source, yard, task)
        return { ok = true, stage = task.stage }
    end

    active[source] = nil
    inmate.task = nil
    local finished = AJ.Jail.Progress(source, s, task.job)
    if not finished then Tasks.Assign(source, inmate, s) end
    return { ok = true, counted = true, finished = finished }
end)

lib.callback.register(AJ.Callback.ABORT, function(source, id)
    if not Util.Rate(source, 'abort') then return { ok = false } end
    local inmate = AJ.Jail.Inmate(source)
    if inmate and inmate.task and inmate.task.id == id then inmate.task.startedAt = nil end
    return { ok = true }
end)

function Tasks.Forget(source)
    active[source] = nil
    lastSuspicious[source] = nil
end
