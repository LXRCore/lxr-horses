--[[
    ██╗     ██╗  ██╗██████╗       ██╗  ██╗ ██████╗ ██████╗ ███████╗███████╗███████╗
    ██║     ╚██╗██╔╝██╔══██╗      ██║  ██║██╔═══██╗██╔══██╗██╔════╝██╔════╝██╔════╝
    ██║      ╚███╔╝ ██████╔╝█████╗███████║██║   ██║██████╔╝███████╗█████╗  ███████╗
    ██║      ██╔██╗ ██╔══██╗╚════╝██╔══██║██║   ██║██╔══██╗╚════██║██╔══╝  ╚════██║
    ███████╗██╔╝ ██╗██║  ██║      ██║  ██║╚██████╔╝██║  ██║███████║███████╗███████║
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝      ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝

    LXR Core - Horses & Stables

    Brand:       LXRCore — Lux Empire eXperience RedM Core
    Product:     wolves.land / The Land of Wolves
    Developer:   iBoss21 / LXRCore
    Website:     https://www.lxrcore.com
    Discord:     https://discord.gg/GAhk8cgXe9
    GitHub:      https://github.com/LXRCore

    Version: 1.0.0
    Performance Target: 0.00 ms idle

    Framework Support:
    - LXR Core v3 (Native — GetCoreObject / GetLXR)

    © 2026 iBoss21 / LXRCore | lxrcore.com | All Rights Reserved
]]

fx_version '3.0.0'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

name 'lxr-horses'
author 'iBoss21 / LXRCore'
description 'LXRCore v3 horses: ownership, stables, cores & bonding, tack, wild herds, training, market, breeding'
version '1.0.0'
repository 'https://github.com/LXRCore/lxr-horses'

shared_scripts {
    '@lxr-core/shared/import.lua',   -- LXRShared: the catalog, jobs, gangs, weapons, horses, prices
    'shared/locale.lua',
    'locales/*.lua',
    'config.lua',
    'shared/tack.lua',
    'shared/logic.lua',
}

client_scripts {
    'client/main.lua',
    'client/stable.lua',
}

server_script 'server/main.lua'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/lxr-ui.css',
    'html/stable.css',
    'html/fonts/*.woff2',
    'html/app.js',
    'html/img/*.png',
}

dependencies { 'lxr-core', 'lxr-inventory' }
