-- Immersive Snow: frost on the screen in hypothermia. It follows the vanilla Hypothermia moodle of
-- player 0: from level FrostScreenFromLevel (1) on, frost creeps in from the edges of the screen,
-- one stage further per moodle level, in full at level 4 (FrostScreen, FrostScreenOpacity), over
-- FrostScreenComeSeconds, and thaws over FrostScreenGoSeconds as the moodle goes. From level
-- FrostScreenShiverLevel (2) on it trembles (FrostScreenShiver), harder at each level.
--
-- Drawn like the breath and the blow-off particles (ISnow_BlowOff.lua: why OnPostRender, the screen
-- maths): every frame from OnPostRender into the player's world buffer, which goes on the screen
-- before the UI, so the frost is under the HUD and the moodles. One texture stretched over the view
-- per stage (tools/gen_frost.py): the same frost reaching further in, each stage covering all of
-- the one before, cross-faded from one to the next. A stage's texture loads when it is first
-- needed (most games never get past the first).
--
-- No camera shake: the camera offset is not reachable from Lua (IsoCamera keeps it in fields), so
-- the shiver is the frost itself trembling, in waves.
--
-- Split screen gets no frost (OnPostRender does not say which player's view it draws, as for the
-- breath).

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_Decals"

local Frost = {}
ISnow.Frost = Frost

local STAGES = 4             -- as gen_frost.py
local MAX_LEVEL = 4          -- moodle levels
-- Without the moodle (its type not found): the level from the body temperature, with the vanilla
-- thresholds of the Hypothermia moodle (below 36.5, 35, 30, 25 C: levels 1-4).
local LEVEL_TEMPS = { 36.5, 35, 30, 25 }
local SHIVER_PX = 4          -- trembling at its strongest, px at 1080 px high
local SHIVER_MARGIN = 6      -- px the frost overhangs the view on each side, so a tremble shows no edge
-- The shown frost follows the moodle exponentially: FrostScreenComeSeconds /
-- FrostScreenGoSeconds is about all the way (3 time constants, 95 %), coming / going.
local TAUS = 3
local SHIVER_TAU = 4
local LEVEL_TICKS = 30       -- ticks between asking for the moodle

local textures = {}          -- [name] = Texture, loaded on first need
local broken = false
local shown = 0              -- 0..1, the frost on the screen
local shiver = 0             -- 0..1
local level = 0              -- Hypothermia moodle level 0..4
local forcedLevel = nil      -- console tests: Frost.test(level)
local tick = 0
local lastMs = nil
local clock = 0              -- s of unpaused game, drives the tremble
local stats = { drawn = 0, errors = 0, source = "none" }
local lastError = nil

local function clamp01(x) return x < 0 and 0 or (x > 1 and 1 or x) end
local function sane(v) return type(v) == "number" and v > 15 and v < 45 end

-- The body temperature of player p in C, nil if none of the ways to ask works: the stats API
-- changed in B42 (CharacterStat), so each way in turn.
local function bodyTemp(p)
    local st = p:getStats()
    if st and CharacterStat and CharacterStat.TEMPERATURE and st.get then
        local ok, v = pcall(st.get, st, CharacterStat.TEMPERATURE)
        if ok and sane(v) then stats.source = "stats"; return v end
    end
    if p.getTemperature then
        local ok, v = pcall(p.getTemperature, p)
        if ok and sane(v) then stats.source = "character"; return v end
    end
    local bd = p.getBodyDamage and p:getBodyDamage()
    if bd and bd.getTemperature then
        local ok, v = pcall(bd.getTemperature, bd)
        if ok and sane(v) then stats.source = "body"; return v end
    end
    stats.source = "none"
    return nil
end

-- The moodle level for body temperature t (the fallback).
function Frost.levelOfTemp(t)
    local l = 0
    for i, below in ipairs(LEVEL_TEMPS) do
        if t < below then l = i end
    end
    return l
end

-- The Hypothermia moodle type: MoodleType.HYPOTHERMIA (B42) or MoodleType.Hypothermia (B41 name).
local function moodleType()
    if not MoodleType then return nil end
    local ok, t = pcall(function() return MoodleType.HYPOTHERMIA end)
    if ok and t then return t end
    ok, t = pcall(function() return MoodleType.Hypothermia end)
    if ok and t then return t end
    return nil
end

-- The Hypothermia moodle level 0..4 of player p: the moodle, else from the body temperature.
local function hypothermia(p)
    local m = p.getMoodles and p:getMoodles()
    local mt = moodleType()
    if m and mt then
        local ok, v = pcall(m.getMoodleLevel, m, mt)
        if ok and type(v) == "number" then
            stats.source = "moodle"
            return math.max(0, math.min(MAX_LEVEL, v))
        end
    end
    local t = bodyTemp(p)
    return t and Frost.levelOfTemp(t) or 0
end

-- 0..1 from moodle level l with the effect starting at level from: a step per level, full at 4.
local function fromLevel(l, from)
    from = math.max(1, math.min(MAX_LEVEL, math.floor(from + 0.5)))
    if l < from then return 0 end
    return clamp01((l - from + 1) / (MAX_LEVEL - from + 1))
end

-- 0..1: how far in the frost reaches at moodle level l.
function Frost.strength(l)
    return fromLevel(l or 0, ISnow.opt("FrostScreenFromLevel"))
end

-- 0..1: how hard the frost trembles at moodle level l.
function Frost.shiverStrength(l)
    return fromLevel(l or 0, ISnow.opt("FrostScreenShiverLevel"))
end

-- The stages to draw for frost v (0..1): { stage, alpha } pairs, lower stage first.
function Frost.layers(v)
    local s = clamp01(v) * STAGES
    if s <= 0 then return {} end
    if s <= 1 then return { { 0, s } } end
    -- past the first: from stage i to i + 1
    local i = math.floor(s - 1)
    local f = s - 1 - i
    if i >= STAGES - 1 then return { { STAGES - 1, 1 } } end
    if f <= 0 then return { { i, 1 } } end
    return { { i, 1 - f }, { i + 1, f } }
end

-- Screen offset (px) of the tremble at time t for shiver strength k at screen height h: fast
-- shaking (about 7-11 Hz) that comes in waves.
function Frost.tremble(t, k, h)
    if k <= 0 then return 0, 0 end
    local wave = clamp01(0.45 + 0.7 * math.sin(t * 0.9) + 0.3 * math.sin(t * 2.3 + 1))
    local a = SHIVER_PX * h / 1080 * k * wave
    return a * (math.sin(t * 47) + 0.6 * math.sin(t * 71.3)) / 1.6, a * 0.6 * math.sin(t * 53.1 + 1)
end

local function texture(name)
    local t = textures[name]
    if t == nil then
        t = getTexture(ISnow.TEXTURE_DIR .. name .. ".png")
        if not t then error("missing texture " .. name .. ".png") end
        textures[name] = t
    end
    return t
end

local function update(dt)
    tick = tick + 1
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then
        level = 0
    elseif forcedLevel then
        level = forcedLevel
    elseif tick % LEVEL_TICKS == 1 then
        level = hypothermia(p)
    end
    -- no hypothermia and nothing shown (most of the year): nothing to ease in or out
    if level <= 0 and shown == 0 and shiver == 0 then return end
    if not ISnow.opt("FrostScreen") then
        shown, shiver = 0, 0
        return
    end
    local target = Frost.strength(level)
    local tau = ISnow.opt(target > shown and "FrostScreenComeSeconds" or "FrostScreenGoSeconds") / TAUS
    shown = shown + (target - shown) * math.min(1, dt / tau)
    if shown < 0.002 and target == 0 then shown = 0 end
    if ISnow.opt("FrostScreenShiver") then
        shiver = shiver + (Frost.shiverStrength(level) - shiver) * math.min(1, dt / SHIVER_TAU)
    else
        shiver = 0   -- turned off: still at once
    end
    clock = clock + dt
end

local function onTick()
    local now = getTimestampMs()
    local dt = lastMs and (now - lastMs) / 1000 or 0
    lastMs = now
    if broken or isGamePaused() then return end
    local ok, err = pcall(update, math.min(dt, 0.1))
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
        shown, shiver = 0, 0
    end
end

local function render()
    stats.drawn = 0
    if broken or shown <= 0 then return end
    if getNumActivePlayers() > 1 then return end
    local pi = 0
    local player = getSpecificPlayer(pi)
    if not player then return end
    local zoom = getCore():getZoom(pi)
    local w, h = getPlayerScreenWidth(pi), getPlayerScreenHeight(pi)
    local dx, dy = Frost.tremble(clock, shiver, h)
    local m = SHIVER_MARGIN * h / 1080
    local opacity = ISnow.opt("FrostScreenOpacity")
    local r = getRenderer()
    ISnow.Decals.resetBlend(player)
    for _, l in ipairs(Frost.layers(shown)) do
        local a = l[2] * opacity
        if a > 0.005 then
            r:render(texture("frost_" .. l[1]), (dx - m) * zoom, (dy - m) * zoom, (w + 2 * m) * zoom, (h + 2 * m) * zoom, 1, 1, 1, a, nil)
            stats.drawn = stats.drawn + 1
        end
    end
end

local function onRenderSafe()
    local ok, err = pcall(render)
    if not ok then
        stats.errors = stats.errors + 1
        lastError = tostring(err)
        broken = true
        print("[ImmersiveSnow] frost on the screen disabled: " .. lastError)
    end
end

function Frost.stats()
    print(string.format("[ImmersiveSnow] frost: on=%s hypothermia=%d (from %s) shown=%.2f shiver=%.2f drawn=%d broken=%s errors=%d",
        tostring(ISnow.opt("FrostScreen")), level, forcedLevel and "test" or stats.source, shown, shiver,
        stats.drawn, tostring(broken), stats.errors))
    if lastError then print("[ImmersiveSnow] last error: " .. lastError) end
end

-- Console test: as if the Hypothermia moodle were at level l, 0..4 (nil: the real one again).
function Frost.test(l)
    forcedLevel = l
    if l then level = l end
end

ISnow.listen("OnTick", "Frost", onTick)
ISnow.listen("OnPostRender", "Frost", onRenderSafe)
