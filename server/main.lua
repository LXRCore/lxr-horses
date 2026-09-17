--[[ ═══════════════════════════════════════════════════════════════════════════
     🐺 LXR-HORSES — Server: ownership, stables, cores, wild herds, breeding
     ═══════════════════════════════════════════════════════════════════════════
     The server owns every horse record and every decision. Clients ask
     (LXR.RPC) and report entity facts the server can re-check on its own
     copy of the entity (position, health, model). Cores tick here; the
     client only animates what it is told.
     ═══════════════════════════════════════════════════════════════════════════
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

local LXRCore = exports['lxr-core']:GetCoreObject()
local LXR = exports['lxr-core']:GetLXR()
local H = LXRHorses.Logic
local RES = GetCurrentResourceName()

local cache = {}      -- citizenid → { [id] = record }  (loaded on first use)
local active = {}     -- src → { id, netId, since, ridingAt, lastTick }
local byNet = {}      -- netId → src
local buckets = {}
local cooldowns = {}  -- src → { action = ms }
local wild = {}       -- herdId → { netIds = { [netId] = model }, emptiedAt, host }
local tamed = {}      -- src → { model, netId, at }
local claimLog = {}   -- citizenid → { lastAt, today = n, day = yyyymmdd }
local pendingTransfers = {} -- targetSrc → { from = src, id, expires }

local function log(level, msg, data) LXRCore.Log[level]('horses', msg, data) end
local function notify(src, key, kind, vars) LXRCore.Notify(src, Lang:t(key, vars), kind or 'error') end

local function limited(src)
    local b = buckets[src]
    local now = GetGameTimer()
    if not b or now - b.at > Config.Security.rateLimit.windowMs then b = { at = now, n = 0 } buckets[src] = b end
    b.n = b.n + 1
    return b.n > Config.Security.rateLimit.burst
end

local function onCooldown(src, action, ms)
    cooldowns[src] = cooldowns[src] or {}
    local now = GetGameTimer()
    if cooldowns[src][action] and now - cooldowns[src][action] < ms then return true end
    cooldowns[src][action] = now
    return false
end

local function player(src) return LXRCore.Functions.GetPlayer(src) end
local function cid(src) local P = player(src) return P and P.PlayerData.citizenid or nil end

local function distance(src, coords)
    local ped = GetPlayerPed(src)
    if ped == 0 or not coords then return math.huge end
    return #(GetEntityCoords(ped) - vector3(coords.x, coords.y, coords.z))
end

local function stableById(id) for _, s in ipairs(Config.Stables) do if s.id == id then return s end end end

local function atStable(src, stableId)
    local s = stableById(stableId)
    if not s then return nil, 'invalid' end
    if distance(src, s.coords) > Config.Security.stableRange then
        LXRCore.Log.exploit(src, 'stable action away from the stable', { stable = stableId })
        return nil, 'too_far'
    end
    return s
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 💾 PERSISTENCE
-- ═══════════════════════════════════════════════════════════════════════════════
LXRCore.DB.RegisterMigration(RES, '0001_lxr_horses', [[
CREATE TABLE IF NOT EXISTS `lxr_horses` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(50) NOT NULL,
  `model` VARCHAR(80) NOT NULL,
  `name` VARCHAR(40) NOT NULL,
  `gender` VARCHAR(10) NOT NULL DEFAULT 'gelding',
  `data` LONGTEXT NOT NULL,
  `active` TINYINT(1) NOT NULL DEFAULT 0,
  `favorite` TINYINT(1) NOT NULL DEFAULT 0,
  `dead` TINYINT(1) NOT NULL DEFAULT 0,
  `listing` LONGTEXT DEFAULT NULL,
  `stable` VARCHAR(32) DEFAULT NULL,
  `sire_id` INT(11) DEFAULT NULL,
  `dam_id` INT(11) DEFAULT NULL,
  `born_at` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_owner` (`citizenid`, `dead`),
  KEY `idx_listing` (`listing`(1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS `lxr_horse_tack` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(50) NOT NULL,
  `piece` VARCHAR(40) NOT NULL,
  `horse_id` INT(11) DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_owner` (`citizenid`),
  KEY `idx_horse` (`horse_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE IF NOT EXISTS `lxr_horse_breeding` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(50) NOT NULL,
  `sire_id` INT(11) NOT NULL,
  `dam_id` INT(11) NOT NULL,
  `stable` VARCHAR(32) NOT NULL,
  `due_at` TIMESTAMP NOT NULL,
  `done` TINYINT(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_owner` (`citizenid`, `done`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
]])
LXRCore.Player.RegisterCharacterTable('lxr_horses')
LXRCore.Player.RegisterCharacterTable('lxr_horse_tack')

local function rowToRecord(row)
    local rec = json.decode(row.data or '{}') or {}
    rec.id, rec.citizenid, rec.model, rec.name, rec.gender = row.id, row.citizenid, row.model, row.name, row.gender
    rec.active, rec.favorite, rec.dead = row.active == 1, row.favorite == 1, row.dead == 1
    rec.listing = row.listing and json.decode(row.listing) or nil
    rec.stable, rec.sireId, rec.damId = row.stable, row.sire_id, row.dam_id
    rec.updatedAt = row.updated_at
    rec.cores = rec.cores or H.NewRecord(rec.model).cores
    rec.stats = rec.stats or H.NewRecord(rec.model).stats
    rec.tack = rec.tack or {}
    return rec
end

local function serialize(rec)
    local copy = {}
    for k, v in pairs(rec) do
        if not ({ id = 1, citizenid = 1, model = 1, name = 1, gender = 1, active = 1, favorite = 1, dead = 1, listing = 1, stable = 1, sireId = 1, damId = 1, updatedAt = 1 })[k] then copy[k] = v end
    end
    return json.encode(copy)
end

local function loadOwned(citizenid)
    if cache[citizenid] then return cache[citizenid] end
    local rows = LXRCore.DB.Query('SELECT * FROM lxr_horses WHERE citizenid = ?', { citizenid }) or {}
    local out = {}
    for _, row in ipairs(rows) do
        local rec = rowToRecord(row)
        -- horses resting in the stable recover for the time they were away
        if not rec.active and not rec.dead and row.updated_at then
            local elapsedMin = math.max(0, (os.time() - (type(row.updated_at) == 'number' and row.updated_at / 1000 or os.time())) / 60)
            local ticks = math.floor(elapsedMin / Config.Care.tickMin)
            if ticks > 0 then H.Tick(rec, { inStable = true, ticks = math.min(ticks, 500) }) end
            if rec.injured and elapsedMin >= Config.Care.recoveryHours * 60 then rec.injured = false rec.cores.health = math.max(rec.cores.health, 60) end
        end
        out[rec.id] = rec
    end
    cache[citizenid] = out
    return out
end

local function save(rec)
    LXRCore.DB.UpdateAsync('UPDATE lxr_horses SET name = ?, gender = ?, data = ?, active = ?, favorite = ?, dead = ?, listing = ?, stable = ?, citizenid = ? WHERE id = ?',
        { rec.name, rec.gender, serialize(rec), rec.active and 1 or 0, rec.favorite and 1 or 0, rec.dead and 1 or 0, rec.listing and json.encode(rec.listing) or nil, rec.stable, rec.citizenid, rec.id })
end

local function insert(rec)
    local id = LXRCore.DB.Insert('INSERT INTO lxr_horses (citizenid, model, name, gender, data, active, favorite, dead, stable, sire_id, dam_id, born_at) VALUES (?, ?, ?, ?, ?, 0, 0, 0, ?, ?, ?, NOW())',
        { rec.citizenid, rec.model, rec.name, rec.gender, serialize(rec), rec.stable, rec.sireId, rec.damId })
    rec.id = id
    if cache[rec.citizenid] then cache[rec.citizenid][id] = rec end
    return id
end

local function ownedTack(citizenid)
    return LXRCore.DB.Query('SELECT id, piece, horse_id FROM lxr_horse_tack WHERE citizenid = ?', { citizenid }) or {}
end

local function horseOf(src, id)
    local c = cid(src)
    if not c then return nil, 'no_player' end
    local rec = loadOwned(c)[tonumber(id) or -1]
    if not rec then return nil, 'not_owner' end
    return rec
end

local function countOwned(citizenid, job)
    local n = 0
    for _, r in pairs(loadOwned(citizenid)) do if not r.dead then n = n + 1 end end
    local limit = Config.Ownership.maxHorses
    if job and Config.Ownership.maxHorsesByJob[job] then limit = Config.Ownership.maxHorsesByJob[job] end
    return n, limit
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 📤 VIEWS
-- ═══════════════════════════════════════════════════════════════════════════════
local function view(rec)
    local cat = H.Catalog(rec.model)
    return {
        id = rec.id, model = rec.model, name = rec.name, gender = rec.gender, coat = cat and cat.coat, breed = cat and LXRShared.HorseBreeds[cat.breed].label,
        breedKey = cat and cat.breed, tier = cat and cat.tier, class = cat and cat.class,
        stats = H.EffectiveStats(rec), base = cat and cat.stats, trained = rec.stats, cores = rec.cores,
        xp = rec.xp, bond = H.BondLevel(rec.xp), bondProgress = H.BondProgress(rec.xp),
        personality = rec.personality, personalityLabel = (Config.Personalities[rec.personality] or {}).label,
        tack = rec.tack, ageDays = math.floor(rec.ageDays or 0), injured = rec.injured, dead = rec.dead,
        active = rec.active, favorite = rec.favorite, insuredUntil = rec.insuredUntil, listing = rec.listing,
        sellValue = H.SellValue(rec), insurancePrice = H.InsurancePrice(rec), scale = rec.scale,
        sireId = rec.sireId, damId = rec.damId, shoesLeft = math.max(0, Config.Care.shoes.lifeHours - (rec.shoesHours or 0)),
    }
end

local function stockFor(stable, Player)
    local out = {}
    for _, h in ipairs(LXRShared.HorsesForTown(stable.town)) do
        if not h.wild or #(h.availability or {}) > 0 then
            out[#out + 1] = { model = h.model, label = h.label, breed = LXRShared.HorseBreeds[h.breed].label, breedKey = h.breed, coat = h.coat,
                class = h.class, tier = h.tier, rarity = h.rarity, stats = h.stats, price = H.BuyPrice(h.model, stable),
                temperament = h.temperament, description = LXRShared.HorseBreeds[h.breed].description }
        end
    end
    return out
end

local function tackShopFor(stable, Player)
    local out = {}
    local job = Player.PlayerData.job.name
    for slot, list in pairs(LXRHorses.Tack) do
        for _, p in ipairs(list) do
            local okJob = p.jobs == nil
            if not okJob then for _, j in ipairs(p.jobs) do if j == job then okJob = true end end end
            if p.tier <= (stable.tackTier or 4) and okJob then
                out[#out + 1] = { id = p.id, slot = slot, label = p.label, price = p.price, tier = p.tier, stats = p.stats }
            end
        end
    end
    table.sort(out, function(a, b) if a.slot == b.slot then return a.price < b.price end return a.slot < b.slot end)
    return out
end

local function marketListings()
    local rows = LXRCore.DB.Query('SELECT * FROM lxr_horses WHERE listing IS NOT NULL AND dead = 0', {}) or {}
    local out = {}
    local now = os.time()
    for _, row in ipairs(rows) do
        local rec = rowToRecord(row)
        if rec.listing and (rec.listing.expires or 0) > now then
            local v = view(rec)
            v.seller = rec.listing.seller
            v.price = rec.listing.price
            out[#out + 1] = v
        end
    end
    return out
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🏇 ACTIVE HORSES — spawn / store / state
-- ═══════════════════════════════════════════════════════════════════════════════
local function publishState(src)
    local a = active[src]
    if not a or not a.netId then return end
    local rec = horseOf(src, a.id)
    if not rec then return end
    local ent = NetworkGetEntityFromNetworkId(a.netId)
    if ent and ent ~= 0 then
        Entity(ent).state:set(Config.Spawn.stateBag, {
            id = rec.id, owner = rec.citizenid, name = rec.name, bond = H.BondLevel(rec.xp), personality = rec.personality,
            cores = rec.cores, stats = H.EffectiveStats(rec), tack = rec.tack, injured = rec.injured, scale = rec.scale,
        }, true)
    end
end

local function store(src, reason)
    local a = active[src]
    if not a then return end
    local rec = horseOf(src, a.id)
    if rec then
        rec.active = false
        save(rec)
    end
    if a.netId then byNet[a.netId] = nil end
    active[src] = nil
    TriggerClientEvent('lxr-horses:client:despawn', src, a.id, reason)
    LXRCore.Emit('lxr:horse:stored', {}, src, a.id, reason)
end

LXR.RPC.Register('lxr-horses:call', function(src, horseId)
    if limited(src) then return false, 'rate' end
    local Player = player(src)
    if not Player then return false, 'no_player' end
    local md = Player.PlayerData.metadata or {}
    if md.isdead or md.ishandcuffed then return false, 'busy' end
    if onCooldown(src, 'call', Config.Spawn.respawnCooldownMs) then return false, 'cooldown' end
    local coords = GetEntityCoords(GetPlayerPed(src))
    for _, z in ipairs(Config.Spawn.restrictedZones) do
        if #(coords - z.coords) <= z.radius then return false, 'restricted' end
    end
    local c = cid(src)
    local owned = loadOwned(c)
    local rec
    if horseId then rec = owned[tonumber(horseId)] else
        for _, r in pairs(owned) do if r.active then rec = r break end end
        if not rec then for _, r in pairs(owned) do if r.favorite and not r.dead then rec = r break end end end
    end
    if not rec or rec.dead then return false, 'no_horse' end
    if rec.injured then return false, 'injured' end
    if rec.listing then return false, 'listed' end
    if active[src] and active[src].id ~= rec.id then store(src, 'switch') end
    for _, r in pairs(owned) do if r.active and r.id ~= rec.id then r.active = false save(r) end end
    rec.active = true
    save(rec)
    active[src] = { id = rec.id, since = GetGameTimer(), lastTick = GetGameTimer() }
    return true, view(rec)
end)

RegisterNetEvent('lxr-horses:server:spawned', function(id, netId)
    local src = source
    if limited(src) then return end
    local a = active[src]
    if not a or a.id ~= tonumber(id) then return LXRCore.Log.exploit(src, 'spawn report for a horse not called', { id = tostring(id) }) end
    local ent = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not ent or ent == 0 then return end
    local rec = horseOf(src, a.id)
    if not rec then return end
    if GetEntityModel(ent) ~= joaat(rec.model) then
        LXRCore.Log.exploit(src, 'spawned horse model mismatch', { id = a.id, expected = rec.model })
        return store(src, 'bad_model')
    end
    if distance(src, GetEntityCoords(ent)) > Config.Security.spawnReportRange then
        LXRCore.Log.exploit(src, 'spawned horse too far from the player', { id = a.id })
        return store(src, 'bad_spawn')
    end
    a.netId = tonumber(netId)
    byNet[a.netId] = src
    publishState(src)
    LXRCore.Emit('lxr:horse:spawned', {}, src, rec.id, a.netId)
end)

RegisterNetEvent('lxr-horses:server:store', function(reason)
    local src = source
    if active[src] then store(src, reason or 'stored') end
end)

-- client reports riding; server confirms the player is actually on the entity
RegisterNetEvent('lxr-horses:server:riding', function()
    local src = source
    local a = active[src]
    if not a or not a.netId then return end
    local ent = NetworkGetEntityFromNetworkId(a.netId)
    if ent == 0 or distance(src, GetEntityCoords(ent)) > 3.0 then return end
    a.ridingAt = GetGameTimer()
    -- speed audit
    local v = GetEntityVelocity(ent)
    local speed = #(v)
    if speed > Config.Security.maxHorseSpeedAudit then LXRCore.Log.exploit(src, 'horse speed audit', { speed = speed, id = a.id }) end
end)

RegisterNetEvent('lxr-horses:server:health', function(kind)
    local src = source
    local a = active[src]
    if not a or not a.netId then return end
    local ent = NetworkGetEntityFromNetworkId(a.netId)
    if ent == 0 then return end
    local rec = horseOf(src, a.id)
    if not rec then return end
    local hp = GetEntityHealth(ent)
    if kind == 'dead' then
        if hp > 0 then return LXRCore.Log.exploit(src, 'reported a live horse as dead', { id = a.id }) end
        local insured = (rec.insuredUntil or 0) > os.time()
        if insured then
            rec.dead = false rec.injured = true rec.cores.health = 30
            notify(src, 'info.horse_dead_insured', 'error', { name = rec.name })
        elseif Config.Ownership.uninsuredDeath == 'stable' then
            rec.injured = true rec.cores.health = 10
            notify(src, 'info.horse_dead_stable', 'error', { name = rec.name })
        else
            rec.dead = true
            notify(src, 'info.horse_dead', 'error', { name = rec.name })
        end
        rec.active = false
        save(rec)
        LXRCore.Emit('lxr:horse:died', {}, src, rec.id, insured)
        if a.netId then byNet[a.netId] = nil end
        active[src] = nil
    elseif kind == 'injured' then
        rec.injured = true
        rec.cores.health = math.min(rec.cores.health, 20)
        save(rec)
        publishState(src)
        LXRCore.Emit('lxr:horse:injured', {}, src, rec.id)
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🍎 INTERACTIONS — feed / brush / pat / hoof / revive (items from the catalog)
-- ═══════════════════════════════════════════════════════════════════════════════
local function nearOwnHorse(src, allowOthers)
    local a = active[src]
    local ownerSrc = src
    if not a or not a.netId then
        if not allowOthers then return nil, 'no_horse' end
        -- someone else's horse nearby
        local ped = GetPlayerPed(src)
        local pos = GetEntityCoords(ped)
        for netId, owner in pairs(byNet) do
            local ent = NetworkGetEntityFromNetworkId(netId)
            if ent ~= 0 and #(GetEntityCoords(ent) - pos) <= Config.Security.interactRange then a, ownerSrc = active[owner], owner break end
        end
        if not a then return nil, 'no_horse' end
    end
    local ent = NetworkGetEntityFromNetworkId(a.netId)
    if ent == 0 or distance(src, GetEntityCoords(ent)) > Config.Security.interactRange then return nil, 'too_far' end
    local rec = horseOf(ownerSrc, a.id)
    if not rec then return nil, 'no_horse' end
    return rec, ent, ownerSrc
end

LXR.RPC.Register('lxr-horses:interact', function(src, action, itemName)
    if limited(src) then return false, 'rate' end
    local Player = player(src)
    if not Player then return false, 'no_player' end
    local allowOthers = (action == 'feed' and Config.Interactions.allowOthersToFeed) or (action == 'pat') or (action == 'brush' and Config.Interactions.allowOthersToBrush)
    local rec, ent, ownerSrc = nearOwnHorse(src, allowOthers)
    if not rec then return false, ent end
    local cdKey = action .. ':' .. rec.id
    local cd = Config.Care.bond.cooldownMs[action] or 0
    if cd > 0 and onCooldown(src, cdKey, cd) then return false, 'cooldown' end
    local xp = 0
    if action == 'feed' or action == 'revive' or action == 'tonic' then
        local def = LXRShared.Items[tostring(itemName or ''):lower()]
        if not def or not H.ItemHorseEffects(def) then return false, 'invalid_item' end
        if action == 'revive' and not rec.injured then return false, 'not_injured' end
        if not LXRCore.Inventory.HasItem(src, def.name, 1) then return false, 'no_item' end
        if not Player.Functions.RemoveItem(def.name, 1, nil, 'horse ' .. action) then return false, 'no_item' end
        xp = H.ApplyItem(rec, def, action == 'feed' and 'feed' or (action == 'revive' and 'revive' or 'feed'))
        TriggerClientEvent('lxr-horses:client:anim', src, action, def.name)
    elseif action == 'brush' then
        if not LXRCore.Inventory.HasItem(src, Config.Interactions.brushItem, 1) then return false, 'no_item' end
        xp = H.ApplyItem(rec, LXRShared.Items[Config.Interactions.brushItem], 'brush')
        TriggerClientEvent('lxr-horses:client:anim', src, 'brush')
    elseif action == 'pat' then
        rec.cores.mood = H.Clamp((rec.cores.mood or 0) + 3, 0, 100)
        xp = Config.Care.bond.xp.pat
        rec.xp = (rec.xp or 0) + xp
        TriggerClientEvent('lxr-horses:client:anim', src, 'pat')
    elseif action == 'hoof' then
        if not LXRCore.Inventory.HasItem(src, Config.Interactions.hoofPickItem, 1) then return false, 'no_item' end
        rec.cores.health = H.Clamp((rec.cores.health or 0) + 5, 0, 100)
        xp = 2
        rec.xp = (rec.xp or 0) + xp
        TriggerClientEvent('lxr-horses:client:anim', src, 'hoof')
    elseif action == 'shoes' then
        local job = Player.PlayerData.job.name
        if ownerSrc ~= src and job ~= Config.Care.shoes.farrierJob then return false, 'not_owner' end
        if not Player.Functions.RemoveItem(Config.Care.shoes.item, 1, nil, 'horseshoes') then return false, 'no_item' end
        rec.shoesHours = 0
        TriggerClientEvent('lxr-horses:client:anim', src, 'shoes')
    else
        return false, 'invalid'
    end
    if ownerSrc ~= src then
        -- strangers earn no bond for the owner's horse beyond the item's own effect
        rec.xp = rec.xp - xp
        xp = 0
    end
    local before = H.BondLevel(rec.xp - xp)
    local after = H.BondLevel(rec.xp)
    if after > before then
        H.EvolvePersonality(rec)
        LXRCore.Notify(ownerSrc, Lang:t('info.bond_up', { name = rec.name, level = after }), 'success')
        LXRCore.Emit('lxr:horse:bond', {}, ownerSrc, rec.id, after)
    end
    save(rec)
    publishState(ownerSrc)
    LXRCore.Emit('lxr:horse:interact', {}, src, rec.id, action, itemName)
    return true, { cores = rec.cores, xp = xp, bond = after }
end)

-- saddlebags through lxr-inventory (server-side stash with owner rule)
RegisterNetEvent('lxr-horses:server:saddlebags', function()
    local src = source
    if limited(src) or not Config.Saddlebags.enabled then return end
    local Player = player(src)
    if not Player then return end
    local rec, ent, ownerSrc = nearOwnHorse(src, true)
    if not rec then return notify(src, 'error.' .. tostring(ent)) end
    if ownerSrc ~= src then
        local job = Player.PlayerData.job
        local allowed = false
        for _, j in ipairs(Config.Saddlebags.sharedWithJobs) do if j == job.name then allowed = true end end
        if not allowed and Config.Saddlebags.lawCanSearch and job.type == 'leo' and job.onduty then
            local owner = player(ownerSrc)
            local md = owner and owner.PlayerData.metadata or {}
            allowed = md.ishandcuffed or md.isdead
        end
        if not allowed then return notify(src, 'error.not_owner') end
    end
    local slots, weight = H.SaddlebagCapacity(rec)
    if GetResourceState('lxr-inventory') ~= 'started' then return notify(src, 'error.no_inventory') end
    exports['lxr-inventory']:OpenInventory(src, 'stash', 'horse_' .. rec.id, { label = Lang:t('ui.saddlebags', { name = rec.name }), slots = slots, maxweight = weight, blacklist = Config.Saddlebags.blacklist })
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🏠 STABLE
-- ═══════════════════════════════════════════════════════════════════════════════
local function stablePayload(src, stable, Player)
    local c = Player.PlayerData.citizenid
    local owned = {}
    for _, r in pairs(loadOwned(c)) do if not r.dead or (r.insuredUntil or 0) > os.time() then owned[#owned + 1] = view(r) end end
    table.sort(owned, function(a, b) if a.favorite ~= b.favorite then return a.favorite end return a.id < b.id end)
    local n, limit = countOwned(c, Player.PlayerData.job.name)
    local pending = tamed[src] and { model = tamed[src].model, label = (H.Catalog(tamed[src].model) or {}).label, fee = math.floor((H.Catalog(tamed[src].model) or { price = 0 }).price * Config.Wild.claim.feePct) / 100, sell = math.floor((H.Catalog(tamed[src].model) or { price = 0 }).price * Config.Wild.claim.sellInsteadPct) / 100 } or nil
    local breeding = LXRCore.DB.Query('SELECT * FROM lxr_horse_breeding WHERE citizenid = ? AND done = 0', { c }) or {}
    return {
        stable = { id = stable.id, label = stable.label, town = stable.town, tackTier = stable.tackTier },
        owned = owned, count = n, limit = limit,
        stock = stockFor(stable, Player),
        tack = Config.StableUI.tackShop and tackShopFor(stable, Player) or {},
        ownedTack = ownedTack(c),
        market = Config.Market.enabled and marketListings() or {},
        cash = Player.Functions.GetMoney('cash'),
        pendingWild = pending,
        breeding = breeding,
        options = { genderChoice = Config.StableUI.genderChoice, scaleRange = Config.StableUI.previewScaleRange, insurance = Config.Ownership.insurance, renamePrice = Config.Ownership.renamePrice, vetPrice = Config.Care.revive.vetPrice, market = Config.Market, breeding = Config.Breeding.enabled and Config.Breeding or nil, slots = LXRHorses.TackSlots },
        locale = Lang.bundle(),
    }
end

LXR.RPC.Register('lxr-horses:stable:open', function(src, stableId)
    if limited(src) then return false, 'rate' end
    local Player = player(src)
    local stable, err = atStable(src, stableId)
    if not Player or not stable then return false, err end
    return true, stablePayload(src, stable, Player)
end)

local function validName(name)
    if type(name) ~= 'string' then return false end
    name = name:gsub('^%s+', ''):gsub('%s+$', '')
    if #name < Config.Ownership.nameMinLen or #name > Config.Ownership.nameMaxLen then return false end
    local lower = name:lower()
    for _, bad in ipairs(Config.Ownership.nameBlacklist) do if lower:find(bad, 1, true) then return false, 'blacklist' end end
    if name:find('[<>~]') then return false end
    return name
end

LXR.RPC.Register('lxr-horses:stable:buy', function(src, stableId, model, opts)
    if limited(src) then return false, 'rate' end
    local Player = player(src)
    local stable, err = atStable(src, stableId)
    if not Player or not stable then return false, err end
    opts = type(opts) == 'table' and opts or {}
    local cat = H.Catalog(model)
    if not cat then return false, 'invalid' end
    local inStock = false
    for _, h in ipairs(stockFor(stable, Player)) do if h.model == model then inStock = true end end
    if not inStock then LXRCore.Log.exploit(src, 'buy of a horse this stable does not stock', { model = model, stable = stableId }) return false, 'invalid' end
    local c = Player.PlayerData.citizenid
    local n, limit = countOwned(c, Player.PlayerData.job.name)
    if n >= limit then return false, 'limit' end
    local name, why = validName(opts.name or cat.coat)
    if not name then if why == 'blacklist' then LXRCore.Log.exploit(src, 'blacklisted horse name', { name = tostring(opts.name) }) end return false, 'bad_name' end
    local price = H.BuyPrice(model, stable)
    if not Player.Functions.RemoveMoney('cash', price, 'stable purchase ' .. model) then return false, 'no_money' end
    local gender = Config.StableUI.genderChoice and ({ male = 'male', female = 'female', gelding = 'gelding' })[opts.gender] or 'gelding'
    local scale = tonumber(opts.scale) or 1.0
    scale = H.Clamp(scale, Config.StableUI.previewScaleRange[1], Config.StableUI.previewScaleRange[2])
    local rec = H.NewRecord(model, { name = name, gender = gender, scale = scale })
    rec.citizenid, rec.stable, rec.pricePaid = c, stable.id, price
    insert(rec)
    if Config.StableUI.giveDeedItem then Player.Functions.AddItem('horse_deed', 1, nil, { horseId = rec.id, name = name, model = model }, 'stable purchase') end
    log('info', 'horse bought', { source = src, id = rec.id, model = model, price = price })
    LXRCore.Emit('lxr:horse:bought', {}, src, rec.id, model, price)
    return true, stablePayload(src, stable, Player)
end)

LXR.RPC.Register('lxr-horses:stable:sell', function(src, stableId, horseId)
    if limited(src) then return false, 'rate' end
    local Player = player(src)
    local stable, err = atStable(src, stableId)
    if not Player or not stable then return false, err end
    local rec, e = horseOf(src, horseId)
    if not rec then return false, e end
    if rec.listing then return false, 'listed' end
    if active[src] and active[src].id == rec.id then store(src, 'sold') end
    local value = H.SellValue(rec)
    LXRCore.DB.Update('DELETE FROM lxr_horses WHERE id = ? AND citizenid = ?', { rec.id, rec.citizenid })
    LXRCore.DB.Update('UPDATE lxr_horse_tack SET horse_id = NULL WHERE horse_id = ?', { rec.id })
    cache[rec.citizenid][rec.id] = nil
    if GetResourceState('lxr-inventory') == 'started' then pcall(function() exports['lxr-inventory']:ClearStash('horse_' .. rec.id) end) end
    Player.Functions.AddMoney('cash', value, 'stable sale ' .. rec.model)
    log('info', 'horse sold', { source = src, id = rec.id, value = value })
    LXRCore.Emit('lxr:horse:sold', {}, src, rec.id, value)
    return true, stablePayload(src, stable, Player)
end)

LXR.RPC.Register('lxr-horses:stable:action', function(src, stableId, action, horseId, arg)
    if limited(src) then return false, 'rate' end
    local Player = player(src)
    local stable, err = atStable(src, stableId)
    if not Player or not stable then return false, err end
    local rec, e = horseOf(src, horseId)
    if not rec then return false, e end
    if action == 'rename' then
        local name, why = validName(arg)
        if not name then if why == 'blacklist' then LXRCore.Log.exploit(src, 'blacklisted horse name', { name = tostring(arg) }) end return false, 'bad_name' end
        if Config.Ownership.renamePrice > 0 and not Player.Functions.RemoveMoney('cash', Config.Ownership.renamePrice, 'horse rename') then return false, 'no_money' end
        rec.name = name
    elseif action == 'favorite' then
        if not rec.favorite then
            local n = 0
            for _, r in pairs(loadOwned(rec.citizenid)) do if r.favorite then n = n + 1 end end
            if n >= Config.Ownership.maxFavorites then return false, 'favorites' end
        end
        rec.favorite = not rec.favorite
    elseif action == 'insure' then
        if not Config.Ownership.insurance.enabled then return false, 'invalid' end
        local price = H.InsurancePrice(rec)
        if not Player.Functions.RemoveMoney('cash', price, 'horse insurance') then return false, 'no_money' end
        rec.insuredUntil = math.max(os.time(), rec.insuredUntil or 0) + Config.Ownership.insurance.durationDays * 86400
    elseif action == 'vet' then
        if not rec.injured and not rec.dead then return false, 'not_injured' end
        local price = rec.dead and Config.Ownership.insurance.revivePrice or Config.Care.revive.vetPrice
        if rec.dead and (rec.insuredUntil or 0) < os.time() then return false, 'uninsured' end
        if price > 0 and not Player.Functions.RemoveMoney('cash', price, 'horse vet') then return false, 'no_money' end
        rec.injured, rec.dead = false, false
        rec.cores.health = math.max(rec.cores.health or 0, 70)
    elseif action == 'select' then
        if rec.dead or rec.injured then return false, 'injured' end
        if rec.listing then return false, 'listed' end
        for _, r in pairs(loadOwned(rec.citizenid)) do if r.active and r.id ~= rec.id then r.active = false save(r) end end
        if active[src] and active[src].id ~= rec.id then store(src, 'switch') end
        rec.active = true
        save(rec)
        TriggerClientEvent('lxr-horses:client:spawnAt', src, view(rec), stable.spawn)
        active[src] = { id = rec.id, since = GetGameTimer(), lastTick = GetGameTimer() }
        return true, stablePayload(src, stable, Player)
    elseif action == 'store' then
        if active[src] and active[src].id == rec.id then store(src, 'stable') end
        rec.active = false
    elseif action == 'equip' then
        -- arg = { piece = id | false, slot = name }
        local a = type(arg) == 'table' and arg or {}
        local slot = tostring(a.slot or '')
        if not LXRHorses.TackSlots[slot] then return false, 'invalid' end
        if a.piece == false or a.piece == nil then
            rec.tack[slot] = nil
            LXRCore.DB.Update('UPDATE lxr_horse_tack SET horse_id = NULL WHERE horse_id = ? AND piece LIKE ?', { rec.id, slot .. '_%' })
        else
            local piece = LXRHorses.TackById[tostring(a.piece)]
            if not piece or piece.slot ~= slot then return false, 'invalid' end
            local row = LXRCore.DB.Single('SELECT id, horse_id FROM lxr_horse_tack WHERE citizenid = ? AND piece = ? AND (horse_id IS NULL OR horse_id = ?) LIMIT 1', { rec.citizenid, piece.id, rec.id })
            if not row then return false, 'not_owned_tack' end
            LXRCore.DB.Update('UPDATE lxr_horse_tack SET horse_id = NULL WHERE horse_id = ? AND piece LIKE ?', { rec.id, slot .. '_%' })
            LXRCore.DB.Update('UPDATE lxr_horse_tack SET horse_id = ? WHERE id = ?', { rec.id, row.id })
            rec.tack[slot] = piece.id
        end
        if active[src] and active[src].id == rec.id then publishState(src) TriggerClientEvent('lxr-horses:client:tack', src, rec.tack) end
    elseif action == 'list' then
        if not Config.Market.enabled then return false, 'invalid' end
        local price = tonumber(arg)
        if not price or price < Config.Market.minPrice or price > Config.Market.maxPrice then return false, 'bad_price' end
        local n = 0
        for _, r in pairs(loadOwned(rec.citizenid)) do if r.listing then n = n + 1 end end
        if n >= Config.Market.maxListings then return false, 'listings' end
        if active[src] and active[src].id == rec.id then store(src, 'listed') end
        rec.active = false
        rec.listing = { price = math.floor(price * 100) / 100, seller = Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname, sellerCid = rec.citizenid, stable = stable.id, expires = os.time() + Config.Market.listingDays * 86400 }
    elseif action == 'unlist' then
        rec.listing = nil
    else
        return false, 'invalid'
    end
    save(rec)
    return true, stablePayload(src, stable, Player)
end)

LXR.RPC.Register('lxr-horses:stable:tack', function(src, stableId, action, pieceId)
    if limited(src) then return false, 'rate' end
    local Player = player(src)
    local stable, err = atStable(src, stableId)
    if not Player or not stable then return false, err end
    local piece = LXRHorses.TackById[tostring(pieceId)]
    if not piece then return false, 'invalid' end
    local c = Player.PlayerData.citizenid
    if action == 'buy' then
        local ok = false
        for _, p in ipairs(tackShopFor(stable, Player)) do if p.id == piece.id then ok = true end end
        if not ok then return false, 'invalid' end
        if not Player.Functions.RemoveMoney('cash', piece.price, 'tack ' .. piece.id) then return false, 'no_money' end
        LXRCore.DB.Insert('INSERT INTO lxr_horse_tack (citizenid, piece) VALUES (?, ?)', { c, piece.id })
    elseif action == 'sell' then
        local row = LXRCore.DB.Single('SELECT id FROM lxr_horse_tack WHERE citizenid = ? AND piece = ? AND horse_id IS NULL LIMIT 1', { c, piece.id })
        if not row then return false, 'not_owned_tack' end
        LXRCore.DB.Update('DELETE FROM lxr_horse_tack WHERE id = ?', { row.id })
        Player.Functions.AddMoney('cash', math.floor(piece.price * Config.StableUI.sellTackMult * 100) / 100, 'tack sale')
    else
        return false, 'invalid'
    end
    return true, stablePayload(src, stable, Player)
end)

LXR.RPC.Register('lxr-horses:market:buy', function(src, stableId, horseId)
    if limited(src) or not Config.Market.enabled then return false, 'invalid' end
    local Player = player(src)
    local stable, err = atStable(src, stableId)
    if not Player or not stable then return false, err end
    local row = LXRCore.DB.Single('SELECT * FROM lxr_horses WHERE id = ? AND listing IS NOT NULL', { tonumber(horseId) or -1 })
    if not row then return false, 'invalid' end
    local rec = rowToRecord(row)
    if rec.citizenid == Player.PlayerData.citizenid then return false, 'own_listing' end
    if (rec.listing.expires or 0) < os.time() then return false, 'expired' end
    local n, limit = countOwned(Player.PlayerData.citizenid, Player.PlayerData.job.name)
    if n >= limit then return false, 'limit' end
    local price = rec.listing.price
    if not Player.Functions.RemoveMoney('cash', price, 'market horse ' .. rec.id) then return false, 'no_money' end
    local tax = math.floor(price * Config.StableUI.marketTax) / 100
    local sellerCid = rec.listing.sellerCid
    local sellerRec = LXRCore.Functions.GetPlayerByCitizenId(sellerCid)
    if sellerRec then
        sellerRec.Functions.AddMoney('bank', price - tax, 'market horse sale ' .. rec.id)
        LXRCore.Notify(sellerRec.PlayerData.source, Lang:t('info.market_sold', { name = rec.name, amount = price - tax }), 'success')
    else
        local off = LXRCore.Player.GetOfflinePlayer(sellerCid)
        if off then off.Functions.AddMoney('bank', price - tax, 'market horse sale ' .. rec.id) off.Functions.Save() end
    end
    if cache[sellerCid] then cache[sellerCid][rec.id] = nil end
    rec.listing = nil
    rec.citizenid = Player.PlayerData.citizenid
    rec.favorite, rec.active = false, false
    rec.stable = stable.id
    LXRCore.DB.Update('UPDATE lxr_horse_tack SET citizenid = ? WHERE horse_id = ?', { rec.citizenid, rec.id })
    save(rec)
    if cache[rec.citizenid] then cache[rec.citizenid][rec.id] = rec end
    log('info', 'market purchase', { source = src, id = rec.id, price = price, from = sellerCid })
    LXRCore.Emit('lxr:horse:market', {}, src, rec.id, price, sellerCid)
    return true, stablePayload(src, stable, Player)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🤝 TRANSFER
-- ═══════════════════════════════════════════════════════════════════════════════
LXR.RPC.Register('lxr-horses:transfer', function(src, targetSrc)
    if limited(src) or not Config.Ownership.transferEnabled then return false, 'invalid' end
    local a = active[src]
    if not a then return false, 'no_horse' end
    targetSrc = tonumber(targetSrc)
    local Target = player(targetSrc or -1)
    if not Target or targetSrc == src then return false, 'invalid' end
    if distance(src, GetEntityCoords(GetPlayerPed(targetSrc))) > Config.Ownership.transferDistance then return false, 'too_far' end
    local rec = horseOf(src, a.id)
    if not rec or rec.listing then return false, 'invalid' end
    local n, limit = countOwned(Target.PlayerData.citizenid, Target.PlayerData.job.name)
    if n >= limit then return false, 'target_limit' end
    pendingTransfers[targetSrc] = { from = src, id = rec.id, expires = GetGameTimer() + 30000 }
    TriggerClientEvent('lxr-horses:client:transferOffer', targetSrc, src, view(rec))
    return true
end)

RegisterNetEvent('lxr-horses:server:transferAnswer', function(accept)
    local src = source
    local offer = pendingTransfers[src]
    pendingTransfers[src] = nil
    if not offer or offer.expires < GetGameTimer() then return end
    local from = offer.from
    local Giver, Taker = player(from), player(src)
    if not accept or not Giver or not Taker then if Giver then notify(from, 'info.transfer_declined', 'error') end return end
    local rec = horseOf(from, offer.id)
    if not rec then return end
    if Config.Ownership.transferFee > 0 and not Giver.Functions.RemoveMoney('cash', Config.Ownership.transferFee, 'horse transfer') then return notify(from, 'error.no_money') end
    if active[from] and active[from].id == rec.id then store(from, 'transfer') end
    cache[rec.citizenid][rec.id] = nil
    rec.citizenid = Taker.PlayerData.citizenid
    rec.favorite, rec.active = false, false
    LXRCore.DB.Update('UPDATE lxr_horse_tack SET citizenid = ? WHERE horse_id = ?', { rec.citizenid, rec.id })
    save(rec)
    if cache[rec.citizenid] then cache[rec.citizenid][rec.id] = rec end
    notify(from, 'info.transfer_done', 'success', { name = rec.name })
    notify(src, 'info.transfer_received', 'success', { name = rec.name })
    log('info', 'horse transferred', { from = from, to = src, id = rec.id })
    LXRCore.Emit('lxr:horse:transferred', {}, from, src, rec.id)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🐎 WILD HERDS
-- ═══════════════════════════════════════════════════════════════════════════════
local function herdById(id) for _, h in ipairs(Config.Wild.herds) do if h.id == id then return h end end end

local function pickWildModel(herd)
    if herd.models then return herd.models[math.random(#herd.models)] end
    local pool = {}
    for _, key in ipairs(herd.breeds or {}) do
        for _, h in ipairs(LXRShared.HorsesOfBreed(key)) do
            local rare = (LXRShared.Rarities[h.rarity] or {}).tier or 1
            if rare <= 2 or math.random(100) <= (herd.chanceRare or 5) then pool[#pool + 1] = h.model end
        end
    end
    return pool[math.random(#pool)]
end

LXR.RPC.Register('lxr-horses:wild:request', function(src, herdId)
    if limited(src) or not Config.Wild.enabled then return false end
    local herd = herdById(herdId)
    if not herd then return false end
    if distance(src, herd.coords) > herd.radius + 50.0 then return false end
    local state = wild[herdId] or { netIds = {} }
    wild[herdId] = state
    if next(state.netIds) then return false end -- already spawned (someone hosts it)
    local cooldown = (herd.cooldownMin or Config.Wild.respawnMin) * 60000
    if state.emptiedAt and GetGameTimer() - state.emptiedAt < cooldown then return false end
    if state.host and LXRCore.Players[state.host] and GetGameTimer() - (state.hostAt or 0) < 60000 then return false end
    state.host, state.hostAt = src, GetGameTimer()
    local n = math.random(herd.size[1], herd.size[2])
    local models = {}
    for i = 1, n do models[i] = pickWildModel(herd) end
    return true, models
end)

RegisterNetEvent('lxr-horses:server:wildSpawned', function(herdId, list)
    local src = source
    local state = wild[herdId]
    if not state or state.host ~= src or type(list) ~= 'table' then return end
    for _, e in ipairs(list) do
        local ent = NetworkGetEntityFromNetworkId(tonumber(e.netId) or 0)
        if ent ~= 0 and LXRShared.Horses[tostring(e.model)] and GetEntityModel(ent) == joaat(e.model) then
            state.netIds[tonumber(e.netId)] = e.model
        end
    end
end)

RegisterNetEvent('lxr-horses:server:wildTamed', function(netId)
    local src = source
    if limited(src) then return end
    netId = tonumber(netId)
    local herdId, model
    for id, st in pairs(wild) do if st.netIds[netId] then herdId, model = id, st.netIds[netId] end end
    if not model then return LXRCore.Log.exploit(src, 'tamed a horse the server never spawned', { netId = tostring(netId) }) end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent == 0 or distance(src, GetEntityCoords(ent)) > 5.0 then return end
    local Player = player(src)
    if not Player then return end
    local cat = H.Catalog(model)
    local need = Config.Wild.taming.minSkillLevelForTier[cat.tier]
    if need then
        local lvl = Player.Functions.GetLevel and Player.Functions.GetLevel(Config.Wild.taming.skill) or 0
        if lvl < need then return notify(src, 'error.skill_low', 'error', { level = need }) end
    end
    wild[herdId].netIds[netId] = nil
    if not next(wild[herdId].netIds) then wild[herdId].emptiedAt = GetGameTimer() end
    tamed[src] = { model = model, netId = netId, at = os.time() }
    if Player.Functions.AddXp then Player.Functions.AddXp(Config.Wild.taming.skill, Config.Wild.taming.xpOnTame) end
    notify(src, 'info.tamed', 'success', { label = cat.label })
    LXRCore.Emit('lxr:horse:tamed', {}, src, model)
end)

LXR.RPC.Register('lxr-horses:wild:claim', function(src, stableId, sell)
    if limited(src) then return false, 'rate' end
    local Player = player(src)
    local stable, err = atStable(src, stableId)
    if not Player or not stable then return false, err end
    local t = tamed[src]
    if not t then return false, 'no_wild' end
    local ent = NetworkGetEntityFromNetworkId(t.netId)
    if ent == 0 or distance(src, GetEntityCoords(ent)) > 15.0 then return false, 'bring_horse' end
    local cat = H.Catalog(t.model)
    local c = Player.PlayerData.citizenid
    if sell then
        local value = math.floor(cat.price * Config.Wild.claim.sellInsteadPct) / 100
        Player.Functions.AddMoney('cash', value, 'wild horse sale')
        tamed[src] = nil
        TriggerClientEvent('lxr-horses:client:releaseWild', src, t.netId)
        return true, stablePayload(src, stable, Player)
    end
    local today = os.date('%Y%m%d')
    local cl = claimLog[c] or { day = today, today = 0, lastAt = 0 }
    if cl.day ~= today then cl = { day = today, today = 0, lastAt = 0 } end
    if os.time() - cl.lastAt < Config.Wild.claim.cooldownMin * 60 then return false, 'claim_cooldown' end
    if cl.today >= Config.Wild.claim.maxPerDay then return false, 'claim_limit' end
    local n, limit = countOwned(c, Player.PlayerData.job.name)
    if n >= limit then return false, 'limit' end
    local fee = math.floor(cat.price * Config.Wild.claim.feePct) / 100
    if fee > 0 and not Player.Functions.RemoveMoney('cash', fee, 'wild horse registration') then return false, 'no_money' end
    local rec = H.NewRecord(t.model, { name = cat.coat, gender = math.random(2) == 1 and 'male' or 'female' })
    rec.citizenid, rec.stable, rec.wildCaught = c, stable.id, true
    rec.xp = Config.Care.bond.xp.calm
    insert(rec)
    cl.today, cl.lastAt = cl.today + 1, os.time()
    claimLog[c] = cl
    tamed[src] = nil
    TriggerClientEvent('lxr-horses:client:releaseWild', src, t.netId)
    log('info', 'wild horse claimed', { source = src, id = rec.id, model = t.model })
    LXRCore.Emit('lxr:horse:claimed', {}, src, rec.id, t.model)
    return true, stablePayload(src, stable, Player)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🏁 TRAINING
-- ═══════════════════════════════════════════════════════════════════════════════
LXR.RPC.Register('lxr-horses:training:start', function(src, courseId)
    if limited(src) or not Config.Training.enabled then return false, 'invalid' end
    local course
    for _, c in ipairs(Config.Training.courses) do if c.id == courseId then course = c end end
    if not course then return false, 'invalid' end
    if distance(src, course.start) > 10.0 then return false, 'too_far' end
    local a = active[src]
    if not a then return false, 'no_horse' end
    local rec = horseOf(src, a.id)
    if not rec then return false, 'no_horse' end
    if (rec.trainedAt or 0) + Config.Training.cooldownMin * 60 > os.time() then return false, 'cooldown' end
    local Player = player(src)
    if Config.Training.fee > 0 and not Player.Functions.RemoveMoney('cash', Config.Training.fee, 'horse training') then return false, 'no_money' end
    a.training = { course = courseId, startedAt = GetGameTimer() }
    return true, course
end)

RegisterNetEvent('lxr-horses:server:trainingDone', function(courseId, success)
    local src = source
    local a = active[src]
    if not a or not a.training or a.training.course ~= courseId then return end
    local course
    for _, c in ipairs(Config.Training.courses) do if c.id == courseId then course = c end end
    local elapsed = (GetGameTimer() - a.training.startedAt) / 1000
    a.training = nil
    local rec = horseOf(src, a.id)
    if not rec or not course then return end
    rec.trainedAt = os.time()
    if success and elapsed <= course.timeLimitSec + 2 and elapsed >= #course.checkpoints * 1.5 then
        rec.xp = (rec.xp or 0) + course.xp
        local stat = course.statTraining
        if stat and rec.stats[stat] ~= nil then rec.stats[stat] = math.min(Config.Training.maxStatBonus, rec.stats[stat] + Config.Training.bonusPerSuccess) end
        notify(src, 'info.training_done', 'success', { xp = course.xp, stat = stat or '' })
        LXRCore.Emit('lxr:horse:trained', {}, src, rec.id, courseId)
    else
        if success then LXRCore.Log.exploit(src, 'implausible training time', { course = courseId, elapsed = elapsed }) end
        notify(src, 'info.training_failed', 'error')
    end
    save(rec)
    publishState(src)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🐣 BREEDING
-- ═══════════════════════════════════════════════════════════════════════════════
LXR.RPC.Register('lxr-horses:breed', function(src, stableId, sireId, damId)
    if limited(src) or not Config.Breeding.enabled then return false, 'invalid' end
    local Player = player(src)
    local stable, err = atStable(src, stableId)
    if not Player or not stable then return false, err end
    local sire, dam = horseOf(src, sireId), horseOf(src, damId)
    if not sire or not dam then return false, 'not_owner' end
    if sire.gender ~= 'male' or dam.gender ~= 'female' then return false, 'bad_pair' end
    if H.BondLevel(sire.xp) < Config.Breeding.minBond or H.BondLevel(dam.xp) < Config.Breeding.minBond then return false, 'bond_low' end
    if (dam.bredAt or 0) + Config.Breeding.cooldownHours * 3600 > os.time() then return false, 'mare_cooldown' end
    if not Player.Functions.RemoveMoney('cash', Config.Breeding.fee, 'horse breeding') then return false, 'no_money' end
    dam.bredAt = os.time()
    save(dam)
    LXRCore.DB.Insert('INSERT INTO lxr_horse_breeding (citizenid, sire_id, dam_id, stable, due_at) VALUES (?, ?, ?, ?, FROM_UNIXTIME(?))', { Player.PlayerData.citizenid, sire.id, dam.id, stable.id, os.time() + Config.Breeding.gestationHours * 3600 })
    LXRCore.Emit('lxr:horse:bred', {}, src, sire.id, dam.id)
    return true, stablePayload(src, stable, Player)
end)

LXR.RPC.Register('lxr-horses:breed:collect', function(src, stableId)
    if limited(src) then return false, 'rate' end
    local Player = player(src)
    local stable, err = atStable(src, stableId)
    if not Player or not stable then return false, err end
    local c = Player.PlayerData.citizenid
    local rows = LXRCore.DB.Query('SELECT * FROM lxr_horse_breeding WHERE citizenid = ? AND done = 0 AND due_at <= NOW()', { c }) or {}
    if #rows == 0 then return false, 'nothing_due' end
    local n, limit = countOwned(c, Player.PlayerData.job.name)
    local born = 0
    for _, row in ipairs(rows) do
        if n + born >= limit then break end
        local sire, dam = loadOwned(c)[row.sire_id], loadOwned(c)[row.dam_id]
        if sire and dam then
            local foal = H.Foal(sire, dam)
            if foal then
                foal.citizenid, foal.stable = c, stable.id
                insert(foal)
                born = born + 1
            end
        end
        LXRCore.DB.Update('UPDATE lxr_horse_breeding SET done = 1 WHERE id = ?', { row.id })
    end
    if born == 0 then return false, 'limit' end
    notify(src, 'info.foal_born', 'success', { count = born })
    return true, stablePayload(src, stable, Player)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- ⏱️ CORE TICK
-- ═══════════════════════════════════════════════════════════════════════════════
CreateThread(function()
    while true do
        Wait(Config.Care.tickMin * 60000)
        for src, a in pairs(active) do
            local rec = horseOf(src, a.id)
            if rec then
                local ridden = a.ridingAt and GetGameTimer() - a.ridingAt < Config.Care.tickMin * 60000
                local _, events = H.Tick(rec, { inStable = false, ridden = ridden })
                if ridden then
                    a.rideTicks = (a.rideTicks or 0) + 1
                    rec.xp = (rec.xp or 0) + Config.Care.bond.xp.ride5min
                end
                for _, e in ipairs(events) do
                    if e:sub(1, 4) == 'low:' then notify(src, 'info.core_low', 'error', { name = rec.name, core = Lang:t('core.' .. e:sub(5)) })
                    elseif e == 'injured' then notify(src, 'info.neglect_injured', 'error', { name = rec.name }) TriggerClientEvent('lxr-horses:client:injured', src)
                    elseif e == 'old_age' then notify(src, 'info.old_age', 'error', { name = rec.name }) store(src, 'old_age') end
                end
                save(rec)
                publishState(src)
            end
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🧹 LIFECYCLE
-- ═══════════════════════════════════════════════════════════════════════════════
AddEventHandler('lxr:player:unloaded', function(src) if active[src] then store(src, 'logout') end tamed[src] = nil end)
AddEventHandler('playerDropped', function()
    local src = source
    if active[src] then store(src, 'dropped') end
    buckets[src], cooldowns[src], tamed[src], pendingTransfers[src] = nil, nil, nil, nil
    for id, st in pairs(wild) do if st.host == src then st.host = nil end end
end)
AddEventHandler('lxr:character:deleted', function(citizenid) cache[citizenid] = nil end)

-- exports for other resources
exports('GetActiveHorse', function(src) local a = active[src] if not a then return nil end local rec = horseOf(src, a.id) return rec and view(rec) or nil, a.netId end)
exports('GetOwnedHorses', function(citizenid) local out = {} for _, r in pairs(loadOwned(citizenid)) do out[#out + 1] = view(r) end return out end)
exports('IsHorseOwnedBy', function(netId, citizenid) local src = byNet[tonumber(netId) or 0] if not src then return false end local a = active[src] local rec = a and horseOf(src, a.id) return rec ~= nil and rec.citizenid == citizenid end)
exports('AddBond', function(src, amount, reason) local a = active[src] if not a then return false end local rec = horseOf(src, a.id) if not rec then return false end rec.xp = math.max(0, (rec.xp or 0) + (tonumber(amount) or 0)) save(rec) publishState(src) return true end)

if Config.Debug.adminCommands then
    LXR.Commands.Register({ name = 'givehorse', help = Lang:t('command.givehorse'), permission = 'admin',
        args = { { name = 'id', help = 'server id' }, { name = 'model', help = 'catalog model' } },
        handler = function(src, args)
            local target = tonumber(args[1])
            local Target = player(target or -1)
            local cat = H.Catalog(tostring(args[2]))
            if not Target or not cat then return notify(src, 'error.invalid') end
            local rec = H.NewRecord(cat.model, { name = cat.coat, gender = 'gelding' })
            rec.citizenid = Target.PlayerData.citizenid
            insert(rec)
            notify(src, 'info.given', 'success', { label = cat.label })
        end })
end

CreateThread(function()
    Wait(1500)
    if not Config.Debug.printBanner then return end
    local n = 0 for _ in pairs(LXRShared.Horses) do n = n + 1 end
    print('^5═══════════════════════════════════════════════════════════════════════════════^7')
    print(('^5🐺 LXR-HORSES^7 ^3v%s^7 — %d coats · %d tack pieces · %d stables · wild herds %s · breeding %s'):format(
        GetResourceMetadata(RES, 'version', 0) or '?', n, LXRShared.TableSize(LXRHorses.TackById), #Config.Stables,
        Config.Wild.enabled and '^2ON^7' or '^1OFF^7', Config.Breeding.enabled and '^2ON^7' or '^1OFF^7'))
    print('^5═══════════════════════════════════════════════════════════════════════════════^7')
end)
