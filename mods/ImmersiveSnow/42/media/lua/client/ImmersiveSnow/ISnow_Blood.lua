-- Immersive Snow: what soaks the soles and the tires in blood: a corpse stepped or driven on, for the
-- bloody footprints (ISnow_Footprints.lua) and the bloody tire tracks (ISnow_TireTracks.lua).
--
-- API (keep it this small):
--   ISnow.Blood.enabled()   whether the game shows blood at all: sandbox BloodLevel is not 1 ("none":
--                           no splats at all, IsoZombie.addBloodFromVehicleImpact) and Options >
--                           Display "Blood decals" (Core.getOptionBloodDecals, 0..10) is not "none"
--                           (0). Everything made of blood is off with either, as vanilla's own floor
--                           and wall splats are.
--                           Read again after CACHE_MS (it is asked every step).
--   ISnow.Blood.corpses(cell, sx, sy, z)  the corpses on the 3x3 squares round sx, sy as
--                           { x, y, ux, uy } (centre, unit vector along the body) or nil; cached per
--                           square for CACHE_MS (a horde walks the same squares).
--   ISnow.Blood.over(x, y, bodies, reach)  point x, y is within reach of one of those bodies.
--   ISnow.Blood.onCorpse(cell, x, y, z, reach)  both, with enabled(): what a step asks.
--
-- Only the body itself counts, never the blood on the floor (2026-10-04, by request: red prints and
-- tire tracks only after stepping or driving on the corpse). Floor splats were tried and dropped:
-- IsoGridSquare.haveBloodFloor (bytecode 42.21) is true for any splat within one tile of the square,
-- faded or not drawn (a chunk keeps up to 1000 for good, the world spills them round the corpses it
-- lays), and even counted only near where blood was shed lately (a hit, a death) it made red prints
-- 2 m off the body. A bleeding player's own drips are not blood to step in either: their own drops
-- on the snow (BloodOnSnow) show that.
--
-- A lying body is vanilla's line of BODY_HALF either way of its centre along its angle
-- (BaseVehicle.testCollisionWithProneCharacter; IsoDeadBody.getAngle in radians, as vanilla uses
-- it). Corpses are the IsoDeadBody of a square's static moving objects (zombies, players, animals),
-- not skeletons (no blood left). They come to every MP client, so every client works this out for
-- itself, like the prints.

require "ImmersiveSnow/ISnow_Config"

local Blood = {}
ISnow.Blood = Blood

local CACHE_MS = 1000
local BODY_HALF = 0.65      -- half a lying body's length along its angle (testCollisionWithProneCharacter)

local cache, cacheAt = {}, -1e9    -- [square key] = list of corpses / false
local shown, shownAt = true, -1e9   -- enabled(), read again after CACHE_MS (asked every step)

function Blood.enabled()
    local t = getTimestampMs()
    if t - shownAt > CACHE_MS or t < shownAt then
        local level = SandboxVars and tonumber(SandboxVars.BloodLevel)
        local core = getCore and getCore() or (Core and Core.getInstance and Core.getInstance())
        shown = not (level and level <= 1) and (core == nil or core:getOptionBloodDecals() > 0)
        shownAt = t
    end
    return shown
end

local function key(sx, sy, z)
    return (z + 64) * 1099511627776 + sx * 1048576 + sy   -- levels from -64, x, y < 2^20
end

local function fresher()
    local t = getTimestampMs()
    if t - cacheAt > CACHE_MS or t < cacheAt then
        cache, cacheAt = {}, t
    end
end

function Blood.corpses(cell, sx, sy, z)
    fresher()
    local k = key(sx, sy, z)
    local out = cache[k]
    if out == nil then
        out = false
        for i = -1, 1 do
            for j = -1, 1 do
                local sq = cell:getGridSquare(sx + i, sy + j, z)
                if sq then
                    local list = sq:getStaticMovingObjects()
                    for n = 0, list:size() - 1 do
                        local o = list:get(n)
                        if instanceof(o, "IsoDeadBody") and not o:isSkeleton() then
                            local a = o:getAngle()
                            out = out or {}
                            out[#out + 1] = { x = o:getX(), y = o:getY(), ux = math.cos(a), uy = math.sin(a) }
                        end
                    end
                end
            end
        end
        cache[k] = out
    end
    return out or nil
end

function Blood.over(x, y, bodies, reach)
    if not bodies then return false end
    for i = 1, #bodies do
        local b = bodies[i]
        local dx, dy = x - b.x, y - b.y
        local t = math.max(-BODY_HALF, math.min(BODY_HALF, dx * b.ux + dy * b.uy))
        local ex, ey = dx - b.ux * t, dy - b.uy * t
        if ex * ex + ey * ey <= reach * reach then return true end
    end
    return false
end

function Blood.onCorpse(cell, x, y, z, reach)
    if not cell or not Blood.enabled() then return false end
    z = math.floor(z)
    return Blood.over(x, y, Blood.corpses(cell, math.floor(x), math.floor(y), z), reach)
end

-- Forgets the cache (tests).
function Blood.reset() cache, cacheAt, shownAt = {}, -1e9, -1e9 end
