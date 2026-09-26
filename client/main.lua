local state = {
    open = false,
    busy = false,
    cam = nil,
    peds = {},      -- [entry index] = ped
    entries = {},   -- [i] = character or false (empty slot)
    selected = nil,
    scene = nil,
}

local function defaultModel(gender)
    return gender == 1 and `mp_f_freemode_01` or `mp_m_freemode_01`
end

local function toNui(ch)
    return {
        citizenid = ch.citizenid,
        firstname = ch.firstname, lastname = ch.lastname,
        gender = ch.gender, birthdate = ch.birthdate, nationality = ch.nationality,
        cash = ch.cash, bank = ch.bank,
        job = ch.job, grade = ch.grade,
    }
end

local function trackItems()
    local items = {}
    for i, slot in ipairs(state.scene.slots) do
        if state.entries[i] ~= nil then
            items[#items + 1] = { key = i, ped = state.peds[i], coords = slot.coords }
        end
    end
    return items
end

-- Frame a ped from the scene camera's side, looking at the upper chest
local function focusShot(ped)
    local F, wide = Config.Focus, state.wide
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local target = vec3(head.x, head.y, head.z - 0.2)
    local dir = vec3(wide.x - target.x, wide.y - target.y, 0.0)
    local len = #dir
    dir = len > 0.01 and dir / len or vec3(0.0, 1.0, 0.0)

    local pos = vec3(target.x + dir.x * F.distance, target.y + dir.y * F.distance, head.z + F.height)
    local rx, rz = SceneUtil.lookRotation(pos, target)
    return { x = pos.x, y = pos.y, z = pos.z, rx = rx, ry = 0.0, rz = rz, fov = F.fov }, #(pos - target)
end

local function select(index, instant)
    if state.selected == index and not instant then return end
    state.selected = index
    local ped = state.peds[index]
    -- Empty-slot selections ghost everyone
    SceneUtil.ghost(state.peds, ped and index or -1)

    if not state.cam then return end
    local shot, dist = state.wide, nil
    if Config.Focus.enabled and ped then
        shot, dist = focusShot(ped)
    end
    state.cam = SceneUtil.glide(state.cam, shot, instant and 0 or Config.Focus.duration, Config.Focus.dof and dist or nil)
end

-- Fetch characters, (re)build the peds and push everything to the NUI
local function refresh(intro)
    local chars, allowed = lib.callback.await('srp-multicharacter:server:getCharacters', false)
    chars = chars or {}
    allowed = math.max(allowed or Config.DefaultSlots, #chars)

    SceneUtil.deletePeds(state.peds)
    state.entries = {}
    for i = 1, allowed do state.entries[i] = chars[i] or false end

    for i, slot in ipairs(state.scene.slots) do
        local ch = state.entries[i]
        if ch then
            local ped = SceneUtil.createPed(ch.model or defaultModel(ch.gender), slot.coords, ch.skin)
            SceneUtil.playAnim(ped, slot.anim)
            state.peds[i] = ped
        end
    end

    local list = {}
    for i, ch in ipairs(state.entries) do
        list[i] = ch and toNui(ch) or false
    end

    Wait(250) -- let the animations settle so the head bone is where it'll stay
    state.selected = nil
    if intro then
        SceneUtil.ghost(state.peds, nil)
    else
        select(1)
    end
    SendNUIMessage({
        action = 'open',
        entries = list,
        sceneSlots = #state.scene.slots,
        selected = 1,
        canDelete = Config.EnableDelete,
        intro = intro and {
            title = Config.Intro.title,
            subtitle = Config.Intro.subtitle,
            prompt = Config.Intro.prompt,
        } or nil,
    })
end

-- Loop drifting shots of the location until the player continues
local function playIntro()
    local token = {}
    state.intro = token
    local shots = SceneUtil.introFor(state.scene)
    local fade = Config.Intro.fade

    CreateThread(function()
        local i = 1
        while state.intro == token do
            local shot = shots[i]
            state.cam = SceneUtil.playShot(shot, state.cam)
            if i > 1 or IsScreenFadedOut() then DoScreenFadeIn(fade) end

            local cutAt = GetGameTimer() + (shot.duration or 6000) - fade
            while GetGameTimer() < cutAt and state.intro == token do Wait(0) end
            if state.intro ~= token then break end

            DoScreenFadeOut(fade)
            while not IsScreenFadedOut() and state.intro == token do Wait(0) end
            i = i % #shots + 1
        end
    end)
end

local function finishIntro()
    if not state.intro then return end
    state.intro = nil
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(600) end
    select(1)
end

local function openSelector()
    if state.open then return end
    state.open, state.busy = true, false

    if not IsScreenFadedOut() then
        DoScreenFadeOut(250)
        while not IsScreenFadingOut() and not IsScreenFadedOut() do Wait(0) end
        while not IsScreenFadedOut() do Wait(0) end
    end
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()

    TriggerServerEvent('srp-multicharacter:server:enter')
    SceneUtil.fetch()
    state.scene = SceneUtil.active()
    if not state.scene then
        state.open = false
        DoScreenFadeIn(250)
        return lib.print.error('no character scenes configured')
    end

    local camData = SceneUtil.cameraFor(state.scene)
    state.wide = camData
    SceneUtil.setEnvironment(state.scene)
    SceneUtil.loadArea(state.scene, camData)
    state.cam = SceneUtil.createCam(camData)
    DisplayRadar(false)

    if Config.Focus.dof then
        CreateThread(function()
            while state.open do
                SetUseHiDof()
                Wait(0)
            end
        end)
    end

    local intro = Config.Intro.enabled
    refresh(intro)
    if intro then playIntro() end
    SetNuiFocus(true, true)
    SceneUtil.track(function() return state.open end, trackItems, 'positions')

    CreateThread(function()
        while state.open do
            if state.scene.time then NetworkOverrideClockTime(state.scene.time.hour, state.scene.time.minute, 0) end
            Wait(1000)
        end
    end)

    Wait(300)
    DoScreenFadeIn(800)
end

local function closeSelector()
    state.open = false
    state.intro = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    SceneUtil.deletePeds(state.peds)
    SceneUtil.destroyCam(state.cam)
    state.cam = nil
    ClearFocus()
    SceneUtil.clearEnvironment()
    DisplayRadar(true)
    TriggerServerEvent('srp-multicharacter:server:leave')
end

local function fadeOut()
    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end
end

local function spawnAt(c)
    local ped = PlayerPedId()
    RequestCollisionAtCoord(c.x, c.y, c.z)
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
    SetEntityHeading(ped, c.w or c.a or 0.0)

    local timeout = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do Wait(0) end

    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)

    TriggerServerEvent('QBCore:Server:OnPlayerLoaded')
    TriggerEvent('QBCore:Client:OnPlayerLoaded')

    Wait(500)
    DoScreenFadeIn(1000)
end

local function started(res) return GetResourceState(res) == 'started' end

---------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------

RegisterNUICallback('introDone', function(_, cb)
    cb('ok')
    if state.open then finishIntro() end
end)

RegisterNUICallback('select', function(data, cb)
    cb('ok')
    if state.open then select(tonumber(data.index)) end
end)

RegisterNUICallback('play', function(data, cb)
    local ch = state.entries[tonumber(data.index)]
    if not state.open or state.busy or not ch then return cb(false) end
    state.busy = true
    cb(true)

    fadeOut()
    closeSelector()
    lib.callback.await('qbx_core:server:loadCharacter', false, ch.citizenid)

    -- Same hand-off order as qbx_core's built-in selector
    if Config.UseSpawnSelector and started('qbx_apartments') then
        TriggerEvent('apartments:client:setupSpawnUI', ch.citizenid)
    elseif Config.UseSpawnSelector and started('qbx_spawn') then
        TriggerEvent('qb-spawn:client:setupSpawns', ch.citizenid)
        TriggerEvent('qb-spawn:client:openUI', true)
    else
        local pos = ch.position or Config.NewCharacter.coords
        spawnAt(pos)
    end
    state.busy = false
end)

local function validName(s)
    return type(s) == 'string' and #s >= 2 and #s <= 16 and s:match("^[%a][%a%-' ]*$") ~= nil
end

RegisterNUICallback('create', function(data, cb)
    if not state.open or state.busy then return cb({ ok = false }) end

    local index = tonumber(data.index)
    if not index or state.entries[index] ~= false then
        return cb({ ok = false, error = 'That slot is not available.' })
    end
    if not validName(data.firstname) or not validName(data.lastname) then
        return cb({ ok = false, error = 'Names must be 2-16 letters.' })
    end
    local y, m, d = tostring(data.birthdate or ''):match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if not y or y < 1900 or y > tonumber(os.date('%Y') or 2100) or m < 1 or m > 12 or d < 1 or d > 31 then
        return cb({ ok = false, error = 'Enter a valid date of birth.' })
    end

    -- First unused cid
    local used = {}
    for _, ch in ipairs(state.entries) do if ch then used[ch.cid] = true end end
    local cid = 1
    while used[cid] do cid += 1 end

    state.busy = true
    local nationality = type(data.nationality) == 'string' and data.nationality:gsub('[%c<>]', ''):sub(1, 30) or ''
    local newData = lib.callback.await('qbx_core:server:createCharacter', false, {
        firstname = data.firstname, lastname = data.lastname,
        nationality = nationality ~= '' and nationality or 'American',
        gender = data.gender == 'female' and 1 or 0,
        birthdate = data.birthdate,
        cid = cid,
    })

    if not newData then
        state.busy = false
        return cb({ ok = false, error = 'Could not create character.' })
    end
    cb({ ok = true })

    fadeOut()
    closeSelector()
    spawnAt(Config.NewCharacter.coords)
    if Config.NewCharacter.openClothing then
        TriggerEvent('qb-clothes:client:CreateFirstCharacter')
    end
    state.busy = false
end)

RegisterNUICallback('delete', function(data, cb)
    local ch = state.entries[tonumber(data.index)]
    if not state.open or state.busy or not ch or not Config.EnableDelete then return cb(false) end
    state.busy = true
    local ok = lib.callback.await('srp-multicharacter:server:deleteCharacter', false, ch.citizenid)
    if ok then refresh() end
    state.busy = false
    cb(ok and true or false)
end)

---------------------------------------------------------------------
-- Entry points
---------------------------------------------------------------------

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(0) end
    pcall(function() exports.spawnmanager:setAutoSpawn(false) end)
    Wait(250)
    if not LocalPlayer.state.isLoggedIn then openSelector() end
end)

-- /logout and friends
RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    if GetInvokingResource() then return end
    Wait(500)
    openSelector()
end)

-- Rebuild live if an admin saves the active scene while someone is selecting
AddEventHandler('srp-multicharacter:client:scenesUpdated', function()
    if not state.open or state.busy then return end
    local scene = SceneUtil.active()
    if not scene then return end
    state.scene = scene
    SceneUtil.destroyCam(state.cam)
    SceneUtil.setEnvironment(scene)
    state.wide = SceneUtil.cameraFor(scene)
    state.cam = SceneUtil.createCam(state.wide)
    refresh()
end)

exports('OpenSelector', openSelector)
exports('IsSelectorOpen', function() return state.open end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not state.open then return end
    SetNuiFocus(false, false)
    SceneUtil.deletePeds(state.peds)
    SceneUtil.destroyCam(state.cam)
    ClearFocus()
end)
