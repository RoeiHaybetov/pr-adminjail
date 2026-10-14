AJ = AJ or {}
AJ.Access = {}

local Access = AJ.Access

--- Staff rows from the database, keyed by Discord id. Owners are NOT in here — they come
--- from configs/s.secrets.lua only and can never be edited or removed from the panel.
local staff = {}

local function clean(id)
    if id == nil then return nil end
    id = tostring(id):gsub('^discord:', ''):gsub('%s', '')
    return id:match('^%d+$') and id or nil
end

function Access.IsOwnerId(discordId)
    if not discordId then return false end
    for _, id in ipairs(Config.Owners or {}) do
        if clean(id) == discordId then return true end
    end
    return false
end

function Access.Load()
    local rows = AJ.Db.Staff()
    local next = {}
    for _, row in ipairs(rows) do
        local ok, list = pcall(json.decode, row.perms or '[]')
        local perms = {}
        for _, key in ipairs(ok and type(list) == 'table' and list or {}) do
            if AJ.PermSet[key] then perms[key] = true end
        end
        next[row.discord_id] = {
            discord = row.discord_id, label = row.label, perms = perms,
            maxTasks = tonumber(row.max_tasks) or 0, addedBy = row.added_by,
            createdAt = row.created_at, updatedAt = row.updated_at,
        }
    end
    staff = next
end

function Access.StaffList()
    local list = {}
    for _, s in pairs(staff) do list[#list + 1] = s end
    table.sort(list, function(a, b) return (a.createdAt or 0) < (b.createdAt or 0) end)
    return list
end

function Access.StaffEntry(discordId)
    return staff[discordId]
end

--- Who is this player, as far as the jail is concerned. Re-derived from the real
--- `discord:` identifier on EVERY call — there is no cached "is admin" flag and the client
--- is never asked who it is.
function Access.Get(source)
    if not AJ.Online(source) then return nil, 'offline' end

    local discord = AJ.Identity.Raw('discord', GetPlayerIdentifierByType(source, 'discord'))
    if not discord then return nil, 'no_discord' end

    local ids = AJ.Identity.Get(source)
    local actor = {
        source = source, discord = discord, name = ids.name, ids = ids,
        isOwner = false, perms = {}, maxTasks = Config.Sentence.maxTasks,
    }

    if Access.IsOwnerId(discord) then
        actor.isOwner = true
        actor.label = 'Owner'
        for key in pairs(AJ.PermSet) do actor.perms[key] = true end
        return actor
    end

    local entry = staff[discord]
    if not entry then return nil, 'not_allowed' end

    actor.label = entry.label
    for key in pairs(entry.perms) do actor.perms[key] = true end
    if entry.maxTasks and entry.maxTasks > 0 then
        actor.maxTasks = math.min(entry.maxTasks, Config.Sentence.maxTasks)
    end
    return actor
end

function Access.Can(actor, perm)
    return actor ~= nil and (actor.isOwner or actor.perms[perm] == true)
end

--- Staff rules on top of plain permissions: never touch an owner, never touch yourself.
--- `sentence` is an in-memory sentence (has .ids).
function Access.MayTouch(actor, sentence)
    if actor.isOwner then return true end
    local ids = sentence.ids or {}
    if Config.Sentence.protectOwners ~= false and ids.discord and Access.IsOwnerId(ids.discord) then
        return false, 'error.protected_owner'
    end
    if Config.Sentence.blockSelfActions ~= false then
        for _, kind in ipairs(AJ.Identity.MATCH) do
            if ids[kind] and actor.ids[kind] and ids[kind] == actor.ids[kind] then
                return false, 'error.self_action'
            end
        end
    end
    return true
end

function Access.Save(actor, discordId, label, permsList, maxTasks)
    discordId = clean(discordId)
    if not discordId then return false, 'error.bad_discord' end
    if Access.IsOwnerId(discordId) then return false, 'error.owner_immutable' end

    local perms = {}
    for _, key in ipairs(type(permsList) == 'table' and permsList or {}) do
        if AJ.PermSet[key] then perms[#perms + 1] = key end
    end

    label = AJ.Util.Trim(label, 64)
    if label == '' then label = ('Staff %s'):format(discordId:sub(-4)) end

    local previous = staff[discordId]
    local now = AJ.Now()
    AJ.Db.SaveStaff({
        discord_id = discordId, label = label, perms = json.encode(perms),
        max_tasks = AJ.Util.Int(maxTasks, 0, Config.Sentence.maxTasks) or 0,
        added_by = previous and previous.addedBy or actor.discord,
        created_at = previous and previous.createdAt or now, updated_at = now,
    })
    Access.Load()
    return true, previous ~= nil, perms, discordId
end

function Access.Remove(discordId)
    discordId = clean(discordId)
    if not discordId or not staff[discordId] then return false end
    local entry = staff[discordId]
    AJ.Db.DeleteStaff(discordId)
    Access.Load()
    return true, entry
end

function Access.Report()
    local owners = #(Config.Owners or {})
    if owners == 0 then
        AJ.Print('^3access: Config.Owners in configs/s.secrets.lua is EMPTY — nobody can open the panel.^0')
    else
        local count = 0
        for _ in pairs(staff) do count = count + 1 end
        AJ.Print(('access: %d owner(s), %d staff member(s).'):format(owners, count))
    end
end
