AJ = AJ or {}
AJ.Identity = {}

local Identity = AJ.Identity

--- The identifier kinds a sentence is matched on. A sentence follows the PERSON: any one
--- of these matching an active sentence puts them back in the yard, so a new character,
--- a new Rockstar licence or a fresh Steam account alone does not get anyone out.
Identity.MATCH = { 'license', 'discord', 'steam', 'fivem' }

local PREFIX = {
    license = 'license:', license2 = 'license2:', discord = 'discord:',
    steam = 'steam:', fivem = 'fivem:', xbl = 'xbl:', live = 'live:',
}

--- Strips a known prefix. `discord:123` -> `123`, `steam:1100001...` -> `1100001...`.
function Identity.Raw(kind, value)
    if type(value) ~= 'string' then return nil end
    local p = PREFIX[kind]
    if p and value:sub(1, #p) == p then value = value:sub(#p + 1) end
    value = value:gsub('%s', '')
    return value ~= '' and value or nil
end

function Identity.Steam64(hex)
    if type(hex) ~= 'string' or not hex:match('^%x+$') then return nil end
    local n = math.tointeger(tonumber(hex, 16))
    return n and tostring(n) or nil
end

--- Identifiers never change during a session, so they are read once per player. The
--- character name can (character switch) and is refreshed at most every 30 s.
local known = {}
local CHAR_TTL_MS = 30000

--- Every identifier we care about for an online player, prefixes stripped. The returned
--- table is shared — treat it as read-only.
function Identity.Get(source)
    local entry = known[source]
    if not entry then
        local ids = { source = source, name = GetPlayerName(source) or ('player %s'):format(source) }
        for kind in pairs(PREFIX) do
            ids[kind] = Identity.Raw(kind, GetPlayerIdentifierByType(source, kind))
        end
        ids.steam64 = Identity.Steam64(ids.steam)
        entry = { ids = ids, charAt = -CHAR_TTL_MS }
        if GetPlayerName(source) then known[source] = entry end
    end

    local now = GetGameTimer()
    if now - entry.charAt >= CHAR_TTL_MS then
        entry.charAt = now
        entry.ids.char = AJ.Fw.CharName(source)
    end
    return entry.ids
end

function Identity.Forget(source)
    known[source] = nil
end

--- Normalises one identifier value to exactly what GetPlayerIdentifierByType gives (prefix
--- stripped, lowercase hex), or nil if it cannot be one. A value that can never match a
--- real player must be refused, not stored as a sentence nobody ever serves.
local function normalise(kind, value)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('%s', '')
    if kind == 'license' then
        value = value:lower()
        return (#value == 40 and value:match('^%x+$')) and value or nil
    elseif kind == 'steam' then
        if value:match('^7656119%d+$') then
            local n = math.tointeger(tonumber(value))
            return n and ('%x'):format(n) or nil
        end
        value = value:lower()
        return value:match('^1100001%x+$') and value or nil
    elseif kind == 'discord' then
        return (value:match('^%d+$') and #value >= 15 and #value <= 22) and value or nil
    elseif kind == 'fivem' then
        return value:match('^%d+$') and value or nil
    end
    return nil
end

--- Parse whatever a staff member pasted: `discord:123`, `<@123>`, `steam:1100…`, a steam64,
--- a raw 40-hex licence, a raw Discord id. Returns kind, value — or nil.
function Identity.Parse(text)
    if type(text) ~= 'string' then return nil end
    text = text:gsub('%s', ''):gsub('^<@!?(%d+)>$', 'discord:%1')
    if text == '' then return nil end

    local kind, value = text:match('^(%a+%d?):(.+)$')
    if kind then
        kind = kind:lower()
        value = normalise(kind, value)
        if not value then return nil end
        return kind, value
    end

    -- Bare values. Steam hex is checked BEFORE the Discord rule: a steam hex whose account
    -- digits are all 0-9 is otherwise indistinguishable from a number.
    if text:match('^7656119%d+$') then return 'steam', normalise('steam', text) end
    if #text == 15 and text:lower():match('^1100001%x+$') then return 'steam', text:lower() end
    if #text == 40 and text:match('^%x+$') then return 'license', text:lower() end
    if text:match('^%d+$') and #text >= 17 and #text <= 22 then return 'discord', text end
    return nil
end

-- ----------------------------------------------------------------------------
-- Discord username / avatar lookup, only when a bot token is configured.

local cache = {}
local CACHE_SECONDS = 6 * 3600

--- Synchronous inside a thread. Returns { username, globalName, avatar } or nil. Never
--- blocks longer than ~4 seconds, never throws.
function Identity.DiscordUser(id)
    local token = Config.DiscordBotToken
    if type(token) ~= 'string' or token == '' or type(id) ~= 'string' or not id:match('^%d+$') then
        return nil
    end

    local hit = cache[id]
    if hit and hit.expires > os.time() then return hit.user end

    local p, settled = promise.new(), false
    local function settle(value)
        if settled then return end
        settled = true
        p:resolve(value)
    end

    PerformHttpRequest(('https://discord.com/api/v10/users/%s'):format(id), function(status, body)
        if status ~= 200 or type(body) ~= 'string' then return settle(false) end
        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= 'table' then return settle(false) end

        local avatar
        if data.avatar then
            local ext = tostring(data.avatar):sub(1, 2) == 'a_' and 'gif' or 'png'
            avatar = ('https://cdn.discordapp.com/avatars/%s/%s.%s?size=128'):format(id, data.avatar, ext)
        end
        settle({ username = data.username, globalName = data.global_name, avatar = avatar })
    end, 'GET', '', { ['Authorization'] = 'Bot ' .. token })

    SetTimeout(4000, function() settle(false) end)
    local user = Citizen.Await(p) or nil
    cache[id] = { user = user, expires = os.time() + (user and CACHE_SECONDS or 300) }
    return user
end

--- A snapshot of who someone is, built once and stored with a sentence, so an offline
--- player's identity can still be logged and shown.
function Identity.Snapshot(ids)
    return {
        name = ids.name, char = ids.char,
        license = ids.license, discord = ids.discord, steam = ids.steam, fivem = ids.fivem,
    }
end
