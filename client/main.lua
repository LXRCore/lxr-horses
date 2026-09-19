--[[ ═══════════════════════════════════════════════════════════════════════════
     🐺 LXR-HORSES — Client: the horse in the world
     ═══════════════════════════════════════════════════════════════════════════
     Spawns the owned horse the server approved, dresses it (tack hashes),
     applies stats / bond / personality, runs the prompts around it, draws
     the tag, reports riding and health, handles wild herds, training
     courses and transfers. Nothing here decides ownership or money.
     ═══════════════════════════════════════════════════════════════════════════
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

local LXRCore = exports['lxr-core']:GetCoreObject()
-- LXRCore crosses the export as a copy: its PlayerData would stay what it was at load. The core broadcasts every
-- change (money, job, metadata) — keep ours current.
RegisterNetEvent('lxr:client:data', function(d) if type(d) == 'table' then LXRCore.PlayerData = d end end)
RegisterNetEvent('lxr:client:unloaded', function() LXRCore.PlayerData = {} end)
local LXR = exports['lxr-core']:GetLXR()
local H = LXRHorses.Logic

local horse = nil        -- { ent, id, view }
local tagVisible = true
local prompts = {}
local wildLocal = {}     -- herdId → { ents }
local training = nil

local N = Citizen.InvokeNative
local function notify(key, kind, vars) LXRCore.Functions.Notify(Lang:t(key, vars), kind or 'error') end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🐴 SPAWN / DRESS
-- ═══════════════════════════════════════════════════════════════════════════════
local function findSpawnPoint()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    for i = 0, 7 do
        local ang = math.rad(heading + 180 + i * 45)
        for _, d in ipairs({ Config.Spawn.minDistance, Config.Spawn.minDistance + 6.0, Config.Spawn.maxDistance }) do
            local x, y = pos.x + math.sin(-ang) * d, pos.y + math.cos(-ang) * d
            local ok, z = GetGroundZFor_3dCoord(x, y, pos.z + 5.0, false)
            if ok and not IsPositionOccupied(x, y, z, 1.5, false, true, true, false, false, 0, false) then
                return vector3(x, y, z)
            end
        end
    end
    return pos + vector3(Config.Spawn.minDistance, 0, 0)
end

local function applyTack(ent, tack)
    for slot, def in pairs(LXRHorses.TackSlots) do
        N(0xD710A5007C2AC539, ent, def.category, 0) -- REMOVE_TAG_FROM_META_PED
    end
    for _, pieceId in pairs(tack or {}) do
        local piece = LXRHorses.TackById[pieceId]
        if piece then N(0xD3A7B003ED343FD9, ent, piece.hash, true, true, true) end -- _APPLY_SHOP_ITEM_TO_PED
    end
    N(0xAAB86462966168CE, ent, true) -- _SET_ACTIVE_META_PED_COMPONENTS_UPDATED
end

local function applyStats(ent, v)
    local s = v.stats or {}
    -- attribute 0 health, 1 stamina; ranks 1..10 → base rank
    N(0x5DA12E025D47D4E5, ent, 0, math.floor(s.health or 5))     -- SET_ATTRIBUTE_BASE_RANK
    N(0x5DA12E025D47D4E5, ent, 1, math.floor(s.stamina or 5))
    N(0x920F9488BD115EFB, ent, 0, 0)                              -- SET_ATTRIBUTE_BONUS_RANK
    N(0x920F9488BD115EFB, ent, 1, 0)
    N(0xC6258F41D86676E0, ent, 0, math.floor(v.cores.health or 100)) -- _SET_ATTRIBUTE_CORE_VALUE
    N(0xC6258F41D86676E0, ent, 1, math.floor(v.cores.stamina or 100))
    local maxHp = 100 + math.floor((s.health or 5) * 40)
    SetEntityMaxHealth(ent, maxHp)
    SetEntityHealth(ent, math.floor(maxHp * (v.cores.health or 100) / 100), 0)
    N(0xA69899995997A63B, ent, math.max(1, math.min(4, (v.bond or 1))))  -- _SET_MOUNT_BONDING_LEVEL
    N(0xDDCF6FEA5D7ACC17, ent, math.floor((s.courage or 5) / 2))          -- SET_HORSE_AVOIDANCE_LEVEL
    if v.scale and v.scale ~= 1.0 then N(0x25ACFC650B65C538, ent, v.scale + 0.0) end -- _SET_PED_SCALE
    if Config.Care.dirt.enabled then
        local dirt = (v.cores.cleanliness or 100) < Config.Care.dirt.muddyBelow and (1.0 - (v.cores.cleanliness or 0) / 100) or 0.0
        N(0xF9CFF5BB70E8A2CB, ent, dirt) -- _SET_PED_WETNESS_AMOUNT (mud look)
    end
end

local function spawnHorse(v, at)
    local model = joaat(v.model)
    if not IsModelValid(model) then return nil end
    RequestModel(model)
    local tries = 0
    while not HasModelLoaded(model) and tries < 200 do Wait(25) tries = tries + 1 end
    if not HasModelLoaded(model) then return nil end
    local pos = at and vector3(at.x, at.y, at.z) or findSpawnPoint()
    local ent = CreatePed(model, pos.x, pos.y, pos.z, GetEntityHeading(PlayerPedId()), true, true, false, false)
    SetModelAsNoLongerNeeded(model)
    if not ent or ent == 0 then return nil end
    N(0x283978A15512B2FE, ent, true) -- SET_RANDOM_OUTFIT_VARIATION
    SetEntityAsMissionEntity(ent, true, true)
    NetworkRegisterEntityAsNetworked(ent)
    SetBlockingOfNonTemporaryEvents(ent, true)
    SetPedKeepTask(ent, true)
    N(0x4A48B6E03BABB4AC, ent, v.name)                   -- _SET_PED_PROMPT_NAME
    N(0x8FBF9EDB378CCB8C, PlayerId(), ent)               -- _SET_PED_ACTIVE_PLAYER_HORSE
    N(0xE6D4E435B56D5BD0, PlayerId(), ent)               -- _SET_PLAYER_OWNS_MOUNT
    N(0xD2CB0FB0FDCB473D, PlayerId(), ent)               -- _SET_PED_AS_SADDLE_HORSE_FOR_PLAYER
    N(0x11E6B9629C46D6EC, ent, true)                     -- _SET_MOUNT_SECURITY_ENABLED
    applyTack(ent, v.tack)
    applyStats(ent, v)
    if v.injured then N(0xBAE08F00021BFFB2, ent, false) end
    return ent
end

local function personality() return Config.Personalities[horse and horse.view.personality or 'steady'] or Config.Personalities.steady end

local function despawn(reason)
    if not horse then return end
    local ent = horse.ent
    horse = nil
    for _, p in pairs(prompts) do if p then PromptDelete(p) end end
    prompts = {}
    if ent and DoesEntityExist(ent) then
        if reason == 'stable' or reason == 'stored' or reason == 'switch' or reason == 'logout' or reason == 'dropped' or reason == 'listed' or reason == 'sold' or reason == 'transfer' then
            SetEntityAsMissionEntity(ent, true, true)
            DeleteEntity(ent)
        else
            -- flee away and vanish
            TaskSmartFleePed(ent, PlayerPedId(), 200.0, 8000, false, false)
            SetTimeout(8000, function() if DoesEntityExist(ent) then DeleteEntity(ent) end end)
        end
    end
end

local function callHorse(id)
    if horse and DoesEntityExist(horse.ent) then
        -- already out: make it come
        N(0xBAD6545608CECA6E, horse.ent, PlayerPedId(), 3) -- TASK_GO_TO_WHISTLE
        return
    end
    local ok, res = LXR.RPC.Server('lxr-horses:call', id)
    if not ok then return notify('error.' .. tostring(res)) end
    local delay = personality().effects.followDelayMs or 0
    if delay > 0 then Wait(delay) end
    if (personality().effects.skipWhistleChance or 0) > math.random(100) then return notify('info.horse_ignores', 'info', { name = res.name }) end
    local ent = spawnHorse(res)
    if not ent then TriggerServerEvent('lxr-horses:server:store', 'spawn_failed') return notify('error.spawn_failed') end
    horse = { ent = ent, id = res.id, view = res }
    TriggerServerEvent('lxr-horses:server:spawned', res.id, NetworkGetNetworkIdFromEntity(ent))
    N(0xBAD6545608CECA6E, ent, PlayerPedId(), 3) -- TASK_GO_TO_WHISTLE
    TriggerEvent('lxr:horse:client:spawned', ent, res)
end

RegisterNetEvent('lxr-horses:client:spawnAt', function(v, at)
    despawn('switch')
    local ent = spawnHorse(v, at)
    if not ent then return TriggerServerEvent('lxr-horses:server:store', 'spawn_failed') end
    horse = { ent = ent, id = v.id, view = v }
    TriggerServerEvent('lxr-horses:server:spawned', v.id, NetworkGetNetworkIdFromEntity(ent))
    TriggerEvent('lxr:horse:client:spawned', ent, v)
end)

RegisterNetEvent('lxr-horses:client:despawn', function(id, reason) if horse and horse.id == id then despawn(reason) end end)
RegisterNetEvent('lxr-horses:client:tack', function(tack) if horse and DoesEntityExist(horse.ent) then horse.view.tack = tack applyTack(horse.ent, tack) end end)
RegisterNetEvent('lxr-horses:client:injured', function() if horse and DoesEntityExist(horse.ent) then N(0xBAE08F00021BFFB2, horse.ent, true) end end)

-- state bag updates from the server (cores / stats / bond)
AddStateBagChangeHandler(Config.Spawn.stateBag, nil, function(bagName, _, value)
    if not horse or type(value) ~= 'table' or value.id ~= horse.id then return end
    horse.view.cores, horse.view.stats, horse.view.bond, horse.view.personality, horse.view.injured = value.cores, value.stats, value.bond, value.personality, value.injured
    if DoesEntityExist(horse.ent) then applyStats(horse.ent, horse.view) end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🎺 WHISTLE / COMMAND
-- ═══════════════════════════════════════════════════════════════════════════════
if Config.Spawn.whistle then
    CreateThread(function()
        while true do
            Wait(0)
            if IsControlJustReleased(0, Config.Spawn.whistleKey) and LocalPlayer.state.isLoggedIn then
                if not horse or not DoesEntityExist(horse.ent) then
                    if not IsPedOnMount(PlayerPedId()) and not IsPedInAnyVehicle(PlayerPedId(), false) then callHorse(nil) end
                end
                Wait(500)
            end
        end
    end)
end
if Config.Spawn.command and Config.Spawn.command ~= '' then
    RegisterCommand(Config.Spawn.command, function(_, args)
        if args[1] == 'store' then TriggerServerEvent('lxr-horses:server:store', 'stored') despawn('stored') return end
        callHorse(tonumber(args[1]))
    end, false)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🖐️ PROMPTS AROUND THE HORSE + TAG + RIDING REPORT
-- ═══════════════════════════════════════════════════════════════════════════════
local function feedItems()
    local out = {}
    local items = LXRCore.PlayerData and LXRCore.PlayerData.items or {}
    for _, it in pairs(items) do
        local def = LXRShared.Items[it.name]
        if def and H.ItemHorseEffects(def) and (def.effects.horse_hunger or def.effects.horse_thirst) then out[#out + 1] = it.name end
    end
    return out
end

local function interact(action, item)
    local ok, res = LXR.RPC.Server('lxr-horses:interact', action, item)
    if not ok then return notify('error.' .. tostring(res)) end
    if res and res.cores and horse then horse.view.cores = res.cores end
end

local function nearestForeignHorse()
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestD = nil, Config.Interactions.distance
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= (horse and horse.ent) and N(0x772A1969F649E902, GetEntityModel(ped)) then -- _IS_THIS_MODEL_A_HORSE
            local st = Entity(ped).state[Config.Spawn.stateBag]
            if st then
                local d = #(GetEntityCoords(ped) - pos)
                if d < bestD then best, bestD = ped, d end
            end
        end
    end
    return best
end

local function ensurePrompts()
    if next(prompts) then return end
    local K, HOLD = Config.Interactions.keys, Config.Interactions.holdMs
    prompts.feed = LXRCore.Prompts.Register(K.feed, Lang:t('prompt.feed'), HOLD.feed)
    prompts.brush = LXRCore.Prompts.Register(K.brush, Lang:t('prompt.brush'), HOLD.brush)
    prompts.pat = LXRCore.Prompts.Register(K.pat, Lang:t('prompt.pat'), HOLD.pat)
    prompts.bags = LXRCore.Prompts.Register(K.saddlebags, Lang:t('prompt.saddlebags'), HOLD.saddlebags)
    prompts.inspect = LXRCore.Prompts.Register(K.inspect, Lang:t('prompt.inspect'), HOLD.inspect)
end

local function setPromptsVisible(on)
    for _, p in pairs(prompts) do PromptSetEnabled(p, on) PromptSetVisible(p, on) end
end

CreateThread(function()
    local lastRide = 0
    local groupId = GetRandomIntInRange(0, 0xffffff)
    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local target = horse and DoesEntityExist(horse.ent) and horse.ent or nil
        local foreign = false
        if not target then
            target = nearestForeignHorse()
            foreign = target ~= nil
        end
        if target then
            local d = #(GetEntityCoords(ped) - GetEntityCoords(target))
            local mounted = IsPedOnMount(ped)
            if mounted and horse and GetMount(ped) == horse.ent and GetGameTimer() - lastRide > 30000 then
                lastRide = GetGameTimer()
                TriggerServerEvent('lxr-horses:server:riding')
            end
            if d <= Config.Interactions.distance and not mounted then
                sleep = 0
                ensurePrompts()
                setPromptsVisible(true)
                local st = foreign and Entity(target).state[Config.Spawn.stateBag] or horse.view
                PromptSetActiveGroupThisFrame(groupId, st and st.name or Lang:t('ui.horse'))
                if N(0xC92AC953F0A982AE, prompts.feed) then
                    local items = feedItems()
                    if #items == 0 then notify('error.no_feed') else interact('feed', items[1]) end
                    Wait(600)
                elseif N(0xC92AC953F0A982AE, prompts.brush) then interact('brush') Wait(600)
                elseif N(0xC92AC953F0A982AE, prompts.pat) then interact('pat') Wait(600)
                elseif N(0xC92AC953F0A982AE, prompts.bags) then TriggerServerEvent('lxr-horses:server:saddlebags') Wait(600)
                elseif N(0xC92AC953F0A982AE, prompts.inspect) then
                    if not foreign then TriggerEvent('lxr-horses:client:inspect') end
                    Wait(600)
                end
            elseif next(prompts) then
                setPromptsVisible(false)
            end
            -- tag
            if Config.Tag.enabled and tagVisible and d <= Config.Tag.range then
                sleep = 0
                local c = GetEntityCoords(target)
                local st = foreign and Entity(target).state[Config.Spawn.stateBag] or horse.view
                if st then
                    local lines = {}
                    if not foreign or (Config.Tag.showNamesToOthers) then lines[#lines + 1] = st.name end
                    if not foreign or not Config.Tag.ownerOnly then
                        for _, k in ipairs(Config.Tag.show) do
                            if k == 'bond' then lines[#lines + 1] = Lang:t('tag.bond', { level = st.bond or 1 })
                            elseif k == 'personality' then lines[#lines + 1] = (Config.Personalities[st.personality] or {}).label or ''
                            elseif k ~= 'name' and st.cores and st.cores[k] then lines[#lines + 1] = ('%s %d%%'):format(Lang:t('core.' .. k), st.cores[k]) end
                        end
                    end
                    LXRCore.Functions.DrawText3D(c.x, c.y, c.z + 1.4, table.concat(lines, '\n'))
                end
            end
            -- mounted shortcuts
            if mounted and horse and GetMount(ped) == horse.ent and Config.Interactions.mountedShortcuts then
                sleep = 0
                if Config.Interactions.mountedShortcuts.feed and IsControlJustReleased(0, Config.Interactions.mountedShortcuts.feed) then
                    local items = feedItems()
                    if #items > 0 then interact('feed', items[1]) end
                elseif Config.Interactions.mountedShortcuts.brush and IsControlJustReleased(0, Config.Interactions.mountedShortcuts.brush) then
                    interact('brush')
                end
            end
            -- health watch (own horse)
            if horse and target == horse.ent then
                if IsEntityDead(target) and not horse.reportedDead then horse.reportedDead = true TriggerServerEvent('lxr-horses:server:health', 'dead') end
                if not horse.view.injured and GetEntityHealth(target) > 0 and GetEntityHealth(target) < GetEntityMaxHealth(target, false) * 0.15 and not horse.reportedInjury then
                    horse.reportedInjury = true
                    TriggerServerEvent('lxr-horses:server:health', 'injured')
                end
                -- wandered off → back to the stable
                if d > Config.Spawn.returnToStableWhenFar then
                    horse.farSince = horse.farSince or GetGameTimer()
                    if GetGameTimer() - horse.farSince > 120000 then TriggerServerEvent('lxr-horses:server:store', 'wandered') despawn('wandered') end
                else
                    horse.farSince = nil
                end
            end
        elseif next(prompts) then
            setPromptsVisible(false)
        end
        Wait(sleep)
    end
end)

if Config.Tag.enabled then
    CreateThread(function()
        while true do
            Wait(0)
            if IsControlJustReleased(0, Config.Tag.toggleKey) and horse then tagVisible = not tagVisible Wait(300) end
        end
    end)
end

RegisterNetEvent('lxr-horses:client:anim', function(action, item)
    local ped = PlayerPedId()
    local key = ({ feed = 'feed_horse', brush = 'brush_horse', pat = 'feed_horse', hoof = 'tool', revive = 'inject', tonic = 'feed_horse', shoes = 'craft' })[action] or 'inspect'
    local anim = LXRShared.Animations[key]
    if not anim then return end
    RequestAnimDict(anim.dict)
    local t = 0
    while not HasAnimDictLoaded(anim.dict) and t < 40 do Wait(50) t = t + 1 end
    if HasAnimDictLoaded(anim.dict) then TaskPlayAnim(ped, anim.dict, anim.name, 2.0, 2.0, Config.Interactions.progressMs[action] or anim.duration or 3000, anim.flag or 31, 0, false, false, false) end
    if horse and DoesEntityExist(horse.ent) and (action == 'feed' or action == 'brush' or action == 'pat') then
        TaskLookAtEntity(horse.ent, ped, 3000, 2048, 3, 0)
    end
end)

RegisterNetEvent('lxr-horses:client:inspect', function()
    if not horse then return end
    local v = horse.view
    local s = v.stats or {}
    notify('info.inspect', 'info', { name = v.name, breed = v.breed or '', speed = s.speed or 0, stamina = s.stamina or 0, health = s.health or 0, bond = v.bond or 1, personality = v.personalityLabel or '' })
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🤝 TRANSFER
-- ═══════════════════════════════════════════════════════════════════════════════
RegisterCommand('givehorse', function(_, args)
    local target = tonumber(args[1])
    if not target then return notify('error.invalid') end
    local ok, err = LXR.RPC.Server('lxr-horses:transfer', target)
    if not ok then return notify('error.' .. tostring(err)) end
    notify('info.transfer_sent', 'info')
end, false)

RegisterNetEvent('lxr-horses:client:transferOffer', function(fromSrc, v)
    notify('info.transfer_offer', 'info', { name = v.name, id = fromSrc })
    local prompt = LXRCore.Prompts.Register(0xC7B5340A, Lang:t('prompt.accept_horse', { name = v.name }), 1000) -- ENTER
    local decline = LXRCore.Prompts.Register(0x156F7119, Lang:t('prompt.decline_horse'), 0)                    -- BACKSPACE
    local until_ = GetGameTimer() + 25000
    local answered = false
    while GetGameTimer() < until_ and not answered do
        Wait(0)
        PromptSetEnabled(prompt, true) PromptSetVisible(prompt, true)
        PromptSetEnabled(decline, true) PromptSetVisible(decline, true)
        PromptSetActiveGroupThisFrame(9001, Lang:t('ui.transfer'))
        if N(0xC92AC953F0A982AE, prompt) then answered = true TriggerServerEvent('lxr-horses:server:transferAnswer', true)
        elseif N(0xC92AC953F0A982AE, decline) then answered = true TriggerServerEvent('lxr-horses:server:transferAnswer', false) end
    end
    PromptDelete(prompt) PromptDelete(decline)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🐎 WILD HERDS
-- ═══════════════════════════════════════════════════════════════════════════════
local function spawnHerd(herd, models)
    local list, ents = {}, {}
    for i, model in ipairs(models) do
        local hash = joaat(model)
        RequestModel(hash)
        local t = 0
        while not HasModelLoaded(hash) and t < 200 do Wait(25) t = t + 1 end
        if HasModelLoaded(hash) then
            local ang = math.random() * math.pi * 2
            local r = math.random(10, math.floor(herd.radius * 0.5))
            local x, y = herd.coords.x + math.cos(ang) * r, herd.coords.y + math.sin(ang) * r
            local ok, z = GetGroundZFor_3dCoord(x, y, herd.coords.z + 50.0, false)
            local ent = CreatePed(hash, x, y, ok and z or herd.coords.z, math.random(0, 359) + 0.0, true, true, false, false)
            if ent and ent ~= 0 then
                N(0x283978A15512B2FE, ent, true)
                SetEntityAsMissionEntity(ent, true, true)
                NetworkRegisterEntityAsNetworked(ent)
                SetPedFleeAttributes(ent, 0, false)
                TaskWanderInArea(ent, herd.coords.x, herd.coords.y, herd.coords.z, herd.radius * 0.6, 5.0, 5.0)
                list[#list + 1] = { netId = NetworkGetNetworkIdFromEntity(ent), model = model }
                ents[#ents + 1] = ent
            end
            SetModelAsNoLongerNeeded(hash)
        end
    end
    wildLocal[herd.id] = { ents = ents }
    TriggerServerEvent('lxr-horses:server:wildSpawned', herd.id, list)
end

if Config.Wild.enabled then
    CreateThread(function()
        while true do
            Wait(5000)
            if LocalPlayer.state.isLoggedIn then
                local pos = GetEntityCoords(PlayerPedId())
                for _, herd in ipairs(Config.Wild.herds) do
                    if #(pos - herd.coords) <= herd.radius and not wildLocal[herd.id] then
                        local ok, models = LXR.RPC.Server('lxr-horses:wild:request', herd.id)
                        if ok and type(models) == 'table' then spawnHerd(herd, models) else wildLocal[herd.id] = { ents = {}, until_ = GetGameTimer() + 60000 } end
                    elseif wildLocal[herd.id] and wildLocal[herd.id].until_ and GetGameTimer() > wildLocal[herd.id].until_ then
                        wildLocal[herd.id] = nil
                    end
                end
            end
        end
    end)

    -- taming: mounted on a wild horse the server spawned (state bag absent, not our horse) for calmSeconds
    CreateThread(function()
        local mountedSince, mountedOn = nil, nil
        while true do
            Wait(500)
            local ped = PlayerPedId()
            if IsPedOnMount(ped) then
                local m = GetMount(ped)
                if m ~= 0 and (not horse or m ~= horse.ent) and not Entity(m).state[Config.Spawn.stateBag] and not Entity(m).state.lxrTamed then
                    if mountedOn ~= m then mountedOn, mountedSince = m, GetGameTimer() end
                    if GetGameTimer() - mountedSince >= Config.Wild.taming.calmSeconds * 1000 then
                        local netId = NetworkGetNetworkIdFromEntity(m)
                        if N(0x454AD4DA6C41B5BD, m) ~= 0 or true then -- _GET_HORSE_TAMING_STATE (informational)
                            TriggerServerEvent('lxr-horses:server:wildTamed', netId)
                            Entity(m).state:set('lxrTamed', true, false)
                            N(0x227B06324234FB09, PlayerId(), m) -- SET_PED_AS_TEMP_PLAYER_HORSE
                            mountedOn, mountedSince = nil, nil
                        end
                    end
                else
                    mountedOn, mountedSince = nil, nil
                end
            else
                mountedOn, mountedSince = nil, nil
            end
        end
    end)
end

RegisterNetEvent('lxr-horses:client:releaseWild', function(netId)
    if NetworkDoesNetworkIdExist(netId) then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent ~= 0 then SetEntityAsMissionEntity(ent, true, true) DeleteEntity(ent) end
    end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🏁 TRAINING COURSES
-- ═══════════════════════════════════════════════════════════════════════════════
if Config.Training.enabled then
    for _, course in ipairs(Config.Training.courses) do
        LXRCore.Functions.Door('lxr-horses:course:' .. course.id, course.start, { label = Lang:t('prompt.train', { course = course.label }), action = Lang:t('prompt.open'), distance = 5.0, control = 0xC7B5340A }, (function()
            return function()
                if training then return end
                if not horse or not IsPedOnMount(PlayerPedId()) or GetMount(PlayerPedId()) ~= horse.ent then return notify('error.mount_first') end
                local ok, res = LXR.RPC.Server('lxr-horses:training:start', course.id)
                if not ok then return notify('error.' .. tostring(res)) end
                training = { course = res, index = 1, startedAt = GetGameTimer() }
                notify('info.training_started', 'info', { course = res.label, time = res.timeLimitSec })
            end
        end)())
    end
    CreateThread(function()
        local blip
        while true do
            local sleep = 1000
            if training then
                sleep = 0
                local cp = training.course.checkpoints[training.index]
                local ped = PlayerPedId()
                if not cp then
                    TriggerServerEvent('lxr-horses:server:trainingDone', training.course.id, true)
                    training = nil
                    if blip then RemoveBlip(blip) blip = nil end
                else
                    local target = vector3(cp.x, cp.y, cp.z)
                    DrawMarker(0x50638AB9, target.x, target.y, target.z + 1.5, 0, 0, 0, 0, 0, 0, 2.0, 2.0, 2.0, 194, 28, 55, 160, true, false, 2, false, nil, nil, false)
                    if not blip then blip = N(0x554D9D53F696D002, 1664425300, target.x, target.y, target.z) end -- BLIP_ADD_FOR_COORDS
                    if #(GetEntityCoords(ped) - target) <= training.course.radius and IsPedOnMount(ped) then
                        training.index = training.index + 1
                        if blip then RemoveBlip(blip) blip = nil end
                    end
                    if (GetGameTimer() - training.startedAt) / 1000 > training.course.timeLimitSec or not IsPedOnMount(ped) then
                        TriggerServerEvent('lxr-horses:server:trainingDone', training.course.id, false)
                        training = nil
                        if blip then RemoveBlip(blip) blip = nil end
                    end
                end
            end
            Wait(sleep)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🧹 CLEANUP
-- ═══════════════════════════════════════════════════════════════════════════════
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    despawn('stored')
    for _, h in pairs(wildLocal) do for _, e in ipairs(h.ents or {}) do if DoesEntityExist(e) then DeleteEntity(e) end end end
end)
RegisterNetEvent('lxr:client:unloaded', function() despawn('logout') end)

exports('GetHorse', function() return horse and horse.ent or nil, horse and horse.view or nil end)
exports('CallHorse', callHorse)
