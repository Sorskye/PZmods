-- Immersive Snow: tracks of B42 animals in the ground snow (hoof and paw prints), to follow game.
--
-- The prints are decals like the footprints (ISnow_Decals.lua, ISnow_Footprints.lua): drawn every
-- frame, multiply blended, in a buffer of their own (AnimalTrackHours, MaxAnimalTracks), nothing
-- saved or synced. Every client lays the prints of the animals near its player 0 itself, as it does
-- for the zombies.
--
-- B42 animals (bytecode 42.21): IsoAnimal extends IsoPlayer, but no path of ours meets them as a
-- player. IsoPlayer.updateInternal1 returns for an animal before OnPlayerUpdate is raised;
-- getOnlinePlayers is GameClient.IDToPlayerMap (filled only by ConnectedPacket: connected players)
-- or, on a server, the players of the connections; getSpecificPlayer is the local players; animals
-- are not in the cell's zombie list. So they leave no boot prints and get no snow on clothes. They
-- are moving objects of the cell: IsoCell.getAnimals() (public, so exposed with the class) goes
-- through IsoCell.objectList and returns a new LinkedList of the IsoAnimals in it, so the list is
-- asked for once every LIST_MS and kept between (the nearest MAX_TRACKED within the radius).
-- Animals on a butcher's hook (isOnHook), in a hutch (getHutch), in a vehicle or trailer
-- (getVehicle) and invisible ones leave none; one picked up is an item, not in the cell.
-- Vanilla's own AnimalTracks (zombie.characters.animals.AnimalTracks, IsoAnimalTrack objects) are
-- something else: signs of the virtual herds for the tracking skill, found by searching.
--
-- As the zombies' (ISnow_Footprints.lua), the prints of an animal no local player sees (the game
-- hides it: targetAlpha 0, behind the player or a wall) are not laid: prints showing up out of
-- nowhere give away an animal the player cannot see. The trail it left in sight stays to follow.
--
-- What print an animal leaves: its group in the vanilla Lua table AnimalDefinitions.animals[type]
-- (the definition files of vanilla and of mods fill it; mod animals of a known group get its
-- prints), TYPE_GROUP when that table has none. GROUPS has the print kind (shape and size, the
-- textures of tools/gen_animal_prints.py) and the gait. A walking quadruped puts its hind foot
-- into the print of the fore foot (direct register), so a walk is one line of prints, left and
-- right of the body line; running, the feet land apart: a pair of prints per step, the steps
-- longer. A rabbit bounds: per bound the two long hind feet side by side ahead of the two fore
-- feet one behind the other. Mice and rats leave none (smaller than a pixel).
--
-- Mods (checked in their code, 2026-10-03):
-- * Horse Mod (Workshop 3661336777, id Horse; "Ride Horses in MP" 3758708355 adds MP riding):
--   horses are vanilla IsoAnimals, group "horse" (stallion, mare, filly). The rider is the player,
--   pinned every tick to the horse (setForceX / Y): it would walk boot prints along under the
--   horse, so footprints and the snow walked into the shoes skip a rider (ISnow.isRiding, below).
--   It still gets snow on it like any player outdoors.
-- * Bicycle! (3461415167, id BicycleMod): not an animal, but its rider is a player on foot as far
--   as the game knows (the bicycle is an item in the hands, the pedalling an animation), so the
--   same skip; the wheels leave a rut (ISnow_TireTracks.lua).
-- * Companion Dogs (3740052292, id CompanionDogs) and CD: Cats (3791294616, id CompanionCat):
--   vanilla IsoAnimals too, groups "dog" (dog*, gs* German shepherds) and "cat". A dog carried is an
--   AnimalInventoryItem (out of the cell); one riding in its owner's vehicle is despawned and spawned
--   again by the vehicle when the owner gets out (a jump: TELEPORT_DIST); a fence hop in MP may
--   blink it invisible.

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_Decals"

local AnimalTracks = {}
ISnow.AnimalTracks = AnimalTracks

-- Texture layout: keep in sync with tools/gen_animal_prints.py.
local SIZE = 32                  -- px, square texture with the print centred
local REACH = 12                 -- px below the centre the visible print reaches (10 in the PNGs)
local VARIANTS = 2               -- textures per kind and direction, one picked at random per print
local DIRS = ISnow.DIRS
local KINDS = { "cloven_s", "cloven_m", "cloven_l", "hoof_m", "hoof_l", "paw_s", "paw_m", "paw_l", "bird_s", "bird_m" }
AnimalTracks.KINDS = KINDS

local function printFile(kind, dir, variant, level)
    return "aprint_" .. kind .. "_" .. dir .. "_" .. variant .. "_" .. level .. ".png"
end
AnimalTracks.printFile = printFile

-- Per group: the print kind of an adult and of a young one (YOUNG), the distance between two
-- prints walking (tiles; a stride is two of them), half the width of the trail, the speed (tiles /
-- s) above which it runs, the gait ("bound": rabbits; else a walk). Roughly the real ones, a little
-- longer to go with the prints, which are larger than life (EXAGGERATE in gen_animal_prints.py).
-- Public: a mod adding an animal group may add its line here.
local GROUPS = {
    cow = { kind = "cloven_l", young = "cloven_m", step = 0.5, side = 0.12, run = 2.5 },
    horse = { kind = "hoof_l", young = "hoof_m", step = 0.65, side = 0.1, run = 3.0 },
    deer = { kind = "cloven_m", young = "cloven_s", step = 0.42, side = 0.07, run = 2.5 },
    sheep = { kind = "cloven_s", young = "cloven_s", step = 0.3, side = 0.06, run = 2.0 },
    pig = { kind = "cloven_s", young = "cloven_s", step = 0.28, side = 0.07, run = 2.0 },
    dog = { kind = "paw_m", young = "paw_s", step = 0.32, side = 0.05, run = 2.5 },
    cat = { kind = "paw_s", young = "paw_s", step = 0.24, side = 0.025, run = 2.2 },
    raccoon = { kind = "paw_s", young = "paw_s", step = 0.22, side = 0.05, run = 2.0 },
    rabbit = { kind = "paw_s", young = "paw_s", step = 0.45, side = 0.04, run = 2.0, gait = "bound" },
    chicken = { kind = "bird_s", young = "bird_s", step = 0.16, side = 0.025, run = 1.8 },
    turkey = { kind = "bird_m", young = "bird_s", step = 0.22, side = 0.03, run = 2.0 },
}
AnimalTracks.GROUPS = GROUPS
-- The young of each group (vanilla types; Horse Mod filly; Companion Dogs dogpup, gspup; CD: Cats
-- catpup): the young kind, steps YOUNG_STEP as long.
local YOUNG = { cowcalf = true, fawn = true, lamb = true, piglet = true, chick = true, turkeypoult = true,
    rabkitten = true, raccoonkit = true, filly = true, dogpup = true, gspup = true, catpup = true }
local YOUNG_STEP = 0.7
-- Types whose kind is not their group's: German shepherds (Companion Dogs) have larger paws.
local TYPE_KIND = { gsmale = "paw_l", gsfemale = "paw_l" }
-- Group by type when AnimalDefinitions has none (vanilla 42.21 and the mods above).
local TYPE_GROUP = {
    cow = "cow", bull = "cow", cowcalf = "cow", doe = "deer", buck = "deer", fawn = "deer",
    ewe = "sheep", ram = "sheep", lamb = "sheep", sow = "pig", boar = "pig", piglet = "pig",
    hen = "chicken", cockerel = "chicken", chick = "chicken",
    turkeyhen = "turkey", gobblers = "turkey", turkeypoult = "turkey",
    rabdoe = "rabbit", rabbuck = "rabbit", rabkitten = "rabbit",
    raccoonsow = "raccoon", raccoonboar = "raccoon", raccoonkit = "raccoon",
    stallion = "horse", mare = "horse", filly = "horse",
    dogmale = "dog", dogfemale = "dog", dogpup = "dog", gsmale = "dog", gsfemale = "dog", gspup = "dog",
    catmale = "cat", catfemale = "cat", catpup = "cat",
}
AnimalTracks.TYPE_GROUP = TYPE_GROUP

local RUN_STRIDE = 2.2           -- running, the steps are this many times longer ...
local RUN_PAIR = 0.3             -- ... and each leaves two prints, the second this part of a step behind
local BOUND_HIND, BOUND_FORE = 0.06, { -0.08, -0.17 }   -- a bound's prints along the way, in tiles
local SPEED_SMOOTH = 0.35        -- weight of the newest speed sample
local TELEPORT_DIST = 3.0        -- movement larger than this resets tracking
local MAX_STEPS = 8              -- steps laid at most in one update
local STATE_TTL_MS = 60000       -- forget animals not seen for this long
local RENDER_RADIUS = 45
local FULL_ALPHA_UNTIL = 0.4

-- The sweep (onTick): the animals of the cell are listed every LIST_MS (IsoCell.getAnimals builds
-- a list, see the top), keeping the nearest MAX_TRACKED within AnimalTrackRadius + LIST_MARGIN of
-- player 0 (an animal runs at most about that far in LIST_MS); every ANIMAL_TICKS ticks those
-- within the radius are followed, as the zombies (ISnow_Footprints.lua): a galloping horse covers
-- well under a step in two ticks, and track() lays every step finished since its last look.
local LIST_MS = 1000
local LIST_MARGIN = 10
local MAX_TRACKED = 48
local ANIMAL_TICKS = 2

local prints = ISnow.Decals.newBuffer(function() return ISnow.opt("MaxAnimalTracks") end, nil, FULL_ALPHA_UNTIL, false, true)
local sets = {}                  -- [kind] = { [dir * VARIANTS + variant] = texture paths by fade level }
local walkers = {}               -- [animal] = { x, y, dist, side, seen, speed }
local infos = {}   -- [animal] = its GROUPS line + kind, or false: none
local tracked = {}               -- the animals followed, refreshed every LIST_MS
local listedAt = nil
local anchorX, anchorY, anchorZ = 0, 0, 0
local ready = false
local snowActive = false
local on = false                 -- snow on the ground and AnimalTracks on
local nowMs = 0
local stats = { placed = 0, unseen = 0, listed = 0, followed = 0, errors = 0 }

-- Animation variables riding mods set on the rider while mounted (true on every client, a remote
-- rider's too): Horse Mod (Mounts.addMount, AnimationVariable.RIDING_HORSE, also run on the clients
-- by its Mount command); Bicycle! (Workshop 3461415167, id BicycleMod, 5.3.1: BicycleMenu
-- .enterMountedState sets BicycleActive on the rider, its BicycleSyncClient on a remote rider from the
-- server's relay; off again on dismount, death and its state guards). A player walking the bicycle
-- in its hands is not mounted and leaves boot prints.
local RIDING_VARIABLES = { "HorseRiding", "BicycleActive" }
-- Those of them that put the rider on two wheels: the bicycle leaves a tire track instead
-- (ISnow_TireTracks.lua, ISnow.isCycling).
local CYCLING_VARIABLES = { "BicycleActive" }

local function anyVariable(chr, names)
    for i = 1, #names do
        if chr:getVariableBoolean(names[i]) then return true end
    end
    return false
end

-- Whether chr rides an animal or a bicycle: no boot prints under it, no snow walked into its shoes.
function ISnow.isRiding(chr)
    return anyVariable(chr, RIDING_VARIABLES)
end

-- Whether chr rides a bicycle (one of the riding mods above).
function ISnow.isCycling(chr)
    return anyVariable(chr, CYCLING_VARIABLES)
end

-- Whether a local player sees a (the game fades out what none does, as for the zombies).
local function isSeen(a)
    for i = 0, getNumActivePlayers() - 1 do
        if getSpecificPlayer(i) and a:getTargetAlpha(i) > 0 then return true end
    end
    return false
end

local function dirIndex(fx, fy)
    local a = math.atan2(fy, fx)
    if a < 0 then a = a + math.pi * 2 end
    return math.floor(a / (math.pi * 2) * DIRS + 0.5) % DIRS
end

local function loadSprites()
    for _, kind in ipairs(KINDS) do
        local byDir = {}
        for dir = 0, DIRS - 1 do
            for v = 0, VARIANTS - 1 do
                byDir[dir * VARIANTS + v] = ISnow.Decals.newSet(
                    function(level) return printFile(kind, dir, v, level) end, ISnow.FADE_LEVELS)
            end
        end
        sets[kind] = byDir
    end
    anchorX, anchorY, anchorZ = ISnow.Decals.anchor(SIZE, REACH)
    ready = true
end

-- The group of an animal type: AnimalDefinitions (Lua) first, then TYPE_GROUP.
local function groupOf(animalType)
    local defs = AnimalDefinitions
    local def = type(defs) == "table" and type(defs.animals) == "table" and defs.animals[animalType]
    local group = type(def) == "table" and def.group
    if type(group) == "string" and GROUPS[group] then return group end
    return TYPE_GROUP[animalType]
end
AnimalTracks.groupOf = groupOf

-- What animal a leaves (cached): { kind, step, side, run, gait }, or false for none.
local function infoOf(a)
    local info = infos[a]
    if info ~= nil then return info end
    info = false
    local animalType = a:getAnimalType()
    local group = animalType and groupOf(animalType)
    local g = group and GROUPS[group]
    if g then
        local young = YOUNG[animalType] == true
        info = { kind = TYPE_KIND[animalType] or (young and g.young or g.kind), step = g.step * (young and YOUNG_STEP or 1),
            side = g.side * (young and YOUNG_STEP or 1), run = g.run, gait = g.gait }
    end
    infos[a] = info
    return info
end

local function placePrint(kind, x, y, z, fx, fy)
    local sx, sy, sz = math.floor(x), math.floor(y), math.floor(z)
    if not ISnow.Decals.isSnowSquare(getCell(), sx, sy, sz) then return end
    local byDir = sets[kind]
    local set = byDir and byDir[dirIndex(fx, fy) * VARIANTS + ISnow.decalVariant(VARIANTS)]
    if not set then return end
    prints:push({ x = x + anchorX, y = y + anchorY, z = sz, rz = sz + anchorZ, set = set })
    stats.placed = stats.placed + 1
end

-- The prints of one step ending at x, y, z, the animal facing fx, fy; side 0 / 1: left / right.
local function placeStep(info, x, y, z, fx, fy, side, running, step)
    local lat = (side == 0 and -1 or 1) * info.side
    -- right of forward in world coords (y points south)
    local rx, ry = -fy, fx
    local kind = info.kind
    if info.gait == "bound" then
        -- the hind feet side by side ahead, the fore feet behind them in a line
        placePrint(kind, x + fx * BOUND_HIND - rx * info.side, y + fy * BOUND_HIND - ry * info.side, z, fx, fy)
        placePrint(kind, x + fx * BOUND_HIND + rx * info.side, y + fy * BOUND_HIND + ry * info.side, z, fx, fy)
        for i = 1, #BOUND_FORE do
            local b, l = BOUND_FORE[i], (i == 1 and lat or -lat) * 0.2
            placePrint(kind, x + fx * b + rx * l, y + fy * b + ry * l, z, fx, fy)
        end
        return
    end
    placePrint(kind, x + rx * lat, y + ry * lat, z, fx, fy)
    if running then
        local b = step * RUN_PAIR
        placePrint(kind, x - fx * b - rx * lat, y - fy * b - ry * lat, z, fx, fy)
    end
end

-- Follows animal a at x, y: every step finished since its last look leaves its prints where that
-- step ended on the way here (as track() in ISnow_Footprints.lua).
local function track(a, x, y)
    local st = walkers[a]
    local now = nowMs
    if not st then
        walkers[a] = { x = x, y = y, dist = 0, side = ZombRand(2), seen = now, speed = 0 }
        return
    end
    local dtMs = now - st.seen
    st.seen = now
    local dx, dy = x - st.x, y - st.y
    if dx == 0 and dy == 0 then
        st.speed = st.speed * (1 - SPEED_SMOOTH)
        return
    end
    local d = math.sqrt(dx * dx + dy * dy)
    st.x, st.y = x, y
    if d > TELEPORT_DIST then
        st.dist = 0
        return
    end
    if dtMs > 0 then st.speed = st.speed + (d * 1000 / dtMs - st.speed) * SPEED_SMOOTH end
    local info = infoOf(a)
    if not info then return end
    st.dist = st.dist + d
    -- running: longer steps, and (but bounding) a pair of prints per step
    local fast = st.speed > info.run
    local running = fast and info.gait ~= "bound"
    local step = info.step * (fast and RUN_STRIDE or 1)
    if st.dist < step then return end
    local n = math.min(MAX_STEPS, math.floor(st.dist / step))
    st.dist = st.dist - n * step
    if st.dist >= step then st.dist = 0 end
    -- in a vehicle or trailer, or hidden (a fence hop in Companion Dogs MP): no prints
    if a:getVehicle() or a:isInvisible() then return end
    -- out of sight: no prints (see the top), the feet keep alternating
    if not isSeen(a) then
        stats.unseen = stats.unseen + n
        st.side = (st.side + n) % 2
        return
    end

    local ux, uy = dx / d, dy / d
    -- the hooves point where the body faces (backing up, turning on the spot); fall back to movement
    local fx, fy = a:getForwardDirectionX(), a:getForwardDirectionY()
    if fx == 0 and fy == 0 then fx, fy = ux, uy end
    local z = a:getZ()
    for k = n - 1, 0, -1 do
        local back = math.min(d, st.dist + k * step)
        local ok = pcall(placeStep, info, x - ux * back, y - uy * back, z, fx, fy, st.side, running, step)
        if not ok then stats.errors = stats.errors + 1 end
        st.side = 1 - st.side
    end
end

-- The animals of the cell near player 0, nearest first, at most MAX_TRACKED.
local function listAnimals(px, py)
    local cell = getCell()
    local list = cell and cell:getAnimals()
    tracked = {}
    if not list then return end
    local r = ISnow.opt("AnimalTrackRadius") + LIST_MARGIN
    local r2 = r * r
    local near = {}
    for i = 0, list:size() - 1 do
        local a = list:get(i)
        if a and not a:isDead() and not a:isOnHook() and not a:getHutch() then
            local dx, dy = a:getX() - px, a:getY() - py
            local d2 = dx * dx + dy * dy
            if d2 <= r2 then near[#near + 1] = { a = a, d2 = d2 } end
        end
    end
    if #near > MAX_TRACKED then table.sort(near, function(p, q) return p.d2 < q.d2 end) end
    for i = 1, math.min(#near, MAX_TRACKED) do tracked[i] = near[i].a end
    stats.listed = list:size()
end

local function sweep()
    local p = getSpecificPlayer(0)
    if not p then return end
    local px, py = p:getX(), p:getY()
    if not listedAt or nowMs - listedAt >= LIST_MS or nowMs < listedAt then
        listedAt = nowMs
        listAnimals(px, py)
    end
    local r = ISnow.opt("AnimalTrackRadius")
    local r2 = r * r
    local followed = 0
    for i = 1, #tracked do
        local a = tracked[i]
        local x, y = a:getX(), a:getY()
        local dx, dy = x - px, y - py
        if dx * dx + dy * dy <= r2 then
            track(a, x, y)
            followed = followed + 1
        end
    end
    stats.followed = followed
end

local tickCounter = 0
local function onTick()
    if not on then return end
    tickCounter = tickCounter + 1
    if tickCounter % ANIMAL_TICKS ~= 0 then return end
    nowMs = getTimestampMs()
    local ok = pcall(sweep)
    if not ok then stats.errors = stats.errors + 1 end
end

local function onRender(playerIndex)
    if not ready then return end
    local ok = pcall(prints.render, prints, playerIndex, RENDER_RADIUS)
    if not ok then stats.errors = stats.errors + 1 end
end

local function refreshState()
    snowActive = ISnow.Decals.snowActive()
    local enabled = ISnow.opt("AnimalTracks") == true
    -- melted away, or turned off (Options > Mods hides them at once, not as they age)
    if not snowActive or not enabled then prints:clear() end
    on = snowActive and enabled
    if not on then
        tracked, listedAt = {}, nil
        walkers = {}
    end
end

local function onEveryOneMinute()
    refreshState()
    prints:age(ISnow.Decals.agePerMinute(ISnow.opt("AnimalTrackHours")))
    local now = getTimestampMs()
    for a, st in pairs(walkers) do
        if now - st.seen > STATE_TTL_MS then walkers[a] = nil end
    end
    -- Kahlua has no weak tables (ISnow.prune): the kinds of animals no longer walking here go too
    -- (one that grew up is looked up anew)
    ISnow.prune(infos, function(a) return walkers[a] ~= nil end)
end

local function onGameStart()
    nowMs = getTimestampMs()
    local ok, err = pcall(loadSprites)
    if not ok then
        stats.errors = stats.errors + 1
        print("[ImmersiveSnow] loading animal print textures failed: " .. tostring(err))
    end
    refreshState()
end

-- Debug console helpers ------------------------------------------------------

function AnimalTracks.stats()
    print(string.format("[ImmersiveSnow] animal tracks: on=%s prints=%d (fading %d) drawnLastFrame=%d placed=%d unseen=%d expired=%d pushedOut=%d animals in cell=%d tracked=%d followed=%d errors=%d max=%d radius=%d",
        tostring(on), prints:count(), prints:fading(), prints.drawn, stats.placed, stats.unseen, prints.expired, prints.evicted,
        stats.listed, #tracked, stats.followed, stats.errors, ISnow.opt("MaxAnimalTracks"), ISnow.opt("AnimalTrackRadius")))
end

-- What the animals near player 0 leave (type, group, kind).
function AnimalTracks.list()
    for i = 1, #tracked do
        local a = tracked[i]
        local info = infoOf(a)
        print(string.format("[ImmersiveSnow] %s group=%s kind=%s at %.1f,%.1f", tostring(a:getAnimalType()),
            tostring(groupOf(a:getAnimalType())), info and info.kind or "none", a:getX(), a:getY()))
    end
end

function AnimalTracks.clear()
    prints:clear()
end

-- Stamps a short trail of kind (default "hoof_l") in front of player 0 (tests rendering only).
function AnimalTracks.testTrail(kind)
    local p = getSpecificPlayer(0)
    local fx, fy = p:getForwardDirectionX(), p:getForwardDirectionY()
    local x, y, z = p:getX(), p:getY(), p:getZ()
    local info = { kind = kind or "hoof_l", side = 0.08 }
    for s = 1, 10 do
        placeStep(info, x + fx * s * 0.5, y + fy * s * 0.5, z, fx, fy, s % 2, false, 0.5)
    end
    AnimalTracks.stats()
end

Events.OnGameStart.Add(onGameStart)
Events.EveryOneMinute.Add(onEveryOneMinute)
ISnow.listen("OnTick", "AnimalTracks", onTick)
ISnow.listen("RenderOpaqueObjectsInWorld", "AnimalTracks", onRender)
