-- Immersive Snow: helpers shared by the ground decals (footprints, tire tracks).
--
-- Decals are not world objects: a Lua list of them is drawn every frame from
-- RenderOpaqueObjectsInWorld. B42 (FBORenderCell.renderInternal) raises it after the chunk FBOs
-- (floor, ground snow, static objects: all write depth) and after the local players
-- (renderPlayers runs first, IsoGameCharacter.render writes depth), and before zombies and other
-- moving objects, shadows and the translucent passes.
--
-- Each decal is drawn with Render3DItem (LuaManager.GlobalObject) as the icon of a carrier item
-- without a 3D model (scripts/ISnow_Decal.txt). That is the vanilla path of 2D items on the
-- ground: depth test on (GL_LEQUAL), depth write off, and the whole quad gets the scene depth of
-- one world point, TextureDraw.nextZ = IsoDepthHelper.getSquareDepthData(x + 0.25, y + 0.25, z),
-- chunk depth plus depth inside the chunk. So walls, fences, trees, roofs and players in front of
-- a decal hide it pixel by pixel, and zombies and shadows drawn later go over it.
-- (IsoSprite.renderTextureWithDepth, used before, leaves the chunk depth at 0 outside the
-- translucent pass: the depth only covered the position inside the 8x8 chunk, so decals showed
-- through roofs and players. IsoSprite:renderBloodSplat has no depth test at all.)
--
-- Render3DItem, bytecode 42.20:
--  * texture: getSharedTexture(item:getWorldTexture()) when the script has UseWorldItem, so the
--    carrier gets each decal's file path before the call (the same string the texture was
--    loaded with, so it is the cached texture);
--  * rotation < 0 makes WorldItemModelDrawer.renderAtlasTexture return at once; with no model the
--    item then takes the 2D branch;
--  * the colour is always 1,1,1,1 (Texture.render(..., 1, 1, 1, 1, null)): fading uses
--    ISnow.FADE_LEVELS textures with the alpha baked in. The square's light is not applied either,
--    so white carried snow on dark clear ground glowed at night. Lit buffers (newBuffer's lit)
--    scale the alpha level by the light of the square as well: on ground much darker than the
--    snow, a*S*L + (1-a)*G (lit snow) is close to a*L*S + (1-a*L)*G (fainter unlit snow);
--    sq:getLightLevel(playerIndex) is max(r, g, b) of the square's current light (bytecode 42.20),
--    about 0.45 at dusk outdoors, 0.75 under a street lamp (measured in game);
--  * it sets no blend function, so it draws with whatever the previous drawer left. After the
--    chunk textures are redrawn (zooming, for one) that is not straight alpha and the decals
--    glowed brighter than the snow. So each frame starts with one IsoSprite:renderBloodSplat of a
--    blank 4x4 texture far off screen: it sets IndieGL.glBlendFuncSeparate(SRC_ALPHA,
--    ONE_MINUS_SRC_ALPHA, ONE_MINUS_DST_ALPHA, ONE) through the IndieGL state cache (calling
--    SpriteRenderer:glBlendFunc from Lua would bypass it) and has no screen culling under
--    fboRenderChunk; its fully transparent pixels are discarded by the shader. Verified in game
--    2026-09-29 at zoom 0.5: glowing without it, normal with it.
--  * dents in the snow (footprints, tire tracks: multiply buffers) are not alpha blended. With
--    colour 1,1,1,1 and no light a blue-grey shadow a*C + (1-a)*G is lighter than snow G that the
--    night made darker than C, so they glowed at night. The ground in the frame buffer is already
--    lit when the event runs (FBORenderSnow.setVertColors: the snow quads get the square's four
--    corner lights, IsoGridSquare.getVertLight, as vertex colours), so these decals multiply it: getRenderer():glBlendFuncSeparate(ZERO, ONE_MINUS_SRC_COLOR, ZERO, ONE),
--    screen = G * (1 - rgb), where the texture's rgb is how much each channel is darkened
--    (tools/gen_prints.py, gen_tracks.py: darkening()). Any light, night, lamp or coloured, then
--    darkens the mark exactly like the snow around it, and the mark is never lighter than it.
--    default.frag outputs texture * colour and discards alpha 0, so alpha is only the discard
--    mask. The call goes straight to the SpriteRenderer queue, past the IndieGL cache
--    (GLState.BlendFuncSeparate, IOpenGLState.set skips values equal to the cached one), so the
--    buffer sets it after resetBlend and, after its last decal, sets the cached value back
--    (IsoSprite.renderBloodSplat: SRC_ALPHA, ONE_MINUS_SRC_ALPHA, ONE_MINUS_DST_ALPHA, ONE):
--    the GL state matches the cache again for whatever vanilla draws next. Render3DItem only
--    touches the shader, depth mask, depth test and depth func (bytecode 42.20).
--    The cache skips a value equal to its own (IOpenGLState.set; GLState.startFrame marks it dirty
--    once a frame), so a multiply left behind would stay for everything vanilla draws after the
--    event that frame (moving objects, water, puddles on translucent floors, rain splashes, shadows:
--    FBORenderCell.performRenderTiles, 42.21) and darken it. Hence: the blend goes back even when a
--    draw fails (Buffer:render, the error is printed once and raised again), and a frame whose blank
--    splat cannot set the cached value (no texture: renderBloodSplat returns first) draws no
--    multiply decals at all. (Two players wrote that the mod broke puddles and ground snow,
--    2026-10-03/04. Both are drawn into the chunk textures before the event, and vanilla draws no
--    puddles at all while any snow lies, FBORenderCell.renderPuddles: isSnowAnywhere.)
--  * the texture is drawn at its own pixel size with its top-left corner at
--    screen(x, y, z) - (W * s / 2, 3 * H * s / 4), s = ScaleWorldIcon * tileScale / 2.

require "ImmersiveSnow/ISnow_Config"

local Decals = {}
ISnow.Decals = Decals

local CARRIER_ITEM = "ISnow.Decal"
local ICON_SCALE = 1.0           -- ScaleWorldIcon of the carrier item
local BLANK_TEXTURE = "media/textures/Item_ISnowBlank.png"
local BLANK_OFFSET = 300         -- tiles up-left of the viewer: the blank splat lands off screen

-- GL blend factors
local GL_ZERO, GL_ONE = 0, 1
local GL_ONE_MINUS_SRC_COLOR, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE_MINUS_DST_ALPHA = 769, 770, 771, 773

local carrier = nil
local carrierFailed = false
local renderErrorShown = false   -- the first error of Buffer:render is printed
local carrierTex = nil           -- world texture the carrier has now (setWorldTexture only on a change)
local blank = nil
local white = nil

function Decals.carrier()
    if carrier or carrierFailed then return carrier end
    carrier = instanceItem(CARRIER_ITEM)
    if not carrier then
        carrierFailed = true
        print("[ImmersiveSnow] decal carrier item " .. CARRIER_ITEM .. " missing, decals disabled")
    end
    return carrier
end

-- Sets straight-alpha blending for the decals drawn after it this frame (see the top). Whether it
-- could: without its texture renderBloodSplat sets nothing.
local function resetBlend(player)
    if not blank then
        blank = IsoSprite.new()
        blank:LoadSingleTexture(BLANK_TEXTURE)
        white = ColorInfo.new(1, 1, 1, 1)
    end
    if not blank:getTextureForCurrentFrame(IsoDirections.N) then return false end
    blank:renderBloodSplat(player:getX() - BLANK_OFFSET, player:getY() - BLANK_OFFSET, player:getZ(), white)
    return true
end
Decals.resetBlend = resetBlend

-- Multiply blending for the dents in the snow, after resetBlend (see the top).
local function startMultiply()
    getRenderer():glBlendFuncSeparate(GL_ZERO, GL_ONE_MINUS_SRC_COLOR, GL_ZERO, GL_ONE)
end

-- Back to the blend function resetBlend left in the IndieGL cache.
local function endMultiply()
    getRenderer():glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE_MINUS_DST_ALPHA, GL_ONE)
end

local function loadPath(path)
    local spr = IsoSprite.new()
    spr:LoadSingleTexture(path)
    return spr:getTextureForCurrentFrame(IsoDirections.N)
end

function Decals.loadTexture(file)
    return loadPath(ISnow.TEXTURE_DIR .. file)
end

-- The fade levels of one decal, fileFn(level) for level 1 (faintest) .. levels (full), as the list
-- of texture paths the renderer uses. The textures are loaded on first use (ensureSet, called by
-- Buffer:push): all decal sets together are about 2700 files, which used to be loaded when the game
-- started, even in summer, while a game only draws the directions (and tire widths) it meets.
function Decals.newSet(fileFn, levels)
    local set = {}
    for level = 1, levels do set[level] = ISnow.TEXTURE_DIR .. fileFn(level) end
    return set
end

-- Fade levels used: every step-th (ISnow.opt("DecalFadeStep"), 2 in the low-end mode) and the
-- full one, so only those textures are loaded (video memory); a level in between shows as the
-- next used one above it.
function Decals.fadeStep()
    return math.max(1, math.floor(ISnow.opt("DecalFadeStep") or 1))
end

local function usedLevel(set, level, step)
    if step <= 1 then return level end
    return math.min(#set, math.ceil(level / step) * step)
end

-- The texture path of fade level 1..#set of set, loading it if the used levels changed since the
-- set was loaded.
function Decals.pick(set, level, step)
    local q = usedLevel(set, level, step or Decals.fadeStep())
    local loaded = set.loaded
    if loaded and not loaded[q] then
        loadPath(set[q])
        loaded[q] = true
    end
    return set[q]
end

-- Loads the used textures of set once; returns its full-strength Texture (nil if it failed).
function Decals.ensureSet(set)
    local tex = set.tex
    if tex == nil then
        local step = Decals.fadeStep()
        local loaded = {}
        for level = 1, #set do
            if usedLevel(set, level, step) == level then
                tex = loadPath(set[level])
                loaded[level] = true
            end
        end
        set.loaded = loaded
        set.tex = tex or false
    end
    return tex or nil
end

-- newSet with the textures loaded at once; returns the set and the full-strength Texture.
function Decals.loadSet(fileFn, levels)
    local set = Decals.newSet(fileFn, levels)
    return set, Decals.ensureSet(set)
end

-- Render3DItem places the texture from one world point and takes the depth at that point plus
-- (0.25, 0.25). Screen x = (x - y) * 32 ts, screen y = (x + y) * 16 ts - z * 96 ts, and the scene
-- depth falls linearly with x + y + 2 z (IsoDepthHelper.getSquareDepthData), so moving the point
-- down by a fraction of a level and forward in x + y shifts the depth without moving the picture.
-- Returns the offset from a decal's centre on floor level z to the point to pass: a size x size
-- texture is centred on the decal, and the depth is that of the floor reach px below the centre
-- on screen, the front edge of the visible mark. The floor under the mark then never hides it,
-- while a boot or a wall standing in front of it does.
function Decals.anchor(size, reach)
    local ts = Core.getTileScale()
    local s = ICON_SCALE * ts / 2
    local u = size * (s - 1) / 2 / (32 * ts)        -- x - y, from the screen x offset
    local k = size * (3 * s - 2) / 4 / (16 * ts)    -- x + y - 6 z, from the screen y offset
    local t = reach / (16 * ts)                     -- x + y + 2 z of the depth point
    local dz = (t - 0.5 - k) / 8
    local sum = k + 6 * dz
    return (sum + u) / 2, (sum - u) / 2, dz
end

-- Snow on the ground at all (IsoCell.snowTarget); decals are dropped when it is gone.
function Decals.snowActive()
    local cell = getCell()
    return cell ~= nil and cell:getSnowTarget() > 0
end

-- A square a decal may be placed on: outdoors, has a floor, vanilla draws snow on it, not cleared
-- with a shovel (ISnow_Cleared.lua).
function Decals.isSnowSquare(cell, sx, sy, sz)
    local sq = cell:getGridSquare(sx, sy, sz)
    if not ISnow.underSky(sq) or not sq:getFloor() then return false end
    if sz == 0 and ISnow.Cleared and ISnow.Cleared.has(sx, sy) then return false end
    return cell:gridSquareIsSnow(sx, sy, sz)
end

-- Fraction of a decal's lifetime that passes in one game minute; fresh snowfall covers faster.
function Decals.agePerMinute(lifetimeHours)
    local rate = 1
    local clim = getClimateManager()
    if clim:isSnowing() then
        rate = rate + clim:getSnowIntensity() * ISnow.opt("SnowfallCoverRate")
    end
    return rate / 60 / math.max(0.1, lifetimeHours)
end

-- Per-minute ageing of snow carried onto clear ground (Buffer:ageEach), by the air temperature of
-- each decal's square (ClimateManager.getAirTemperatureForSquare: outdoors the weather, indoors
-- the room with its heating): a lifetime of CarriedSnowHours at 0 C and below, plus melting that
-- alone would take CarriedSnowMeltHours at 20 C (linear in the degrees above 0). Entries need
-- sx, sy, z (their square).
function Decals.carriedAger()
    local clim, cell = getClimateManager(), getCell()
    local cold = 1 / math.max(0.05, ISnow.opt("CarriedSnowHours"))
    local warm = 1 / math.max(0.01, ISnow.opt("CarriedSnowMeltHours"))
    local temps = {}   -- per square, for this pass
    -- a number, not a string built per entry: a game minute passes every tick or more often while
    -- the time runs fast (sleeping), and this goes through every entry each time
    return function(e)
        local k = (e.z + 64) * 1099511627776 + e.sx * 1048576 + e.sy   -- levels from -64, x, y < 2^20
        local t = temps[k]
        if not t then
            local sq = cell:getGridSquare(e.sx, e.sy, e.z)
            t = sq and clim:getAirTemperatureForSquare(sq) or clim:getTemperature()
            temps[k] = t
        end
        return (cold + math.max(0, t) / 20 * warm) / 60
    end
end

-- FIFO of decals { x, y, z, rz, set }: x, y, rz = z + dz are the Render3DItem point
-- (centre + anchor()), z the floor level, set the texture paths by fade level. All entries age
-- at the same rate and are pushed in order, so the oldest is always at the head.
--
-- Drawing only looks at the entries near the screen: every entry is also in the list of its
-- CELL x CELL tile cell (in push order), and a frame goes through the cells that overlap the
-- viewer's screen. Looping over all entries cost about 1.2 us each in Kahlua (measured offline on
-- the game's VM), 14 ms a frame with the buffers full, and Render3DItem has no screen culling of
-- its own (bytecode 42.20: it always queues the texture), while at the default zoom the screen
-- shows about a tenth of the RENDER_RADIUS circle. Entries that leave the buffer are flagged
-- (gone / dead) and dropped from the cell lists when those are rebuilt.
--
-- Ageing does not touch every entry either (that was 0.6 us an entry, a 7 ms frame once a game
-- minute with 12000 entries): the buffer has a clock, an entry keeps the clock value it was
-- born at (e.born; its age is clock - born, ageOf), and age() only moves the clock and pops the
-- expired head. The fade texture (e.tex) is picked when an entry is pushed, and again when the
-- clock passes e.texUntil, the age at which its fade level drops, checked only for the entries a
-- frame draws.
--
-- Entries do not leave the drawing at once (but on clear, and past the allowance in trim): the
-- textures cannot fade any finer than their levels (see the top), so an entry pushed out by the
-- limit fades out through its levels
-- over fadeMs of real time (e.fadeAt) and leaves the list after that. The entries head ..
-- fadeNext - 1 are those pushed out (fading, or dead), oldest first; the limit counts the others.
-- A soft limit (softFn) pushes out the oldest above it the same way but fading over SOFT_FADE_MS,
-- so a spot driven over again and again loses its old laps smoothly; maxFn stays the hard limit
-- of all entries, fading ones included (past it the oldest go at once).
-- fadeOut(e) fades an entry anywhere in the list (a replaced rut); ageing already fades the rest
-- through the levels over the last part of the lifetime.
local Buffer = {}
Buffer.__index = Buffer

local CELL = 8                 -- tiles per cell side
local CELL_KEY = 1048576       -- key = cellX * CELL_KEY + cellY
local VIEW_MARGIN = 3          -- world units (of x - y and x + y) beyond the screen edge: texture size, anchor
local FADE_MS = 2400           -- real ms an entry pushed out by the limit takes to fade out
local SOFT_FADE_MS = 20000     -- ... by the soft limit
local FADE_EXTRA_MIN = 64      -- entries allowed above the limit while they fade: at least this many ...
local FADE_EXTRA_PART = 0.25   -- ... or this part of the limit; the oldest beyond it go at once

-- maxFn() returns the current size limit. onRemove(entry), if given, is called for every entry
-- that leaves the buffer (pushed out by the limit: when it starts to fade; expired; not on clear,
-- not for kill / fadeOut). After fullAlphaUntil (default 0.4) of its lifetime an entry's fade level
-- falls linearly to the faintest one. fadeMs (default FADE_MS, 0: at once): see "Nothing leaves".
-- lit: the level is picked every frame from e.strength (0..1, default 1) x fade x the light of the
-- entry's square (e.sx, e.sy, e.z); an entry whose level rounds to 0 is not drawn. lit = "strength":
-- the same from e.strength x fade alone (multiply textures take the light from the ground already:
-- the bloody prints, ISnow_Footprints.lua). Not lit: the level follows the age, scaled by
-- e.strength (at least level 1, see retexture).
-- multiply: the textures darken the lit ground under them (dents in the snow, see the top)
-- instead of being alpha blended over it.
-- softFn, if given, returns the soft limit (see "Entries do not leave").
function Decals.newBuffer(maxFn, onRemove, fullAlphaUntil, lit, multiply, fadeMs, softFn)
    local b = setmetatable({ maxFn = maxFn, onRemove = onRemove, fullAlphaUntil = fullAlphaUntil or 0.4,
        lit = lit or false, multiply = multiply or false, fadeMs = fadeMs or FADE_MS, softFn = softFn, drawn = 0,
        expired = 0, evicted = 0 }, Buffer)
    b:clear()
    return b
end

-- Entries in the buffer, removed ones (see kill) included until compact drops them.
function Buffer:count()
    return self.tail - self.head + 1
end

-- Entries fading out after the limit pushed them out (dead ones among them included).
function Buffer:fading()
    return self.fadeNext - self.head
end

function Buffer:clear()
    self.items, self.head, self.tail = {}, 1, 0
    self.fadeNext = 1
    self.dead = 0
    self.cells, self.stale = {}, 0
    self.clock = 0
end

-- Age of entry e as a fraction of its lifetime (1: expired).
function Buffer:ageOf(e)
    return self.clock - e.born
end

-- The fade texture of e for its age, and the clock value at which it changes. e.strength (0..1,
-- default 1) scales the level here too (bloody tire tracks pale with the blood left on the tire).
function Buffer:retexture(e)
    if self.lit then
        e.texUntil = 1e300   -- picked in render
        return
    end
    local set = e.set
    local levels = #set
    local top = levels * math.min(1, e.strength or 1)
    local full = self.fullAlphaUntil
    local age = self.clock - e.born
    local level = math.max(1, math.ceil(top - 1e-9))
    if age > full then
        level = math.max(1, math.ceil((1 - age) / (1 - full) * top))
    end
    e.tex = Decals.pick(set, level)
    e.level = level
    -- the level drops to level - 1 once (1 - age) / (1 - full) * top <= level - 1
    if level <= 1 or full >= 1 or top <= 0 then
        e.texUntil = 1e300
    else
        e.texUntil = e.born + 1 - (level - 1) * (1 - full) / top
    end
end

local function addToCell(cells, e)
    local key = math.floor(e.x / CELL) * CELL_KEY + math.floor(e.y / CELL)
    local list = cells[key]
    if not list then
        list = {}
        cells[key] = list
    end
    list[#list + 1] = e
end

-- Rebuilds the cell lists from the live entries once enough of them are gone.
function Buffer:pruneCells()
    local live = self:count() - self.dead
    if self.stale < 64 or self.stale < live then return end
    local cells = {}
    local items = self.items
    for i = self.head, self.tail do
        local e = items[i]
        if not e.dead then addToCell(cells, e) end
    end
    self.cells, self.stale = cells, 0
end

-- Fades entry e out over fadeMs; it is killed once that is over (in render). onRemove is not
-- called for it (the caller already knows).
function Buffer:fadeOut(e, now)
    if e.dead or e.fadeAt then return end
    e.fadeAt = now or getTimestampMs()
end

-- Real ms entry e takes to fade out once pushed out.
function Buffer:fadeTime(e)
    return e.fadeMs or self.fadeMs
end

-- Takes entry e out of the drawing at once; it leaves the list at the next compact. onRemove is
-- not called for it (the caller already knows).
function Buffer:kill(e)
    if e.dead then return end
    e.dead = true
    self.dead = self.dead + 1
    self.stale = self.stale + 1
end

-- Kills (see kill) every entry for which gone(e) is true: a kind of decal turned off.
function Buffer:killWhere(gone)
    local items = self.items
    for i = self.head, self.tail do
        local e = items[i]
        if e and not e.dead and gone(e) then self:kill(e) end
    end
end

-- Drops killed entries from the list, keeping the order.
function Buffer:compact()
    if self.dead == 0 then return end
    local keep, fadeNext = {}, 1
    for i = self.head, self.tail do
        local e = self.items[i]
        if not e.dead then
            keep[#keep + 1] = e
            if i < self.fadeNext then fadeNext = #keep + 1 end
        end
    end
    self.items, self.head, self.tail = keep, 1, #keep
    self.fadeNext = fadeNext
    self.dead = 0
end

function Buffer:popHead()
    local e = self.items[self.head]
    self.items[self.head] = nil
    self.head = self.head + 1
    if self.fadeNext < self.head then self.fadeNext = self.head end
    if e.dead then
        self.dead = self.dead - 1
    else
        e.gone = true
        self.stale = self.stale + 1
        -- a fading entry was reported when it started to fade (or by fadeOut's caller)
        if self.onRemove and not e.fadeAt then self.onRemove(e) end
    end
end

-- Drops the pushed-out entries at the head whose fade is over.
function Buffer:dropFaded(now)
    local items = self.items
    local popped = false
    while self.head < self.fadeNext do
        local e = items[self.head]
        if not e.dead and now - e.fadeAt < self:fadeTime(e) then break end
        self:popHead()
        popped = true
    end
    return popped
end

-- Keeps the entries not pushed out at the soft limit (max without one): the oldest others start
-- fading (onRemove is called for them now: they are no longer part of the tracks). Fading ones
-- above the extra allowance (decals laid faster than they fade) go at once; with a soft limit
-- the allowance ends at max itself.
function Buffer:trim(max, now)
    local items = self.items
    local keep, fadeMs = max, nil
    local soft = self.softFn and math.floor(self.softFn() or max)
    if soft and soft >= 1 and soft < max then keep, fadeMs = soft, SOFT_FADE_MS end
    while self.tail - self.fadeNext + 1 > keep do
        local e = items[self.fadeNext]
        self.fadeNext = self.fadeNext + 1
        if not e.dead and not e.fadeAt then
            e.fadeAt = now
            e.fadeMs = fadeMs
            self.evicted = self.evicted + 1
            if self.onRemove then self.onRemove(e) end
        end
    end
    self:dropFaded(now)
    local cap = fadeMs and max or max + math.max(FADE_EXTRA_MIN, math.floor(max * FADE_EXTRA_PART))
    while self:count() > cap do self:popHead() end
end

-- e.age, if given, is the age e starts at.
function Buffer:push(e)
    e.born = self.clock - (e.age or 0)
    e.age = nil
    self:retexture(e)
    if e.set.tex == nil then Decals.ensureSet(e.set) end
    self.tail = self.tail + 1
    self.items[self.tail] = e
    addToCell(self.cells, e)
    if self.dead * 4 > self:count() then self:compact() end
    self:trim(math.max(1, self.maxFn()), getTimestampMs())
    self:pruneCells()
    return e
end

function Buffer:age(dAge)
    if self:count() == 0 then return end
    local clock = self.clock + dAge
    self.clock = clock
    local items = self.items
    while self:count() > 0 and clock - items[self.head].born >= 1 do
        self:popHead()
        self.expired = self.expired + 1
    end
    self:pruneCells()
end

-- Ages every entry by rateFn(entry): entries age at their own rate, so any of them may expire.
function Buffer:ageEach(rateFn)
    if self:count() == 0 then return end
    local keep, fadeNext = {}, 1
    local clock = self.clock
    local now = getTimestampMs()
    for i = self.head, self.tail do
        local e = self.items[i]
        e.born = e.born - rateFn(e)
        if e.dead then
            -- dropped here, already reported when killed
        elseif clock - e.born >= 1 or (e.fadeAt and now - e.fadeAt >= self:fadeTime(e)) then
            e.gone = true
            self.stale = self.stale + 1
            if e.fadeAt then
                -- faded out; reported when it started
            else
                if self.onRemove then self.onRemove(e) end
                self.expired = self.expired + 1
            end
        else
            self:retexture(e)
            keep[#keep + 1] = e
            if i < self.fadeNext then fadeNext = #keep + 1 end
        end
    end
    self.items, self.head, self.tail = keep, 1, #keep
    self.fadeNext = fadeNext
    self.dead = 0
    self:pruneCells()
end

-- The part of the viewer's level on screen as ranges of x - y and x + y (screen x and y are
-- linear in them, LuaManager.GlobalObject.isoToScreenX / Y), with VIEW_MARGIN; nil if unknown.
local function viewBounds(playerIndex, px, py, pz)
    if not isoToScreenX or not getPlayerScreenWidth then return nil end
    local sx0, sy0 = isoToScreenX(playerIndex, px, py, pz), isoToScreenY(playerIndex, px, py, pz)
    -- one step in x: x - y and x + y both grow by 1
    local kx = isoToScreenX(playerIndex, px + 1, py, pz) - sx0
    local ky = isoToScreenY(playerIndex, px + 1, py, pz) - sy0
    if not (kx > 0 and ky > 0) then return nil end
    local left, top = getPlayerScreenLeft(playerIndex), getPlayerScreenTop(playerIndex)
    local u0, v0 = px - py, px + py
    return u0 + (left - sx0) / kx - VIEW_MARGIN, u0 + (left + getPlayerScreenWidth(playerIndex) - sx0) / kx + VIEW_MARGIN,
        v0 + (top - sy0) / ky - VIEW_MARGIN, v0 + (top + getPlayerScreenHeight(playerIndex) - sy0) / ky + VIEW_MARGIN
end
Decals.viewBounds = viewBounds   -- where drifting snow and steam may start (ISnow_Drift.lua, ISnow_Thaw.lua)

-- Draws the entries on the viewer's z level within radius that are on screen (with
-- Decals.toViewpoint set: hands them to the Viewpoint bridge instead, see exportVP).
function Buffer:render(playerIndex, radius)
    if Decals.toViewpoint then return self:exportVP(playerIndex, radius) end
    self.drawn = 0
    if self:count() == 0 then return end
    local player = getSpecificPlayer(playerIndex)
    if not player then return end
    local sq = player:getCurrentSquare()
    local item = Decals.carrier()
    if not sq or not item then return end
    local cx, cy, cz = player:getX(), player:getY(), math.floor(player:getZ())
    local r2 = radius * radius
    -- cells overlapping the screen (as an x / y box) and the radius
    local x0, x1, y0, y1 = cx - radius, cx + radius, cy - radius, cy + radius
    local umin, umax, vmin, vmax = viewBounds(playerIndex, cx, cy, cz)
    if umin then
        x0, x1 = math.max(x0, (umin + vmin) / 2), math.min(x1, (umax + vmax) / 2)
        y0, y1 = math.max(y0, (vmin - umax) / 2), math.min(y1, (vmax - umin) / 2)
    else
        umin, umax, vmin, vmax = -1e30, 1e30, -1e30, 1e30
    end
    local now = getTimestampMs()
    if self:dropFaded(now) then self:pruneCells() end
    local drawn = 0
    local cells = self.cells
    local clock = self.clock
    local lit, full = self.lit, self.fullAlphaUntil
    local cell = lit and getCell()
    local lights = lit and {}   -- [square key] = light, this frame
    -- darker snow (ISnow.darkSnow): the carried snow is white, so it gets fainter by the darker
    -- snow's brightness, as it does by the light (on ground much darker than snow it reads the same)
    local dim = lit and ISnow.darkSnow() and ISnow.DARK_SNOW_LUMA or 1
    local step = Decals.fadeStep()
    -- what is left of an entry fading out (1 .. 0), nil when it is not fading; kills it when done
    local function fadeLeft(e)
        local at = e.fadeAt
        if not at then return nil end
        local fadeMs = e.fadeMs or self.fadeMs
        local left = fadeMs > 0 and 1 - (now - at) / fadeMs or 0
        if left <= 0 then
            self:kill(e)
            return 0
        end
        return left
    end
    local byLight = lit ~= "strength"
    local function litTexture(e)
        local light = 1
        if byLight then
            local k = e.sx * CELL_KEY + e.sy
            light = lights[k]
            if not light then
                local lsq = cell:getGridSquare(e.sx, e.sy, e.z)
                light = (lsq and math.min(1, math.max(0, lsq:getLightLevel(playerIndex))) or 1) * dim
                lights[k] = light
            end
        end
        local age = clock - e.born
        local fade = age > full and (1 - age) / (1 - full) or 1
        fade = fade * (fadeLeft(e) or 1)
        local set = e.set
        local level = math.floor(#set * (e.strength or 1) * fade * light + 0.5)
        if level < 1 then return nil end
        return Decals.pick(set, math.min(level, #set), step)
    end
    local multiplying = false   -- startMultiply done, endMultiply owed
    local function draw()
        for gx = math.floor(x0 / CELL), math.floor(x1 / CELL) do
            for gy = math.floor(y0 / CELL), math.floor(y1 / CELL) do
                local list = cells[gx * CELL_KEY + gy]
                if list then
                    for i = 1, #list do
                        local e = list[i]
                        local x, y = e.x, e.y
                        local dx, dy = x - cx, y - cy
                        local u, v = x - y, x + y
                        if e.z == cz and dx * dx + dy * dy < r2 and u >= umin and u <= umax and v >= vmin and v <= vmax
                                and not e.gone and not e.dead then
                            local tex
                            if lit then
                                tex = litTexture(e)
                            else
                                if clock >= e.texUntil then self:retexture(e) end
                                tex = e.tex
                                local left = fadeLeft(e)
                                if left then
                                    local level = math.floor(e.level * left + 0.5)
                                    tex = level >= 1 and Decals.pick(e.set, level, step) or nil
                                end
                            end
                            if tex then
                                if drawn == 0 then
                                    -- a multiply decal only with the cached blend known (see the top)
                                    if not resetBlend(player) and self.multiply then return end
                                    if self.multiply then
                                        startMultiply()
                                        multiplying = true
                                    end
                                end
                                if tex ~= carrierTex then
                                    item:setWorldTexture(tex)
                                    carrierTex = tex
                                end
                                Render3DItem(item, sq, x, y, e.rz, -1)
                                drawn = drawn + 1
                            end
                        end
                    end
                end
            end
        end
    end
    local ok, err = pcall(draw)
    if multiplying then endMultiply() end
    self.drawn = drawn
    if not ok then
        if not renderErrorShown then
            renderErrorShown = true
            print("[ImmersiveSnow] decal render error (blend restored): " .. tostring(err))
        end
        error(err, 0)
    end
end

-- Project Viewpoint's 3D view (ISnow_CompatViewpoint.lua, with the submod's bridge ISnowVP): hands
-- the entries within radius of the player, on any level and in any direction (the camera may look
-- anywhere), to the bridge, which lays each texture on the ground where this view would draw it
-- (GroundDecals.java). The fade level is picked as render does, but Viewpoint lights the ground
-- itself, so lit entries leave the square's light out (strength and age only).
function Buffer:exportVP(playerIndex, radius)
    self.drawn = 0
    local vp = ISnowVP
    if self:count() == 0 or not vp then return end
    local player = getSpecificPlayer(playerIndex)
    if not player then return end
    local cx, cy = player:getX(), player:getY()
    local r2 = radius * radius
    local now = getTimestampMs()
    if self:dropFaded(now) then self:pruneCells() end
    local cells, clock = self.cells, self.clock
    local lit, full = self.lit, self.fullAlphaUntil
    -- as render: the white carried snow fainter by the darker snow's brightness
    local dim = lit and lit ~= "strength" and ISnow.darkSnow() and ISnow.DARK_SNOW_LUMA or 1
    local step = Decals.fadeStep()
    local n = 0
    vp.decalLayer(self.multiply and true or false)
    for gx = math.floor((cx - radius) / CELL), math.floor((cx + radius) / CELL) do
        for gy = math.floor((cy - radius) / CELL), math.floor((cy + radius) / CELL) do
            local list = cells[gx * CELL_KEY + gy]
            if list then
                for i = 1, #list do
                    local e = list[i]
                    local dx, dy = e.x - cx, e.y - cy
                    if not e.gone and not e.dead and dx * dx + dy * dy < r2 then
                        -- what is left of an entry fading out (see render's fadeLeft)
                        local left = 1
                        if e.fadeAt then
                            local fadeMs = e.fadeMs or self.fadeMs
                            left = fadeMs > 0 and 1 - (now - e.fadeAt) / fadeMs or 0
                            if left <= 0 then self:kill(e) end
                        end
                        local tex
                        if left > 0 then
                            if lit then
                                local age = clock - e.born
                                local fade = (age > full and (1 - age) / (1 - full) or 1) * left
                                local set = e.set
                                local level = math.floor(#set * (e.strength or 1) * fade * dim + 0.5)
                                if level >= 1 then tex = Decals.pick(set, math.min(level, #set), step) end
                            else
                                if clock >= e.texUntil then self:retexture(e) end
                                tex = e.tex
                                if e.fadeAt then
                                    local level = math.floor(e.level * left + 0.5)
                                    tex = level >= 1 and Decals.pick(e.set, level, step) or nil
                                end
                            end
                        end
                        if tex then
                            vp.decal(e.x, e.y, e.rz, e.z, tex)
                            n = n + 1
                        end
                    end
                end
            end
        end
    end
    self.drawn = n
end
