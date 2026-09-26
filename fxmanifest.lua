fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'srp-multicharacter'
description 'Scene-based character selector for Qbox'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}

client_scripts {
    'client/scene.lua',
    'client/main.lua',
    'client/editor.lua',
}

ui_page 'web/build/index.html'

files {
    'web/build/index.html',
    'web/build/**/*',
}

dependencies {
    'qbx_core',
    'ox_lib',
    'oxmysql',
}
