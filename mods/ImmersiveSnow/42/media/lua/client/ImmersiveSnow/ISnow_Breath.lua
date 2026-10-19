-- Immersive Snow: breath vapour in the cold. Each exhale of a living player puffs a few soft wisps
-- out of the mouth that drift forward and with the wind, grow and fade. Zombies do not breathe.
--
-- Drawn like the blow-off particles (ISnow_BlowOff.lua: why OnPostRender, the screen maths): every
-- frame from OnPostRender into the player's world buffer, depth test off, so a puff shows over
-- whatever is in front of it. It stays next to a visible character, and the character's own alpha
-- (it fades out when the viewer cannot see it) fades its breath too, so breath does not show
-- through the walls around a player behind them. That is how the Workshop breath mods draw it as
-- well (Cold Breath: UIManager.DrawTexture in OnPostRender). Render3DItem (depth tested, the ground
-- decals) was tried from OnPostRender on 2026-09-30: it draws there, but whether the depth buffer is
-- still the scene's at that point was not established, and it draws at alpha 1 (one baked texture
-- per fade level, no light tint).
--
-- Rhythm: an exhale every PERIOD_REST s at rest down to PERIOD_HARD when out of breath. How hard a
-- character breathes (effort 0..1) climbs with running and sprinting and eases off slowly after
-- it, and low endurance (stats ENDURANCE) keeps it up. Strength: none above BreathMaxTemp (air
-- temperature at the character: indoors, heaters, the vehicle heater), faint but on every exhale
-- at it, full at BreathFullTemp. No vapour through a gas mask or respirator, half through cloth
-- over the face.
--
-- Textures (tools/gen_breath.py) are white and drawn at their pixel size x tile scale / 2 x the
-- puff's size, tinted by the light of the square (night blue, lamps warm). They must exist when the
-- game starts (getTexture finds no file added later).
--
-- Split screen gets no breath (OnPostRender does not say which player's view it draws, as for the
-- blow-off). In MP every client breathes for the players it sees, with no network traffic; a remote
-- player's movement comes from how fast it moves, its endurance is not known here.

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_Decals"
require "ImmersiveSnow/ISnow_CompatViewpoint"

local Breath = {}
ISnow.Breath = Breath

local SHAPES = 4             -- as gen_breath.py
local TEX_SIZE = 64          -- px
local MAX_PARTICLES = 96
local RADIUS = 25            -- tiles from the viewer
local TEMP_TICKS = 30        -- ticks between asking for the air temperature at a character

-- mouth height above the feet, floor levels (0.46 showed at the neck in game; Cold Breath uses 0.53)
local MOUTH_STAND = 0.53
local MOUTH_SNEAK = 0.40
local MOUTH_SIT = 0.31       -- on the ground
local MOUTH_CHAIR = 0.42
local MOUTH_LIE = 0.16       -- asleep (in bed)
local MOUTH_FWD = 0.16       -- tiles in front of the character's position

local PERIOD_REST = 3.8      -- s between exhales at rest
local PERIOD_HARD = 1.0      -- ... when out of breath
local PERIOD_SLEEP = 1.5     -- x asleep
local EXHALE_PART = 0.3      -- of the period the exhale lasts ...
local EXHALE_MIN, EXHALE_MAX = 0.3, 0.8   -- ... s
local PUFFS_REST, PUFFS_HARD = 3, 5       -- wisps per exhale
-- effort a movement drives toward, and the time constants (s) it climbs and eases off with
local EFFORT_WALK, EFFORT_RUN, EFFORT_SPRINT = 0.15, 0.55, 1.0
local EFFORT_UP, EFFORT_DOWN = 4, 15
local TIRED = 0.8            -- effort that full exhaustion (endurance 0) keeps
-- remote players: speed (tiles / s) above which they count as walking / running / sprinting
local SPEED_WALK, SPEED_RUN, SPEED_SPRINT = 0.3, 1.8, 3.0

-- a wisp: speed out of the mouth (tiles / s, more when out of breath), part of the character's own
-- speed it keeps, air drag (1 / s), rise (levels / s), life (s, longer in harder frost), size
local PUFF_SPEED = { 0.3, 0.7 }
local PUFF_CARRY = 0.35
local PUFF_DRAG = 1.6
local PUFF_RISE = { 0.02, 0.07 }
local PUFF_LIFE = { 0.9, 1.5 }
local PUFF_GROW = { 0.3, 1.1 }
local PUFF_FULL = 0.12       -- of the life fading in
local WIND_DRIFT = 0.08      -- tiles / s per km/h of wind, outdoors
local WIND_MAX = 1.5
local CLOTH_MASK = 0.5       -- alpha through cloth over the face
-- The square's light alone makes a white puff exactly the colour of the lit snow behind it (the
-- camera looks down on the ground), so it vanished on snow: part of it is white regardless.
local LIGHT_LIFT = 0.5

local SEALED = { "GasMask", "Respirator", "WeldingMask", "Hazmat" }
local RIVAL_MODS = { "ColdBreath", "FoggyBreath" }

local textures = {}
local ready = false
local rival = nil
local particles = {}
local live = {}              -- [kind] = particles of that kind in the list (breath: BREATH)
local BREATH = "breath"
local states = {}            -- [character] = breathing state
local lastMs = nil
local tick = 0
local forcedTemp = nil       -- console tests: Breath.test(temp)
local stats = { exhales = 0, emitted = 0, dropped = 0, drawn = 0, errors = 0, breathing = 0 }
local lastError = nil

local function rand(r) return ZombRandFloat(r[1], r[2]) end
local function lerp(a, b, t) return a + (b - a) * t end
local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end

local function load()
    for s = 0, SHAPES - 1 do
        local t = getTexture(ISnow.TEXTURE_DIR .. "breath_" .. s .. ".png")
        if not t then error("missing texture breath_" .. s .. ".png") end
        textures[s] = t
    end
    local mods = getActivatedMods()
    for _, id in ipairs(RIVAL_MODS) do
        if mods:contains(id) or mods:contains("\\" .. id) then rival = id end
    end
    ready = true
end

-- 0..1: how strong the vapour is at air temperature temp (0: none above BreathMaxTemp).
function Breath.strength(temp)
    local maxT, fullT = ISnow.opt("BreathMaxTemp"), ISnow.opt("BreathFullTemp")
    if temp > maxT then return 0 end
    if fullT >= maxT then return 1 end
    return clamp01((maxT - temp) / (maxT - fullT))
end

-- The period between exhales for effort 0..1.
function Breath.period(effort, asleep)
    local p = lerp(PERIOD_REST, PERIOD_HARD, clamp01(effort))
    return asleep and p * PERIOD_SLEEP or p
end

-- Alpha factor of one worn item, by its type name and body location: 0 sealed, CLOTH_MASK cloth,
-- 1 nothing over the face.
local function itemMask(name, loc)
    name = name or ""
    for _, s in ipairs(SEALED) do
        if string.find(name, s, 1, true) then return 0 end
    end
    if string.find(string.lower(tostring(loc or "")), "mask", 1, true) then return CLOTH_MASK end
    return 1
end

-- Alpha factor of what is worn over the face: 0 sealed, CLOTH_MASK cloth, 1 nothing. Other players
-- in MP have no worn items on this client, only item visuals (see wornList in ISnow_CharSnow.lua):
-- theirs come from the visuals' script items (a gas mask hid nothing on them before).
local function maskFactor(chr)
    local f = 1
    if not chr:isLocalPlayer() then
        local ivs = chr:getItemVisuals()
        if not ivs then return 1 end
        for i = 0, ivs:size() - 1 do
            local vis = ivs:get(i)
            local script = vis and vis:getScriptItem()
            if script then
                f = math.min(f, itemMask(script:getName(), script:getBodyLocation()))
                if f == 0 then return 0 end
            end
        end
        return f
    end
    local worn = chr:getWornItems()
    if not worn then return 1 end
    for i = 0, worn:size() - 1 do
        local item = worn:get(i):getItem()
        if item then
            f = math.min(f, itemMask(item:getType(), item.getBodyLocation and item:getBodyLocation()))
            if f == 0 then return 0 end
        end
    end
    return f
end

local function endurance(chr)
    local st = chr:getStats()
    if not st then return 1 end
    if CharacterStat and CharacterStat.ENDURANCE and st.get then return st:get(CharacterStat.ENDURANCE) or 1 end
    if st.getEndurance then return st:getEndurance() end
    return 1
end

local function mouthHeight(chr)
    if chr:isAsleep() then return MOUTH_LIE end
    if chr:isSitOnGround() then return MOUTH_SIT end
    if chr.isSittingOnFurniture and chr:isSittingOnFurniture() then return MOUTH_CHAIR end
    if chr:isSneaking() then return MOUTH_SNEAK end
    return MOUTH_STAND
end

-- The effort a character's movement drives toward, from its flags (local players) or speed.
local function effortTarget(chr, speed)
    local isLocal = chr:isLocalPlayer()
    if (isLocal and chr:isSprinting()) or (not isLocal and speed > SPEED_SPRINT) then return EFFORT_SPRINT end
    if (isLocal and chr:isRunning()) or (not isLocal and speed > SPEED_RUN) then return EFFORT_RUN end
    if speed > SPEED_WALK then return EFFORT_WALK end
    return 0
end

local function add(p)
    if (live[BREATH] or 0) >= MAX_PARTICLES then
        stats.dropped = stats.dropped + 1
        return
    end
    p.kind = BREATH
    live[BREATH] = (live[BREATH] or 0) + 1
    particles[#particles + 1] = p
    stats.emitted = stats.emitted + 1
end

-- Takes the particles of kind (nil: all) out of the list.
local function drop(kind)
    if not kind then
        particles, live = {}, {}
        return
    end
    if not live[kind] or live[kind] == 0 then return end
    local keep = {}
    for i = 1, #particles do
        local p = particles[i]
        if p.kind ~= kind then keep[#keep + 1] = p end
    end
    particles = keep
    live[kind] = 0
end

local function emit(chr, st, strength)
    local f = chr:getForwardDirection()
    local fx, fy = f:getX(), f:getY()
    local out = lerp(PUFF_SPEED[1], PUFF_SPEED[2], st.effort) * ZombRandFloat(0.8, 1.2)
    local side = ZombRandFloat(-0.12, 0.12)
    add({
        x = chr:getX() + fx * MOUTH_FWD, y = chr:getY() + fy * MOUTH_FWD, z = chr:getZ() + st.mouth,
        fz = math.floor(chr:getZ()),
        vx = fx * out - fy * side + st.vx * PUFF_CARRY, vy = fy * out + fx * side + st.vy * PUFF_CARRY,
        vz = rand(PUFF_RISE),
        age = 0, life = rand(PUFF_LIFE) * (0.8 + 0.5 * strength),
        shape = ZombRand(SHAPES),
        grow = (0.85 + 0.35 * st.effort) * ZombRandFloat(0.85, 1.15),
        alpha = st.alpha, owner = chr,
    })
end

-- Advances the breathing of character chr by dt s; starts and feeds its exhales.
local function breathe(chr, dt, clim)
    local st = states[chr]
    local x, y = chr:getX(), chr:getY()
    if not st then
        st = { t = ZombRandFloat(0, PERIOD_REST), period = PERIOD_REST, effort = 0, x = x, y = y,
            vx = 0, vy = 0, left = 0, puffs = 0, every = 1, mask = 1, maskAt = -1000 }
        states[chr] = st
    end
    st.seen = tick
    if dt > 0 then
        st.vx, st.vy = (x - st.x) / dt, (y - st.y) / dt
        if st.vx * st.vx + st.vy * st.vy > 100 then st.vx, st.vy = 0, 0 end   -- teleport
    end
    st.x, st.y = x, y

    -- the air changes slowly: asked every TEMP_TICKS ticks, not every tick
    if forcedTemp then
        st.temp, st.tempAt = forcedTemp, tick
    elseif not st.temp or tick - st.tempAt >= TEMP_TICKS then
        st.temp = clim:getAirTemperatureForCharacter(chr)
        st.tempAt = tick
    end
    local temp = st.temp
    -- too warm for vapour and no exhale going on (summer, indoors): nothing else to do; the effort
    -- waits where it was
    if st.left <= 0 and temp > ISnow.opt("BreathMaxTemp") then return end

    local speed = math.sqrt(st.vx * st.vx + st.vy * st.vy)
    -- endurance only of the local players (not known here for the others)
    local tired = chr:isLocalPlayer() and (1 - endurance(chr)) * TIRED or 0
    local target = math.max(effortTarget(chr, speed), tired)
    local tau = target > st.effort and EFFORT_UP or EFFORT_DOWN
    st.effort = st.effort + (target - st.effort) * math.min(1, dt / tau)

    local strength = Breath.strength(temp)
    if tick - st.maskAt > 120 then
        st.mask = maskFactor(chr)
        st.maskAt = tick
    end

    -- the exhale going on
    if st.left > 0 then
        st.left = st.left - dt
        st.acc = st.acc + dt
        while st.puffs > 0 and st.acc >= st.every do
            st.acc = st.acc - st.every
            st.puffs = st.puffs - 1
            emit(chr, st, st.strength)
        end
    end

    st.t = st.t + dt
    if st.t < st.period then return end
    st.t = 0
    st.period = Breath.period(st.effort, chr:isAsleep()) * ZombRandFloat(0.88, 1.12)
    if temp > ISnow.opt("BreathMaxTemp") or st.mask <= 0 then return end
    stats.exhales = stats.exhales + 1
    local len = math.max(EXHALE_MIN, math.min(EXHALE_MAX, st.period * EXHALE_PART))
    st.puffs = math.floor(lerp(PUFFS_REST, PUFFS_HARD, st.effort) + 0.5)
    st.every = len / st.puffs
    st.left, st.acc = len, st.every   -- the first wisp at once
    st.strength = strength
    st.mouth = mouthHeight(chr)
    st.alpha = ISnow.opt("BreathOpacity") * (0.6 + 0.4 * strength) * st.mask
end

local function canBreathe(chr, viewer)
    return chr and not chr:isDead() and not chr:getVehicle() and not chr:isInvisible() and chr:getCurrentSquare() ~= nil
        and math.abs(chr:getX() - viewer:getX()) < RADIUS and math.abs(chr:getY() - viewer:getY()) < RADIUS
end

-- Breathes for the characters near the viewer (player 0).
local function breatheAll(dt, viewer, clim)
    local n = 0
    for i = 0, 3 do
        local chr = getSpecificPlayer(i)
        if canBreathe(chr, viewer) then breathe(chr, dt, clim); n = n + 1 end
    end
    if isClient() then
        local others = ISnow.otherPlayers()
        if others then
            for i = 0, others:size() - 1 do
                local chr = others:get(i)
                if chr and not chr:isLocalPlayer() and canBreathe(chr, viewer) then breathe(chr, dt, clim); n = n + 1 end
            end
        end
    end
    stats.breathing = n
    -- forget characters not seen for a while (a car ride, gone out of range)
    if tick % 300 == 0 then
        local old = {}
        for chr, st in pairs(states) do
            if tick - st.seen > 300 then old[#old + 1] = chr end
        end
        for _, chr in ipairs(old) do states[chr] = nil end
    end
end

-- Breathes (breathing: Breath on and no rival mod) and moves every wisp.
local function update(dt, breathing)
    tick = tick + 1
    local viewer = getSpecificPlayer(0)
    if not viewer then return end
    local clim = getClimateManager()
    if breathing then breatheAll(dt, viewer, clim) end

    -- move the wisps
    if #particles == 0 then return end
    local wx, wy = 0, 0
    local kph = clim:getWindspeedKph()
    if kph > 0 then
        -- the weather carries things along (sin a, cos a) in world x, y (WorldFlares.Flare, bytecode
        -- 42.21; ISnow_Drift.lua): (cos a, sin a) blew the vapour mirrored to the falling snow
        local a = clim:getWindAngleRadians()
        local w = math.min(WIND_MAX, kph * WIND_DRIFT / 3.6)
        wx, wy = math.sin(a) * w, math.cos(a) * w
    end
    local drag = math.exp(-PUFF_DRAG * dt)
    local keep = {}
    local counts = {}
    local cell = getCell()
    for i = 1, #particles do
        local p = particles[i]
        p.age = p.age + dt
        if p.age < p.life then
            p.vx, p.vy = p.vx * drag, p.vy * drag
            local ox, oy = 0, 0
            if p.outside == nil then
                local sq = cell:getGridSquare(math.floor(p.x), math.floor(p.y), p.fz)
                p.outside = ISnow.snowReaches(sq)
            end
            if p.outside then ox, oy = wx, wy end
            p.x, p.y, p.z = p.x + (p.vx + ox) * dt, p.y + (p.vy + oy) * dt, p.z + p.vz * dt
            keep[#keep + 1] = p
            counts[p.kind] = (counts[p.kind] or 0) + 1
        end
    end
    particles, live = keep, counts
end

local function onTick()
    local now = getTimestampMs()
    local dt = lastMs and (now - lastMs) / 1000 or 0
    lastMs = now
    if not ready or isGamePaused() then return end
    -- quiet weather (ISnow.quietWeather: warmer than BreathMaxTemp by a margin, no snow): no breath
    -- shows; the wisps still in the air finish
    if #particles == 0 and ISnow.quietWeather() then return end
    -- Project Viewpoint draws the world in 3D now: the isometric screen position is wrong there,
    -- unless its submod's bridge gives its camera (ISnow_CompatViewpoint.lua)
    local breathing = not rival and ISnow.opt("Breath") and not (ISnow.Viewpoint and ISnow.Viewpoint.hideScreenParticles())
    if not breathing then
        drop(BREATH)
        if #particles == 0 then return end
    end
    local ok, err = pcall(update, math.min(dt, 0.1), breathing)
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
        drop()
        states = {}
    end
end

-- Project Viewpoint's 3D view (ISnow_CompatViewpoint.lua, VP.camera): a puff is placed and sized by
-- Viewpoint's own camera (ISnowVP.project, the way it places names over heads) instead of the
-- isometric screen. Its size in tiles is what the isometric picture covers (VP_ISO_PX_PER_TILE x
-- tile scale screen px per tile across the screen: x - y moves 32 x tile scale px per unit, and a
-- tile across the screen is sqrt 2 of x - y), and it fades out as it nears the camera: the first
-- person's own breath starts at the mouth, right under the eye.
local VP_ISO_PX_PER_TILE = 45.25
local VP_NEAR = { 0.12, 0.45 }   -- distance (tiles) over which a puff fades in from the camera

local function render()
    stats.drawn = 0
    if not ready or #particles == 0 then return end
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
    local seen = {}
    local drawn = 0
    local cam = ISnow.Viewpoint and ISnow.Viewpoint.camera()
    for i = 1, #particles do
        local p = particles[i]
        if p.fz == cz or cam then
            local u = p.age / p.life
            local out = 1 - (u - PUFF_FULL) / (1 - PUFF_FULL)
            local fade = u < PUFF_FULL and u / PUFF_FULL or out * math.sqrt(out)
            -- the character's own alpha: its breath fades with it when the viewer loses sight of it
            -- (the isometric view's sight; in Viewpoint's view it is left out)
            local owner = p.owner
            local ca = owner and seen[owner]
            if ca == nil then
                ca = (owner and not cam) and owner:getAlpha(pi) or 1
                if owner then seen[owner] = ca end
            end
            local a = fade * p.alpha * ca
            if a > 0.01 then
                local sx, sy = math.floor(p.x), math.floor(p.y)
                local k = sx * 1048576 + sy
                local light = lights[k]
                if not light then
                    local lsq = cell:getGridSquare(sx, sy, p.fz)
                    local c = lsq and lsq:getLightInfo(pi)
                    light = c and { c:getR(), c:getG(), c:getB() } or { 1, 1, 1 }
                    for j = 1, 3 do light[j] = LIGHT_LIFT + (1 - LIGHT_LIFT) * light[j] end
                    lights[k] = light
                end
                local size = TEX_SIZE * scale * p.grow * lerp(PUFF_GROW[1], PUFF_GROW[2], 1 - (1 - u) * (1 - u))
                local x, y
                if cam then
                    if cam.project(p.x, p.y, p.z) then
                        local d = cam.pdepth()
                        a = a * clamp01((d - VP_NEAR[1]) / (VP_NEAR[2] - VP_NEAR[1]))
                        size = size / (VP_ISO_PX_PER_TILE * Core.getTileScale()) * cam.pscale() * zoom
                        x, y = cam.px() * zoom, cam.py() * zoom
                    end
                else
                    x = (isoToScreenX(pi, p.x, p.y, p.z) - left) * zoom
                    y = (isoToScreenY(pi, p.x, p.y, p.z) - top) * zoom
                end
                if x and a > 0.01 then
                    if drawn == 0 then ISnow.Decals.resetBlend(player) end
                    r:render(textures[p.shape], x - size / 2, y - size / 2, size, size, light[1], light[2], light[3], a, nil)
                    drawn = drawn + 1
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
        drop()
    end
end

function Breath.stats()
    local p = getSpecificPlayer(0)
    local st = p and states[p]
    print(string.format("[ImmersiveSnow] breath: ready=%s rival=%s on=%s breathing=%d live=%d exhales=%d emitted=%d dropped=%d drawn=%d errors=%d",
        tostring(ready), tostring(rival), tostring(ISnow.opt("Breath")), stats.breathing, live[BREATH] or 0, stats.exhales,
        stats.emitted, stats.dropped, stats.drawn, stats.errors))
    if p then
        local temp = forcedTemp or getClimateManager():getAirTemperatureForCharacter(p)
        print(string.format("[ImmersiveSnow] player 0: temp=%.1f strength=%.2f effort=%.2f period=%.2f mask=%.2f endurance=%.2f",
            temp, Breath.strength(temp), st and st.effort or -1, st and st.period or -1, st and st.mask or -1, endurance(p)))
    end
    if lastError then print("[ImmersiveSnow] last error: " .. lastError) end
end

-- Console test: breathe as if the air were temp degrees (nil: the real temperature again).
function Breath.test(temp)
    forcedTemp = temp
end

-- 0.5.1 moved the BreathMaxTemp default from -5 to 7 C (ISnow.migrateDefault: old SP saves too).
local function migrateMaxTemp()
    ISnow.migrateDefault("breathMaxTemp051", "BreathMaxTemp", -5, 7)
end

local function onGameStart()
    local okMigrate, errMigrate = pcall(migrateMaxTemp)
    if not okMigrate then print("[ImmersiveSnow] breath: BreathMaxTemp not migrated: " .. tostring(errMigrate)) end
    local ok, err = pcall(load)
    if not ok then
        lastError = tostring(err)
        print("[ImmersiveSnow] breath disabled: " .. lastError)
    elseif rival then
        print("[ImmersiveSnow] breath off: " .. rival .. " draws breath already")
    end
end

Breath.init = onGameStart   -- for a reload from the console
Events.OnGameStart.Add(onGameStart)
ISnow.listen("OnTick", "Breath", onTick)
ISnow.listen("OnPostRender", "Breath", onRenderSafe)
