-- =============================================================================
--  pr-adminjail — database schema
--
--  Idempotent. Safe to run repeatedly and on a live database.
--  The resource creates these same tables at boot (Db.Ensure in s.lib.db.lua), so
--  running this file is optional. Keep the two in sync.
--
--      mysql -u root -p your_database < sql/install.sql
-- =============================================================================


-- One row per sentence. Identifiers are stored so a sentence follows the PERSON across
-- characters, licences and reconnects: any one of license / discord / steam / fivem matching
-- an active row puts them back in the yard. `release_pending` marks a sentence that ended
-- while the player was offline, so they are moved out of the yard on their next join.
CREATE TABLE IF NOT EXISTS `adminjail_sentences` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- Everything that ever happened to a sentence — jail, modify, transfer, escape attempts,
-- suspicious task calls, disconnects, release — plus staff changes (sentence_id NULL).
CREATE TABLE IF NOT EXISTS `adminjail_events` (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- Staff allowed to use the panel, managed in-game by owners. Owners themselves live in
-- configs/s.secrets.lua and never in this table.
CREATE TABLE IF NOT EXISTS `adminjail_staff` (
    `discord_id` VARCHAR(32)  NOT NULL,
    `label`      VARCHAR(64)  NOT NULL,
    `perms`      VARCHAR(255) NOT NULL DEFAULT '[]',
    `max_tasks`  INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 = Config.Sentence.maxTasks',
    `added_by`   VARCHAR(32)  NULL,
    `created_at` INT UNSIGNED NOT NULL,
    `updated_at` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`discord_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
