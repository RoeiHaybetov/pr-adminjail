fx_version 'cerulean'
games { 'gta5' }
lua54 'yes'
use_experimental_fxv2_oal 'yes'

author 'pr'
description 'pr ADMINJAIL — community-service admin jail, served in tasks, not minutes'
version '1.0.0'

ox_lib 'locale'

ui_page 'ui/dist/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'configs/sh.config.lua',
    'escrowed/sh.const.lua',
}

client_scripts {
    'escrowed/client/c.util.lua',
    'escrowed/client/c.tasks.lua',
    'escrowed/client/c.main.lua',
    'escrowed/client/c.panel.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'configs/s.secrets.lua',
    'configs/s.hooks.lua',
    'escrowed/server/s.util.lua',
    'escrowed/server/s.lib.framework.lua',
    'escrowed/server/s.lib.identity.lua',
    'escrowed/server/s.lib.log.lua',
    'escrowed/server/s.lib.db.lua',
    'escrowed/server/s.lib.access.lua',
    'escrowed/server/s.lib.jail.lua',
    'escrowed/server/s.lib.tasks.lua',
    'escrowed/server/s.panel.lua',
    'escrowed/server/s.main.lua',
}

files {
    'locales/*.json',
    'ui/dist/**/*',
}

escrow_ignore {
    'configs/*.lua',
    'locales/*.json',
    'sql/*.sql',
}

dependencies {
    '/onesync',
    'ox_lib',
    'oxmysql',
}
