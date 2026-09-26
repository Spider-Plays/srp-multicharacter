local RESOURCE = GetCurrentResourceName()
local SAVE_FILE = 'data/scenes.json'

local data = { active = Config.ActiveScene, scenes = {} }

local function round(n) return math.floor(n * 100 + 0.5) / 100 end

---------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------

local function identifiers(src)
    return GetPlayerIdentifierByType(src, 'license2'), GetPlayerIdentifierByType(src, 'license')
end

-- Prefer qbx_core's own slot config so both stay in sync
local qbxConfig
do
    local ok, cfg = pcall(lib.load, '@qbx_core.config.server')
    qbxConfig = ok and type(cfg) == 'table' and cfg.characters or nil
end

local function allowedSlots(license2, license)
    local per = qbxConfig and qbxConfig.playersNumberOfCharacters or {}
    return Config.PlayerSlots[license2] or Config.PlayerSlots[license]
        or per[license2] or per[license]
        or qbxConfig and qbxConfig.defaultNumberOfCharacters
        or Config.DefaultSlots
end

local function decode(v)
    if type(v) ~= 'string' then return v end
    local ok, out = pcall(json.decode, v)
    return ok and out or nil
end

local function ownsCharacter(src, citizenid)
    local license2, license = identifiers(src)
    return MySQL.scalar.await('SELECT 1 FROM players WHERE citizenid = ? AND (license = ? OR license = ?)',
        { citizenid, license2 or '', license or '' }) ~= nil
end

lib.callback.register('srp-multicharacter:server:getCharacters', function(source)
    local license2, license = identifiers(source)
    local rows = MySQL.query.await(
        'SELECT citizenid, cid, charinfo, money, job, position FROM players WHERE license = ? OR license = ? ORDER BY cid',
        { license2 or '', license or '' }) or {}

    local list = {}
    for i = 1, #rows do
        local r = rows[i]
        local info = decode(r.charinfo) or {}
        local money = decode(r.money) or {}
        local job = decode(r.job) or {}
        local skinRow = MySQL.single.await('SELECT skin, model FROM playerskins WHERE citizenid = ? AND active = 1', { r.citizenid })

        list[i] = {
            citizenid = r.citizenid,
            cid = r.cid,
            firstname = info.firstname or '',
            lastname = info.lastname or '',
            gender = tonumber(info.gender) or 0,
            birthdate = info.birthdate,
            nationality = info.nationality,
            cash = money.cash or 0,
            bank = money.bank or 0,
            job = job.label or 'Unemployed',
            grade = type(job.grade) == 'table' and job.grade.name or nil,
            onduty = job.onduty,
            position = decode(r.position),
            skin = skinRow and decode(skinRow.skin),
            model = skinRow and skinRow.model,
        }
    end

    return list, allowedSlots(license2, license)
end)

lib.callback.register('srp-multicharacter:server:deleteCharacter', function(source, citizenid)
    if not Config.EnableDelete or type(citizenid) ~= 'string' then return false end
    if not ownsCharacter(source, citizenid) then return false end

    -- Ownership is checked above, so ForceDelete is a safe fallback
    local ok = pcall(function() exports.qbx_core:DeleteCharacter(source, citizenid) end)
    if not ok then ok = pcall(function() exports.qbx_core:ForceDeleteCharacter(citizenid) end) end

    if ok then lib.print.info(('%s deleted character %s'):format(GetPlayerName(source), citizenid)) end
    return ok
end)

-- Isolate players while they're in the selector so scenes don't overlap
RegisterNetEvent('srp-multicharacter:server:enter', function()
    SetPlayerRoutingBucket(source, 10000 + source)
end)

RegisterNetEvent('srp-multicharacter:server:leave', function()
    SetPlayerRoutingBucket(source, 0)
end)

---------------------------------------------------------------------
-- Scenes + in-game configurator
---------------------------------------------------------------------

local function num(v, fallback, min, max)
    v = tonumber(v)
    if not v or v ~= v then return fallback end
    if min and v < min then v = min end
    if max and v > max then v = max end
    return round(v)
end

local function cleanText(v, max, fallback)
    if type(v) ~= 'string' then return fallback end
    v = v:gsub('[%c<>]', ''):match('^%s*(.-)%s*$')
    if v == '' then return fallback end
    return v:sub(1, max)
end

local function token(v, pattern, max)
    if type(v) == 'string' and #v <= max and v:match(pattern) then return v end
end

local function cleanAnim(a)
    if type(a) ~= 'table' then return nil end
    if a.preset then
        local id = token(a.preset, '^[%w_%-]+$', 40)
        return id and { preset = id }
    end
    if a.scenario then
        local s = token(a.scenario, '^[%w_]+$', 64)
        return s and { scenario = s }
    end
    local dict = token(a.dict, '^[%w_@%-%.%^]+$', 128)
    local clip = token(a.clip, '^[%w_@%-%.%^]+$', 128)
    if dict and clip then
        return { dict = dict, clip = clip, flag = math.floor(num(a.flag, 1, 0, 1023)) }
    end
end

local function cleanCoords(c)
    if type(c) ~= 'table' then return nil end
    local x, y, z = num(c.x, nil, -20000, 20000), num(c.y, nil, -20000, 20000), num(c.z, nil, -500, 3000)
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z, w = num(c.w, 0.0, 0, 360) }
end

local function cleanCamera(c)
    local p = cleanCoords(c)
    if not p then return nil end
    return {
        x = p.x, y = p.y, z = p.z,
        rx = num(c.rx, 0.0, -90, 90), ry = 0.0, rz = num(c.rz, 0.0, -360, 360),
        fov = num(c.fov, 50.0, 10, 120),
    }
end

local function cleanIntro(list)
    if type(list) ~= 'table' then return nil end
    local shots = {}
    for i = 1, math.min(#list, 8) do
        local s = list[i]
        local from, to = type(s) == 'table' and cleanCamera(s.from), type(s) == 'table' and cleanCamera(s.to)
        if from and to then
            shots[#shots + 1] = { from = from, to = to, duration = math.floor(num(s.duration, 6000, 1500, 30000)) }
        end
    end
    return #shots > 0 and shots or nil
end

local function cleanScene(s, index)
    if type(s) ~= 'table' then return nil end
    local slots = {}
    if type(s.slots) == 'table' then
        for i = 1, math.min(#s.slots, 12) do
            local slot = s.slots[i]
            local coords = type(slot) == 'table' and cleanCoords(slot.coords)
            if coords then
                slots[#slots + 1] = { coords = coords, anim = cleanAnim(slot.anim), camera = cleanCamera(slot.camera) }
            end
        end
    end
    local weather = token(s.weather, '^[%u]+$', 20)
    return {
        id = token(s.id, '^[%w_%-]+$', 40) or ('scene_' .. index),
        label = cleanText(s.label, 40, 'Scene ' .. index),
        weather = weather,
        time = type(s.time) == 'table' and {
            hour = math.floor(num(s.time.hour, 12, 0, 23)),
            minute = math.floor(num(s.time.minute, 0, 0, 59)),
        } or nil,
        camera = cleanCamera(s.camera),
        intro = cleanIntro(s.intro),
        slots = slots,
    }
end

-- Config uses vec4s; normalise to plain tables so they serialize
local function fromConfig()
    local scenes = {}
    for i, s in ipairs(Config.Scenes) do
        local copy = lib.table.deepclone(s)
        for _, slot in ipairs(copy.slots or {}) do
            local c = slot.coords
            slot.coords = { x = c.x, y = c.y, z = c.z, w = c.w }
        end
        scenes[i] = cleanScene(copy, i)
    end
    return { active = Config.ActiveScene, scenes = scenes }
end

local function load()
    local raw = LoadResourceFile(RESOURCE, SAVE_FILE)
    local saved = raw and json.decode(raw)
    data = type(saved) == 'table' and type(saved.scenes) == 'table' and saved or fromConfig()
end

local function save()
    SaveResourceFile(RESOURCE, SAVE_FILE, json.encode(data, { indent = true }), -1)
    TriggerClientEvent('srp-multicharacter:client:syncScenes', -1, data)
end

local function isAdmin(src)
    return IsPlayerAceAllowed(src, 'command.' .. Config.EditorCommand)
end

lib.callback.register('srp-multicharacter:server:getScenes', function()
    return data
end)

lib.addCommand(Config.EditorCommand, {
    help = 'Open the character scene editor',
    restricted = Config.EditorGroup,
}, function(source)
    TriggerClientEvent('srp-multicharacter:client:openEditor', source, data)
end)

RegisterNetEvent('srp-multicharacter:server:saveScenes', function(payload)
    local src = source
    if not isAdmin(src) or type(payload) ~= 'table' then return end

    if payload.reset then
        data = fromConfig()
    else
        if type(payload.scenes) ~= 'table' then return end
        local scenes, seen = {}, {}
        for i = 1, math.min(#payload.scenes, 30) do
            local s = cleanScene(payload.scenes[i], i)
            if s and not seen[s.id] then
                seen[s.id] = true
                scenes[#scenes + 1] = s
            end
        end
        if #scenes == 0 then return end
        local active = token(payload.active, '^[%w_%-]+$', 40)
        data = { active = active and seen[active] and active or scenes[1].id, scenes = scenes }
    end

    save()
    lib.print.info(('%s saved character scenes (%d scenes, active %s)'):format(GetPlayerName(src), #data.scenes, data.active))
end)

load()
