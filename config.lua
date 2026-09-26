Config = {}

-- IMPORTANT: set `characters.useExternalCharacters = true` in qbx_core/config/client.lua
-- so qbx_core's built-in selector stays out of the way.

-- Clothing resource used to dress the preview peds (must export setPedAppearance)
Config.Appearance = 'illenium-appearance' -- or 'fivem-appearance'

-- Character slots. qbx_core's own server config (characters.defaultNumberOfCharacters /
-- playersNumberOfCharacters) is used when it can be read; these are the fallback.
Config.DefaultSlots = 3
Config.PlayerSlots = {
    -- ['license2:abc123'] = 5,
}

Config.EnableDelete = true

-- Alpha for characters that aren't selected (GTA passive mode uses ~150)
Config.GhostAlpha = 140

-- Scene coords are stored as ped coords (what GetEntityCoords returns, ~1m above the feet).
-- CreatePed places the feet at z, so we drop the ped by this much.
Config.PedZOffset = -1.0

-- Intro: cinematic drifting shots of the scene before character selection.
-- Shots are set per scene in /charconfig ("Intro shots"); scenes without any get auto shots.
Config.Intro = {
    enabled = true,
    title = 'Spider Roleplay',
    subtitle = 'Welcome Back',
    prompt = 'Press ENTER to continue',
    fade = 450,         -- ms fade between shots
}

-- Cinematic focus: the camera glides from the scene shot to frame the selected character
Config.Focus = {
    enabled = true,
    duration = 1600,   -- ms per transition (eased in/out)
    distance = 2.6,    -- metres from the character, along the scene camera's direction
    height = 0.05,     -- camera height relative to the head
    fov = 38.0,
    dof = true,        -- shallow depth of field on the focused character
}

-- Height of the floating info card above the ped's head bone
Config.CardHeight = 0.35

-- Existing characters: hand off to qbx_apartments / qbx_spawn (srp-spawn) when running,
-- otherwise spawn at their last location.
Config.UseSpawnSelector = true

-- New characters spawn here and get the clothing creator
Config.NewCharacter = {
    coords = vec4(-1035.71, -2731.87, 13.76, 0.0),
    openClothing = true,
}

-- In-game configurator: /charconfig
-- Scenes edited in-game are saved to data/scenes.json and override Config.Scenes below.
-- Delete that file (or "Reset to defaults" in the editor) to go back to these.
Config.EditorCommand = 'charconfig'
Config.EditorGroup = 'group.admin'

---------------------------------------------------------------------
-- Scenes
--   camera = nil  -> auto-framed from the slots. Use the editor's free camera to set one.
--   slots[n].anim = { preset = '<id from Config.Animations>' }
--                 | { dict = '', clip = '', flag = 1 }
--                 | { scenario = 'WORLD_HUMAN_...' }
---------------------------------------------------------------------
Config.ActiveScene = 'arcadius'

Config.Scenes = {
    {
        id = 'arcadius',
        label = 'Arcadius Office',
        weather = 'EXTRASUNNY',
        time = { hour = 19, minute = 30 },
        camera = nil,
        slots = {
            { coords = vec4(-136.85, -641.48, 167.82, 149.54), anim = { preset = 'crossarms' } },
            { coords = vec4(-126.07, -641.27, 167.82, 111.23), anim = { preset = 'phone' } },
            { coords = vec4(-125.86, -632.94, 168.52, 190.29), anim = { preset = 'sitchair' } },
        },
    },
}

---------------------------------------------------------------------
-- Animation presets shown in the editor. Any native dict/clip or scenario works.
---------------------------------------------------------------------
Config.Animations = {
    { id = 'idle',       label = 'Idle',                 dict = 'anim@heists@heist_corona@team_idles@male_a', clip = 'idle', flag = 1 },
    { id = 'crossarms',  label = 'Arms Crossed',         dict = 'amb@world_human_hang_out_street@female_arms_crossed@idle_a', clip = 'idle_a', flag = 1 },
    { id = 'crossarms2', label = 'Arms Crossed (Male)',  dict = 'amb@world_human_hang_out_street@male_c@idle_a', clip = 'idle_b', flag = 1 },
    { id = 'boss',       label = 'Boss Stance',          dict = 'anim@heists@heist_corona@single_team', clip = 'single_team_loop_boss', flag = 1 },
    { id = 'think',      label = 'Thinking',             dict = 'misscarsteal4@aliens', clip = 'rehearsal_base_idle_director', flag = 1 },
    { id = 'wait',       label = 'Waiting',              dict = 'random@shop_tattoo', clip = '_idle_a', flag = 1 },
    { id = 'lean',       label = 'Lean on Wall',         dict = 'amb@world_human_leaning@female@wall@back@hand_up@idle_a', clip = 'idle_a', flag = 1 },
    { id = 'sitchair',   label = 'Sit (Chair)',          dict = 'timetable@ron@ig_5_p3', clip = 'ig_5_p3_base', flag = 1 },
    { id = 'sitcouch',   label = 'Sit (Couch)',          dict = 'timetable@ron@ig_3_couch', clip = 'base', flag = 1 },
    { id = 'sitledge',   label = 'Sit (Ledge)',          dict = 'rcm_barry3', clip = 'barry_3_sit_loop', flag = 1 },
    { id = 'sitphone',   label = 'Sit (Phone)',          dict = 'anim@amb@business@bgen@bgen_no_work@', clip = 'sit_phone_phoneputdown_idle_nowork', flag = 1 },
    { id = 'phone',      label = 'On Phone',             scenario = 'WORLD_HUMAN_STAND_MOBILE' },
    { id = 'coffee',     label = 'Coffee',               scenario = 'WORLD_HUMAN_AA_COFFEE' },
    { id = 'smoke',      label = 'Smoking',              scenario = 'WORLD_HUMAN_SMOKING' },
    { id = 'drink',      label = 'Drinking',             scenario = 'WORLD_HUMAN_DRINKING' },
    { id = 'leanscen',   label = 'Leaning (Scenario)',   scenario = 'WORLD_HUMAN_LEANING' },
    { id = 'clipboard',  label = 'Clipboard',            scenario = 'WORLD_HUMAN_CLIPBOARD' },
    { id = 'guard',      label = 'Guard',                scenario = 'WORLD_HUMAN_GUARD_STAND' },
    { id = 'party',      label = 'Partying',             scenario = 'WORLD_HUMAN_PARTYING' },
    { id = 'weights',    label = 'Free Weights',         scenario = 'WORLD_HUMAN_MUSCLE_FREE_WEIGHTS' },
    { id = 'picnic',     label = 'Sit (Ground)',         scenario = 'WORLD_HUMAN_PICNIC' },
}

Config.Weathers = {
    'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'SMOG', 'FOGGY', 'RAIN', 'THUNDER', 'CLEARING', 'SNOWLIGHT', 'XMAS', 'HALLOWEEN',
}
