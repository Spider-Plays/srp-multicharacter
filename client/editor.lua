local editor = {
    open = false,
    scene = nil,      -- draft of the scene being edited (from the NUI)
    peds = {},        -- [slot index] = preview ped
    anims = {},       -- [slot index] = json of the anim last played
    selected = nil,
    viewCam = nil,    -- live scene camera while the panel is open
    isolate = false,  -- preview hides the panel and frames the selected slot
    freecam = false,
    released = false, -- admin is walking; gameplay camera is back
    playing = false,
    returnPos = nil,
}

local function animsForNui()
    local out = {}
    for i, a in ipairs(Config.Animations) do
        out[i] = { id = a.id, label = a.label, kind = a.scenario and 'scenario' or 'anim' }
    end
    return out
end

-- Placeholder peds, not clones of the admin, so every slot reads as an empty position
local function makePreviewPed(coords)
    local ped = SceneUtil.createPed(`mp_m_freemode_01`, coords)
    SetEntityAlpha(ped, Config.EmptyAlpha, false)
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

    local overrides = {}
    for i in pairs(editor.peds) do
        overrides[i] = i == editor.selected and Config.EmptyAlphaSelected or Config.EmptyAlpha
    end
    SceneUtil.ghost(editor.peds, nil, overrides)
end

local function destroyViewCam()
    if editor.viewCam then
        SceneUtil.destroyCam(editor.viewCam)
        editor.viewCam = nil
    end
    if IsNewLoadSceneActive() then NewLoadSceneStop() end
    SceneUtil.clearEnvironment()
    ClearFocus()
end

local function desiredView()
    local scene = editor.scene
    if not scene then return end
    local slot = editor.selected and scene.slots[editor.selected]
    if editor.isolate and slot and slot.camera then
        local custom = SceneUtil.normalizeCam(slot.camera)
        if custom then return custom end
    end
    if editor.isolate then
        local ped = editor.selected and editor.peds[editor.selected]
        if ped and DoesEntityExist(ped) then
            return SceneUtil.focusOnPed(ped, SceneUtil.cameraFor(scene))
        end
    end
    return SceneUtil.cameraFor(scene)
end

-- Swap the editor camera without unloading the interior. ClearFocus here crashes
-- inside MLOs such as the Arcadius office.
local function dropViewCam()
    if not editor.viewCam then return end
    SceneUtil.destroyCam(editor.viewCam, true)
    editor.viewCam = nil
end

local function applyCam(cam, c)
    c = SceneUtil.normalizeCam(c)
    if not c or not cam or not DoesCamExist(cam) then return false end
    SetCamCoord(cam, c.x, c.y, c.z)
    SetCamRot(cam, c.rx, c.ry, c.rz, 2)
    SetCamFov(cam, c.fov)
    SetFocusPosAndVel(c.x, c.y, c.z, 0.0, 0.0, 0.0)
    return true
end

-- What the view camera depends on. Slot coords are deliberately left out: the auto
-- camera is derived from them, and re-framing on every nudge makes the view jump
-- while the admin is lining a ped up.
local function viewKey()
    local scene = editor.scene
    local slot = editor.isolate and editor.selected and scene.slots[editor.selected]
    return json.encode({
        scene.id, scene.camera or false, editor.isolate,
        editor.isolate and editor.selected or false, slot and slot.camera or false,
    })
end

-- Keep a scripted camera on the scene so slot peds stay in view while editing
local function ensureViewCam(force)
    if not editor.open or editor.freecam or editor.playing or editor.released then return end
    if not editor.scene then return end
    SceneUtil.setEnvironment(editor.scene)

    local key = viewKey()
    local alive = editor.viewCam and DoesCamExist(editor.viewCam)
    if alive and not force and key == editor.viewKey then return end

    local c = desiredView()
    if not c then return end
    editor.viewKey = key
    if not alive then
        SceneUtil.prepareArea(editor.scene)
        editor.viewCam = SceneUtil.createCam(c)
        if not editor.viewCam then
            editor.viewKey = nil
            RenderScriptCams(false, false, 0, true, true)
        end
    else
        applyCam(editor.viewCam, c)
    end
end

-- Re-frame the view on demand (e.g. after moving slots with an auto camera)
RegisterNUICallback('editor:reframe', function(_, cb)
    cb('ok')
    ensureViewCam(true)
end)

-- Yaw of whatever is on screen, so keyboard nudges move slots relative to the view
RegisterNUICallback('editor:viewYaw', function(_, cb)
    cb(GetFinalRenderedCamRot(2).z)
end)

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
    editor.isolate = false
    editor.released = false
    editor.playing = false
    destroyViewCam()
    clearPreview()
    editor.scene = nil
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'closeEditor' })
end

-- Chevron and facing line on every slot; the selected one is brighter
local function markerLoop()
    CreateThread(function()
        while editor.open do
            local scene = editor.scene
            if scene and not editor.freecam then
                for i, slot in ipairs(scene.slots) do
                    local c = slot.coords
                    local on = i == editor.selected
                    local alpha = on and 220 or 110
                    local scale = on and 0.28 or 0.16
                    DrawMarker(2, c.x, c.y, c.z + 1.15, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, scale, scale, scale * 0.75, 216, 179, 106, alpha, true, true, 2, false, nil, nil, false)
                    local h = math.rad(c.w or 0.0)
                    local fx, fy = -math.sin(h), math.cos(h)
                    DrawLine(c.x, c.y, c.z - 0.95, c.x + fx * (on and 0.9 or 0.55), c.y + fy * (on and 0.9 or 0.55), c.z - 0.95, 216, 179, 106, alpha)
                end
            end
            Wait(0)
        end
    end)
end

local function sceneById(scenes, id)
    for _, s in ipairs(scenes or {}) do
        if s.id == id then return s end
    end
    return scenes and scenes[1]
end

RegisterNetEvent('srp-multicharacter:client:openEditor', function(data)
    if editor.open then return end
    if exports[GetCurrentResourceName()]:IsSelectorOpen() then return end
    Scenes = data
    editor.open = true
    editor.returnPos = nil
    editor.released = false
    editor.isolate = false
    editor.scene = sceneById(data.scenes, data.active)
    editor.selected = editor.scene and editor.scene.slots[1] and 1 or nil
    applyDraft()
    ensureViewCam()
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'openEditor',
        scenes = data.scenes,
        active = data.active,
        animations = animsForNui(),
        weathers = Config.Weathers,
    })
    markerLoop()
    SceneUtil.track(function() return editor.open end, function()
        if editor.freecam or editor.playing then return {} end
        return trackItems()
    end, 'editorPositions')
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
    ensureViewCam()
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
    editor.isolate = data.active and true or false
    editor.released = false
    ensureViewCam()
    SendNUIMessage({ action = 'editorPreview', active = editor.isolate })
end)

RegisterNUICallback('editor:slotCamera', function(data, cb)
    local i = tonumber(data.index)
    local ped = i and editor.peds[i]
    local scene = editor.scene
    if not scene or not ped or not DoesEntityExist(ped) then return cb(false) end
    cb(SceneUtil.focusOnPed(ped, SceneUtil.cameraFor(scene)))
end)

-- Walk mode, same as srp-spawn: mouse and controls go back to the game so the
-- admin can walk to a spot; E returns to the editor.
local walkControls = false

local function stopWalk()
    if not editor.released then return end
    editor.released = false
end

local function startWalk()
    editor.released = true
    editor.isolate = false
    destroyViewCam()
    SendNUIMessage({ action = 'editorPreview', active = false })
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    if walkControls then return end
    walkControls = true
    CreateThread(function()
        while editor.open and editor.released and not editor.freecam do
            if IsControlJustReleased(0, 38) then -- E
                editor.released = false
            end
            Wait(0)
        end
        walkControls = false
        if editor.open and not editor.freecam and not editor.playing then
            ensureViewCam(true)
            SetNuiFocus(true, true)
            SendNUIMessage({ action = 'editorFocus' })
        end
    end)
end

RegisterNUICallback('editor:release', function(data, cb)
    cb('ok')
    if data.walk == false then
        stopWalk()
    else
        startWalk()
    end
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

local function axis(control)
    local v = GetControlNormal(0, control)
    if v == 0.0 then v = GetDisabledControlNormal(0, control) end
    if v ~= v then return 0.0 end
    if v > 2.0 then return 2.0 end
    if v < -2.0 then return -2.0 end
    return v
end

local function pressed(control)
    return IsControlPressed(0, control) or IsDisabledControlPressed(0, control)
end

local function justPressed(control)
    return IsControlJustPressed(0, control) or IsDisabledControlJustPressed(0, control)
end

-- Free camera: WASD move, Q/E down/up, mouse look, Shift fast, Alt slow,
-- scroll = FOV, Enter = use this view, Backspace or Esc = cancel.
-- Look controls stay enabled; movement is read after being blocked on the ped
-- so the admin does not walk while flying the camera.
RegisterNUICallback('editor:freecam', function(data, cb)
    cb('ok')
    if editor.freecam or not editor.scene then return end

    local start = type(data.start) == 'table' and SceneUtil.normalizeCam(data.start) or nil
    if not start and type(data.target) == 'string' then
        local slotIndex = tonumber(data.target:match('^slot:(%d+)$'))
        local ped = slotIndex and editor.peds[slotIndex]
        if ped and DoesEntityExist(ped) then
            start = SceneUtil.normalizeCam(SceneUtil.focusOnPed(ped, SceneUtil.cameraFor(editor.scene)))
        end
    end
    start = start or SceneUtil.cameraFor(editor.scene)
    if not start then return end

    editor.freecam = true
    editor.released = false
    editor.isolate = false
    dropViewCam()
    SendNUIMessage({ action = 'editorPreview', active = false })
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'editorFreecam', active = true })

    local pos = vec3(start.x, start.y, start.z)
    local rx, rz, fov = start.rx, start.rz, start.fov
    local anchor = SceneUtil.center(editor.scene.slots)
    local cam = SceneUtil.createCam(start)
    if not cam then
        editor.freecam = false
        ensureViewCam()
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'editorFreecam', active = false })
        return
    end
    SceneUtil.setEnvironment(editor.scene)

    CreateThread(function()
        local result
        local block = { 19, 21, 22, 24, 25, 30, 31, 32, 33, 34, 35, 36, 37, 38, 44, 45, 140, 141, 142, 199, 200, 257, 263, 264 }
        while editor.freecam and DoesCamExist(cam) do
            HideHudAndRadarThisFrame()
            for i = 1, #block do DisableControlAction(0, block[i], true) end

            local mx, my = axis(1), axis(2)
            rz = (rz - mx * 6.0) % 360.0
            rx = math.max(-89.0, math.min(89.0, rx - my * 6.0))

            local dt = GetFrameTime()
            if dt > 0.05 then dt = 0.05 end
            local meters = (pressed(21) and 16.0 or pressed(19) and 1.4 or 5.0) * dt
            local h, p = math.rad(rz), math.rad(rx)
            local cosP = math.cos(p)
            local fx, fy, fz = -math.sin(h) * cosP, math.cos(h) * cosP, math.sin(p)
            local rxr, ryr = math.cos(h), math.sin(h)
            local forward, strafe, vertical = 0.0, 0.0, 0.0
            if pressed(32) then forward = 1.0 end
            if pressed(33) then forward = forward - 1.0 end
            if pressed(35) then strafe = 1.0 end
            if pressed(34) then strafe = strafe - 1.0 end
            if pressed(38) then vertical = 1.0 end
            if pressed(44) then vertical = vertical - 1.0 end
            pos = vec3(
                pos.x + (fx * forward + rxr * strafe) * meters,
                pos.y + (fy * forward + ryr * strafe) * meters,
                pos.z + (fz * forward + vertical) * meters
            )

            local ox, oy, oz = pos.x - anchor.x, pos.y - anchor.y, pos.z - anchor.z
            local reach = math.sqrt(ox * ox + oy * oy + oz * oz)
            if reach > 80.0 then
                local scale = 80.0 / reach
                pos = vec3(anchor.x + ox * scale, anchor.y + oy * scale, anchor.z + oz * scale)
            end

            if justPressed(241) or justPressed(15) then fov = math.max(10.0, fov - 2.0) end
            if justPressed(242) or justPressed(14) then fov = math.min(120.0, fov + 2.0) end

            SetCamCoord(cam, pos.x, pos.y, pos.z)
            SetCamRot(cam, rx, 0.0, rz, 2)
            SetCamFov(cam, fov)
            SetFocusPosAndVel(pos.x, pos.y, pos.z, 0.0, 0.0, 0.0)

            if justPressed(191) or justPressed(201) then
                result = { x = pos.x, y = pos.y, z = pos.z, rx = rx, ry = 0.0, rz = rz, fov = fov }
                break
            elseif justPressed(194) or justPressed(202) or justPressed(200) then
                break
            end
            Wait(0)
        end

        editor.freecam = false
        SceneUtil.destroyCam(cam, true)
        if editor.open then
            ensureViewCam()
            SetNuiFocus(true, true)
            SendNUIMessage({ action = 'editorFreecam', active = false, camera = result, target = data.target })
        else
            RenderScriptCams(false, false, 0, true, true)
            ClearFocus()
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
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    clearPreview()
    destroyViewCam()
end)

-- Preview intro shots: one (data.index) or the whole sequence once
RegisterNUICallback('editor:playIntro', function(data, cb)
    cb('ok')
    if not editor.scene or editor.freecam or editor.playing then return end
    local shots = SceneUtil.introFor(editor.scene)
    local index = tonumber(data.index)
    if index then shots = { shots[index] } end
    if #shots == 0 then return end

    editor.playing = true
    editor.released = false
    dropViewCam()
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
        if editor.open then ensureViewCam() end
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
