AJ = AJ or {}
AJ.Db = {}

local Db = AJ.Db

-- Same DDL as sql/install.sql — keep the two in sync. Run at boot so the SQL file is
-- optional; every statement is IF NOT EXISTS.
local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `adminjail_sentences` (
        `id`               INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `status`           VARCHAR(16)  NOT NULL DEFAULT 'active' COMMENT 'active|completed|released',
        `name`             VARCHAR(64)  NOT NULL,
        `char_name`        VARCHAR(64)  NULL,
        `license`          VARCHAR(64)  NULL,
        `discord`          VARCHAR(32)  NULL,
        `steam`            VARCHAR(32)  NULL,
        `fivem`            VARCHAR(32)  NULL,
        `tasks_total`      INT UNSIGNED NOT NULL,
        `tasks_done`       INT UNSIGNED NOT NULL DEFAULT 0,
        `penalty_tasks`    INT UNSIGNED NOT NULL DEFAULT 0,
        `escapes`          INT UNSIGNED NOT NULL DEFAULT 0,
        `yard`             VARCHAR(32)  NOT NULL,
        `bucket_mode`      VARCHAR(16)  NOT NULL,
        `bucket`           INT          NOT NULL,
        `reason`           VARCHAR(255) NOT NULL,
        `staff_discord`    VARCHAR(32)  NULL,
        `staff_name`       VARCHAR(64)  NULL,
        `offline`          TINYINT(1)   NOT NULL DEFAULT 0,
        `release_pending`  TINYINT(1)   NOT NULL DEFAULT 0 COMMENT 'ended while offline - move out on next join',
        `created_at`       INT UNSIGNED NOT NULL,
        `updated_at`       INT UNSIGNED NOT NULL,
        `ended_at`         INT UNSIGNED NULL,
        `ended_by_discord` VARCHAR(32)  NULL,
        `ended_by_name`    VARCHAR(64)  NULL,
        `end_reason`       VARCHAR(255) NULL,
        PRIMARY KEY (`id`),
        KEY `idx_aj_status`  (`status`),
        KEY `idx_aj_license` (`license`),
        KEY `idx_aj_discord` (`discord`),
        KEY `idx_aj_steam`   (`steam`),
        KEY `idx_aj_fivem`   (`fivem`),
        KEY `idx_aj_pending` (`release_pending`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `adminjail_events` (
        `id`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        `sentence_id`   INT UNSIGNED    NULL,
        `kind`          VARCHAR(24)     NOT NULL,
        `actor_discord` VARCHAR(32)     NULL,
        `actor_name`    VARCHAR(64)     NULL,
        `detail`        VARCHAR(512)    NULL,
        `created_at`    INT UNSIGNED    NOT NULL,
        PRIMARY KEY (`id`),
        KEY `idx_aj_ev_sentence` (`sentence_id`),
        KEY `idx_aj_ev_created`  (`created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS `adminjail_staff` (
        `discord_id` VARCHAR(32)  NOT NULL,
        `label`      VARCHAR(64)  NOT NULL,
        `perms`      VARCHAR(255) NOT NULL DEFAULT '[]',
        `max_tasks`  INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 = Config.Sentence.maxTasks',
        `added_by`   VARCHAR(32)  NULL,
        `created_at` INT UNSIGNED NOT NULL,
        `updated_at` INT UNSIGNED NOT NULL,
        PRIMARY KEY (`discord_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

function Db.Ensure()
    for i = 1, #SCHEMA do
        local ok, err = pcall(MySQL.query.await, SCHEMA[i])
        if not ok then
            AJ.Print(('^1database: could not create table %d: %s^0'):format(i, tostring(err)))
            return false
        end
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Sentences

local COLUMNS = {
    status = true, name = true, char_name = true, license = true, discord = true, steam = true,
    fivem = true, tasks_total = true, tasks_done = true, penalty_tasks = true, escapes = true,
    yard = true, bucket_mode = true, bucket = true, reason = true, staff_discord = true,
    staff_name = true, offline = true, release_pending = true, created_at = true,
    updated_at = true, ended_at = true, ended_by_discord = true, ended_by_name = true,
    end_reason = true,
}

function Db.ActiveSentences()
    return MySQL.query.await('SELECT * FROM `adminjail_sentences` WHERE `status` = ?', { 'active' }) or {}
end

function Db.Sentence(id)
    return MySQL.single.await('SELECT * FROM `adminjail_sentences` WHERE `id` = ?', { id })
end

function Db.InsertSentence(row)
    local cols, marks, values = {}, {}, {}
    for key, value in pairs(row) do
        if COLUMNS[key] then
            cols[#cols + 1] = ('`%s`'):format(key)
            marks[#marks + 1] = '?'
            values[#values + 1] = value
        end
    end
    return MySQL.insert.await(('INSERT INTO `adminjail_sentences` (%s) VALUES (%s)')
        :format(table.concat(cols, ','), table.concat(marks, ',')), values)
end

--- Partial update. Only whitelisted column names are ever written.
function Db.UpdateSentence(id, fields)
    local sets, values = {}, {}
    for key, value in pairs(fields) do
        if COLUMNS[key] then
            sets[#sets + 1] = ('`%s` = ?'):format(key)
            values[#values + 1] = value
        end
    end
    if #sets == 0 then return end
    sets[#sets + 1] = '`updated_at` = ?'
    values[#values + 1] = AJ.Now()
    values[#values + 1] = id
    MySQL.update(('UPDATE `adminjail_sentences` SET %s WHERE `id` = ?'):format(table.concat(sets, ', ')), values)
end

--- Fills identifiers a sentence was created without (offline jail by Discord id, say), the
--- first time the person is seen online. Never overwrites one that is already set. Also
--- marks the sentence as having reached the yard (`offline` = 0) — that assignment is LAST,
--- because MySQL evaluates SET left to right and the name IF() must see the old value.
function Db.BackfillIdentity(id, ids)
    MySQL.update([[UPDATE `adminjail_sentences` SET
        `license` = COALESCE(`license`, ?), `discord` = COALESCE(`discord`, ?),
        `steam` = COALESCE(`steam`, ?), `fivem` = COALESCE(`fivem`, ?),
        `char_name` = COALESCE(?, `char_name`),
        `name` = IF(`offline` = 1 AND `name` LIKE 'offline:%', ?, `name`),
        `offline` = 0
        WHERE `id` = ?]], { ids.license, ids.discord, ids.steam, ids.fivem,
            ids.char and AJ.Util.Cut(ids.char, 64) or nil, AJ.Util.Cut(ids.name, 64), id })
end

--- Ended sentences that still need the player moved out of the yard on their next join.
function Db.PendingReleases(ids)
    local where, values = {}, {}
    for _, kind in ipairs(AJ.Identity.MATCH) do
        if ids[kind] then
            where[#where + 1] = ('`%s` = ?'):format(kind)
            values[#values + 1] = ids[kind]
        end
    end
    if #where == 0 then return {} end
    return MySQL.query.await(('SELECT `id`, `status` FROM `adminjail_sentences` WHERE `release_pending` = 1 AND (%s)')
        :format(table.concat(where, ' OR ')), values) or {}
end

--- Fire-and-forget: clears every pending move-out for whoever owns these identifiers.
function Db.ClearPendingFor(ids)
    local where, values = {}, {}
    for _, kind in ipairs(AJ.Identity.MATCH) do
        if ids[kind] then
            where[#where + 1] = ('`%s` = ?'):format(kind)
            values[#values + 1] = ids[kind]
        end
    end
    if #where == 0 then return end
    MySQL.update(('UPDATE `adminjail_sentences` SET `release_pending` = 0 WHERE `release_pending` = 1 AND (%s)')
        :format(table.concat(where, ' OR ')), values)
end

function Db.ClearPending(id)
    MySQL.update('UPDATE `adminjail_sentences` SET `release_pending` = 0 WHERE `id` = ?', { id })
end

function Db.History(opts)
    local where, values = { '1 = 1' }, {}

    if opts.status and opts.status ~= 'all' then
        where[#where + 1] = '`status` = ?'
        values[#values + 1] = opts.status
    end

    if opts.search and opts.search ~= '' then
        local like = '%' .. opts.search:gsub('[%%_\\]', '\\%0') .. '%'
        where[#where + 1] = [[(`name` LIKE ? OR `char_name` LIKE ? OR `reason` LIKE ? OR `staff_name` LIKE ?
            OR `discord` = ? OR `license` = ? OR `steam` = ? OR `fivem` = ? OR `id` = ?)]]
        -- Identifiers are stored without their prefix; the panel shows and copies them with
        -- it ("discord:123…"), so parse first and fall back to the raw text.
        local _, parsed = AJ.Identity.Parse(opts.search)
        local exact = parsed or opts.search
        for _ = 1, 4 do values[#values + 1] = like end
        for _ = 1, 4 do values[#values + 1] = exact end
        values[#values + 1] = tonumber((opts.search:gsub('^#', ''))) or -1
    end

    local pageSize = 25
    local page = math.max(1, tonumber(opts.page) or 1)
    local clause = table.concat(where, ' AND ')

    local total = MySQL.scalar.await(('SELECT COUNT(*) FROM `adminjail_sentences` WHERE %s'):format(clause), values) or 0

    local paged = { table.unpack(values) }
    paged[#paged + 1] = pageSize
    paged[#paged + 1] = (page - 1) * pageSize
    local rows = MySQL.query.await(('SELECT * FROM `adminjail_sentences` WHERE %s ORDER BY `id` DESC LIMIT ? OFFSET ?')
        :format(clause), paged) or {}

    return rows, total, page, pageSize
end

-- ----------------------------------------------------------------------------
-- Event log

function Db.Event(sentenceId, kind, actor, detail)
    MySQL.insert('INSERT INTO `adminjail_events` (`sentence_id`, `kind`, `actor_discord`, `actor_name`, `detail`, `created_at`) VALUES (?, ?, ?, ?, ?, ?)', {
        sentenceId, kind, actor and actor.discord or nil, actor and actor.name and AJ.Util.Cut(actor.name, 64) or nil,
        detail and AJ.Util.Cut(tostring(detail), 500) or nil, AJ.Now(),
    })
end

function Db.Events(sentenceId)
    return MySQL.query.await('SELECT * FROM `adminjail_events` WHERE `sentence_id` = ? ORDER BY `id` DESC LIMIT 200', { sentenceId }) or {}
end

function Db.RecentEvents(limit)
    return MySQL.query.await('SELECT * FROM `adminjail_events` ORDER BY `id` DESC LIMIT ?', { limit or 100 }) or {}
end

-- ----------------------------------------------------------------------------
-- Staff

function Db.Staff()
    return MySQL.query.await('SELECT * FROM `adminjail_staff` ORDER BY `created_at` ASC') or {}
end

function Db.SaveStaff(row)
    MySQL.query.await([[INSERT INTO `adminjail_staff` (`discord_id`, `label`, `perms`, `max_tasks`, `added_by`, `created_at`, `updated_at`)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE `label` = VALUES(`label`), `perms` = VALUES(`perms`),
            `max_tasks` = VALUES(`max_tasks`), `updated_at` = VALUES(`updated_at`)]], {
        row.discord_id, row.label, row.perms, row.max_tasks, row.added_by, row.created_at, row.updated_at,
    })
end

function Db.DeleteStaff(discordId)
    MySQL.query.await('DELETE FROM `adminjail_staff` WHERE `discord_id` = ?', { discordId })
end
