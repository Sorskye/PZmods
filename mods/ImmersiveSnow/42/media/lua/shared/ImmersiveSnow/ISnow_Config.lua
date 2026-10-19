-- Immersive Snow: shared constants and sandbox access.
-- Texture layout must match tools/gen_prints.py and tools/gen_tracks.py.

ISnow = ISnow or {}

ISnow.DIRS = 16
ISnow.FEET = 2
ISnow.PRINT_SIZE = 48   -- px, square texture with the print centred
ISnow.PRINT_REACH = 12  -- px below the centre the visible print reaches on screen (10 in the PNGs)
ISnow.PRINT_VARIANTS = 3  -- textures per foot and direction, one picked at random per print
ISnow.MARKER_SIZE = 32  -- px, debug markers (tools/gen_tracks.py)
ISnow.MARKER_REACH = 16
-- Decal textures come in FADE_LEVELS copies, alpha level / FADE_LEVELS (Render3DItem draws with
-- alpha 1, see ISnow_Decals.lua); level FADE_LEVELS is full strength.
ISnow.FADE_LEVELS = 4
-- Snow carried onto clear ground (sprint_*, strack_*) has CARRIED_LEVELS alpha levels instead:
-- the level also follows the light of the square, see "lit" in ISnow_Decals.lua.
ISnow.CARRIED_LEVELS = 8

ISnow.TRACK_DIRS = 32   -- tread segments over half a turn: angle = dir * 180 / TRACK_DIRS deg
ISnow.TRACK_SIZE = 64   -- px, square texture with the segment centred
ISnow.TRACK_REACH = 17  -- px below the centre the visible segment reaches on screen (15 in the PNGs)
ISnow.TRACK_STEP = 0.4  -- world units between segment centres (texture fades are built for it)
-- Tire widths, world units; texture set = index - 1. The last is a bicycle's (BIKE_TRACK_WIDTH, the
-- set index), vehicles pick from the others (ISnow_TireTracks.lua, widthIndex).
ISnow.TRACK_WIDTHS = { 0.15, 0.22, 0.30, 0.06 }
ISnow.BIKE_TRACK_WIDTH = 3
ISnow.TRACK_VARIANTS = 3  -- textures per width and direction, one picked at random per segment
-- Bloody tire tracks (brut_* in snow, btrack_* on clear ground, tools/gen_tracks.py): one variant per
-- width and direction, TRACK_BLOOD_LEVELS levels picked by age and the blood left on the tire. Not
-- BLOOD_LEVELS (the bloody prints' 8, below): with that name the prints' value replaced this one, the
-- tire sets asked for levels 7 and 8, which have no PNG, and the freshest red track (the first two
-- tiles past the body) was not drawn, then showed up as it aged.
ISnow.TRACK_BLOOD_LEVELS = 6

-- The furrow of a body crawling through the snow instead of prints (drag_*, tools/gen_prints.py):
-- segments like the tire tracks, DRAG_STEP apart, over half a turn: angle = dir * 180 / DRAG_DIRS deg.
ISnow.DRAG_DIRS = 32
ISnow.DRAG_SIZE = 64
ISnow.DRAG_REACH = 18   -- px below the centre (16 in the PNGs)
ISnow.DRAG_STEP = 0.4   -- = TRACK_STEP: the texture fades are built for it
ISnow.DRAG_VARIANTS = 3

-- Immersion 0.5.2: barefoot prints, bloody footprints, blood on the snow
-- (ISnow_Footprints.lua, tools/gen_prints.py). Bare feet: bare_* dents (PRINT_SIZE, BARE_VARIANTS per
-- foot and direction, FADE_LEVELS) and sbare_* carried snow (as sprint_*). Blood: bprint_* / bbare_*
-- (bloody boot / bare foot, per foot and direction) and blood_* drops (BLOOD_DROP_VARIANTS), all
-- PRINT_SIZE multiply textures with BLOOD_LEVELS levels picked by strength x fade.
ISnow.BARE_VARIANTS = 2
ISnow.BLOOD_LEVELS = 8
ISnow.BLOOD_DROP_VARIANTS = 4

ISnow.TEXTURE_DIR = "media/textures/ImmersiveSnow/"

-- Vehicle snow shells (ISnow_VehicleShells.lua). Each entry is one model of the shell parts: the
-- vehicle's body mesh (or wheel mesh) drawn with the snow shader and the parameters of that
-- entry (tools/gen_vehicle_snow.py). Stage i is shown for snow level in ((i-1)/n, i/n].
ISnow.VEHICLE_SNOW_PART = "ISnowShell"
-- Snow on the wheels: one part per tyre part "Tire<x>", ISnow.VEHICLE_SNOW_WHEEL_PART .. x, with shells
-- of its wheel model, on the wheel that tyre part sits on (ISnow_VehicleShells.lua, Shells.wheels).
ISnow.VEHICLE_SNOW_WHEEL_PART = "ISnowWheel"
ISnow.VEHICLE_SNOW_WHEEL_SEEDS = 4   -- noise offsets for wheels, as WHEEL_SEEDS in gen_vehicle_snow.py
-- Snow on separate body parts (doors, hood, trunk lid, windows, roof...): one part per source part,
-- ISnow.VEHICLE_SNOW_PART_PREFIX .. source part id, with parent = the source part.
ISnow.VEHICLE_SNOW_PART_PREFIX = "ISnowPart"
-- Categories (lower case) of source parts that get snow; the rest are inside or under the vehicle.
ISnow.VEHICLE_SNOW_PART_CATEGORIES = { door = true, bodywork = true, other = true, nodisplay = true }
ISnow.VEHICLE_SNOW_BODY_SHADER = "isnow_vsb_"     -- .. variant id: body shells, see gen_vehicle_snow.py
ISnow.VEHICLE_SNOW_WHEEL_SHADER = "isnow_vsw_"    -- .. variant id .. "_" .. seed: wheel shells
-- The same with darker snow (ISnow.darkSnow; stage variants only, DARK_PREFIXES in gen_vehicle_snow.py)
ISnow.VEHICLE_SNOW_BODY_SHADER_DARK = "isnow_vsbd_"
ISnow.VEHICLE_SNOW_WHEEL_SHADER_DARK = "isnow_vswd_"
-- Body shells of vehicles without a mask texture (burnt wrecks, ISnow_VehicleShells.lua maskedByScript):
-- the s, i and c stages without the mask (NOMASK_PREFIXES in gen_vehicle_snow.py)
ISnow.VEHICLE_SNOW_BODY_SHADER_NOMASK = "isnow_vsbm_"
ISnow.VEHICLE_SNOW_BODY_SHADER_NOMASK_DARK = "isnow_vsbmd_"
-- Debug ids with their own wheel shader (WHEEL_DEBUG in gen_vehicle_snow.py); the rest use dbg_normals.
ISnow.VEHICLE_SNOW_WHEEL_DEBUG = { dbg_normals = true, dbg_view = true }
-- Stands in for the texture of a wheel model without one (all tyre).
ISnow.VEHICLE_SNOW_TYRE_TEXTURE = "ImmersiveSnow/vsnow_tyre"
-- The first model of every snow wheel part (ISnow_VehicleShells.lua): never shown in the world; the
-- game's 3D vehicle preview draws a wheel part by its first model only, and this texture is the
-- mark the snow shaders draw nothing for (previewMark in isnow_vehiclesnow.frag)
ISnow.VEHICLE_SNOW_PREVIEW_ID = "pv"
ISnow.VEHICLE_SNOW_PREVIEW_TEXTURE = "ImmersiveSnow/vsnow_preview"
-- Settled snow (the fields on top) and icing (patches, glass / rim edges) are separate models shown
-- together, with their own levels: driving blows the snow off slowly, the icing stays until a thaw.
ISnow.VEHICLE_SNOW_STAGES = { "s1", "s2", "s3", "s4", "s5", "s6" }
ISnow.VEHICLE_SNOW_ICE_STAGES = { "i1", "i2", "i3", "i4", "i5", "i6" }
-- Snow and icing in one model, both at the snow's stage: what body, pieces and wheels show (the icing
-- has the snow's level, ISnow_VehicleSnow.lua).
ISnow.VEHICLE_SNOW_BOTH_STAGES = { "c1", "c2", "c3", "c4", "c5", "c6" }
-- The icing and the one-pass stages with nothing on the glass: a vehicle whose windows were scraped
-- or brushed clean (ISnow_VehicleSnow.lua, KEY_GLASS_CLEAN), body and body pieces only.
ISnow.VEHICLE_SNOW_ICE_CLEAN_STAGES = { "n1", "n2", "n3", "n4", "n5", "n6" }
ISnow.VEHICLE_SNOW_BOTH_CLEAN_STAGES = { "b1", "b2", "b3", "b4", "b5", "b6" }
-- Frost on the glass (VehicleFrost, ISnow_VehicleSnow.lua): a third layer, drawn on the glass alone
-- (the mask's window zones), on body and body piece shells, not on wheels.
ISnow.VEHICLE_SNOW_GLASS_STAGES = { "g1", "g2", "g3", "g4", "g5", "g6" }
ISnow.VEHICLE_SNOW_DEBUG = {
    "dbg_normals", "dbg_view", "dbg_py", "dbg_pz", "dbg_nz", "dbg_ny", "dbg_px", "dbg_bias0", "dbg_bias1", "dbg_bias2",
}

function ISnow.printFile(foot, dir, variant, level)
    return "print_" .. foot .. "_" .. dir .. "_" .. variant .. "_" .. level .. ".png"
end

function ISnow.dragFile(dir, variant, level)
    return "drag_" .. dir .. "_" .. variant .. "_" .. level .. ".png"
end

function ISnow.trackFile(width, dir, variant, level)
    return "track_" .. width .. "_" .. dir .. "_" .. variant .. "_" .. level .. ".png"
end

-- Snow carried by the soles / tires onto clear ground (gen_prints.py / gen_tracks.py), same layout.
function ISnow.carriedPrintFile(foot, dir, level)
    return "sprint_" .. foot .. "_" .. dir .. "_" .. level .. ".png"
end

-- The texture variant for a new print / rut segment out of n: random with the detailed decals on,
-- else always the first, so a third of the textures load and neighbours share one.
function ISnow.decalVariant(n)
    if ISnow.opt("DetailedDecals") then return ZombRand(n) end
    return 0
end

function ISnow.carriedTrackFile(width, dir, level)
    return "strack_" .. width .. "_" .. dir .. "_" .. level .. ".png"
end

-- How strong a bloody print or tire segment is (0..1) with left of its max bloody steps / segments
-- still to go (max .. 1): full red over the first part of the way, then paler over the last
-- BLOOD_FADE_PART. Fading from the very first step left only the first metre or two clearly red.
ISnow.BLOOD_FADE_PART = 0.4
function ISnow.bloodStrength(left, max)
    max = math.max(1, max or left)
    return math.max(0, math.min(1, left / math.max(1, max * ISnow.BLOOD_FADE_PART)))
end

-- Bloody tire tracks: blood soaked into a snow rut, bloody tread on clear ground (gen_tracks.py).
function ISnow.bloodRutFile(width, dir, level)
    return "brut_" .. width .. "_" .. dir .. "_" .. level .. ".png"
end

function ISnow.bloodTrackFile(width, dir, level)
    return "btrack_" .. width .. "_" .. dir .. "_" .. level .. ".png"
end

-- Immersion 0.5.2 (see BARE_VARIANTS above): a bare foot's dent and carried snow, a bloody sole
-- (bare: a bare foot's), blood drops, half (0 head, 1 legs) of a body's imprint.
function ISnow.barePrintFile(foot, dir, variant, level)
    return "bare_" .. foot .. "_" .. dir .. "_" .. variant .. "_" .. level .. ".png"
end

function ISnow.carriedBareFile(foot, dir, level)
    return "sbare_" .. foot .. "_" .. dir .. "_" .. level .. ".png"
end

function ISnow.bloodPrintFile(bare, foot, dir, level)
    return (bare and "bbare_" or "bprint_") .. foot .. "_" .. dir .. "_" .. level .. ".png"
end

function ISnow.bloodDropFile(variant, level)
    return "blood_" .. variant .. "_" .. level .. ".png"
end

local DEFAULTS = {
    FootprintsFrom = 1,     -- who leaves footprints: 1 everyone, 2 players only, 3 nobody (FROM)
    FootprintHours = 6,
    ZombieFootprintHours = 6,
    SnowfallCoverRate = 8,
    MaxFootprints = 2000,
    ZombieRadius = 25,
    -- Animal tracks (ISnow_AnimalTracks.lua)
    AnimalTracks = true,
    AnimalTrackHours = 12,
    MaxAnimalTracks = 1000,
    AnimalTrackRadius = 25,
    -- Immersion 0.5.2: barefoot prints, bloody footprints, blood on the snow
    BarefootPrints = true,
    BloodyFootprints = true,
    BloodyFootprintSteps = 8,
    BloodOnSnow = true,
    TireTracks = true,
    TireTrackHours = 12,
    MaxTireTracks = 4000,
    TireTrackSoftLimit = 1500,
    -- bloody tire tracks (ISnow_TireTracks.lua): on/off, tiles a wheel's track stays red
    BloodyTireTracks = true,
    BloodyTireTrackTiles = 2,
    VehicleSnow = true,
    VehicleSnowHours = 2,
    VehicleSnowIce = true,      -- the icing on vehicles (drawn with the snow by one shell, at its level)
    CharSnow = true,
    CharSnowHours = 3,
    CharSnowMax = 1.5,
    CharSnowMeltHours = 1.25,
    CharSnowIndoorMeltHours = 0.5,
    CharSnowBodyMeltHours = 50,
    CharSnowRainMeltHours = 3,
    CharItemSnow = true,        -- snow on items in hand and on the body (off: clothes only)
    DarkSnow = false,           -- darker snow on vehicles, characters and items (see ISnow.darkSnow)
    ZombieSnow = true,
    ZombieSnowHours = 0.5,
    CorpseKeepSnow = false,     -- the snow stays on corpses and melts there (ISnow_CharSnow.lua "Corpses")
    ColdCorpses = true,         -- no flies over corpses and no stench sickness in frost (ISnow_ColdCorpses.lua)
    SnowWetness = true,
    SnowWetnessRate = 1,
    CarriedSnow = true,
    CarriedSnowSteps = 3,
    CarriedSnowTireTiles = 3.2,
    CarriedSnowHours = 2,
    CarriedSnowMeltHours = 0.25,
    Breath = true,
    BreathMaxTemp = 7,
    BreathFullTemp = -20,
    BreathOpacity = 0.85,
    -- 0.5.2 vehicles: the hood melting from the engine's heat (ISnow_VehicleSnow.lua, KEY_HOOD)
    VehicleHoodMelt = true,
    VehicleHoodMeltHours = 1,   -- game hours a hot engine takes to melt a full layer off the hood
    SnowKick = true,
    SnowKickRun = 0.4,
    SnowKickSprint = 1.3,
    SnowKickFalls = true,
    SnowKickFallAmount = 1,
    SnowKickWheels = true,
    SnowKickWheelAmount = 0.8,   -- 0.5.2: was 1 (ISnow_TireTracks.lua moves old saves on)
    FrostScreen = true,
    FrostScreenOpacity = 0.8,
    FrostScreenFromLevel = 1,
    FrostScreenShiver = true,
    FrostScreenShiverLevel = 2,
    FrostScreenComeSeconds = 12,
    FrostScreenGoSeconds = 30,
    VehicleFrost = true,
    VehicleFrostHours = 3,
    VehicleFrostHeaterMinutes = 10,
    VehicleFrostMeltHours = 2.5,
    LowEndMode = false,
    -- not sandbox options: only the low-end mode changes them (LOW_END)
    VehicleSnowOnePass = false, -- no snow on window panes (the low-end mode)
    VehicleSnowPieces = true,   -- snow on doors, hood, trunk lid, windows...
    VehicleSnowWheels = true,
    VehicleFrostGlass = true,   -- the frost drawn on vehicle glass (one more pass over the body)
    CharSnowSmallItems = true,  -- shells on small worn items: gloves, socks, belts... (ISnow_CharSnow.lua SMALL)
    BlowOffAmount = 1,          -- part of the blow-off particles thrown
    DecalFadeStep = 1,          -- decal fade levels used: every DecalFadeStep-th (fewer textures)
    -- Options > Mods, not sandbox: the texture variants of footprints and tire tracks (ISnow.decalVariant),
    -- the sound of snow flying off a vehicle (ISnow_BlowOff.lua; off and not in PLAYER_OPTIONS while the
    -- mod has no sound files, see ISnow_Sounds.txt)
    DetailedDecals = true,
    BlowOffSound = false,
    -- 0.5.2 weather and world: drifting snow (ISnow_Drift.lua), thaw around fires (ISnow_Thaw.lua),
    -- trampled paths (ISnow_Paths.lua). Sandbox options, but the last two (only the low-end mode
    -- changes them, LOW_END).
    DriftingSnow = true,
    DriftingSnowWind = 25,      -- km/h of wind from which snow drifts along the ground
    DriftingSnowAmount = 1,
    FireThaw = true,
    FireThawHours = 2,          -- game hours a fully thawed patch takes to go once the fire is out
    TrampledPaths = true,
    TrampledPathSteps = 12,     -- prints on a square (passes counted with forgetting) that make a path
    TrampledPathHours = 48,     -- game hours a path lasts after the last walker
    FireThawSteam = true,       -- steam off the thawing snow
    MaxTrampledPaths = 1500,    -- path segments drawn at most
}

-- Low-end mode ("Special mode for @melixrism"): for weak integrated graphics with little video
-- memory (shared with the RAM), where the GPU is the limit, not the CPU. Every shell is a whole
-- extra model drawn with a noise shader, so it takes away the shells that are many or small on
-- screen: zombies' clothes, items, small worn items (gloves, socks, belts: a painted one is a whole
-- body mesh), wheels; vehicles get no snow on the window panes and no glass
-- frost (snow and icing are one model everywhere); draws fewer decals and loads fewer decal textures. true: forced to this
-- value; a number: at most this.
local LOW_END = {
    ZombieSnow = false,
    CorpseKeepSnow = false,
    CharItemSnow = false,
    CharSnowSmallItems = false,
    VehicleSnowOnePass = true,
    VehicleSnowWheels = false,
    VehicleFrostGlass = false,
    MaxFootprints = 600,
    MaxTireTracks = 1200,
    TireTrackSoftLimit = 500,
    ZombieRadius = 15,
    -- Animal tracks (ISnow_AnimalTracks.lua)
    MaxAnimalTracks = 300,
    AnimalTrackRadius = 15,
    BloodyFootprintSteps = 4,   -- Immersion 0.5.2: fewer red prints (blood drops stay)
    BlowOffAmount = 0.35,
    DecalFadeStep = 2,
    DetailedDecals = false,
    -- 0.5.2 weather and world: no steam over thawing snow, fewer path segments (drifting snow is
    -- thinned by BlowOffAmount above)
    FireThawSteam = false,
    MaxTrampledPaths = 400,
}
ISnow.LOW_END = LOW_END

-- The same switch in Options > Mods (B42 PZAPI.ModOptions), per player and changeable in a running
-- game, for when the sandbox of a save cannot be changed; either one turns the mode on.
-- DetailedDecals and BlowOffSound (PLAYER_OPTIONS) live only there: settings of the player, not of the save.
-- Below them, every sandbox option again (MOD_OPTIONS, same ranges as sandbox-options.txt, step of
-- the slider), named and explained by the sandbox translations:
-- - SP with "UseOwn" on: this player's values replace the sandbox's (the low-end mode still caps them);
-- - SP with it off, and always in MP: an on/off option turned off still hides that here (what this
--   player sees), the rest (every number) is the sandbox's, in MP the server's (ISnow.opt).
-- Only what this client draws: in MP the snow on this player's own clothes builds up and melts at
-- the sandbox's rates (updateLevel in ISnow_CharSnow.lua), since the others see it and the melt
-- water wets the clothes. What affects gameplay is in MP always the sandbox's (MP_SERVER).
-- TOP_OPTIONS come first on the page, above the low-end mode, with their own tooltips (the
-- player's side of them); enum: a combo box of that many choices.
local TOP_OPTIONS = {
    { "FootprintsFrom", enum = 3 },
    { "TireTracks" },
    -- bloody tire tracks
    { "BloodyTireTracks" },
    -- bloody footprints, hood melt (2026-10-03/04: asked to be found and turned off at once)
    { "BloodyFootprints" },
    { "VehicleHoodMelt" },
    { "FrostScreen" },
    { "VehicleFrost" },
}
local MOD_OPTIONS = {
    { "FootprintHours", 0.5, 168, 0.5 },
    { "ZombieFootprintHours", 0.5, 168, 0.5 },
    { "SnowfallCoverRate", 0, 50, 0.5 },
    { "MaxFootprints", 10, 10000, 10 },
    { "ZombieRadius", 5, 60, 1 },
    -- Animal tracks (ISnow_AnimalTracks.lua)
    { "AnimalTracks" },
    { "AnimalTrackHours", 0.5, 168, 0.5 },
    { "MaxAnimalTracks", 10, 10000, 10 },
    { "AnimalTrackRadius", 5, 60, 1 },
    -- Immersion 0.5.2: barefoot prints, body imprints, bloody footprints, blood on the snow
    { "BarefootPrints" },
    { "BloodyFootprintSteps", 1, 40, 1 },
    { "BloodOnSnow" },
    { "TireTrackHours", 0.5, 168, 0.5 },
    { "MaxTireTracks", 20, 20000, 20 },
    { "TireTrackSoftLimit", 20, 20000, 20 },
    -- bloody tire tracks
    { "BloodyTireTrackTiles", 0.4, 40, 0.4 },
    { "VehicleSnow" },
    { "VehicleSnowHours", 0.25, 24, 0.25 },
    { "VehicleSnowIce" },
    { "CharSnow" },
    { "CharSnowHours", 0.1, 24, 0.1 },
    { "CharSnowMax", 0.1, 2, 0.05 },
    { "CharSnowMeltHours", 0.1, 24, 0.05 },
    { "CharSnowIndoorMeltHours", 0.1, 24, 0.05 },
    { "CharSnowBodyMeltHours", 1, 500, 1 },
    { "CharSnowRainMeltHours", 0.1, 48, 0.1 },
    { "CharItemSnow" },
    { "DarkSnow" },
    { "ZombieSnow" },
    { "ZombieSnowHours", 0.1, 24, 0.1 },
    { "CorpseKeepSnow" },
    { "SnowWetness" },
    { "SnowWetnessRate", 0, 5, 0.1 },
    { "CarriedSnow" },
    { "CarriedSnowSteps", 1, 10, 1 },
    { "CarriedSnowTireTiles", 0.4, 20, 0.4 },
    { "CarriedSnowHours", 0.1, 48, 0.1 },
    { "CarriedSnowMeltHours", 0.02, 24, 0.01 },
    { "Breath" },
    { "BreathMaxTemp", -20, 15, 1 },
    { "BreathFullTemp", -40, 0, 1 },
    { "BreathOpacity", 0.1, 1, 0.05 },
    -- 0.5.2 vehicles: hood melt
    { "VehicleHoodMeltHours", 0.1, 24, 0.1 },
    { "SnowKick" },
    { "SnowKickRun", 0, 3, 0.1 },
    { "SnowKickSprint", 0, 5, 0.1 },
    { "SnowKickFalls" },
    { "SnowKickFallAmount", 0.1, 3, 0.1 },
    { "SnowKickWheels" },
    { "SnowKickWheelAmount", 0.1, 3, 0.1 },
    { "FrostScreenOpacity", 0.1, 1, 0.05 },
    { "FrostScreenFromLevel", 1, 4, 1 },
    { "FrostScreenComeSeconds", 1, 120, 1 },
    { "FrostScreenGoSeconds", 1, 300, 1 },
    { "FrostScreenShiver" },
    { "FrostScreenShiverLevel", 1, 4, 1 },
    { "VehicleFrostHours", 0.25, 24, 0.25 },
    { "VehicleFrostHeaterMinutes", 1, 120, 1 },
    { "VehicleFrostMeltHours", 0.25, 24, 0.25 },
    -- 0.5.2 weather and world: drifting snow, thaw around fires, trampled paths
    { "DriftingSnow" },
    { "DriftingSnowWind", 5, 100, 1 },
    { "DriftingSnowAmount", 0.1, 3, 0.1 },
    { "FireThaw" },
    { "FireThawHours", 0.25, 24, 0.25 },
    { "TrampledPaths" },
    { "TrampledPathSteps", 3, 100, 1 },
    { "TrampledPathHours", 1, 336, 1 },
}
-- Gameplay that hinders the player: in MP the server's sandbox alone decides, the player's own values
-- in Options > Mods are not read, an option turned off there included (the rest can only be turned
-- off there, see ISnow.opt). Wetness. The frost on vehicle glass (every client works out the frost of
-- a parked vehicle on its own, so the rates must agree) and the frost on the screen in hypothermia:
-- only their numbers; the player may hide either for themselves (VehicleFrost, FrostScreen in
-- TOP_OPTIONS), never turn it on where the server has it off. The hood melting from the engine: its
-- rate, and in the hood's level always the server's on/off (ISnow.worldOpt): the driver reports that
-- level to everyone (vehSnow h); the player may only hide the melt for themselves (VehicleHoodMelt
-- in TOP_OPTIONS: the hood then shows the body's snow, ISnow_VehicleSnow.lua).
local MP_SERVER = { SnowWetness = true, SnowWetnessRate = true, ColdCorpses = true,
    VehicleHoodMeltHours = true,
    VehicleFrostHours = true, VehicleFrostHeaterMinutes = true, VehicleFrostMeltHours = true,
    FrostScreenOpacity = true, FrostScreenFromLevel = true,
    FrostScreenComeSeconds = true, FrostScreenGoSeconds = true }
ISnow.MP_SERVER = MP_SERVER
local ENUMS = { FootprintsFrom = 3 }   -- [option name] = number of choices; a higher one shows less
-- Footprints / ZombieFootprints (what the code asks) are on while FootprintsFrom is at most this.
-- Snow carried off the soles comes only with footprints, so "nobody" turns that off too.
local FROM = { Footprints = 2, ZombieFootprints = 1 }
local PLAYER_OPTIONS = { "DetailedDecals" }   -- add "BlowOffSound" back with the sound files
local modOption = nil
local playerOptions = {}   -- [option name] = tick box, PLAYER_OPTIONS
local useOwnOption = nil
local ownOptions = {}   -- [option name] = tick box, slider or combo box
local function initModOptions()
    if not (PZAPI and PZAPI.ModOptions and PZAPI.ModOptions.create) then return end
    if PZAPI.ModOptions.Dict and PZAPI.ModOptions.Dict["ImmersiveSnow"] then return end
    local function tr(key) return getText("UI_ImmersiveSnow_" .. key) end
    local function sb(key) return getText("Sandbox_ImmersiveSnow_" .. key) end
    local options = PZAPI.ModOptions:create("ImmersiveSnow", tr("Title"))
    -- Apply / Accept in Options > Mods (MainOptions:apply): the values read this tick are stale
    options.apply = function() ISnow.lowEndReset() end
    -- one at a time: an option the game cannot make (addSlider, addComboBox not checked in game)
    -- leaves the rest
    local function addOwn(o, tooltip)
        local name, min, max, step = o[1], o[2], o[3], o[4]
        local ok, box
        if o.enum then
            ok, box = pcall(function()
                local combo = options:addComboBox(name, sb(name), tooltip)
                -- the key: addItem translates it itself (getText of a translated text gave it back only
                -- while no key had that name)
                for i = 1, o.enum do combo:addItem("Sandbox_ImmersiveSnow_" .. name .. "_option" .. i, i == DEFAULTS[name]) end
                return combo
            end)
        elseif min then
            ok, box = pcall(options.addSlider, options, name, sb(name), min, max, step, DEFAULTS[name], tooltip)
        else
            ok, box = pcall(options.addTickBox, options, name, sb(name), DEFAULTS[name], tooltip)
        end
        if ok then ownOptions[name] = box end
    end
    for _, o in ipairs(TOP_OPTIONS) do addOwn(o, tr(o[1] .. "_tooltip")) end
    modOption = options:addTickBox("LowEndMode", tr("LowEndMode"), false, tr("LowEndMode_tooltip"))
    for _, name in ipairs(PLAYER_OPTIONS) do
        playerOptions[name] = options:addTickBox(name, tr(name), DEFAULTS[name], tr(name .. "_tooltip"))
    end
    if options.addSeparator then options:addSeparator() end
    if options.addTitle then options:addTitle(tr("OwnTitle")) end
    if options.addDescription then options:addDescription(tr("OwnNote")) end
    useOwnOption = options:addTickBox("UseOwn", tr("UseOwn"), false, tr("UseOwn_tooltip"))
    for _, o in ipairs(MOD_OPTIONS) do addOwn(o, sb(o[1] .. "_tooltip")) end
end
-- PZAPI.ModOptions is in client/PZAPI/ModOptions.lua, and shared/ loads before client/: this file
-- finds no PZAPI.ModOptions, so ISnow_ModOptions.lua (client) calls this once it exists. The game reads
-- ModOptions.ini only when the Options screen is built, so the saved values are loaded here too, or
-- they would not apply in a game until the player opens Options.
function ISnow.initModOptions()
    if not pcall(initModOptions) then
        modOption, playerOptions, useOwnOption, ownOptions = nil, {}, nil, {}
        return
    end
    if modOption and PZAPI.ModOptions.load then pcall(PZAPI.ModOptions.load, PZAPI.ModOptions) end
    if ISnow.lowEndReset then ISnow.lowEndReset() end   -- defined below: nil on the first call
end
ISnow.initModOptions()

-- The save's value from the game's own option (what map_sand.bin keeps). SandboxVars is only a copy
-- made by SandboxOptions.toLua at the world start: a change in a running game (the sandbox panel,
-- SP debug or admin: SandboxOptions.set, 42.21 bytecode) reaches the Java option alone, and the mod
-- went on with the old value till the save was loaded again (ColdCorpses turned off in SP still held
-- the corpse option, reported 2026-10-11). Looked up once a tick (ISnow.lowEndReset).
local javaCache = {}   -- [option name] = value, or NONE_JAVA without one
local NONE_JAVA = {}
local function javaOpt(name)
    local v = javaCache[name]
    if v == nil then
        v = NONE_JAVA
        local ok, value = pcall(function()
            local so = getSandboxOptions and getSandboxOptions()
            local opt = so and so:getOptionByName("ImmersiveSnow." .. name)
            return opt and opt:getValue()
        end)
        if ok and value ~= nil and type(value) == type(DEFAULTS[name]) then v = value end
        javaCache[name] = v
    end
    if v == NONE_JAVA then return nil end
    return v
end

local function rawOpt(name)
    local box = playerOptions[name]
    if box then
        local ok, v = pcall(box.getValue, box)
        if ok and v ~= nil then return v == true end
    end
    local java = javaOpt(name)
    if java ~= nil then return java end
    local vars = SandboxVars and SandboxVars.ImmersiveSnow
    local v = vars and vars[name]
    if v == nil then return DEFAULTS[name] end
    return v
end

-- worked out once a tick (ISnow.opt runs often)
local NONE = {}
local lowCache = nil
local useOwnCache = nil
local ownCache = {}   -- [option name] = this player's value in Options > Mods, NONE without one
local optCache = {}   -- [option name] = ISnow.opt's value
function ISnow.lowEnd()
    if lowCache ~= nil then return lowCache end
    local on = rawOpt("LowEndMode") == true
    if not on and modOption then
        local ok, v = pcall(modOption.getValue, modOption)
        on = ok and v == true
    end
    lowCache = on
    return on
end

-- Whether this player's values in Options > Mods replace the sandbox's.
function ISnow.useOwn()
    if useOwnCache ~= nil then return useOwnCache end
    local on = false
    if useOwnOption then
        local ok, v = pcall(useOwnOption.getValue, useOwnOption)
        on = ok and v == true
    end
    useOwnCache = on
    return on
end

-- This player's value of option name in Options > Mods (nil: none, or wetness in MP).
function ISnow.ownOpt(name)
    local cached = ownCache[name]
    if cached == nil then
        cached = NONE
        local box = ownOptions[name]
        if box and not (MP_SERVER[name] and isClient and isClient()) then
            local ok, v = pcall(box.getValue, box)
            if ok and type(v) == type(DEFAULTS[name]) then
                if ENUMS[name] then v = math.max(1, math.min(ENUMS[name], math.floor(v))) end
                cached = v
            end
        end
        ownCache[name] = cached
    end
    if cached == NONE then return nil end
    return cached
end

-- Quiet weather: no snow on the ground (IsoCell.getSnowTarget), none falling and warmer than any
-- breath shows (BreathMaxTemp, at least 0 C: frost on glass forms below 0) by QUIET_MARGIN. Modules
-- with nothing left to show or melt skip their polls then (ISnow_VehicleSnow, ISnow_CharSnow,
-- ISnow_Breath): out of winter the mod mostly sleeps, and wakes with the cold; by the weather, not
-- the date (cold snaps in autumn and spring, endless-winter mods). Looked at once a second.
local QUIET_MARGIN = 3
local QUIET_CHECK_MS = 1000
local quietAt, quietValue = nil, false
function ISnow.quietWeather()
    local now = getTimestampMs()
    if quietAt and now - quietAt < QUIET_CHECK_MS and now >= quietAt then return quietValue end
    quietAt = now
    local ok, quiet = pcall(function()
        local cell = getCell()
        if not cell or cell:getSnowTarget() > 0 then return false end
        local clim = getClimateManager()
        if clim:isSnowing() then return false end
        local warmEnough = math.max(ISnow.opt("BreathMaxTemp") or 7, 0) + QUIET_MARGIN
        return clim:getTemperature() > warmEnough
    end)
    quietValue = ok and quiet == true
    return quietValue
end

-- Handlers of the events that come every tick or frame, registered through ISnow.listen so that
-- ISnow.bench can time them: { event, module, fn } in registration order.
ISnow.handlers = ISnow.handlers or {}
function ISnow.listen(event, module, fn)
    local e = Events and Events[event]
    if not e then return end
    e.Add(fn)
    table.insert(ISnow.handlers, { event = event, module = module, fn = fn })
end

-- Debug console: ISnow.bench(n) calls every tick handler (OnTick, OnTickEvenPaused, OnPlayerUpdate
-- for player 0) n times (default 2000) and prints microseconds per call, by module, and the sum per
-- tick. Each call counts as a tick for the handler, so the polls it makes every so many ticks come
-- in at their usual share. render = true times the render handlers too (they draw outside the
-- render pass then: only where nothing is shown, as in summer). The game clock has whole
-- milliseconds only, hence the many calls.
function ISnow.bench(n, render)
    n = tonumber(n) or 2000
    local player = getSpecificPlayer(0)
    local perTick, rows = 0, {}
    for _, h in ipairs(ISnow.handlers) do
        local ev = h.event
        local tick = ev == "OnTick" or ev == "OnTickEvenPaused" or ev == "OnPlayerUpdate"
        if tick or (render and (ev == "OnPostRender" or ev == "RenderOpaqueObjectsInWorld")) then
            local arg = (ev == "OnPlayerUpdate" and player) or (ev == "RenderOpaqueObjectsInWorld" and 0) or nil
            local t0 = getTimestampMs()
            for _ = 1, n do pcall(h.fn, arg) end
            local us = (getTimestampMs() - t0) * 1000 / n
            if tick then perTick = perTick + us end
            table.insert(rows, string.format("%-10s %-26s %7.2f us", h.module, ev, us))
        end
    end
    table.insert(rows, string.format("sum of the tick handlers: %.1f us per tick (%.2f%% of a 16.7 ms frame)", perTick, perTick / 167))
    local out = table.concat(rows, "\n")
    print(out)
    return out
end

function ISnow.lowEndReset()
    lowCache = nil
    useOwnCache = nil
    for name in pairs(ownCache) do ownCache[name] = nil end
    for name in pairs(optCache) do optCache[name] = nil end
    for name in pairs(javaCache) do javaCache[name] = nil end
end
ISnow.listen("OnTick", "Config", ISnow.lowEndReset)
-- also paused (the vehicle snow polls on OnTickEvenPaused, which fires before OnTick in a frame)
ISnow.listen("OnTickEvenPaused", "Config", ISnow.lowEndReset)
-- and before the world start's handlers (registered after these: the other files require this one),
-- so nothing read in the main menu (its default sandbox) is taken for the save's
for _, event in ipairs({ "OnInitWorld", "OnGameStart", "OnServerStarted" }) do
    if Events and Events[event] then Events[event].Add(ISnow.lowEndReset) end
end

-- v for option name, capped by the low-end mode.
local function capped(name, v)
    local low = LOW_END[name]
    if low ~= nil and ISnow.lowEnd() then
        if type(low) == "number" and type(v) == "number" then
            if name == "DecalFadeStep" then return math.max(v, low) end
            return math.min(v, low)
        end
        return low
    end
    return v
end

-- The value of option name for the save (sandbox and low-end mode), without the player's own
-- settings: what the others see of this player in MP.
function ISnow.worldOpt(name)
    local upTo = FROM[name]
    if upTo then return (tonumber(ISnow.worldOpt("FootprintsFrom")) or 1) <= upTo end
    return capped(name, rawOpt(name))
end

-- ISnow.opt(name) without the cache.
local function optNow(name)
    local upTo = FROM[name]
    if upTo then return (tonumber(ISnow.opt("FootprintsFrom")) or 1) <= upTo end
    local own = ISnow.ownOpt(name)
    if own ~= nil and ISnow.useOwn() and not (isClient and isClient()) then return capped(name, own) end
    local v = ISnow.worldOpt(name)
    if own == nil then return v end
    -- only what is on by default can be hidden this way: the box of an option off by default
    -- (DarkSnow, CorpseKeepSnow) is false unless the player ticked it, so it hid the sandbox's (the
    -- server's) "on" from everyone who never opened Options > Mods (found 2026-10-08)
    if v == true and own == false and DEFAULTS[name] ~= false then return false end
    if ENUMS[name] and type(v) == "number" then return math.max(v, own) end
    return v
end

-- The value of option name here. SP: the player's own settings in Options > Mods when they replace
-- the sandbox (UseOwn), else ISnow.worldOpt with what this player turned off there off.
-- MP: always ISnow.worldOpt (the server's), UseOwn or not; the player's on/off options only turn
-- off what the server has on (never on what it has off), FootprintsFrom only shows less; every
-- number (hours, limits, rates, radius) is the server's; MP_SERVER options are the server's alone.
--
-- Public: another mod reads ISnow.opt to turn off its own versions of our effects while ours are on
-- (asked for on 2026-10-03). Keep ISnow.opt and these names, with their types, as they are, and tell
-- that mod's author before any change (test: tools/luatest/test_compatapi.lua):
--   Footprints, ZombieFootprints (from FootprintsFrom), TireTracks, SnowKick, SnowKickFalls,
--   SnowKickWheels: true/false; SnowKickRun, SnowKickSprint: numbers, 0 is none.
-- Worked out once a tick, as the parts above: ISnow.lowEndReset empties the cache every tick and on
-- Apply in Options > Mods, so a change there (the low-end mode too) is read at once, paused too.
function ISnow.opt(name)
    local v = optCache[name]
    if v == nil then
        v = optNow(name)
        optCache[name] = v
    end
    return v
end

-- Darker snow: the ground's snow of Snow Lands - Darker Snow (its e_newsnow_ground_* sprites against
-- the vanilla ones, mean colour 175,189,199 against 240,247,250): our snow on vehicles, characters,
-- items, the particles and the carried snow is darkened by DARK_SNOW_RGB (as DARK_RGB in
-- isnow_vehiclesnow.frag / isnow_charsnow.frag) to match it. On with that mod, or with DarkSnow.
ISnow.DARK_SNOW_MODS = { "SLDarkerSnow" }
ISnow.DARK_SNOW_RGB = { 0.729, 0.765, 0.795 }
-- its luminance (Rec. 709 weights), for what can only get fainter (the carried snow's alpha level)
ISnow.DARK_SNOW_LUMA = 0.2126 * 0.729 + 0.7152 * 0.765 + 0.0722 * 0.795
local darkSnowCache = nil

-- Whether the snow is darker. Read once a session: the vehicle shells' models get their shader when
-- first shown (VehicleShells.ensure), so a change in Options > Mods takes effect after loading the
-- save again (as its tooltip says).
function ISnow.darkSnow()
    if darkSnowCache ~= nil then return darkSnowCache end
    local on = false
    local mods = getActivatedMods and getActivatedMods()
    if mods then
        for _, id in ipairs(ISnow.DARK_SNOW_MODS) do
            if mods:contains(id) or mods:contains("\\" .. id) then on = true end
        end
    end
    darkSnowCache = on or ISnow.opt("DarkSnow") == true
    return darkSnowCache
end

-- Reads ISnow.darkSnow anew on its next call (tests).
function ISnow.resetDarkSnow() darkSnowCache = nil end

-- MP: the server sets a client's clock to its own (SyncClockPacket.processClient: setTimeOfDay with
-- the server's time of day, bytecode 42.21), and the client runs its clock on its own in between, so
-- getWorldAgeHours on a client that ran ahead steps back a little. A time stamp up to this many game
-- hours in the future is such a step (no time passed), not a save loaded from before it.
ISnow.CLOCK_SLACK_HOURS = 0.5

-- Whether o (a character, vehicle or square) is under the open sky: outside and not below ground.
-- isOutside is the square's exterior flag (IsoGridSquare.isOutside), which only a room or a roof
-- clears, and the engine finds no roof over a basement (z < 0) that has only the ground floor above
-- it: IsoChunk on load covers the levels under a rain-blocking tile from z 1 up only, and
-- IsoCell.checkHaveRoof walks z 31..0 (bytecode 42.21). So a basement without a room under open
-- ground (no building above) is "outside" to the engine (Silfarionblade, 2026-10-01: snow in a
-- basement). Nothing below ground is under the sky.
function ISnow.underSky(o)
    return o ~= nil and o:isOutside() and o:getZ() >= 0
end

-- Whether a tile above sq blocks the rain: what IsoCell.checkHaveRoof puts into sq.haveRoof (a
-- field, not readable from Lua), going down the column from the chunk's top level, a square below
-- a hasRainBlockingTile one (solid floor or BlockRain) has a roof (bytecode 42.21).
-- IsoGridSquare.haveRoofFull is not that: it also takes the haveRoof of every square of the column
-- from level 1 up, so on an open rooftop (the floor below it has a roof: the rooftop) it says yes.
local function roofOver(sq)
    local chunk = sq:getChunk()
    local cell = chunk and getCell()
    if not cell then return false end
    local x, y = sq:getX(), sq:getY()
    for z = sq:getZ() + 1, chunk:getMaxLevel() do
        local above = cell:getGridSquare(x, y, z)
        if above and above:hasRainBlockingTile() then return true end
    end
    return false
end

-- Whether falling snow reaches o (a character, vehicle or square): under the sky as above and, as
-- vanilla rain decides it (BodyDamage.UpdateWetness, bytecode 42.21), not in a room (player-built
-- ones included: IsoGridSquare.isInARoom) and with no roof over it (roofOver). Vanilla takes the
-- exterior flag off a square under a roof itself (a floor built above, IsoChunk loading: haveRoof
-- unsets exterior; seen in game 2026-10-11, no such square in Muldraugh), so on vanilla maps this
-- is underSky; it keeps to the rain's rule for maps whose flags say otherwise. The ground snow
-- follows the exterior flag (FBORenderSnow), so decals and the shovel keep underSky.
function ISnow.snowReaches(o)
    if not ISnow.underSky(o) then return false end
    local sq = o
    if not instanceof(o, "IsoGridSquare") then sq = o.getCurrentSquare and o:getCurrentSquare() end
    if not sq or not sq.isInARoom then return true end
    return not (sq:isInARoom() or roofOver(sq))
end

-- The same for a character: in a vehicle only on a seat without a roof (BaseVehicle.hasRoof: the
-- script's passenger hasRoof; motorcycles, open seats), as vanilla rain wets them (UpdateWetness).
function ISnow.snowFallsOnCharacter(chr)
    if not ISnow.snowReaches(chr) then return false end
    local v = chr:getVehicle()
    return v == nil or not v:hasRoof(v:getSeat(chr))
end

-- Snow cover of the ground 0..1 as vanilla draws it: the IsoCell snow target (the climate's
-- snowFracNow, 0 when the sandbox has no snow on the ground), but only in the erosion winter or
-- with forced snow. FBORenderSnow.SnowGrid.init leaves every chunk's snow grid empty outside
-- ClimateManager.getSeason():isSeason(WINTER = 5) unless Core.isForceSnow (bytecode 42.21), while
-- snow falls by temperature alone: a cold snap in autumn or spring (or a cold climate mod) gives
-- a snow target over 0 and bare ground. Vehicles and zombies took their snow from the target and
-- were white on that bare ground. (Vanilla also draws no puddles while the target is over 0,
-- FBORenderCell.renderPuddles: isSnowAnywhere, season or not; players took that for the mod.)
function ISnow.groundCover()
    local cell = getCell()
    local target = cell and cell:getSnowTarget() or 0
    if target <= 0 then return 0 end
    local ok, drawn = pcall(function()
        if getCore():isForceSnow() then return true end
        local season = getClimateManager():getSeason()
        return season == nil or season:isSeason(5)
    end)
    if ok and not drawn then return 0 end
    return math.max(0, math.min(1, target / 100))
end

-- The players this client (or the server) knows in MP, local ones included: getOnlinePlayers (B41
-- name) or getConnectedPlayers (used by B42 mods); which of them B42.20 has is not checked in
-- game, so either. nil when there is neither.
function ISnow.otherPlayers()
    if getOnlinePlayers then return getOnlinePlayers() end
    if getConnectedPlayers then return getConnectedPlayers() end
    return nil
end

-- Kahlua has no weak tables: __mode is ignored (no class of se/krka/kahlua reads it, 42.20; 200000
-- keys stayed in a { __mode = "k" } table through collectgarbage on the game's VM). A table keyed
-- by game objects keeps every vehicle, character and item it ever had, so such tables are pruned
-- by hand. ISnow.prune(t, keep): drops each key for which keep(key, value) is not true (or fails);
-- the count dropped. Keys are collected first: no removal while pairs walks the table.
function ISnow.prune(t, keep)
    local drop = nil
    for k, v in pairs(t) do
        local ok, yes = pcall(keep, k, v)
        if not (ok and yes) then
            drop = drop or {}
            drop[#drop + 1] = k
        end
    end
    if not drop then return 0 end
    for i = 1, #drop do t[drop[i]] = nil end
    return #drop
end

-- The characters alive in this game for this client: [character] = true for the local players
-- and, in MP, the others it knows. Dead ones are left out (a respawn is a new object).
function ISnow.liveCharacters()
    local live = {}
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and not p:isDead() then live[p] = true end
    end
    local others = isClient() and ISnow.otherPlayers() or nil
    if others then
        for i = 0, others:size() - 1 do
            local p = others:get(i)
            if p and not p:isDead() then live[p] = true end
        end
    end
    return live
end

-- [vehicle] = true for the vehicles loaded in the cell now (a vehicle unloaded or streamed out and
-- back is a new object).
function ISnow.liveVehicles()
    local live = {}
    local cell = getCell()
    local list = cell and cell:getVehicles()
    if not list then return live end
    local it = list:iterator()
    while it:hasNext() do
        local v = it:next()
        if v then live[v] = true end
    end
    return live
end

-- A save keeps the sandbox values it was made with, so a new default would reach new saves only.
-- Once per SP save (flag in the global ModData): option name, if it still has the old default, gets
-- the new one, and the game writes it to map_sand.bin with the next save. Only in a save the mod has
-- run in before (its global ModData was there when the game started; only this function makes it,
-- since 0.5.1): a new game has the new default already, and an old value in it was the player's
-- choice. After that the flag keeps a value set by hand later. MP servers keep their sandbox as the
-- admin set it. Call on OnGameStart (the ModData is loaded then).
local savedBefore = nil   -- the mod's global ModData was in this save when it was loaded
function ISnow.migrateDefault(flag, name, old, new)
    if isClient() or isServer() then return end
    if savedBefore == nil then
        local ok, had = pcall(ModData.exists, "ImmersiveSnow")
        savedBefore = ok and had == true
    end
    local data = ModData.getOrCreate("ImmersiveSnow")
    if data[flag] then return end
    if savedBefore then
        local options = getSandboxOptions()
        local option = options:getOptionByName("ImmersiveSnow." .. name)
        if option and option:getValue() == old then
            options:set("ImmersiveSnow." .. name, new)
            options:toLua()
            print("[ImmersiveSnow] " .. name .. " " .. old .. " -> " .. new .. " (new default)")
        end
    end
    -- only once it is done: a move that failed is tried again with the next start
    data[flag] = true
end
