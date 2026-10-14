AJ = AJ or {}

AJ.RESOURCE = GetCurrentResourceName()

local function name(suffix) return ('%s:%s'):format(AJ.RESOURCE, suffix) end

AJ.Event = {
    STATE     = name('client:state'),      -- server -> client: full inmate state, or false
    TASK      = name('client:task'),       -- server -> client: the current task, or false
    PLACE     = name('client:place'),      -- server -> client: put me down at these coords
    CINEMATIC = name('client:cinematic'),  -- server -> client: SENTENCED / RELEASED card
    NOTIFY    = name('client:notify'),
    PANEL     = name('client:panel'),      -- server -> client: open the panel
    SPOT      = name('client:spot'),       -- server -> client: copy my position as a spot line

    DIED      = name('server:died'),       -- client -> server: I died in the yard
    READY     = name('server:ready'),      -- client -> server: my scripts are up
}

AJ.Callback = {
    PANEL  = name('panel'),
    START  = name('task:start'),
    FINISH = name('task:finish'),
    ABORT  = name('task:abort'),
}

--- Every staff permission. Owners hold all of them plus staff management.
AJ.Perms = {
    { key = 'jail',    label = 'Jail players',        desc = 'Sentence online players.' },
    { key = 'offline', label = 'Jail offline',        desc = 'Sentence by identifier — served on next join.' },
    { key = 'modify',  label = 'Modify sentences',    desc = 'Add, remove or set tasks. Move yard or bucket.' },
    { key = 'release', label = 'Release',             desc = 'Cancel a sentence early.' },
    { key = 'history', label = 'History & identities', desc = 'See past sentences, the event log and identifiers.' },
}

AJ.PermSet = {}
for i = 1, #AJ.Perms do AJ.PermSet[AJ.Perms[i].key] = true end

AJ.BucketModes = { 'yard', 'solitary', 'public', 'custom' }
