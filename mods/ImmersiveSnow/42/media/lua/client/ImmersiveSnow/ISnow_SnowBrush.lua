-- Immersive Snow: brushing the snow off a vehicle (ISnow_VehicleSnow.lua).
--
-- Right-clicking a vehicle with snow on it offers "Brush the snow off": the player walks to the front
-- of it (the engine area, as for the frost scrape), faces it and sweeps, by hand or, faster, with a
-- broom or a brush from the main inventory (BRUSHES: matched by item type, so modded ones count too;
-- the small ones in NOT_BRUSHES do not), which goes into the hands for it. The sweep is a vanilla
-- wall scrub: a broom (two-handed) in long strokes of both hands, a hand brush in short strokes of
-- one, bare hands wiping with the palm. The snow thins as the sweep goes on and falls off the
-- vehicle as clumps and powder (ISnow_BlowOff.lua), and from under the hands; the glass is wiped of
-- the icing at GLASS_AT of it (VehicleSnow.cleanGlass, the hoarfrost stays for the scrape); at the
-- end the snow and the icing (one level) are gone (VehicleSnow.brush: in MP for everyone). The time grows with the snow and the size of the vehicle. Nobody may be at the wheel:
-- the driver's reports would put the snow back for the others.
--
-- The action is client side only, like the frost scrape (ISnow_FrostScrape.lua): it has no
-- complete(), so B42 does not run it on the server.

require "ImmersiveSnow/ISnow_Config"
require "TimedActions/ISBaseTimedAction"

local MENU_MIN = 0.05        -- snow below this: no menu entry
local HAND_TIME = 1400       -- action time at full snow on a car of REF_AREA, by hand / with a broom or brush
local TOOL_TIME = 450
local MIN_PART = 0.35        -- of the full time even a light snow takes
local REF_AREA = 1.56 * 4.52 -- extents x * z of a pickup, as BLOWOFF_REF_AREA in ISnow_VehicleSnow.lua
local AREA_RANGE = { 0.5, 2.5 }
local REACH = 4.5            -- tiles from the vehicle's centre the sweeper may stand
-- clumps and powder puffs falling off for a full layer swept off a car of REF_AREA, times BlowOffAmount
local FALL_CHUNKS = 30
local FALL_PUFFS = 30
-- item types (lower case, substrings) that sweep, and the small brushes that do not
local BRUSHES = { "broom", "brush" }
local NOT_BRUSHES = { "toothbrush", "hairbrush", "paintbrush", "makeup" }
local GLASS_AT = 0.5         -- of the action: the icing goes off the glass
local ANIM_BROOM = "ScrubWall_Mop"   -- vanilla AnimSets/player/actions (Bob_IdleScrubWall_Broom)
local ANIM_BRUSH = "ScrubWall_ToiletBrush"
local ANIM_HAND = "ScrubWall"
-- snow falling from under the hands: one clump or puff every CRUMB_MS on average, HAND_REACH tiles
-- in front of the player at HAND_HEIGHT floor levels (a broom reaches farther)
local CRUMB_MS = 90
local HAND_REACH = 0.5
local BROOM_REACH = 0.9
local HAND_HEIGHT = 0.4

ISnowBrushSnow = ISBaseTimedAction:derive("ISnowBrushSnow")

local function matches(t, list)
    for _, s in ipairs(list) do
        if string.find(t, s, 1, true) then return true end
    end
    return false
end

-- Whether item is held in both hands (a broom: a two-handed weapon).
local function twoHanded(item)
    return item ~= nil and instanceof(item, "HandWeapon") and item:isTwoHandWeapon()
end

-- A broom or brush in player p's main inventory to sweep with, nil for bare hands.
local function findBrush(p)
    local items = p:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local t = string.lower(item:getType() or "")
        if matches(t, BRUSHES) and not matches(t, NOT_BRUSHES) then return item end
    end
    return nil
end

local function levelOf(v)
    local vs = ISnow.VehicleSnow
    if not (vs and vs.levelOf) then return 0, 0 end
    return vs.levelOf(v)
end

-- The vehicle's top area against a pickup's, kept in AREA_RANGE.
local function areaOf(v)
    local script = v:getScript()
    if not script then return 1 end
    local ext = script:getExtents()
    return math.max(AREA_RANGE[1], math.min(AREA_RANGE[2], ext:x() * ext:z() / REF_AREA))
end

function ISnowBrushSnow:isValid()
    local v = self.vehicle
    if not v or v:isRemovedFromWorld() or self.character:getVehicle() or v:getDriver() then return false end
    local dx, dy = v:getX() - self.character:getX(), v:getY() - self.character:getY()
    return dx * dx + dy * dy <= REACH * REACH
end

function ISnowBrushSnow:waitToStart()
    self.character:faceThisObject(self.vehicle)
    return self.character:shouldBeTurning()
end

-- Snow amount swept off just now (a level): clumps and powder falling off the vehicle.
function ISnowBrushSnow:fall(amount)
    local blow = ISnow.BlowOff
    if not (blow and blow.emit) then return end
    local k = amount * self.area * ISnow.opt("BlowOffAmount")
    self.chunks = self.chunks + FALL_CHUNKS * k
    self.puffs = self.puffs + FALL_PUFFS * k
    local chunks, puffs = math.floor(self.chunks), math.floor(self.puffs)
    if chunks + puffs == 0 then return end
    self.chunks, self.puffs = self.chunks - chunks, self.puffs - puffs
    blow.emit(self.vehicle, chunks, puffs, 0)
end

-- Snow falling from under the sweeping hands (or the broom's head), on this client.
function ISnowBrushSnow:crumbs()
    local blow = ISnow.BlowOff
    if not (blow and blow.kick) then return end
    local now = getTimestampMs()
    if now < self.nextCrumb then return end
    self.nextCrumb = now + ZombRandFloat(0.5, 1.5) * CRUMB_MS
    local c, v = self.character, self.vehicle
    local dx, dy = v:getX() - c:getX(), v:getY() - c:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.01 then return end
    dx, dy = dx / d, dy / d
    local reach = (twoHanded(self.tool) and BROOM_REACH or HAND_REACH) * ZombRandFloat(0.8, 1.1)
    local side = ZombRandFloat(-0.35, 0.35)
    local x, y = c:getX() + dx * reach - dy * side, c:getY() + dy * reach + dx * side
    -- swept sideways and off the edge
    local push = ZombRandFloat(-0.6, 0.6)
    local vx, vy = -dy * push - dx * 0.15, dx * push - dy * 0.15
    blow.kick(x, y, c:getZ() + HAND_HEIGHT * ZombRandFloat(0.8, 1.15), vx, vy, ZombRand(2) == 0)
end

function ISnowBrushSnow:update()
    self.character:faceThisObject(self.vehicle)
    self.character:setMetabolicTarget(Metabolics.LightWork)
    -- thinner as it goes, on this client (the end goes to everyone)
    local k = 1 - self:getJobDelta()
    local level = self.startLevel * k
    local now = levelOf(self.vehicle)
    if level < now then
        self:fall(now - level)
        ISnow.VehicleSnow.lower(self.vehicle, level, self.iceTo + (self.startIce - self.iceTo) * k)
    end
    if 1 - k >= GLASS_AT and not self.glassDone then
        self.glassDone = true
        ISnow.VehicleSnow.cleanGlass(self.vehicle)
    end
    if level > 0.01 then self:crumbs() end
end

function ISnowBrushSnow:start()
    if twoHanded(self.tool) then
        self:setActionAnim(ANIM_BROOM)
        self:setOverrideHandModels(self.tool, nil)
    elseif self.tool then
        self:setActionAnim(ANIM_BRUSH)
        self:setOverrideHandModels(self.tool, nil)
    else
        self:setActionAnim(ANIM_HAND)
        self:setOverrideHandModels(nil, nil)
    end
end

function ISnowBrushSnow:stop()
    -- stopped half-way: what is off already goes to the others too
    if levelOf(self.vehicle) < self.startLevel or self.glassDone then ISnow.VehicleSnow.report(self.vehicle) end
    ISBaseTimedAction.stop(self)
end

function ISnowBrushSnow:perform()
    self:fall(levelOf(self.vehicle))
    ISnow.VehicleSnow.brush(self.vehicle)
    ISBaseTimedAction.perform(self)
end

function ISnowBrushSnow:getDuration()
    local snow = math.max(MIN_PART, self.startLevel or 1)
    return math.floor((self.tool and TOOL_TIME or HAND_TIME) * snow * self.area)
end

function ISnowBrushSnow:new(character, vehicle, tool)
    local o = ISBaseTimedAction.new(self, character)
    o.vehicle = vehicle
    o.tool = tool
    o.startLevel, o.startIce = levelOf(vehicle)
    o.iceTo = math.min(o.startIce, ISnow.VehicleSnow.BRUSH_ICE)
    o.area = areaOf(vehicle)
    o.chunks, o.puffs = 0, 0
    o.nextCrumb = 0
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

-- Queues the sweep of vehicle v for player p: to the front of it first, the tool into the hands.
local function brush(p, v, tool)
    local area = v:getScript() and v:getScript():getAreaById("Engine")
    if area and ISPathFindAction and ISPathFindAction.pathToVehicleArea then
        ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(p, v, "Engine"))
    end
    if tool and ISWorldObjectContextMenu and ISWorldObjectContextMenu.equip then
        ISWorldObjectContextMenu.equip(p, p:getPrimaryHandItem(), tool, true, twoHanded(tool))
    end
    ISTimedActionQueue.add(ISnowBrushSnow:new(p, v, tool))
end

local function addMenu(playerNum, context, v)
    if not v or v:getDriver() or levelOf(v) < MENU_MIN then return end
    local p = getSpecificPlayer(playerNum)
    if not p or p:getVehicle() then return end
    local tool = findBrush(p)
    local label = tool and getText("UI_ImmersiveSnow_BrushSnowWith", tool:getDisplayName())
        or getText("UI_ImmersiveSnow_BrushSnowHand")
    context:addOption(label, p, brush, v, tool)
end

local function hook()
    if not (ISVehicleMenu and ISVehicleMenu.FillMenuOutsideVehicle) or ISVehicleMenu.ISnowBrushHooked then return end
    local fill = ISVehicleMenu.FillMenuOutsideVehicle
    ISVehicleMenu.FillMenuOutsideVehicle = function(player, context, vehicle, test)
        local r = fill(player, context, vehicle, test)
        if not test then
            local ok, err = pcall(addMenu, player, context, vehicle)
            if not ok then print("[ImmersiveSnow] brush menu failed: " .. tostring(err)) end
        end
        return r
    end
    ISVehicleMenu.ISnowBrushHooked = true
end

hook()
Events.OnGameStart.Add(hook)
