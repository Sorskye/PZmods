-- Immersive Snow: the snow a fast vehicle blows off its roof, as clumps and powder puffs that fly
-- back, fall and fade, and the sound of each stage going. ISnow_VehicleSnow.lua decides when and how
-- much; this file only moves and draws them and plays the sound. The same particles, smaller, are
-- the snow kicked up off the ground by running feet and falling characters (BlowOff.kick, called
-- from ISnow_Footprints.lua) and by the wheels of a vehicle in snow (ISnow_TireTracks.lua). The
-- powder is also the snow dust drifting along the ground in a strong wind (BlowOff.drift,
-- ISnow_Drift.lua) and the steam off snow thawing around a fire (BlowOff.steam, ISnow_Thaw.lua).
--
-- No particle system can be driven from Lua: the only exposed flying object, IsoZombieGiblets,
-- stamps blood splats while it is in the air, draws at half brightness and hides two of three at
-- random (bytecode 42.20). So the particles are a Lua list drawn every frame.
--
-- Where they are drawn: RenderOpaqueObjectsInWorld (the ground decals, ISnow_Decals.lua) runs before
-- renderMovingObjects (FBORenderCell.performRenderTiles), and Render3DItem does not write depth, so
-- the vehicle covered every particle over its outline: the snow leaving the roof, the part that
-- shows the effect. The snow a wheel throws up is behind the body as often as not, so a kick with an
-- owner vehicle (ISnow_TireTracks.lua) fades by how much of it that body leaves to be seen
-- (ISnow_VehicleBody.lua; 2026-10-04: the spray showed through the car). The UI pass (OnPreUIDraw)
-- is not drawn every frame (UIManager.render: uiRenderThisFrame, UI FBO), so particles there would
-- stutter. OnPostRender fires in
-- IngameState.renderFrameInternal right after IsoWorld.render and before Core.EndFrame, every frame,
-- into the player's world buffer (screen size x zoom; checked in game: the player at the screen
-- centre is at x = 1920 at zoom 2), with the depth test off. So particles go over everything,
-- the vehicle included; a tree or roof between them and the camera does not hide them either, a
-- small price for a second or two.
--
-- Units: x, y in tiles (= physics units across), z in floor levels. BaseVehicle.getWorldPos gives
-- the body origin's height as physics height / 2.44949 (bytecode), and adds a local y offset
-- unscaled, so heights above the origin are added here instead. getLinearVelocity is in physics
-- units per second (getCurrentSpeedKmHour is its length * 3.6).
--
-- Textures (tools/gen_blowoff.py) are made for 2x tile scale and drawn at their pixel size x tile
-- scale / 2 x the particle's own size, tinted by the light colour of the square (IsoGridSquare
-- getLightInfo: night is blue-violet, lamps warm; the textures are white and nothing else lights
-- them) and faded with the draw colour's alpha. Textures must exist when the game starts (getTexture finds
-- no file added later).

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_Decals"
require "ImmersiveSnow/ISnow_VehicleBody"
require "ImmersiveSnow/ISnow_CompatViewpoint"

local BlowOff = {}
ISnow.BlowOff = BlowOff

local CHUNK_SHAPES = 6       -- as gen_blowoff.py
local CHUNK_SIZE = 32        -- px
local DUST_SHAPES = 4
local DUST_SIZES = 3
local DUST_SIZE = 64
local MAX_PARTICLES = 500
local SOUND = "ISnowBlowOff"   -- ISnow_Sounds.txt

local PHYS_PER_LEVEL = 2.44949
local GRAVITY = 9.8 / PHYS_PER_LEVEL   -- levels / s^2
-- clumps: part of the vehicle's speed they keep, air drag (1/s), upward kick (physics units / s),
-- sideways spread, how fast the shape cycles (tumbling), fade on the ground
local CHUNK_KEEP = { 0.3, 0.5 }
local CHUNK_DRAG = 1.4
local CHUNK_UP = { 0.6, 1.8 }
local CHUNK_SIDE = 0.8
local CHUNK_TUMBLE = 9       -- shapes per second
local CHUNK_LIFE = 2.5
local CHUNK_LANDED = 0.6     -- s a landed clump takes to fade
-- clump sizes (of the texture): mostly crumbs, now and then a lump
local CHUNK_SMALL = { 0.22, 0.38 }
local CHUNK_LARGE = { 0.4, 0.6 }
local CHUNK_LARGE_ONE_IN = 4
-- powder: slower, lighter, grows through the DUST_SIZES and fades
local DUST_KEEP = { 0.15, 0.35 }
local DUST_DRAG = 2.2
local DUST_UP = { 0.3, 1.2 }
local DUST_SIDE = 1.0
local DUST_GRAVITY = 0.15    -- of GRAVITY
local DUST_LIFE = { 1.0, 1.8 }
local DUST_FULL = 0.3        -- of the life at full alpha
local DUST_SCALE = { 0.9, 1.4 }

-- Seen against the ground snow: lit by the same square light, white particles vanish on it. A
-- particle in the air catches more light than the snow under it (LIGHT_BOOST, capped at 1), and a
-- soft blue-grey shadow on the ground under it (SHADOW_*: of its size, of its alpha, fading with its
-- height) shows where it is; drifting snow and steam (ambient) get none.
local LIGHT_BOOST = 1.25
local SHADOW_RGB = { 0.42, 0.46, 0.58 }
local SHADOW_SIZE = 0.7
local SHADOW_ALPHA = 0.35
local SHADOW_FADE_Z = 1.2     -- levels above the floor where the shadow is gone
-- Hidden by its vehicle (p.owner, see the top): the body box grows by this part of the particle's
-- radius on screen (a puff's texture is DUST_SIZE wide, a clump's CHUNK_SIZE; a tile 128 px at 2x).
local OWNER_CORE = 0.4

local chunkTex = {}   -- [shape] = Texture
local dustTex = {}    -- [shape][size] = Texture
local ready = false
local particles = {}
local vec = nil
local lastMs = nil
local stats = { emitted = 0, dropped = 0, drawn = 0, sounds = 0, errors = 0, hidden = 0 }
local frameNo = 0     -- render frames (ISnow_VehicleBody.lua caches a body per frame)
local lastError = nil

local function rand(r)
    return ZombRandFloat(r[1], r[2])
end

local function texture(name)
    local t = getTexture(ISnow.TEXTURE_DIR .. name)
    if not t then error("missing texture " .. name) end
    return t
end

local function load()
    for s = 0, CHUNK_SHAPES - 1 do
        chunkTex[s] = texture("blow_chunk_" .. s .. ".png")
    end
    for s = 0, DUST_SHAPES - 1 do
        dustTex[s] = {}
        for z = 0, DUST_SIZES - 1 do
            dustTex[s][z] = texture("blow_dust_" .. s .. "_" .. z .. ".png")
        end
    end
    vec = Vector3f.new()
    ready = true
end

local function add(p)
    if #particles >= MAX_PARTICLES then
        stats.dropped = stats.dropped + 1
        return
    end
    particles[#particles + 1] = p
    stats.emitted = stats.emitted + 1
end

-- Snow kicked up off the ground (ISnow_Footprints.lua: a running foot, a character falling;
-- ISnow_TireTracks.lua: a wheel): one low powder puff at x, y, z thrown at vx, vy (tiles / s), or a
-- crumb with crumb, scale times its usual size (default 1); owner: the vehicle whose body may hide
-- it (a wheel's spray). Smaller, fainter and shorter-lived than the snow off a vehicle.
local KICK_DUST_SCALE = { 0.45, 0.75 }
local KICK_DUST_LIFE = { 0.6, 1.1 }
local KICK_DUST_UP = { 0.25, 0.7 }
local KICK_DUST_ALPHA = 1.0
local KICK_CRUMB_SCALE = { 0.18, 0.3 }
local KICK_CRUMB_UP = { 0.8, 1.6 }
local KICK_CRUMB_LIFE = 1.2
local KICK_LANDED_PUFF = 0.35  -- size of the puff a landing crumb raises now and then

function BlowOff.kick(x, y, z, vx, vy, crumb, scale, owner)
    if not ready then return end
    local p = { x = x, y = y, z = z + 0.02, fz = math.floor(z), vx = vx, vy = vy, age = 0, chunk = crumb == true,
        owner = owner }
    if crumb then
        p.vz = rand(KICK_CRUMB_UP) / PHYS_PER_LEVEL
        p.life = KICK_CRUMB_LIFE
        p.shape = ZombRand(CHUNK_SHAPES)
        p.scale = rand(KICK_CRUMB_SCALE) * (scale or 1)
        p.landPuff = KICK_LANDED_PUFF
    else
        p.vz = rand(KICK_DUST_UP) / PHYS_PER_LEVEL
        p.life = rand(KICK_DUST_LIFE)
        p.shape = ZombRand(DUST_SHAPES)
        p.scale = rand(KICK_DUST_SCALE) * (scale or 1)
        p.alpha = KICK_DUST_ALPHA
    end
    add(p)
end

-- Snow dust drifting along the ground in the wind (ISnow_Drift.lua) and steam off snow thawing
-- around a fire (ISnow_Thaw.lua): powder puffs with their own drag (1/s; drifting snow keeps the
-- wind's speed), gravity (of GRAVITY; steam rises, drifting snow barely sinks), alpha, and a fade-in
-- (part of the life) so that they do not pop up out of nothing. Particles of these two may use
-- only part of MAX_PARTICLES (BlowOff.room), the rest stays for the snow off vehicles and feet.
local DRIFT_SCALE = { 0.55, 1.1 }
local DRIFT_LIFE = { 1.2, 2.4 }
local DRIFT_UP = { 0.0, 0.08 }   -- levels / s
local DRIFT_ALPHA = { 0.18, 0.36 }   -- of the denser dust textures (gen_blowoff.py DUST_ALPHA)
local DRIFT_GRAVITY = 0.02
local STEAM_SCALE = { 0.45, 0.85 }
local STEAM_LIFE = { 1.6, 2.8 }
local STEAM_UP = { 0.08, 0.2 }   -- levels / s
local STEAM_ALPHA = 0.24
local STEAM_DRAG = 1.0
local FADE_IN = 0.25
local AMBIENT_SHARE = 0.5        -- of MAX_PARTICLES for drifting snow and steam together
local ambient = 0                -- such particles live now (counted in update)

-- The live particles (tests, the console); read only.
function BlowOff.list() return particles end

-- Room left for drifting snow and steam (particles, 0 or more).
function BlowOff.room()
    if not ready then return 0 end
    return math.max(0, math.min(MAX_PARTICLES - #particles, math.floor(MAX_PARTICLES * AMBIENT_SHARE) - ambient))
end

-- One wisp of drifting snow at x, y, z going at vx, vy (tiles / s, the wind) along the ground.
function BlowOff.drift(x, y, z, vx, vy)
    if BlowOff.room() <= 0 then return end
    ambient = ambient + 1
    add({ x = x, y = y, z = z + 0.01, fz = math.floor(z), vx = vx, vy = vy, vz = rand(DRIFT_UP) / PHYS_PER_LEVEL,
        age = 0, chunk = false, life = rand(DRIFT_LIFE), shape = ZombRand(DUST_SHAPES), scale = rand(DRIFT_SCALE),
        alpha = rand(DRIFT_ALPHA), drag = 0, grav = DRIFT_GRAVITY, fadeIn = FADE_IN, ambient = true })
end

-- One puff of steam rising at x, y, z, carried at vx, vy (tiles / s, a little wind).
function BlowOff.steam(x, y, z, vx, vy)
    if BlowOff.room() <= 0 then return end
    ambient = ambient + 1
    add({ x = x, y = y, z = z + 0.03, fz = math.floor(z), vx = vx or 0, vy = vy or 0, vz = rand(STEAM_UP),
        age = 0, chunk = false, life = rand(STEAM_LIFE), shape = ZombRand(DUST_SHAPES), scale = rand(STEAM_SCALE),
        alpha = STEAM_ALPHA, drag = STEAM_DRAG, grav = 0, fadeIn = FADE_IN, ambient = true })
end

-- Throws chunks clumps and puffs powder puffs off the top of vehicle v. kmh, if given, stands in for
-- the vehicle's speed along its heading (console tests on a parked vehicle).
function BlowOff.emit(v, chunks, puffs, kmh)
    if not ready or (chunks <= 0 and puffs <= 0) then return end
    local script = v:getScript()
    if not script then return end
    local ext, com = script:getExtents(), script:getCenterOfMassOffset()
    local w, l = ext:x(), ext:z()
    local top = com:y() + ext:y() / 2   -- physics units above the body origin
    local vx, vy
    if kmh then
        v:getForwardVector(vec)
        vx, vy = vec:x() * kmh / 3.6, vec:z() * kmh / 3.6
    else
        v:getLinearVelocity(vec)
        vx, vy = vec:x(), vec:z()
        if vx * vx + vy * vy < 1 then
            -- a vehicle another client drives may have no velocity here
            local speed = v:getCurrentSpeedKmHour() / 3.6
            v:getForwardVector(vec)
            vx, vy = vec:x() * speed, vec:z() * speed
        end
    end
    local sp = math.sqrt(vx * vx + vy * vy)
    local sx, sy = 0, 0   -- unit vector across the motion
    if sp > 0.01 then sx, sy = -vy / sp, vx / sp end
    local fz = math.floor(v:getZ())
    for i = 1, chunks + puffs do
        local chunk = i <= chunks
        v:getWorldPos(ZombRandFloat(-0.4, 0.4) * w, 0, com:z() + ZombRandFloat(-0.42, 0.42) * l, vec)
        local keep = rand(chunk and CHUNK_KEEP or DUST_KEEP)
        local side = ZombRandFloat(-1, 1) * (chunk and CHUNK_SIDE or DUST_SIDE)
        local p = {
            x = vec:x(), y = vec:y(), z = vec:z() + top * ZombRandFloat(0.75, 1.0) / PHYS_PER_LEVEL, fz = fz,
            vx = vx * keep + sx * side, vy = vy * keep + sy * side,
            vz = rand(chunk and CHUNK_UP or DUST_UP) / PHYS_PER_LEVEL,
            age = 0, chunk = chunk,
        }
        if chunk then
            p.life = CHUNK_LIFE
            p.shape = ZombRand(CHUNK_SHAPES)
            p.scale = rand(ZombRand(CHUNK_LARGE_ONE_IN) == 0 and CHUNK_LARGE or CHUNK_SMALL)
        else
            p.life = rand(DUST_LIFE)
            p.shape = ZombRand(DUST_SHAPES)
            p.scale = rand(DUST_SCALE)
        end
        add(p)
    end
end

-- The sound of a stage of snow going off vehicle v (ISnow_Sounds.txt), from the vehicle's
-- emitter so it goes along with it; a free emitter at the vehicle if it has none. On this client
-- only: every client runs the blow-off itself.
function BlowOff.sound(v)
    local ok, err = pcall(function()
        local emitter = v:getEmitter()
        if not emitter then emitter = getWorld():getFreeEmitter(v:getX(), v:getY(), v:getZ()) end
        if emitter then
            emitter:playSound(SOUND)
            stats.sounds = stats.sounds + 1
        end
    end)
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
    end
end

local function puffAt(x, y, z, fz, scale)
    add({ x = x, y = y, z = z, fz = fz, vx = ZombRandFloat(-0.5, 0.5), vy = ZombRandFloat(-0.5, 0.5),
        vz = ZombRandFloat(0.1, 0.4) / PHYS_PER_LEVEL, age = 0, chunk = false, life = rand(DUST_LIFE) * 0.6,
        shape = ZombRand(DUST_SHAPES), scale = scale or 0.6, alpha = scale and KICK_DUST_ALPHA or nil })
end

local function update(dt)
    local keep = {}
    local live = 0   -- drifting snow and steam
    local chunkDrag, dustDrag = math.exp(-CHUNK_DRAG * dt), math.exp(-DUST_DRAG * dt)
    for i = 1, #particles do
        local p = particles[i]
        p.age = p.age + dt
        if p.landed then
            if p.age - p.landed < CHUNK_LANDED then keep[#keep + 1] = p end
        elseif p.age < p.life then
            local drag = p.chunk and chunkDrag or dustDrag
            if p.drag then drag = p.drag > 0 and math.exp(-p.drag * dt) or 1 end
            p.vx, p.vy = p.vx * drag, p.vy * drag
            p.vz = p.vz - GRAVITY * (p.grav or (p.chunk and 1 or DUST_GRAVITY)) * dt
            if p.ambient then live = live + 1 end
            p.x, p.y, p.z = p.x + p.vx * dt, p.y + p.vy * dt, p.z + p.vz * dt
            if p.z <= p.fz then
                p.z = p.fz
                if p.chunk then
                    p.landed = p.age
                    if ZombRand(3) == 0 then puffAt(p.x, p.y, p.z, p.fz, p.landPuff) end
                else
                    p.vz = 0
                end
            end
            keep[#keep + 1] = p
        end
    end
    particles = keep
    ambient = live
end

local function onTick()
    local now = getTimestampMs()
    local dt = lastMs and (now - lastMs) / 1000 or 0
    lastMs = now
    if #particles == 0 then ambient = 0 end
    if #particles == 0 or isGamePaused() then return end
    local ok, err = pcall(update, math.min(dt, 0.1))
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
        particles = {}
    end
end

-- Project Viewpoint's 3D view (ISnow_CompatViewpoint.lua, VP.camera): a particle is placed and sized
-- by Viewpoint's camera (ISnowVP.project) instead of the isometric screen, as the breath
-- (ISnow_Breath.lua: VP_ISO_PX_PER_TILE). The isometric checks are left out there: the owner
-- vehicle's outline (ISnow_VehicleBody.lua works on the isometric screen) and the shadow on the
-- ground (an isometric ellipse); a particle of the vehicle the viewer sits in is not drawn (the
-- camera is inside the car, the spray under it would show through the floor).
local VP_ISO_PX_PER_TILE = 45.25
local VP_NEAR = 0.3          -- tiles from the camera inside which a particle is not drawn

-- Draws the powder first, then the clumps over it.
local function render()
    stats.drawn = 0
    if not ready or #particles == 0 then return end
    -- Project Viewpoint draws the world in 3D now: the isometric screen position is wrong there
    -- (ISnow_CompatViewpoint.lua); without its camera the particles fly on unseen
    local cam = ISnow.Viewpoint and ISnow.Viewpoint.camera()
    if not cam and ISnow.Viewpoint and ISnow.Viewpoint.active() then return end
    frameNo = frameNo + 1
    local body = ISnow.VehicleBody
    -- OnPostRender does not say which player's view it is: split screen gets no particles
    if getNumActivePlayers() > 1 then return end
    local pi = 0
    local player = getSpecificPlayer(pi)
    if not player then return end
    local cz = math.floor(player:getZ())
    local zoom = getCore():getZoom(pi)
    local left, top = getPlayerScreenLeft(pi), getPlayerScreenTop(pi)
    local scale = Core.getTileScale() / 2
    local r = getRenderer()
    local cell = getCell()
    local lights = {}
    local drawn = 0
    -- darker snow (ISnow.darkSnow): the particles take its colour over the light
    local tint = ISnow.darkSnow() and ISnow.DARK_SNOW_RGB or nil
    local ownCar = cam and player:getVehicle()
    for pass = 1, 2 do
        local chunks = pass == 2
        for i = 1, #particles do
            local p = particles[i]
            if p.chunk == chunks and (p.fz == cz or cam) and not (ownCar and p.owner == ownCar) then
                local tex, size, fade
                if chunks then
                    fade = p.landed and 1 - (p.age - p.landed) / CHUNK_LANDED or 1
                    tex = chunkTex[(p.shape + (p.landed and 0 or math.floor(p.age * CHUNK_TUMBLE))) % CHUNK_SHAPES]
                    size = CHUNK_SIZE * scale * p.scale
                else
                    local t = p.age / p.life
                    fade = t < DUST_FULL and 1 or (1 - t) / (1 - DUST_FULL)
                    if p.fadeIn and t < p.fadeIn then fade = fade * t / p.fadeIn end
                    tex = dustTex[p.shape][math.min(DUST_SIZES - 1, math.floor(t * DUST_SIZES * 1.3))]
                    size = DUST_SIZE * scale * p.scale
                end
                local sx, sy = math.floor(p.x), math.floor(p.y)
                local k = sx * 1048576 + sy
                local light = lights[k]
                if not light then
                    local lsq = cell:getGridSquare(sx, sy, p.fz)
                    local c = lsq and lsq:getLightInfo(pi)
                    light = c and { c:getR(), c:getG(), c:getB() } or { 1, 1, 1 }
                    if tint then light = { light[1] * tint[1], light[2] * tint[2], light[3] * tint[3] } end
                    light[4] = math.min(1, light[1] * LIGHT_BOOST)
                    light[5] = math.min(1, light[2] * LIGHT_BOOST)
                    light[6] = math.min(1, light[3] * LIGHT_BOOST)
                    lights[k] = light
                end
                fade = fade * (p.alpha or 1)
                local shadowFade = fade
                if cam then
                    shadowFade = 0
                    if fade > 0.01 and cam.project(p.x, p.y, p.z) and cam.pdepth() > VP_NEAR then
                        if drawn == 0 then ISnow.Decals.resetBlend(player) end
                        local s = size / (VP_ISO_PX_PER_TILE * Core.getTileScale()) * cam.pscale() * zoom
                        local x, y = cam.px() * zoom, cam.py() * zoom
                        r:render(tex, x - s / 2, y - s / 2, s, s, light[4], light[5], light[6], fade, nil)
                        drawn = drawn + 1
                    end
                    fade = 0
                elseif fade > 0 and p.owner and body then
                    -- radius in tiles: the drawn size over a tile's 128 px at 2x (size is x tile scale / 2)
                    local m = OWNER_CORE * size / (2 * 64 * scale * 2)
                    local f, behind = body.seen(p.owner, p.x, p.y, p.z, m, pi, frameNo)
                    if behind then stats.hidden = stats.hidden + 1 end
                    fade = fade * f
                    shadowFade = shadowFade * body.seen(p.owner, p.x, p.y, p.fz, m * SHADOW_SIZE, pi, frameNo)
                end
                if fade > 0 or shadowFade > 0 then
                    if drawn == 0 then ISnow.Decals.resetBlend(player) end
                    local h = p.z - p.fz
                    if not p.ambient and not p.landed and h > 0.01 then
                        local sa = shadowFade * SHADOW_ALPHA * (1 - math.min(1, h / SHADOW_FADE_Z))
                        if sa > 0.01 then
                            local ss = size * SHADOW_SIZE
                            local x = (isoToScreenX(pi, p.x, p.y, p.fz) - left) * zoom
                            local y = (isoToScreenY(pi, p.x, p.y, p.fz) - top) * zoom
                            -- a clump's shape counts CHUNK_SHAPES, more than the puffs have
                            r:render(dustTex[p.shape % DUST_SHAPES][0], x - ss / 2, y - ss / 4, ss, ss / 2,
                                SHADOW_RGB[1] * light[1], SHADOW_RGB[2] * light[2], SHADOW_RGB[3] * light[3], sa, nil)
                        end
                    end
                    if fade > 0.01 then
                        local x = (isoToScreenX(pi, p.x, p.y, p.z) - left) * zoom
                        local y = (isoToScreenY(pi, p.x, p.y, p.z) - top) * zoom
                        r:render(tex, x - size / 2, y - size / 2, size, size, light[4], light[5], light[6], fade, nil)
                        drawn = drawn + 1
                    end
                end
            end
        end
    end
    stats.drawn = drawn
end

local function onRenderSafe()
    local ok, err = pcall(render)
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
        particles = {}
    end
end

function BlowOff.stats()
    print(string.format("[ImmersiveSnow] blow-off particles: ready=%s live=%d (drifting snow and steam %d) emitted=%d dropped=%d drawn=%d behindVehicle=%d sounds=%d errors=%d",
        tostring(ready), #particles, ambient, stats.emitted, stats.dropped, stats.drawn, stats.hidden, stats.sounds, stats.errors))
    if lastError then print("[ImmersiveSnow] last error: " .. lastError) end
end

local function onGameStart()
    local ok, err = pcall(load)
    if not ok then
        lastError = tostring(err)
        print("[ImmersiveSnow] blow-off disabled: " .. lastError)
    end
end

BlowOff.init = onGameStart   -- for a reload from the console
Events.OnGameStart.Add(onGameStart)
ISnow.listen("OnTick", "BlowOff", onTick)
ISnow.listen("OnPostRender", "BlowOff", onRenderSafe)
