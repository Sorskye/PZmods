-- Immersive Snow: snow wets the clothes of players.
--
-- Vanilla wets clothes only in rain: BodyDamage.UpdateWetness passes ClimateManager.getRainIntensity
-- to ClothingWetness.updateWetness, and isRaining() is false while the precipitation is snow
-- (bytecode 42). The wet clothes then do the rest in vanilla: they get heavier, keep less warm
-- (Thermoregulator), soak the skin (Wet moodle) and dry again (ClothingWetness, drying arg).
--
-- Water per game hour, in vanilla wetness points (0..100 on a clothing item; heavy rain brings
-- about RAIN_REF, measured: ZomboidGlobals.WetnessIncrease * GameTime multiplier per game hour):
--  * snowfall outdoors, snowIntensity * RAIN_REF * CONTACT, less the colder it is: dry powder
--    falls off, wet snow at 0 C melts on the cloth (wetFactor);
--  * the snow that melts on the clothes (ISnow_CharSnow.lua: warmth, body heat, rain),
--    MELT_WATER for a full layer;
--  * walking through ground snow, on the shoes and shins (FEET_WALK, twice when running).
-- Falling snow and its melt water go where snow lands on a standing body (FALL weights); an
-- umbrella keeps the falling snow off like vanilla keeps the rain (BodyPartType.GetUmbrellaMod).
--
-- The water goes into the layers like vanilla rain (ClothingWetness.updateWetness, rain branch),
-- per body part, from the outermost worn item in: items with a hole there and soaked ones (100)
-- let it through at half rate; the first other one takes delta * (1 - WaterResistance) / the number
-- of parts it covers; a fully waterproof one stops it. A bare part gets it on the skin, and a part
-- whose innermost item is at 50 or more gets half of it on the skin as well.
--
-- In MP the wetness lives on the server (bytecode 42): BodyDamage.Update returns at once on a client
-- for a live player, so the drying, the skin soaking, the Wet moodle and the warmth are all worked
-- out on the server; the clothes' wetness goes server -> client only (ClothingWetnessSync, every 3 s
-- when it changed; a client's SyncItemFields does not carry it back), the skin's as the Wetness
-- stat (PlayerStatsPacket, every 1 s; BodyDamage.UpdateWetness folds the body parts into it). So
-- the water goes into the clothes on the server: the client works out the water (W.water: only it
-- knows the snow that melted on its player, ISnow_CharSnow.lua), adds it up and sends it every
-- SEND_MS ("wet": f = falling snow off the umbrella, u = under it, m = melt, t = feet, all before
-- SnowWetnessRate), and at once when its player dies or quits (W.flush, W.flushAll,
-- ISnow_SnowWetnessClient.lua); the server (ISnow_SnowWetnessServer.lua) puts it into the sender's
-- own clothes with its sandbox's options. Water put in on a client would stay there, shown in the
-- tooltip and nowhere else (the sandbox option SnowWetnessMP that did that is gone in 0.5.2 Patch 1;
-- an old save's value is skipped by SandboxOptions.load).
--
-- Console: ISnow.SnowWetness.stats() shows the clothes' wetness and the last water per source.

require "ImmersiveSnow/ISnow_Config"

ISnow = ISnow or {}
local W = {}
ISnow.SnowWetness = W

local RAIN_REF = 160     -- wetness points per game hour of heavy vanilla rain
local CONTACT = 0.3      -- falling snow at 0 C wets as this part of rain of the same intensity
local MELT_WATER = 60    -- points a full melted snow layer brings to where it lay
local FEET_WALK = 25     -- points per game hour on the feet walking through ground snow at 0 C
local RUN_FEET = 2       -- running / sprinting splashes this many times more
local DRY_COLD = 10      -- degrees below 0 C at which snow stays dry (wetFactor down to MIN_WET)
local MIN_WET = 0.1      -- body heat still melts some

-- Where falling snow lands on a standing character (and melts from), by BloodBodyPartType name.
local FALL_WEIGHTS = {
    Head = 1, Neck = 0.6, Torso_Upper = 1, Torso_Lower = 0.5, Groin = 0.4,
    UpperArm_L = 0.9, UpperArm_R = 0.9, ForeArm_L = 0.6, ForeArm_R = 0.6, Hand_L = 0.5, Hand_R = 0.5,
    UpperLeg_L = 0.6, UpperLeg_R = 0.6, LowerLeg_L = 0.5, LowerLeg_R = 0.5, Foot_L = 0.3, Foot_R = 0.3,
}
local FEET_WEIGHTS = { Foot_L = 1, Foot_R = 1, LowerLeg_L = 0.3, LowerLeg_R = 0.3 }

local parts = nil        -- { { index, blood = BloodBodyPartType, body = BodyPartType, fall, feet, umbrella } }
local last = {}   -- [player] = water of the last update per source

local function initParts()
    parts = {}
    for i = 0, BloodBodyPartType.MAX:index() - 1 do
        local blood = BloodBodyPartType.FromIndex(i)
        local body = BodyPartType.FromIndex(i)
        -- Back has no body part (FromIndex gives MAX): vanilla skips it too
        if body ~= BodyPartType.MAX then
            local name = tostring(blood)
            table.insert(parts, { index = i, blood = blood, body = body, fall = FALL_WEIGHTS[name] or 0,
                feet = FEET_WEIGHTS[name] or 0, umbrella = BodyPartType.GetUmbrellaMod(body) })
        end
    end
end

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

-- 1 at 0 C and above, falling to MIN_WET at -DRY_COLD.
local function wetFactor(temp)
    return clamp(1 + temp / DRY_COLD, MIN_WET, 1)
end

-- Worn clothes over each body part, outermost first: { [part index] = { { item, count } } }.
-- WornItems keeps the body location order, inner to outer (the order vanilla takes them in).
local function layers(chr)
    local out = {}
    local worn = chr:getWornItems()
    for i = worn:size() - 1, 0, -1 do
        local item = worn:get(i):getItem()
        local bct = instanceof(item, "Clothing") and item:getBloodClothingType()
        if bct then
            local covered = BloodClothingType.getCoveredParts(bct)
            local n = covered:size()
            for j = 0, n - 1 do
                local k = covered:get(j):index()
                out[k] = out[k] or {}
                table.insert(out[k], { item = item, count = n })
            end
        end
    end
    return out
end

local function addSkin(bp, water)
    bp:setWetness(math.min(100, bp:getWetness() + water))
end

-- Puts water points into the clothes over one body part (see the top).
local function wetPart(bodyDamage, part, list, water)
    local bp = bodyDamage:getBodyPart(part.body)
    if not bp then return end
    if not list then
        addSkin(bp, water)
        return
    end
    local through = false
    for _, layer in ipairs(list) do
        local item = layer.item
        local vis = item:getVisual()
        if (vis and vis:getHole(part.blood) > 0) or item:getWetness() >= 100 then
            through = true
        else
            local pass = 1
            if item:getWaterResistance() > 0 then pass = math.max(0, 1 - item:getWaterResistance()) end
            if pass > 0 then
                local add = water * pass / layer.count
                if through then add = add / 2 end
                item:setWetness(item:getWetness() + add)
            end
            break
        end
    end
    if list[#list].item:getWetness() >= 50 then addSkin(bp, water / 2) end
end

local function holdsUmbrella(chr)
    local a, b = chr:getPrimaryHandItem(), chr:getSecondaryHandItem()
    return (a and a:isProtectFromRainWhileEquipped()) or (b and b:isProtectFromRainWhileEquipped()) or false
end

-- Water from each source on chr over dt game hours (melted: part of a full snow layer that melted
-- on chr meanwhile), before SnowWetnessRate: falling snow, melt, feet, and whether an umbrella
-- keeps the falling snow off.
function W.water(chr, dt, melted)
    local clim = getClimateManager()
    local temp = clim:getAirTemperatureForCharacter(chr)
    local outside = ISnow.snowFallsOnCharacter(chr)
    local fall, feet = 0, 0
    if outside and clim:isSnowing() then
        fall = clim:getSnowIntensity() * RAIN_REF * CONTACT * wetFactor(temp) * dt
    end
    -- a rider's feet are off the ground (ISnow.isRiding, ISnow_AnimalTracks.lua, client only); a
    -- square cleared with a shovel is bare (ISnow_Cleared.lua)
    local sx, sy, sz = math.floor(chr:getX()), math.floor(chr:getY()), math.floor(chr:getZ())
    if outside and not chr:getVehicle() and chr:isPlayerMoving() and not chr:isOnFloor() and not (ISnow.isRiding and ISnow.isRiding(chr))
            and not (sz == 0 and ISnow.Cleared and ISnow.Cleared.has(sx, sy))
            and getCell():gridSquareIsSnow(sx, sy, sz) then
        feet = FEET_WALK * wetFactor(temp) * dt
        if chr:isRunning() or chr:isSprinting() then feet = feet * RUN_FEET end
    end
    return fall, melted * MELT_WATER, feet, fall > 0 and holdsUmbrella(chr), temp
end

-- Puts water into the clothes of chr (see the top): fall = falling snow off the umbrella,
-- under = under it (BodyPartType.GetUmbrellaMod of it lands), melt, feet; all times rate.
function W.apply(chr, fall, under, melt, feet, rate)
    if (fall + under + melt + feet) * rate <= 0 then return end
    if not parts then initParts() end
    local lists = layers(chr)
    local bodyDamage = chr:getBodyDamage()
    for _, part in ipairs(parts) do
        local f = fall + under * part.umbrella
        local water = ((f + melt) * part.fall + feet * part.feet) * rate
        if water > 0 then wetPart(bodyDamage, part, lists[part.index], water) end
    end
end

-- MP client: water not sent yet, per local player { f, u, m, t, at = getTimestampMs() of the last send }.
local SEND_MS = 5000
local MP_MODULE = "ISnow"
local pending = {}
local mpStats = { sent = 0 }

-- The server takes 0..WET_MAX of each source per message (sane). More water than that waiting (the
-- time running fast: a full melted layer is 60, an hour of heavy wet snow 48) goes in several
-- messages; at most SPLIT_MAX of them, so a runaway amount (a clock jump) does not flood the server.
local WET_MAX = 100
local SPLIT_MAX = 10

local function sendPending(chr, p, now)
    p.at = now
    if p.f + p.u + p.m + p.t <= 0 then return end
    local n = math.ceil(math.max(p.f, p.u, p.m, p.t) / WET_MAX)
    if not (n >= 1) then n = 1 end
    n = math.min(n, SPLIT_MAX)
    local args = { f = math.min(WET_MAX, p.f / n), u = math.min(WET_MAX, p.u / n),
        m = math.min(WET_MAX, p.m / n), t = math.min(WET_MAX, p.t / n) }
    p.f, p.u, p.m, p.t = 0, 0, 0, 0
    for _ = 1, n do
        mpStats.sent = mpStats.sent + 1
        sendClientCommand(chr, MP_MODULE, "wet", args)
    end
end

-- MP client: sends the water waiting for chr now, not with the next update after SEND_MS. Called
-- when the player dies (OnPlayerDeath, below) or quits (ISnow_SnowWetnessClient.lua): the update
-- that would send it never comes.
function W.flush(chr)
    local p = pending[chr]
    if p and isClient() then sendPending(chr, p, getTimestampMs()) end
end

-- W.flush for every local player with water waiting.
function W.flushAll()
    for chr in pairs(pending) do
        local ok, err = pcall(W.flush, chr)
        if not ok then print("[ImmersiveSnow] wetness flush failed: " .. tostring(err)) end
    end
end

-- Called by ISnow_CharSnow.lua for every player poll: dt game hours passed, melted = part of a
-- full snow layer that melted on chr meanwhile.
function W.update(chr, dt, melted)
    if not ISnow.opt("SnowWetness") or not instanceof(chr, "IsoPlayer") then return end
    local fall, melt, feet, umbrella, temp = W.water(chr, dt, melted)
    local rate = ISnow.opt("SnowWetnessRate")
    if not last[chr] then
        -- a player new here (a respawn): the ones gone are dropped (Kahlua has no weak tables,
        -- ISnow.prune), their water not sent yet with them
        local live = ISnow.liveCharacters()
        local function keep(p) return live[p] end
        ISnow.prune(last, keep)
        ISnow.prune(pending, keep)
    end
    last[chr] = { fall = fall * rate, melt = melt * rate, feet = feet * rate, dt = dt, temp = temp }
    local under = umbrella and fall or 0
    if umbrella then fall = 0 end
    if not isClient() then
        W.apply(chr, fall, under, melt, feet, rate)
        return
    end
    local now = getTimestampMs()
    local p = pending[chr]
    if not p then
        p = { f = 0, u = 0, m = 0, t = 0, at = now }
        pending[chr] = p
    end
    p.f, p.u, p.m, p.t = p.f + fall, p.u + under, p.m + melt, p.t + feet
    if now - p.at >= SEND_MS then sendPending(chr, p, now) end
end

-- Server: water a client sent for its own player (the sender, never another one), at the server's
-- sandbox options. Wetting only oneself, so the values are only kept sane: 0..WET_MAX each.
local function sane(v)
    v = tonumber(v)
    if not v or v ~= v then return 0 end
    return math.max(0, math.min(WET_MAX, v))
end

function W.onClientWet(chr, args)
    if not ISnow.worldOpt("SnowWetness") or type(args) ~= "table" then return false end
    W.apply(chr, sane(args.f), sane(args.u), sane(args.m), sane(args.t), ISnow.worldOpt("SnowWetnessRate"))
    return true
end

-- Debug console --------------------------------------------------------------

function W.stats(chr)
    chr = chr or getPlayer()
    local out = {}
    local l = last[chr]
    if l then
        table.insert(out, string.format("last update: dt=%.4fh temp=%.1f water fall=%.3f melt=%.3f feet=%.3f (per hour %.1f / %.1f / %.1f)",
            l.dt, l.temp, l.fall, l.melt, l.feet, l.fall / l.dt, l.melt / l.dt, l.feet / l.dt))
    else
        table.insert(out, "no update yet")
    end
    local worn = chr:getWornItems()
    for i = worn:size() - 1, 0, -1 do
        local item = worn:get(i):getItem()
        if instanceof(item, "Clothing") then
            table.insert(out, string.format("  %s wet=%.1f waterRes=%.2f", item:getType(), item:getWetness(),
                item:getWaterResistance()))
        end
    end
    local bd = chr:getBodyDamage()
    local skin = {}
    for i = 0, BodyPartType.MAX:index() - 1 do
        local bp = bd:getBodyPart(BodyPartType.FromIndex(i))
        if bp and bp:getWetness() > 0 then table.insert(skin, string.format("%s=%.0f", tostring(bp:getType()), bp:getWetness())) end
    end
    table.insert(out, "skin: " .. (#skin > 0 and table.concat(skin, " ") or "dry"))
    if isClient() then
        -- "skin" above is this client's copy of the body parts, never synced; the Wetness stat is
        local ok, wet = pcall(function() return chr:getStats():get(CharacterStat.WETNESS) end)
        local p = pending[chr]
        table.insert(out, string.format("MP: Wetness stat=%s, messages sent=%d, waiting fall=%.2f under=%.2f melt=%.2f feet=%.2f",
            ok and string.format("%.1f", wet) or "?", mpStats.sent, p and p.f or 0, p and p.u or 0, p and p.m or 0, p and p.t or 0))
    end
    return table.concat(out, "\n")
end

-- MP client: the water waiting for a player who dies is sent now, as on quitting.
Events.OnPlayerDeath.Add(function(chr)
    local ok, err = pcall(W.flush, chr)
    if not ok then print("[ImmersiveSnow] wetness flush failed: " .. tostring(err)) end
end)
