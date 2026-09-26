local editor = {
    open = false,
    scene = nil,      -- draft of the scene being edited (from the NUI)
    peds = {},        -- [slot index] = preview ped
    anims = {},       -- [slot index] = json of the anim last played
    selected = nil,
    previewCam = nil,
    freecam = false,
    returnPos = nil,
}

local function animsForNui()
    local out = {}
    for i, a in ipairs(Config.Animations) do
        out[i] = { id = a.id, label = a.label, kind = a.scenario and 'scenario' or 'anim' }
    end
    return out
end

-- Preview peds are clones of the admin so outfits read like a real character
local function makePreviewPed(coords)
    local src = PlayerPedId()
    local ped = ClonePed(src, false, false, true)
    SceneUtil.placePed(ped, coords)
    SetEntityVisible(ped, true, false)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetEntityCollision(ped, false, false)
    return ped
end

local function clearPreview()
    SceneUtil.deletePeds(editor.peds)
    editor.anims = {}
end

-- Diff the draft against the spawned peds so nudges don't restart animations
local function applyDraft()
    local scene = editor.scene
    if not scene then return clearPreview() end

    for i, slot in ipairs(scene.slots) do
        local ped = editor.peds[i]
        if not ped or not DoesEntityExist(ped) then
            ped = makePreviewPed(slot.coords)
            editor.peds[i] = ped
            editor.anims[i] = nil
        else
            SceneUtil.placePed(ped, slot.coords)
        end
        local key = json.encode(slot.anim or {})
        if editor.anims[i] ~= key then
            editor.anims[i] = key
            SceneUtil.playAnim(ped, slot.anim)
        end
    end

    for i, ped in pairs(editor.peds) do
        if i > #scene.slots then
            if DoesEntityExist(ped) then DeleteEntity(ped) end
            editor.peds[i], editor.anims[i] = nil, nil
        end
    end

    SceneUtil.ghost(editor.peds, editor.selected)
end

local function stopPreviewCam()
    if not editor.previewCam then return end
    SceneUtil.destroyCam(editor.previewCam)
    editor.previewCam = nil
    SceneUtil.clearEnvironment()
    SendNUIMessage({ action = 'editorPreview', active = false })
end

local function trackItems()
    local items = {}
    if editor.scene then
        for i, slot in ipairs(editor.scene.slots) do
            items[#items + 1] = { key = i, ped = editor.peds[i], coords = slot.coords }
        end
    end
    return items
end

local function closeEditor()
    editor.open = false
    editor.freecam = false
    stopPreviewCam()
    clearPreview()
    editor.scene = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeEditor' })
end

-- Marker over the selected slot while the editor is open
local function markerLoop()
    CreateThread(function()
        while editor.open do
            local slot = editor.scene and editor.selected and editor.scene.slots[editor.selected]
            if slot and not editor.previewCam then
                local c = slot.coords
                DrawMarker(2, c.x, c.y, c.z + 1.25, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.25, 0.25, 0.2, 216, 179, 106, 200, true, true, 2, false, nil, nil, false)
                -- heading arrow at the feet
                local h = math.rad(c.w or 0.0)
                local fx, fy = -math.sin(h), math.cos(h)
                DrawLine(c.x, c.y, c.z - 0.95, c.x + fx * 0.8, c.y + fy * 0.8, c.z - 0.95, 216, 179, 106, 255)
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent('srp-multicharacter:client:openEditor', function(data)
    if editor.open then return end
    if exports[GetCurrentResourceName()]:IsSelectorOpen() then return end
    Scenes = data
    editor.open = true
    editor.returnPos = nil
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openEditor',
        scenes = data.scenes,
        active = data.active,
        animations = animsForNui(),
        weathers = Config.Weathers,
    })
    markerLoop()
end)

AddEventHandler('srp-multicharacter:client:scenesUpdated', function()
    if editor.open then
        SendNUIMessage({ action = 'editorSync', scenes = Scenes.scenes, active = Scenes.active })
    end
end)

---------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------

RegisterNUICallback('editor:close', function(_, cb)
    cb('ok')
    closeEditor()
end)

RegisterNUICallback('editor:draft', function(data, cb)
    cb('ok')
    if not editor.open then return end
    editor.scene = type(data.scene) == 'table' and data.scene or nil
    editor.selected = tonumber(data.selected)
    applyDraft()

    if editor.previewCam and editor.scene then
        local c = SceneUtil.cameraFor(editor.scene)
        SetCamCoord(editor.previewCam, c.x, c.y, c.z)
        SetCamRot(editor.previewCam, c.rx, c.ry or 0.0, c.rz, 2)
        SetCamFov(editor.previewCam, c.fov or 50.0)
        SceneUtil.setEnvironment(editor.scene)
    end
end)

RegisterNUICallback('editor:replay', function(data, cb)
    cb('ok')
    local i = tonumber(data.index)
    if i and editor.peds[i] and editor.scene and editor.scene.slots[i] then
        SceneUtil.playAnim(editor.peds[i], editor.scene.slots[i].anim)
    end
end)

RegisterNUICallback('editor:myPosition', function(_, cb)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    cb({ x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) })
end)

RegisterNUICallback('editor:autoCamera', function(_, cb)
    cb(editor.scene and SceneUtil.autoCamera(editor.scene.slots) or false)
end)

RegisterNUICallback('editor:preview', function(data, cb)
    cb('ok')
    if not editor.scene then return end
    if not data.active then return stopPreviewCam() end
    if editor.previewCam then return end
    SceneUtil.setEnvironment(editor.scene)
    editor.previewCam = SceneUtil.createCam(SceneUtil.cameraFor(editor.scene))
    SendNUIMessage({ action = 'editorPreview', active = true })
    SceneUtil.track(function() return editor.open and editor.previewCam ~= nil end, trackItems, 'editorPositions')
end)

-- Hand the mouse back so the admin can walk to a spot; E returns to the editor
RegisterNUICallback('editor:release', function(_, cb)
    cb('ok')
    stopPreviewCam()
    SetNuiFocus(false, false)
    CreateThread(function()
        while editor.open do
            if IsControlJustReleased(0, 38) then -- E
                SetNuiFocus(true, true)
                SendNUIMessage({ action = 'editorFocus' })
                return
            end
            Wait(0)
        end
    end)
end)

RegisterNUICallback('editor:goto', function(_, cb)
    cb('ok')
    if not editor.scene or #editor.scene.slots == 0 then return end
    local ped = PlayerPedId()
    if not editor.returnPos then
        local p = GetEntityCoords(ped)
        editor.returnPos = vec4(p.x, p.y, p.z, GetEntityHeading(ped))
    end
    local c = SceneUtil.cameraFor(editor.scene)
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end
    RequestCollisionAtCoord(c.x, c.y, c.z)
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
    local timeout = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do Wait(0) end
    DoScreenFadeIn(400)
end)

RegisterNUICallback('editor:return', function(_, cb)
    cb('ok')
    local p = editor.returnPos
    if not p then return end
    editor.returnPos = nil
    local ped = PlayerPedId()
    DoScreenFadeOut(250)
    while not IsScreenFadedOut() do Wait(0) end
    RequestCollisionAtCoord(p.x, p.y, p.z)
    SetEntityCoords(ped, p.x, p.y, p.z, false, false, false, false)
    SetEntityHeading(ped, p.w)
    DoScreenFadeIn(400)
end)

-- Free camera: WASD move, Q/E down/up, mouse look, Shift fast, Alt slow,
-- scroll = FOV, Enter = use this view, Backspace = cancel
RegisterNUICallback('editor:freecam', function(data, cb)
    cb('ok')
    if editor.freecam or not editor.scene then return end
    stopPreviewCam()
    editor.freecam = true
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'editorFreecam', active = true })

    local start = type(data.start) == 'table' and data.start or editor.scene.camera or SceneUtil.autoCamera(editor.scene.slots)
    local pos = vec3(start.x, start.y, start.z)
    local rx, rz, fov = start.rx, start.rz, start.fov or 50.0
    local cam = SceneUtil.createCam(start)
    SceneUtil.setEnvironment(editor.scene)

    CreateThread(function()
        local result
        while editor.freecam do
            DisableAllControlActions(0)
            HideHudAndRadarThisFrame()

            rz = rz - GetDisabledControlNormal(0, 1) * 8.0
            rx = math.max(-89.0, math.min(89.0, rx - GetDisabledControlNormal(0, 2) * 8.0))

            local speed = IsDisabledControlPressed(0, 21) and 0.25 or IsDisabledControlPressed(0, 19) and 0.01 or 0.05
            local h, p = math.rad(rz), math.rad(rx)
            local fwd = vec3(-math.sin(h) * math.cos(p), math.cos(h) * math.cos(p), math.sin(p))
            local right = vec3(math.cos(h), math.sin(h), 0.0)

            if IsDisabledControlPressed(0, 32) then pos = pos + fwd * speed end   -- W
            if IsDisabledControlPressed(0, 33) then pos = pos - fwd * speed end   -- S
            if IsDisabledControlPressed(0, 34) then pos = pos - right * speed end -- A
            if IsDisabledControlPressed(0, 35) then pos = pos + right * speed end -- D
            if IsDisabledControlPressed(0, 38) then pos = pos + vec3(0, 0, speed) end -- E
            if IsDisabledControlPressed(0, 44) then pos = pos - vec3(0, 0, speed) end -- Q
            if IsDisabledControlJustPressed(0, 241) then fov = math.max(10.0, fov - 2.0) end
            if IsDisabledControlJustPressed(0, 242) then fov = math.min(120.0, fov + 2.0) end

            SetCamCoord(cam, pos.x, pos.y, pos.z)
            SetCamRot(cam, rx, 0.0, rz, 2)
            SetCamFov(cam, fov)
            SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)

            if IsDisabledControlJustPressed(0, 191) then -- Enter
                result = { x = pos.x, y = pos.y, z = pos.z, rx = rx, ry = 0.0, rz = rz, fov = fov }
                break
            elseif IsDisabledControlJustPressed(0, 194) then -- Backspace
                break
            end
            Wait(0)
        end

        editor.freecam = false
        SceneUtil.destroyCam(cam)
        ClearFocus()
        SceneUtil.clearEnvironment()
        if editor.open then
            SetNuiFocus(true, true)
            SendNUIMessage({ action = 'editorFreecam', active = false, camera = result, target = data.target })
        end
    end)
end)

RegisterNUICallback('editor:save', function(data, cb)
    cb('ok')
    TriggerServerEvent('srp-multicharacter:server:saveScenes', {
        scenes = data.scenes, active = data.active, reset = data.reset == true,
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not editor.open then return end
    SetNuiFocus(false, false)
    clearPreview()
    if editor.previewCam then SceneUtil.destroyCam(editor.previewCam) end
    ClearFocus()
end)

-- Preview intro shots: one (data.index) or the whole sequence once
RegisterNUICallback('editor:playIntro', function(data, cb)
    cb('ok')
    if not editor.scene or editor.freecam or editor.playing then return end
    local shots = SceneUtil.introFor(editor.scene)
    local index = tonumber(data.index)
    if index then shots = { shots[index] } end
    if #shots == 0 then return end

    stopPreviewCam()
    editor.playing = true
    SendNUIMessage({ action = 'editorPlaying', active = true })
    SceneUtil.setEnvironment(editor.scene)

    CreateThread(function()
        local cam
        for _, shot in ipairs(shots) do
            if not editor.playing then break end
            cam = SceneUtil.playShot(shot, cam)
            SetFocusPosAndVel(shot.to.x, shot.to.y, shot.to.z, 0.0, 0.0, 0.0)
            local done = GetGameTimer() + (shot.duration or 6000)
            while GetGameTimer() < done and editor.playing do
                HideHudAndRadarThisFrame()
                if IsControlJustPressed(0, 194) or IsDisabledControlJustPressed(0, 200) then editor.playing = false end
                Wait(0)
            end
        end
        editor.playing = false
        SceneUtil.destroyCam(cam)
        ClearFocus()
        SceneUtil.clearEnvironment()
        SendNUIMessage({ action = 'editorPlaying', active = false })
    end)
end)

RegisterNUICallback('editor:stopIntro', function(_, cb)
    cb('ok')
    editor.playing = false
end)

RegisterNUICallback('editor:autoIntro', function(_, cb)
    cb(editor.scene and SceneUtil.autoIntro(editor.scene) or false)
end)
