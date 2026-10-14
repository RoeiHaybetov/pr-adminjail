AJ = AJ or {}
AJ.Log = {}

local Log = AJ.Log
local Identity = AJ.Identity

--- Logging event -> which webhook in Config.Webhooks it goes to.
local ROUTE = {
    jail = 'jail', release = 'release', complete = 'complete', modify = 'modify',
    transfer = 'modify', escape = 'escape', suspicious = 'suspicious',
    reconnect = 'session', disconnect = 'session', staff = 'staff', progress = 'progress',
}

Log.Color = {
    jail = 0xE74C3C, release = 0x2ECC71, complete = 0x1ABC9C, modify = 0xF1C40F,
    transfer = 0x3498DB, escape = 0xE67E22, suspicious = 0x992D22, reconnect = 0x95A5A6,
    disconnect = 0x7F8C8D, staff = 0x9B59B6, progress = 0x5865F2,
}

--- Discord rejects a whole message whose embeds add up to more than 6000 characters, so
--- batches are cut well below that.
local MAX_EMBEDS, MAX_QUEUE, MAX_BATCH_CHARS = 10, 200, 5500
local DROPPED_TITLE = 'Logs dropped'

local function embedSize(e)
    local n = #(e.title or '') + #(e.description or '') + #((e.footer and e.footer.text) or '')
    for _, f in ipairs(e.fields or {}) do n = n + #(f.name or '') + #(f.value or '') end
    return n
end

local function webhookFor(event)
    local hooks = Config.Webhooks or {}
    local url = hooks[ROUTE[event] or event]
    if type(url) ~= 'string' or url == '' then url = hooks.default end
    if type(url) ~= 'string' or not url:match('^https://') then return nil end
    return url
end

local function enabled(event)
    local cfg = Config.Logging or {}
    if cfg.enabled == false then return false end
    return not cfg.events or cfg.events[event] ~= false
end

-- ----------------------------------------------------------------------------
-- One queue per webhook URL, drained no faster than postIntervalMs, honouring 429.

local queues = {}

local pump

function pump(url)
    local q = queues[url]
    if q.pumping then return end
    q.pumping = true

    CreateThread(function()
        while #q.items > 0 or q.dropped > 0 do
            local wait = q.nextAt - GetGameTimer()
            if wait > 0 then Wait(wait) end

            local batch, size = {}, 0
            if q.dropped > 0 then
                batch[1] = { title = DROPPED_TITLE, color = 0xE67E22,
                    description = ('%d log line(s) were dropped — the queue was full.'):format(q.dropped) }
                size = embedSize(batch[1])
                q.dropped = 0
            end
            while #batch < MAX_EMBEDS and #q.items > 0 do
                local nextSize = embedSize(q.items[1])
                if #batch > 0 and size + nextSize > MAX_BATCH_CHARS then break end
                batch[#batch + 1] = table.remove(q.items, 1)
                size = size + nextSize
            end

            local interval = math.max(500, tonumber(Config.Logging.postIntervalMs) or 2000)
            q.nextAt = GetGameTimer() + interval

            PerformHttpRequest(url, function(status, _, headers)
                if status == 429 then
                    local after = headers and (headers['retry-after'] or headers['Retry-After'])
                    q.nextAt = GetGameTimer() + math.max(interval, math.floor((tonumber(after) or 2) * 1000))
                    -- Rate limited: nothing was posted. Put the batch back at the front.
                    for i = #batch, 1, -1 do
                        if batch[i].title ~= DROPPED_TITLE then table.insert(q.items, 1, batch[i]) end
                    end
                    pump(url)
                elseif status and (status < 200 or status >= 300) then
                    AJ.Print(('^3webhook answered HTTP %s — check the URL in configs/s.secrets.lua^0'):format(tostring(status)))
                end
            end, 'POST', json.encode({
                username = Config.Logging.username or 'Admin Jail',
                embeds = batch,
                allowed_mentions = { parse = {} },
            }), { ['Content-Type'] = 'application/json' })

            Wait(interval)
        end
        q.pumping = false
    end)
end

local function enqueue(url, embed)
    local q = queues[url]
    if not q then
        q = { items = {}, dropped = 0, nextAt = 0, pumping = false }
        queues[url] = q
    end
    if #q.items >= MAX_QUEUE then
        q.dropped = q.dropped + 1
        return
    end
    q.items[#q.items + 1] = embed
    pump(url)
end

-- ----------------------------------------------------------------------------
-- Formatting

local function code(v) return ('`%s`'):format(tostring(v):gsub('`', "'")) end

local function clip(text, n)
    text = tostring(text or '')
    local cut = AJ.Util.Cut(text, n - 1)
    if cut ~= text then return cut .. '…' end
    return text
end

--- One person as an embed field: name, character, server id, Discord mention + username,
--- Steam profile link, licence, FiveM id. `ids` is an Identity.Get() result or a stored
--- snapshot (offline sentences have no server id).
function Log.Person(role, ids, withAvatar)
    ids = ids or {}
    local lines = {}

    local head = ('**%s**'):format(clip(ids.name or 'unknown', 64))
    if ids.char and ids.char ~= ids.name then head = head .. (' · %s'):format(clip(ids.char, 64)) end
    if ids.source then head = head .. (' · ID %s'):format(ids.source) end
    lines[#lines + 1] = head

    local avatar
    if ids.discord then
        local user = Identity.DiscordUser(ids.discord)
        local tag = ''
        if user and user.username then
            tag = (' %s'):format(code(user.globalName and ('%s (@%s)'):format(user.globalName, user.username) or ('@' .. user.username)))
            avatar = user.avatar
        end
        lines[#lines + 1] = ('Discord: <@%s>%s · %s'):format(ids.discord, tag, code(ids.discord))
    else
        lines[#lines + 1] = 'Discord: —'
    end

    if ids.steam then
        local s64 = Identity.Steam64(ids.steam)
        lines[#lines + 1] = s64
            and ('Steam: [%s](https://steamcommunity.com/profiles/%s)'):format(s64, s64)
            or ('Steam: %s'):format(code('steam:' .. ids.steam))
    else
        lines[#lines + 1] = 'Steam: —'
    end

    lines[#lines + 1] = ('License: %s'):format(ids.license and code('license:' .. ids.license) or '—')
    if ids.fivem then lines[#lines + 1] = ('FiveM: %s'):format(code('fivem:' .. ids.fivem)) end

    return { name = role, value = clip(table.concat(lines, '\n'), 1024), inline = false }, withAvatar and avatar or nil
end

--- event   : key in Config.Logging.events
--- opts    : { title, description, inmate = ids, staff = ids, fields = { {name,value,inline} }, sentenceId }
--- Runs in its own thread — the Discord lookup is a network call.
function Log.Send(event, opts)
    if not enabled(event) then return end

    AJ.Print(('[%s] %s%s'):format(event, opts.title or '', opts.description and (' — ' .. opts.description:gsub('\n', ' | ')) or ''))

    local url = webhookFor(event)
    if not url then return end

    CreateThread(function()
        local fields, thumb = {}, nil

        if opts.inmate then
            local f, avatar = Log.Person('Inmate', opts.inmate, true)
            fields[#fields + 1] = f
            thumb = avatar
        end
        if opts.staff then
            fields[#fields + 1] = (Log.Person(opts.staffRole or 'Staff', opts.staff))
        end
        for _, f in ipairs(opts.fields or {}) do
            local value, inline = f[2], f[3]
            if inline == nil then inline = true end
            fields[#fields + 1] = {
                name = clip(f[1], 256),
                value = clip(value ~= nil and value ~= '' and tostring(value) or '—', 1024),
                inline = inline,
            }
        end

        local footer = Config.Logging.serverName or 'Admin Jail'
        if opts.sentenceId then footer = ('%s · sentence #%s'):format(footer, opts.sentenceId) end

        enqueue(url, {
            title = clip(opts.title or event, 256),
            description = opts.description and clip(opts.description, 4000) or nil,
            color = opts.color or Log.Color[event] or 0x5865F2,
            fields = fields,
            thumbnail = thumb and { url = thumb } or nil,
            footer = { text = footer },
            timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        })
    end)
end

function Log.Code(v) return code(v) end

function Log.Ready()
    local hooks, n = Config.Webhooks or {}, 0
    for _, url in pairs(hooks) do
        if type(url) == 'string' and url:match('^https://') then n = n + 1 end
    end
    if n == 0 then
        AJ.Print('logging: no webhooks set in configs/s.secrets.lua — console only.')
    else
        AJ.Print(('logging: %d webhook(s) configured%s.'):format(n,
            (type(Config.DiscordBotToken) == 'string' and Config.DiscordBotToken ~= '') and ', Discord usernames ON' or ''))
    end
end
