-- Immersive Snow: drifting snow (позёмка). In a strong wind in the frost, low snow dust sweeps
-- along the ground snow with the wind, in gusts.
--
-- The wisps are the blow-off's powder (ISnow_BlowOff.lua, BlowOff.drift): drawn from OnPostRender
-- over everything, tinted by the light of their square. They start at random points of the part of
-- the viewer's level on screen (ISnow.Decals.viewBounds), on squares under the sky with ground snow
-- (Decals.isSnowSquare), so the effect costs nothing off screen and its rate follows the area shown,
-- not the radius around the player. Drifting snow and steam share part of the particle limit
-- (BlowOff.room): a blizzard does not leave the snow off vehicles and feet without particles.
--
-- Wind (ClimateManager, bytecode 42.21): getWindspeedKph is windPower * 120; getWindAngleRadians
-- is the angle the weather carries things along in world x, y as (sin a, cos a): WorldFlares.Flare
-- moves a flare by exactly that, and it matches the falling snow of IsoWeatherFX on screen (wind
-- angle intensity above 0: to the right, a of 45..225 deg; below: to the left).
--
-- Strength 0..1: from DriftingSnowWind km/h up to full FULL_SPAN km/h above it, only at or below
-- MAX_TEMP (wet snow does not drift), times DriftingSnowAmount and BlowOffAmount (35 % in the
-- low-end mode). Gusts: the rate swells and drops with two slow waves.
--
-- Client side only: every client draws its own; nothing saved or synced.

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_Decals"
require "ImmersiveSnow/ISnow_BlowOff"

local Drift = {}
ISnow.Drift = Drift

local FULL_SPAN = 30            -- km/h above DriftingSnowWind for full strength
local MAX_TEMP = 0              -- C, warmer: no drifting
local RATE_PER_TILE = 0.06      -- wisps a second per square of the screen at full strength ...
local RATE_MAX = 30             -- ... up to this many a second (the tooltip says up to ~30)
local SPEED_PART = 0.3          -- of the wind's speed the dust goes at near the ground ...
local SPEED_MAX = 6             -- ... tiles / s at most
local SPREAD = 0.25             -- rad either way off the wind
local SPEED_VARY = { 0.7, 1.25 }
local CLIMATE_MS = 1000         -- real ms between looks at the weather
local TRIES = 3                 -- random points tried for snow per wisp

local strength = 0              -- 0..1, from the last look at the weather
local windX, windY = 0, 0       -- tiles / s
local lastClimateMs = nil
local lastMs = nil
local acc = 0                   -- wisps owed
local clock = 0                 -- s, for the gusts
local stats = { emitted = 0, missed = 0, errors = 0 }
local lastError = nil

local function rand(r) return ZombRandFloat(r[1], r[2]) end

-- Strength of drifting snow for wind kph and temperature temp (C), 0..1, before the amount.
function Drift.strength(kph, temp)
    if temp > MAX_TEMP then return 0 end
    local from = ISnow.opt("DriftingSnowWind")
    return math.max(0, math.min(1, (kph - from) / FULL_SPAN))
end

local function lookAtWeather()
    strength, windX, windY = 0, 0, 0
    if not ISnow.opt("DriftingSnow") or not ISnow.Decals.snowActive() then return end
    local clim = getClimateManager()
    local kph = clim:getWindspeedKph()
    local s = Drift.strength(kph, clim:getTemperature())
    if s <= 0 then return end
    local a = clim:getWindAngleRadians()
    local speed = math.min(SPEED_MAX, kph / 3.6 * SPEED_PART)
    strength = s * ISnow.opt("DriftingSnowAmount") * ISnow.opt("BlowOffAmount")
    windX, windY = math.sin(a) * speed, math.cos(a) * speed
end

-- One wisp at a random snowy point of the screen, if one is found in TRIES.
local function emitOne(cell, cz, umin, umax, vmin, vmax)
    for _ = 1, TRIES do
        local u, v = ZombRandFloat(umin, umax), ZombRandFloat(vmin, vmax)
        local x, y = (u + v) / 2, (v - u) / 2
        if ISnow.Decals.isSnowSquare(cell, math.floor(x), math.floor(y), cz) then
            local turn = ZombRandFloat(-SPREAD, SPREAD)
            local c, s = math.cos(turn), math.sin(turn)
            local k = rand(SPEED_VARY)
            ISnow.BlowOff.drift(x, y, cz, (windX * c - windY * s) * k, (windX * s + windY * c) * k)
            stats.emitted = stats.emitted + 1
            return
        end
    end
    stats.missed = stats.missed + 1
end

local function update(now, dt)
    if not lastClimateMs or now - lastClimateMs >= CLIMATE_MS then
        lastClimateMs = now
        lookAtWeather()
    end
    if strength <= 0 then
        acc = 0
        return
    end
    -- split screen gets no particles (BlowOff draws for one player only)
    if getNumActivePlayers() > 1 then return end
    local player = getSpecificPlayer(0)
    if not player then return end
    local cz = math.floor(player:getZ())
    local umin, umax, vmin, vmax = ISnow.Decals.viewBounds(0, player:getX(), player:getY(), cz)
    if not umin then return end
    clock = clock + dt
    local gust = 0.7 + 0.3 * math.sin(clock * 0.9) * math.sin(clock * 0.37 + 1)   -- 0.4 .. 1
    local area = (umax - umin) * (vmax - vmin) / 2   -- squares: a unit of x - y by x + y is half a square
    local rate = math.min(RATE_MAX * strength, area * RATE_PER_TILE * strength) * gust
    acc = acc + rate * dt
    local room = ISnow.BlowOff.room()
    if acc > room then acc = room end
    if acc < 1 then return end
    local cell = getCell()
    while acc >= 1 do
        acc = acc - 1
        emitOne(cell, cz, umin, umax, vmin, vmax)
    end
end

local function onTick()
    local now = getTimestampMs()
    local dt = lastMs and (now - lastMs) / 1000 or 0
    lastMs = now
    if isGamePaused() or not (ISnow.BlowOff and ISnow.BlowOff.drift) then return end
    local ok, err = pcall(update, now, math.min(dt, 0.1))
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
    end
end

function Drift.stats()
    local clim = getClimateManager()
    print(string.format("[ImmersiveSnow] drifting snow: on=%s wind=%.1f km/h angle=%.0f deg temp=%.1f strength=%.2f wind=%.2f,%.2f tiles/s emitted=%d missed=%d errors=%d",
        tostring(ISnow.opt("DriftingSnow")), clim:getWindspeedKph(), math.deg(clim:getWindAngleRadians()), clim:getTemperature(),
        strength, windX, windY, stats.emitted, stats.missed, stats.errors))
    if lastError then print("[ImmersiveSnow] last error: " .. lastError) end
end

ISnow.listen("OnTick", "Drift", onTick)
