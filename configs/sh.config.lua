--[[
    pr — ADMINJAIL

    An admin jail that is served in WORK, not in minutes. Staff hand out a number of
    community-service tasks — sweep the yard, mop, collect trash, blow leaves, pull weeds —
    and the inmate walks out only when the last one is done. Nothing counts unless the
    SERVER saw it happen: where the inmate stood, how long the job took, which job it was.

    Durations are MILLISECONDS unless the name ends in Seconds. Distances are metres.

    This file is SHARED — every client downloads it. Webhooks, the owner list and the
    Discord bot token live in configs/s.secrets.lua, which never leaves the server.
]]

Config = Config or {}

-- ====== GLOBAL =============================================================

--- 'auto' | 'qbx' | 'qb' | 'esx' | 'standalone'. Only used to know when a character is
--- loaded (so a multicharacter screen is never yanked into the yard) and for the
--- character name in logs. Set explicitly only if auto guesses wrong.
Config.Framework = 'auto'

--- Verbose console output. MUST be false in production.
Config.Debug = false

-- ====== COMMANDS ===========================================================
-- Every command checks access on the server, against the real `discord:` identifier.

Config.Commands = {
    panel  = 'jailpanel',   -- open the owner / staff panel
    jail   = 'ajail',       -- /ajail <id> <tasks> <reason...>   quick jail, default yard
    unjail = 'aunjail',     -- /aunjail <id> <reason...>         cancel a sentence
    tasks  = 'tasksleft',   -- inmates: how much is left
    spot   = 'ajspot',      -- owners: print your position as a task spot (for building yards)
}

-- ====== SENTENCES ==========================================================

Config.Sentence = {
    minTasks = 1,
    maxTasks = 1000,

    --- Quick-pick buttons in the panel.
    presets = { 10, 25, 50, 100, 150, 300 },

    reasonRequired = true,
    reasonMaxLength = 200,

    defaultYard = 'bolingbroke',

    --- Staff (not owners) cannot jail, modify or release an owner.
    protectOwners = true,

    --- Staff can never touch their OWN sentence — no self-release, no self-reduction.
    --- Owners are exempt.
    blockSelfActions = true,
}

-- ====== BUCKETS ============================================================
-- Where the inmate serves. Picked per sentence in the panel and changeable later.
--
--   yard      the yard's own shared bucket — every inmate of that yard together
--   solitary  a private bucket for this inmate alone
--   public    bucket 0, the main world: everyone can watch them mop. The leash still holds.
--   custom    any bucket number the staff member types

Config.Buckets = {
    allowed = { yard = true, solitary = true, public = true, custom = true },
    default = 'yard',

    --- Solitary buckets are allocated from this range, one per inmate.
    solitaryFrom = 7100,
    solitaryTo   = 7999,

    --- Bounds for 'custom'. 0 is the main world and is offered as 'public' instead.
    customMin = 1,
    customMax = 1000000,

    --- Where a released inmate goes back to.
    releaseBucket = 0,
}

-- ====== YARDS ==============================================================
-- A yard is where a sentence is served: a spawn, a leash, task spots and dumpsters.
-- Stand somewhere and run /ajspot to print a ready-to-paste spot line.
--
-- `types` on a spot limits which jobs can be rolled there. Leave it out for "any".

Config.Yards = {
    bolingbroke = {
        label = 'Bolingbroke Penitentiary',
        bucket = 7000,

        --- Entity lockdown for this yard's bucket and its solitary buckets. 'relaxed' blocks
        --- every script-spawned vehicle or prop (menus, /car) but keeps the props GTA's own
        --- work scenarios use. 'strict' blocks those too. Never applied to bucket 0.
        lockdown = 'relaxed',
        population = false,

        spawn = vec4(1661.05, 2524.68, 45.56, 229.75),

        --- Step outside this circle and you are dragged back — with a penalty.
        leash = { center = vec3(1690.0, 2528.0, 45.56), radius = 110.0 },

        spots = {
            { coords = vec3(1761.46, 2540.41, 45.56) },
            { coords = vec3(1718.54, 2527.80, 45.56) },
            { coords = vec3(1700.20, 2474.81, 45.56) },
            { coords = vec3(1664.83, 2501.58, 45.56) },
            { coords = vec3(1621.62, 2509.30, 45.56) },
            { coords = vec3(1627.94, 2538.39, 45.56) },
            { coords = vec3(1625.10, 2575.99, 45.56) },
            { coords = vec3(1650.81, 2540.58, 45.56) },
            { coords = vec3(1697.11, 2525.56, 45.56) },
            { coords = vec3(1673.08, 2519.82, 45.56) },
            { coords = vec3(1765.67, 2565.91, 45.56) },
            { coords = vec3(1660.10, 2555.40, 45.56) },
        },

        --- Trash goes here. A dumpster prop is placed locally if none stands there.
        dropoffs = {
            vec3(1666.62, 2511.55, 45.56),
            vec3(1654.96, 2545.54, 45.56),
            vec3(1730.40, 2545.10, 45.56),
        },
    },
}

--- Where a finished or released inmate is put down.
Config.Release = {
    coords = vec4(1848.13, 2586.05, 45.67, 269.5),
}

-- ====== JOBS ===============================================================
-- Each job is one or more STAGES. A stage happens at the task spot ('spot') or at the
-- nearest dumpster ('dropoff'). The server times every stage and checks where the inmate
-- stood when it started and when it ended.
--
--   durationMs  how long the stage takes — the server will not accept it any faster
--   scenario    a GTA scenario (brings its own props and is seen by everyone)
--   anim        { dict, clip, flag } plus an optional local `prop`
--   skill       ox_lib skill checks spread across the stage. Fail one and the stage
--               restarts — the job does not count until it is done right.
--   carry       stage-to-stage: a prop held while walking to the next stage
--   target      a local prop placed at the spot so there is something to clean up

Config.Jobs = {
    sweep = {
        label = 'Sweep the yard',
        icon = 'broom',
        weight = 3,
        stages = {
            { at = 'spot', durationMs = 9000, scenario = 'WORLD_HUMAN_JANITOR', skill = { 'easy', 'easy' } },
        },
    },

    mop = {
        label = 'Mop the floor',
        icon = 'mop',
        weight = 3,
        stages = {
            {
                at = 'spot', durationMs = 10000, skill = { 'easy', 'medium' },
                anim = { dict = 'missfbi_s4mop', clip = 'idle_scrub', flag = 1 },
                prop = { model = 'prop_cs_mop_s', bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
            },
        },
    },

    trash = {
        label = 'Collect the trash',
        icon = 'trash',
        weight = 3,
        stages = {
            {
                at = 'spot', durationMs = 3500, label = 'Pick up the trash bag', skill = { 'easy' },
                anim = { dict = 'pickup_object', clip = 'pickup_low', flag = 0 },
                target = { model = 'prop_rub_binbag_01' },
            },
            {
                at = 'dropoff', durationMs = 2500, label = 'Throw it in the dumpster',
                anim = { dict = 'anim@heists@narcotics@trash', clip = 'throw_b', flag = 0 },
                carry = {
                    model = 'prop_cs_rub_binbag_01', bone = 57005,
                    pos = vec3(0.12, 0.0, -0.05), rot = vec3(220.0, 120.0, 0.0),
                    anim = { dict = 'anim@heists@narcotics@trash', clip = 'walk', flag = 49 },
                },
            },
        },
    },

    leaves = {
        label = 'Blow the leaves',
        icon = 'wind',
        weight = 2,
        stages = {
            { at = 'spot', durationMs = 11000, scenario = 'WORLD_HUMAN_GARDENER_LEAF_BLOWER', skill = { 'easy', 'medium' } },
        },
    },

    weeds = {
        label = 'Pull the weeds',
        icon = 'sprout',
        weight = 2,
        stages = {
            { at = 'spot', durationMs = 9000, scenario = 'WORLD_HUMAN_GARDENER_PLANT', skill = { 'easy', 'easy' } },
        },
    },

    scrub = {
        label = 'Scrub the graffiti',
        icon = 'spray',
        weight = 2,
        stages = {
            { at = 'spot', durationMs = 9000, scenario = 'WORLD_HUMAN_MAID_CLEAN', skill = { 'medium' } },
        },
    },

    fence = {
        label = 'Fix the fence',
        icon = 'hammer',
        weight = 1,
        stages = {
            { at = 'spot', durationMs = 10000, scenario = 'WORLD_HUMAN_HAMMERING', skill = { 'easy', 'medium', 'easy' } },
        },
    },
}

--- Keys the skill check accepts. ox_lib default is { 'e' }.
Config.SkillKeys = { 'w', 'a', 's', 'd' }

-- ====== ANTI-ESCAPE ========================================================
-- "You can't get out of it." Everything below is enforced on the server.

Config.AntiEscape = {
    --- How often the server checks every inmate's bucket, position and vehicle.
    watchdogMs = 1500,

    --- Tasks ADDED for each escape attempt — leaving the leash, leaving the bucket,
    --- getting into a vehicle. 0 disables the penalty; the inmate is still dragged back.
    penaltyTasks = 5,

    --- One penalty per this many ms, so a single attempt is not billed five times.
    penaltyCooldownMs = 10000,

    --- Total penalty a single sentence can accumulate. 0 = unlimited.
    maxPenaltyTasks = 100,

    --- Tasks added when an inmate disconnects mid-sentence. The sentence always survives
    --- a disconnect; this only decides whether it also costs something. Crashes happen,
    --- so the default is 0.
    disconnectPenaltyTasks = 0,

    --- How long after placing someone in the yard before the leash starts biting.
    placeGraceMs = 8000,

    --- If the client has not walked into the yard by this point, the server moves it.
    forcePlaceAfterMs = 12000,

    --- A task stage cannot start sooner than (distance / maxSpeed). A sprinting ped does
    --- ~7.5 m/s; anything faster is a teleport, and the attempt is refused and logged.
    maxSpeed = 9.0,

    --- How close to the spot / dumpster the inmate must be, checked by the server.
    stageRadius = 3.0,

    --- Server tolerance on stage timing, to absorb network latency.
    timingToleranceMs = 600,

    --- Make inmates immune to damage, disarm them, and lock their inventory. Invincibility and
    --- the inventory lock are client-side comfort; disarming is also enforced by the server.
    invincible = true,
    disarm = true,
    lockInventory = true,
}

-- ====== HUD / LOGGING ======================================================

Config.Hud = {
    --- 'top-right' 'top-left' 'bottom-right' 'bottom-left' 'top-center'
    position = 'top-right',

    --- The cinematic "SENTENCED" / "RELEASED" card.
    cinematic = true,
    cinematicMs = 6500,

    --- Draw a waypoint blip and a ground marker on the current task.
    blip = true,
    marker = true,
}

Config.Logging = {
    enabled = true,

    --- !! WEBHOOKS LIVE IN configs/s.secrets.lua, NOT HERE. !!

    --- Name shown on the webhook message and in every embed footer.
    username = 'pr · Admin Jail',
    serverName = 'My Server',

    --- Discord's per-webhook limit is 30 msgs/minute; batches are sent no faster than this.
    postIntervalMs = 2000,

    --- Turn single categories off.
    events = {
        jail = true,
        release = true,
        complete = true,
        modify = true,
        transfer = true,
        escape = true,
        suspicious = true,
        reconnect = true,
        disconnect = true,
        staff = true,
        progress = false,   -- one line per finished task. Noisy — off by default.
    },
}
