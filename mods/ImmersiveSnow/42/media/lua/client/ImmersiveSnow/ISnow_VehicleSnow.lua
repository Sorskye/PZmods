-- Immersive Snow: snow building up on vehicles.
--
-- Every vehicle script has shell parts (body, wheels, separate body pieces) with one model per
-- snow stage (ISnow_VehicleShells.lua). The client keeps two levels 0..1 per vehicle (see stateOf),
-- the settled snow (the fields on top, stages s1..s6) and the icing (patches and glass / rim edges,
-- i1..i6, drawn under the snow), and shows the matching stages with VehiclePart:setModelVisible. Model visibility is local render state (never transmitted), so
-- every client decides on its own; the level only depends on weather and on what the vehicle
-- does, which all clients see alike.
--
-- Snow level per game hour:
--   + snowIntensity / VehicleSnowHours    while snowing and the vehicle stands outdoors
--   - MELT_PER_DEGREE * temperature       above 0 C, the air temperature of the vehicle's square
--                                         (ClimateManager.getAirTemperatureForSquare: indoors,
--                                         heat sources)
--   - INDOOR_MELT                         under a roof (garage), even in the frost
--   - ENGINE_MELT                         while the engine runs
--   - (speed - BLOW_KMH) * BLOW_PER_KMH   while driving faster than BLOW_KMH (slow: the wind only
--                                         takes the snow layer, over several game hours)
-- The hood (VehicleHoodMelt, the body pieces of HOOD_PART and its children) melts on top of that from
-- the engine's heat: warmth / VehicleHoodMeltHours more, warmth = the vanilla engine temperature
-- (Engine part ModData, see engineWarmth) over ENGINE_WARM. It is kept as the hood's deficit against
-- the body (KEY_HOOD), like the deficit of a door opened (see pieceStage), and reported in MP.
-- The icing has the snow's level (KEY_ICE = KEY_LEVEL): it comes, melts and blows off with the snow,
-- and both are drawn by one model (the snow stage's BOTH_OF, see showNow).
-- Faster than BLOWOFF_KMH a heap of snow does not stay on: snow above stage BLOWOFF_KEEP flies off,
-- one stage at a time (see BLOWOFF_LEAD_MS), as clumps and powder with a sound (ISnow_BlowOff.lua); the lower stages
-- stay. Snow falling on a vehicle already that fast stops at stage BLOWOFF_KEEP quietly.
-- A vehicle the mod meets for the first time (fresh spawn, a save from before the mod) or one that
-- was not updated for more than CATCHUP_HOURS (the player went farther than RADIUS, a save loaded
-- later) has outdoors the ground snow cover, snow and icing alike: the ground shows what the
-- weather did meanwhile (a thaw nobody watched takes the icing too), and a car standing out there
-- would carry as much. Under a roof one met for the first time has none, and one not updated goes
-- on from its own level, melting over the whole gap as in a garage (catchUp).
-- While no local player sees a vehicle (see seenAlpha: the game fades vehicles out of sight) its
-- snow is not changed: the shells fade with it (isnow_vehiclesnow.frag writes the vehicle's alpha),
-- and every model switch rebuilds all its models (see TOGGLE_MIN), so the changes wait (pending)
-- until it is seen. Hiding the snow out of sight and showing it again made a KI5 truck rebuild its
-- models some 60 times each way, again and again while driving past.
-- MP: every client works the levels out on its own, but the one whose player drives a vehicle
-- reports them through the server ("Multiplayer" below), so the others see the snow the driver
-- blew off, and a client that comes later (or back) gets the last report instead of the ground cover.
--
-- Frost on the glass (VehicleFrost; a third level, KEY_FROST): hoarfrost that grows on a vehicle
-- standing outdoors below 0 C with the engine off, faster in harder frost (full in VehicleFrostHours
-- at -FROST_FULL_DEG C and colder). It melts above 0 (VehicleFrostMeltHours at +FROST_MELT_AT C),
-- slowly under a roof, fast with the engine running and the heater on (VehicleFrostHeaterMinutes
-- game minutes from full) and FROST_ENGINE_SLOW times slower with the engine alone. Scraping it
-- off (ISnow_FrostScrape.lua, VehicleSnow.scrape) clears it. It is drawn on the glass itself: a
-- third layer of shells (GLASS_STAGES, shader GLASS_LAYER: hoarfrost on the mask's window zones
-- only) on the body and the body pieces whose glass is in and closed, not on the paint. It is only
-- that texture: it does not narrow the view from inside (the camera looks down, not through the
-- glass). VehicleSnow.frostOf (only while the windscreen is in and whole: hasWindscreen) is what
-- the scrape works on. A vehicle met first or caught up outdoors in frost has what the cold gives
-- (frostFor). MP: reported with the other levels; a scrape goes to everyone ("vehFrost").
--
-- Brushing the snow off (ISnow_SnowBrush.lua, VehicleSnow.brush) takes all the snow, and the icing
-- with it (one level). MP: the brushing client reports the levels like a driver ("vehSnow").
--
-- Clean glass (KEY_GLASS_CLEAN): the icing layer also draws on the glass (a band of snow along its
-- edge, a frost film in zones). A brush or a scrape wipes the windows (VehicleSnow.cleanGlass): the
-- icing then shows the stages without the glass (ICE_CLEAN_STAGES, BOTH_CLEAN_STAGES in the
-- low-end one pass) while the rest of the body keeps it, until new icing of GLASS_REICE grows over
-- the level it had when wiped (snow falling again), or the vehicle takes the ground cover (first
-- sight, a catch-up outdoors). The hoarfrost (VehicleFrost) is apart: only a scrape takes it. MP:
-- reports carry it (g), a scrape ("vehFrost") wipes the glass for everyone too.

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_CompatViewpoint"

local VehicleSnow = {}
ISnow.VehicleSnow = VehicleSnow

-- Project Viewpoint draws the world in 3D now: it draws the shells as copies of the body and wheels
-- with the vehicle's textures, so none are shown (ISnow_CompatViewpoint.lua). The levels go on.
local function viewpoint() return ISnow.Viewpoint ~= nil and ISnow.Viewpoint.hideVehicleShells() end

local POLL_TICKS = 30
local RADIUS = 60
local MIN_LEVEL = 0.02
local MELT_PER_DEGREE = 0.15
local INDOOR_MELT = 0.05     -- a full layer in 20 game hours in a frozen garage
local ENGINE_MELT = 0.05
local BLOW_KMH = 15
local BLOW_PER_KMH = 0.003   -- 60 km/h: 0.135 per hour, a full layer in about 7 game hours
local ICE_MELT = 0.5   -- the icing under a roof in a catch-up (overridden by the snow's level since)
local BLOWOFF_KMH = 40
local BLOWOFF_KEEP = 4       -- snow stages that stay on at any speed
-- One stage goes like this: after BLOWOFF_START_MS at speed the wind starts lifting the top
-- (particles growing from LEAD_*[1] to LEAD_*[2] of the full rate over BLOWOFF_LEAD_MS), then the
-- stage flies off with BLOWOFF_BURST_MS of particles at the full rate; the next stage starts its lead
-- after BLOWOFF_PAUSE_MS more at speed. Slower than BLOWOFF_KMH * BLOWOFF_SLOW stops the lead and
-- restarts the count; that slow for BLOWOFF_PAUSE_MS forgets the vehicle.
local BLOWOFF_SLOW = 0.75
local BLOWOFF_START_MS = 2000
local BLOWOFF_LEAD_MS = 6000
local BLOWOFF_BURST_MS = 1000
local BLOWOFF_PAUSE_MS = 15000
local BLOWOFF_LEAD_CHUNKS = { 0.05, 0.4 }
local BLOWOFF_LEAD_PUFFS = { 0.2, 0.7 }
local BLOWOFF_CHUNKS = 20    -- clumps and powder puffs per second at the full rate, on a car of REF_AREA
local BLOWOFF_PUFFS = 24
local BLOWOFF_REF_AREA = 1.56 * 4.52   -- extents x * z of a pickup (Base.88chevyS10)
local CATCHUP_HOURS = 2
local CLOCK_SLACK = ISnow.CLOCK_SLACK_HOURS   -- MP: a clock sync steps back up to this, see ISnow_Config.lua
local BRUSH_ICE_KEEP = 2     -- icing stages left on a vehicle brushed clean
local KEY_GLASS_CLEAN = "ISnowGlassClean"   -- icing level when the glass was wiped (nil: not clean)
local GLASS_REICE = 1 / 6    -- new icing over that level that frosts the wiped glass again
local KEY_LEVEL = "ISnowLevel"
local KEY_AT = "ISnowAt"
local KEY_ICE = "ISnowIce"
local KEY_FROST = "ISnowFrost"
local FROST_BELOW = 0        -- C: hoarfrost forms below this air temperature
local FROST_FULL_DEG = 8     -- degrees under FROST_BELOW at which it grows at its full rate
local FROST_ENGINE_SLOW = 4  -- the engine without the heater thaws it this many times slower
local FROST_GLASS_PART = "Windshield"   -- the glass the frost is seen through and scraped off
local FROST_MELT_AT = 5      -- C at which full frost thaws in VehicleFrostMeltHours (twice as warm: twice as fast)
local FROST_REPORT_STEPS = 12   -- MP: a new report when the frost moves a step of 1 / this
-- The hood melting from the engine (VehicleHoodMelt). KEY_HOOD: how much less snow the hood has than
-- the body, kept like a door's deficit (KEY_CLEAR) but apart from it, since only it is reported (h).
-- The engine's heat is the vanilla Engine part's ModData temperature (Vehicles.Update.Engine,
-- media/lua/server/Vehicles/Vehicles.lua 42.21): while running +ZombRand(0, 3) a game minute up to
-- 100 (more with a worn or missing hood), after it -2 a minute down to 0, so warm after about an
-- hour of running and cold 50 minutes after it stops. The server transmits it to the clients
-- (transmitPartModData) as it changes. Full hood melt from ENGINE_WARM.
local KEY_HOOD = "ISnowHood"
local HOOD_PART = "EngineDoor"   -- the vanilla hood (template EngineDoor; KI5 and VVA keep the id)
local ENGINE_WARM = 60
local MP_KEEP_HOURS = 72           -- MP: levels of vehicles not updated this long are forgotten
local ICE = "#ice"   -- showOn key suffix of the icing models
local GLASS = "#glass"   -- ... of the glass frost models
-- Out of sight: below this vehicle alpha (the fade's midpoint), checked every SIGHT_TICKS ticks.
local SEEN_ALPHA = 0.5
local SIGHT_TICKS = 3
-- Every model shown or hidden on a vehicle in the world makes the game build all its models anew
-- (BaseVehicle.setModelVisible: ModelManager.Remove + addVehicle, a new instance for every visible
-- model, bytecode 42.21), so showing the snow on a vehicle with n snow models costs about n * n
-- model instances: a KI5 truck with its pieces, icing and glass frost has some 60. A parking lot
-- coming into sight (or the first stages of each vehicle type, Shells.addVariant) froze the game.
-- The switches are paced: TOGGLE_MIN per tick, more while this tick's vehicle snow work stays under
-- TOGGLE_MS; a vehicle whose show() was cut short is shown again from the same state on the next
-- ticks (pending). One switch on a KI5 truck rebuilds a hundred models or so: 4 a tick, whatever
-- they took, kept the frames long for as long as a parking lot took (minutes with 100+ vehicle
-- mods, at load and when driving).
local TOGGLE_MIN = 1
local TOGGLE_MS = 3
-- A frame longer than this is logged (at most every HITCH_LOG_MS) with how much of it was ours.
local HITCH_MS = 150
local HITCH_LOG_MS = 5000

-- Body pieces (doors, hood, trunk lid, windows...) carry the body's snow while installed and closed.
-- Rolling down a window or removing a piece shakes all the snow off it and its children: the piece
-- keeps a deficit (ModData KEY_CLEAR[source part id]) of the body level at that moment, which only
-- new snow on the body pays off. Opening a door shakes one stage off it and its children, as the
-- speed does (BLOWOFF_KEEP and below stay), once per opening (doorsOpened); the open door shows
-- nothing until closed.
-- A piece's snow part shares the piece's animation player (see ISnow_VehicleShells.lua) and every
-- visible model updates that player once per frame (BaseVehicle.postupdate), so the piece would
-- animate faster while its snow shows. Part animations are started from Lua only (BaseVehicle:
-- playPartAnim, hooked below; the engine itself only sets the still Opened / Closed poses), so when
-- a part that can animate starts one, the snow on every piece sharing that player (the part's whole
-- tree: children use their parent's player) goes on the next tick and comes back HIDE_MS after the
-- start. The engine gives no way to see when the animation ends (a KI5 door takes under 0.45 s);
-- a longer one only runs faster for its rest.
local HIDE_MS = 700
local KEY_CLEAR = "ISnowClear"

local PART = ISnow.VEHICLE_SNOW_PART
local PIECE_PREFIX = ISnow.VEHICLE_SNOW_PART_PREFIX
local PIECE_CATEGORIES = ISnow.VEHICLE_SNOW_PART_CATEGORIES
local STAGES = ISnow.VEHICLE_SNOW_STAGES
local ICE_STAGES = ISnow.VEHICLE_SNOW_ICE_STAGES
local GLASS_STAGES = ISnow.VEHICLE_SNOW_GLASS_STAGES
-- VehicleSnowOnePass (the low-end mode): the snow stage's model with the icing in it, in place of
-- the snow and icing models (body and body pieces; wheels have no such model)
local BOTH_OF = {}
for i, id in ipairs(STAGES) do BOTH_OF[id] = ISnow.VEHICLE_SNOW_BOTH_STAGES[i] end
-- clean glass (KEY_GLASS_CLEAN): the icing and one-pass stages without the glass, other ids as they are
local CLEAN_OF = {}
for i, id in ipairs(ICE_STAGES) do CLEAN_OF[id] = ISnow.VEHICLE_SNOW_ICE_CLEAN_STAGES[i] end
for i, id in ipairs(ISnow.VEHICLE_SNOW_BOTH_STAGES) do CLEAN_OF[id] = ISnow.VEHICLE_SNOW_BOTH_CLEAN_STAGES[i] end
local function cleanOf(id) return id and CLEAN_OF[id] or id end

local shown = {}    -- [shell part] = { [slot] = variant id currently visible }
local modelVis = {} -- [part] = { [model id] = visible }, from the setModelVisible hook
local pinned = {}   -- [vehicle] = { snow, ice } levels set from the console
local forcedModel = {}  -- [vehicle] = model id set from the console
local doorsOpened = {} -- [vehicle] = { [source part id] = true } while its door is open
local anims = {}     -- [root part] = getTimestampMs() of the last animation in its tree
-- [part] = { at = { times of its last SWITCH_COUNT model switches from Lua }, n = how many } (see
-- noteSwitch): a part whose models Lua keeps switching (a helicopter rotor turning, AviationCore
-- shows one of 24 blade positions at a time) shows no snow and sheds it
local switches = {}
local SWITCH_COUNT = 3       -- switches ...
local SWITCH_WINDOW_MS = 2000  -- ... within this make the part spinning,
local SWITCH_GAP_MS = 30     -- each this long after the one before (a variant set in one go is one)
local SWITCH_HOLD_MS = 1500  -- and it stays so this long after the last one

-- Whether Lua keeps switching the models of part (see switches).
local function spinning(part, now)
    local s = switches[part]
    if not s or s.n < SWITCH_COUNT then return false end
    local last = s.at[SWITCH_COUNT]
    return now - last < SWITCH_HOLD_MS and last - s.at[1] <= SWITCH_WINDOW_MS
end
local animatable = {} -- [script part] = whether a model of it is not static
local blowing = {}  -- [vehicle] = blow-off state, see startBlow
local unseen = {}   -- [vehicle] = true while out of sight (its changes wait)
-- Vehicles without snow cost nothing past their level (all year: in summer every vehicle is one):
-- bare[v] is set once a poll hid everything on v (NO_PART: v has no snow part), and while v has
-- nothing to show poll() skips show() and the sight test, which could not change anything on it.
-- snowy: the vehicles near the player that the last poll showed snow or icing on, the only ones
-- the sight test between polls looks at, with what that poll showed: a vehicle coming back into
-- sight gets what waits for it (pending) without a poll of every vehicle near.
local NO_PART = "no part"
local bare = {}     -- [vehicle] = true / NO_PART
local snowy = {}    -- [vehicle] = { id, iceId, level, ice, glassId, clean } (level nil: no lv)
local hooked = false      -- BaseVehicle:playPartAnim hooked
local piecesOff = false   -- console switch, VehicleSnow.pieces(false)
local sightOff = false    -- console switch, VehicleSnow.sight(false)
local sightBroken = false -- the vehicle a player sits in read as faded: vehicle alpha is not the fade
local stats = { near = 0, noPart = 0, visible = 0, unseen = 0, errors = 0, pieces = 0, piecesShown = 0, noShellModel = 0,
    anims = 0, blowOffs = 0, toggles = 0, deferred = 0, asleep = 0 }
-- The budget of this tick (see TOGGLE_MIN): when it started, the switches made, whether a show()
-- ran out of it. pending[v] = what show() was asked to show on v, done on the next ticks.
local budget = { start = 0, toggles = 0, out = false }
local pending = {}
-- Our share of the frames, for the hitch log: this tick's ms and switches, variants and shell
-- models made (ISnow_CharSnow.lua adds its zombie rebuilds to the same table).
ISnow.perf = ISnow.perf or {}
local perf = ISnow.perf
local lastError = nil

-- Where the levels of vehicle v live (keys KEY_LEVEL, KEY_ICE, KEY_AT, KEY_CLEAR). SP: its ModData,
-- saved with the world. MP: a client's ModData of a vehicle is the server's copy, which comes back
-- whenever the server sends the vehicle again (streamed in, full updates), and which keeps
-- whatever a mod transmits from some client's copy (transmitModData): the server saves that, so a
-- stale level survived restarts, and levels kept there went back to it or to nothing (then the
-- ground cover: full snow again right after it was blown off). So in
-- MP they live in mpState by vehicle id (the same for all clients while the server runs), for the
-- session, and the keys are taken out of the client's ModData, so the next transmit clears the
-- server's copy too.
local mpState = {}      -- [vehicle id] = { script = vehicle script full name, levels by key }
local mpPurgedAt = nil  -- world hours of the last purge of mpState

-- Multiplayer -----------------------------------------------------------------
-- The client whose local player drives a vehicle reports its snow and icing levels ("vehSnow":
-- id, s = script full name, l, i, h = the hood's melt KEY_HOOD) when the stage of either (or of the
-- hood) changes (blow-offs included) and every REPORT_REFRESH_MS, even while that player hides vehicle snow in Options > Mods; the
-- server (ISnow_VehicleSnowServer.lua) keeps the last report per vehicle id and passes it on to
-- every client (from = the sender's online id, so it skips its own). A client meeting a vehicle
-- it has no levels for asks for the kept report ("vehSnowQuery"); the answer has age = game hours
-- since the report. A report is taken (incoming, applied in updateLevel) unless a local player
-- drives that vehicle (a vehicle met first at the wheel takes it, see awaitingReport); the levels
-- then go on from it as usual (catch-up when it is old). Until the
-- answer comes (or QUERY_WAIT_MS passed: the server has no report and sends nothing) such a vehicle
-- is not updated and shows nothing (awaitingReport): a first sight would put the ground cover on it,
-- and a car its driver had blown or brushed clean flashed snowed-in until the report came.
-- A player hiding vehicle snow (Options > Mods) only hides it here: at the wheel the client still
-- works the levels out at the sandbox's rates and reports them, blow-offs included (without
-- particles here), and the other clients show that vehicle, and its blow-off, by their own options.
-- The body pieces' deficits (doors opened) are not reported: every client sees the doors. The hood's
-- melt (KEY_HOOD) is: it comes from the engine's heat over time, which a client meeting the vehicle
-- later did not see.
-- The server is also asked once for a signature of the vehicle scripts' parts (shellsQuery): the
-- parts are synced by index, so a vehicle whose parts differ here and there (a shell part that
-- failed on one side, ISnow_VehicleShells.lua) goes wrong in MP; the differences are logged.
local MP_MODULE = "ISnow"
local QUERY_WAIT_MS = 1000
local incoming = {}     -- [vehicle id] = { s, l, i, f (nil: a client without frost), g (glass clean, nil: a client
                        -- without it), h (the hood's melt, nil: a client without it), at = world hours
                        -- the report was made }
-- [vehicle id] = world hours another player scraped its frost off ("vehFrost", also the answer to
-- a query for a vehicle scraped after its last report): applied when the vehicle is next updated,
-- a vehicle not met yet included (it gets what grew back since, not the frost of a first sight)
local frostScraped = {}
local reportedVeh = {}   -- [vehicle] = { key = stages last reported, at = ms, player, held }
local mpStats = { sent = 0, received = 0, applied = 0, queries = 0, unanswered = 0, partsCheck = "not asked" }

local function queryVehicle(id)
    mpStats.queries = mpStats.queries + 1
    sendClientCommand(MP_MODULE, "vehSnowQuery", { id = id })
end

local function stateOf(v)
    if not isClient() then return v:getModData() end
    local md = v:getModData()
    if md[KEY_LEVEL] ~= nil or md[KEY_AT] ~= nil or md[KEY_ICE] ~= nil or md[KEY_CLEAR] ~= nil or md[KEY_FROST] ~= nil
            or md[KEY_HOOD] ~= nil then
        md[KEY_LEVEL], md[KEY_AT], md[KEY_ICE], md[KEY_CLEAR], md[KEY_FROST], md[KEY_HOOD] = nil, nil, nil, nil, nil, nil
    end
    local vs = v:getScript()
    local name = vs and vs:getFullName()
    local id = v:getId()
    local st = mpState[id]
    if not st or st.script ~= name then   -- a new vehicle under a freed id
        st = { script = name }
        mpState[id] = st
        if not incoming[id] then
            queryVehicle(id)
            st.askedMs = getTimestampMs()
        end
    end
    return st
end

-- Whether a local player drives v.
local function drivenHere(v)
    local d = v:getDriver()
    return d ~= nil and d:isLocalPlayer()
end

-- MP: whether v, new to this client, waits for the answer to its query (see "Multiplayer" above).
-- At the wheel here too: a player back on the server sits in their car, which this client meets
-- first at the wheel; without the report it took the ground cover and reported that to everyone (a
-- car brushed clean came back snowed-in).
local function awaitingReport(v)
    if not isClient() or pinned[v] then return false end
    local st = stateOf(v)
    if not st.askedMs or st[KEY_AT] ~= nil then return false end
    local id = v:getId()
    local t = getTimestampMs()
    local answered = incoming[id] or frostScraped[id]
    if answered or t - st.askedMs >= QUERY_WAIT_MS or t < st.askedMs then
        if not answered then mpStats.unanswered = mpStats.unanswered + 1 end
        st.askedMs = nil
        return false
    end
    return true
end

-- Drops the MP levels of vehicles not updated for MP_KEEP_HOURS (they start from the ground cover
-- again; dropped after CATCHUP_HOURS, a car blown clean came back covered).
local function purgeState(now)
    if not isClient() or (mpPurgedAt and now - mpPurgedAt < CATCHUP_HOURS and now >= mpPurgedAt) then return end
    mpPurgedAt = now
    local old = {}
    for id, st in pairs(mpState) do
        local at = st[KEY_AT]
        if not at or now - at > MP_KEEP_HOURS or now < at - CLOCK_SLACK then table.insert(old, id) end
    end
    for _, id in ipairs(old) do mpState[id] = nil end
    -- reports of vehicles never met here (the server sends every report to every client)
    old = {}
    for id, r in pairs(incoming) do
        if now - r.at > MP_KEEP_HOURS or now < r.at - CLOCK_SLACK then table.insert(old, id) end
    end
    for _, id in ipairs(old) do incoming[id] = nil end
    old = {}
    for id, at in pairs(frostScraped) do
        if now - at > MP_KEEP_HOURS or now < at - CLOCK_SLACK then table.insert(old, id) end
    end
    for _, id in ipairs(old) do frostScraped[id] = nil end
end

-- Index of the stage shown for level (0: none).
local function stageIndex(level, n)
    n = n or #STAGES
    if level <= MIN_LEVEL then return 0 end
    return math.max(1, math.min(n, math.ceil(level * n)))
end

local function stageFor(level, stages)
    stages = stages or STAGES
    local i = stageIndex(level, #stages)
    return i > 0 and stages[i] or nil
end

-- The highest level that still shows stage i (just under the next stage's range).
local function levelOfStage(i)
    return i / #STAGES - 1e-4
end

local function isOutdoors(v)
    local sq = v:getSquare()
    return ISnow.snowReaches(sq)
end

local function clamp01(x)
    return math.max(0, math.min(1, x))
end

-- Snow cover of the ground 0..1 as drawn (ISnow.groundCover: none outside the erosion winter).
local function groundCover() return ISnow.groundCover() end

-- Speed of v in km/h. getCurrentSpeedKmHour reads 0 while the vehicle's CarController is disabled
-- (BaseVehicle.getCurrentSpeedKmHour): a towed trailer, and maybe a vehicle another player drives
-- in MP (not checked in game), whose snow then never blew off here. Then the speed comes from how
-- far v moved, sampled every SPEED_SAMPLE_MS at least, taking a tile as a metre (not checked in
-- game: stats() shows both for the nearest vehicle).
local SPEED_SAMPLE_MS = 250
-- A longer gap between samples: not followed, no speed. Longer than a poll (POLL_TICKS) down to
-- 5 fps: at 2000 a poll took longer below 15 fps and the speed read 0 at every one.
local SPEED_GAP_MS = 6000
local SPEED_MAX_KMH = 300      -- faster: a jump (streamed in, moved by the server), not driving
local motion = {}   -- [vehicle] = { x, y, at = ms, kmh }

local function movedKmh(v)
    local now = getTimestampMs()
    local x, y = v:getX(), v:getY()
    local m = motion[v]
    if not m then
        motion[v] = { x = x, y = y, at = now, kmh = 0 }
        return 0
    end
    local dt = now - m.at
    if dt >= SPEED_SAMPLE_MS then
        local dx, dy = x - m.x, y - m.y
        local kmh = math.sqrt(dx * dx + dy * dy) / (dt / 1000) * 3.6
        m.kmh = (dt <= SPEED_GAP_MS and kmh <= SPEED_MAX_KMH) and kmh or 0
        m.x, m.y, m.at = x, y, now
    end
    return m.kmh
end

local function speedKmh(v)
    local moved = movedKmh(v)
    local kmh = math.abs(v:getCurrentSpeedKmHour())
    if kmh > 0 then return kmh end
    return moved
end

-- Snow and icing of a vehicle not updated for hours game hours (see the top): outdoors the ground
-- cover; under a roof its own, melting over the whole gap as a parked vehicle (engine off).
local function catchUp(level, ice, hours, temp, outdoors)
    if outdoors then
        local ground = groundCover()
        return ground, ground
    end
    local melt = INDOOR_MELT + (temp > 0 and temp * MELT_PER_DEGREE or 0)
    return clamp01(level - melt * hours), clamp01(ice - melt * ICE_MELT * hours)
end

-- The frost on a vehicle that stood outdoors (or not) at air temperature temp for long: what the
-- cold gives (a first sight, a catch-up).
local function frostFor(temp, outdoors)
    if not outdoors or temp >= FROST_BELOW then return 0 end
    return clamp01((FROST_BELOW - temp) / FROST_FULL_DEG)
end

-- Whether vehicle v has glass to frost over and to look through: its windscreen (the vanilla part
-- Windshield) installed and not broken. A trailer or a script without one, a removed or smashed
-- windscreen: no frost inside and nothing to scrape.
local function hasWindscreen(v)
    local w = v:getPartById(FROST_GLASS_PART)
    if not w or not w:getInventoryItem() then return false end
    local win = w:getWindow()
    return not (win and win:isDestroyed())
end
VehicleSnow.hasWindscreen = hasWindscreen

-- Whether the heater of v blows warm air (the vanilla Heater part: ModData active and temperature).
local function heaterOn(v)
    local h = v:getPartById("Heater")
    local md = h and h:getModData()
    return md ~= nil and md.active == true and (tonumber(md.temperature) or 1) > 0
end

-- How warm the engine of v is, 0..1: the vanilla engine temperature over ENGINE_WARM (see KEY_HOOD).
-- An engine part without that ModData (a mod's own engine) is warm while it runs.
local function engineWarmth(v)
    local e = v:getPartById("Engine")
    local md = e and e:getModData()
    local t = md and tonumber(md.temperature)
    if not t then return v:isEngineRunning() and 1 or 0 end
    return clamp01(t / ENGINE_WARM)
end
VehicleSnow.engineWarmth = engineWarmth

-- The frost on v after dt game hours at air temperature temp (see the top); opt reads the rates.
local function frostStep(v, frost, dt, temp, outdoors, opt)
    local rate = 0
    local engine = v:isEngineRunning()
    if outdoors and temp < FROST_BELOW and not engine then
        rate = math.min(1, (FROST_BELOW - temp) / FROST_FULL_DEG) / math.max(0.05, opt("VehicleFrostHours"))
    end
    if temp > 0 then rate = rate - temp / FROST_MELT_AT / math.max(0.05, opt("VehicleFrostMeltHours")) end
    if not outdoors then rate = rate - INDOOR_MELT end
    if engine then
        local thaw = 60 / math.max(0.5, opt("VehicleFrostHeaterMinutes"))
        rate = rate - (heaterOn(v) and thaw or thaw / FROST_ENGINE_SLOW)
    end
    return clamp01(frost + rate * dt)
end

-- New snow level of vehicle v, the change before clamping to 0..1 (+1 when the level jumped, which
-- resets the body pieces), the old level, the new icing level and the new frost level.
local function updateLevel(v, now)
    local md = stateOf(v)
    if isClient() then
        local id = v:getId()
        local r = incoming[id]
        if r then
            incoming[id] = nil
            local vs = v:getScript()
            -- driven here: only while this client has no levels of it (met first at the wheel)
            if r.s == (vs and vs:getFullName()) and (not drivenHere(v) or md[KEY_AT] == nil) and not pinned[v] then
                md[KEY_LEVEL], md[KEY_ICE], md[KEY_AT] = r.l, math.max(r.l, r.i), math.min(now, r.at)
                if r.f then md[KEY_FROST] = r.f end
                if r.g ~= nil then md[KEY_GLASS_CLEAN] = r.g and md[KEY_ICE] or nil end
                if r.h ~= nil then md[KEY_HOOD] = r.h > 0.001 and r.h or nil end
                mpStats.applied = mpStats.applied + 1
            end
        end
    end
    local scrapedAt = nil
    if isClient() then
        local id = v:getId()
        scrapedAt = frostScraped[id]
        frostScraped[id] = nil
    end
    -- Bare (summer, most of the year): no snow, icing, frost or hood melt on it, followed (no first
    -- sight or catch-up), no snow falling and no frost forming; only the time stamp moves, the rest
    -- below gives the same (level 0, the deficits gone) after asking every vehicle near for its
    -- square's temperature and its speed. The square's air (getAirTemperatureForSquare without a
    -- vehicle or wind chill) is never colder than the climate's temperature up to 22 C (a room and
    -- heat sources only warm it, bytecode 42.21): at FROST_BELOW and up there no frost forms anywhere.
    local at0 = md[KEY_AT]
    if not pinned[v] and not scrapedAt and md[KEY_LEVEL] == 0 and md[KEY_ICE] == 0 and md[KEY_FROST] == 0
            and md[KEY_HOOD] == nil and (md[KEY_GLASS_CLEAN] or 0) == 0
            and at0 and now >= at0 - CLOCK_SLACK and now - at0 <= CATCHUP_HOURS then
        local clim = getClimateManager()
        if not clim:isSnowing() and clim:getTemperature() >= FROST_BELOW then
            md[KEY_AT] = math.max(now, at0)   -- a clock set back: as below
            return 0, 0, 0, 0, 0
        end
    end
    local old = md[KEY_LEVEL] or 0
    local level = md[KEY_LEVEL]
    local ice = md[KEY_ICE] or old   -- saves from before the icing: as much as snow
    local at = md[KEY_AT]
    local frost = md[KEY_FROST]
    local clim = getClimateManager()
    local sq = v:getSquare()
    local outdoors = ISnow.snowReaches(sq)
    local temp = sq and clim:getAirTemperatureForSquare(sq) or clim:getTemperature()
    -- MP at the wheel at the sandbox's rates, not this player's own: the levels are reported
    local opt = (isClient() and drivenHere(v)) and ISnow.worldOpt or ISnow.opt
    -- the hood's level in MP always with the server's on/off (reported, h); a player who turned the
    -- melt off only does not see it (hoodShown)
    local hoodOn = (isClient() and ISnow.worldOpt or opt)("VehicleHoodMelt")
    local delta
    local stamp = now   -- KEY_AT from here on
    local hoodMelt = 0  -- the hood's own melt from the engine's heat (KEY_HOOD), only while followed

    if pinned[v] then
        level, ice = pinned[v][1], pinned[v][2]
        delta = level - old
    elseif level == nil or at == nil or now < at - CLOCK_SLACK then
        -- first sight (or a save from before at): the icing too
        level = outdoors and groundCover() or 0
        ice = level
        frost = frostFor(temp, outdoors)
        delta = 1
    elseif now - at > CATCHUP_HOURS then
        level, ice = catchUp(level, ice, now - at, temp, outdoors)
        frost = outdoors and frostFor(temp, outdoors) or frostStep(v, frost or 0, now - at, temp, false, opt)
        -- outdoors the body pieces take the ground cover too (a jump resets their deficits)
        delta = outdoors and 1 or level - old
    else
        -- MP: the server's clock sync set this client's clock back (CLOCK_SLACK): no time passed, and
        -- the time up to at is not counted twice. Taken for a first sight, it put the ground cover
        -- back on a vehicle that had just blown its snow off.
        local dt = now - at
        if dt < 0 then dt, stamp = 0, at end
        local fall, melt = 0, 0
        if outdoors and clim:isSnowing() then
            fall = clim:getSnowIntensity() / math.max(0.1, opt("VehicleSnowHours"))
        end
        if temp > 0 then melt = temp * MELT_PER_DEGREE end
        if not outdoors then melt = melt + INDOOR_MELT end
        local rate = fall - melt
        if v:isEngineRunning() then rate = rate - ENGINE_MELT end
        local speed = speedKmh(v)
        if speed > BLOW_KMH then rate = rate - (speed - BLOW_KMH) * BLOW_PER_KMH end
        delta = rate * dt
        level = clamp01(level + delta)
        if level > 0 and hoodOn then   -- no snow (all summer): no engine asked
            hoodMelt = engineWarmth(v) * dt / math.max(0.05, opt("VehicleHoodMeltHours"))
        end
        if speed > BLOWOFF_KMH then
            -- no heap builds up at speed: up to stage BLOWOFF_KEEP, and above it no more than there is
            -- (it would refill a stage while the next waits to blow off)
            if stageIndex(old) <= BLOWOFF_KEEP then
                level = math.min(level, levelOfStage(BLOWOFF_KEEP))
            else
                level = math.min(level, old)
            end
        end
        -- a save from before the frost: what the cold gives
        frost = frost and frostStep(v, frost, dt, temp, outdoors, opt) or frostFor(temp, outdoors)
    end
    -- the icing has the snow's level (one model for both, see showNow); kept as a key for the glass
    -- wipe, the brush and MP reports
    ice = level
    frost = frost or 0
    if scrapedAt then
        -- scraped by another player: no more than grew back since (any branch above, a first
        -- sight too)
        frost = math.min(frost, frostStep(v, 0, math.max(0, now - scrapedAt), temp, outdoors, opt))
        md[KEY_GLASS_CLEAN] = ice
    end
    local clean = md[KEY_GLASS_CLEAN]
    if clean then
        -- frosted again by new icing or the ground cover; a thaw lowers the mark
        if delta >= 1 or ice > clean + GLASS_REICE then clean = nil else clean = math.min(clean, ice) end
        md[KEY_GLASS_CLEAN] = clean
    end

    -- the hood: its deficit follows the body as a door's does (pieceStage: snow and melt keep it, a
    -- jump of the level resets it), plus the engine's melt; none with the option off
    local hood = md[KEY_HOOD]
    if not hoodOn then
        hood = nil
    elseif hood or hoodMelt > 0 then
        local piece = math.max(0, math.min(level, math.max(0, old - (hood or 0)) + delta - hoodMelt))
        hood = level - piece
        -- a poll is a few game seconds, so the engine melts well under 0.001 at a time: a deficit
        -- that small is dropped only when the engine does not melt (it never grew from none; seen
        -- 2026-10-04, ~0.0003 h a poll at speed 1)
        if hood <= 0 or (hood <= 0.001 and hoodMelt <= 0) then hood = nil end
    end

    md[KEY_LEVEL] = level
    md[KEY_ICE] = ice
    md[KEY_FROST] = frost
    md[KEY_HOOD] = hood
    md[KEY_AT] = stamp
    return level, delta, old, ice, frost
end

-- MP: reports the levels of v while a local player drives it, when the stage of either changed
-- (see "Multiplayer" above); the first poll at the wheel reports at once. A player's reports go
-- REPORT_GAP_MS apart at least: the server drops one sooner than its MIN_GAP_MS
-- (ISnow_VehicleSnowServer.lua), so a change held back here goes at a later poll instead, the
-- first one after the driver got out too. The levels go again every REPORT_REFRESH_MS at the
-- wheel, in case a report got lost.
local REPORT_GAP_MS = 500
local REPORT_REFRESH_MS = 30000
local lastReportMs = {}   -- [local player] = getTimestampMs() of its last report

local function reportLevels(v, level, ice, frost)
    local md = stateOf(v)
    local clean = md[KEY_GLASS_CLEAN] ~= nil
    local hood = md[KEY_HOOD] or 0
    local key = stageIndex(math.max(0, level - hood)) * 10000000 + (clean and 1000000 or 0) + stageIndex(level) * 10000
        + stageIndex(ice) * 100 + math.ceil((frost or 0) * FROST_REPORT_STEPS)
    local t = getTimestampMs()
    local r = reportedVeh[v]
    local d = v:getDriver()
    local atWheel = d and d:isLocalPlayer()
    if not atWheel then
        -- the local driver got out with a change held back (REPORT_GAP_MS): it still goes, once
        if d or not (r and r.held) or r.key == key then
            reportedVeh[v] = nil
            return
        end
        d = r.player
    elseif r and r.key == key and t - r.at < REPORT_REFRESH_MS and t >= r.at then
        return
    end
    local last = lastReportMs[d]
    if last and t - last < REPORT_GAP_MS and t >= last then
        if not r then
            r = { at = t }
            reportedVeh[v] = r
        end
        r.held, r.player = true, d
        return
    end
    lastReportMs[d] = t
    reportedVeh[v] = atWheel and { key = key, at = t, player = d } or nil
    local vs = v:getScript()
    mpStats.sent = mpStats.sent + 1
    sendClientCommand(d, MP_MODULE, "vehSnow", { id = v:getId(), s = vs and vs:getFullName() or "", l = level, i = ice, f = frost,
        g = clean, h = hood })
end

-- Whether the budget of this tick allows one more model switch; marks the show() cut short if not.
-- budget.defer: the vehicle is out of sight, nothing switches on it now.
local function canToggle()
    if budget.defer then
        budget.out = true
        return false
    end
    if budget.toggles >= TOGGLE_MIN and getTimestampMs() - budget.start >= TOGGLE_MS then
        budget.out = true
        return false
    end
    return true
end

-- Every REASSERT_POLLS polls (about 2 s) showOn shows the models it has shown again. The engine
-- drops every model of a vehicle in BaseVehicle.setScript(), which addToWorld -> createPhysics
-- calls when the same vehicle object goes into the world again, and keeps its parts, so `shown`
-- said a model was visible that was gone (a car without any snow until its stage changed; seen
-- 2026-10-04). For a model still there BaseVehicle.setModelVisible only finds it and returns
-- (bytecode 42.21); a dropped one comes back, which rebuilds the vehicle's models: so it goes
-- through the budget of the tick like any switch (cheap while the models are there: the budget
-- runs out by time), and what is left waits for the next time.
local REASSERT_POLLS = 4
local reassert = false

-- Our own switches of the snow parts' models go to the engine's setModelVisible past our hook
-- (ISnowSetModelVisible, once hookSetModelVisible is in): what the hook notes (modelVis) is only
-- read for the source parts, never for the snow parts.
local rawSetVisible = false

-- A switch rebuilds the vehicle's models (ModelManager.addVehicle: a new VehicleModelInstance), and
-- the new one has no dents, scratches, broken glass or blood: BaseVehicle.doDamageOverlay sets them
-- on the instance, and the engine runs it only after a part changes (updateDamageOverlayLater, done
-- in BaseVehicle.update, bytecode 42.21). Every vehicle that got snow looked repaired from then on,
-- with or without snow (Workshop comment, 2026-10-08). The flag redoes them on the vehicle's next
-- update, once for any number of switches.
local function redoDamage(part)
    local v = part:getVehicle()
    if v and v.updateDamageOverlayLater then v:updateDamageOverlayLater() end
end

local function setVisible(part, modelId, visible)
    local r
    if rawSetVisible then r = part:ISnowSetModelVisible(modelId, visible) else r = part:setModelVisible(modelId, visible) end
    redoDamage(part)
    return r
end

-- Shows variant id (nil: none) of the models named slot .. variant of a snow part of a vehicle with
-- script vs; key: where shown[part] keeps it, slot (the default) or slot .. ICE for the icing models
-- and slot .. GLASS for the glass frost ones, which show next to the snow ones.
local function showOn(vs, part, id, slot, key)
    slot = slot or ""
    key = key or slot
    local s = shown[part]
    if not s then
        s = {}
        shown[part] = s
    end
    local cur = s[key]
    if cur == id then
        if id and reassert and not budget.defer and canToggle() then
            setVisible(part, slot .. id, true)
            budget.toggles = budget.toggles + 1
        end
        return
    end
    if not canToggle() then return end
    if cur then
        setVisible(part, slot .. cur, false)
        budget.toggles = budget.toggles + 1
    end
    s[key] = nil
    if id then
        if not canToggle() then return end
        -- the shell ModelScript is made on first use (ISnow_VehicleShells.lua, Shells.ensure); without
        -- it the engine's model info would have no script
        local sp = part:getScriptPart()
        local model = sp and sp:getModelById(slot .. id)
        -- the script gets a variant's models on its first use too (Shells.addVariant)
        if sp and not model and ISnow.VehicleShells.addVariant and ISnow.VehicleShells.addVariant(vs, id) then
            model = sp:getModelById(slot .. id)
        end
        if not (model and ISnow.VehicleShells.ensure(model:getFile())) then
            stats.noShellModel = stats.noShellModel + 1
            return
        end
        setVisible(part, slot .. id, true)
        budget.toggles = budget.toggles + 1
    end
    s[key] = id
end

-- Whether model modelId of part is visible: as last set from Lua through VehiclePart:setModelVisible
-- / setAllModelsVisible / setInventoryItem (the hooks at the end of this file; KI5 picks bumper,
-- roof, armour variants that way, AviationCore the rotor blade position), else as the engine sets
-- it up: VehicleParts.setScript calls setInventoryItem(item) on every part, which shows all its
-- models when the script part has setAllModelsVisible (the default) and an item is in, else hides
-- them all; a part without items (no itemType) has none, so its models show only when Lua shows
-- them (bytecode 42.21). Taking those as shown put snow on all 24 blade positions of the UH-1B's
-- rotor parts (2026-10-05).
local function modelVisible(part, modelId)
    local t = modelVis[part]
    local v = t and modelId and t[modelId]
    if v ~= nil then return v end
    return part:isSetAllModelsVisible() and part:getInventoryItem() ~= nil
end

local function installed(part)
    if part:getInventoryItem() then return true end
    local types = part:getItemType()
    return types == nil or types:isEmpty()   -- a part without items is always there
end

-- Whether the snow and the icing on body piece src show; then the reason the snow does not and
-- whether it was shaken off (DOOR: by an open door, see pieceStage). An open door (or one of its
-- children) shows nothing while open and sheds one stage; a removed piece or an open / broken
-- window sheds everything.
local DOOR = "door"
local function pieceVisible(src)
    local cat = src:getCategory()
    -- no category: KI5 truck beds live in GloveBox (its interior model is not given snow)
    if cat and not PIECE_CATEGORIES[string.lower(cat)] then return nil, nil, "category " .. tostring(cat) end
    if spinning(src, getTimestampMs()) then return nil, nil, src:getId() .. " models switching (spinning)", true end
    local open = nil
    local p = src
    while p do
        if not installed(p) then return nil, nil, p:getId() .. " not installed", true end
        local w = p:getWindow()
        if w and (w:isOpen() or w:isDestroyed()) then return nil, nil, p:getId() .. " window open/broken", true end
        local door = p:getDoor()
        if not open and door and door:isOpen() then open = p:getId() .. " open" end
        p = p:getParent()
    end
    if open then return nil, true, open, DOOR end
    return true, true
end

-- Whether body piece src is the hood (HOOD_PART) or sits on it (a child of it: KI5 hood armour...).
local function isHood(src)
    local p = src
    while p do
        if p:getId() == HOOD_PART then return true end
        p = p:getParent()
    end
    return false
end

-- Snow stage id for body piece srcId of vehicle v, and whether the piece shows its icing. id is the
-- body's stage; lv = { level, delta, old } as from updateLevel, nil when id was set from the console
-- (then the deficits are ignored).
-- The piece level is the body's minus the deficit, and changes by the same delta as the body
-- but is clamped to 0..body level: snow and melt keep the deficit, a body already at 1 lets the
-- piece catch up.
local function pieceStage(v, srcId, src, id, lv)
    if piecesOff or not ISnow.opt("VehicleSnowPieces") then return nil, false end
    -- one pass: no window panes (the snow does not settle on glass, only its edge and a film would show)
    if src:getWindow() and ISnow.opt("VehicleSnowOnePass") then return nil, false end
    local ok, iceOk, _, shaken = pieceVisible(src)
    if not id then return nil, iceOk end
    if lv == nil then return ok and id or nil, iceOk end
    local level = lv[1]
    local md = stateOf(v)
    local clear = md[KEY_CLEAR]
    local doors = doorsOpened[v]
    if shaken and shaken ~= DOOR then
        if doors then doors[srcId] = nil end
        if level > 0 and not clear then
            clear = {}
            md[KEY_CLEAR] = clear
        end
        if clear then clear[srcId] = level > 0 and level or nil end
        return nil, iceOk
    end
    local d = clear and clear[srcId]
    if d then
        local piece = math.max(0, math.min(level, math.max(0, lv[3] - d) + lv[2]))
        d = level - piece
        if d <= 0.001 then d = nil end
        clear[srcId] = d
    end
    -- the hood's melt from the engine (KEY_HOOD): the hood and what sits on it show the lesser snow
    local less = d or 0
    local hood = md[KEY_HOOD]
    -- (hidden by this player: the hood shows the body's snow, the level stays as reported)
    if hood and isHood(src) and ISnow.opt("VehicleHoodMelt") then less = math.max(less, hood) end
    if shaken then
        -- an open door, once per opening: one stage off, as at speed, and none at BLOWOFF_KEEP and
        -- below; the middle of the stage below, as dropStage
        if not (doors and doors[srcId]) then
            if not doors then
                doors = {}
                doorsOpened[v] = doors
            end
            doors[srcId] = true
            local i = stageIndex(level - less)
            if i > BLOWOFF_KEEP then
                d = level - (i - 1.5) / #STAGES
                if not clear then
                    clear = {}
                    md[KEY_CLEAR] = clear
                end
                clear[srcId] = d
            end
        end
        return nil, iceOk
    end
    if doors then doors[srcId] = nil end
    return ok and stageFor(level - less) or nil, iceOk
end

-- Whether a part has a model that is not static, i.e. can be animated (a static model gets no
-- animation player, BaseVehicle$ModelInfo.getAnimationPlayer).
local function isAnimatable(part)
    local sp = part:getScriptPart()
    if not sp then return false end
    local a = animatable[sp]
    if a == nil then
        a = false
        local sm = getScriptManager()
        for k = 0, sp:getModelCount() - 1 do
            local ms = sm:getModelScript(sp:getModel(k):getFile())
            if ms and not ms:isStatic() then a = true end
        end
        animatable[sp] = a
    end
    return a
end

-- The topmost parent of a part (itself without one): its first model's animation player is the one
-- the whole tree uses (BaseVehicle$ModelInfo.getAnimationPlayer).
local function rootOf(part)
    while part:getParent() do part = part:getParent() end
    return part
end

-- Milliseconds since the last animation in the tree of src started, if under HIDE_MS.
local function animating(src, now)
    local at = anims[rootOf(src)]
    if at and now - at < HIDE_MS then return now - at end
    return nil
end

-- The snow stage id and icing stage iceId on the body, on every wheel that has a tire on it and on
-- every body piece that shows snow, and the glass frost stage glassId on the body and the body
-- pieces that show icing (installed, closed, glass whole). lv as for pieceStage. hidden: none of it
-- (out of sight), the body pieces still keep their deficits. The icing has the snow's level, so
-- body, wheels and pieces show the snow and the icing in one model (oneModel: BOTH_OF), the snow
-- model alone with the icing off, the icing model only when set alone from the console.
-- clean: the glass was wiped, body and pieces show their icing without it (cleanOf).
-- Every model switched on a vehicle rebuilds all of its models (TOGGLE_MIN), so one model a piece
-- instead of two takes the work of a full show to under half.
local function oneModel(id, iceId)
    if id then return iceId and BOTH_OF[id] or id end
    return iceId
end

-- showOn slot and keys of model k of a body piece: { "m" .. k .. "_", .. ICE, .. GLASS }, made once
-- (a poll goes through every model of every piece of every vehicle near, and the same few model
-- indices serve every vehicle)
local PIECE_SLOTS = {}
local function pieceSlot(k)
    local keys = PIECE_SLOTS[k]
    if not keys then
        local slot = "m" .. k .. "_"
        keys = { slot, slot .. ICE, slot .. GLASS }
        PIECE_SLOTS[k] = keys
    end
    return keys
end

local function showNow(v, id, iceId, lv, hidden, glassId, clean)
    local part = v:getPartById(PART)
    if not part then return false end
    local bodyId = oneModel(id, iceId)
    if clean then bodyId = cleanOf(bodyId) end
    local vs = v:getScript()
    showOn(vs, part, not hidden and bodyId or nil)
    -- the icing layer of earlier versions (or of a Lua reload) goes
    showOn(vs, part, nil, "", ICE)
    showOn(vs, part, not hidden and glassId or nil, "", GLASS)
    local wheelsOn = ISnow.opt("VehicleSnowWheels")
    for _, w in ipairs(ISnow.VehicleShells.wheels(v)) do
        local wheel = v:getPartById(w.part)
        if wheel then
            local tire = v:getPartById(w.tire)
            local on = wheelsOn and w.bound and tire and tire:getInventoryItem() ~= nil
            on = on and not hidden
            showOn(vs, wheel, on and oneModel(id, iceId) or nil)
            showOn(vs, wheel, nil, "", ICE)
        end
    end
    local now = getTimestampMs()
    for _, piece in ipairs(ISnow.VehicleShells.pieces(vs)) do
        local snow = v:getPartById(PIECE_PREFIX .. piece.src)
        local src = v:getPartById(piece.src)
        if snow and src then
            local pieceId, iceOk = pieceStage(v, piece.src, src, id, lv)
            local sp = src:getScriptPart()
            local busy = hidden or animating(src, now)
            for _, k in ipairs(piece.models) do
                local model = sp and k < sp:getModelCount() and sp:getModel(k)
                local vis = model and modelVisible(src, model:getId())
                -- an open door shakes the snow off and the icing with it (one level); the icing
                -- alone only from the console (id nil)
                local on = vis and (pieceId and oneModel(pieceId, iceId) or (not id and iceOk and iceId)) or nil
                if clean then on = cleanOf(on) end
                local onGlass = vis and iceOk and piece.glass and piece.glass[k] and glassId or nil
                stats.pieces = stats.pieces + 1
                if on then stats.piecesShown = stats.piecesShown + 1 end
                local keys = pieceSlot(k)
                showOn(vs, snow, not busy and on or nil, keys[1])
                showOn(vs, snow, nil, keys[1], keys[2])
                showOn(vs, snow, not busy and onGlass or nil, keys[1], keys[3])
            end
        end
    end
    return true
end

-- showNow within the budget of this tick (see TOGGLE_MIN): cut short, v is pending and shown again
-- from the same state on the next ticks, its body pieces with no change of level (delta 0), so the
-- deficits move once.
local function show(v, id, iceId, lv, hidden, glassId, clean)
    -- also what was pending from before Viewpoint's view came on
    if viewpoint() then id, iceId, lv, glassId, clean = nil, nil, nil, nil, nil end
    budget.out = false
    budget.defer = unseen[v] or false
    local had = showNow(v, id, iceId, lv, hidden, glassId, clean)
    budget.defer = false
    if budget.out then
        stats.deferred = stats.deferred + 1
        pending[v] = { id, iceId, lv and lv[1], lv and lv[4], hidden, glassId, clean }
    else
        pending[v] = nil
    end
    return had
end

local outOfSight   -- below

-- The pending vehicles in sight, while the budget lasts.
local function showPending()
    for v, p in pairs(pending) do
        if budget.toggles >= TOGGLE_MIN and getTimestampMs() - budget.start >= TOGGLE_MS then return end
        if unseen[v] then
            -- went out of sight since (the sight test only looks at snowy vehicles)
            unseen[v] = outOfSight(v) or nil
        end
        if not unseen[v] then
        local lv = p[3] and { p[3], 0, p[3], p[4] } or nil
        local pieces, piecesShown = stats.pieces, stats.piecesShown
        show(v, p[1], p[2], lv, p[5], p[6], p[7])
        stats.pieces, stats.piecesShown = pieces, piecesShown   -- the counts of the last poll
        end
    end
end

local function forEachVehicleNear(x, y, r, fn)
    local r2 = r * r
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        local dx, dy = v:getX() - x, v:getY() - y
        local d2 = dx * dx + dy * dy
        if d2 <= r2 then fn(v, d2) end
    end
end

-- How much a local player sees vehicle v, 0..1: its alpha for the player who sees it best. The
-- game fades vehicles out of sight as it does zombies (IsoObject alpha per player, the model drawn
-- with it); the shells ignore that (vehicle shaders get no Alpha, isnow_vehiclesnow.frag), so the
-- snow stayed in the air where the vehicle had faded. The vehicle a player sits in counts as seen;
-- if it reads as faded, alpha is not what fades vehicles in this game version and the snow is
-- never hidden (sightBroken, see stats()).
local function seenAlpha(v)
    local best = 0
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p then
            local a = v:getAlpha(i)
            if p:getVehicle() == v then
                if a < SEEN_ALPHA and not sightBroken then
                    sightBroken = true
                    print(string.format("[ImmersiveSnow] vehicle alpha %.2f for its driver: not hiding snow out of sight", a))
                end
                return 1
            end
            best = math.max(best, a)
        end
    end
    return best
end

function outOfSight(v)
    -- Viewpoint's view (with the submod's bridge too, which keeps the shells on) is not the isometric
    -- one the alpha is for: the alpha steps toward its target only in BaseVehicle.render
    -- (IsoObject.updateAlpha, bytecode 42.21), which the view skips, so it stayed as it was when the
    -- view came on, and a vehicle out of sight then kept the snow of that moment (Workshop comment
    -- 2026-10-10: "in fpv snow stays as it was at the moment of entering fpv")
    return not sightOff and not sightBroken and not (ISnow.Viewpoint and ISnow.Viewpoint.active())
        and seenAlpha(v) < SEEN_ALPHA
end

-- Starts blowing the snow above stage BLOWOFF_KEEP off vehicle v (stepped in onTick, see
-- stepBlowing): lead = when the running lead began (nil while waiting), fast / slow = ms at / below
-- speed while waiting, need = fast ms before the next lead, burst = when the last burst ends,
-- chunks / puffs = particles owed (fractions carry over).
local function startBlow(v)
    local now = getTimestampMs()
    local ext = v:getScript():getExtents()
    local area = math.max(0.4, math.min(2.5, ext:x() * ext:z() / BLOWOFF_REF_AREA))
    blowing[v] = { last = now, area = area, fast = 0, slow = 0, need = BLOWOFF_START_MS, burst = 0,
        chunks = 0, puffs = 0 }
    stats.blowOffs = stats.blowOffs + 1
end

local polledViewpoint = false   -- Viewpoint's view as the last poll had it (asleep, below)

local function poll()
    local p = getSpecificPlayer(0)
    if not p then return end
    polledViewpoint = viewpoint()
    local now = getGameTime():getWorldAgeHours()
    local enabled = ISnow.opt("VehicleSnow")
    -- MP: the vehicles near are followed even while this player hides vehicle snow (Options >
    -- Mods), and one a local player drives is reported: the others see it as the sandbox says.
    -- Not only the driven one: a vehicle met first at the wheel that the server has no report of
    -- starts from the ground cover, and that goes to everyone.
    local reporting = isClient() and ISnow.worldOpt("VehicleSnow")
    local frostOn = ISnow.opt("VehicleFrost")
    local near, noPart, visible, hiddenN = 0, 0, 0, 0
    stats.pieces, stats.piecesShown = 0, 0
    purgeState(now)
    local nowSnowy = {}
    forEachVehicleNear(p:getX(), p:getY(), RADIUS, function(v)
        near = near + 1
        local id, iceId, glassId, lv, clean = nil, nil, nil, nil, nil
        local forced = forcedModel[v]
        if forced then
            local kind = string.sub(forced, 1, 1)
            if kind == "i" or kind == "n" then iceId = forced elseif kind == "g" then glassId = forced else id = forced end
        elseif (enabled or reporting or frostOn) and not awaitingReport(v) then
            lv = { updateLevel(v, now) }
            if isClient() then reportLevels(v, lv[1], lv[4], lv[5]) end
            if (enabled or drivenHere(v)) and not pinned[v] and not blowing[v] and stageIndex(lv[1]) > BLOWOFF_KEEP
                    and speedKmh(v) > BLOWOFF_KMH then
                startBlow(v)
            end
            -- a vehicle without a mask (a burnt wreck) has no glass to tell (ISnow_VehicleShells.lua)
            if frostOn and ISnow.opt("VehicleFrostGlass") and ISnow.VehicleShells.masked(v:getScript()) then
                glassId = stageFor(lv[5], GLASS_STAGES)
            end
            if enabled then
                id = stageFor(lv[1])
                iceId = ISnow.opt("VehicleSnowIce") and stageFor(lv[4], ICE_STAGES) or nil
                clean = stateOf(v)[KEY_GLASS_CLEAN] ~= nil
            else
                lv = nil
            end
        end
        if viewpoint() then id, iceId, glassId, lv, clean = nil, nil, nil, nil, nil end
        if not id and not iceId and not glassId and bare[v] then
            -- nothing shown and nothing to show: show() would only find every model hidden already
            unseen[v] = nil
            if bare[v] == NO_PART then noPart = noPart + 1 end
            return
        end
        local hidden = outOfSight(v)
        unseen[v] = hidden or nil
        -- out of sight: worked out (body piece deficits), switched once it is seen
        local hasPart = show(v, id, iceId, lv, false, glassId, clean)
        if not hasPart then noPart = noPart + 1 end
        if id or iceId or glassId then
            bare[v] = nil
            nowSnowy[v] = { id, iceId, lv and lv[1], lv and lv[4], glassId, clean }
        elseif not pending[v] then
            bare[v] = hasPart or NO_PART
        end
        if hidden then
            hiddenN = hiddenN + 1
        elseif id or iceId or glassId then
            visible = visible + 1
        end
    end)
    stats.near, stats.noPart, stats.visible, stats.unseen = near, noPart, visible, hiddenN
    snowy = nowSnowy
end

-- Runs on OnTickEvenPaused, which fires before IsoWorld.update in the same frame (OnTick fires
-- after it). A model made visible gets a new BaseVehicle.ModelInfo whose renderTransform is the
-- identity until BaseVehicle.updateTransform runs in the vehicle update, so a model shown after
-- that update, or while the game is paused, is drawn once at mesh scale (~70x too big).
local tickCounter = 0
local pollNow = false
local pollCount = 0

-- Lowers the snow level in state md to new (never raises it). Body pieces with less snow (a
-- deficit, see pieceStage) keep theirs: the deficit shrinks by the same amount, down to none.
local function lowerLevel(md, new)
    local level = md[KEY_LEVEL] or 0
    if new >= level then return end
    md[KEY_LEVEL] = new
    local clear = md[KEY_CLEAR]
    if clear then
        for src, d in pairs(clear) do
            d = d - (level - new)
            clear[src] = d > 0.001 and d or nil
        end
    end
    local hood = md[KEY_HOOD]
    if hood then
        hood = hood - (level - new)
        md[KEY_HOOD] = hood > 0.001 and hood or nil
    end
end

-- Takes one stage of snow off vehicle v if it is above BLOWOFF_KEEP; whether it did.
local function dropStage(v)
    local md = stateOf(v)
    local i = stageIndex(md[KEY_LEVEL] or 0)
    if i <= BLOWOFF_KEEP then return false end
    -- the middle of the stage below: snow that fell since the last poll (added in updateLevel) must
    -- not lift it straight back
    lowerLevel(md, (i - 1.5) / #STAGES)
    return true
end

local function lerp(r, t)
    return r[1] + (r[2] - r[1]) * t
end

-- Steps the blow-offs (see BLOWOFF_LEAD_MS): waits for enough time at speed, runs the lead, drops
-- the stage with a burst, and throws the particles of the lead and the burst.
local function stepBlowing(now)
    for v, b in pairs(blowing) do
        local dt = now - b.last
        local fast = speedKmh(v) >= BLOWOFF_KMH * BLOWOFF_SLOW
        local above = stageIndex(stateOf(v)[KEY_LEVEL] or 0) > BLOWOFF_KEEP
        if b.lead and (not fast or not above) then
            b.lead = nil          -- slowed down (or the snow went otherwise): start the count over
            b.need = BLOWOFF_START_MS
        end
        if b.lead then
            if now - b.lead >= BLOWOFF_LEAD_MS then
                b.lead = nil
                if dropStage(v) then
                    b.burst = now + BLOWOFF_BURST_MS
                    pollNow = true
                    if ISnow.BlowOff and not unseen[v] and ISnow.opt("VehicleSnow") and ISnow.opt("BlowOffSound") then
                        ISnow.BlowOff.sound(v)
                    end
                end
                b.fast, b.slow, b.need = 0, 0, BLOWOFF_PAUSE_MS
            end
        else
            if fast then
                b.fast, b.slow = b.fast + dt, 0
            else
                b.fast, b.slow = 0, b.slow + dt
            end
            if above and b.fast >= b.need then b.lead = now end
        end
        local rc, rp = 0, 0   -- particle rate, of the full one
        if now < b.burst then rc, rp = 1, 1 end
        if b.lead then
            local t = (now - b.lead) / BLOWOFF_LEAD_MS
            rc, rp = rc + lerp(BLOWOFF_LEAD_CHUNKS, t), rp + lerp(BLOWOFF_LEAD_PUFFS, t)
        end
        if pinned[v] or (not b.lead and now >= b.burst and (not above or b.slow >= BLOWOFF_PAUSE_MS)) then
            blowing[v] = nil
        elseif rc > 0 or rp > 0 then
            local f = dt / 1000 * b.area * ISnow.opt("BlowOffAmount")
            b.chunks = b.chunks + f * BLOWOFF_CHUNKS * rc
            b.puffs = b.puffs + f * BLOWOFF_PUFFS * rp
            local c, p = math.floor(b.chunks), math.floor(b.puffs)
            b.chunks, b.puffs = b.chunks - c, b.puffs - p
            -- no particles while this player hides vehicle snow (followed only for the report)
            if ISnow.BlowOff and (c > 0 or p > 0) and not unseen[v] and ISnow.opt("VehicleSnow") then
                ISnow.BlowOff.emit(v, c, p)
            end
        end
        b.last = now
    end
end

-- MP: what the server sends (see "Multiplayer" above).

-- Whether online id is one of this client's players.
local function isLocalId(id)
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and p:getOnlineID() == id then return true end
    end
    return false
end

local MAX_PART_DIFFS = 30   -- vehicle scripts with other parts than the server's, logged at most

-- The server's part counts against this client's, in console.txt.
local function logPartDiffs(theirs)
    local mine = ISnow.VehicleShells.partCounts()
    local diffs = {}
    for name, n in pairs(theirs) do
        if mine[name] ~= n then table.insert(diffs, name .. ": server " .. tostring(n) .. ", here " .. tostring(mine[name])) end
    end
    for name, n in pairs(mine) do
        if theirs[name] == nil then table.insert(diffs, name .. ": server none, here " .. tostring(n)) end
    end
    table.sort(diffs)
    mpStats.partsCheck = "differs in " .. #diffs .. " vehicle scripts (console.txt)"
    print("[ImmersiveSnow] vehicle parts differ from the server's in " .. #diffs ..
        " vehicle scripts; those vehicles may go wrong in MP (a mod missing or another version on one side?)")
    for k = 1, math.min(#diffs, MAX_PART_DIFFS) do print("[ImmersiveSnow]   " .. diffs[k]) end
end

local function onServerCommand(module, command, args)
    if module ~= MP_MODULE or type(args) ~= "table" then return end
    if command == "vehSnow" then
        local id, l, i = tonumber(args.id), tonumber(args.l), tonumber(args.i)
        if not id or not l or not i or type(args.s) ~= "string" then return end
        if args.from ~= nil and isLocalId(tonumber(args.from)) then return end
        mpStats.received = mpStats.received + 1
        local f = tonumber(args.f)
        local g = nil
        if type(args.g) == "boolean" then g = args.g end
        local h = tonumber(args.h)
        incoming[id] = { s = args.s, l = clamp01(l), i = clamp01(i), f = f and clamp01(f) or nil, g = g,
            h = h and clamp01(h) or nil, at = getGameTime():getWorldAgeHours() - math.max(0, tonumber(args.age) or 0) }
        pollNow = true
    elseif command == "vehFrost" then
        local id = tonumber(args.id)
        if not id or (args.from ~= nil and isLocalId(tonumber(args.from))) then return end
        frostScraped[id] = getGameTime():getWorldAgeHours() - math.max(0, tonumber(args.age) or 0)
        if incoming[id] then incoming[id].f, incoming[id].g = 0, true end
        pollNow = true
    elseif command == "shells" then
        local sig, n = ISnow.VehicleShells.signature()
        if sig == tonumber(args.sig) and n == tonumber(args.n) then
            mpStats.partsCheck = "same as the server's (" .. n .. " vehicle scripts)"
        else
            mpStats.partsCheck = "differs, asking which"
            sendClientCommand(MP_MODULE, "shellsDetailQuery", { ask = true })
        end
    elseif command == "shellsDetail" and type(args.counts) == "table" then
        logPartDiffs(args.counts)
    end
end
Events.OnServerCommand.Add(function(module, command, args)
    local ok, err = pcall(onServerCommand, module, command, args)
    if not ok then
        stats.errors = stats.errors + 1
        lastError = "server command: " .. tostring(err)
    end
end)

-- Asks for the parts signature once a player is in the world.
local partsAsked = false
local function askParts()
    if partsAsked or not getSpecificPlayer(0) then return end
    partsAsked = true
    if not isClient() then return end
    mpStats.partsCheck = "asked"
    -- never an empty table: the server gets nil for one (seen in game) and drops the command
    sendClientCommand(MP_MODULE, "shellsQuery", { ask = true })
end

local lastTickMs, lastHitchLog = nil, 0

-- A long frame since the last tick: logged with our part of the last one (vehicles: ms, model
-- switches, variants added, shell models made; zombies: model rebuilds, ms), only when there was a
-- part of ours: the engine's own hitches (loading cells, saving) all summer long read as the mod at
-- work (TheShreddieH, 2026-10-05: "in July my console still has this mod firing").
local HITCH_OURS_MS = 5
local function logHitch(t)
    local ours = (perf.toggles or 0) + (perf.variants or 0) + (perf.shells or 0) + (perf.zRebuilds or 0) > 0
        or (perf.vehMs or 0) + (perf.zMs or 0) >= HITCH_OURS_MS
    if ours and lastTickMs and t - lastTickMs >= HITCH_MS and t - lastHitchLog >= HITCH_LOG_MS then
        lastHitchLog = t
        print(string.format("[ImmersiveSnow] long frame %d ms; ours before it: vehicles %d ms (%d switches, %d variants, %d shells), zombies %d rebuilds %d ms",
            t - lastTickMs, perf.vehMs or 0, perf.toggles or 0, perf.variants or 0, perf.shells or 0,
            perf.zRebuilds or 0, perf.zMs or 0))
    end
    lastTickMs = t
end

-- The tables keyed by vehicles and parts keep every vehicle met (Kahlua has no weak tables, see
-- ISnow.prune): every SWEEP_POLLS polls the vehicles no longer loaded go, with their parts. One
-- unloaded and loaded again is a new object, met anew.
local SWEEP_POLLS = 40
local function sweep()
    local live = ISnow.liveVehicles()
    local function vehicleLive(v) return live[v] end
    -- a part kept when its vehicle is not known: a shown model forgotten would stay visible
    local function partLive(part)
        local v = part.getVehicle and part:getVehicle()
        return v == nil or live[v]
    end
    for _, t in ipairs({ pinned, forcedModel, doorsOpened, blowing, unseen, bare, snowy, pending, reportedVeh, motion }) do
        ISnow.prune(t, vehicleLive)
    end
    for _, t in ipairs({ shown, modelVis, anims, switches }) do ISnow.prune(t, partLive) end
    local players = {}
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p then players[p] = true end
    end
    ISnow.prune(lastReportMs, function(p) return players[p] end)
end

local function tick()
    if isGamePaused() then return end
    tickCounter = tickCounter + 1
    if not partsAsked and tickCounter % POLL_TICKS == 0 then pcall(askParts) end
    local any = false
    for _ in pairs(blowing) do
        any = true
        break
    end
    if any then   -- (Kahlua has no next)
        local ok, err = pcall(stepBlowing, getTimestampMs())
        if not ok then
            stats.errors = stats.errors + 1
            lastError = "blow-off: " .. tostring(err)
            blowing = {}
        end
    end
    -- the snow of an animated tree comes back as soon as HIDE_MS is over
    local now = getTimestampMs()
    for root, at in pairs(anims) do
        if now - at >= HIDE_MS then
            anims[root] = nil
            pollNow = true
        end
    end
    -- a vehicle going out of sight (or coming back) is shown anew at once, not at the next poll;
    -- only those with snow on them (snowy), sight changes nothing on the others
    if not pollNow and tickCounter % SIGHT_TICKS == 0 then
        local ok, err = pcall(function()
            for v in pairs(snowy) do
                -- coming into sight: what waits is shown (pending); going out: nothing changes
                unseen[v] = outOfSight(v) or nil
            end
        end)
        if not ok then
            stats.errors = stats.errors + 1
            lastError = "sight: " .. tostring(err)
        end
    end
    local anyPending = false
    for _ in pairs(pending) do
        anyPending = true
        break
    end
    if anyPending then   -- (Kahlua has no next)
        local ok, err = pcall(showPending)
        if not ok then
            stats.errors = stats.errors + 1
            lastError = "pending: " .. tostring(err)
            pending = {}
        end
    end
    if not pollNow and tickCounter % POLL_TICKS ~= 0 then return end
    pollNow = false
    pollCount = pollCount + 1
    if pollCount % SWEEP_POLLS == 0 then
        local ok, err = pcall(sweep)
        if not ok then
            stats.errors = stats.errors + 1
            lastError = "sweep: " .. tostring(err)
        end
    end
    reassert = pollCount % REASSERT_POLLS == 0
    local ok, err = pcall(poll)
    reassert = false
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
    end
end

-- ISnow.cleanSave (ISnow_CharSnow.lua, before removing the mod): the levels out of the ModData of
-- every loaded vehicle (SP: they live there, see stateOf; an MP client keeps them in mpState and
-- takes them out of its copy anyway), every snow model hidden; the polls stop with
-- ISnow.saveCleaned. The shell parts stay while the mod runs (they are in the vehicle scripts);
-- the game drops them when it loads a vehicle without them (VehicleParts.setScript keeps only the
-- script's parts, 42.21). Returns how many vehicles had levels.
local SAVED_KEYS = { KEY_LEVEL, KEY_AT, KEY_ICE, KEY_FROST, KEY_HOOD, KEY_CLEAR, KEY_GLASS_CLEAN }
function VehicleSnow.cleanSave()
    local n = 0
    for v in pairs(ISnow.liveVehicles()) do
        local md = v:getModData()
        local had = false
        for _, k in ipairs(SAVED_KEYS) do
            if md and md[k] ~= nil then
                md[k] = nil
                had = true
            end
        end
        if had then n = n + 1 end
    end
    for part, s in pairs(shown) do
        for key, id in pairs(s) do
            local slot = string.gsub(string.gsub(key, ICE .. "$", ""), GLASS .. "$", "")
            pcall(part.setModelVisible, part, slot .. id, false)
            pcall(redoDamage, part)
        end
    end
    for _, t in ipairs({ shown, pinned, forcedModel, snowy, bare, mpState, incoming, frostScraped }) do
        for k in pairs(t) do t[k] = nil end
    end
    return n
end

-- Quiet weather (ISnow.quietWeather) and no vehicle near with snow or icing shown (snowy), nothing
-- waiting (pending, blow-offs, door animations): a poll would change nothing. A vehicle left with
-- a level keeps it unseen until the weather wakes the polls; then catch-up (updateLevel) gives it the
-- ground's. The MP parts check is asked first. Viewpoint's view coming on or going off wakes them
-- (polledViewpoint): the snow it hid is shown again.
local function isEmpty(t)
    for _ in pairs(t) do return false end
    return true
end
local function asleep()
    return partsAsked and not pollNow and ISnow.quietWeather() and isEmpty(snowy) and isEmpty(pending)
        and isEmpty(blowing) and isEmpty(anims) and viewpoint() == polledViewpoint
end

-- Ticks skipped asleep so far (tests, the debug console).
function VehicleSnow.asleepTicks() return stats.asleep end

local function onTick()
    if ISnow.saveCleaned then return end
    local t = getTimestampMs()
    logHitch(t)
    if asleep() then
        perf.vehMs, perf.toggles, perf.variants, perf.shells = 0, 0, 0, 0
        stats.asleep = stats.asleep + 1
        return
    end
    budget.start, budget.toggles = t, 0
    local shells = ISnow.VehicleShells and ISnow.VehicleShells.counts and ISnow.VehicleShells.counts() or nil
    tick()
    local shells2 = shells and ISnow.VehicleShells.counts() or nil
    perf.vehMs = getTimestampMs() - t
    perf.toggles = budget.toggles
    stats.toggles = stats.toggles + budget.toggles
    perf.variants = shells and shells2.variants - shells.variants or 0
    perf.shells = shells and shells2.created - shells.created or 0
end

-- Debug console helpers ------------------------------------------------------

local function nearestVehicle()
    local p = getSpecificPlayer(0)
    local best, bestD2 = nil, 1e30
    forEachVehicleNear(p:getX(), p:getY(), RADIUS, function(v, d2)
        if d2 < bestD2 then best, bestD2 = v, d2 end
    end)
    return best
end

-- Counters, and the state of vehicle v (default the nearest one).
function VehicleSnow.stats(v)
    if ISnow.VehicleShells then ISnow.VehicleShells.stats() end
    local clim = getClimateManager()
    print(string.format("[ImmersiveSnow] vehicle snow: enabled=%s near=%d visible=%d unseen=%d noPart=%d pieces=%d piecesShown=%d noShellModel=%d animations=%d hooked=%s blowOffs=%d errors=%d asleep=%d ticks (quietWeather=%s) snowing=%s intensity=%.2f temp=%.1f groundFrac=%.2f groundCover=%.2f",
        tostring(ISnow.opt("VehicleSnow")), stats.near, stats.visible, stats.unseen, stats.noPart, stats.pieces, stats.piecesShown, stats.noShellModel, stats.anims, tostring(hooked), stats.blowOffs, stats.errors,
        stats.asleep, tostring(ISnow.quietWeather()),
        tostring(clim:isSnowing()), clim:getSnowIntensity(), clim:getTemperature(), clim:getSnowFracNow(), groundCover()))
    local waiting = 0
    for _ in pairs(pending) do waiting = waiting + 1 end
    print(string.format("[ImmersiveSnow]   model switches=%d, shows cut short by the budget=%d, vehicles waiting=%d",
        stats.toggles, stats.deferred, waiting))
    if lastError then print("[ImmersiveSnow] last error: " .. lastError) end
    if isClient() then
        print(string.format("[ImmersiveSnow] MP: reports sent=%d received=%d applied=%d queries=%d (unanswered %d), parts %s",
            mpStats.sent, mpStats.received, mpStats.applied, mpStats.queries, mpStats.unanswered, mpStats.partsCheck))
    end

    v = v or nearestVehicle()
    if not v then
        print("[ImmersiveSnow] no vehicle within " .. RADIUS .. " tiles")
        return
    end
    local vs = v:getScript()
    local part = v:getPartById(PART)
    local model = vs and vs:getModelCount() > 0 and vs:getModel()
    local bodyScript = model and getScriptManager():getModelScript(model:getFile())
    print(string.format("[ImmersiveSnow] nearest %s body=%s (mesh %s, static=%s) prefix=%s part=%s models=%d level=%s ice=%s shown=%s/%s outdoors=%s",
        vs and vs:getFullName() or "?", model and model:getFile() or "?",
        bodyScript and bodyScript:getMeshName() or "?", bodyScript and tostring(bodyScript:isStatic()) or "?",
        tostring(ISnow.VehicleShells and ISnow.VehicleShells.prefixFor(vs)), tostring(part ~= nil),
        part and part:getScriptPart() and part:getScriptPart():getModelCount() or 0,
        tostring(stateOf(v)[KEY_LEVEL]), tostring(stateOf(v)[KEY_ICE]), tostring(part and shown[part] and shown[part][""]),
        tostring(part and shown[part] and shown[part][ICE]), tostring(isOutdoors(v))))
    local sq = v:getSquare()
    print(string.format("[ImmersiveSnow]   state in %s, at=%s, square temp=%s | sight: alpha=%.2f target=%.2f seen=%.2f hidden=%s sightOff=%s sightBroken=%s",
        isClient() and ("client memory, id " .. tostring(v:getId())) or "ModData", tostring(stateOf(v)[KEY_AT]),
        sq and string.format("%.1f", clim:getAirTemperatureForSquare(sq)) or "?", v:getAlpha(0), v:getTargetAlpha(0),
        seenAlpha(v), tostring(unseen[v] == true), tostring(sightOff), tostring(sightBroken)))
    -- the two should agree while driving (a tile taken as a metre, see speedKmh)
    print(string.format("[ImmersiveSnow]   speed: reported %.1f km/h, from movement %.1f km/h",
        math.abs(v:getCurrentSpeedKmHour()), movedKmh(v)))
    print(string.format("[ImmersiveSnow]   frost on the glass: on=%s level=%s shown=%s windscreen=%s engine=%s heater=%s",
        tostring(ISnow.opt("VehicleFrost")), tostring(stateOf(v)[KEY_FROST]), tostring(part and shown[part] and shown[part][GLASS]),
        tostring(hasWindscreen(v)),
        tostring(v:isEngineRunning()), tostring(heaterOn(v))))
    local engine = v:getPartById("Engine")
    local emd = engine and engine:getModData()
    print(string.format("[ImmersiveSnow]   hood melt: on=%s engine temperature=%s warmth=%.2f hood deficit=%s",
        tostring(ISnow.opt("VehicleHoodMelt")), tostring(emd and emd.temperature), engineWarmth(v),
        tostring(stateOf(v)[KEY_HOOD])))
    for _, w in ipairs(ISnow.VehicleShells.wheels(v)) do
        local wheel = v:getPartById(w.part)
        local tire = v:getPartById(w.tire)
        print(string.format("[ImmersiveSnow]   %s on wheel %s (bound %s): snow part=%s tire=%s shown=%s/%s", w.tire,
            tostring(w.wheel), tostring(w.bound),
            tostring(wheel ~= nil), tostring(tire ~= nil and tire:getInventoryItem() ~= nil),
            tostring(wheel and shown[wheel] and shown[wheel][""]), tostring(wheel and shown[wheel] and shown[wheel][ICE])))
    end
    local now = getTimestampMs()
    local clear = stateOf(v)[KEY_CLEAR]
    for _, piece in ipairs(ISnow.VehicleShells.pieces(vs)) do
        local srcId = piece.src
        local snow = v:getPartById(PIECE_PREFIX .. srcId)
        local src = v:getPartById(srcId)
        local ok, iceOk, why = nil, nil, "no part"
        if src then ok, iceOk, why = pieceVisible(src) end
        local busy = src and animating(src, now)
        local models = {}
        local sp = src and src:getScriptPart()
        for _, k in ipairs(piece.models) do
            local m = sp and k < sp:getModelCount() and sp:getModel(k)
            local mid = m and m:getId()
            table.insert(models, tostring(mid) .. (src and modelVisible(src, mid) and "+" or "-") .. "=" ..
                tostring(snow and shown[snow] and shown[snow]["m" .. k .. "_"]) .. "/" ..
                tostring(snow and shown[snow] and shown[snow]["m" .. k .. "_" .. ICE]))
        end
        print(string.format("[ImmersiveSnow]   piece %s: snow part=%s deficit=%s models %s%s%s%s", srcId, tostring(snow ~= nil),
            tostring(clear and clear[srcId]), table.concat(models, " "),
            ok and "" or " (no snow: " .. tostring(why) .. ")", iceOk and "" or " (no icing)",
            busy and string.format(" (hidden: animation started %d ms ago)", busy) or ""))
    end
end

-- The console helpers only queue the change for the next onTick (see there why not poll() here).
local function queued()
    pollNow = true
    print("[ImmersiveSnow] applied on the next tick" .. (isGamePaused() and " after unpausing" or "") ..
        "; ISnow.VehicleSnow.stats() shows the result")
end

-- Pins the snow level of vehicle v, default the nearest one (0..1), and its icing level (default
-- the same, never below the snow); nil unpins them.
function VehicleSnow.set(level, v, ice)
    v = v or nearestVehicle()
    if not v then return end
    pinned[v] = level and { level, math.max(level, ice or level) } or nil
    queued()
end

-- The frost on the glass of vehicle v, 0..1 (0 with VehicleFrost off or without a windscreen), as
-- the last poll left it.
function VehicleSnow.frostOf(v)
    if not v or not ISnow.opt("VehicleFrost") or not hasWindscreen(v) then return 0 end
    return stateOf(v)[KEY_FROST] or 0
end

-- Sets the frost on vehicle v to level on this client only (a scrape going on, the console). quiet:
-- not shown outside before the next poll (a scrape sets it every tick; the view inside reads it).
function VehicleSnow.setFrost(v, level, quiet)
    v = v or nearestVehicle()
    if not v then return end
    stateOf(v)[KEY_FROST] = clamp01(level)
    if not quiet then pollNow = true end
end

-- Whether the icing shows on the glass of vehicle v (VehicleSnowIce on, some icing, not wiped).
function VehicleSnow.glassIced(v)
    if not v or not ISnow.opt("VehicleSnow") or not ISnow.opt("VehicleSnowIce") then return false end
    local md = stateOf(v)
    return md[KEY_GLASS_CLEAN] == nil and stageFor(md[KEY_ICE] or md[KEY_LEVEL] or 0, ICE_STAGES) ~= nil
end

-- Wipes the glass of vehicle v on this client only: its icing no longer shows on the glass (see
-- "Clean glass" at the top), shown at the next poll.
function VehicleSnow.cleanGlass(v)
    v = v or nearestVehicle()
    if not v then return end
    local md = stateOf(v)
    md[KEY_GLASS_CLEAN] = math.min(md[KEY_GLASS_CLEAN] or 1, md[KEY_ICE] or md[KEY_LEVEL] or 0)
    pollNow = true
end

-- Scraped clean: no frost on vehicle v and its glass wiped, for everyone (MP: through the server,
-- "vehFrost").
function VehicleSnow.scrape(v)
    VehicleSnow.setFrost(v, 0)
    VehicleSnow.cleanGlass(v)
    if isClient() and v then
        sendClientCommand(MP_MODULE, "vehFrost", { id = v:getId() })
        mpStats.sent = mpStats.sent + 1
    end
end

-- The snow and icing levels on vehicle v, 0..1 (0 with VehicleSnow off here), as the last poll left
-- them.
function VehicleSnow.levelOf(v)
    if not v or not ISnow.opt("VehicleSnow") then return 0, 0 end
    local md = stateOf(v)
    local level = md[KEY_LEVEL] or 0
    return level, md[KEY_ICE] or level
end

-- The icing level left on a vehicle brushed clean (it may have less).
VehicleSnow.BRUSH_ICE = levelOfStage(BRUSH_ICE_KEEP)

-- Lowers the snow and icing on vehicle v to level and ice (never raises them) on this client only
-- (a brush going on): shown at the next poll.
function VehicleSnow.lower(v, level, ice)
    local md = stateOf(v)
    lowerLevel(md, clamp01(level))
    -- one level: the icing goes with the snow (ice is not used)
    if md[KEY_ICE] then md[KEY_ICE] = md[KEY_LEVEL] or 0 end
end

-- MP: the levels of vehicle v as this client has them now, to everyone ("vehSnow", like a
-- driver's report): a brush, or a brush or a scrape stopped half-way (their steps change this
-- client only). Nothing while this client has no levels of v.
function VehicleSnow.report(v)
    if not (isClient() and v) then return end
    local md = stateOf(v)
    if md[KEY_AT] == nil then return end
    local level = md[KEY_LEVEL] or 0
    local vs = v:getScript()
    sendClientCommand(MP_MODULE, "vehSnow", { id = v:getId(), s = vs and vs:getFullName() or "", l = level,
        i = md[KEY_ICE] or level, f = md[KEY_FROST], g = md[KEY_GLASS_CLEAN] ~= nil, h = md[KEY_HOOD] or 0 })
    mpStats.sent = mpStats.sent + 1
end

-- Brushed clean: no snow on vehicle v, the icing down to BRUSH_ICE and the glass wiped (the
-- hoarfrost stays), for everyone (MP: reported like a driver's levels, "vehSnow").
function VehicleSnow.brush(v)
    if not v then return end
    VehicleSnow.lower(v, 0, VehicleSnow.BRUSH_ICE)
    VehicleSnow.cleanGlass(v)
    VehicleSnow.report(v)
end

-- Shows one shell model on vehicle v, default the nearest one, regardless of snow ("s1".."s6",
-- "i1".."i6", "g1".."g6", or a debug id from ISnow.VEHICLE_SNOW_DEBUG, e.g. "dbg_normals"); nil goes back to normal.
function VehicleSnow.show(id, v)
    v = v or nearestVehicle()
    if not v then return end
    forcedModel[v] = id
    queued()
end

-- Covers every vehicle within radius tiles (default 20) of the player with snow and icing level
-- (default 1, stage s6), unpinned: it melts, blows off and is shaken off as usual.
function VehicleSnow.fill(level, radius)
    level = level or 1
    local p = getSpecificPlayer(0)
    local now = getGameTime():getWorldAgeHours()
    local n = 0
    forEachVehicleNear(p:getX(), p:getY(), radius or 20, function(v)
        local md = stateOf(v)
        md[KEY_LEVEL], md[KEY_ICE], md[KEY_AT], md[KEY_CLEAR], md[KEY_HOOD] = level, level, now, nil, nil
        n = n + 1
    end)
    print("[ImmersiveSnow] snow level " .. level .. " on " .. n .. " vehicles")
end

-- Throws one stage's worth of blow-off particles (and its sound) from vehicle v (default the nearest one) as if
-- it drove at kmh (default 60) along its heading, without touching its snow (to look at the effect).
function VehicleSnow.blowTest(kmh, v)
    v = v or nearestVehicle()
    if not v or not ISnow.BlowOff then return end
    local ext = v:getScript():getExtents()
    local area = math.max(0.4, math.min(2.5, ext:x() * ext:z() / BLOWOFF_REF_AREA))
    ISnow.BlowOff.emit(v, math.floor(BLOWOFF_CHUNKS * area), math.floor(BLOWOFF_PUFFS * area), kmh or 60)
    if ISnow.opt("BlowOffSound") then ISnow.BlowOff.sound(v) end
end

-- Turns the snow on separate body pieces (doors, hood...) on or off for every vehicle.
function VehicleSnow.pieces(on)
    piecesOff = not on
    queued()
end

-- Turns hiding the snow of vehicles out of sight on or off (on again also retries after
-- sightBroken).
function VehicleSnow.sight(on)
    sightOff = not on
    if on then sightBroken = false end
    queued()
end

-- Debug mode only (field reflection is refused otherwise): declared field of obj's own class.
local function field(obj, name)
    if obj == nil then return nil end
    for i = 0, getNumClassFields(obj) - 1 do
        local f = getClassField(obj, i)
        local s = tostring(f)
        if string.sub(s, -(#name + 1)) == "." .. name then return getClassFieldVal(obj, f) end
    end
    return nil
end

local function modelScriptInfo(ms)
    if not ms then return "nil" end
    return string.format("%s mesh=%s tex=%s shader=%s scale=%s invertX=%s static=%s", tostring(ms:getFullType()),
        tostring(ms:getMeshName()), tostring(ms:getTextureName()), tostring(ms:getShaderName()),
        tostring(field(ms, "scale")), tostring(field(ms, "invertX")), tostring(ms:isStatic()))
end

-- Prints the body and shell transforms of the nearest vehicle to compare them (needs -debug).
function VehicleSnow.dump()
    local v = nearestVehicle()
    if not v then return end
    local vs = v:getScript()
    local sm = getScriptManager()
    print("[ImmersiveSnow] dump " .. vs:getFullName() .. " modelScale=" .. tostring(vs:getModelScale()))
    local body = vs:getModel()
    print("[ImmersiveSnow]   body model file=" .. tostring(body:getFile()) .. " offset=" .. tostring(body:getOffset()) ..
        " scale=" .. tostring(body:getScale()))
    print("[ImmersiveSnow]   body script: " .. modelScriptInfo(sm:getModelScript(body:getFile())))
    print("[ImmersiveSnow]   vehicle.renderTransform=" .. tostring(field(v, "renderTransform")))
    print("[ImmersiveSnow]   vehicle.vehicleTransform=" .. tostring(field(v, "vehicleTransform")))
    local models = field(v, "models")
    if not models then return end
    for i = 0, models:size() - 1 do
        local mi = models:get(i)
        local sModel = field(mi, "scriptModel")
        local part = field(mi, "part")
        print(string.format("[ImmersiveSnow]   models[%d] part=%s id=%s file=%s partScale=%s offset=%s", i,
            part and part:getId() or "nil", sModel and sModel:getId() or "nil", sModel and sModel:getFile() or "nil",
            sModel and tostring(sModel:getScale()) or "nil", sModel and tostring(sModel:getOffset()) or "nil"))
        print("[ImmersiveSnow]     script: " .. modelScriptInfo(field(mi, "modelScript")))
        print("[ImmersiveSnow]     renderTransform=" .. tostring(field(mi, "renderTransform")))
    end
end

-- Notes every part animation started from Lua (vanilla door actions, KI5 sunroofs / rear windows /
-- ramps...) on a part that can animate; the next tick hides the snow of its tree (show). Wrapped anew
-- on a reload, around the original kept in ISnowPlayPartAnim.
local function hookPlayPartAnim()
    local mt = __classmetatables and BaseVehicle and __classmetatables[BaseVehicle.class]
    local index = mt and mt.__index
    if not index or not index.playPartAnim then return false end
    local orig = index.ISnowPlayPartAnim or index.playPartAnim
    index.ISnowPlayPartAnim = orig
    hooked = true
    index.playPartAnim = function(vehicle, part, animId)
        local r = orig(vehicle, part, animId)
        local ok, err = pcall(function()
            if part and animId and isAnimatable(part) then
                anims[rootOf(part)] = getTimestampMs()
                stats.anims = stats.anims + 1
                pollNow = true
            end
        end)
        if not ok then
            stats.errors = stats.errors + 1
            lastError = "playPartAnim hook: " .. tostring(err)
        end
        return r
    end
    return true
end
if not hookPlayPartAnim() then
    print("[ImmersiveSnow] BaseVehicle.playPartAnim not hooked: snow on animated body pieces may speed the animation up")
end

-- A model switch of part from Lua (not ours): counted for spinning (switches), once per
-- SWITCH_GAP_MS. A part that starts spinning gets a poll at once (its snow goes).
local function noteSwitch(part)
    local now = getTimestampMs()
    local s = switches[part]
    if not s then
        s = { at = {}, n = 0 }
        switches[part] = s
    end
    local last = s.n > 0 and s.at[math.min(s.n, SWITCH_COUNT)] or nil
    if last and now - last < SWITCH_GAP_MS then return end
    local was = spinning(part, now)
    if s.n >= SWITCH_COUNT then
        table.remove(s.at, 1)
    else
        s.n = s.n + 1
    end
    s.at[s.n] = now
    if not was and spinning(part, now) then pollNow = true end
end

-- Notes that model id of part is now visible (or not), and counts a change as a switch.
local function noteVisible(part, id, visible)
    local t = modelVis[part]
    if not t then
        t = {}
        modelVis[part] = t
    end
    local old = t[id]
    if old == nil then old = modelVisible(part, id) end
    t[id] = visible
    if old ~= visible then noteSwitch(part) end
end

-- Remembers which models of a part the vehicle's Lua shows or hides, see modelVisible:
-- setModelVisible (KI5 damnlib in the parts' Init / InstallComplete, client side; AviationCore's
-- rotor), setAllModelsVisible (every model of the part, VehiclePart.setAllModelsVisible; AviationCore
-- hides all blade positions that way before showing one) and setInventoryItem (all models shown with
-- an item, hidden without, when the script part has setAllModelsVisible). Java methods are looked up
-- in the class metatable, so wrapping the entry catches every call from Lua; the engine's own calls
-- (VehicleParts.setScript) come before Lua sees the part.
local function hookSetModelVisible()
    local mt = __classmetatables and VehiclePart and __classmetatables[VehiclePart.class]
    local index = mt and mt.__index
    if not index or not index.setModelVisible then return false end
    -- wrapped anew on a reload, around the original (visibility set before the reload is forgotten)
    local orig = index.ISnowSetModelVisible or index.setModelVisible
    index.ISnowSetModelVisible = orig
    rawSetVisible = true
    index.setModelVisible = function(part, id, visible)
        if id ~= nil then
            local ok, err = pcall(noteVisible, part, id, visible and true or false)
            if not ok then
                stats.errors = stats.errors + 1
                lastError = "setModelVisible hook: " .. tostring(err)
            end
        end
        return orig(part, id, visible)
    end
    -- all models of part to visible, as VehiclePart.setAllModelsVisible does
    local function noteAll(part, visible)
        local sp = part:getScriptPart()
        for k = 0, (sp and sp:getModelCount() or 0) - 1 do
            noteVisible(part, sp:getModel(k):getId(), visible)
        end
    end
    local origAll = index.ISnowSetAllModelsVisible or index.setAllModelsVisible
    if origAll then
        index.ISnowSetAllModelsVisible = origAll
        index.setAllModelsVisible = function(part, visible)
            local r = origAll(part, visible)
            local ok, err = pcall(noteAll, part, visible and true or false)
            if not ok then
                stats.errors = stats.errors + 1
                lastError = "setAllModelsVisible hook: " .. tostring(err)
            end
            return r
        end
    end
    local origItem = index.ISnowSetInventoryItem or index.setInventoryItem
    if origItem then
        index.ISnowSetInventoryItem = origItem
        index.setInventoryItem = function(part, ...)
            local r = origItem(part, ...)
            local ok, err = pcall(function()
                if part:isSetAllModelsVisible() then noteAll(part, part:getInventoryItem() ~= nil) end
            end)
            if not ok then
                stats.errors = stats.errors + 1
                lastError = "setInventoryItem hook: " .. tostring(err)
            end
            return r
        end
    end
    return true
end
if not hookSetModelVisible() then
    print("[ImmersiveSnow] VehiclePart.setModelVisible not hooked: multi-model body pieces assume all models visible")
end

ISnow.listen("OnTickEvenPaused", "VehicleSnow", onTick)
