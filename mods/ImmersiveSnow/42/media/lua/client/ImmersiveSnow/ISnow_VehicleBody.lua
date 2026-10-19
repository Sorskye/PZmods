-- Immersive Snow: whether a vehicle's body hides a point from the camera, for the particles drawn
-- with the depth test off (the snow thrown up by the wheels, ISnow_BlowOff.lua): nothing in front
-- hides them, so each asks, once a frame, how much of it the body of its vehicle leaves to be seen.
--
-- The body is a box of the script's extents round the centre of mass (BODY_PART of it across and
-- along, the full height), level (no pitch or roll); the camera looks along +x +y and down,
-- isoToScreenY says how steeply (UP_PER_TILE without it). The box is grown by a margin (tiles; the
-- caller passes part of its sprite's radius: a soft sprite, its rim faint), so one whose core already
-- overlaps the body on screen goes too. The part of the line toward the camera inside the box hides
-- the point, all of it from HIDE_DEPTH tiles on, so a particle past an edge or a corner fades rather
-- than blinks. (Made for the exhaust vapour cut from 0.5.2; kept for the wheel spray, which showed
-- through the car too, 2026-10-04.)

require "ImmersiveSnow/ISnow_Config"

local VehicleBody = {}
ISnow.VehicleBody = VehicleBody

local PHYS_PER_LEVEL = 2.44949
local BODY_PART = 0.92        -- of the extents across and along: the body, rounded at the corners
local HIDE_DEPTH = 0.35       -- tiles of the line through the body that hide a point entirely
local UP_PER_TILE = 1 / 3     -- levels the line to the camera rises per tile along +x +y (IsoUtils, scale 1: 32 / 96)
local LEVELS_PER_TILE_UP = 2 / 3   -- a tile's width on screen in floor levels of height (64 / 96)

local bodies = {}   -- [vehicle] = its body box this frame
-- Kahlua has no weak tables (ISnow.prune): every SWEEP_FRAMES frames the vehicles not asked
-- about for KEEP_FRAMES go.
local SWEEP_FRAMES, KEEP_FRAMES = 1800, 60
local sweptFrame = 0
local upFrame, up = -1, UP_PER_TILE
local bvec = nil

local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end

-- Levels the line to the camera rises per tile along +x +y, from the screen maths of player pi.
local function upPerTile(pi, frame)
    if upFrame == frame then return up end
    upFrame, up = frame, UP_PER_TILE
    if isoToScreenY then
        local y0 = isoToScreenY(pi, 0, 0, 0)
        local dz = y0 - isoToScreenY(pi, 0, 0, 1)
        if dz > 0 then up = (isoToScreenY(pi, 1, 1, 0) - y0) / dz end
    end
    return up
end

-- The body box of v this frame: its origin, the local x and z axes in world x / y, the box in local
-- units (physics units; height above the origin's level).
local function bodyOf(v, frame)
    if frame - sweptFrame >= SWEEP_FRAMES or frame < sweptFrame then
        sweptFrame = frame
        ISnow.prune(bodies, function(_, b) return b.frame and frame - b.frame < KEEP_FRAMES end)
    end
    local b = bodies[v]
    if b and b.frame == frame then return b end
    b = b or {}
    bodies[v] = b
    b.frame = frame
    local vs = v:getScript()
    if not vs then
        b.none = true
        return b
    end
    if not bvec then bvec = Vector3f.new() end
    v:getWorldPos(0, 0, 0, bvec)
    local ox, oy, oz = bvec:x(), bvec:y(), bvec:z()   -- oz: the level the particles' heights start from
    v:getWorldPos(1, 0, 0, bvec)
    local xx, xy = bvec:x() - ox, bvec:y() - oy
    v:getWorldPos(0, 0, 1, bvec)
    local zx, zy = bvec:x() - ox, bvec:y() - oy
    local ext, com = vs:getExtents(), vs:getCenterOfMassOffset()
    local hx, hy, hz = ext:x() / 2 * BODY_PART, ext:y() / 2, ext:z() / 2 * BODY_PART
    local lx, lz = xx * xx + xy * xy, zx * zx + zy * zy
    b.none = lx < 1e-6 or lz < 1e-6
    b.ox, b.oy, b.oz = ox, oy, oz
    b.xx, b.xy, b.zx, b.zy = xx / lx, xy / lx, zx / lz, zy / lz   -- world offset -> local, by dot
    b.x0, b.x1 = com:x() - hx, com:x() + hx
    b.y0, b.y1 = com:y() - hy, com:y() + hy
    b.z0, b.z1 = com:z() - hz, com:z() + hz
    return b
end

-- t range [t0, t1] of o + d t inside [lo, hi], narrowed; nil once empty.
local function slab(t0, t1, o, d, lo, hi)
    if d > -1e-6 and d < 1e-6 then
        if o < lo or o > hi then return nil end
        return t0, t1
    end
    local a, b = (lo - o) / d, (hi - o) / d
    if a > b then a, b = b, a end
    if a > t0 then t0 = a end
    if b < t1 then t1 = b end
    if t0 > t1 then return nil end
    return t0, t1
end

-- 0..1: how much of the point x, y, z (tiles, floor levels) the body of vehicle v leaves to be seen
-- by player pi, the box grown by margin tiles; frame counts the render frames (a cache per frame).
-- Second result: whether the line went through the box at all.
function VehicleBody.seen(v, x, y, z, margin, pi, frame)
    if not v then return 1, false end
    local ok, b = pcall(bodyOf, v, frame)
    if not ok or b.none then return 1, false end
    local k = upPerTile(pi, frame)
    local dx, dy = x - b.ox, y - b.oy
    -- the line p + (t, t, k t) in the vehicle's local units
    local lx, ldx = dx * b.xx + dy * b.xy, b.xx + b.xy
    local lz, ldz = dx * b.zx + dy * b.zy, b.zx + b.zy
    local ly, ldy = (z - b.oz) * PHYS_PER_LEVEL, k * PHYS_PER_LEVEL
    local m, my = margin, margin * LEVELS_PER_TILE_UP * PHYS_PER_LEVEL
    local t0, t1 = 0, 1e9
    t0, t1 = slab(t0, t1, lx, ldx, b.x0 - m, b.x1 + m)
    if not t0 then return 1, false end
    t0, t1 = slab(t0, t1, lz, ldz, b.z0 - m, b.z1 + m)
    if not t0 then return 1, false end
    t0, t1 = slab(t0, t1, ly, ldy, b.y0 - my, b.y1 + my)
    if not t0 then return 1, false end
    return 1 - clamp01((t1 - t0) / HIDE_DEPTH), true
end
