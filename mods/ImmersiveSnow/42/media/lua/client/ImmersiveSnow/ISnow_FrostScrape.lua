-- Immersive Snow: scraping the frost off a vehicle's windows (VehicleFrost, ISnow_VehicleSnow.lua).
--
-- Right-clicking a vehicle with frost on its glass (the hoarfrost, or the icing's film and snow
-- along the glass edges: VehicleSnow.glassIced) offers "Scrape frost off the windows": the player
-- walks to the front of it (the engine area, at the windscreen), faces it and scrapes, by hand or,
-- faster, with a flat tool from the main inventory (SCRAPERS: matched by item type, so a modded ice
-- scraper counts too), which goes into the hands for it. With a tool the player scrapes the glass
-- in short strokes of one hand (the vanilla wall scrub with a toilet brush), by hand rubs it with
-- the palm (the sponge wall scrub), with a scraping sound, and ice crumbs and powder fall from
-- the hands (ISnow_BlowOff.lua). The frost thins as the scrape goes on, the glass is wiped of the
-- icing at GLASS_AT of it (VehicleSnow.cleanGlass) and all of it is gone at the end
-- (VehicleSnow.scrape: in MP for everyone). The time grows with the frost.
--
-- The action is client side only: it has no complete(), so B42 does not run it on the server (the
-- frost is not server state, see ISnow_VehicleSnow.lua).

require "ImmersiveSnow/ISnow_Config"
require "TimedActions/ISBaseTimedAction"

local MENU_MIN = 0.05        -- frost below this (and no icing on the glass): no menu entry
local HAND_TIME = 900        -- action time at full frost, by hand / with a tool
local TOOL_TIME = 260
local MIN_PART = 0.35        -- of the full time even a light frost takes
local GLASS_AT = 0.5         -- of the action: the icing goes off the glass
local REACH = 4.5            -- tiles from the vehicle's centre the scraper may stand
-- item types (lower case, substrings) that scrape: ice scrapers of mods, spatulas, trowels, putty knives
local SCRAPERS = { "icescraper", "scraper", "spatula", "trowel", "puttyknife" }
local ANIM_TOOL = "ScrubWall_ToiletBrush"   -- vanilla AnimSets/player/actions
local ANIM_HAND = "ScrubWall"
local SOUND = "CleanBloodScrub"
-- ice falling from the hands: one crumb or puff every CRUMB_MS on average (by hand twice as
-- far apart), HAND_REACH tiles in front of the player at HAND_HEIGHT floor levels
local CRUMB_MS = 140
local HAND_REACH = 0.45
local HAND_HEIGHT = 0.36
local CRUMB_SCALE = 0.6

ISnowScrapeFrost = ISBaseTimedAction:derive("ISnowScrapeFrost")

-- A flat tool in player p's main inventory to scrape with, nil for bare hands.
local function findScraper(p)
    local items = p:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local t = string.lower(item:getType() or "")
        for _, s in ipairs(SCRAPERS) do
            if string.find(t, s, 1, true) then return item end
        end
    end
    return nil
end

local function frostOf(v)
    local vs = ISnow.VehicleSnow
    return vs and vs.frostOf and vs.frostOf(v) or 0
end

local function glassIced(v)
    local vs = ISnow.VehicleSnow
    return vs and vs.glassIced and vs.glassIced(v) or false
end

function ISnowScrapeFrost:isValid()
    local v = self.vehicle
    if not v or v:isRemovedFromWorld() or self.character:getVehicle() then return false end
    local dx, dy = v:getX() - self.character:getX(), v:getY() - self.character:getY()
    return dx * dx + dy * dy <= REACH * REACH
end

function ISnowScrapeFrost:waitToStart()
    self.character:faceThisObject(self.vehicle)
    return self.character:shouldBeTurning()
end

-- Ice crumbs and powder falling from the scraping hands, on this client.
function ISnowScrapeFrost:crumbs()
    local blow = ISnow.BlowOff
    if not (blow and blow.kick) then return end
    local now = getTimestampMs()
    if now < self.nextCrumb then return end
    local gap = self.tool and CRUMB_MS or CRUMB_MS * 2
    self.nextCrumb = now + ZombRandFloat(0.5, 1.5) * gap
    local c, v = self.character, self.vehicle
    local dx, dy = v:getX() - c:getX(), v:getY() - c:getY()
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 0.01 then return end
    dx, dy = dx / d, dy / d
    local side = ZombRandFloat(-0.15, 0.15)
    local x, y = c:getX() + dx * HAND_REACH - dy * side, c:getY() + dy * HAND_REACH + dx * side
    -- falling off the glass, a little back towards the player
    local vx, vy = -dx * ZombRandFloat(0.1, 0.4), -dy * ZombRandFloat(0.1, 0.4)
    blow.kick(x, y, c:getZ() + HAND_HEIGHT * ZombRandFloat(0.85, 1.1), vx, vy, ZombRand(3) ~= 0, CRUMB_SCALE)
end

function ISnowScrapeFrost:update()
    self.character:faceThisObject(self.vehicle)
    self.character:setMetabolicTarget(Metabolics.LightWork)
    -- thinner as it goes, on this client (the end goes to everyone)
    local done = self:getJobDelta()
    local f = self.startFrost * (1 - done)
    if f < frostOf(self.vehicle) then ISnow.VehicleSnow.setFrost(self.vehicle, f, true) end
    if done >= GLASS_AT and not self.glassDone then
        self.glassDone = true
        ISnow.VehicleSnow.cleanGlass(self.vehicle)
    end
    if self.startFrost > 0 or not self.glassDone then self:crumbs() end
end

function ISnowScrapeFrost:start()
    if self.tool then
        self:setActionAnim(ANIM_TOOL)
        self:setOverrideHandModels(self.tool, nil)
    else
        self:setActionAnim(ANIM_HAND)
        self:setOverrideHandModels(nil, nil)
    end
    self.sound = self.character:playSound(SOUND)
end

function ISnowScrapeFrost:stopSound()
    if self.sound and self.sound ~= 0 then self.character:stopOrTriggerSound(self.sound) end
    self.sound = nil
end

function ISnowScrapeFrost:stop()
    self:stopSound()
    -- stopped half-way: what is off already goes to the others too
    if frostOf(self.vehicle) < self.startFrost or self.glassDone then ISnow.VehicleSnow.report(self.vehicle) end
    ISBaseTimedAction.stop(self)
end

function ISnowScrapeFrost:perform()
    self:stopSound()
    ISnow.VehicleSnow.scrape(self.vehicle)
    ISBaseTimedAction.perform(self)
end

function ISnowScrapeFrost:getDuration()
    local frost = math.max(MIN_PART, self.startFrost or 1)
    return math.floor((self.tool and TOOL_TIME or HAND_TIME) * frost)
end

function ISnowScrapeFrost:new(character, vehicle, tool)
    local o = ISBaseTimedAction.new(self, character)
    o.vehicle = vehicle
    o.tool = tool
    o.startFrost = frostOf(vehicle)
    o.nextCrumb = 0
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

-- Queues the scrape of vehicle v for player p: to the front of it first, the tool into the hands.
local function scrape(p, v, tool)
    local area = v:getScript() and v:getScript():getAreaById("Engine")
    if area and ISPathFindAction and ISPathFindAction.pathToVehicleArea then
        ISTimedActionQueue.add(ISPathFindAction:pathToVehicleArea(p, v, "Engine"))
    end
    if tool and ISWorldObjectContextMenu and ISWorldObjectContextMenu.equip then
        ISWorldObjectContextMenu.equip(p, p:getPrimaryHandItem(), tool, true)
    end
    ISTimedActionQueue.add(ISnowScrapeFrost:new(p, v, tool))
end

local function addMenu(playerNum, context, v)
    if not v or (frostOf(v) < MENU_MIN and not glassIced(v)) then return end
    local p = getSpecificPlayer(playerNum)
    if not p or p:getVehicle() then return end
    local tool = findScraper(p)
    local label = tool and getText("UI_ImmersiveSnow_ScrapeFrostWith", tool:getDisplayName())
        or getText("UI_ImmersiveSnow_ScrapeFrostHand")
    context:addOption(label, p, scrape, v, tool)
end

local function hook()
    if not (ISVehicleMenu and ISVehicleMenu.FillMenuOutsideVehicle) or ISVehicleMenu.ISnowScrapeHooked then return end
    local fill = ISVehicleMenu.FillMenuOutsideVehicle
    ISVehicleMenu.FillMenuOutsideVehicle = function(player, context, vehicle, test)
        local r = fill(player, context, vehicle, test)
        if not test then
            local ok, err = pcall(addMenu, player, context, vehicle)
            if not ok then print("[ImmersiveSnow] scrape menu failed: " .. tostring(err)) end
        end
        return r
    end
    ISVehicleMenu.ISnowScrapeHooked = true
end

hook()
Events.OnGameStart.Add(hook)
