AJ = AJ or {}

--[[
    The panel's only door into the server. Every call:
      1. is rate limited per player,
      2. re-derives who the caller is from their real `discord:` identifier,
      3. checks the one permission that action needs,
      4. validates every field of the payload — bounds, types, lengths — here, not in the UI.
    There is no generic "set this field" call; each action does exactly one thing.
]]

local Util, Access, Jail, Identity, Log, Db = AJ.Util, AJ.Access, AJ.Jail, AJ.Identity, AJ.Log, AJ.Db

local function fail(key, extra)
    local out = { ok = false, error = key }
    if extra then for k, v in pairs(extra) do out[k] = v end end
    return out
end

local function reasonOf(payload)
    local reason = Util.Trim(payload.reason, Config.Sentence.reasonMaxLength)
    if reason == '' then
        if Config.Sentence.reasonRequired then return nil end
        reason = 'No reason given'
    end
    return reason
end

local function sentenceOf(payload, actor)
    local s = Jail.Get(payload.id)
    if not s then return nil, 'error.no_sentence' end
    local ok, why = Access.MayTouch(actor, s)
    if not ok then return nil, why end
    return s
end

local function yardList()
    local list = {}
    for key, yard in pairs(Config.Yards) do
        list[#list + 1] = { key = key, label = yard.label, bucket = yard.bucket, spots = #yard.spots }
    end
    table.sort(list, function(a, b) return a.label < b.label end)
    return list
end

local function ownerList()
    local list = {}
    for _, id in ipairs(Config.Owners or {}) do
        list[#list + 1] = tostring(id):gsub('^discord:', '')
    end
    return list
end

-- ----------------------------------------------------------------------------

local Actions = {}

Actions.bootstrap = { perm = nil, fn = function(actor)
    local perms = {}
    for key in pairs(actor.perms) do perms[#perms + 1] = key end
    local modes = {}
    for _, mode in ipairs(AJ.BucketModes) do
        if Config.Buckets.allowed[mode] then modes[#modes + 1] = mode end
    end
    return {
        ok = true,
        me = {
            name = actor.name, discord = actor.discord, isOwner = actor.isOwner,
            label = actor.label, perms = perms, maxTasks = actor.maxTasks,
        },
        config = {
            minTasks = Config.Sentence.minTasks, maxTasks = Config.Sentence.maxTasks,
            presets = Config.Sentence.presets, reasonRequired = Config.Sentence.reasonRequired,
            reasonMaxLength = Config.Sentence.reasonMaxLength,
            defaultYard = Config.Sentence.defaultYard,
            bucketModes = modes, defaultMode = Config.Buckets.default,
            customMin = Config.Buckets.customMin, customMax = Config.Buckets.customMax,
            penaltyTasks = Config.AntiEscape.penaltyTasks,
        },
        yards = yardList(),
        permsCatalog = AJ.Perms,
    }
end }

Actions.players = { perm = nil, fn = function(actor)
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local ids = Identity.Get(src)
        local s = Jail.Find(ids)
        list[#list + 1] = {
            source = src, name = ids.name, char = ids.char,
            discord = ids.discord, hasSteam = ids.steam ~= nil,
            jailed = s and s.id or nil, isOwner = Access.IsOwnerId(ids.discord),
            isStaff = ids.discord and Access.StaffEntry(ids.discord) ~= nil or false,
        }
    end
    table.sort(list, function(a, b) return a.source < b.source end)

    local recent = {}
    if Access.Can(actor, 'offline') then
        for _, r in ipairs(Jail.Recent()) do
            recent[#recent + 1] = {
                token = r.token, name = r.ids.name, char = r.ids.char, source = r.source,
                droppedAt = r.droppedAt, reason = r.reason, discord = r.ids.discord,
                jailed = Jail.Find(r.ids) and true or false,
            }
        end
    end
    return { ok = true, players = list, recent = recent, now = AJ.Now() }
end }

Actions.inmates = { perm = nil, fn = function(actor)
    local list = {}
    for _, s in pairs(Jail.All()) do list[#list + 1] = Jail.Public(s, Access.Can(actor, 'history')) end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.id > b.id
    end)
    return { ok = true, inmates = list, now = AJ.Now() }
end }

Actions.jail = { perm = 'jail', fn = function(actor, p)
    local tasks = Util.Int(p.tasks, Config.Sentence.minTasks, actor.maxTasks)
    if not tasks then return fail('error.bad_tasks', { max = actor.maxTasks }) end

    local reason = reasonOf(p)
    if not reason then return fail('error.reason_required') end

    local yard = type(p.yard) == 'string' and Config.Yards[p.yard] and p.yard or nil
    if not yard then return fail('error.bad_yard') end

    local mode = type(p.mode) == 'string' and p.mode or Config.Buckets.default

    local target
    if p.source ~= nil then
        local src = Util.Int(p.source, 1)
        if not src or not AJ.Online(src) then return fail('error.player_offline') end
        target = { source = src }
    elseif p.recent ~= nil or p.identifier ~= nil then
        if not Access.Can(actor, 'offline') then return fail('error.no_permission') end

        local ids
        if p.recent ~= nil then
            for _, r in ipairs(Jail.Recent()) do
                if r.token == p.recent then ids = r.ids break end
            end
            if not ids then return fail('error.recent_gone') end
        else
            local kind, value = Identity.Parse(p.identifier)
            if not kind then return fail('error.bad_identifier') end
            ids = { [kind] = value, name = ('offline:%s:%s'):format(kind, value):sub(1, 64) }
            local label = Util.Trim(p.label, 64)
            if label ~= '' then ids.name = 'offline:' .. label end
        end

        -- They might be online after all — then jail them properly.
        for _, id in ipairs(GetPlayers()) do
            local src = tonumber(id)
            local live = Identity.Get(src)
            for _, kind in ipairs(Identity.MATCH) do
                if ids[kind] and live[kind] == ids[kind] then target = { source = src } break end
            end
            if target then break end
        end
        target = target or { ids = ids }
    else
        return fail('error.bad_request')
    end

    local ok, result, existing = Jail.Create(actor, target, {
        tasks = tasks, yard = yard, mode = mode, bucket = p.bucket, reason = reason,
    })
    if not ok then return fail(result, { existing = existing }) end
    return { ok = true, id = result.id, online = result.source ~= nil }
end }

Actions.modify = { perm = 'modify', fn = function(actor, p)
    local s, err = sentenceOf(p, actor)
    if not s then return fail(err) end

    local op = p.op
    if op ~= 'add' and op ~= 'remove' and op ~= 'set' then return fail('error.bad_request') end

    local amount = Util.Int(p.amount, op == 'set' and 0 or 1, Config.Sentence.maxTasks)
    if not amount then return fail('error.bad_tasks', { max = Config.Sentence.maxTasks }) end

    -- Lowering someone's sentence to zero is a release — that needs the release permission.
    local left = Jail.Left(s)
    local after = op == 'add' and left + amount or op == 'remove' and left - amount or amount
    if after <= 0 and not Access.Can(actor, 'release') then return fail('error.no_permission') end

    local reason = reasonOf(p)
    if not reason then return fail('error.reason_required') end

    local ok, why = Jail.Modify(actor, s, op, amount, reason)
    if not ok then return fail(why, { max = actor.maxTasks }) end
    return { ok = true }
end }

Actions.transfer = { perm = 'modify', fn = function(actor, p)
    local s, err = sentenceOf(p, actor)
    if not s then return fail(err) end

    local yard = type(p.yard) == 'string' and Config.Yards[p.yard] and p.yard or nil
    if not yard then return fail('error.bad_yard') end

    local reason = reasonOf(p)
    if not reason then return fail('error.reason_required') end

    local ok, why = Jail.Transfer(actor, s, yard, p.mode, p.bucket, reason)
    if not ok then return fail(why) end
    return { ok = true }
end }

Actions.release = { perm = 'release', fn = function(actor, p)
    local s, err = sentenceOf(p, actor)
    if not s then return fail(err) end

    local reason = reasonOf(p)
    if not reason then return fail('error.reason_required') end

    Jail.End(s, 'release', actor, reason)
    return { ok = true }
end }

Actions.history = { perm = 'history', fn = function(_, p)
    local status = p.status
    if status ~= 'all' and status ~= 'active' and status ~= 'completed' and status ~= 'released' then status = 'all' end
    local rows, total, page, pageSize = Db.History({
        status = status, search = Util.Trim(p.search, 64), page = p.page,
    })
    return { ok = true, rows = rows, total = total, page = page, pageSize = pageSize }
end }

Actions.events = { perm = 'history', fn = function(_, p)
    local id = Util.Int(p.id, 1)
    if not id then return fail('error.bad_request') end
    return { ok = true, sentence = Db.Sentence(id), events = Db.Events(id) }
end }

Actions.activity = { perm = 'history', fn = function()
    return { ok = true, events = Db.RecentEvents(80) }
end }

Actions.staff = { perm = 'owner', fn = function()
    return { ok = true, staff = Access.StaffList(), owners = ownerList() }
end }

Actions.saveStaff = { perm = 'owner', fn = function(actor, p)
    local discordId = p.discord
    if p.source ~= nil then
        local src = Util.Int(p.source, 1)
        if not src or not AJ.Online(src) then return fail('error.player_offline') end
        discordId = Identity.Raw('discord', GetPlayerIdentifierByType(src, 'discord'))
        if not discordId then return fail('error.target_no_discord') end
        if Util.Trim(p.label, 64) == '' then p.label = GetPlayerName(src) end
    end

    local ok, updated, perms, cleanId = Access.Save(actor, discordId, p.label, p.perms, p.maxTasks)
    if not ok then return fail(updated) end

    local entry = Access.StaffEntry(cleanId)
    Db.Event(nil, updated and 'staff_update' or 'staff_add', actor,
        ('%s (%s) · %s · max %s'):format(entry.label, entry.discord, table.concat(perms, ','), entry.maxTasks > 0 and entry.maxTasks or 'default'))

    Log.Send('staff', {
        title = updated and 'Staff permissions changed' or 'Staff member added',
        description = ('<@%s> · **%s**'):format(entry.discord, entry.label),
        staff = actor.ids, staffRole = 'By owner',
        fields = {
            { 'Permissions', #perms > 0 and table.concat(perms, ', ') or 'none (panel view only)', false },
            { 'Max tasks', entry.maxTasks > 0 and entry.maxTasks or ('default (%d)'):format(Config.Sentence.maxTasks) },
        },
    })
    return { ok = true }
end }

Actions.removeStaff = { perm = 'owner', fn = function(actor, p)
    local ok, entry = Access.Remove(p.discord)
    if not ok then return fail('error.bad_discord') end

    Db.Event(nil, 'staff_remove', actor, ('%s (%s)'):format(entry.label, entry.discord))
    Log.Send('staff', {
        title = 'Staff member removed',
        description = ('<@%s> · **%s** can no longer use the jail.'):format(entry.discord, entry.label),
        staff = actor.ids, staffRole = 'By owner',
    })
    return { ok = true }
end }

Actions.testLog = { perm = 'owner', fn = function(actor)
    Log.Send('staff', {
        title = 'Webhook test',
        description = 'If you can read this, the Admin Jail can reach this channel.',
        staff = actor.ids, staffRole = 'Sent by',
    })
    return { ok = true }
end }

-- ----------------------------------------------------------------------------

local DENY = {
    no_discord = 'error.no_discord',
    not_allowed = 'error.not_allowed',
    offline = 'error.not_allowed',
}

function AJ.PanelGate(source)
    local actor, why = Access.Get(source)
    if not actor then return nil, DENY[why] or 'error.not_allowed' end

    -- A jailed staff member does not get a panel. Owners do — it is their server.
    if not actor.isOwner and Jail.ForSource(source) then return nil, 'error.jailed_staff' end
    return actor
end

lib.callback.register(AJ.Callback.PANEL, function(source, action, payload)
    if not Util.Rate(source, 'panel') then return fail('error.slow_down') end

    local def = type(action) == 'string' and Actions[action] or nil
    if not def then return fail('error.bad_request') end

    local actor, why = AJ.PanelGate(source)
    if not actor then return fail(why) end

    if def.perm == 'owner' then
        if not actor.isOwner then return fail('error.no_permission') end
    elseif def.perm and not Access.Can(actor, def.perm) then
        return fail('error.no_permission')
    end

    local ok, result = pcall(def.fn, actor, type(payload) == 'table' and payload or {})
    if not ok then
        AJ.Print(('^1panel action %s failed: %s^0'):format(action, tostring(result)))
        return fail('error.generic')
    end
    return result
end)
