--[[ ═══════════════════════════════════════════════════════════════════════════
     🐺 LXR-HORSES — Offline tests for shared/logic.lua and the tack catalog
     Requires a sibling checkout of lxr-core (../lxr-core) for the runtime shim.
     Usage (from the lxr-horses folder):  lua tests/run.lua
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

local CORE = os.getenv('LXR_CORE_PATH') or '../lxr-core'
package.path = CORE .. '/?.lua;' .. package.path
local ok = pcall(function() require('tests.lib.fxshim') end)
if not ok then print('lxr-core shim not found at ' .. CORE .. ' (set LXR_CORE_PATH)') os.exit(2) end
local Shim = require('tests.lib.fxshim')

for _, f in ipairs({ 'shared/main.lua', 'shared/locale.lua', 'locales/en.lua', 'config.lua', 'shared/catalog.lua', 'shared/items.lua', 'shared/horses.lua' }) do
    Shim.load(CORE .. '/' .. f)
end
local CoreConfig = Config
Config = nil
Shim.load('config.lua')
local HorseConfig = Config
Shim.load('shared/tack.lua')
Shim.load('shared/logic.lua')
local H = LXRHorses.Logic

local passed, failed = 0, 0
local function test(name, fn)
    local okT, err = xpcall(fn, debug.traceback)
    if okT then passed = passed + 1 print('  ^ ok   ' .. name) else failed = failed + 1 print('  x FAIL ' .. name .. '\n' .. err) end
end
local function eq(a, b, msg) if a ~= b then error((msg or 'eq') .. ': expected ' .. tostring(b) .. ' got ' .. tostring(a), 2) end end
local function near(a, b, eps, msg) if math.abs(a - b) > (eps or 0.01) then error((msg or 'near') .. ': ' .. a .. ' !~ ' .. b, 2) end end

test('tack catalog: 546 pieces, unique hashes, overrides applied', function()
    local n, seen = 0, {}
    for _, list in pairs(LXRHorses.Tack) do
        for _, p in ipairs(list) do
            n = n + 1
            assert(not seen[p.hash], 'duplicate hash ' .. tostring(p.hash))
            seen[p.hash] = true
            assert(LXRHorses.TackSlots[p.slot], 'slot ' .. p.slot)
        end
    end
    assert(n >= 500, 'pieces: ' .. n)
    eq(LXRHorses.TackById.saddle_1.label, 'Worn Saddle')
    eq(LXRHorses.TackById.saddle_5.tier, 4)
    eq(#LXRHorses.TackFor('saddle', 1) < #LXRHorses.TackFor('saddle', 4), true)
end)

test('new record inherits breed temperament and catalog coat name', function()
    local r = H.NewRecord('a_c_horse_arabian_white')
    eq(r.personality, 'spirited')
    eq(r.name, 'White')
    eq(r.cores.health, 100)
end)

test('bond levels, progress and whistle range', function()
    eq(H.BondLevel(0), 1)
    eq(H.BondLevel(199), 1)
    eq(H.BondLevel(200), 2)
    eq(H.BondLevel(5000), 5)
    near(H.BondProgress(300), 0.4, 0.01)
    eq(H.WhistleRange(0), 60.0)
    eq(H.WhistleRange(1250), 600.0)
end)

test('effective stats: base + training + bond + tack − penalties, clamped 1..10', function()
    local r = H.NewRecord('a_c_horse_morgan_bay')          -- base { 4, 5, 5, 5, 6, 5 }
    local s = H.EffectiveStats(r)
    near(s.speed, 4)                                         -- bond level 1 → +0.5 stamina/health/courage only
    near(s.stamina, 5.5)
    r.stats.speed = 2
    r.tack.saddle = 'saddle_5'                               -- tier 4: stamina 3, health 2, speed 1
    r.xp = 1250                                              -- bond 5 → +2.5
    s = H.EffectiveStats(r)
    near(s.speed, 7)
    near(s.stamina, 10, 0.01, 'clamped at 10')
    r.cores.thirst = 10                                      -- low thirst: stamina -3, health -1
    s = H.EffectiveStats(r)
    near(s.stamina, 5 + 3 + 2.5 - 3)
    r.xp = 0
    s = H.EffectiveStats(r)
    near(s.stamina, 5 + 3 + 0.5 - 3)
    r.shoesHours = 999
    s = H.EffectiveStats(r)
    near(s.speed, 4 + 2 + 1 - 1)
end)

test('value: sell price scales with condition; buy price with stable stock multiplier', function()
    local r = H.NewRecord('a_c_horse_arabian_white')
    local full = H.SellValue(r)
    r.cores.health = 20
    assert(H.SellValue(r) < full, 'injured horse worth less')
    r.cores.health = 100
    r.xp = 1250
    assert(H.SellValue(r) > full, 'bonded horse worth more')
    eq(H.BuyPrice('a_c_horse_morgan_bay', { stockMult = 1.25 }), 62.5)
    eq(H.InsurancePrice(H.NewRecord('a_c_horse_morgan_bay')), 5)
end)

test('tick: drains out of the stable, recovers inside, neglect injures and costs bond', function()
    local r = H.NewRecord('a_c_horse_morgan_bay')
    r.xp = 100
    H.Tick(r, { inStable = false, ridden = true })
    eq(r.cores.hunger, 77)
    eq(r.cores.thirst, 76)
    eq(r.cores.stamina, 99)
    H.Tick(r, { inStable = true, ticks = 10 })
    eq(r.cores.hunger, 100)
    r.cores.hunger, r.cores.thirst = 10, 10
    local ticksToInjury = math.ceil(HorseConfig.Care.neglect.hoursToInjury * 60 / HorseConfig.Care.tickMin)
    local _, events = H.Tick(r, { inStable = false, ticks = ticksToInjury })
    eq(r.injured, true)
    local sawInjury = false
    for _, e in ipairs(events) do if e == 'injured' then sawInjury = true end end
    eq(sawInjury, true)
    eq(r.xp, 100 - ticksToInjury)
end)

test('items: catalog horse_* effects feed, brush and revive', function()
    local r = H.NewRecord('a_c_horse_morgan_bay')
    r.cores.hunger = 40
    local xp = H.ApplyItem(r, LXRShared.Items.oats, 'feed')
    eq(r.cores.hunger, 75)
    eq(r.cores.stamina, 100)
    eq(xp, 6)
    eq(r.xp, 6 + 2, 'oats carry horse_bond = 2')
    r.cores.cleanliness = 10
    H.ApplyItem(r, LXRShared.Items.horse_brush, 'brush')
    eq(r.cores.cleanliness, 100)
    r.injured = true
    r.cores.health = 5
    H.ApplyItem(r, LXRShared.Items.horse_reviver, 'revive')
    eq(r.injured, false)
    eq(r.cores.health, 50)
    eq(H.ItemHorseEffects(LXRShared.Items.bread), nil, 'bread is not horse feed')
end)

test('personality drifts with mood; foal inherits between parents', function()
    local r = H.NewRecord('a_c_horse_mustang_wildbay')   -- nervous
    r.cores.mood = 90
    eq(H.EvolvePersonality(r), 'steady')
    r.cores.mood = 10
    eq(H.EvolvePersonality(r), 'nervous')
    local sire = H.NewRecord('a_c_horse_arabian_black', { gender = 'male' }); sire.id = 1; sire.xp = 1250
    local dam = H.NewRecord('a_c_horse_morgan_bay', { gender = 'female' }); dam.id = 2
    local seq = { 1, 1, 1 }  -- breed from sire, coat index 1, gender male
    local i = 0
    local function rand(n) i = i + 1 if n then return seq[i] or 1 end return 0.5 end
    local foal = H.Foal(sire, dam, rand)
    assert(foal, 'foal')
    eq(foal.sireId, 1)
    eq(foal.damId, 2)
    eq(LXRShared.Horses[foal.model].breed, 'arabian')
    assert(foal.stats.speed <= HorseConfig.Training.maxStatBonus and foal.stats.speed >= -2, 'stat bonus in range')
    eq(foal.ageDays, 0)
end)

print(('\n%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
