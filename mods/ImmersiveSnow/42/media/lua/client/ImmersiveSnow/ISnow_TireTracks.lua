-- Immersive Snow: tire tracks left in ground snow by vehicles.
--
-- Drawn the same way as footprints: a Lua list of decals rendered every frame from
-- RenderOpaqueObjectsInWorld with the scene depth, depth tested without depth write
-- (ISnow_Decals.lua).
--
-- Wheel positions: BaseVehicle:getWorldPos(localOffset, out) transforms a point from the physics
-- body frame (x = left, y = up, z = forward) and returns out.x / out.y as world tile X / Y
-- (physics z maps to world y). Vanilla BaseVehicle.testCollisionWithProneCharacter uses it with
-- VehicleScript$Wheel.offset exactly like this. getForwardVector returns the body z axis in
-- physics coords, so the world direction is (fwd:x(), fwd:z()). Verified in game with markers.
--
-- Each wheel's path is cut into straight segments exactly TRACK_STEP long, measured from the
-- previous segment end, so the line is continuous and follows the real motion (turns, reverse).
-- A segment's texture fades at both ends over the overlap with its neighbours, and each direction
-- has TRACK_VARIANTS textures that join seamlessly, one picked at random per segment so the rut
-- does not repeat every TRACK_STEP (gen_tracks.py; the first only with DetailedDecals off).
-- Works for any vehicle with a VehicleScript, modded ones included: wheel count, offsets and
-- scale all come from the script at runtime (VehicleScript.Loaded already applies the model scale
-- to wheel offsets). Tire width is not readable from Lua (VehicleScript$Wheel.width is a public
-- field, never scaled), so it is estimated from the vehicle's track: 0.22 tiles on a car whose
-- left and right wheels are 1.32 apart, picked from ISnow.TRACK_WIDTHS. A motorcycle (track ~0)
-- gets the narrowest vehicle set, a semi truck the widest.
--
-- Bicycles of riding mods (ISnow.isCycling, ISnow_AnimalTracks.lua: Bicycle!, Workshop 3461415167)
-- are no vehicles: the game sees a player on foot holding an item, the pedalling is an animation.
-- Their rider leaves no boot prints (ISnow.isRiding), and the bicycle's two wheels roll like a
-- vehicle's (rollWheel) in its own narrow rut (ISnow.BIKE_TRACK_WIDTH, never picked for a vehicle):
-- the front one BIKE_FRONT ahead of the rider's position along where it faces, the rear one pulled
-- along behind it at the wheelbase, BIKE_FRONT + BIKE_REAR (it rolls where it points, so in a turn
-- it cuts inside the front wheel's rut, as on a real bicycle; it starts BIKE_REAR behind the rider).
-- Local players and, in MP, remote ones (the mod sets its variable on every client). A
-- remote rider no local player sees lays none, like its footprints. Snow thrown up, carried snow
-- and blood work as for a vehicle; the spray by its speed worked out from how far it went, BIKE_SPRAY
-- of a vehicle's.
--
-- Movement is detected from the vehicle position, not getCurrentSpeedKmHour: that returns 0 when
-- the vehicle's CarController is disabled (BaseVehicle.getCurrentSpeedKmHour), e.g. a towed
-- trailer may not report speed.
--
-- Rear wheels mostly roll in the front wheels' ruts: a segment that lands on a fresh one with
-- the same direction (sideways offset < DEDUP_SIDE) is skipped, so the rut does not get twice
-- as dark. Where the paths part (turns) the rear wheel draws its own rut.
--
-- Drifting and turning on the spot drive over the same snow again and again: every pass laid new
-- segments over the old ones, a few thousand decals in view (4000 cost 240 -> 75 fps, measured) and
-- solid black rings. So a DENSITY_CELL square takes at most DENSITY_PASSES passes of a wheel (a
-- pass: the segments one wheel lays from entering the square to leaving it; ruts and carried snow
-- together). A further pass there is dropped while the ones there are fresh (the spot already shows
-- tracks) and replaces the oldest pass (which fades out) once that is older than DENSITY_REFRESH, so the decal count
-- in view is bounded by the area driven over. Counting passes, not segments, keeps a front and a
-- rear rut side by side in a turn whole.
--
-- Snow carried on the tires: after a segment in snow the wheel's next CarriedSnowTireTiles on clear
-- ground leave white tread marks (strack_*), each fainter, which melt by the temperature of their
-- square (ISnow.Decals.carriedAger; options CarriedSnow*) and are as bright as the light there
-- (lit buffer, ISnow_Decals.lua); deduplicated like the ruts.
--
-- Snow thrown up by the wheels (SnowKickWheels, works with the tracks off too): every segment a wheel
-- lays in snow throws powder puffs, now and then a clump, the particles of the running feet
-- (ISnow_BlowOff.lua, BlowOff.kick) only bigger. How many grows with the speed (none below
-- SPRAY_FROM_KMH) and with the wheel sliding sideways (the angle between where it goes and where the
-- vehicle points: drifts, skids in a turn); they keep a little of the wheel's speed along its way, so
-- the spray trails behind. Per segment, so per distance driven: a faster vehicle throws more per
-- second as well. Every vehicle within VEHICLE_RADIUS, a remote or towed one included.
--
-- Bloody tire tracks (BloodyTireTracks, works with the tracks off and without snow too): a wheel
-- that runs over a corpse keeps leaving a red track for BloodyTireTrackTiles, full red, then paler
-- over the last of it (e.strength, ISnow.bloodStrength): blood soaked into the rut in snow
-- (brut_*), red tread marks on clear ground (btrack_*), both multiply textures (gen_tracks.py).
-- Only the wheels that went over the body, each its own: the body is vanilla's line of BODY_HALF
-- either way along its angle (BaseVehicle.testCollisionWithProneCharacter, bytecode 42.21; see
-- ISnow_Blood.lua), run over when a wheel point comes within WHEEL_REACH of it. Blood on the floor
-- does not count, nor a character still alive on the ground (2026-10-04: only the corpse, see
-- ISnow_Blood.lua). The vanilla blood
-- settings decide: none with sandbox BloodLevel 1 ("none", no splats at all) or blood decals 0.
-- MP: every client works it out on its own, like the tracks; corpses are on every client.
-- Wheels look for bodies only when they move, on the 3x3 squares around them, once per square
-- entered (or BLOOD_LOOK_MS), in the block "Blood under a wheel" below.

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_Decals"
require "ImmersiveSnow/ISnow_Blood"

local TireTracks = {}
ISnow.TireTracks = TireTracks

local POLL_TICKS = 3
local VEHICLE_RADIUS = 40        -- tiles around the player to look for vehicles
local RENDER_RADIUS = 45
local FULL_ALPHA_UNTIL = 0.25    -- ruts start to pale early, so older laps read lighter than fresh ones
local CARRIED_FULL_UNTIL = 0.4
local MOVED_EPS = 0.01           -- vehicle centre moved this far since last poll -> check wheels
local TURNED_EPS = 0.5           -- ... or turned this many degrees (turning on the spot)
local REF_TRACK = 1.32           -- left-right wheel distance of a vanilla car (CarLightsBulletinSheriff)
local REF_WIDTH = 0.22           -- its tire width
local TELEPORT_DIST = 4          -- a wheel jumping further than this resets its path
local STATE_TTL_MS = 60000       -- forget vehicles not seen for this long
local DEDUP_SIDE = 0.08          -- sideways offset under which two segments are "the same rut"
local DEDUP_DEG = 8.5             -- ... and direction difference, degrees (in whole TRACK_DIRS steps)
local DEDUP_FRESH = 0.05         -- only merge into segments younger than this (lifetime fraction)
local GRID = 0.25                -- dedup hash cell, world units
local DENSITY_CELL = 0.5         -- world units, see "Drifting" above
local DENSITY_PASSES = 2         -- wheel passes kept per density cell
local DENSITY_REFRESH = 0.05     -- lifetime fraction after which a pass may be replaced
local DEBUG_MAX = 800
-- Snow thrown up by the wheels (see above), times SnowKickWheelAmount and BlowOffAmount: puffs per
-- segment at SPRAY_FULL_KMH and over (a fraction is the chance of one; fewer down to none at
-- SPRAY_FROM_KMH), times 1 + SPRAY_SLIDE x sin(slide angle); the chance of a clump likewise; part of
-- the wheel's speed a particle keeps along its way, sideways spread (tiles / s); puff size (of a
-- running foot's) from slow to full speed.
local SPRAY_FROM_KMH = 5
local SPRAY_FULL_KMH = 40
local SPRAY_PUFFS = 0.35
local SPRAY_CRUMB = 0.05
local SPRAY_SLIDE = 1.5
local SPRAY_KEEP = { 0.05, 0.3 }
local SPRAY_SIDE = 0.8
local SPRAY_SCALE = { 1.2, 2.0 }
-- Bloody tire tracks (see above): they start to pale like the ruts; each of the two buffers (in snow,
-- on clear ground) holds up to this part of MaxTireTracks.
local BLOOD_FULL_UNTIL = 0.25
local BLOOD_LIMIT_PART = 0.25

local STEP = ISnow.TRACK_STEP
local DIRS = ISnow.TRACK_DIRS
local DEDUP_DIRS = math.floor(DEDUP_DEG * DIRS / 180)   -- 1 of 32 (3 of the former 64)
local DEDUP_ALONG = STEP / 2 + 0.02  -- chains of two wheels are out of phase by up to STEP / 2

local vec = nil                  -- Vector3f scratch
local VARIANTS = ISnow.TRACK_VARIANTS
local sets = {}                  -- [(widthIndex * DIRS + dir) * VARIANTS + variant] = texture paths by fade level
local carrySets = {}             -- [widthIndex * DIRS + dir] = snowy segment paths by alpha level (CARRIED_LEVELS)
local bloodRutSets = {}          -- [widthIndex * DIRS + dir] = blood in a snow rut by level (TRACK_BLOOD_LEVELS)
local bloodTreadSets = {}        -- [widthIndex * DIRS + dir] = bloody tread on clear ground by level
local anchorX, anchorY, anchorZ = 0, 0, 0   -- Render3DItem point for TRACK_SIZE textures
local markerX, markerY, markerZ = 0, 0, 0
local markerWheel, markerFwd = nil, nil     -- single-level sets
local ready = false
local snowActive = false
local debugTrail = false
local vehicles = {}              -- [vehicle] = { seen, x, y, at, angle, width, wheels = { [i] = { x, y } } }
local grid = {}                  -- [cellKey] = newest segment in that cell
local density = {}               -- [densityKey] = segments in that cell, oldest first
local bloodGrid = {}             -- [cellKey] = newest bloody segment in that cell (dedup)
local bloodOn = false            -- bloody tire tracks on (option and vanilla blood settings), this poll
local stats = { vehicles = 0, near = 0, moving = 0, bikesMoving = 0, placed = 0, carried = 0, noSnow = 0, merged = 0, crowded = 0,
    replaced = 0, errors = 0, puffs = 0, crumbs = 0, bloodied = 0, bloody = 0, bloodMerged = 0 }
local lastError = nil

local function gridKey(x, y)
    return math.floor(x / GRID) * 1048576 + math.floor(y / GRID)
end

local function densityKey(x, y)
    return math.floor(x / DENSITY_CELL) * 1048576 + math.floor(y / DENSITY_CELL)
end

-- Segment e leaves: out of the dedup grid and its density cell.
local function forget(e)
    if grid[e.key] == e then grid[e.key] = nil end
    local list = density[e.dkey]
    if not list then return end
    for i = 1, #list do
        if list[i] == e then
            table.remove(list, i)
            break
        end
    end
    if #list == 0 then density[e.dkey] = nil end
end

-- Above TireTrackSoftLimit segments the oldest fade out over a while (ISnow_Decals.lua, soft limit),
-- MaxTireTracks is the hard limit.
local function maxTracks() return ISnow.opt("MaxTireTracks") end
local function softTracks() return ISnow.opt("TireTrackSoftLimit") end
local tracks = ISnow.Decals.newBuffer(maxTracks, forget, FULL_ALPHA_UNTIL, false, true, nil, softTracks)
local carried = ISnow.Decals.newBuffer(maxTracks, forget, CARRIED_FULL_UNTIL, true, nil, nil, softTracks)

-- Bloody segments: in snow (gone with the snow) and on clear ground; multiply, not lit, e.strength.
local function maxBlood() return math.max(20, math.floor(maxTracks() * BLOOD_LIMIT_PART)) end
local function forgetBlood(e)
    if bloodGrid[e.key] == e then bloodGrid[e.key] = nil end
end
local bloodSnow = ISnow.Decals.newBuffer(maxBlood, forgetBlood, BLOOD_FULL_UNTIL, false, true)
local bloodGround = ISnow.Decals.newBuffer(maxBlood, forgetBlood, BLOOD_FULL_UNTIL, false, true)

-- Adds segment e, laid by wheel (its state; nil: a pass of its own), to buffer unless its density
-- cell is full, see "Drifting" above. Returns false when it was dropped.
local function addSegment(buffer, e, wheel)
    e.key = gridKey(e.x, e.y)
    e.dkey = densityKey(e.x, e.y)
    if wheel then
        if wheel.dkey ~= e.dkey then
            wheel.dkey = e.dkey
            wheel.pass = {}
        end
        e.pass = wheel.pass
    else
        e.pass = e
    end
    local list = density[e.dkey]
    if not list then
        list = {}
        density[e.dkey] = list
    end
    local passes, known = {}, false
    for i = 1, #list do
        local p = list[i].pass
        if p == e.pass then known = true end
        passes[p] = true
    end
    if not known then
        local n = 0
        for _ in pairs(passes) do n = n + 1 end
        if n >= DENSITY_PASSES then
            local oldest = list[1]
            if oldest.buffer:ageOf(oldest) < DENSITY_REFRESH then
                stats.crowded = stats.crowded + 1
                return false
            end
            -- the old pass fades out under the new one
            local p = oldest.pass
            local now = getTimestampMs()
            for i = #list, 1, -1 do
                local old = list[i]
                if old.pass == p then
                    forget(old)
                    old.buffer:fadeOut(old, now)
                end
            end
            stats.replaced = stats.replaced + 1
        end
    end
    e.buffer = buffer
    buffer:push(e)
    table.insert(list, e)
    grid[e.key] = e
    return true
end

local markers = ISnow.Decals.newBuffer(function() return DEBUG_MAX end, nil, 1, false, false, 0)

-- Bicycles, see the top: wheel distances from the rider's position (tiles; Bicycle! 5.3.1 model
-- Bicycle_Frame: front wheel 0.39 ahead of the frame origin, rear 0.22 behind, the origin under the
-- rider's hands), part of a vehicle's snow thrown up.
local BIKE_FRONT = 0.55
local BIKE_REAR = 0.4
local BIKE_SPRAY = 0.5
local bikes = {}                 -- [player] = state as vehicles', width = ISnow.BIKE_TRACK_WIDTH

local function dirIndex(ux, uy)
    local a = math.atan2(uy, ux)
    if a < 0 then a = a + math.pi end
    return math.floor(a / math.pi * DIRS + 0.5) % DIRS
end

local function dirDiff(a, b)
    local d = math.abs(a - b) % DIRS
    return math.min(d, DIRS - d)
end

-- IsoCell:getVehicles() is a java.util.HashSet (IsoCell.<init>), so no :get(i). Kahlua resolves
-- methods through superclasses and interfaces (KahluaThread.getClassMetatable), and
-- java.util.Iterator is exposed, so the iterator works from Lua.
local function forEachVehicleNear(x, y, r, fn)
    local r2 = r * r
    local total = 0
    local it = getCell():getVehicles():iterator()
    while it:hasNext() do
        local v = it:next()
        total = total + 1
        local vx, vy = v:getX(), v:getY()
        local dx, dy = vx - x, vy - y
        local d2 = dx * dx + dy * dy
        if d2 <= r2 then fn(v, d2, vx, vy) end
    end
    return total
end

local function wheelPos(vehicle, wheel)
    vehicle:getWorldPos(wheel:getOffset(), vec)
    return vec:x(), vec:y()
end

local function addMarker(x, y, z, set)
    markers:push({ x = x + markerX, y = y + markerY, z = z, rz = z + markerZ, set = set })
end

-- Snow thrown up off a wheel at x, y, z going along ux, uy (a segment in snow); s: sprayFor.
local function sprayAt(x, y, z, ux, uy, s)
    local blow = ISnow.BlowOff
    -- sin of the angle between the wheel's way and the vehicle's heading
    local more = 1 + SPRAY_SLIDE * math.abs(ux * s.fy - uy * s.fx)
    local scale = SPRAY_SCALE[1] + (SPRAY_SCALE[2] - SPRAY_SCALE[1]) * s.t
    local n = SPRAY_PUFFS * s.t * more * s.amount
    while n > 0 do
        if n >= 1 or ZombRandFloat(0, 1) < n then
            local keep, side = ZombRandFloat(SPRAY_KEEP[1], SPRAY_KEEP[2]) * s.speed, ZombRandFloat(-1, 1) * SPRAY_SIDE
            blow.kick(x, y, z, ux * keep - uy * side, uy * keep + ux * side, false, scale, s.vehicle)
            stats.puffs = stats.puffs + 1
        end
        n = n - 1
    end
    if ZombRandFloat(0, 1) < SPRAY_CRUMB * s.t * more * s.amount then
        local keep, side = ZombRandFloat(SPRAY_KEEP[1], SPRAY_KEEP[2]) * s.speed, ZombRandFloat(-1, 1) * SPRAY_SIDE
        blow.kick(x, y, z, ux * keep - uy * side, uy * keep + ux * side, true, scale, s.vehicle)
        stats.crumbs = stats.crumbs + 1
    end
end

-- Blood under a wheel ---------------------------------------------------------------------------
-- Whether a wheel at a point runs over a corpse. Whether blood is shown at all and the corpses (lines
-- along the bodies) are ISnow_Blood.lua's, shared with the bloody footprints.
-- A wheel point this close to a body's line runs over it. Vanilla uses the wheel's radius
-- (VehicleScript$Wheel.radius, 0.3..0.5 in the vanilla scripts), a public field without a getter,
-- not readable from Lua. Segments are STEP apart, so a body across the way is always within reach.
local WHEEL_REACH = 0.35
local BLOOD_LOOK_MS = 250    -- a wheel on the same square looks for bodies again after this long

-- Whether the vanilla blood settings allow blood (ISnow.Blood.enabled: sandbox BloodLevel, the
-- Blood decals display option).
local function bloodAllowed()
    return ISnow.Blood.enabled()
end

-- Whether the wheel (its state l) at x, y, z goes over a corpse now. The squares are looked at when
-- the wheel enters a new one or after BLOOD_LOOK_MS, the bodies' lines every call.
local function bloodUnder(cell, l, x, y, z, now)
    local sx, sy = math.floor(x), math.floor(y)
    if l.bsx ~= sx or l.bsy ~= sy or l.bz ~= z or now - l.bAt >= BLOOD_LOOK_MS or now < l.bAt then
        l.bsx, l.bsy, l.bz, l.bAt = sx, sy, z, now
        l.bodies = ISnow.Blood.corpses(cell, sx, sy, z)
    end
    return ISnow.Blood.over(x, y, l.bodies, WHEEL_REACH)
end
-- End of "Blood under a wheel" ---------------------------------------------------------------------

-- Whether a fresh segment in grid g (ruts or bloody ones) at x, y, z along ux, uy (dir) is the same
-- as this one: the rear wheel in the front wheel's rut.
local function duplicate(g, x, y, z, ux, uy, dir)
    local gx, gy = math.floor(x / GRID), math.floor(y / GRID)
    for i = -1, 1 do
        for j = -1, 1 do
            local e = g[(gx + i) * 1048576 + gy + j]
            if e and e.z == z and e.buffer:ageOf(e) < DEDUP_FRESH and dirDiff(e.dir, dir) <= DEDUP_DIRS then
                local dx, dy = e.x - x, e.y - y
                if math.abs(dx * ux + dy * uy) < DEDUP_ALONG and math.abs(dy * ux - dx * uy) < DEDUP_SIDE then
                    return true
                end
            end
        end
    end
    return false
end

-- A bloody segment of wheel (its state, blood left) at (mx, my) on square sx, sy: soaked into the rut
-- on snow, a red tread print on clear ground with a floor. Uses up one segment of the blood either way.
local function placeBlood(cell, mx, my, z, ux, uy, dir, width, wheel, snowy, sx, sy)
    local left = wheel.blood
    wheel.blood = left - 1
    local buffer, set = bloodSnow, bloodRutSets[width * DIRS + dir]
    if not snowy then
        local sq = cell:getGridSquare(sx, sy, z)
        if not sq or not sq:getFloor() then return end
        buffer, set = bloodGround, bloodTreadSets[width * DIRS + dir]
    end
    local x, y = mx + anchorX, my + anchorY
    if duplicate(bloodGrid, x, y, z, ux, uy, dir) then
        stats.bloodMerged = stats.bloodMerged + 1
        return
    end
    local e = { x = x, y = y, z = z, rz = z + anchorZ, set = set, dir = dir, sx = sx, sy = sy,
        strength = ISnow.bloodStrength(left, wheel.bloodMax), key = gridKey(x, y), buffer = buffer }
    buffer:push(e)
    bloodGrid[e.key] = e
    stats.bloody = stats.bloody + 1
end

-- A segment of the rut centred at (mx, my), pointing along (ux, uy); wheel: its state (carried snow,
-- blood); spray: the snow thrown up (sprayFor), nil for none.
local function placeSegment(mx, my, z, ux, uy, dir, width, wheel, spray)
    if debugTrail then addMarker(mx, my, z, markerWheel) end
    local tracksOn = snowActive and ISnow.opt("TireTracks")
    local bloody = bloodOn and (wheel.blood or 0) > 0
    if not tracksOn and not spray and not bloody then return end

    local sx, sy = math.floor(mx), math.floor(my)
    local cell = getCell()
    local snowy = snowActive and ISnow.Decals.isSnowSquare(cell, sx, sy, z)
    if snowy and spray then sprayAt(mx, my, z, ux, uy, spray) end
    if bloody then placeBlood(cell, mx, my, z, ux, uy, dir, width, wheel, snowy, sx, sy) end
    if not tracksOn then return end
    local buffer, set, strength = tracks, sets[(width * DIRS + dir) * VARIANTS + ISnow.decalVariant(VARIANTS)], nil
    if snowy then
        wheel.carryMax = math.max(1, math.floor(ISnow.opt("CarriedSnowTireTiles") / STEP + 0.5))
        wheel.carry = wheel.carryMax
    else
        stats.noSnow = stats.noSnow + 1
        local left = wheel.carry or 0
        if left <= 0 then return end
        wheel.carry = left - 1
        local sq = cell:getGridSquare(sx, sy, z)
        if not sq or not sq:getFloor() or not ISnow.opt("CarriedSnow") then return end
        buffer = carried
        set = carrySets[width * DIRS + dir]
        strength = math.min(1, left / (wheel.carryMax or left))
    end

    local x, y = mx + anchorX, my + anchorY
    if duplicate(grid, x, y, z, ux, uy, dir) then
        stats.merged = stats.merged + 1
        return
    end

    if not addSegment(buffer, { x = x, y = y, z = z, rz = z + anchorZ, set = set, dir = dir, sx = sx, sy = sy,
            strength = strength }, wheel) then
        return
    end
    if buffer == carried then stats.carried = stats.carried + 1 else stats.placed = stats.placed + 1 end
end

-- Texture set for the vehicle: tire width estimated from the widest left-right wheel distance.
local function widthIndex(script)
    local track = 0
    for i = 0, script:getWheelCount() - 1 do
        track = math.max(track, 2 * math.abs(script:getWheel(i):getOffset():x()))
    end
    local width = REF_WIDTH * track / REF_TRACK
    local widths = ISnow.TRACK_WIDTHS
    local best, bestD = 0, 1e30
    for i = 1, #widths do
        local d = math.abs(widths[i] - width)
        if d < bestD and i - 1 ~= ISnow.BIKE_TRACK_WIDTH then best, bestD = i - 1, d end
    end
    return best, track
end

-- Speed in km/h of what went from its state st (position and time of its last move) to x, y by now.
local function speedSince(st, x, y, now)
    if not st.at or now <= st.at then return 0 end
    local dx, dy = x - st.x, y - st.y
    return math.sqrt(dx * dx + dy * dy) * 3600 / (now - st.at)
end

-- How wheels at kmh throw up snow in this poll, part (1: a vehicle's) of the options' amount:
-- { t = 0..1 of the full amount by speed, amount, speed = tiles / s, fx, fy = heading, vehicle =
-- the body that may hide it, or nil }; nil for none (off, too slow).
local function sprayAtSpeed(kmh, part, fx, fy, owner)
    if not ISnow.opt("SnowKickWheels") then return nil end
    local blow = ISnow.BlowOff
    if not (blow and blow.kick) then return nil end
    local t = math.min(1, (kmh - SPRAY_FROM_KMH) / (SPRAY_FULL_KMH - SPRAY_FROM_KMH))
    if t <= 0 then return nil end
    local amount = ISnow.opt("SnowKickWheelAmount") * ISnow.opt("BlowOffAmount") * part
    if amount <= 0 then return nil end
    return { t = t, amount = amount, speed = kmh / 3.6, fx = fx, fy = fy, vehicle = owner }
end

-- How vehicle v throws up snow from its wheels in this poll, before its state st takes x, y (its
-- position now), see sprayAtSpeed.
local function sprayFor(v, st, x, y, now)
    if not ISnow.opt("SnowKickWheels") then return nil end
    local kmh = math.abs(v:getCurrentSpeedKmHour())
    if kmh < 1 then
        -- no speed reported (a towed trailer, see above): from how far it went since the last move
        kmh = speedSince(st, x, y, now)
    end
    v:getForwardVector(vec)
    return sprayAtSpeed(kmh, 1, vec:x(), vec:z(), v)
end

-- Rolls wheel i of st (a vehicle's or a bicycle's state, its texture width st.width) to x, y on
-- level z: a segment for every STEP it went (spray: sprayAtSpeed or nil). hidden: none, the wheel
-- only follows (a remote rider no local player sees).
local function rollWheel(st, i, x, y, z, now, spray, hidden)
    local l = st.wheels[i]
    if not l then
        st.wheels[i] = { x = x, y = y }
        return
    end
    local dx, dy = x - l.x, y - l.y
    local d2 = dx * dx + dy * dy
    if hidden or d2 > TELEPORT_DIST * TELEPORT_DIST then
        l.x, l.y = x, y
        return
    end
    if d2 < STEP * STEP then return end
    local d = math.sqrt(d2)
    local ux, uy = dx / d, dy / d
    local dir = dirIndex(ux, uy)
    for _ = 1, math.floor(d / STEP) do
        local nx, ny = l.x + ux * STEP, l.y + uy * STEP
        if bloodOn and bloodUnder(getCell(), l, nx, ny, z, now) then
            stats.bloodied = stats.bloodied + 1
            local segments = math.max(1, math.floor(ISnow.opt("BloodyTireTrackTiles") / STEP + 0.5))
            l.blood, l.bloodMax = segments, segments
        end
        placeSegment((l.x + nx) / 2, (l.y + ny) / 2, z, ux, uy, dir, st.width, l, spray)
        l.x, l.y = nx, ny
    end
end

-- x, y: the vehicle's position (forEachVehicleNear has it already).
local function trackVehicle(v, now, x, y)
    local angle = v:getAngleZ()
    local st = vehicles[v]
    if not st then
        st = { x = x, y = y, at = now, angle = angle, wheels = {} }
        vehicles[v] = st
    end
    st.seen = now
    local da = math.abs(angle - st.angle) % 360
    if math.abs(x - st.x) + math.abs(y - st.y) < MOVED_EPS and math.min(da, 360 - da) < TURNED_EPS then return end
    local spray = snowActive and sprayFor(v, st, x, y, now)
    st.x, st.y, st.at, st.angle = x, y, now, angle
    stats.moving = stats.moving + 1

    local script = v:getScript()
    if not script then return end
    if not st.width then st.width = widthIndex(script) end
    local z = math.floor(v:getZ())
    for i = 0, script:getWheelCount() - 1 do
        local wx, wy = wheelPos(v, script:getWheel(i))
        rollWheel(st, i, wx, wy, z, now, spray)
    end
end

-- Where the wheels of a bicycle ridden by p at x, y are now (its state st, or nil): front x, y,
-- rear x, y. The rear one is pulled after the front one from where it was (st.rx, st.ry); first
-- (and after a jump) BIKE_REAR behind the rider.
local function bikeWheels(p, x, y, st)
    local fx, fy = p:getForwardDirectionX(), p:getForwardDirectionY()
    local ax, ay = x + fx * BIKE_FRONT, y + fy * BIKE_FRONT
    if st and st.rx then
        local dx, dy = ax - st.rx, ay - st.ry
        local d = math.sqrt(dx * dx + dy * dy)
        if d > 0.01 and d < TELEPORT_DIST then
            local base = BIKE_FRONT + BIKE_REAR
            return ax, ay, ax - dx / d * base, ay - dy / d * base
        end
    end
    return ax, ay, x - fx * BIKE_REAR, y - fy * BIKE_REAR
end

-- A bicycle ridden by p at x, y (see the top); hidden: a remote rider no local player sees.
local function trackBike(p, now, x, y, hidden)
    local fx, fy = p:getForwardDirectionX(), p:getForwardDirectionY()
    local angle = math.deg(math.atan2(fy, fx))
    local st = bikes[p]
    if not st then
        st = { x = x, y = y, at = now, angle = angle, wheels = {}, width = ISnow.BIKE_TRACK_WIDTH }
        bikes[p] = st
    end
    st.seen = now
    local da = math.abs(angle - st.angle) % 360
    if math.abs(x - st.x) + math.abs(y - st.y) < MOVED_EPS and math.min(da, 360 - da) < TURNED_EPS then return end
    local spray = snowActive and not hidden and sprayAtSpeed(speedSince(st, x, y, now), BIKE_SPRAY, fx, fy, nil)
    st.x, st.y, st.at, st.angle = x, y, now, angle
    stats.bikesMoving = stats.bikesMoving + 1
    local z = math.floor(p:getZ())
    local ax, ay, bx, by = bikeWheels(p, x, y, st)
    st.rx, st.ry = bx, by
    rollWheel(st, 0, ax, ay, z, now, spray, hidden)
    rollWheel(st, 1, bx, by, z, now, spray, hidden)
end

-- Whether a local player sees chr (the game hides remote players out of their sight).
local function seenByLocalPlayer(chr)
    for i = 0, getNumActivePlayers() - 1 do
        if getSpecificPlayer(i) and chr:getTargetAlpha(i) > 0 then return true end
    end
    return false
end

-- The bicycles ridden within VEHICLE_RADIUS of px, py: by the local players, then by remote ones.
local function pollBikes(now, px, py)
    stats.bikesMoving = 0
    if not ISnow.isCycling then return end
    local r2 = VEHICLE_RADIUS * VEHICLE_RADIUS
    local function look(p, remote)
        if not p or p:isDead() or p:getVehicle() then return end
        local x, y = p:getX(), p:getY()
        local dx, dy = x - px, y - py
        if dx * dx + dy * dy > r2 or not ISnow.isCycling(p) then return end
        trackBike(p, now, x, y, remote and not seenByLocalPlayer(p))
    end
    for i = 0, getNumActivePlayers() - 1 do look(getSpecificPlayer(i), false) end
    local others = isClient() and ISnow.otherPlayers() or nil
    if not others then return end
    for i = 0, others:size() - 1 do
        local p = others:get(i)
        if p and not p:isLocalPlayer() then look(p, true) end
    end
end

-- Every vehicle of the cell (a town's parking lots) is gone through only every NEAR_MS or
-- NEAR_POLLS polls, whichever comes first, for those within VEHICLE_RADIUS + NEAR_MARGIN; the
-- polls between look at those alone. A vehicle that comes nearer faster than the margin allows
-- (two vehicles closing in at over 100 km/h each) starts its tracks a little later.
local NEAR_MS = 500
local NEAR_POLLS = 10
local NEAR_MARGIN = 30
local nearList = {}
local nearAt, nearPolls = nil, 0

local function poll()
    local p = getSpecificPlayer(0)
    if not p then return end
    local now = getTimestampMs()
    local px, py = p:getX(), p:getY()
    nearPolls = nearPolls + 1
    if not nearAt or now - nearAt >= NEAR_MS or now < nearAt or nearPolls >= NEAR_POLLS then
        nearAt, nearPolls = now, 0
        local list = {}
        stats.vehicles = forEachVehicleNear(px, py, VEHICLE_RADIUS + NEAR_MARGIN, function(v)
            list[#list + 1] = v
        end)
        nearList = list
    end
    local near = 0
    local r2 = VEHICLE_RADIUS * VEHICLE_RADIUS
    stats.moving = 0
    for i = 1, #nearList do
        local v = nearList[i]
        local x, y = v:getX(), v:getY()
        local dx, dy = x - px, y - py
        if dx * dx + dy * dy <= r2 then
            near = near + 1
            trackVehicle(v, now, x, y)
        end
    end
    stats.near = near
    pollBikes(now, px, py)
end

local tickCounter = 0
local function onTick()
    tickCounter = tickCounter + 1
    if tickCounter % POLL_TICKS ~= 0 or not vec then return end
    -- bloody tracks in any season: blood on asphalt needs no snow
    bloodOn = ISnow.opt("BloodyTireTracks") == true and bloodAllowed()
    if not debugTrail and not bloodOn and not (snowActive and (ISnow.opt("TireTracks") or ISnow.opt("SnowKickWheels"))) then
        return
    end
    local ok, err = pcall(poll)
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
    end
end

local function onRender(playerIndex)
    if not ready then return end
    tracks:render(playerIndex, RENDER_RADIUS)
    bloodSnow:render(playerIndex, RENDER_RADIUS)    -- over the ruts
    carried:render(playerIndex, RENDER_RADIUS)
    bloodGround:render(playerIndex, RENDER_RADIUS)
    markers:render(playerIndex, RENDER_RADIUS)
end

local function onRenderSafe(playerIndex)
    local ok, err = pcall(onRender, playerIndex)
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
    end
end

-- Removes the bloody segments in snow (snowOnly) or all of them.
local function clearBlood(snowOnly)
    bloodSnow:clear()
    if snowOnly then
        for k, e in pairs(bloodGrid) do
            if e.buffer == bloodSnow then bloodGrid[k] = nil end
        end
    else
        bloodGround:clear()
        bloodGrid = {}
    end
end

-- Removes the carried snow segments, from grid and density too (Buffer:clear does not call forget:
-- left there, they kept new carried segments out as duplicates or a full cell until the snow went).
local function clearCarried()
    if carried:count() == 0 then return end
    carried:clear()
    local function notCarried(_, e) return e.buffer ~= carried end
    ISnow.prune(grid, notCarried)
    for k, list in pairs(density) do
        for i = #list, 1, -1 do
            if list[i].buffer == carried then table.remove(list, i) end
        end
    end
    ISnow.prune(density, function(_, list) return #list > 0 end)
end

local function clearTracks()
    tracks:clear()
    carried:clear()
    grid = {}
    density = {}
end

local function refreshSnowState()
    snowActive = ISnow.Decals.snowActive()
    bloodOn = ISnow.opt("BloodyTireTracks") == true and bloodAllowed()
    if not bloodOn then   -- off, here or in Options > Mods, or no blood in vanilla: gone at once
        clearBlood(false)
    elseif not snowActive then   -- the blood in the snow goes with it
        clearBlood(true)
    end
    if not snowActive then
        clearTracks()
    elseif not ISnow.opt("TireTracks") then   -- off in Options > Mods: gone at once
        if not debugTrail then clearTracks() end
    elseif not ISnow.opt("CarriedSnow") then
        clearCarried()
    end
end

local function onEveryOneMinute()
    refreshSnowState()
    tracks:age(ISnow.Decals.agePerMinute(ISnow.opt("TireTrackHours")))
    carried:ageEach(ISnow.Decals.carriedAger())
    local hours = ISnow.opt("TireTrackHours")
    bloodSnow:age(ISnow.Decals.agePerMinute(hours))
    -- red tread on clear ground: no snowfall covers it (a garage, under a roof), as the bloody
    -- prints on clear ground (bloodAger in ISnow_Footprints.lua)
    bloodGround:age(1 / 60 / math.max(0.1, hours))

    local now = getTimestampMs()
    for v, st in pairs(vehicles) do
        if now - st.seen > STATE_TTL_MS then vehicles[v] = nil end
    end
    for p, st in pairs(bikes) do
        if now - st.seen > STATE_TTL_MS then bikes[p] = nil end
    end
end

-- 0.5.2 moved the SnowKickWheelAmount default from 1 to 0.8 (ISnow.migrateDefault: old SP saves too),
-- the red tracks from 8 to 2 tiles (12 for a while before the release, then the author: 2 m behind
-- the vehicle is enough; saves made then go to 2 too), the bloody footprints from 6 to 8 steps (14
-- for a while before the release was too long: saves made then go to 8 too).
-- Each on its own: one failing does not keep the others back.
local MIGRATIONS_052 = {
    { "wheelAmount052", "SnowKickWheelAmount", 1, 0.8 },
    { "bloodTiles052", "BloodyTireTrackTiles", 8, 2 },
    { "bloodTiles052b", "BloodyTireTrackTiles", 12, 2 },
    { "bloodSteps052", "BloodyFootprintSteps", 6, 8 },
    { "bloodSteps052b", "BloodyFootprintSteps", 14, 8 },
}

local function onGameStart()
    for _, m in ipairs(MIGRATIONS_052) do
        local okMigrate, errMigrate = pcall(ISnow.migrateDefault, m[1], m[2], m[3], m[4])
        if not okMigrate then print("[ImmersiveSnow] " .. m[2] .. " default not moved: " .. tostring(errMigrate)) end
    end
    local ok, err = pcall(function()
        vec = Vector3f.new()
        -- only the paths: a set's textures load with its first segment (ISnow.Decals.newSet)
        for w = 0, #ISnow.TRACK_WIDTHS - 1 do
            for dir = 0, DIRS - 1 do
                for v = 0, VARIANTS - 1 do
                    sets[(w * DIRS + dir) * VARIANTS + v] = ISnow.Decals.newSet(
                        function(level) return ISnow.trackFile(w, dir, v, level) end, ISnow.FADE_LEVELS)
                end
                carrySets[w * DIRS + dir] = ISnow.Decals.newSet(
                    function(level) return ISnow.carriedTrackFile(w, dir, level) end, ISnow.CARRIED_LEVELS)
                bloodRutSets[w * DIRS + dir] = ISnow.Decals.newSet(
                    function(level) return ISnow.bloodRutFile(w, dir, level) end, ISnow.TRACK_BLOOD_LEVELS)
                bloodTreadSets[w * DIRS + dir] = ISnow.Decals.newSet(
                    function(level) return ISnow.bloodTrackFile(w, dir, level) end, ISnow.TRACK_BLOOD_LEVELS)
            end
        end
        anchorX, anchorY, anchorZ = ISnow.Decals.anchor(ISnow.TRACK_SIZE, ISnow.TRACK_REACH)
        markerWheel = ISnow.Decals.newSet(function() return "marker_wheel.png" end, 1)
        markerFwd = ISnow.Decals.newSet(function() return "marker_fwd.png" end, 1)
        markerX, markerY, markerZ = ISnow.Decals.anchor(ISnow.MARKER_SIZE, ISnow.MARKER_REACH)
        ready = true
    end)
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
        print("[ImmersiveSnow] tire tracks init failed: " .. lastError)
    end
    refreshSnowState()
end

-- Debug console helpers ------------------------------------------------------

local function textureInfo(tex)
    return tex and (tex:getWidth() .. "x" .. tex:getHeight()) or "MISSING"
end

local function nearestVehicle()
    local p = getSpecificPlayer(0)
    local best, bestD2 = nil, 1e30
    forEachVehicleNear(p:getX(), p:getY(), VEHICLE_RADIUS, function(v, d2)
        if d2 < bestD2 then best, bestD2 = v, d2 end
    end)
    return best, bestD2
end

function TireTracks.stats()
    local near = 0
    local total = forEachVehicleNear(getSpecificPlayer(0):getX(), getSpecificPlayer(0):getY(), VEHICLE_RADIUS,
        function() near = near + 1 end)
    print(string.format("[ImmersiveSnow] tracks: enabled=%s snowActive=%s vehiclesInCell=%d near=%d movingLastPoll=%d segments=%d (fading %d) drawnLastFrame=%d max=%d",
        tostring(ISnow.opt("TireTracks")), tostring(snowActive), total, near, stats.moving, tracks:count(), tracks:fading(),
        tracks.drawn, ISnow.opt("MaxTireTracks")))
    print(string.format("[ImmersiveSnow] tracks: placed=%d merged=%d crowded=%d replaced=%d noSnow=%d expired=%d pushedOut=%d errors=%d markers=%d debugTrail=%s carried=%d (placed %d, drawn %d)",
        stats.placed, stats.merged, stats.crowded, stats.replaced, stats.noSnow, tracks.expired, tracks.evicted, stats.errors, markers:count(),
        tostring(debugTrail), carried:count(), stats.carried, carried.drawn))
    print(string.format("[ImmersiveSnow] snow off the wheels: on=%s puffs=%d clumps=%d",
        tostring(ISnow.opt("SnowKickWheels")), stats.puffs, stats.crumbs))
    print(string.format("[ImmersiveSnow] bloody tracks: on=%s allowed=%s stepsInBlood=%d laid=%d deduped=%d inSnow=%d (drawn %d) onGround=%d (drawn %d) max=%d",
        tostring(ISnow.opt("BloodyTireTracks")), tostring(bloodAllowed()), stats.bloodied, stats.bloody, stats.bloodMerged,
        bloodSnow:count(), bloodSnow.drawn, bloodGround:count(), bloodGround.drawn, maxBlood()))
    local last = #ISnow.TRACK_WIDTHS * DIRS * VARIANTS - 1
    local firstTex, lastTex = sets[0] and ISnow.Decals.ensureSet(sets[0]), sets[last] and ISnow.Decals.ensureSet(sets[last])
    local markerTex = markerWheel and ISnow.Decals.ensureSet(markerWheel)
    print("[ImmersiveSnow] textures: " .. ISnow.trackFile(0, 0, 0, ISnow.FADE_LEVELS) .. " " .. textureInfo(firstTex) ..
        ", last " .. textureInfo(lastTex) .. ", marker " .. textureInfo(markerTex) ..
        string.format(", anchor=%.4f,%.4f,%.4f, carrier=%s", anchorX, anchorY, anchorZ,
            tostring(ISnow.Decals.carrier() ~= nil)))
    if lastError then print("[ImmersiveSnow] last error: " .. lastError) end
    local followed = 0
    for _ in pairs(bikes) do followed = followed + 1 end
    print(string.format("[ImmersiveSnow] bicycles: player0Cycling=%s followed=%d movingLastPoll=%d",
        tostring(ISnow.isCycling ~= nil and ISnow.isCycling(getSpecificPlayer(0))), followed, stats.bikesMoving))

    local v, d2 = nearestVehicle()
    if not v then
        print("[ImmersiveSnow] no vehicle within " .. VEHICLE_RADIUS .. " tiles")
        return
    end
    local script = v:getScript()
    v:getForwardVector(vec)
    local fx, fy, fz = vec:x(), vec:y(), vec:z()
    print(string.format("[ImmersiveSnow] nearest %s dist=%.1f pos=%.2f,%.2f,%.2f angleZ=%.1f speed=%.1fkmh fwd(phys)=%.2f,%.2f,%.2f skid=%.2f",
        script and script:getName() or "?", math.sqrt(d2), v:getX(), v:getY(), v:getZ(), v:getAngleZ(),
        v:getCurrentSpeedKmHour(), fx, fy, fz, v:getMinWheelSkid()))
    if not script then return end
    local wi, track = widthIndex(script)
    print(string.format("[ImmersiveSnow]   script=%s modelScale=%.2f wheels=%d track=%.2f tireWidth=%.2f (set %d)",
        script:getFullName(), script:getModelScale(), script:getWheelCount(), track, ISnow.TRACK_WIDTHS[wi + 1], wi))
    for i = 0, script:getWheelCount() - 1 do
        local w = script:getWheel(i)
        local o = w:getOffset()
        local x, y = wheelPos(v, w)
        local tire = v:getPartById("Tire" .. w:getId())
        print(string.format("[ImmersiveSnow]   wheel %d %s offset=%.2f,%.2f,%.2f world=%.2f,%.2f snow=%s tire=%s",
            i, w:getId(), o:x(), o:y(), o:z(), x, y,
            tostring(getCell():gridSquareIsSnow(math.floor(x), math.floor(y), math.floor(v:getZ()))),
            tire and (tire:getInventoryItem() and "yes" or "removed") or "no part"))
    end
end

-- Leaves red markers where the wheels of the nearest vehicle are now, and yellow dots ahead of it
-- along getForwardVector. Drive the vehicle away to see them. Player 0 on a bicycle: its wheels.
function TireTracks.markWheels()
    local p = getSpecificPlayer(0)
    if ISnow.isCycling and ISnow.isCycling(p) then
        local ax, ay, bx, by = bikeWheels(p, p:getX(), p:getY(), bikes[p])
        local z = math.floor(p:getZ())
        addMarker(ax, ay, z, markerWheel)
        addMarker(bx, by, z, markerWheel)
        TireTracks.stats()
        return
    end
    local v = nearestVehicle()
    if not v then
        print("[ImmersiveSnow] no vehicle within " .. VEHICLE_RADIUS .. " tiles")
        return
    end
    local script = v:getScript()
    local z = math.floor(v:getZ())
    for i = 0, script:getWheelCount() - 1 do
        local x, y = wheelPos(v, script:getWheel(i))
        addMarker(x, y, z, markerWheel)
    end
    v:getForwardVector(vec)
    local fx, fy = vec:x(), vec:z()
    for k = 1, 6 do
        local d = 1 + k * 0.4
        addMarker(v:getX() + fx * d, v:getY() + fy * d, z, markerFwd)
    end
    TireTracks.stats()
end

-- Toggles a red marker at the centre of every segment of moving vehicles nearby (ignores snow).
function TireTracks.debugTrail(on)
    if on == nil then on = not debugTrail end
    debugTrail = on
    print("[ImmersiveSnow] debugTrail=" .. tostring(debugTrail))
end

-- Lays n segments (default 4000) on circles of radius 2..6 around the player, like doing donuts
-- on the spot, ignoring snow: for measuring the render cost of many tracks in view.
function TireTracks.stress(n)
    n = n or 4000
    local p = getSpecificPlayer(0)
    local z = math.floor(p:getZ())
    for i = 0, n - 1 do
        local r = 2 + (i % 5)
        local a = i * STEP / r
        local ux, uy = -math.sin(a), math.cos(a)
        local x, y = p:getX() + r * math.cos(a) + anchorX, p:getY() + r * math.sin(a) + anchorY
        addSegment(tracks, { x = x, y = y, z = z, rz = z + anchorZ,
            set = sets[(1 * DIRS + dirIndex(ux, uy)) * VARIANTS + i % VARIANTS],
            dir = dirIndex(ux, uy), sx = math.floor(x), sy = math.floor(y) })
    end
    tracks:compact()
    return tracks:count()
end

-- Removes all tracks and debug markers.
function TireTracks.clear()
    clearTracks()
    clearBlood(false)
    markers:clear()
end

Events.OnGameStart.Add(onGameStart)
Events.EveryOneMinute.Add(onEveryOneMinute)
ISnow.listen("OnTick", "TireTracks", onTick)
ISnow.listen("RenderOpaqueObjectsInWorld", "TireTracks", onRenderSafe)
