AJ = AJ or {}

local Cl, Work = AJ.Cl, AJ.Work

--- The sentence as the server last described it, or nil when free.
local state = nil
local deathReported = false

local function jailed() return state ~= nil end

-- ----------------------------------------------------------------------------
-- Sentence state

RegisterNetEvent(AJ.Event.STATE, function(payload)
    local was = state
    state = type(payload) == 'table' and payload or nil

    if state then
        local yard = Config.Yards[state.yard]
        SendNUIMessage({ action = 'hud', data = {
            total = state.total, done = state.done, left = state.left,
            reason = state.reason, staff = state.staff, yard = state.yardLabel,
            escapes = state.escapes, penalty = state.penalty, penaltyTasks = state.penaltyTasks,
            position = Config.Hud.position,
        }, locales = not was and Cl.Locales() or nil })

        if not was then
            if Config.AntiEscape.disarm then TriggerEvent('ox_inventory:disarm', true) end
            AJ.Restrict()
        end
        AJ.LeashYard = yard
    else
        SendNUIMessage({ action = 'hud', data = false })
        Work.ClearAll()
        AJ.LeashYard = nil
        if was then AJ.Unrestrict() end
    end
end)

-- ----------------------------------------------------------------------------
-- Placement — the server says where; the client does it smoothly. If the client never
-- does, the server moves the ped itself after Config.AntiEscape.forcePlaceAfterMs.

RegisterNetEvent(AJ.Event.PLACE, function(coords, revive)
    if type(coords) ~= 'table' then return end
    local ped = PlayerPedId()

    DoScreenFadeOut(350)
    local deadline = GetGameTimer() + 1000
    while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end

    if revive or IsEntityDead(ped) then
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, coords.w or 0.0, true, false)
        ped = PlayerPedId()
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        ClearPedBloodDamage(ped)
        deathReported = false
    end

    if IsPedInAnyVehicle(ped, false) then ClearPedTasksImmediately(ped) end

    RequestCollisionAtCoord(coords.x, coords.y, coords.z)
    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    SetEntityHeading(ped, coords.w or 0.0)
    FreezeEntityPosition(ped, true)

    deadline = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do Wait(0) end

    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 2.0, false)
    if found and math.abs(groundZ - coords.z) < 6.0 then
        SetEntityCoords(ped, coords.x, coords.y, groundZ, false, false, false, false)
    end

    FreezeEntityPosition(ped, false)
    Wait(250)
    DoScreenFadeIn(600)
end)

RegisterNetEvent(AJ.Event.CINEMATIC, function(kind, data)
    if type(kind) ~= 'string' then return end
    SendNUIMessage({ action = 'cinematic', data = {
        kind = kind, data = data, duration = Config.Hud.cinematicMs,
    }, locales = Cl.Locales() })

    if kind == 'sentenced' then
        PlaySoundFrontend(-1, 'Bed', 'WastedSounds', true)
    else
        PlaySoundFrontend(-1, 'Mission_Pass_Notify', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', true)
    end
end)

-- ----------------------------------------------------------------------------
-- Restrictions while jailed. Everything here is comfort; the real walls are on the server.

-- Weapons, melee and vehicle entry. Per-frame only while jailed; a free player runs nothing.
local DISABLED_CONTROLS = { 24, 25, 37, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264, 23, 75 }

local restricting = false

local function setInvBusy(value)
    local st = LocalPlayer.state
    if st.invBusy ~= value then st:set('invBusy', value, false) end
    if st.inv_busy ~= value then st:set('inv_busy', value, false) end
end

function AJ.Restrict()
    if restricting then return end
    restricting = true

    CreateThread(function()
        local DisableControlAction, DisablePlayerFiring, Wait = DisableControlAction, DisablePlayerFiring, Wait
        local controls, n = DISABLED_CONTROLS, #DISABLED_CONTROLS
        local pid = PlayerId()
        while restricting do
            DisablePlayerFiring(pid, true)
            for i = 1, n do DisableControlAction(0, controls[i], true) end
            Wait(0)
        end
    end)

    CreateThread(function()
        local cfg = Config.AntiEscape
        local warned = false
        while restricting do
            local ped = PlayerPedId()

            if cfg.invincible then SetEntityInvincible(ped, true) end
            if cfg.disarm and GetSelectedPedWeapon(ped) ~= `WEAPON_UNARMED` then
                SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
            end
            if cfg.lockInventory then setInvBusy(true) end

            if IsEntityDead(ped) then
                if not deathReported then
                    deathReported = true
                    TriggerServerEvent(AJ.Event.DIED)
                end
            else
                deathReported = false
            end

            -- Edge-of-yard warning on the HUD, sent only when it flips.
            local yard = AJ.LeashYard
            if yard then
                local here, c = GetEntityCoords(ped), yard.leash.center
                local dx, dy = here.x - c.x, here.y - c.y
                local edge = yard.leash.radius - 12.0
                local near = dx * dx + dy * dy > edge * edge
                if near ~= warned then
                    warned = near
                    SendNUIMessage({ action = 'edge', data = near })
                end
            end

            Wait(1000)
        end
    end)
end

function AJ.Unrestrict()
    restricting = false
    local ped = PlayerPedId()
    if Config.AntiEscape.invincible then SetEntityInvincible(ped, false) end
    if Config.AntiEscape.lockInventory then setInvBusy(false) end
    SendNUIMessage({ action = 'edge', data = false })
end

-- ----------------------------------------------------------------------------
-- Owner tool: copy a spot line for the config.

RegisterNetEvent(AJ.Event.SPOT, function()
    local c = GetEntityCoords(PlayerPedId())
    local line = ('{ coords = vec3(%.2f, %.2f, %.2f) },'):format(c.x, c.y, c.z)
    lib.setClipboard(line)
    print(line)
    Cl.Notify('cmd.spot', { line }, 'success')
end)

-- ----------------------------------------------------------------------------
-- Ready signal (standalone servers use it as "character loaded").

local function ready()
    CreateThread(function()
        while not NetworkIsPlayerActive(PlayerId()) do Wait(500) end
        Wait(2000)
        TriggerServerEvent(AJ.Event.READY)
    end)
end

AddEventHandler('playerSpawned', ready)
CreateThread(ready)

exports('IsJailed', jailed)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= AJ.RESOURCE then return end
    if state then AJ.Unrestrict() end
    DoScreenFadeIn(0)
end)
