--[[ ═══════════════════════════════════════════════════════════════════════════
     🐺 LXR-HORSES — Shared: pure horse logic (no natives, fully testable)
     ═══════════════════════════════════════════════════════════════════════════
     Everything that turns a stored horse record into numbers: effective
     stats, value, bond level, core ticks, item effects, personality drift,
     foal inheritance. Server and client both use it; tests/run.lua covers it.

     Record shape (as stored in lxr_horses):
       { id, citizenid, model, name, gender, stats = { speed, acceleration,
         health, stamina, handling, courage } (trained bonus, 0..maxStatBonus),
         cores = { health, stamina, hunger, thirst, cleanliness, mood } (0..100),
         xp, personality, tack = { slot = pieceId }, ageDays, injured, dead,
         shoesHours, insuredUntil, sireId, damId, favorite, active }
     ═══════════════════════════════════════════════════════════════════════════
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

LXRHorses = LXRHorses or {}
local H = {}
LXRHorses.Logic = H

local STATS = { 'speed', 'acceleration', 'health', 'stamina', 'handling', 'courage' }
H.StatKeys = STATS
local CORES = { 'health', 'stamina', 'hunger', 'thirst', 'cleanliness', 'mood' }
H.CoreKeys = CORES

local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
H.Clamp = clamp

function H.Catalog(model)
    return LXRShared and LXRShared.Horses and LXRShared.Horses[model] or nil
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🐴 RECORDS
-- ═══════════════════════════════════════════════════════════════════════════════
function H.NewRecord(model, opts)
    opts = opts or {}
    local cat = H.Catalog(model)
    local breed = cat and LXRShared.HorseBreeds[cat.breed] or nil
    return {
        model = model, name = opts.name or (cat and cat.coat) or 'Horse',
        gender = opts.gender or 'gelding',
        stats = { speed = 0, acceleration = 0, health = 0, stamina = 0, handling = 0, courage = 0 },
        cores = { health = 100, stamina = 100, hunger = 80, thirst = 80, cleanliness = 90, mood = 70 },
        xp = opts.xp or 0,
        personality = opts.personality or (breed and breed.temperament) or 'steady',
        tack = opts.tack or {},
        ageDays = opts.ageDays or 1200,
        injured = false, dead = false, shoesHours = 0, insuredUntil = 0,
        sireId = opts.sireId, damId = opts.damId, favorite = false, active = false,
        scale = opts.scale or 1.0,
    }
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 💞 BOND
-- ═══════════════════════════════════════════════════════════════════════════════
function H.BondLevel(xp)
    local levels = Config.Care.bond.levels
    local lvl = 0
    for i, need in ipairs(levels) do if (xp or 0) >= need then lvl = i end end
    return lvl
end

function H.BondProgress(xp)
    local levels = Config.Care.bond.levels
    local lvl = H.BondLevel(xp)
    local cur = levels[lvl] or 0
    local nxt = levels[lvl + 1]
    if not nxt then return 1.0 end
    return clamp(((xp or 0) - cur) / (nxt - cur), 0, 1)
end

function H.WhistleRange(xp)
    local lvl = math.max(1, H.BondLevel(xp))
    return Config.Care.bond.whistleRangeByLevel[lvl] or 60.0
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 📊 STATS
-- ═══════════════════════════════════════════════════════════════════════════════
---Effective 1–10 stats: catalog base + training + bond + tack − core penalties − age − shoes.
function H.EffectiveStats(rec)
    local cat = H.Catalog(rec.model)
    local base = cat and cat.stats or { speed = 5, acceleration = 5, health = 5, stamina = 5, handling = 5, courage = 5 }
    local out = {}
    local bond = H.BondLevel(rec.xp)
    for _, k in ipairs(STATS) do
        local v = (base[k] or 5) + (rec.stats and rec.stats[k] or 0)
        v = v + (Config.Care.bond.statBonusPerLevel[k] or 0) * bond
        out[k] = v
    end
    -- tack
    for _, pieceId in pairs(rec.tack or {}) do
        local piece = LXRHorses.TackById and LXRHorses.TackById[pieceId]
        if piece and piece.stats then
            for k, v in pairs(piece.stats) do if out[k] then out[k] = out[k] + v end end
        end
    end
    -- low cores
    local cores = rec.cores or {}
    for core, pen in pairs(Config.Care.penalties) do
        if (cores[core] or 100) < Config.Care.lowThreshold then
            for k, v in pairs(pen) do if out[k] then out[k] = out[k] + v end end
        end
    end
    -- age
    if Config.Care.aging.enabled and (rec.ageDays or 0) > Config.Care.aging.primeUntil then
        local decline = ((rec.ageDays or 0) - Config.Care.aging.primeUntil) * Config.Care.aging.declinePerDay
        for _, k in ipairs(STATS) do out[k] = out[k] - decline end
    end
    -- shoes
    if Config.Care.shoes.enabled and (rec.shoesHours or 0) >= Config.Care.shoes.lifeHours then
        for k, v in pairs(Config.Care.shoes.penalty) do if out[k] then out[k] = out[k] + v end end
    end
    -- personality
    local p = Config.Personalities[rec.personality or 'steady']
    if p and p.effects.speedBonus then out.speed = out.speed + p.effects.speedBonus end
    for _, k in ipairs(STATS) do out[k] = clamp(out[k], 1, 10) end
    return out
end

---Saddlebag capacity from tack.
function H.SaddlebagCapacity(rec)
    local slots, weight = Config.Saddlebags.baseSlots, Config.Saddlebags.baseWeight
    for _, pieceId in pairs(rec.tack or {}) do
        local piece = LXRHorses.TackById and LXRHorses.TackById[pieceId]
        if piece and piece.stats and piece.stats.storage then slots = slots + piece.stats.storage end
    end
    if rec.bagUpgrade then weight = weight + Config.Saddlebags.upgradeWeight end
    return slots, weight
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 💰 VALUE
-- ═══════════════════════════════════════════════════════════════════════════════
---Condition multiplier 0.3–1.2 from health core, bond and age.
function H.Condition(rec)
    local cores = rec.cores or {}
    local health = (cores.health or 100) / 100
    local bond = H.BondLevel(rec.xp) / #Config.Care.bond.levels
    local age = 1.0
    if Config.Care.aging.enabled and (rec.ageDays or 0) > Config.Care.aging.primeUntil then
        age = clamp(1 - ((rec.ageDays or 0) - Config.Care.aging.primeUntil) / (Config.Care.aging.maxDays - Config.Care.aging.primeUntil), 0.3, 1)
    end
    return clamp(0.5 + 0.4 * health + 0.3 * bond, 0.3, 1.2) * age
end

---What the stable pays for the horse.
function H.SellValue(rec)
    local cat = H.Catalog(rec.model)
    local price = cat and cat.price or 0
    local mult = Config.Ownership.sellToStableMult or (cat and cat.sellMult) or 0.45
    local v = price * mult
    if Config.Ownership.sellConditionMult then v = v * H.Condition(rec) end
    return math.floor(v * 100 + 0.5) / 100
end

---Purchase price at a stable (stock multiplier + personality premium).
function H.BuyPrice(model, stable)
    local cat = H.Catalog(model)
    if not cat then return nil end
    return math.floor(cat.price * (stable and stable.stockMult or 1.0) * 100 + 0.5) / 100
end

function H.InsurancePrice(rec)
    local cat = H.Catalog(rec.model)
    return math.floor((cat and cat.price or 0) * Config.Ownership.insurance.pricePct / 100 * 100 + 0.5) / 100
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- ⏱️ CORES TICK
-- ═══════════════════════════════════════════════════════════════════════════════
---Advance cores by one tick. ctx = { inStable = bool, ridden = bool, ticks = n }
---Returns the record (mutated) and a list of events ('low:hunger', 'injured', 'bond_loss', 'aged').
function H.Tick(rec, ctx)
    ctx = ctx or {}
    local ticks = ctx.ticks or 1
    local cores = rec.cores
    local events = {}
    local cfg = Config.Care
    for _ = 1, ticks do
        if ctx.inStable then
            for k, v in pairs(cfg.recoverPerTick) do cores[k] = clamp((cores[k] or 0) + v, 0, 100) end
        else
            for k, v in pairs(cfg.drainPerTick) do cores[k] = clamp((cores[k] or 0) - v, 0, 100) end
            if ctx.ridden then
                for k, v in pairs(cfg.ridingDrain) do cores[k] = clamp((cores[k] or 0) - v, 0, 100) end
                if cfg.shoes.enabled then rec.shoesHours = (rec.shoesHours or 0) + cfg.tickMin / 60 end
            end
        end
        -- neglect
        local p = Config.Personalities[rec.personality or 'steady']
        local resistant = p and p.effects.lackOfCareResistance
        if (cores.hunger or 100) < cfg.lowThreshold and (cores.thirst or 100) < cfg.lowThreshold and not ctx.inStable and not resistant then
            rec.neglectTicks = (rec.neglectTicks or 0) + 1
            rec.xp = math.max(0, (rec.xp or 0) - cfg.neglect.bondLossPerTick)
            events[#events + 1] = 'bond_loss'
            if rec.neglectTicks * cfg.tickMin >= cfg.neglect.hoursToInjury * 60 and not rec.injured then
                rec.injured = true
                events[#events + 1] = 'injured'
            end
        else
            rec.neglectTicks = 0
        end
    end
    for _, k in ipairs({ 'hunger', 'thirst', 'cleanliness', 'mood' }) do
        if (cores[k] or 100) < cfg.lowThreshold then events[#events + 1] = 'low:' .. k end
    end
    if cfg.aging.enabled then
        rec.ageDays = (rec.ageDays or 0) + (cfg.tickMin / 1440) * cfg.aging.gameDaysPerRealDay * ticks
        if rec.ageDays >= cfg.aging.maxDays and not rec.dead then rec.dead = true events[#events + 1] = 'old_age' end
    end
    return rec, events
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🍎 ITEMS
-- ═══════════════════════════════════════════════════════════════════════════════
---Is this catalog item something a horse consumes / benefits from?
function H.ItemHorseEffects(def)
    if not def or type(def.effects) ~= 'table' then return nil end
    local fx = {}
    local any = false
    for k, v in pairs(def.effects) do
        if k:sub(1, 6) == 'horse_' then fx[k:sub(7)] = v any = true end
    end
    return any and fx or nil
end

---Apply a catalog item's horse effects. Returns bond xp earned.
function H.ApplyItem(rec, def, action)
    local fx = H.ItemHorseEffects(def)
    if not fx then return 0 end
    local cores = rec.cores
    for k, v in pairs(fx) do
        if k == 'bond' then rec.xp = (rec.xp or 0) + v
        elseif k == 'revive' then rec.injured = false rec.dead = false cores.health = math.max(cores.health or 0, 50)
        elseif k == 'clean' then cores.cleanliness = clamp((cores.cleanliness or 0) + v, 0, 100)
        elseif k == 'core_health' then cores.health = clamp((cores.health or 0) + v, 0, 100)
        elseif k == 'core_stamina' then cores.stamina = clamp((cores.stamina or 0) + v, 0, 100)
        elseif cores[k] ~= nil then cores[k] = clamp((cores[k] or 0) + v, 0, 100) end
    end
    if fx.hunger or fx.thirst then cores.mood = clamp((cores.mood or 0) + 5, 0, 100) end
    local xp = Config.Care.bond.xp[action or 'feed'] or 0
    rec.xp = (rec.xp or 0) + xp
    return xp
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🧠 PERSONALITY
-- ═══════════════════════════════════════════════════════════════════════════════
---Called when the bond level changes: drift toward improvesTo / worsensTo.
function H.EvolvePersonality(rec)
    local ev = Config.PersonalityEvolution
    if not ev.enabled then return rec.personality end
    local p = Config.Personalities[rec.personality or 'steady']
    if not p then return rec.personality end
    local mood = rec.cores and rec.cores.mood or 50
    if mood >= ev.improveIfMoodAbove then rec.personality = p.improvesTo
    elseif mood <= ev.worsenIfMoodBelow then rec.personality = p.worsensTo end
    return rec.personality
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🐣 BREEDING
-- ═══════════════════════════════════════════════════════════════════════════════
---Compute a foal record from two parents. `rand` is injectable for tests.
function H.Foal(sire, dam, rand)
    rand = rand or math.random
    local b = Config.Breeding
    local sireCat, damCat = H.Catalog(sire.model), H.Catalog(dam.model)
    if not sireCat or not damCat then return nil, 'invalid_parent' end
    local breedKey
    if b.foalTakesBreedOf == 'dam' then breedKey = damCat.breed
    elseif b.foalTakesBreedOf == 'sire' then breedKey = sireCat.breed
    else breedKey = rand(2) == 1 and sireCat.breed or damCat.breed end
    local coats = LXRShared.HorsesOfBreed(breedKey)
    local pick = coats[rand(#coats)]
    local foal = H.NewRecord(pick.model, { gender = rand(2) == 1 and 'male' or 'female', ageDays = 0, sireId = sire.id, damId = dam.id })
    local sStats, dStats = H.EffectiveStats(sire), H.EffectiveStats(dam)
    local w = b.statInheritance
    for _, k in ipairs(STATS) do
        local parentAvg = (sStats[k] + dStats[k]) / 2
        local base = pick.stats[k]
        local target = parentAvg * w.parentAvgWeight + base * w.breedBaseWeight + (rand() * 2 - 1) * w.variance
        foal.stats[k] = clamp(math.floor((target - base) * 4 + 0.5) / 4, -2, Config.Training.maxStatBonus)
    end
    foal.personality = rand(2) == 1 and sire.personality or dam.personality
    return foal
end

return H
