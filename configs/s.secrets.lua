--[[
    pr — ADMINJAIL secrets

    ==========================================================================================
    THIS FILE IS IN `server_scripts` ONLY. IT IS NEVER SENT TO A CLIENT.
    ==========================================================================================

    `sh.config.lua` is downloaded by every player who joins. A webhook URL is a bearer
    credential — whoever holds it can post to your channel or delete the hook — and a bot
    token is worse. So every webhook, the owner list and the bot token live here.
]]

Config = Config or {}

--- OWNERS — raw Discord user IDs, no `discord:` prefix.
--- Owners have every permission and are the only ones who can open the Staff tab and
--- decide who else may use the jail. Staff are managed in-game from the panel.
Config.Owners = {
    '720720916354564199',
}

--- Discord webhooks, one per channel you want. Any category left '' falls back to
--- `default`. Leave everything '' to disable Discord logging.
Config.Webhooks = {
    default    = '',

    jail       = '',   -- someone was jailed
    release    = '',   -- sentence cancelled by staff
    complete   = '',   -- sentence served to the last task
    modify     = '',   -- tasks added / removed / set, yard or bucket changed
    escape     = '',   -- left the leash, left the bucket, got in a vehicle
    suspicious = '',   -- teleport-to-task, early finish, forged task id, rate limits
    session    = '',   -- inmate disconnected / reconnected mid-sentence
    staff      = '',   -- staff added, removed or changed
    progress   = '',   -- per-task progress (only if Config.Logging.events.progress)
}

--- OPTIONAL. A Discord BOT token (not a webhook) lets the logs show each person's real
--- Discord username and avatar instead of only a mention. The bot needs no permissions
--- and does not even need to be in your server. Leave '' to skip the lookup.
Config.DiscordBotToken = ''
