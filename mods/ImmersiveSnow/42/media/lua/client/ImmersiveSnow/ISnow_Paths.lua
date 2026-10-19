-- Immersive Snow: trampled paths. Ground snow walked over again and again (players and zombies)
-- becomes a trodden path that lasts far longer than the prints (TrampledPathHours against
-- FootprintHours), so you can see where a horde keeps walking.
--
-- Counted from the prints: ISnow_Footprints.lua calls Paths.step for every print it lays in snow
-- (so only for characters a local player sees, and only with their footprints on). Each square has
-- a pass counter that forgets: a print adds 1, and the count halves every PASS_HALF_LIFE game
-- minutes (worked out when the square is stepped on again, and by a sweep that drops the forgotten
-- ones). From TrampledPathSteps the square gets a path segment, one strength darker every
-- LEVEL_STEP x that many more (PATH_LEVELS strengths). A walker crosses a square in about two prints.
--
-- The segment lies on the mean of the prints on that square, along their mean direction (doubled
-- angles: back and forth is one path), path_<dir>_<variant>_<level>.png (tools/gen_paths.py), long
-- enough to reach the next square's segment, with overlap weights that sum to 1 there. Drawn like
-- the prints (ISnow_Decals.lua: a multiply buffer from RenderOpaqueObjectsInWorld). A strength-s
-- segment uses the textures of levels 1..s, so the buffer fades it from its own strength down over
-- the last part of its life. A walked-on segment is pushed again (born now) when it is due: a new
-- strength or direction, or REFRESH of its life gone; so it lasts TrampledPathHours after the last
-- walker, less in fresh snowfall (Decals.agePerMinute, like the prints).
--
-- Client side only, like the prints: nothing saved or synced, every MP client counts the prints it
-- lays itself, and the paths are gone when the game is loaded again.

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_Decals"

local Paths = {}
ISnow.Paths = Paths

-- texture layout, as tools/gen_paths.py
local PATH_DIRS = 16             -- over half a turn: angle = dir * 180 / PATH_DIRS deg
local PATH_SIZE = 128            -- px, square texture with the segment centred
local PATH_REACH = 40            -- px below the centre the visible segment reaches (38 in the PNGs)
local PATH_VARIANTS = 2
local PATH_LEVELS = 4

local PASS_HALF_LIFE = 180       -- game minutes in which a square's pass count halves
local LEVEL_STEP = 0.5           -- of TrampledPathSteps more prints per strength above the first
local REFRESH = 0.05             -- part of its life after which a walked-on segment is pushed again
local FULL_ALPHA_UNTIL = 0.5     -- part of its life before a segment starts to fade
local RENDER_RADIUS = 45
local FORGET = 0.5               -- a square without a segment is dropped below this many passes
local SWEEP_MINUTES = 30         -- game minutes between sweeps of the counters
local MAX_SQUARES = 20000        -- past this many counted squares a sweep drops all without a segment

local buffer = ISnow.Decals.newBuffer(function() return ISnow.opt("MaxTrampledPaths") end, nil, FULL_ALPHA_UNTIL, false, true)
local squares = {}               -- [key] = { n = passes, t = minute, x, y (sums), c, s (doubled angle sums), e, level, dir, v }
local count = 0                  -- squares counted
local sets = {}                  -- [((dir * PATH_VARIANTS) + variant) * PATH_LEVELS + strength - 1] = texture paths
local anchorX, anchorY, anchorZ = 0, 0, 0
local minute = 0                 -- game minutes since the game started (EveryOneMinute)
local snowActive = false
local ready = false
local stats = { steps = 0, pushed = 0, swept = 0, errors = 0 }

function Paths.file(dir, variant, level)
    return "path_" .. dir .. "_" .. variant .. "_" .. level .. ".png"
end

-- Only the paths: a set's textures load when its first segment is laid (ISnow.Decals.newSet).
local function loadSprites()
    for dir = 0, PATH_DIRS - 1 do
        for v = 0, PATH_VARIANTS - 1 do
            for strength = 1, PATH_LEVELS do
                sets[(dir * PATH_VARIANTS + v) * PATH_LEVELS + strength - 1] = ISnow.Decals.newSet(
                    function(level) return Paths.file(dir, v, level) end, strength)
            end
        end
    end
    anchorX, anchorY, anchorZ = ISnow.Decals.anchor(PATH_SIZE, PATH_REACH)
    ready = true
end

-- Brings a square's counts to this minute.
local function decay(sq)
    local dt = minute - sq.t
    if dt <= 0 then return end
    local f = 0.5 ^ (dt / PASS_HALF_LIFE)
    sq.n, sq.x, sq.y, sq.c, sq.s = sq.n * f, sq.x * f, sq.y * f, sq.c * f, sq.s * f
    sq.t = minute
end

-- Strength 0 (no path) .. PATH_LEVELS of n passes.
function Paths.strength(n)
    local steps = math.max(1, ISnow.opt("TrampledPathSteps"))
    if n < steps then return 0 end
    return math.min(PATH_LEVELS, 1 + math.floor((n - steps) / (steps * LEVEL_STEP)))
end

local function alive(e)
    return e ~= nil and not e.gone and not e.dead and not e.fadeAt
end

-- Lays (again) the segment of square sq at strength level.
local function lay(sq, level, dir)
    if alive(sq.e) then buffer:kill(sq.e) end
    local x, y = sq.x / sq.n, sq.y / sq.n
    local set = sets[(dir * PATH_VARIANTS + sq.v) * PATH_LEVELS + level - 1]
    sq.e = buffer:push({ x = x + anchorX, y = y + anchorY, z = sq.z, rz = sq.z + anchorZ, set = set })
    sq.level, sq.dir = level, dir
    stats.pushed = stats.pushed + 1
end

-- A print at x, y on floor level z (an integer), the walker facing fx, fy. Called by
-- ISnow_Footprints.lua for every print laid in snow.
function Paths.step(x, y, z, fx, fy)
    if not ready or not snowActive or not ISnow.opt("TrampledPaths") then return end
    local sx, sy = math.floor(x), math.floor(y)
    local key = (z + 64) * 1099511627776 + sx * 1048576 + sy   -- levels from -64, x, y < 2^20
    local sq = squares[key]
    if not sq then
        sq = { n = 0, t = minute, x = 0, y = 0, c = 0, s = 0, z = z, v = ISnow.decalVariant(PATH_VARIANTS) }
        squares[key] = sq
        count = count + 1
    else
        decay(sq)
    end
    -- doubled angle: facing either way along a line adds up
    local a = 2 * math.atan2(fy, fx)
    sq.n, sq.x, sq.y = sq.n + 1, sq.x + x, sq.y + y
    sq.c, sq.s = sq.c + math.cos(a), sq.s + math.sin(a)
    stats.steps = stats.steps + 1
    local level = Paths.strength(sq.n)
    if level <= 0 then return end
    local half = math.atan2(sq.s, sq.c) / 2
    if half < 0 then half = half + math.pi end
    local dir = math.floor(half / math.pi * PATH_DIRS + 0.5) % PATH_DIRS
    local e = sq.e
    if not alive(e) or level > sq.level or dir ~= sq.dir or buffer:ageOf(e) > REFRESH then
        lay(sq, level, dir)
    end
end

-- Drops the counters that have been forgotten (and their segments gone).
local function sweep()
    local tooMany = count > MAX_SQUARES
    for key, sq in pairs(squares) do
        decay(sq)
        if not alive(sq.e) and (tooMany or sq.n < FORGET) then
            squares[key] = nil
            count = count - 1
            stats.swept = stats.swept + 1
        end
    end
end

function Paths.clear()
    buffer:clear()
    squares, count = {}, 0
end

local function refresh()
    snowActive = ISnow.Decals.snowActive()
    -- snow melted away, or turned off in Options > Mods: gone at once
    if not snowActive or not ISnow.opt("TrampledPaths") then
        if count > 0 or buffer:count() > 0 then Paths.clear() end
    end
end

local function onEveryOneMinute()
    minute = minute + 1
    refresh()
    buffer:age(ISnow.Decals.agePerMinute(ISnow.opt("TrampledPathHours")))
    if minute % SWEEP_MINUTES == 0 and count > 0 then sweep() end
end

local function onRender(playerIndex)
    if ready then buffer:render(playerIndex, RENDER_RADIUS) end
end

local function onRenderSafe(playerIndex)
    local ok = pcall(onRender, playerIndex)
    if not ok then stats.errors = stats.errors + 1 end
end

local function onGameStart()
    local ok, err = pcall(loadSprites)
    if not ok then
        stats.errors = stats.errors + 1
        print("[ImmersiveSnow] loading path textures failed: " .. tostring(err))
    end
    refresh()
end

-- Debug console helpers ------------------------------------------------------

function Paths.stats()
    print(string.format("[ImmersiveSnow] trampled paths: on=%s squares=%d segments=%d (fading %d) drawnLastFrame=%d steps=%d pushed=%d expired=%d pushedOut=%d swept=%d errors=%d max=%d",
        tostring(ISnow.opt("TrampledPaths")), count, buffer:count(), buffer:fading(), buffer.drawn, stats.steps, stats.pushed,
        buffer.expired, buffer.evicted, stats.swept, stats.errors, ISnow.opt("MaxTrampledPaths")))
end

-- Walks n times (default the steps for a full-strength path) back and forth over 8 squares in front
-- of player 0, two prints a square, without walking (tests rendering only).
function Paths.testPath(n)
    local p = getSpecificPlayer(0)
    local fx, fy = p:getForwardDirectionX(), p:getForwardDirectionY()
    local x, y, z = p:getX(), p:getY(), math.floor(p:getZ())
    n = n or math.ceil(ISnow.opt("TrampledPathSteps") * (1 + LEVEL_STEP * (PATH_LEVELS - 1)) / 2)
    for pass = 1, n do
        local back = pass % 2 == 0 and -1 or 1
        for k = 1, 16 do
            local d = 1 + k * 0.5
            Paths.step(x + fx * d, y + fy * d, z, fx * back, fy * back)
        end
    end
    Paths.stats()
end

Events.OnGameStart.Add(onGameStart)
Events.EveryOneMinute.Add(onEveryOneMinute)
ISnow.listen("RenderOpaqueObjectsInWorld", "Paths", onRenderSafe)
