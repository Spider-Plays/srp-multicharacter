-- Shared helpers for the selector (main.lua) and the configurator (editor.lua)
SceneUtil = {}

Scenes = { active = Config.ActiveScene, scenes = {} }

function SceneUtil.fetch()
    Scenes = lib.callback.await('srp-multicharacter:server:getScenes', false) or Scenes
    return Scenes
end

function SceneUtil.find(id)
    for i, s in ipairs(Scenes.scenes) do
        if s.id == id then return s, i end
    end
end

function SceneUtil.active()
    return SceneUtil.find(Scenes.active) or Scenes.scenes[1]
end

---------------------------------------------------------------------
-- Peds + animations
---------------------------------------------------------------------

function SceneUtil.resolveAnim(anim)
    if type(anim) ~= 'table' then return nil end
    if anim.preset then
        for _, a in ipairs(Config.Animations) do
            if a.id == anim.preset then return a end
        end
        return nil
    end
    return anim
end

function SceneUtil.playAnim(ped, anim)
    if not DoesEntityExist(ped) then return end
    ClearPedTasksImmediately(ped)
    local a = SceneUtil.resolveAnim(anim)
    if not a then return end

    if a.scenario then
        TaskStartScenarioInPlace(ped, a.scenario, 0, true)
    elseif a.dict and a.clip then
        if not pcall(lib.requestAnimDict, a.dict, 5000) then
            return lib.print.warn(('anim dict "%s" failed to load'):format(a.dict))
        end
        TaskPlayAnim(ped, a.dict, a.clip, 8.0, -8.0, -1, a.flag or 1, 0.0, false, false, false)
        RemoveAnimDict(a.dict)
    end
end

function SceneUtil.applySkin(ped, skin)
    if not skin or GetResourceState(Config.Appearance) ~= 'started' then return false end
    return pcall(function() exports[Config.Appearance]:setPedAppearance(ped, skin) end)
end

function SceneUtil.placePed(ped, c)
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z + Config.PedZOffset, false, false, false)
    SetEntityHeading(ped, c.w or 0.0)
end

---@param model number|string
---@param coords table {x,y,z,w}
---@param skin? table appearance data
function SceneUtil.createPed(model, coords, skin)
    model = type(model) == 'string' and (tonumber(model) or joaat(model)) or model
    if not IsModelInCdimage(model) or not pcall(lib.requestModel, model, 10000) then
        model = `mp_m_freemode_01`
        lib.requestModel(model)
    end

    local ped = CreatePed(4, model, coords.x, coords.y, coords.z + Config.PedZOffset, coords.w or 0.0, false, false)
    SetModelAsNoLongerNeeded(model)
    SceneUtil.placePed(ped, coords)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedFleeAttributes(ped, 0, false)

    if not SceneUtil.applySkin(ped, skin) then
        SetPedDefaultComponentVariation(ped)
        local model = GetEntityModel(ped)
        if model == `mp_m_freemode_01` or model == `mp_f_freemode_01` then
            SetPedHeadBlendData(ped, 21, 0, 0, 21, 0, 0, 0.5, 0.5, 0.0, false)
        end
    end
    return ped
end

function SceneUtil.deletePeds(peds)
    for k, ped in pairs(peds) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
        peds[k] = nil
    end
end

-- Non-selected peds are ghosted like passive mode; alpha eases toward its target
local fades, fading = {}, false

function SceneUtil.ghost(peds, selected, overrides)
    for k, ped in pairs(peds) do
        fades[ped] = (overrides and overrides[k])
            or ((selected == nil or k == selected) and 255 or Config.GhostAlpha)
    end
    if fading then return end
    fading = true
    CreateThread(function()
        while next(fades) do
            for ped, target in pairs(fades) do
                if not DoesEntityExist(ped) then
                    fades[ped] = nil
                else
                    local a = GetEntityAlpha(ped)
                    a = a < target and math.min(target, a + 6) or math.max(target, a - 6)
                    if a == 255 then ResetEntityAlpha(ped) else SetEntityAlpha(ped, a, false) end
                    if a == target then fades[ped] = nil end
                end
            end
            Wait(0)
        end
        fading = false
    end)
end

---------------------------------------------------------------------
-- Camera + environment
---------------------------------------------------------------------

local function lookRotation(from, to)
    local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
    local flat = math.sqrt(dx * dx + dy * dy)
    return math.deg(math.atan(dz, flat)), math.deg(math.atan(-dx, dy))
end
SceneUtil.lookRotation = lookRotation

-- Natives crash the client if a coord or rotation is nil/NaN, so every camera
-- is reduced to plain numbers before it is handed to a native.
function SceneUtil.normalizeCam(c)
    if type(c) ~= 'table' then return nil end
    local x, y, z = tonumber(c.x), tonumber(c.y), tonumber(c.z)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z then return nil end
    local rx, ry, rz = tonumber(c.rx) or 0.0, tonumber(c.ry) or 0.0, tonumber(c.rz) or 0.0
    local fov = tonumber(c.fov) or 50.0
    if rx ~= rx or ry ~= ry or rz ~= rz or fov ~= fov then return nil end
    if rx < -89.0 then rx = -89.0 elseif rx > 89.0 then rx = 89.0 end
    if fov < 10.0 then fov = 10.0 elseif fov > 120.0 then fov = 120.0 end
    return { x = x, y = y, z = z, rx = rx, ry = ry, rz = rz, fov = fov }
end

-- Glide from whatever is on screen right now to `c`. Safe to call mid-transition:
-- we snapshot the rendered view first so rapid switching never snaps.
---@return number cam the new active cam
function SceneUtil.glide(current, c, duration, dofDistance)
    c = SceneUtil.normalizeCam(c)
    if not c then return current end
    local from = current
    if current and IsCamInterpolating(current) then
        local p, r = GetFinalRenderedCamCoord(), GetFinalRenderedCamRot(2)
        from = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', p.x, p.y, p.z, r.x, r.y, r.z, GetFinalRenderedCamFov(), true, 2)
        SetCamActive(from, true)
        RenderScriptCams(true, false, 0, true, true)
        if DoesCamExist(current) then DestroyCam(current, false) end
    end

    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', c.x, c.y, c.z, c.rx, c.ry, c.rz, c.fov, false, 2)
    if not cam or cam == 0 or not DoesCamExist(cam) then return current end
    if dofDistance then
        SetCamUseShallowDofMode(cam, true)
        SetCamNearDof(cam, math.max(0.1, dofDistance - 0.9))
        SetCamFarDof(cam, dofDistance + 1.4)
        SetCamDofStrength(cam, 0.9)
    end
    SetCamActiveWithInterp(cam, from, duration, 1, 1) -- ease in/out on position and rotation

    SetTimeout(duration + 200, function()
        if from and DoesCamExist(from) and not IsCamActive(from) then DestroyCam(from, false) end
    end)
    return cam
end

function SceneUtil.center(slots)
    local x, y, z, n = 0.0, 0.0, 0.0, #slots
    if n == 0 then
        local p = GetEntityCoords(PlayerPedId())
        return vec3(p.x, p.y, p.z)
    end
    for _, s in ipairs(slots) do
        x, y, z = x + s.coords.x, y + s.coords.y, z + s.coords.z
    end
    return vec3(x / n, y / n, z / n)
end

-- Frame the slots from the side they are (on average) facing
function SceneUtil.autoCamera(slots)
    local c = SceneUtil.center(slots)
    local fx, fy, spread = 0.0, 0.0, 0.0
    for _, s in ipairs(slots) do
        local h = math.rad(s.coords.w or 0.0)
        fx, fy = fx - math.sin(h), fy + math.cos(h)
        spread = math.max(spread, #(vec2(s.coords.x, s.coords.y) - vec2(c.x, c.y)))
    end
    local len = math.sqrt(fx * fx + fy * fy)
    if len < 0.01 then fx, fy, len = 0.0, 1.0, 1.0 end

    local dist = math.max(4.0, spread * 1.3 + 2.5)
    local pos = vec3(c.x + fx / len * dist, c.y + fy / len * dist, c.z + 0.5)
    local rx, rz = lookRotation(pos, c)
    return { x = pos.x, y = pos.y, z = pos.z, rx = rx, ry = 0.0, rz = rz, fov = 50.0 }
end

-- Three drifting shots around the scene: wide orbit, low push-in, high orbit
function SceneUtil.autoIntro(scene)
    local c = SceneUtil.center(scene.slots)
    local wide = SceneUtil.cameraFor(scene)
    local base = math.atan(wide.y - c.y, wide.x - c.x)

    local function at(angle, radius, height, fov)
        local pos = vec3(c.x + math.cos(angle) * radius, c.y + math.sin(angle) * radius, c.z + height)
        local rx, rz = lookRotation(pos, c)
        return { x = pos.x, y = pos.y, z = pos.z, rx = rx, ry = 0.0, rz = rz, fov = fov }
    end

    local r = math.max(5.0, #(vec2(wide.x, wide.y) - vec2(c.x, c.y)))
    return {
        { from = at(base - 0.5, r * 1.1, 2.2, 55.0), to = at(base + 0.1, r * 1.1, 1.8, 55.0), duration = 7000 },
        { from = at(base + 0.35, r * 1.2, 0.1, 42.0), to = at(base + 0.3, r * 0.7, 0.3, 42.0), duration = 6500 },
        { from = at(base + 0.9, r * 0.9, 3.0, 60.0), to = at(base + 0.5, r * 0.9, 2.6, 60.0), duration = 7000 },
    }
end

function SceneUtil.introFor(scene)
    return (scene.intro and #scene.intro > 0) and scene.intro or SceneUtil.autoIntro(scene)
end

-- Cut to `shot.from` and drift to `shot.to`. Returns the drifting cam.
function SceneUtil.playShot(shot, previous)
    local f, t = SceneUtil.normalizeCam(shot.from), SceneUtil.normalizeCam(shot.to)
    if not f or not t then return previous end
    local from = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', f.x, f.y, f.z, f.rx, f.ry, f.rz, f.fov, true, 2)
    if not from or from == 0 or not DoesCamExist(from) then return previous end
    RenderScriptCams(true, false, 0, true, true)
    if previous and previous ~= from and DoesCamExist(previous) then DestroyCam(previous, false) end

    local to = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', t.x, t.y, t.z, t.rx, t.ry, t.rz, t.fov, false, 2)
    if not to or to == 0 or not DoesCamExist(to) then return from end
    SetCamActiveWithInterp(to, from, shot.duration or 6000, 1, 1)
    SetTimeout((shot.duration or 6000) + 200, function()
        if DoesCamExist(from) then DestroyCam(from, false) end
    end)
    return to
end

-- Close-up of one ped, shot from the wide camera's side
function SceneUtil.focusOnPed(ped, wide)
    if not ped or not DoesEntityExist(ped) then return nil end
    wide = SceneUtil.normalizeCam(wide) or SceneUtil.normalizeCam(SceneUtil.autoCamera({})) or { x = 0.0, y = 1.0, z = 0.0, rx = 0.0, ry = 0.0, rz = 0.0, fov = 50.0 }
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    if not head then return nil end
    local F = Config.Focus
    local target = vec3(head.x, head.y, head.z - 0.2)
    local dx, dy = wide.x - target.x, wide.y - target.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.01 then dx, dy, len = 0.0, 1.0, 1.0 end
    dx, dy = dx / len, dy / len

    local pos = vec3(target.x + dx * F.distance, target.y + dy * F.distance, head.z + F.height)
    local rx, rz = lookRotation(pos, target)
    local dist = #(pos - target)
    return { x = pos.x, y = pos.y, z = pos.z, rx = rx, ry = 0.0, rz = rz, fov = F.fov }, dist
end

function SceneUtil.cameraFor(scene)
    return SceneUtil.normalizeCam(scene.camera) or SceneUtil.autoCamera(scene.slots)
end

-- Stream the scene around the slots without moving the player (editor view)
function SceneUtil.prepareArea(scene)
    local c = SceneUtil.center(scene.slots)
    SetFocusPosAndVel(c.x, c.y, c.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(c.x, c.y, c.z)
    local interior = GetInteriorAtCoords(c.x, c.y, c.z)
    if interior ~= 0 then PinInteriorInMemory(interior) end
    if not IsNewLoadSceneActive() then
        NewLoadSceneStartSphere(c.x, c.y, c.z, 50.0, 0)
    end
end

function SceneUtil.createCam(c)
    c = SceneUtil.normalizeCam(c)
    if not c then return nil end
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', c.x, c.y, c.z, c.rx, c.ry, c.rz, c.fov, false, 2)
    if not cam or cam == 0 or not DoesCamExist(cam) then return nil end
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
    return cam
end

function SceneUtil.destroyCam(cam, keepRendering)
    if cam and cam ~= 0 and DoesCamExist(cam) then
        SetCamActive(cam, false)
        DestroyCam(cam, false)
    end
    if not keepRendering then
        RenderScriptCams(false, false, 0, true, true)
    end
end

function SceneUtil.setEnvironment(scene)
    if scene.weather then
        SetWeatherTypeNowPersist(scene.weather)
        SetOverrideWeather(scene.weather)
    end
    if scene.time then
        NetworkOverrideClockTime(scene.time.hour, scene.time.minute, 0)
    end
end

function SceneUtil.clearEnvironment()
    ClearOverrideWeather()
    NetworkClearClockTimeOverride()
end

-- Stream the area (and any interior, e.g. the Arcadius office) before showing it
function SceneUtil.loadArea(scene, cam)
    local c = SceneUtil.center(scene.slots)
    SetFocusPosAndVel(c.x, c.y, c.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(c.x, c.y, c.z)

    local interior = GetInteriorAtCoords(c.x, c.y, c.z)
    if interior ~= 0 then
        PinInteriorInMemory(interior)
        local timeout = GetGameTimer() + 5000
        while not IsInteriorReady(interior) and GetGameTimer() < timeout do Wait(0) end
    end

    NewLoadSceneStartSphere(c.x, c.y, c.z, 30.0, 0)
    local timeout = GetGameTimer() + 5000
    while not IsNewLoadSceneLoaded() and GetGameTimer() < timeout do Wait(0) end
    NewLoadSceneStop()

    -- Park the (hidden) player at the camera so the area stays streamed
    local ped = PlayerPedId()
    SetEntityCoords(ped, cam.x, cam.y, cam.z - 1.0, false, false, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityVisible(ped, false, false)
end

---------------------------------------------------------------------
-- Screen tracking for floating NUI cards
---------------------------------------------------------------------

local HEAD_BONE = 31086

---@param isActive fun(): boolean
---@param getItems fun(): table[] list of { key, ped?, coords }
---@param action string NUI action name
function SceneUtil.track(isActive, getItems, action)
    CreateThread(function()
        local last = ''
        while isActive() do
            HideHudAndRadarThisFrame()
            local out = {}
            for _, item in ipairs(getItems()) do
                local p
                if item.ped and DoesEntityExist(item.ped) then
                    p = GetPedBoneCoords(item.ped, HEAD_BONE, 0.0, 0.0, 0.0)
                else
                    p = vec3(item.coords.x, item.coords.y, item.coords.z + 0.7)
                end
                local onScreen, sx, sy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z + Config.CardHeight)
                out[#out + 1] = {
                    key = item.key,
                    visible = onScreen,
                    x = math.floor(sx * 1000 + 0.5) / 10,
                    y = math.floor(sy * 1000 + 0.5) / 10,
                }
            end
            local encoded = json.encode(out)
            if encoded ~= last then
                last = encoded
                SendNUIMessage({ action = action, items = out })
            end
            Wait(0)
        end
        SendNUIMessage({ action = action, items = {} })
    end)
end

RegisterNetEvent('srp-multicharacter:client:syncScenes', function(data)
    Scenes = data
    TriggerEvent('srp-multicharacter:client:scenesUpdated')
end)
