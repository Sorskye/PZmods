-- Immersive Snow: clearing the ground snow with a shovel. The vanilla snow itself goes off the
-- square: no picture is laid over it.
--
-- How the vanilla snow is drawn (bytecode 42.21): FBORenderSnow.RenderSnow draws it into a chunk
-- level's cached texture when that level is redrawn (FBORenderCell, right after the floors), on
-- each square of the floor list whose properties have IsoFlagType.solidfloor and exterior and no
-- room (and handle water apart); the tile comes from the chunk's snow grid (noise and the edges
-- between snowy and bare squares), which Lua cannot reach. IsoCell.gridSquareIsSnow asks the same
-- flags. The square's properties are its own PropertyContainer, the union of its objects' sprite
-- flags (IsoGridSquare.RecalcProperties), and Lua may set and unset a flag on it (vanilla does so
-- with IsoFlagType.burning, ISDestroyStuffAction.lua). The floor tile is drawn by its sprite's
-- flags, not the square's, so it stays.
--
-- So the snow goes off a cleared square by taking solidfloor off its properties while the world is
-- drawn, and putting it back before anything else reads it: off on OnTick (the end of the game
-- update; the handler is added on OnGameStart, after those of the mods that add theirs when
-- loaded), back on OnPostRender (right after IsoWorld.render: IngameState.renderFrameInternal),
-- after the last local player's view, and again on OnTickEvenPaused (the start of the next update)
-- if a view was not drawn (a sleeping player). Paused, OnTick does not come: off on
-- OnTickEvenPaused then. The game logic (paths, building, items, the pathfinder's square bits)
-- never sees the flag off; the caches IsoGridSquare fills from it on demand (isFree,
-- TreatAsSolidFloor) are emptied when it goes back, in case something asked while it was off. The
-- vanilla snow grid itself is untouched: the squares around keep their tiles, so the cleared one
-- has the straight edge of a cut. A change redraws the square's chunk level
-- (invalidateRenderChunkLevel), and every later redraw (lighting, objects, zoom, the snow growing)
-- happens inside the world render too, so it never brings the snow back.
--
-- Only squares near the local players are touched each tick (buckets by chunk, NEAR_CHUNKS around
-- each player): about seven Java calls a square.
--
-- Footprints, ruts and wet feet take a cleared square as bare ground (ISnow.Shovel.isCleared:
-- ISnow_Decals.lua isSnowSquare, ISnow_SnowWetness.lua). The squares and the snow coming back on
-- them: ISnow_Cleared.lua (in the save; MP: the server's).
--
-- The shovel: right-clicking the ground with a shovel (SHOVELS: matched by item type, so modded
-- ones count too) in the main inventory offers "Clear the snow" for the square, and "... around"
-- for the snowy ones of the 3 x 3 around it. The player walks next to the square, takes the shovel
-- in both hands and digs (the vanilla shovel animation and loop), throwing the snow aside in
-- clumps (ISnow_BlowOff.lua); a snow shovel is faster. A square has snow to clear when vanilla draws
-- any there: its own full tile or an edge from a snowy neighbour (the edge pass only puts edges on
-- squares next to a full one).

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_Cleared"
require "ImmersiveSnow/ISnow_BlowOff"
require "TimedActions/ISBaseTimedAction"

local Shovel = {}
ISnow.Shovel = Shovel
local Cleared = ISnow.Cleared

local NEAR_CHUNKS = 8         -- chunks (8 squares) around each local player whose cleared squares are hidden
local SHOVELS = { "shovel", "spade" }   -- item types (lower case, substrings) that clear snow ...
local NOT_SHOVELS = { "handshovel" }    -- ... and the small ones that do not
local SNOW_SHOVEL = "snowshovel"
local SNOW_SHOVEL_TIME = 110  -- action time per square at full snow, a snow shovel / any other
local SPADE_TIME = 190
local MIN_PART = 0.5          -- of the full time even a thin snow takes
local REACH = 2.2             -- tiles from the square's centre the digger may stand
-- snow thrown aside: a clump or puff every THROW_MS on average while digging, a burst at the end
local THROW_MS = 160
local THROW_END = 7
local THROW_SPEED = { 1.0, 2.2 }   -- tiles / s

local MP_MODULE = Cleared.MODULE

-- [bucket] = { { x, y }, ... }: the cleared squares by chunk (bucket = chunk x * 4096 + chunk y)
local buckets = {}
local near = {}               -- the cleared squares within NEAR_CHUNKS of a local player: { x, y }
local nearDirty = true
local nearAt = {}             -- [player index] = bucket of that player's chunk at the last refresh
local hiddenSq, hiddenProps = {}, {}
local nHidden = 0
local viewsLeft = 0           -- local players' views still to be drawn with the snow off
local SOLID = IsoFlagType.solidfloor
local stats = { hide = 0, restore = 0, hideMs = 0, frames = 0, maxHidden = 0 }

local function bucketOf(x, y)
    return math.floor(x / 8) * 4096 + math.floor(y / 8)
end

-- Whether x, y, z was cleared with a shovel: bare ground for the footprints and wet feet.
function Shovel.isCleared(x, y, z)
    return z ~= nil and math.floor(z) == 0 and Cleared.has(x, y)
end

local function redraw(x, y)
    local cell = getCell()
    local sq = cell and cell:getGridSquare(x, y, 0)
    if sq then sq:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_REDRAW) end
end

-- Cleared (ISnow_Cleared.lua): x, y cleared, or back = true: snowy again.
local function onChange(x, y, back)
    local b = bucketOf(x, y)
    local list = buckets[b]
    if back then
        if list then
            for i = #list, 1, -1 do
                if list[i][1] == x and list[i][2] == y then table.remove(list, i) end
            end
            if #list == 0 then buckets[b] = nil end
        end
    else
        if not list then
            list = {}
            buckets[b] = list
        end
        for i = 1, #list do
            if list[i][1] == x and list[i][2] == y then return end
        end
        list[#list + 1] = { x, y }
    end
    nearDirty = true
    redraw(x, y)
end
Cleared.onChange = onChange

local function refreshNear()
    local moved = nearDirty
    local players = {}
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p then
            local b = bucketOf(p:getX(), p:getY())
            players[#players + 1] = b
            if nearAt[i] ~= b then
                nearAt[i] = b
                moved = true
            end
        end
    end
    if not moved then return end
    nearDirty = false
    near = {}
    local seen = {}
    for _, b in ipairs(players) do
        local cx, cy = math.floor(b / 4096), b % 4096
        for dx = -NEAR_CHUNKS, NEAR_CHUNKS do
            for dy = -NEAR_CHUNKS, NEAR_CHUNKS do
                local k = (cx + dx) * 4096 + cy + dy
                local list = buckets[k]
                if list and not seen[k] then
                    seen[k] = true
                    for i = 1, #list do near[#near + 1] = list[i] end
                end
            end
        end
    end
end

-- Puts solidfloor back on the squares that had it taken off.
local function restore()
    if nHidden == 0 then return end
    for i = 1, nHidden do
        hiddenProps[i]:set(SOLID)
        local sq = hiddenSq[i]
        sq:setCachedIsFree(false)
        sq:setSolidFloorCached(false)
        hiddenSq[i], hiddenProps[i] = nil, nil
    end
    nHidden = 0
    stats.restore = stats.restore + 1
end

local function activeViews()
    local n = 0
    for i = 0, getNumActivePlayers() - 1 do
        if getSpecificPlayer(i) then n = n + 1 end
    end
    return n
end

-- Takes solidfloor off the cleared squares near the local players, for the world render.
local function hide()
    restore()
    if Cleared.count() == 0 then return end
    local cell = getCell()
    if not cell then return end
    local t0 = getTimestampMs()
    refreshNear()
    for i = 1, #near do
        local e = near[i]
        local sq = cell:getGridSquare(e[1], e[2], 0)
        if sq then
            local props = sq:getProperties()
            if props:has(SOLID) then
                props:unset(SOLID)
                nHidden = nHidden + 1
                hiddenSq[nHidden], hiddenProps[nHidden] = sq, props
            end
        end
    end
    viewsLeft = activeViews()
    stats.hide = stats.hide + 1
    stats.hideMs = stats.hideMs + getTimestampMs() - t0
    if nHidden > stats.maxHidden then stats.maxHidden = nHidden end
end

-- MP: the server's set is asked for once a local player is in the world (a command sent on
-- OnGameStart never reaches the server: seen in game), again every QUERY_RETRY_MS until it comes.
local QUERY_RETRY_MS = 10000
local QUERY_TRIES = 5
local queryAt, queryTries, synced = nil, 0, false

local function askServer()
    if synced or queryTries >= QUERY_TRIES or not getSpecificPlayer(0) then return end
    local now = getTimestampMs()
    if queryAt and now - queryAt < QUERY_RETRY_MS then return end
    queryAt, queryTries = now, queryTries + 1
    sendClientCommand(MP_MODULE, "clearedQuery", { ask = true })
end

local function onTick()
    if isClient() then askServer() end
    hide()
end

local function onTickEvenPaused()
    restore()
    if isGamePaused() then hide() end
end

local function onPostRender()
    stats.frames = stats.frames + 1
    if nHidden == 0 then return end
    viewsLeft = viewsLeft - 1
    if viewsLeft <= 0 then restore() end
end

local function safe(name, fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then
            -- never leave the flags off
            pcall(restore)
            print("[ImmersiveSnow] shovel " .. name .. " failed: " .. tostring(err))
        end
    end
end

ISnow.listen("OnTickEvenPaused", "Shovel", safe("restore", onTickEvenPaused))
ISnow.listen("OnPostRender", "Shovel", safe("restore", onPostRender))
local tickAdded = false
local function onGameStart()
    if not tickAdded then
        tickAdded = true
        ISnow.listen("OnTick", "Shovel", safe("hide", onTick))
    end
end
Events.OnGameStart.Add(onGameStart)

-- MP: the server's set (ISnow_Cleared.lua). "clearedAll" comes in parts; the copy is replaced
-- with the last one. An empty keys table arrives as nil, so no keys = none.
local incoming = nil
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= MP_MODULE or not isClient() or type(args) ~= "table" then return end
    local ok, err = pcall(function()
        if command == "cleared" then
            local x, y = tonumber(args.x), tonumber(args.y)
            if x and y then Cleared.add(x, y) end
        elseif command == "uncleared" and type(args.keys) == "table" then
            Cleared.remove(args.keys)
        elseif command == "clearedAll" then
            local keys = type(args.keys) == "table" and args.keys or {}
            if args.part == 1 or not incoming then incoming = {} end
            for i = 1, #keys do incoming[#incoming + 1] = keys[i] end
            if args.last then
                Cleared.replace(incoming)
                incoming = nil
                synced = true
            end
        end
    end)
    if not ok then print("[ImmersiveSnow] cleared squares command failed: " .. tostring(err)) end
end)

-- Clears x, y: here at once (SP: in the save), and in MP for everyone through the server.
function Shovel.clear(x, y)
    x, y = math.floor(x), math.floor(y)
    Cleared.add(x, y)
    if isClient() then sendClientCommand(MP_MODULE, "shovel", { x = x, y = y }) end
end

-- Whether vanilla draws snow on square sq (z 0, under the sky, with a floor): a full tile of its
-- own or an edge from a full neighbour, and not cleared.
function Shovel.hasSnow(sq)
    if not sq or sq:getZ() ~= 0 or not ISnow.underSky(sq) or not sq:getFloor() then return false end
    if ISnow.groundCover() <= 0 then return false end
    local x, y = sq:getX(), sq:getY()
    if Cleared.has(x, y) then return false end
    local cell = getCell()
    return cell:gridSquareIsSnow(x, y, 0) or cell:gridSquareIsSnow(x, y - 1, 0) or cell:gridSquareIsSnow(x, y + 1, 0)
        or cell:gridSquareIsSnow(x - 1, y, 0) or cell:gridSquareIsSnow(x + 1, y, 0)
end

local function matches(t, list)
    for _, s in ipairs(list) do
        if string.find(t, s, 1, true) then return true end
    end
    return false
end

local function isShovel(item)
    local t = string.lower(item:getType() or "")
    return matches(t, SHOVELS) and not matches(t, NOT_SHOVELS)
end

-- The shovel in player p's main inventory to clear snow with (the one in the hands first, then a
-- snow shovel), nil for none.
function Shovel.find(p)
    local hand = p:getPrimaryHandItem()
    if hand and isShovel(hand) then return hand end
    local best = nil
    local items = p:getInventory():getItems()
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if isShovel(item) then
            if string.find(string.lower(item:getType() or ""), SNOW_SHOVEL, 1, true) then return item end
            best = best or item
        end
    end
    return best
end

ISnowShovelSnow = ISBaseTimedAction:derive("ISnowShovelSnow")

function ISnowShovelSnow:isValid()
    if not self.tool or not self.character:getInventory():contains(self.tool) then return false end
    local dx = self.sq:getX() + 0.5 - self.character:getX()
    local dy = self.sq:getY() + 0.5 - self.character:getY()
    return dx * dx + dy * dy <= REACH * REACH and not Cleared.has(self.sq:getX(), self.sq:getY())
end

function ISnowShovelSnow:waitToStart()
    self.character:faceLocation(self.sq:getX() + 0.5, self.sq:getY() + 0.5)
    return self.character:shouldBeTurning()
end

-- Snow thrown off the shovel: n clumps (and a puff each now and then) from the square, to the
-- digger's side.
function ISnowShovelSnow:throw(n)
    local blow = ISnow.BlowOff
    if not (blow and blow.kick) then return end
    local c = self.character
    local fx, fy = self.sq:getX() + 0.5 - c:getX(), self.sq:getY() + 0.5 - c:getY()
    local d = math.sqrt(fx * fx + fy * fy)
    if d < 0.01 then fx, fy, d = 1, 0, 1 end
    fx, fy = fx / d, fy / d
    for _ = 1, n do
        local x = self.sq:getX() + ZombRandFloat(0.2, 0.8)
        local y = self.sq:getY() + ZombRandFloat(0.2, 0.8)
        -- to the side (right of the digger) and a little forward
        local speed = ZombRandFloat(THROW_SPEED[1], THROW_SPEED[2])
        local side = self.side
        local vx, vy = (-fy * side + fx * 0.3) * speed, (fx * side + fy * 0.3) * speed
        blow.kick(x, y, 0.05, vx, vy, true, ZombRandFloat(1.2, 2.0))
        if ZombRand(3) == 0 then blow.kick(x, y, 0.05, vx * 0.5, vy * 0.5, false) end
    end
end

function ISnowShovelSnow:update()
    self.character:faceLocation(self.sq:getX() + 0.5, self.sq:getY() + 0.5)
    self.character:setMetabolicTarget(Metabolics.DiggingSpade)
    local now = getTimestampMs()
    if now >= self.nextThrow then
        self.nextThrow = now + ZombRandFloat(0.5, 1.5) * THROW_MS
        self:throw(1)
    end
end

function ISnowShovelSnow:start()
    self:setActionAnim(BuildingHelper.getShovelAnim(self.tool))
    self:setOverrideHandModels(self.tool, nil)
    self.sound = self.character:getEmitter():playSound("Shoveling")
    addSound(self.character, self.character:getX(), self.character:getY(), self.character:getZ(), 10, 1)
end

function ISnowShovelSnow:stopSound()
    if self.sound and self.sound ~= 0 and self.character:getEmitter():isPlaying(self.sound) then
        self.character:getEmitter():stopSound(self.sound)
    end
end

function ISnowShovelSnow:stop()
    self:stopSound()
    ISBaseTimedAction.stop(self)
end

function ISnowShovelSnow:perform()
    self:stopSound()
    self:throw(THROW_END)
    Shovel.clear(self.sq:getX(), self.sq:getY())
    ISBaseTimedAction.perform(self)
end

function ISnowShovelSnow:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    local t = string.lower(self.tool:getType() or "")
    local full = string.find(t, SNOW_SHOVEL, 1, true) and SNOW_SHOVEL_TIME or SPADE_TIME
    return math.floor(full * math.max(MIN_PART, ISnow.groundCover()))
end

function ISnowShovelSnow:new(character, sq, tool)
    local o = ISBaseTimedAction.new(self, character)
    o.sq = sq
    o.tool = tool
    o.side = ZombRand(2) == 0 and 1 or -1
    o.nextThrow = 0
    o.stopOnWalk = true
    o.stopOnRun = true
    o.maxTime = o:getDuration()
    return o
end

-- Whether item is held in both hands.
local function twoHanded(item)
    return item ~= nil and instanceof(item, "HandWeapon") and item:isTwoHandWeapon()
end

-- Queues clearing the squares (nearest to p first): walk next to each (the first walk empties the
-- queue, as vanilla's), the shovel into the hands before the first dig.
local function clearSquares(p, squares, tool)
    local px, py = p:getX(), p:getY()
    table.sort(squares, function(a, b)
        local da = (a:getX() + 0.5 - px) ^ 2 + (a:getY() + 0.5 - py) ^ 2
        local db = (b:getX() + 0.5 - px) ^ 2 + (b:getY() + 0.5 - py) ^ 2
        return da < db
    end)
    for i, sq in ipairs(squares) do
        if luautils.walkAdj(p, sq, i > 1) then
            if i == 1 and ISWorldObjectContextMenu and ISWorldObjectContextMenu.equip then
                ISWorldObjectContextMenu.equip(p, p:getPrimaryHandItem(), tool, true, twoHanded(tool))
            end
            ISTimedActionQueue.add(ISnowShovelSnow:new(p, sq, tool))
        end
    end
end

local function clickedSquare(worldobjects)
    for _, o in ipairs(worldobjects or {}) do
        local sq = o.getSquare and o:getSquare()
        if sq then return sq end
    end
    return nil
end

local function addMenu(playerNum, context, worldobjects)
    local p = getSpecificPlayer(playerNum)
    if not p or p:isDead() or p:getVehicle() then return end
    local sq = clickedSquare(worldobjects)
    if not sq or not Shovel.hasSnow(sq) then return end
    local tool = Shovel.find(p)
    if not tool then return end
    local name = tool:getDisplayName()
    context:addOption(getText("UI_ImmersiveSnow_ClearSnow", name), p, clearSquares, { sq }, tool)
    local around = {}
    local cell = getCell()
    for dx = -1, 1 do
        for dy = -1, 1 do
            local s = cell:getGridSquare(sq:getX() + dx, sq:getY() + dy, 0)
            if s and Shovel.hasSnow(s) then around[#around + 1] = s end
        end
    end
    if #around > 1 then
        context:addOption(getText("UI_ImmersiveSnow_ClearSnowAround", name), p, clearSquares, around, tool)
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    local ok, err = pcall(addMenu, playerNum, context, worldobjects)
    if not ok then print("[ImmersiveSnow] shovel menu failed: " .. tostring(err)) end
end)

-- Debug console: ISnow.Shovel.stats() prints the cleared squares, how many are hidden each frame
-- and the time it takes.
function Shovel.stats()
    local out = string.format("cleared %d, near %d, hidden now %d (max %d), hide %d x (%.3f ms avg), restore %d x, frames %d",
        Cleared.count(), #near, nHidden, stats.maxHidden, stats.hide,
        stats.hide > 0 and stats.hideMs / stats.hide or 0, stats.restore, stats.frames)
    print(out)
    return out
end

-- Test hooks (tools/luatest): hide / restore by hand.
Shovel.hide = hide
Shovel.restore = restore
Shovel.onGameStart = onGameStart
