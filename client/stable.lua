--[[ ═══════════════════════════════════════════════════════════════════════════
     🐺 LXR-HORSES — Client: stable UI (vanilla NUI), preview ped and camera
     ═══════════════════════════════════════════════════════════════════════════
     © 2026 iBoss21 / LXRCore — All Rights Reserved
     ═══════════════════════════════════════════════════════════════════════════ ]]

local LXRCore = exports['lxr-core']:GetCoreObject()
local LXR = exports['lxr-core']:GetLXR()
local N = Citizen.InvokeNative

local open = nil        -- { stable }
local preview = { ped = nil, cam = nil, model = nil }
local blips = {}

local function notify(key, kind, vars) LXRCore.Functions.Notify(Lang:t(key, vars), kind or 'error') end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 👁️ PREVIEW
-- ═══════════════════════════════════════════════════════════════════════════════
local function clearPreview()
    if preview.ped and DoesEntityExist(preview.ped) then DeleteEntity(preview.ped) end
    preview.ped, preview.model = nil, nil
end

local function showPreview(model, tack, scale)
    if not open then return end
    local stable = open.stable
    if preview.model ~= model then
        clearPreview()
        local hash = joaat(model)
        if not IsModelValid(hash) then return end
        RequestModel(hash)
        local t = 0
        while not HasModelLoaded(hash) and t < 200 do Wait(25) t = t + 1 end
        local p = stable.preview
        local ped = CreatePed(hash, p.x, p.y, p.z, stable.heading or 0.0, false, false, false, false)
        SetModelAsNoLongerNeeded(hash)
        N(0x283978A15512B2FE, ped, true)
        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        preview.ped, preview.model = ped, model
    end
    if preview.ped then
        for _, def in pairs(LXRHorses.TackSlots) do N(0xD710A5007C2AC539, preview.ped, def.category, 0) end
        for _, pieceId in pairs(tack or {}) do
            local piece = LXRHorses.TackById[pieceId]
            if piece then N(0xD3A7B003ED343FD9, preview.ped, piece.hash, true, true, true) end
        end
        N(0xAAB86462966168CE, preview.ped, true)
        if scale then N(0x25ACFC650B65C538, preview.ped, scale + 0.0) end
    end
end

local function startCamera()
    if not Config.StableUI.previewCamera or not open then return end
    local p = open.stable.preview
    local h = math.rad(open.stable.heading or 0.0)
    preview.cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', p.x - math.sin(h) * 4.5, p.y + math.cos(h) * 4.5, p.z + 1.4, 0.0, 0.0, 0.0, 45.0, false, 0)
    PointCamAtCoord(preview.cam, p.x, p.y, p.z + 0.9)
    SetCamActive(preview.cam, true)
    RenderScriptCams(true, true, 800, true, true)
end

local function stopCamera()
    if preview.cam then
        RenderScriptCams(false, true, 800, true, true)
        DestroyCam(preview.cam, false)
        preview.cam = nil
    end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 🪟 OPEN / CLOSE
-- ═══════════════════════════════════════════════════════════════════════════════
local function close()
    if not open then return end
    open = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    clearPreview()
    stopCamera()
end

local function openStable(stable)
    if open then return end
    local ok, data = LXR.RPC.Server('lxr-horses:stable:open', stable.id)
    if not ok then return notify('error.' .. tostring(data)) end
    open = { stable = stable }
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = data, brand = LXRCore.Brand })
    startCamera()
    if data.owned[1] then showPreview(data.owned[1].model, data.owned[1].tack, data.owned[1].scale) end
end

RegisterNUICallback('close', function(_, cb) close() cb('ok') end)
RegisterNUICallback('preview', function(d, cb) showPreview(d.model, d.tack, d.scale) cb('ok') end)

local function rpc(name, ...)
    if not open then return false, 'closed' end
    local ok, res = LXR.RPC.Server(name, open.stable.id, ...)
    if not ok then notify('error.' .. tostring(res)) return false, res end
    return true, res
end

RegisterNUICallback('buy', function(d, cb)
    local ok, res = rpc('lxr-horses:stable:buy', d.model, { name = d.name, gender = d.gender, scale = d.scale })
    if ok then notify('info.bought', 'success', { name = d.name or '' }) cb({ ok = true, data = res }) else cb({ ok = false, error = res }) end
end)
RegisterNUICallback('sell', function(d, cb)
    local ok, res = rpc('lxr-horses:stable:sell', d.id)
    if ok then notify('info.sold', 'success') cb({ ok = true, data = res }) else cb({ ok = false, error = res }) end
end)
RegisterNUICallback('action', function(d, cb)
    local ok, res = rpc('lxr-horses:stable:action', d.action, d.id, d.arg)
    if ok then
        if d.action == 'select' then close() end
        cb({ ok = true, data = res })
    else cb({ ok = false, error = res }) end
end)
RegisterNUICallback('tack', function(d, cb)
    local ok, res = rpc('lxr-horses:stable:tack', d.action, d.piece)
    cb(ok and { ok = true, data = res } or { ok = false, error = res })
end)
RegisterNUICallback('marketBuy', function(d, cb)
    local ok, res = rpc('lxr-horses:market:buy', d.id)
    cb(ok and { ok = true, data = res } or { ok = false, error = res })
end)
RegisterNUICallback('wild', function(d, cb)
    local ok, res = rpc('lxr-horses:wild:claim', d.sell == true)
    cb(ok and { ok = true, data = res } or { ok = false, error = res })
end)
RegisterNUICallback('breed', function(d, cb)
    local ok, res
    if d.collect then ok, res = rpc('lxr-horses:breed:collect') else ok, res = rpc('lxr-horses:breed', d.sire, d.dam) end
    cb(ok and { ok = true, data = res } or { ok = false, error = res })
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 📍 PROMPTS & BLIPS
-- ═══════════════════════════════════════════════════════════════════════════════
CreateThread(function()
    for _, stable in ipairs(Config.Stables) do
        LXRCore.Prompts.Create('lxr-horses:stable:' .. stable.id, stable.coords, Config.StableUI.key, Lang:t('prompt.stable', { name = stable.label }),
            { type = 'callback', event = function() openStable(stable) end }, Config.StableUI.promptDistance, nil, 0)
        if stable.blip then
            local blip = N(0x554D9D53F696D002, 1664425300, stable.coords.x, stable.coords.y, stable.coords.z) -- BLIP_ADD_FOR_COORDS
            if blip and blip ~= 0 then
                N(0x74F74D3207ED525C, blip, joaat(Config.StableUI.blipSprite), true) -- SET_BLIP_SPRITE
                N(0x9CB1A1623062F402, blip, stable.label)                         -- _SET_BLIP_NAME
                if GetResourceState('lxr-mapcolor') == 'started' then
                    pcall(function() N(0x662D364ABF16DE2F, blip, exports['lxr-mapcolor']:modifier('stable')) end) -- BLIP_ADD_MODIFIER
                end
                blips[#blips + 1] = blip
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(open and 0 or 1000)
        if open then
            DisableControlAction(0, 0x4CC0E2FE, true) -- B
            if IsControlJustReleased(0, 0x156F7119) then close() end -- BACKSPACE
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    close()
    for _, b in ipairs(blips) do RemoveBlip(b) end
end)
