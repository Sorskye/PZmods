-- Immersive Snow: shaking the snow off one's own clothes (ISnow_CharSnow.lua).
--
-- Right-clicking anywhere while the player's clothes carry snow offers "Shake the snow off": the
-- player brushes it off the torso, the left and the right arm, the left and the right leg in turn
-- (PARTS: the vanilla wipe emotes, Bob_EmoteWipe*, as action anims of our own in
-- media/AnimSets/player/actions/ISnowShake*.xml; the vanilla ones are idle "ext" anims, which a timed
-- action does not play), the snow thins as it goes and falls off as clumps and powder from the part
-- being brushed (ISnow_BlowOff.lua); at the end the clothes and the items in hand and on the body are
-- clean. Less snow: fewer parts (at least MIN_PARTS), so less time. Snow shaken off does not melt into the clothes (CharSnow.shakeOff), so shaking it off before
-- going indoors keeps them drier (ISnow_SnowWetness.lua).
--
-- Client side only, like the brush (ISnow_SnowBrush.lua): the level is worked out by the player's
-- own client, and in MP the others get the new look through the usual report. The particles are
-- drawn on this client only.

require "ImmersiveSnow/ISnow_Config"
require "TimedActions/ISBaseTimedAction"

local MENU_MIN = 0.05       -- snow below this: no menu entry (MIN_LEVEL in ISnow_CharSnow.lua)
-- one part of the body per clip; the parts change with the action's progress (as ISLureAnimal
-- changes its anim in update), so they keep their order at any game speed
local PARTS = {
    { anim = "ISnowShakeTorso", height = { 0.3, 0.55 } },
    { anim = "ISnowShakeArmL", height = { 0.25, 0.5 } },
    { anim = "ISnowShakeArmR", height = { 0.25, 0.5 } },
    { anim = "ISnowShakeLegL", height = { 0.05, 0.3 } },
    { anim = "ISnowShakeLegR", height = { 0.05, 0.3 } },
}
local MIN_PARTS = 2         -- even a little snow: the torso and an arm
-- action time per part: a clip is about 2.7 s, played at 1.5x (m_SpeedScale in the XML; 2x looked
-- too fast), 1.8 s at ~48 units a second; a full layer (all five parts) about 9 s, as brushing a car
-- with a brush (ISnow_SnowBrush.lua), 0.6 (three) about 5 s
local PART_TIME = 86
-- clumps and powder puffs falling off for a full layer, times BlowOffAmount
local FALL_CHUNKS = 14
local FALL_PUFFS = 40
local MAX_PER_UPDATE = 4    -- particles one update emits at most (the rest carry over)
-- where they come off: BODY_RADIUS tiles around the player, at the height of the part being
-- brushed (floor levels above the feet), flung outwards at OUT_SPEED tiles a second
local BODY_RADIUS = { 0.12, 0.25 }
local OUT_SPEED = { 0.2, 0.7 }

ISnowShakeSnow = ISBaseTimedAction:derive("ISnowShakeSnow")

local function levelOf(p)
    local cs = ISnow.CharSnow
    return cs and cs.levelOf and cs.levelOf(p) or 0
end

function ISnowShakeSnow:isValid()
    local p = self.character
    return not p:isDead() and not p:getVehicle()
end

-- Snow amount shaken off just now (a level): clumps and powder falling off around the body, at
-- most MAX_PER_UPDATE now unless all (the end of the action).
function ISnowShakeSnow:fall(amount, all)
    local blow = ISnow.BlowOff
    if not (blow and blow.kick) then return end
    local k = amount * ISnow.opt("BlowOffAmount")
    self.chunks = self.chunks + FALL_CHUNKS * k
    self.puffs = self.puffs + FALL_PUFFS * k
    local p = self.character
    local x, y, z = p:getX(), p:getY(), p:getZ()
    local height = PARTS[self.part or 1].height
    local limit = all and math.ceil(self.chunks + self.puffs) or MAX_PER_UPDATE
    for _ = 1, limit do
        local chunk = self.chunks >= 1 and (self.puffs < 1 or ZombRand(3) == 0)
        if chunk then
            self.chunks = self.chunks - 1
        elseif self.puffs >= 1 then
            self.puffs = self.puffs - 1
        else
            break
        end
        local a = ZombRandFloat(0, 2 * math.pi)
        local ca, sa = math.cos(a), math.sin(a)
        local r, out = ZombRandFloat(BODY_RADIUS[1], BODY_RADIUS[2]), ZombRandFloat(OUT_SPEED[1], OUT_SPEED[2])
        blow.kick(x + ca * r, y + sa * r, z + ZombRandFloat(height[1], height[2]), ca * out, sa * out, chunk)
    end
end

-- The part of the body being brushed now: one of the first self.parts, in turn.
function ISnowShakeSnow:showPart()
    local part = math.min(self.parts, math.floor(self:getJobDelta() * self.parts) + 1)
    if part ~= self.part then
        self.part = part
        self:setActionAnim(PARTS[part].anim)
    end
end

function ISnowShakeSnow:update()
    self.character:setMetabolicTarget(Metabolics.LightWork)
    self:showPart()
    local level = self.startLevel * (1 - self:getJobDelta())
    local now = levelOf(self.character)
    if level < now then
        self:fall(now - level)
        local ok, err = pcall(ISnow.CharSnow.shakeOff, self.character, level)
        if not ok then print("[ImmersiveSnow] shake off failed: " .. tostring(err)) end
    end
end

function ISnowShakeSnow:start()
    self.part = nil
    self:showPart()
    self:setOverrideHandModels(nil, nil)
end

function ISnowShakeSnow:stop()
    ISBaseTimedAction.stop(self)
end

function ISnowShakeSnow:perform()
    self:fall(levelOf(self.character), true)
    pcall(ISnow.CharSnow.shakeOff, self.character, 0)
    ISBaseTimedAction.perform(self)
end

-- Parts of the body to brush for snow level: all at a full layer, fewer for less.
local function partsFor(level)
    return math.max(MIN_PARTS, math.min(#PARTS, math.ceil(level * #PARTS)))
end

function ISnowShakeSnow:getDuration()
    return self.parts * PART_TIME
end

function ISnowShakeSnow:new(character)
    local o = ISBaseTimedAction.new(self, character)
    o.startLevel = levelOf(character)
    o.parts = partsFor(o.startLevel)
    o.chunks, o.puffs = 0, 0
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

local function shake(p)
    ISTimedActionQueue.add(ISnowShakeSnow:new(p))
end

local function addMenu(playerNum, context)
    local p = getSpecificPlayer(playerNum)
    -- no snow builds up with Snow on characters off in the sandbox (ISnow_CharSnow.lua, updateLevel)
    if not p or p:isDead() or p:getVehicle() then return end
    if levelOf(p) < MENU_MIN then return end
    context:addOption(getText("UI_ImmersiveSnow_ShakeSnow"), p, shake)
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, _, test)
    if test then return end
    local ok, err = pcall(addMenu, playerNum, context)
    if not ok then print("[ImmersiveSnow] shake menu failed: " .. tostring(err)) end
end)
