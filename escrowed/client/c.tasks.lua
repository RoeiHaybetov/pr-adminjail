AJ = AJ or {}
AJ.Work = {}

local Work, Cl = AJ.Work, AJ.Cl

local current = nil       -- task from the server (see s.lib.tasks.lua Tasks.Public)
local busy = false        -- a stage is being performed right now
local blip, targetProp, dumpsterProp, carryProp = nil, nil, nil, nil
local carryAnim = nil
local textShown = false
local lastDistance = -1   -- last distance pushed to the HUD, in whole metres

local DUMPSTERS = { `prop_dumpster_01a`, `prop_dumpster_02a`, `prop_dumpster_02b`, `prop_dumpster_3a`, `prop_dumpster_4a` }

local function hideText()
    if textShown then lib.hideTextUI() textShown = false end
end

local function clearBlip()
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    blip = nil
end

local function clearCarry()
    if carryAnim then StopAnimTask(PlayerPedId(), carryAnim.dict, carryAnim.clip, 1.0) end
    carryAnim = nil
    Cl.Delete(carryProp)
    carryProp = nil
end

function Work.ClearAll()
    clearBlip()
    clearCarry()
    Cl.Delete(targetProp) targetProp = nil
    Cl.Delete(dumpsterProp) dumpsterProp = nil
    hideText()
    current = nil
    SendNUIMessage({ action = 'task', data = false })
end

local function stageDef(task)
    local job = Config.Jobs[task.job]
    return job and job.stages[task.stage], job
end

local function hasDumpster(coords)
    for _, model in ipairs(DUMPSTERS) do
        if GetClosestObjectOfType(coords.x, coords.y, coords.z, 3.0, model, false, false, false) ~= 0 then return true end
    end
    return false
end

local function show(task)
    local stage, job = stageDef(task)
    if not stage then return end
    local coords = Cl.Vec(task.coords)

    clearBlip()
    if Config.Hud.blip ~= false then
        blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, task.stages > 1 and task.stage > 1 and 318 or 566)
        SetBlipColour(blip, 5)
        SetBlipScale(blip, 0.85)
        SetBlipRoute(blip, true)
        SetBlipRouteColour(blip, 5)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(task.stageLabel)
        EndTextCommandSetBlipName(blip)
    end

    -- Something to clean up at the spot — gone once the first stage is done.
    Cl.Delete(targetProp) targetProp = nil
    if task.stage == 1 and stage.target then
        targetProp = Cl.LocalProp(stage.target.model, Cl.Vec(task.spotCoords), true)
    end

    -- A dumpster at the dropoff, unless the map already has one there.
    if stage.at == 'dropoff' then
        Cl.Delete(dumpsterProp) dumpsterProp = nil
        if not hasDumpster(coords) then dumpsterProp = Cl.LocalProp('prop_dumpster_01a', coords, true) end
    end

    -- Walking to this stage with something in hand.
    clearCarry()
    if stage.carry then
        local ped = PlayerPedId()
        carryProp = Cl.AttachProp(ped, stage.carry)
        if stage.carry.anim and Cl.LoadDict(stage.carry.anim.dict) then
            carryAnim = stage.carry.anim
            TaskPlayAnim(ped, carryAnim.dict, carryAnim.clip, 8.0, -8.0, -1, carryAnim.flag or 49, 0, false, false, false)
        end
    end

    SendNUIMessage({ action = 'task', data = {
        label = job.label, stageLabel = task.stageLabel, icon = job.icon,
        stage = task.stage, stages = task.stages,
    } })
end

RegisterNetEvent(AJ.Event.TASK, function(task)
    if busy and task and current and task.id == current.id and task.stage == current.stage then return end
    if not task then
        Work.ClearAll()
        return
    end
    if not current or current.id ~= task.id then
        Cl.Delete(targetProp) targetProp = nil
        Cl.Delete(dumpsterProp) dumpsterProp = nil
    end
    task.vec = Cl.Vec(task.coords)
    current = task
    lastDistance = -1
    show(task)
    Work.EnsureLoop()
end)

-- ----------------------------------------------------------------------------
-- Doing the work

local function startAnim(ped, stage)
    local prop
    if stage.scenario then
        TaskStartScenarioInPlace(ped, stage.scenario, 0, true)
    elseif stage.anim and Cl.LoadDict(stage.anim.dict) then
        TaskPlayAnim(ped, stage.anim.dict, stage.anim.clip, 8.0, -8.0, -1, stage.anim.flag or 1, 0, false, false, false)
    end
    if stage.prop then prop = Cl.AttachProp(ped, stage.prop) end
    return prop
end

local function stopAnim(ped, stage, prop)
    if stage.anim then StopAnimTask(ped, stage.anim.dict, stage.anim.clip, 1.0) end
    if stage.scenario then ClearPedTasks(ped) end
    Cl.Delete(prop)
end

local function perform()
    local task = current
    local stage, job = stageDef(task or {})
    if not task or not stage then busy = false return end
    busy = true
    hideText()

    local res = lib.callback.await(AJ.Callback.START, false, task.id)
    if not res or not res.ok then
        Cl.Notify(res and res.error or 'error.generic', nil, 'error')
        busy = false
        return
    end

    local ped = PlayerPedId()
    local coords = task.vec
    TaskTurnPedToFaceCoord(ped, coords.x, coords.y, coords.z, 700)
    Wait(700)

    if stage.carry then clearCarry() end
    local prop = startAnim(ped, stage)

    local checks = stage.skill or {}
    local segments = #checks + 1
    local per = math.ceil(stage.durationMs / segments) + 50
    local ok = true

    for i = 1, segments do
        if not lib.progressBar({
            duration = per,
            label = ('%s  (%d/%d)'):format(task.stageLabel, i, segments),
            canCancel = true,
            disable = { move = true, car = true, combat = true, sprint = true },
        }) then
            ok = false
            Cl.Notify('task.cancelled', nil, 'error')
            break
        end
        if checks[i] then
            if not lib.skillCheck(checks[i], Config.SkillKeys) then
                ok = false
                Cl.Notify('task.failed', nil, 'error')
                break
            end
        end
    end

    stopAnim(ped, stage, prop)

    if ok then
        local done = lib.callback.await(AJ.Callback.FINISH, false, task.id)
        if not done or not done.ok then
            Cl.Notify(done and done.error or 'error.generic', nil, 'error')
        elseif done.counted and not done.finished then
            -- The next task (and its props) arrives on its own TASK event.
            PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            Cl.Notify('task.done', { job.label }, 'success')
        end
    else
        lib.callback.await(AJ.Callback.ABORT, false, task.id)
        -- Restore the carry if this stage was the dropoff.
        if stage.carry and current and current.id == task.id then show(current) end
    end

    busy = false
end

-- ----------------------------------------------------------------------------
-- The loop. It only exists while there is a task: an inmate-free client runs nothing.
--   far  (> NEAR m): one check every 500 ms — HUD distance, carry animation
--   near (<= NEAR m): per-frame marker + prompt, HUD distance at most 4x a second

local NEAR, NEAR_EXIT = 25.0, 30.0
local looping = false

local PlayerPedId, GetEntityCoords, GetGameTimer = PlayerPedId, GetEntityCoords, GetGameTimer
local DrawMarker, IsControlJustReleased, IsPedInAnyVehicle = DrawMarker, IsControlJustReleased, IsPedInAnyVehicle

local function pushDistance(dist)
    local rounded = math.floor(dist + 0.5)
    if rounded == lastDistance then return end
    lastDistance = rounded
    SendNUIMessage({ action = 'taskDistance', data = rounded })
end

local function keepCarrying(ped)
    if carryAnim and not IsEntityPlayingAnim(ped, carryAnim.dict, carryAnim.clip, 3) then
        TaskPlayAnim(ped, carryAnim.dict, carryAnim.clip, 8.0, -8.0, -1, carryAnim.flag or 49, 0, false, false, false)
    end
end

local function nearLoop(task)
    local c = task.vec
    local x, y, z = c.x, c.y, c.z
    local markers = Config.Hud.marker ~= false
    local nextHud, nextCarry = 0, 0

    while current == task and not busy do
        local ped = PlayerPedId()
        local dist = #(GetEntityCoords(ped) - c)
        if dist > NEAR_EXIT then break end

        local now = GetGameTimer()
        if now >= nextHud then nextHud = now + 250; pushDistance(dist) end
        if now >= nextCarry then nextCarry = now + 1000; keepCarrying(ped) end

        if markers then
            DrawMarker(1, x, y, z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.6, 1.6, 0.6, 250, 190, 40, 110, false, false, 2, false, nil, nil, false)
            DrawMarker(20, x, y, z + 0.6, 0.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.45, 0.45, 0.45, 250, 190, 40, 200, true, true, 2, false, nil, nil, false)
        end

        if dist < 1.8 and not IsPedInAnyVehicle(ped, false) then
            if not textShown then
                lib.showTextUI(('[E] %s'):format(task.stageLabel), { position = 'left-center', icon = 'hand' })
                textShown = true
            end
            if IsControlJustReleased(0, 38) then
                busy = true
                hideText()
                CreateThread(perform)
                return
            end
        elseif textShown then
            hideText()
        end

        Wait(0)
    end
    hideText()
end

function Work.EnsureLoop()
    if looping then return end
    looping = true
    CreateThread(function()
        while current do
            if busy then
                Wait(250)
            else
                local task = current
                local ped = PlayerPedId()
                local dist = #(GetEntityCoords(ped) - task.vec)
                pushDistance(dist)
                if dist <= NEAR then
                    nearLoop(task)
                else
                    keepCarrying(ped)
                    Wait(500)
                end
            end
        end
        looping = false
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= AJ.RESOURCE then return end
    Work.ClearAll()
end)
