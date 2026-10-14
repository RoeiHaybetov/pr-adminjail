AJ = AJ or {}

local Util = {}
AJ.Util = Util

function AJ.Now()
    return os.time()
end

function AJ.Mono()
    return GetGameTimer()
end

function AJ.Print(message)
    print(('[%s] %s'):format(AJ.RESOURCE, message))
end

function AJ.Debug(message)
    if Config.Debug then print(('[%s][debug] %s'):format(AJ.RESOURCE, message)) end
end

function AJ.Notify(source, key, args, kind)
    if type(source) ~= 'number' or GetPlayerName(source) == nil then return end
    TriggerClientEvent(AJ.Event.NOTIFY, source, key, args, kind)
end

function AJ.Online(source)
    return type(source) == 'number' and source > 0 and GetPlayerName(source) ~= nil
end

--- Calls `fn(...)` from configs/s.hooks.lua inside a pcall.
function AJ.Hook(name, ...)
    local fn = Hooks and Hooks[name]
    if type(fn) ~= 'function' then return end
    local ok, err = pcall(fn, ...)
    if not ok then AJ.Print(('^1hook %s failed: %s^0'):format(name, tostring(err))) end
end

--- Cuts to at most `maxChars` CHARACTERS, never in the middle of a UTF-8 sequence — a
--- Hebrew letter is two bytes, and a half letter breaks the database and Discord.
function Util.Cut(value, maxChars)
    if type(value) ~= 'string' then return value end
    local n = utf8.len(value)
    if n then
        if n > maxChars then value = value:sub(1, utf8.offset(value, maxChars + 1) - 1) end
        return value
    end
    -- Invalid UTF-8 already: fall back to bytes, then drop any trailing partial sequence.
    value = value:sub(1, maxChars)
    while #value > 0 and not utf8.len(value) do value = value:sub(1, -2) end
    return value
end

function Util.Trim(value, maxLength)
    if type(value) ~= 'string' then return '' end
    value = value:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if maxLength then value = Util.Cut(value, maxLength) end
    return value
end

function Util.Int(value, min, max)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    value = math.floor(value)
    if min and value < min then return nil end
    if max and value > max then return nil end
    return value
end

function Util.Dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Util.Dist2D(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

function Util.Vec(v)
    if not v then return nil end
    return { x = v.x + 0.0, y = v.y + 0.0, z = v.z + 0.0, w = v.w and (v.w + 0.0) or nil }
end

function Util.Token()
    return ('%08x%08x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
end

--- Weighted pick from a list of { weight = n, ... }.
function Util.Weighted(list)
    local total = 0
    for i = 1, #list do total = total + (list[i].weight or 1) end
    if total <= 0 then return list[1] end
    local roll = math.random() * total
    for i = 1, #list do
        roll = roll - (list[i].weight or 1)
        if roll <= 0 then return list[i] end
    end
    return list[#list]
end

-- ----------------------------------------------------------------------------
-- Rate limiting — per player, per action, fixed window.

local LIMITS = {
    panel  = { max = 40, windowMs = 5000 },
    start  = { max = 6,  windowMs = 5000 },
    finish = { max = 6,  windowMs = 5000 },
    abort  = { max = 10, windowMs = 5000 },
    died   = { max = 3,  windowMs = 10000 },
    cmd    = { max = 6,  windowMs = 5000 },
    ready  = { max = 3,  windowMs = 10000 },
}

local buckets = {}

function Util.Rate(source, action)
    local limit = LIMITS[action] or LIMITS.panel
    local now = AJ.Mono()
    local mine = buckets[source]
    if not mine then mine = {}; buckets[source] = mine end

    local b = mine[action]
    if not b or now - b.start >= limit.windowMs then
        mine[action] = { count = 1, start = now }
        return true
    end
    if b.count >= limit.max then return false end
    b.count = b.count + 1
    return true
end

function Util.ClearRate(source)
    buckets[source] = nil
end

math.randomseed(os.time() + GetGameTimer())
