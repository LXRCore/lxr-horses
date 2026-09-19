--[[
    ██╗     ██╗  ██╗██████╗       ██╗  ██╗ ██████╗ ██████╗ ███████╗███████╗███████╗
    ██║     ╚██╗██╔╝██╔══██╗      ██║  ██║██╔═══██╗██╔══██╗██╔════╝██╔════╝██╔════╝
    ██║      ╚███╔╝ ██████╔╝█████╗███████║██║   ██║██████╔╝███████╗█████╗  ███████╗
    ██║      ██╔██╗ ██╔══██╗╚════╝██╔══██║██║   ██║██╔══██╗╚════██║██╔══╝  ╚════██║
    ███████╗██╔╝ ██╗██║  ██║      ██║  ██║╚██████╔╝██║  ██║███████║███████╗███████║
    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝      ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝

    🐺 LXR Core - Horses & Stables

    The horse is a character: it has a name, a temperament, cores that drain
    and fill, a bond that grows with care and breaks with neglect, tack that
    changes what it can do, and papers that say who owns it. Everything a
    stable, a rancher or a horse thief needs lives in this file.

    Data comes from the core catalog — LXRShared.Horses / HorseBreeds for
    breeds, coats, prices, stats and town availability; LXRShared.Items for
    feed, tonics, brushes and tack items. Nothing is duplicated here.

    ═══════════════════════════════════════════════════════════════════════════════
    SERVER INFORMATION
    ═══════════════════════════════════════════════════════════════════════════════

    Brand:       LXRCore — Lux Empire eXperience RedM Core
    Product:     wolves.land / The Land of Wolves 🐺
    Developer:   iBoss21 / LXRCore
    Website:     https://www.lxrcore.com
    Discord:     https://discord.gg/GAhk8cgXe9
    GitHub:      https://github.com/LXRCore

    Version: 1.0.0
    Performance Target: 0.00 ms idle; ~0.02 ms with a horse out (prompt + tag)

    © 2026 iBoss21 / LXRCore | lxrcore.com | All Rights Reserved
]]

Config = Config or {}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ LANGUAGE ██████████████████████████████████████████████
-- ████████████████████████████████████████████████████████████████████████████████
Config.Lang = 'en'   -- any file in locales/ ('en', 'ka'); missing keys fall back to English

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ OWNERSHIP ═════════════════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
Config.Ownership = {
    maxHorses          = 5,       -- per character (jobs below may raise it)
    maxHorsesByJob     = { rancher = 12, stable = 20, usmarshal = 8, stageline = 10 },
    maxFavorites       = 3,
    oneActiveHorse     = true,    -- only one owned horse out of the stable at a time
    nameMinLen         = 2,
    nameMaxLen         = 24,
    nameBlacklist      = { 'admin', 'nigger', 'hitler' },  -- lowercase substrings refused (logged as exploit)
    renamePrice        = 0.50,    -- brand re-registration at the county clerk
    transferEnabled    = true,    -- give a horse to another player (prompt near both)
    transferDistance   = 4.0,
    transferFee        = 0.50,    -- paid by the giver: bill of sale + brand transfer
    sellToStableMult   = nil,     -- nil: use catalog `sellMult` (0.45); number: override
    sellConditionMult  = true,    -- price scales with health / bond / age
    insurance = {
        enabled        = true,
        pricePct       = 10,      -- % of the horse value per policy
        durationDays   = 7,       -- real days
        revivePrice    = 0,       -- dead insured horse comes back for this at any stable
    },
    uninsuredDeath = 'permanent', -- 'permanent' (gone), 'stable' (returns injured after Config.Care.recoveryHours)
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ CORES, METABOLISM & BONDING ═══════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
-- Cores are 0–100. They tick on the server every `tickMin` minutes while the
-- horse is out; in the stable they slowly recover (stables feed and water).
Config.Care = {
    tickMin        = 5,
    drainPerTick   = { hunger = 2, thirst = 3, cleanliness = 1, mood = 1 },       -- out of the stable
    recoverPerTick = { hunger = 4, thirst = 6, cleanliness = 0, mood = 1, health = 3, stamina = 5 }, -- in the stable
    ridingDrain    = { stamina = 1, hunger = 1, thirst = 1 },                      -- extra per tick while ridden
    lowThreshold   = 25,      -- below this a core is "low": stat penalties + notifications
    penalties      = { hunger = { stamina = -2, speed = -1 }, thirst = { stamina = -3, health = -1 }, cleanliness = { mood = -1 }, mood = { handling = -1, courage = -1 } },
    neglect = {               -- both hunger and thirst under lowThreshold for this long → injured
        hoursToInjury = 6,
        bondLossPerTick = 1,
    },
    recoveryHours  = 8,       -- injured horse in the stable heals after this
    revive = {
        item            = 'horse_reviver',  -- catalog item; nil disables item revives
        timerSec        = 90,               -- downed horse dies after this unless revived
        tonicHealth     = 40,
        vetPrice        = 2.00,             -- veterinary call, 1899 rate
    },
    -- bonding: XP → level; the level gates whistle range, tricks and stat bonus
    bond = {
        levels        = { 0, 200, 450, 800, 1250 },   -- xp needed for level 1..5
        statBonusPerLevel = { stamina = 0.5, health = 0.5, courage = 0.5 },
        xp = {
            feed = 6, brush = 8, pat = 3, ride5min = 5, train = 15, calm = 10, revive = 20,
            neglectLossPerTick = 1,
        },
        cooldownMs = { feed = 60000, brush = 120000, pat = 20000 },
        whistleRangeByLevel = { 60.0, 120.0, 200.0, 350.0, 600.0 },
    },
    -- shoes wear out: without shoes the horse is slower on roads and loses health faster
    shoes = {
        enabled       = true,
        item          = 'horseshoe',
        lifeHours     = 72,      -- real hours ridden
        farrierJob    = 'blacksmith',  -- can fit shoes to any horse (else owner with the item)
        penalty       = { speed = -1, health = -1 },
    },
    dirt = {
        enabled       = true,
        muddyBelow    = 40,      -- cleanliness below this shows dirt (SetPedDirtLevel)
        rainCleans    = true,
        waterCleans   = true,
    },
    aging = {
        enabled       = true,
        gameDaysPerRealDay = 24,   -- how many horse "days" pass per real day
        primeUntil    = 4000,      -- days; after this stats slowly decline
        maxDays       = 8000,      -- dies of old age (insured or not; foal replaces if breeding is on)
        declinePerDay = 0.001,     -- stat points per day past prime
    },
}

-- Personalities: traits from the breed temperament with room to evolve.
-- Each has effects the client applies while the horse is out. Bond level
-- and care move a horse toward `improvesTo` / `worsensTo`.
Config.Personalities = {
    docile     = { label = 'Docile',     improvesTo = 'docile',   worsensTo = 'nervous',  effects = { skipWhistleChance = 0,  fleeGunfireChance = 5,  kickStrangers = false, buckChance = 0,  followDelayMs = 0 } },
    steady     = { label = 'Steady',     improvesTo = 'docile',   worsensTo = 'nervous',  effects = { skipWhistleChance = 0,  fleeGunfireChance = 10, kickStrangers = false, buckChance = 2,  followDelayMs = 300 } },
    spirited   = { label = 'Spirited',   improvesTo = 'steady',   worsensTo = 'fierce',   effects = { skipWhistleChance = 5,  fleeGunfireChance = 10, kickStrangers = false, buckChance = 6,  followDelayMs = 500, speedBonus = 0.5 } },
    nervous    = { label = 'Nervous',    improvesTo = 'steady',   worsensTo = 'nervous',  effects = { skipWhistleChance = 15, fleeGunfireChance = 40, kickStrangers = false, buckChance = 12, followDelayMs = 1500, fearsPredators = true } },
    fierce     = { label = 'Fierce',     improvesTo = 'spirited', worsensTo = 'fierce',   effects = { skipWhistleChance = 10, fleeGunfireChance = 0,  kickStrangers = true,  buckChance = 8,  followDelayMs = 800, defendsOwner = true } },
}
Config.PersonalityEvolution = { enabled = true, checkEveryBondLevel = true, improveIfMoodAbove = 70, worsenIfMoodBelow = 30 }

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ INTERACTIONS (prompts near your horse) ════════════════
-- ████████████████████████████████████████████████████████████████████████████████
-- Item effects come from the catalog (`effects.horse_*` on hay, oats, apple,
-- sugar_cube, horse_tonic, horse_meds, horse_brush …). Add a new feed by
-- adding an item with `horse_hunger` in lxr-core — no change here.
Config.Interactions = {
    distance     = 2.5,
    keys         = { feed = 0x9959A6F0, brush = 0x7F8D09B8, pat = 0x760A9C6F, lead = 0xCEFD9220, saddlebags = 0x6319DB71, tack = 0x8AAA0AD4, inspect = 0xC1989F95 },
    holdMs       = { feed = 800, brush = 800, pat = 0, lead = 0, saddlebags = 0, tack = 800, inspect = 0 },
    feedTags     = { 'horse_treat', 'horse_feed' },  -- items with these tags or `effects.horse_hunger` are offered
    brushItem    = 'horse_brush',
    hoofPickItem = 'hoof_pick',
    progressMs   = { feed = 4000, brush = 8000, pat = 1500, hoof = 5000 },
    allowOthersToFeed = true,   -- strangers may feed / pat (bond goes to the owner's horse anyway)
    allowOthersToBrush = false,
    mountedShortcuts = { feed = 0x4CC0E2FE, brush = 0x8CC9CD42 }, -- B / X while riding (nil = off)
}

-- Saddlebags: a stash on the horse, opened through lxr-inventory server-side.
Config.Saddlebags = {
    enabled        = true,
    baseSlots      = 10,
    baseWeight     = 20000,     -- grams; tack `stats.storage` adds slots, saddlebag_upgrade item adds weight
    upgradeWeight  = 15000,
    sharedWithJobs = { 'stable' },   -- jobs allowed to open any horse's bags (searches)
    lawCanSearch   = true,           -- job.type == 'leo' may open bags of a horse whose owner is cuffed/dead
    blacklist      = { 'gold_bar' },
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ SPAWNING & CALLING ════════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
Config.Spawn = {
    whistle          = true,    -- the game's whistle (H) calls the active horse
    whistleKey       = 0x24978A28, -- H
    command          = 'horse', -- chat command that calls / dismisses ('' = off)
    minDistance      = 6.0,     -- spawn at least this far away
    maxDistance      = 25.0,
    onlyOutdoors     = true,    -- refuse to spawn inside interiors
    everywhere       = false,   -- true: also inside towns/buildings (not recommended)
    respawnCooldownMs = 8000,
    followOffset     = -4.0,    -- distance behind the player when following
    returnToStableWhenFar = 400.0, -- horse walks "home" (despawns) when this far from its owner for 2 minutes
    fleeOnOwnerDeath = false,
    restrictedZones  = {        -- no calling here (church, prison, …)
        { label = 'Sisika Penitentiary', coords = vector3(3327.0, -698.0, 46.0), radius = 150.0 },
    },
    -- state bag written on every owned horse entity: other resources read it
    stateBag = 'lxr:horse',     -- { id, owner (citizenid), name, bond, personality }
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ STABLES ═══════════════════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
-- `town` links to LXRShared.Towns → the catalog decides which breeds this
-- stable stocks. `stockMult` scales prices; `tackTier` caps tack quality.
Config.Stables = {
    { id = 'valentine',  town = 'valentine',  label = 'Valentine Stable',    coords = vector3(-361.72, 789.25, 116.24), heading = 80.0,  spawn = vector3(-368.2, 787.9, 116.2), preview = vector3(-359.5, 780.0, 116.1), stockMult = 1.0, tackTier = 3, blip = true },
    { id = 'strawberry', town = 'strawberry', label = 'Strawberry Stable',   coords = vector3(-1874.2, -434.7, 159.9), heading = 190.0, spawn = vector3(-1868.0, -440.0, 160.0), preview = vector3(-1878.0, -428.0, 160.0), stockMult = 1.05, tackTier = 2, blip = true },
    { id = 'blackwater', town = 'blackwater', label = 'Blackwater Stable',   coords = vector3(-873.5, -1318.9, 43.7),  heading = 270.0, spawn = vector3(-880.0, -1312.0, 43.6), preview = vector3(-868.0, -1325.0, 43.7), stockMult = 1.1, tackTier = 4, blip = true },
    { id = 'saintdenis', town = 'saintdenis', label = 'Saint Denis Stable',  coords = vector3(2503.6, -1440.1, 46.3),  heading = 0.0,   spawn = vector3(2510.0, -1436.0, 46.3), preview = vector3(2498.0, -1446.0, 46.3), stockMult = 1.25, tackTier = 4, blip = true },
    { id = 'rhodes',     town = 'rhodes',     label = 'Rhodes Stable',       coords = vector3(1381.3, -1289.0, 78.0),  heading = 130.0, spawn = vector3(1388.0, -1285.0, 78.0), preview = vector3(1375.0, -1294.0, 78.0), stockMult = 1.0, tackTier = 3, blip = true },
    { id = 'tumbleweed', town = 'tumbleweed', label = 'Tumbleweed Stable',   coords = vector3(-5488.6, -2951.2, -1.3), heading = 320.0, spawn = vector3(-5480.0, -2946.0, -1.3), preview = vector3(-5495.0, -2956.0, -1.3), stockMult = 0.95, tackTier = 2, blip = true },
    { id = 'armadillo',  town = 'armadillo',  label = 'Armadillo Stable',    coords = vector3(-3636.9, -2683.8, -14.6), heading = 45.0, spawn = vector3(-3630.0, -2680.0, -14.6), preview = vector3(-3644.0, -2688.0, -14.6), stockMult = 0.95, tackTier = 2, blip = true },
    { id = 'annesburg',  town = 'annesburg',  label = 'Annesburg Livery',    coords = vector3(2879.4, 1362.7, 63.6),   heading = 100.0, spawn = vector3(2886.0, 1366.0, 63.6), preview = vector3(2873.0, 1358.0, 63.6), stockMult = 1.05, tackTier = 2, blip = true },
}
Config.StableUI = {
    key            = 0xC7B5340A,   -- ENTER at the stable prompt
    promptDistance = 2.0,
    blipSprite     = 'blip_stable',
    boardingFee    = 0.50,          -- livery board per day, 1899 rate (0 = free); charged on next visit
    buyRequiresPapers = false,      -- give `horse_deed` item on purchase (papers other resources can check)
    giveDeedItem   = true,
    previewCamera  = true,
    previewScaleRange = { 0.95, 1.05 }, -- cosmetic size choice at purchase
    genderChoice   = true,          -- buyer picks stallion / mare / gelding (breeding needs male+female)
    tackShop       = true,
    sellTackMult   = 0.5,
    marketTax      = 5,             -- % on player-to-player listings (Config.Market)
}

-- Player market: list a horse at a stable; buyers browse from any stable.
Config.Market = {
    enabled     = true,
    minPrice    = 5,
    maxPrice    = 10000,
    listingDays = 7,
    maxListings = 3,
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ WILD HORSES ═══════════════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
Config.Wild = {
    enabled          = true,
    herds = {   -- region herds: breeds are drawn from LXRShared.HorseBreeds with wild = true unless `models` is given
        { id = 'heartlands', label = 'The Heartlands', coords = vector3(1150.0, 300.0, 90.0), radius = 400.0, size = { 4, 8 }, breeds = { 'tennesseewalker', 'mustang', 'nokota' }, chanceRare = 5 },
        { id = 'bigvalley',  label = 'Big Valley',     coords = vector3(-1700.0, 500.0, 120.0), radius = 500.0, size = { 3, 6 }, breeds = { 'mustang', 'appaloosa', 'americanpaint' }, chanceRare = 8 },
        { id = 'grizzlies',  label = 'Grizzlies West', coords = vector3(-1300.0, 1900.0, 250.0), radius = 400.0, size = { 2, 4 }, breeds = { 'nokota', 'mustang' }, chanceRare = 10 },
        { id = 'newaustin',  label = 'Rio Bravo',      coords = vector3(-4500.0, -3200.0, 20.0), radius = 600.0, size = { 4, 8 }, breeds = { 'mustang', 'criollo' }, chanceRare = 6 },
        { id = 'isabella',   label = 'Lake Isabella',  coords = vector3(-2200.0, 1650.0, 280.0), radius = 150.0, size = { 1, 1 }, models = { 'a_c_horse_arabian_white' }, chanceRare = 100, cooldownMin = 720 },
    },
    respawnMin       = 45,       -- minutes after a herd is emptied
    taming = {
        requireLasso   = true,   -- catch with the lasso (weapon_lasso) then mount to calm
        calmSeconds    = 12,     -- stay mounted this long (bucking mini-game handled by the game)
        breakChance    = 35,     -- % the horse throws you on the first try (minus bond skill)
        skill          = 'horsemanship',  -- xp skill in Config.Catalog.skills
        xpOnTame       = 25,
        minSkillLevelForTier = { [4] = 3, [5] = 5 },
    },
    claim = {
        atStableOnly  = true,    -- a tamed wild horse must be ridden to a stable to be registered
        feePct        = 30,      -- % of catalog price as registration fee
        cooldownMin   = 60,      -- per player between claims
        maxPerDay     = 3,
        sellInsteadPct = 20,     -- sell a wild catch to the stable for this % of value instead of claiming
    },
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ TRAINING ══════════════════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
Config.Training = {
    enabled        = true,
    courses = {
        { id = 'valentine_paddock', label = 'Valentine Paddock', start = vector3(-401.0, 762.0, 116.0), checkpoints = { vector3(-420.0, 770.0, 116.0), vector3(-440.0, 740.0, 116.0), vector3(-410.0, 720.0, 116.0), vector3(-395.0, 750.0, 116.0) }, radius = 3.0, timeLimitSec = 90, xp = 15, statTraining = 'handling' },
        { id = 'blackwater_run',    label = 'Blackwater Run',    start = vector3(-948.0, -1339.0, 50.0), checkpoints = { vector3(-962.0, -1339.0, 49.7), vector3(-973.0, -1333.0, 50.6), vector3(-972.0, -1320.0, 50.2), vector3(-964.0, -1305.0, 49.4), vector3(-947.0, -1305.0, 49.1) }, radius = 3.0, timeLimitSec = 60, xp = 20, statTraining = 'speed' },
    },
    cooldownMin    = 30,       -- per horse
    maxStatBonus   = 2,        -- trained bonus cap per stat (added to catalog stats)
    bonusPerSuccess = 0.25,
    fee            = 0.50,
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ BREEDING (v1: simple, honest) ═════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
Config.Breeding = {
    enabled        = true,
    atStable       = true,      -- pair a stallion and a mare you own at a stable
    fee            = 10.00,    -- stud fee
    gestationHours = 48,        -- real hours
    cooldownHours  = 96,        -- per mare
    minBond        = 3,         -- both parents
    foalTakesBreedOf = 'random', -- 'random' | 'dam' | 'sire'
    statInheritance = { parentAvgWeight = 0.7, breedBaseWeight = 0.3, variance = 1 }, -- ±variance points
    crossBreedTier = 'lower',   -- foal tier = lower | higher | average of parents' breeds
    maxGenerations = 5,         -- genealogy kept this deep
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ HORSE TAG (overhead) ══════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
Config.Tag = {
    enabled     = true,
    ownerOnly   = true,       -- others only see the name (when `showNamesToOthers`)
    showNamesToOthers = true,
    range       = 30.0,
    toggleKey   = 0x4BC9DABB, -- N
    show        = { 'name', 'bond', 'hunger', 'thirst', 'cleanliness', 'mood', 'personality' },
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ SECURITY ══════════════════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
Config.Security = {
    rateLimit          = { burst = 20, windowMs = 5000 },
    spawnReportRange   = 60.0,     -- client must report the spawned horse from within this range
    interactRange      = 6.0,      -- server re-checks distance for feed/brush/tack
    stableRange        = 8.0,      -- server re-checks the player is at the stable for stable actions
    maxHorseSpeedAudit = 30.0,     -- m/s; faster than this while mounted is logged (speed hacks)
    logExploits        = true,
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ TACK OVERRIDES ════════════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
-- Rename / re-price / restrict any piece from shared/tack.lua by id.
Config.TackOverrides = {
    saddle_1  = { label = 'Worn Saddle', price = 5 },
    saddle_2  = { label = 'Leather Saddle', price = 10, tier = 2, stats = { stamina = 1 } },
    saddle_3  = { label = 'Western Saddle', price = 18, tier = 3, stats = { stamina = 2, health = 1 } },
    saddle_4  = { label = 'McClellan Saddle', price = 12, tier = 3, stats = { stamina = 2, speed = 1 }, jobs = { 'usmarshal', 'vallaw', 'blklaw', 'sdlaw' } },
    saddle_5  = { label = 'Ornate Saddle', price = 45, tier = 4, stats = { stamina = 3, health = 2, speed = 1 } },
    saddlebag_1 = { label = 'Small Saddlebags', price = 1.50 },
    saddlebag_2 = { label = 'Large Saddlebags', price = 3, tier = 2, stats = { storage = 15 } },
    mask_1    = { label = 'Racing Mask', price = 1.50 },
}

-- ████████████████████████████████████████████████████████████████████████████████
-- ████████████████████████ DEBUG ═════════════════════════════════════════════════
-- ████████████████████████████████████████████████████████████████████████████████
Config.Debug = { enabled = false, printBanner = true, adminCommands = true }
