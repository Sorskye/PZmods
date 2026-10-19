-- Immersive Snow: footprints left in ground snow by players and zombies.
--
-- Prints are not world objects. They are drawn every frame from RenderOpaqueObjectsInWorld with
-- the scene depth, depth tested without depth write (ISnow_Decals.lua): objects, roofs and
-- players in front of a print cover it, zombies and shadows are drawn over it, and nothing is
-- saved or synced.
--
-- Why not objects on the square: every depth-writing path (tileWithDepth shader) writes depth
-- for the whole sprite quad, so a floor-level print blocks the shadows drawn later and the
-- bottom of the boots; floor-attached sprites end up under FBORenderSnow instead.
--
-- Snow carried on the soles: after a step in snow the next CarriedSnowSteps steps on clear floor
-- (a road, a porch, indoors) leave white prints (sprint_*), each fainter, which melt by the
-- temperature of their square (ISnow.Decals.carriedAger; options CarriedSnow*) and are as bright
-- as the light there (lit buffer, ISnow_Decals.lua).
--
-- Snow kicked up (SnowKick): a running or sprinting step into snow throws a little powder back off
-- the foot, and a character that goes down in the snow (knocked down, tripped, killed) raises a
-- puff along its body as it hits the ground. The particles are the blow-off's (ISnow_BlowOff.lua,
-- BlowOff.kick). Like the prints, only for characters a local player sees.
--
-- A body crawling through the snow leaves a furrow instead of prints (drag_*, gen_prints.py): a
-- crawler zombie, or a player prone in Lethal Stealth. Segments exactly DRAG_STEP apart along the
-- way it went, turned along the movement, like a tire track (ISnow_TireTracks.lua); in the prints'
-- buffers, so they last, fade and count like the prints of that character (under the same switches).
-- A corpse dragged through the snow leaves the same furrow, in the prints of the player dragging it.
--
-- Immersion 0.5.2 (each under its own switch, and only where the prints are: the same characters,
-- the same per-step work; nothing of it is synced in MP, every client works it out):
--  * Barefoot prints (BarefootPrints): a character with nothing in the Shoes location leaves a bare
--    foot (bare_*; snow carried off it: sbare_*). Local players: their worn items; zombies and remote
--    players: their item visuals (the worn items of a remote player stay on its own client,
--    SyncClothingPacket brings the visuals; ISnow_CharSnow.lua wornList), each visual's script item's
--    body location. Looked at again every SHOES_CHECK_MS (ZOMBIE_SHOES_MS: a recycled zombie object
--    gets new clothes), on a step only.
--  * Bloody footprints (BloodyFootprints): a step on a corpse (the planted foot within FOOT_REACH of
--    the body, ISnow_Blood.lua; blood on the floor does not count) makes the
--    next BloodyFootprintSteps steps leave red prints (bprint_* / bbare_*), full red and then paler
--    over the last ones, on snow over the dent and on clear ground (a floor) alone, like the carried snow.
--  * Blood on the snow (BloodOnSnow): drops (blood_*) by the steps of a bleeding character on snow.
--    Local players: BodyDamage.getNumPartsBleeding. Zombies have no bleeding of their own: one whose
--    health dropped (hit) bleeds for ZOMBIE_BLEED_MS. Remote players in MP: none, their client does
--    not tell; the BodyDamage of another player reaches a client only while it asks for it
--    (BodyDamageUpdatePacket, the medical check), PlayerInjuriesPacket carries only the limp.
-- Blood is one more buffer (multiply, its level by strength x fade, "strength" in ISnow_Decals.lua)
-- of BLOOD_SHARE of MaxFootprints; entries on snow age like the prints of who left them (snowfall
-- covers them), the rest at the same lifetime without snowfall. All of it is off with the game's
-- blood decals at "none" (ISnow.Blood.enabled), and, like every print, only while snow lies.

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_Decals"
require "ImmersiveSnow/ISnow_Blood"

local Footprints = {}
ISnow.Footprints = Footprints

local TWO_PI = math.pi * 2
local SIDE_OFFSET = 0.075        -- lateral distance of a foot from the body line
local FORWARD_OFFSET = 0.12      -- the planted foot is ahead of the body centre
local STEP_WALK = 0.55
local STEP_SNEAK = 0.42
local STEP_RUN = 0.8
local STEP_SPRINT = 0.95
local STEP_ZOMBIE = 0.5
local DRAG_STEP = ISnow.DRAG_STEP  -- the shortest step: under it no character is looked at
local TELEPORT_DIST = 3.0        -- movement larger than this resets tracking
local STATE_TTL_MS = 60000       -- forget characters not seen for this long
local RENDER_RADIUS = 45         -- tiles around the viewing player
local FULL_ALPHA_UNTIL = 0.4     -- fraction of lifetime before a print starts to fade

-- Snow kicked up (SnowKick), times BlowOffAmount (the low-end mode throws fewer): puffs per running /
-- sprinting step are options (SnowKickRun / SnowKickSprint, a fraction is the chance of one); the
-- chance of a crumb with a sprinting step, how fast the foot throws them back (tiles / s); a fall
-- (SnowKickFalls): puffs and crumbs along the body times SnowKickFallAmount (its length from the
-- feet along the facing, tiles), and how long a dying character takes to hit the ground (it goes
-- down when its death animation starts).
local KICK_CRUMB = 0.3
local KICK_SPEED = { 0.3, 0.9 }
local FALL_PUFFS, FALL_CRUMBS = 7, 3
local FALL_BODY = 0.8
local FALL_SPEED = 0.6
local FALL_DEATH_MS = 600

-- Immersion 0.5.2 (see the top): the blood buffer's limit as a part of MaxFootprints; how often a
-- character's shoes are looked at again; how long a hit zombie bleeds (real ms); chance of drops per
-- step and bleeding body part.
local BLOOD_SHARE = 0.25
local SHOES_CHECK_MS = 3000
local ZOMBIE_SHOES_MS = 30000
local ZOMBIE_BLEED_MS = 30000
local BLEED_DROPS = 0.45
local DROP_SPREAD = 0.15         -- tiles the drops fall off the body line
-- A planted foot this close to a corpse's line (ISnow_Blood.lua) stepped on it. Steps are about 0.55
-- apart, so a walk across a body plants one foot within 0.3 of it at least.
local FOOT_REACH = 0.3

-- Zombies' prints are a buffer of their own: they last ZombieFootprintHours, the players'
-- FootprintHours, and a buffer ages all its entries at one rate. MaxFootprints stays one limit for
-- both: either may use what the other leaves, and keeps at least half of it (a horde does not
-- push out the players' trail).
local prints, zprints
local function limitBeside(other)
    local max = ISnow.opt("MaxFootprints")
    return math.max(math.ceil(max / 2), max - (other:count() - other:fading()))
end
prints = ISnow.Decals.newBuffer(function() return limitBeside(zprints) end, nil, FULL_ALPHA_UNTIL, false, true)
zprints = ISnow.Decals.newBuffer(function() return limitBeside(prints) end, nil, FULL_ALPHA_UNTIL, false, true)
local carried = ISnow.Decals.newBuffer(function() return ISnow.opt("MaxFootprints") end, nil, FULL_ALPHA_UNTIL, true)
-- bloody prints and drops: { ..., sx, sy, strength, snow = on a snow square, zombie, drop }
local blood = ISnow.Decals.newBuffer(function() return math.max(1, math.floor(ISnow.opt("MaxFootprints") * BLOOD_SHARE)) end,
    nil, FULL_ALPHA_UNTIL, "strength", true)
-- [character] = { x, y, dist, foot, seen, carry = snowy steps left, blood = bloody steps left,
-- bare = no shoes, hp = a zombie's health }
local walkers = {}
local VARIANTS = ISnow.PRINT_VARIANTS
local sets = {}                  -- [(foot * DIRS + dir) * VARIANTS + variant] = texture paths by fade level
local carrySets = {}             -- [foot * DIRS + dir] = snowy print paths by alpha level (CARRIED_LEVELS)
local dragSets = {}              -- [dir * DRAG_VARIANTS + variant] = furrow segment paths by fade level
local bareSets = {}              -- [(foot * DIRS + dir) * BARE_VARIANTS + variant] = bare foot dents by fade level
local bareCarrySets = {}         -- [foot * DIRS + dir] = snow off a bare foot by alpha level
local bloodSets = {}             -- [foot * DIRS + dir] = bloody sole by level (BLOOD_LEVELS)
local bareBloodSets = {}         -- [foot * DIRS + dir] = bloody bare foot by level
local dropSets = {}              -- [variant] = blood drops by level
local anchorX, anchorY, anchorZ = 0, 0, 0
local dragX, dragY, dragZ = 0, 0, 0   -- Render3DItem point for DRAG_SIZE textures
local snowActive = false
local playerX, playerY = 0, 0
local ready = false
local stats = { placed = 0, dragged = 0, carried = 0, unseen = 0, errors = 0, kicks = 0, falls = 0,
    bare = 0, bloody = 0, drops = 0 }
local falls = {}                 -- falls to puff at: { chr, at = nowMs, x, y, z, fx, fy, zombie }
local nowMs = 0                  -- getTimestampMs() of this tick (forgetting walkers only)

-- n directions over a whole turn (ISnow.DIRS by default)
local function dirIndex(fx, fy, n)
    n = n or ISnow.DIRS
    local a = math.atan2(fy, fx)
    if a < 0 then a = a + TWO_PI end
    return math.floor(a / TWO_PI * n + 0.5) % n
end

-- A furrow segment looks the same both ways: DRAG_DIRS over half a turn.
local function dragDir(ux, uy)
    local a = math.atan2(uy, ux)
    if a < 0 then a = a + math.pi end
    return math.floor(a / math.pi * ISnow.DRAG_DIRS + 0.5) % ISnow.DRAG_DIRS
end

-- Only the paths: a set's textures load when its first print is laid (ISnow.Decals.newSet).
local function loadSprites()
    for foot = 0, ISnow.FEET - 1 do
        for dir = 0, ISnow.DIRS - 1 do
            for v = 0, VARIANTS - 1 do
                sets[(foot * ISnow.DIRS + dir) * VARIANTS + v] = ISnow.Decals.newSet(
                    function(level) return ISnow.printFile(foot, dir, v, level) end, ISnow.FADE_LEVELS)
            end
            carrySets[foot * ISnow.DIRS + dir] = ISnow.Decals.newSet(
                function(level) return ISnow.carriedPrintFile(foot, dir, level) end, ISnow.CARRIED_LEVELS)
            local key = foot * ISnow.DIRS + dir
            for v = 0, ISnow.BARE_VARIANTS - 1 do
                bareSets[key * ISnow.BARE_VARIANTS + v] = ISnow.Decals.newSet(
                    function(level) return ISnow.barePrintFile(foot, dir, v, level) end, ISnow.FADE_LEVELS)
            end
            bareCarrySets[key] = ISnow.Decals.newSet(
                function(level) return ISnow.carriedBareFile(foot, dir, level) end, ISnow.CARRIED_LEVELS)
            bloodSets[key] = ISnow.Decals.newSet(
                function(level) return ISnow.bloodPrintFile(false, foot, dir, level) end, ISnow.BLOOD_LEVELS)
            bareBloodSets[key] = ISnow.Decals.newSet(
                function(level) return ISnow.bloodPrintFile(true, foot, dir, level) end, ISnow.BLOOD_LEVELS)
        end
    end
    for v = 0, ISnow.BLOOD_DROP_VARIANTS - 1 do
        dropSets[v] = ISnow.Decals.newSet(function(level) return ISnow.bloodDropFile(v, level) end, ISnow.BLOOD_LEVELS)
    end
    for dir = 0, ISnow.DRAG_DIRS - 1 do
        for v = 0, ISnow.DRAG_VARIANTS - 1 do
            dragSets[dir * ISnow.DRAG_VARIANTS + v] = ISnow.Decals.newSet(
                function(level) return ISnow.dragFile(dir, v, level) end, ISnow.FADE_LEVELS)
        end
    end
    anchorX, anchorY, anchorZ = ISnow.Decals.anchor(ISnow.PRINT_SIZE, ISnow.PRINT_REACH)
    dragX, dragY, dragZ = ISnow.Decals.anchor(ISnow.DRAG_SIZE, ISnow.DRAG_REACH)
    ready = true
end

-- Throws n puffs (a fraction: the chance of one) and a crumb with chance crumb back off a foot at
-- x, y, z going along fx, fy.
local function kickAt(x, y, z, fx, fy, n, crumb)
    local blow = ISnow.BlowOff
    if not (blow and blow.kick) then return end
    local amount = ISnow.opt("BlowOffAmount")
    n = n * amount
    while n > 0 do
        if n >= 1 or ZombRandFloat(0, 1) < n then
            local back, side = ZombRandFloat(KICK_SPEED[1], KICK_SPEED[2]), ZombRandFloat(-0.25, 0.25)
            blow.kick(x, y, z, -fx * back - fy * side, -fy * back + fx * side)
            stats.kicks = stats.kicks + 1
        end
        n = n - 1
    end
    if crumb > 0 and ZombRandFloat(0, 1) < crumb * amount then
        local back = ZombRandFloat(KICK_SPEED[1], KICK_SPEED[2]) * 1.5
        blow.kick(x, y, z, -fx * back, -fy * back, true)
    end
end

-- A print or furrow segment into the players' buffer, or into zprints for a zombie.
local function pushMark(e, zombie)
    local buffer, other = prints, zprints
    if zombie then buffer, other = zprints, prints end
    buffer:push(e)
    -- a buffer trims itself only when it gets a print: the other gives up its share here, or a
    -- player standing still kept the whole trail while a horde filled its half (limitBeside)
    other:trim(math.max(1, other.maxFn()), getTimestampMs())
end

-- One furrow segment centred at x, y, z along ux, uy (a unit vector), on snow only: nothing is
-- carried off by a body (no sprint_* after it).
local function placeDrag(x, y, z, ux, uy, zombie)
    local sx, sy, sz = math.floor(x), math.floor(y), math.floor(z)
    if not ISnow.Decals.isSnowSquare(getCell(), sx, sy, sz) then return end
    local set = dragSets[dragDir(ux, uy) * ISnow.DRAG_VARIANTS + ISnow.decalVariant(ISnow.DRAG_VARIANTS)]
    if not set then return end
    pushMark({ x = x + dragX, y = y + dragY, z = sz, rz = sz + dragZ, set = set }, zombie)
    stats.dragged = stats.dragged + 1
end

-- A bloody print of the walker st at px, py on level sz (square sx, sy), one of its bloody steps
-- (paler over the last of them, ISnow.bloodStrength).
local function placeBloody(px, py, sz, sx, sy, key, st, zombie, onSnow)
    local left = st.blood
    st.blood = left - 1
    local set = (st.bare and bareBloodSets or bloodSets)[key]
    if not set then return end
    blood:push({ x = px + anchorX, y = py + anchorY, z = sz, rz = sz + anchorZ, set = set, sx = sx, sy = sy,
        strength = ISnow.bloodStrength(left, st.bloodMax), snow = onSnow, zombie = zombie })
    stats.bloody = stats.bloody + 1
end

-- After a step at px, py on level sz: a corpse under the foot soaks the soles of st.
local function stepInBlood(st, cell, px, py, sz)
    if not ISnow.Blood.onCorpse(cell, px, py, sz, FOOT_REACH) then return end
    st.bloodMax = math.max(1, math.floor(ISnow.opt("BloodyFootprintSteps")))
    st.blood = st.bloodMax
end

-- st: the walker's state (carried snow, blood, bare feet), nil for test prints. zombie: into zprints.
-- step: the stride (running ones kick up snow).
local function placePrint(x, y, z, fx, fy, foot, st, zombie, step)
    local side = foot == 0 and -1 or 1
    -- right of forward in world coords (y points south); nudge forward onto the planted foot
    local px = x - fy * SIDE_OFFSET * side + fx * FORWARD_OFFSET
    local py = y + fx * SIDE_OFFSET * side + fy * FORWARD_OFFSET
    local sx, sy, sz = math.floor(px), math.floor(py), math.floor(z)
    local key = foot * ISnow.DIRS + dirIndex(fx, fy)
    local bare = st ~= nil and st.bare == true
    -- bloody soles: asked only with the option on (and blood shown at all), the corpses near per step
    local bloody = st ~= nil and ISnow.opt("BloodyFootprints") and ISnow.Blood.enabled()

    local cell = getCell()
    if not ISnow.Decals.isSnowSquare(cell, sx, sy, sz) then
        -- a clear square: snow off the soles for a few steps, blood for a few more
        local left = st and st.carry or 0
        if left <= 0 and not bloody then return end
        local sq = cell:getGridSquare(sx, sy, sz)
        local floor = sq ~= nil and sq:getFloor() ~= nil
        if left > 0 then
            st.carry = left - 1
            local set = (bare and bareCarrySets or carrySets)[key]
            if set and floor and ISnow.opt("CarriedSnow") then
                carried:push({ x = px + anchorX, y = py + anchorY, z = sz, rz = sz + anchorZ, set = set, sx = sx, sy = sy,
                    strength = math.min(1, left / math.max(1, st.carryMax or left)) })
                stats.carried = stats.carried + 1
            end
        end
        if bloody then
            if (st.blood or 0) > 0 and floor then placeBloody(px, py, sz, sx, sy, key, st, zombie, false) end
            stepInBlood(st, cell, px, py, sz)
        end
        return
    end
    if st then
        st.carryMax = math.floor(ISnow.opt("CarriedSnowSteps"))
        st.carry = st.carryMax
    end

    local set
    if bare then
        set = bareSets[key * ISnow.BARE_VARIANTS + ISnow.decalVariant(ISnow.BARE_VARIANTS)]
    else
        set = sets[key * VARIANTS + ISnow.decalVariant(VARIANTS)]
    end
    if not set then return end

    pushMark({ x = px + anchorX, y = py + anchorY, z = sz, rz = sz + anchorZ, set = set }, zombie)
    stats.placed = stats.placed + 1
    if bare then stats.bare = stats.bare + 1 end
    if bloody then
        if (st.blood or 0) > 0 then placeBloody(px, py, sz, sx, sy, key, st, zombie, true) end
        stepInBlood(st, cell, px, py, sz)
    end
    -- trampled paths count the prints laid on each square (ISnow_Paths.lua, 0.5.2)
    if ISnow.Paths then ISnow.Paths.step(px, py, sz, fx, fy) end
    if step and step >= STEP_RUN and ISnow.opt("SnowKick") then
        local sprint = step >= STEP_SPRINT
        kickAt(px, py, z, fx, fy, ISnow.opt(sprint and "SnowKickSprint" or "SnowKickRun"), sprint and KICK_CRUMB or 0)
    end
end

-- A puff of snow along a body that just hit the ground at x, y, z, its feet there and its head
-- along fx, fy (a fall forwards or backwards, it is not known which: both ways a little).
local function fallPuff(x, y, z, fx, fy)
    local sx, sy, sz = math.floor(x), math.floor(y), math.floor(z)
    if not ISnow.Decals.isSnowSquare(getCell(), sx, sy, sz) then return end
    local blow = ISnow.BlowOff
    if not (blow and blow.kick) then return end
    local amount = ISnow.opt("BlowOffAmount") * ISnow.opt("SnowKickFallAmount")
    local puffs, crumbs = math.max(1, math.floor(FALL_PUFFS * amount + 0.5)), math.floor(FALL_CRUMBS * amount + 0.5)
    for i = 1, puffs + crumbs do
        local along = ZombRandFloat(-0.3, 1) * FALL_BODY * (i % 2 == 0 and 1 or -1)
        local side = ZombRandFloat(-0.2, 0.2)
        local ox, oy = fx * along - fy * side, fy * along + fx * side
        local d = math.max(0.05, math.sqrt(ox * ox + oy * oy))
        local v = FALL_SPEED * ZombRandFloat(0.5, 1.2)
        blow.kick(x + ox * 0.6, y + oy * 0.6, z, ox / d * v, oy / d * v, i > puffs)
    end
    stats.falls = stats.falls + 1
end

-- Drops of blood by a step at x, y, z of a character bleeding from parts body parts (a fraction of
-- them land, BLEED_DROPS each), on snow only.
local function dropBlood(x, y, z, parts, zombie)
    if ZombRand(1000) >= math.min(1, BLEED_DROPS * parts) * 1000 then return end
    local px = x + (ZombRand(201) - 100) / 100 * DROP_SPREAD
    local py = y + (ZombRand(201) - 100) / 100 * DROP_SPREAD
    local sx, sy, sz = math.floor(px), math.floor(py), math.floor(z)
    if not ISnow.Decals.isSnowSquare(getCell(), sx, sy, sz) then return end
    local set = dropSets[ISnow.decalVariant(ISnow.BLOOD_DROP_VARIANTS)]
    if not set then return end
    blood:push({ x = px + anchorX, y = py + anchorY, z = sz, rz = sz + anchorZ, set = set, sx = sx, sy = sy,
        snow = true, zombie = zombie, drop = true })
    stats.drops = stats.drops + 1
end

-- Whether a body location (ItemBodyLocation, "base:shoes"; a string in older builds) is the shoes'.
local function isShoes(loc)
    if loc == nil then return false end
    local name = string.lower(tostring(loc))
    return name == "base:shoes" or name == "shoes"
end

-- Whether chr wears something in the Shoes location. fromVisuals (zombies, remote players): by its
-- item visuals; a character with visuals none of which has a script item is not known, and counts
-- as shod (no visuals at all: naked, barefoot).
local function wearsShoes(chr, fromVisuals)
    if fromVisuals then
        local ivs = chr:getItemVisuals()
        if not ivs or ivs:size() == 0 then return ivs == nil end
        local known = false
        for i = 0, ivs:size() - 1 do
            local vis = ivs:get(i)
            local script = vis and vis:getScriptItem()
            if script then
                known = true
                if isShoes(script:getBodyLocation()) then return true end
            end
        end
        return not known
    end
    local worn = chr:getWornItems()
    if not worn then return true end
    for i = 0, worn:size() - 1 do
        local wi = worn:get(i)
        if wi and wi:getItem() and isShoes(wi:getLocation()) then return true end
    end
    return false
end
Footprints.wearsShoes = wearsShoes

-- Body parts chr bleeds from now (0: none). Zombies: 1 for ZOMBIE_BLEED_MS after their health
-- dropped (st.hp: what it was at the last step). Remote players: 0 (not known here).
local function bleedingParts(chr, isZombie, remote, st)
    if isZombie then
        local hp = chr:getHealth()
        if st.hp and hp < st.hp then st.bleedUntil = nowMs + ZOMBIE_BLEED_MS end
        st.hp = hp
        return (st.bleedUntil or 0) > nowMs and 1 or 0
    end
    if remote then return 0 end
    local bd = chr:getBodyDamage()
    return bd and bd:getNumPartsBleeding() or 0
end

-- The stride by the character's own flags. A remote player in MP has them too: its client sends
-- sneaking / running / sprinting with every position (PlayerPacket.booleanVariables, set on the
-- remote IsoPlayer by NetworkPlayerVariables.setBooleanVariables; a remote player's update returns
-- before the local input resets them, bytecode 42). Its speed here is not used: the position comes
-- over the network in jerks, and a walk read by the last few ticks looked like a run.
local function stepLength(chr, isZombie)
    if isZombie then return STEP_ZOMBIE end
    if chr:isSprinting() then return STEP_SPRINT end
    if chr:isRunning() then return STEP_RUN end
    if chr:isSneaking() then return STEP_SNEAK end
    return STEP_WALK
end

-- Animation variables that mods set on a player lying prone (true while prone, moving or not):
-- Lethal Stealth (RET_LethalStealth) sets "ltsproneposition" in RET_LTS.setPronePosition on every
-- client, a remote player's from its own SyncProneStates server command, so it is there for remote
-- players too. Vanilla B42 players do not crawl: on the floor (knocked down) they do not move, and
-- IsoMovingObject.isCrawling is false for them (bytecode 42.21).
local PRONE_VARIABLES = { "ltsproneposition" }

-- Corpses being dragged by a player: [body] = true. B42 drags a corpse as an IsoZombie reanimated for
-- the grapple only (IsoDeadBody.Grappled -> reanimateZombieForGrapple: on the floor, not a crawler;
-- IsoGameCharacter.isDraggingCorpse: the grappling target is such a zombie; bytecode 42.21), back to a
-- corpse when let go. It is in the cell's zombie list but tracked with the player dragging it
-- (trackDragged): its furrow goes into that player's prints, under the players' switches.
local dragged = {}

-- Whether chr moves lying in the snow (a furrow instead of prints): a crawler zombie (IsoZombie
-- crawling, which every client knows: ZombieStateFlags), a dragged corpse, or a player prone in one
-- of the mods above.
local function isLying(chr, isZombie)
    if dragged[chr] then return true end
    if isZombie then return chr:isCrawling() end
    for i = 1, #PRONE_VARIABLES do
        if chr:getVariableBoolean(PRONE_VARIABLES[i]) then return true end
    end
    return false
end
Footprints.isLying = isLying

-- The game hides zombies and remote players outside the local players' sight (targetAlpha 0,
-- IsoGameCharacter.updateSeenVisibility); their prints must not give them away either.
local function isSeenByLocalPlayer(chr)
    for i = 0, getNumActivePlayers() - 1 do
        if getSpecificPlayer(i) and chr:getTargetAlpha(i) > 0 then return true end
    end
    return false
end

-- Steps laid at most in one update (TELEPORT_DIST over the shortest step, STEP_SNEAK).
local MAX_STEPS = 8

-- x, y: the character's position (the caller has it already). remote: a remote player in MP (bare
-- feet by its item visuals, no bleeding). Every step finished since the last update leaves its
-- print where that step ended on the way here, so updates far apart (remote players every 6 ticks,
-- at a low frame rate) leave the whole trail, not one print per update.
local function track(chr, isZombie, onlyIfSeen, x, y, remote)
    local st = walkers[chr]
    local now = nowMs
    -- falls are watched for the puff (SnowKick)
    local watch = ISnow.opt("SnowKick") and ISnow.opt("SnowKickFalls")
    if not st then
        walkers[chr] = { x = x, y = y, dist = 0, foot = ZombRand(2), seen = now, carry = 0, blood = 0,
            down = watch and (chr:isOnFloor() or chr:isDead()) }
        return
    end
    st.seen = now
    if watch then
        -- going down: knocked down or tripped (on the floor at once), or killed (its death animation
        -- puts it on the ground FALL_DEATH_MS later)
        local floor = chr:isOnFloor()
        local down = floor or chr:isDead()
        if down and not st.down and not chr:getVehicle() and not chr:isInvisible()
                and (not onlyIfSeen or isSeenByLocalPlayer(chr)) then
            falls[#falls + 1] = { chr = chr, at = now + (floor and 0 or FALL_DEATH_MS), x = x, y = y, z = chr:getZ(),
                fx = chr:getForwardDirectionX(), fy = chr:getForwardDirectionY(), zombie = isZombie }
        end
        st.down = down
    end
    local dx, dy = x - st.x, y - st.y
    if dx == 0 and dy == 0 then return end
    local d = math.sqrt(dx * dx + dy * dy)
    st.x, st.y = x, y
    if d > TELEPORT_DIST then
        st.dist = 0
        return
    end
    st.dist = st.dist + d
    -- the shortest step first: lying or not is asked only when a step may be done
    if st.dist < DRAG_STEP then return end
    local drag = isLying(chr, isZombie)
    local step = drag and DRAG_STEP or stepLength(chr, isZombie)
    if st.dist < step then return end
    local n = math.min(MAX_STEPS, math.floor(st.dist / step))
    st.dist = st.dist - n * step
    if st.dist >= step then st.dist = 0 end

    -- invisible (admin Invisible, ghost mode): its prints would show where it walks. On the floor
    -- and not crawling: knocked down, sliding, no steps.
    if chr:getVehicle() or chr:isInvisible() or (not drag and chr:isOnFloor()) then return end
    -- on horseback (ISnow_AnimalTracks.lua): the horse leaves the prints
    if ISnow.isRiding and ISnow.isRiding(chr) then return end
    if onlyIfSeen and not isSeenByLocalPlayer(chr) then
        stats.unseen = stats.unseen + n
        st.foot = (st.foot + n) % 2
        return
    end

    local ux, uy = dx / d, dy / d
    local z = chr:getZ()
    if drag then
        -- the body drags along the way it goes: each segment is centred half a step behind the
        -- point where it ends
        for k = n - 1, 0, -1 do
            local back = math.min(d, st.dist + k * step) + step / 2
            local ok = pcall(placeDrag, x - ux * back, y - uy * back, z, ux, uy, isZombie)
            if not ok then stats.errors = stats.errors + 1 end
        end
        return
    end

    -- boots point where the body faces (backpedalling, strafing); fall back to movement
    local fx, fy = chr:getForwardDirectionX(), chr:getForwardDirectionY()
    if fx == 0 and fy == 0 then fx, fy = ux, uy end

    -- bare feet (looked at again now and then) and bleeding, for these steps
    if ISnow.opt("BarefootPrints") then
        if not st.bareAt or now >= st.bareAt then
            local ok, shod = pcall(wearsShoes, chr, isZombie or remote == true)
            st.bare = ok and not shod
            st.bareAt = now + (isZombie and ZOMBIE_SHOES_MS or SHOES_CHECK_MS)
            if not ok then stats.errors = stats.errors + 1 end
        end
    else
        st.bare, st.bareAt = false, nil
    end
    local bleed = 0
    if ISnow.opt("BloodOnSnow") and ISnow.Blood.enabled() then
        local ok, parts = pcall(bleedingParts, chr, isZombie, remote, st)
        if ok then bleed = parts else stats.errors = stats.errors + 1 end
    end

    for k = n - 1, 0, -1 do
        -- the step k steps before the last one ended this far back along the way
        local back = math.min(d, st.dist + k * step)
        local sx, sy = x - ux * back, y - uy * back
        local ok = pcall(placePrint, sx, sy, z, fx, fy, st.foot, st, isZombie, step)
        if not ok then stats.errors = stats.errors + 1 end
        if bleed > 0 and not pcall(dropBlood, sx, sy, z, bleed, isZombie) then stats.errors = stats.errors + 1 end
        st.foot = 1 - st.foot
    end
end

-- [player] = the corpse it drags (in dragged)
local dragging = {}

-- The corpse player drags, if any, tracked as a body lying in the snow with player's prints.
local function trackDragged(player, onlyIfSeen, remote)
    local body = player:isDraggingCorpse() and player:getGrapplingTarget() or nil
    local was = dragging[player]
    if was ~= body then
        if was then dragged[was] = nil end
        dragging[player] = body
        -- a fresh start: as a zombie it may have been tracked before, with its own steps
        if body then walkers[body] = nil end
    end
    if not body then return end
    dragged[body] = true
    track(body, false, onlyIfSeen, body:getX(), body:getY(), remote)
end

local function onPlayerUpdate(player)
    local x, y = player:getX(), player:getY()
    if player:getPlayerNum() == 0 then
        playerX, playerY = x, y
    end
    if not snowActive or not ISnow.opt("Footprints") then return end
    track(player, false, false, x, y)
    local ok = pcall(trackDragged, player, false)
    if not ok then stats.errors = stats.errors + 1 end
end

-- Zombies are gone through from onTick every ZOMBIE_TICKS ticks, not from OnZombieUpdate:
-- IsoZombie.updateInternal raises that for every zombie on every update, a Java -> Lua call per
-- zombie per frame all winter (30000 a second with 500 zombies) only to throw most of them away by
-- distance. A zombie walks under 0.2 tiles in ZOMBIE_TICKS ticks at 30 fps (a sprinter), well
-- under STEP_ZOMBIE, so track() still lays every step; a print lands where the zombie is at the
-- tick, at most that far past the exact footfall.
local ZOMBIE_TICKS = 2
local zombieR2 = 0
local zombiesOn = false          -- snow on the ground and ZombieFootprints on (syncZombies)

-- A zombie outside ZombieRadius is not looked at again (two Java calls for its position) until it
-- could be inside: half the gap closed by the zombie at ZOMBIE_MAX_SPEED, half by player 0 (the
-- odometer: how far it went, a car ride or a teleport included), and after FAR_MAX_MS at the
-- latest (a new radius). Most of a town's zombie list is far, every sweep went through it all.
-- ZOMBIE_MAX_SPEED is in real time: while the game runs fast (SP fast-forward) none is skipped.
local ZOMBIE_MAX_SPEED = 8       -- tiles / s, faster than a sprinter
local FAR_MAX_MS = 3000
-- Emptied every game minute (onEveryOneMinute): Kahlua has no weak tables (ISnow.prune), and a
-- zombie object back from the pool must not keep the skip of the one it was.
local farUntilMs = {}   -- [zombie] = nowMs before which it is skipped
local farUntilOdo = {}  -- [zombie] = odometer before which it is skipped
local odometer, odoX, odoY = 0, nil, nil
local zstats = { looked = 0, skipped = 0 }

local function trackZombies()
    local cell = getCell()
    local list = cell and cell:getZombieList()
    if not list then return end
    local px, py, r2 = playerX, playerY, zombieR2
    if odoX then
        local dx, dy = px - odoX, py - odoY
        odometer = odometer + math.sqrt(dx * dx + dy * dy)
    end
    odoX, odoY = px, py
    local now, odo, r = nowMs, odometer, math.sqrt(r2)
    local fast = getGameSpeed ~= nil and getGameSpeed() > 1
    local looked = 0
    local n = list:size()
    for i = 0, n - 1 do
        local z = list:get(i)
        local t = farUntilMs[z]
        -- a dragged corpse goes with the player dragging it (trackDragged)
        if not dragged[z] and (fast or not t or now >= t or odo >= farUntilOdo[z]) then
            looked = looked + 1
            local x, y = z:getX(), z:getY()
            local dx, dy = x - px, y - py
            local d2 = dx * dx + dy * dy
            if d2 <= r2 then
                if t then farUntilMs[z], farUntilOdo[z] = nil, nil end
                track(z, true, true, x, y)
            else
                local half = (math.sqrt(d2) - r) / 2
                farUntilMs[z] = now + math.min(FAR_MAX_MS, half / ZOMBIE_MAX_SPEED * 1000)
                farUntilOdo[z] = odo + half
            end
        end
    end
    zstats.looked, zstats.skipped = looked, n - looked
end

local function syncZombies()
    local r = ISnow.opt("ZombieRadius")
    zombieR2 = r * r
    zombiesOn = snowActive and ISnow.opt("ZombieFootprints") and true or false
end

-- Remote players in MP do not raise OnPlayerUpdate on this client.
local REMOTE_TICKS = 6

local function trackRemotes()
    local players = ISnow.otherPlayers()
    if not players then return end
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and not p:isLocalPlayer() and not p:isDead() then
            track(p, false, true, p:getX(), p:getY(), true)
            trackDragged(p, true, true)
        end
    end
end

-- Puffs the falls whose time has come, where the body is now (a dying one may still slide).
local function puffFalls()
    local keep = {}
    local puff = ISnow.opt("SnowKick") and ISnow.opt("SnowKickFalls")
    for _, f in ipairs(falls) do
        if nowMs >= f.at then
            local chr, x, y = f.chr, f.x, f.y
            local okPos, cx, cy = pcall(function() return chr:getX(), chr:getY() end)
            if okPos and cx and math.abs(cx - x) < TELEPORT_DIST and math.abs(cy - y) < TELEPORT_DIST then x, y = cx, cy end
            if puff and not pcall(fallPuff, x, y, f.z, f.fx, f.fy) then stats.errors = stats.errors + 1 end
        else
            keep[#keep + 1] = f
        end
    end
    falls = keep
end

local tickCounter = 0
local function onTick()
    nowMs = getTimestampMs()
    tickCounter = tickCounter + 1
    if #falls > 0 then puffFalls() end
    if zombiesOn and snowActive and tickCounter % ZOMBIE_TICKS == 0 then
        local ok = pcall(trackZombies)
        if not ok then stats.errors = stats.errors + 1 end
    end
    if tickCounter % REMOTE_TICKS ~= 0 or not isClient() then return end
    if not snowActive or not ISnow.opt("Footprints") then return end
    local ok = pcall(trackRemotes)
    if not ok then stats.errors = stats.errors + 1 end
end

local function onRender(playerIndex)
    if not ready then return end
    prints:render(playerIndex, RENDER_RADIUS)
    zprints:render(playerIndex, RENDER_RADIUS)
    carried:render(playerIndex, RENDER_RADIUS)
    blood:render(playerIndex, RENDER_RADIUS)
end

local function onRenderSafe(playerIndex)
    local ok = pcall(onRender, playerIndex)
    if not ok then stats.errors = stats.errors + 1 end
end

local function refreshSnowState()
    snowActive = ISnow.Decals.snowActive()
    if not snowActive then
        -- snow melted away: drop everything
        prints:clear()
        zprints:clear()
        carried:clear()
        blood:clear()
    else
        -- turned off in Options > Mods: gone at once, not as they age (zombies' footprints are
        -- off whenever the players' are, FROM in ISnow_Config.lua)
        local playersOff = not ISnow.opt("Footprints")
        local zombiesOff = not ISnow.opt("ZombieFootprints")
        if playersOff then prints:clear() end
        if zombiesOff then zprints:clear() end
        if playersOff or not ISnow.opt("CarriedSnow") then carried:clear() end
        -- the 0.5.2 marks of whoever's prints are off, or of a kind turned off
        local bloodyOff = not ISnow.opt("BloodyFootprints")
        local dropsOff = not ISnow.opt("BloodOnSnow")
        if not ISnow.Blood.enabled() or (playersOff and zombiesOff) or (bloodyOff and dropsOff) then
            blood:clear()
        elseif (playersOff or zombiesOff or bloodyOff or dropsOff) and blood:count() > 0 then
            blood:killWhere(function(e)
                if e.zombie then if zombiesOff then return true end elseif playersOff then return true end
                if e.drop then return dropsOff end
                return bloodyOff
            end)
        end
    end
    syncZombies()
end

-- Per-minute ageing of the blood (Buffer:ageEach): on snow like the prints of who left it (fresh
-- snowfall covers it), on clear ground at the same lifetime without the snowfall.
local function bloodAger()
    local playerHours, zombieHours = ISnow.opt("FootprintHours"), ISnow.opt("ZombieFootprintHours")
    local snowP, snowZ = ISnow.Decals.agePerMinute(playerHours), ISnow.Decals.agePerMinute(zombieHours)
    local clearP, clearZ = 1 / 60 / math.max(0.1, playerHours), 1 / 60 / math.max(0.1, zombieHours)
    return function(e)
        if e.snow then return e.zombie and snowZ or snowP end
        return e.zombie and clearZ or clearP
    end
end

-- Ages prints; fresh snowfall covers them faster.
local function onEveryOneMinute()
    refreshSnowState()
    farUntilMs, farUntilOdo = {}, {}

    prints:age(ISnow.Decals.agePerMinute(ISnow.opt("FootprintHours")))
    zprints:age(ISnow.Decals.agePerMinute(ISnow.opt("ZombieFootprintHours")))
    carried:ageEach(ISnow.Decals.carriedAger())
    blood:ageEach(bloodAger())

    -- corpses let go of while the prints were off or no snow lay (zombie objects get recycled)
    for p, body in pairs(dragging) do
        local ok, still = pcall(function() return p:isDraggingCorpse() and p:getGrapplingTarget() == body end)
        if not (ok and still) then
            dragging[p], dragged[body] = nil, nil
        end
    end

    -- forget characters we have not seen for a while (zombies get recycled)
    local now = getTimestampMs()
    for chr, st in pairs(walkers) do
        if now - st.seen > STATE_TTL_MS then walkers[chr] = nil end
    end
end

local function onGameStart()
    nowMs = getTimestampMs()
    local ok, err = pcall(loadSprites)
    if not ok then
        stats.errors = stats.errors + 1
        print("[ImmersiveSnow] loading print textures failed: " .. tostring(err))
    end
    refreshSnowState()
end

-- Debug console helpers ------------------------------------------------------

function Footprints.stats()
    local fullTex = sets[0] and ISnow.Decals.ensureSet(sets[0])
    print(string.format("[ImmersiveSnow] snowActive=%s snowTarget=%d prints=%d (fading %d) zombie prints=%d (fading %d) drawnLastFrame=%d placed=%d dragged=%d expired=%d pushedOut=%d unseen=%d errors=%d carried=%d (placed %d, drawn %d) max=%d",
        tostring(snowActive), getCell():getSnowTarget(), prints:count(), prints:fading(), zprints:count(), zprints:fading(),
        prints.drawn + zprints.drawn, stats.placed, stats.dragged, prints.expired + zprints.expired, prints.evicted + zprints.evicted,
        stats.unseen, stats.errors, carried:count(), stats.carried, carried.drawn, ISnow.opt("MaxFootprints")))
    print(string.format("[ImmersiveSnow] snow kicked up: on=%s puffs=%d falls=%d pending=%d",
        tostring(ISnow.opt("SnowKick")), stats.kicks, stats.falls, #falls))
    print(string.format("[ImmersiveSnow] immersion: bare prints=%d blood=%d (fading %d, drawn %d) bloody prints=%d drops=%d bloodShown=%s",
        stats.bare, blood:count(), blood:fading(), blood.drawn,
        stats.bloody, stats.drops, tostring(ISnow.Blood.enabled())))
    print("[ImmersiveSnow] texture " .. ISnow.TEXTURE_DIR .. ISnow.printFile(0, 0, 0, ISnow.FADE_LEVELS) .. ": " ..
        (fullTex and (fullTex:getWidth() .. "x" .. fullTex:getHeight()) or "MISSING") ..
        string.format(", tileScale=%d, anchor=%.4f,%.4f,%.4f, carrier=%s, zombie sweep looked=%d skipped=%d", Core.getTileScale(),
            anchorX, anchorY, anchorZ, tostring(ISnow.Decals.carrier() ~= nil), zstats.looked, zstats.skipped))
end

function Footprints.clear()
    prints:clear()
    zprints:clear()
    carried:clear()
    blood:clear()
end

-- Stamps a short trail in front of player 0 without walking (tests rendering only).
function Footprints.testTrail()
    local p = getSpecificPlayer(0)
    local fx, fy = p:getForwardDirectionX(), p:getForwardDirectionY()
    local x, y, z = p:getX(), p:getY(), p:getZ()
    for s = 1, 10 do
        placePrint(x + fx * s * 0.55, y + fy * s * 0.55, z, fx, fy, s % 2)
    end
    Footprints.stats()
end

-- Stamps a short furrow in front of player 0 without crawling (tests rendering only).
function Footprints.testDrag()
    local p = getSpecificPlayer(0)
    local fx, fy = p:getForwardDirectionX(), p:getForwardDirectionY()
    local x, y, z = p:getX(), p:getY(), p:getZ()
    for s = 1, 10 do
        placeDrag(x + fx * s * ISnow.DRAG_STEP, y + fy * s * ISnow.DRAG_STEP, z, fx, fy)
    end
    Footprints.stats()
end

-- Stamps a bloody bare trail and blood drops beside it in front of player 0 (tests rendering only).
function Footprints.testImmersion()
    local p = getSpecificPlayer(0)
    local fx, fy = p:getForwardDirectionX(), p:getForwardDirectionY()
    local x, y, z = p:getX(), p:getY(), p:getZ()
    local st = { bare = true, blood = 6, bloodMax = 6, carry = 0 }
    for s = 1, 8 do
        placePrint(x - fy + fx * s * 0.55, y + fx + fy * s * 0.55, z, fx, fy, s % 2, st)
        dropBlood(x + fy + fx * s * 0.55, y - fx + fy * s * 0.55, z, 3)
    end
    Footprints.stats()
end

function Footprints.forceSnow()
    getCore():setForceSnow(true)
    forceSnowCheck()
    getClimateManager():triggerWinterIsComingStorm()
end

Events.OnGameStart.Add(onGameStart)
Events.EveryOneMinute.Add(onEveryOneMinute)
ISnow.listen("OnPlayerUpdate", "Footprints", onPlayerUpdate)
ISnow.listen("OnTick", "Footprints", onTick)
ISnow.listen("RenderOpaqueObjectsInWorld", "Footprints", onRenderSafe)
