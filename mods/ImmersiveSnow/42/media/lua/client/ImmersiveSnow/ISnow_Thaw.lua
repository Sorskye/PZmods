-- Immersive Snow: snow thawing around fires. A campfire, a fire on the ground or a burning building
-- melts the snow around it into a dark wet patch, with a little steam off it, while it burns; after
-- the fire is out the patch goes over FireThawHours (faster in fresh snowfall).
--
-- Finding fires: every fire in B42 is an IsoFire object on its square, a lit campfire included
-- (SCampfireGlobalObject:getFireObject finds its permanent IsoFire), and the IsoFire constructors
-- set IsoFlagType.burning on the square's properties, extinctFire unsets it (bytecode 42.21). The
-- list of fires (IsoFireManager.FireStack) is a static field, not reachable from Lua. So the squares
-- around player 0 (SCAN_RADIUS, the player's level) are searched for sq:has(IsoFlagType.burning)
-- (IsoGridSquare.has(IsoFlagType), what vanilla FireFighting.lua asks), a few rows a tick: one
-- search of the whole square takes SCAN_TICKS ticks, two Java calls a square, and only while
-- there is snow on the ground.
--
-- The patch: points on a GRID grid within THAW_RADIUS of a burning square's centre, on squares
-- under the sky with ground snow; heat 0..1 goes towards 1 near the fire (falling off past
-- THAW_FULL) over GROW_MINUTES while it burns, and back to 0 after. Each point draws one of
-- thaw_<variant>_<level>.png (tools/gen_thaw.py) at the level of its heat: multiply textures whose
-- overlap weights sum to 1 on the grid, so a field of points is one even darkness, rising towards
-- the fire. Drawn like the prints (ISnow_Decals.lua: a multiply buffer from
-- RenderOpaqueObjectsInWorld), never aged by the buffer: a point is laid again when its level
-- changes. A burning building's squares are indoors: its patch is the ring of snow around it.
--
-- Steam: puffs of the blow-off's powder rising slowly (BlowOff.steam) off the warm points of the
-- fires on screen while they burn; not in the low-end mode (FireThawSteam).
--
-- Client side only: every client looks for the fires near its player; nothing saved or synced.

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_Decals"
require "ImmersiveSnow/ISnow_BlowOff"

local Thaw = {}
ISnow.Thaw = Thaw

-- texture layout, as tools/gen_thaw.py
local THAW_SIZE = 128
local THAW_REACH = 29            -- px below the centre (27 in the PNGs)
local THAW_VARIANTS = 4
local THAW_LEVELS = 4
local GRID = 0.5                 -- world units between points

local SCAN_RADIUS = 20           -- squares around player 0 searched for fires
local SCAN_TICKS = 30            -- ticks one search takes
local THAW_RADIUS = 2.25         -- tiles from a burning square's centre the thaw reaches ...
local THAW_FULL = 1.0            -- ... at full heat up to this
local GROW_MINUTES = 20          -- game minutes a fire takes to thaw its patch fully
local MAX_POINTS = 800           -- points drawn at most ...
local MAX_KEPT = 3200            -- ... and known (those without snow too: a burning building's floor)
local RENDER_RADIUS = 45
local STEAM_RATE = 3             -- puffs a second off a fire's patch at full heat
local STEAM_MAX = 12             -- ... all fires together
local STEAM_HEAT = 0.3           -- points at least this warm steam
local STEAM_WIND = 0.04          -- tiles / s per km/h of wind the steam is carried at ...
local STEAM_WIND_MAX = 0.8       -- ... at most

local buffer = ISnow.Decals.newBuffer(function() return MAX_POINTS end, nil, 1, false, true)
local points = {}                -- [key] = { x, y, z, heat, target, level, e, v, snow, seen = search }
local pointCount = 0
local fires = {}                 -- burning squares found by the last whole search: { x, y, z, points = {} }
local forced = {}                -- test fires (Thaw.testFire)
local scan = nil                 -- the search going on: { x, y, z, row, found }
local sets = {}                  -- [variant * THAW_LEVELS + level - 1] = texture paths of levels 1..level
local anchorX, anchorY, anchorZ = 0, 0, 0
local BURNING = nil
local active = false             -- snow on the ground and FireThaw on
local ready = false
local lastMs = nil
local steamAcc = 0
local stats = { searches = 0, laid = 0, steam = 0, errors = 0 }
local lastError = nil

function Thaw.file(variant, level)
    return "thaw_" .. variant .. "_" .. level .. ".png"
end

local function load()
    for v = 0, THAW_VARIANTS - 1 do
        for level = 1, THAW_LEVELS do
            sets[v * THAW_LEVELS + level - 1] = ISnow.Decals.newSet(function(l) return Thaw.file(v, l) end, level)
        end
    end
    anchorX, anchorY, anchorZ = ISnow.Decals.anchor(THAW_SIZE, THAW_REACH)
    BURNING = IsoFlagType.burning
    ready = true
end

-- Heat a point dist tiles from a burning square's centre goes towards, 0..1.
function Thaw.heatAt(dist)
    if dist <= THAW_FULL then return 1 end
    return math.max(0, 1 - (dist - THAW_FULL) / (THAW_RADIUS - THAW_FULL))
end

local function pointKey(gx, gy, z)
    return (z + 64) * 1099511627776 + gx * 1048576 + gy   -- grid indices from 0, < 2^20
end

-- Gives each point the heat its fires call for, making the points a fire newly reaches.
local function applyFires()
    for _, p in pairs(points) do p.target = 0 end
    local cell = getCell()
    local reach = math.ceil(THAW_RADIUS / GRID)
    for _, f in ipairs(fires) do
        f.points = {}
        local cx, cy = f.x + 0.5, f.y + 0.5
        local g0x, g0y = math.floor(cx / GRID), math.floor(cy / GRID)
        for gx = g0x - reach, g0x + reach do
            for gy = g0y - reach, g0y + reach do
                local px, py = (gx + 0.5) * GRID, (gy + 0.5) * GRID
                local heat = Thaw.heatAt(math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2))
                if heat > 0 then
                    local key = pointKey(gx, gy, f.z)
                    local p = points[key]
                    if not p and pointCount < MAX_KEPT then
                        p = { x = px, y = py, z = f.z, heat = 0, target = 0, level = 0, v = ISnow.decalVariant(THAW_VARIANTS),
                            snow = ISnow.Decals.isSnowSquare(cell, math.floor(px), math.floor(py), f.z) }
                        points[key] = p
                        pointCount = pointCount + 1
                    end
                    if p then p.seen = stats.searches end
                    if p and p.snow then
                        if heat > p.target then p.target = heat end
                        f.points[#f.points + 1] = p
                    end
                end
            end
        end
    end
end

-- Searches a few rows of the square around player 0 for burning squares; at the end of a whole
-- search they are the fires.
local function searchStep()
    local cell = getCell()
    if not scan then
        local player = getSpecificPlayer(0)
        if not player then return end
        scan = { x = math.floor(player:getX()), y = math.floor(player:getY()), z = math.floor(player:getZ()),
            row = -SCAN_RADIUS, found = {} }
    end
    local rows = math.ceil((2 * SCAN_RADIUS + 1) / SCAN_TICKS)
    local found = scan.found
    for _ = 1, rows do
        local y = scan.y + scan.row
        for x = scan.x - SCAN_RADIUS, scan.x + SCAN_RADIUS do
            local sq = cell:getGridSquare(x, y, scan.z)
            if sq and sq:has(BURNING) then found[#found + 1] = { x = x, y = y, z = scan.z } end
        end
        scan.row = scan.row + 1
        if scan.row > SCAN_RADIUS then
            for _, f in ipairs(forced) do found[#found + 1] = { x = f.x, y = f.y, z = f.z } end
            fires = found
            scan = nil
            stats.searches = stats.searches + 1
            applyFires()
            return
        end
    end
end

-- Lays point p again at level (0: takes it out).
local function relay(p, level)
    if p.e and not p.e.dead and not p.e.gone then buffer:kill(p.e) end
    p.e = nil
    p.level = level
    if level > 0 then
        p.e = buffer:push({ x = p.x + anchorX, y = p.y + anchorY, z = p.z, rz = p.z + anchorZ,
            set = sets[p.v * THAW_LEVELS + level - 1] })
        stats.laid = stats.laid + 1
    end
end

-- Heat follows the fires, a game minute at a time. The points to lay again are killed first and
-- laid after one compact: killed entries count against MAX_POINTS until a compact (the buffer
-- compacts at a quarter dead), so ~650 warm points already pushed the oldest out. A point pushed
-- out (its entry gone) is laid again while there is room: at full heat its level never changes,
-- and its hole in the patch stayed.
local function warm()
    local grow = 1 / GROW_MINUTES
    local cool = ISnow.Decals.agePerMinute(ISnow.opt("FireThawHours"))
    local again = {}
    for key, p in pairs(points) do
        if p.target > p.heat then
            p.heat = math.min(p.target, p.heat + grow)
        else
            p.heat = math.max(p.target, p.heat - cool)
        end
        local level = math.floor(p.heat * THAW_LEVELS + 0.5)
        local lost = level > 0 and (p.e == nil or p.e.gone or p.e.dead or p.e.fadeAt ~= nil)
        if level ~= p.level or lost then
            relay(p, 0)
            p.level = level
            again[#again + 1] = p
        end
        -- gone once cold; one without snow once no fire reaches it (else it would be made again,
        -- and its square looked at, every search)
        if p.heat <= 0 and p.target <= 0 and (p.snow or p.seen < stats.searches) then
            points[key] = nil
            pointCount = pointCount - 1
        end
    end
    if #again == 0 then return end
    buffer:compact()
    for _, p in ipairs(again) do
        if p.level > 0 and buffer:count() - buffer:fading() < MAX_POINTS then relay(p, p.level) end
    end
end

-- Steam off the warm points of the fires on screen.
local function steam(dt)
    if not ISnow.opt("FireThawSteam") or getNumActivePlayers() > 1 then return end
    local player = getSpecificPlayer(0)
    if not player then return end
    local umin, umax, vmin, vmax = ISnow.Decals.viewBounds(0, player:getX(), player:getY(), math.floor(player:getZ()))
    if not umin then return end
    local shown = {}
    local rate = 0
    for _, f in ipairs(fires) do
        local u, v = f.x - f.y, f.x + f.y
        if f.points and #f.points > 0 and u >= umin and u <= umax and v >= vmin and v <= vmax then
            shown[#shown + 1] = f
            rate = rate + STEAM_RATE
        end
    end
    if #shown == 0 then
        steamAcc = 0
        return
    end
    steamAcc = math.min(steamAcc + math.min(STEAM_MAX, rate) * dt, ISnow.BlowOff.room())
    if steamAcc < 1 then return end
    local clim = getClimateManager()
    local a = clim:getWindAngleRadians()   -- world direction (sin a, cos a), see ISnow_Drift.lua
    local w = math.min(STEAM_WIND_MAX, clim:getWindspeedKph() * STEAM_WIND)
    local wx, wy = math.sin(a) * w, math.cos(a) * w
    while steamAcc >= 1 do
        steamAcc = steamAcc - 1
        local f = shown[ZombRand(#shown) + 1]
        local p = f.points[ZombRand(#f.points) + 1]
        if p.heat >= STEAM_HEAT and ZombRandFloat(0, 1) < p.heat then
            ISnow.BlowOff.steam(p.x + ZombRandFloat(-0.25, 0.25), p.y + ZombRandFloat(-0.25, 0.25), p.z, wx, wy)
            stats.steam = stats.steam + 1
        end
    end
end

function Thaw.clear()
    buffer:clear()
    points, pointCount = {}, 0
    fires, scan = {}, nil
end

local function refresh()
    active = ready and ISnow.Decals.snowActive() and ISnow.opt("FireThaw") and true or false
    if not active and (pointCount > 0 or buffer:count() > 0) then Thaw.clear() end
end

local function onTick()
    local now = getTimestampMs()
    local dt = lastMs and (now - lastMs) / 1000 or 0
    lastMs = now
    if not active or isGamePaused() then return end
    local ok, err = pcall(searchStep)
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
        scan = nil
    end
    if #fires > 0 and ISnow.BlowOff and ISnow.BlowOff.steam then
        ok, err = pcall(steam, math.min(dt, 0.1))
        if not ok then
            stats.errors = stats.errors + 1
            lastError = tostring(err)
        end
    end
end

local function onEveryOneMinute()
    refresh()
    if not active or pointCount == 0 then return end
    local ok, err = pcall(warm)
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
    end
end

local function onRender(playerIndex)
    if active then buffer:render(playerIndex, RENDER_RADIUS) end
end

local function onRenderSafe(playerIndex)
    local ok = pcall(onRender, playerIndex)
    if not ok then stats.errors = stats.errors + 1 end
end

local function onGameStart()
    local ok, err = pcall(load)
    if not ok then
        lastError = tostring(err)
        print("[ImmersiveSnow] thaw around fires disabled: " .. lastError)
    end
    refresh()
end

-- Debug console helpers ------------------------------------------------------

function Thaw.stats()
    local warmPoints = 0
    for _, p in pairs(points) do if p.level > 0 then warmPoints = warmPoints + 1 end end
    print(string.format("[ImmersiveSnow] thaw: active=%s fires=%d points=%d (thawed %d) segments=%d drawnLastFrame=%d searches=%d laid=%d steam=%d errors=%d",
        tostring(active), #fires, pointCount, warmPoints, buffer:count(), buffer.drawn, stats.searches, stats.laid,
        stats.steam, stats.errors))
    if lastError then print("[ImmersiveSnow] last error: " .. lastError) end
end

-- A pretend fire on the square 3 tiles in front of player 0 (on = false takes the test fires away),
-- found by the next searches like a burning one; game minutes thaw it as usual.
function Thaw.testFire(on)
    if on == false then
        forced = {}
        return
    end
    local p = getSpecificPlayer(0)
    forced[#forced + 1] = { x = math.floor(p:getX() + p:getForwardDirectionX() * 3),
        y = math.floor(p:getY() + p:getForwardDirectionY() * 3), z = math.floor(p:getZ()) }
end

Events.OnGameStart.Add(onGameStart)
ISnow.listen("OnTick", "Thaw", onTick)
Events.EveryOneMinute.Add(onEveryOneMinute)
ISnow.listen("RenderOpaqueObjectsInWorld", "Thaw", onRenderSafe)
