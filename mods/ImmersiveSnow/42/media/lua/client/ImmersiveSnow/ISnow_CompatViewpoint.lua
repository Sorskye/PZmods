-- Immersive Snow: compatibility with Project Viewpoint (workshop 3809306528, mod id Viewpoint, a Java
-- mod on ZombieBuddy; checked against its 0.1.5a-hotfix jar, the submod's bridge against 0.1.6).
--
-- With its view on (key O: first person; Shift+O third person), Viewpoint draws the world itself,
-- in 3D: Patch_IsoCell skips IsoCell.render (FP.renderWorld), and characters, vehicles and items on
-- the ground are drawn from their ModelSlotRenderData by its own shaders (ModelCapture,
-- VehicleCapture: each model's mesh with its texture and tint; the model's shader is never used).
-- So what our shaders draw comes out wrong there:
--  * the clothing shells (ISnow_CS_*) are a second copy of the clothes in the tint that carries
--    their parameters (r = amount, g = 0.75 or 1, b = fields): "clothes of players and zombies in
--    random colours", "clothes go blue" (Workshop, 2026-10-01..04);
--  * the vehicle body shells pass for vehicle shader models (they have TextureRust,
--    Shader.isVehicleShader), so they are a second copy of the body with the vehicle's own
--    textures; the wheel shells a copy of the wheels;
--  * breath and blow-off particles are drawn from OnPostRender at the isometric screen position of
--    their point, which in 3D is anywhere on the screen.
-- Prints, ruts, paths and the thaw (RenderOpaqueObjectsInWorld, raised from
-- FBORenderCell.renderInternal inside IsoCell.render) are simply not drawn then. The snow on the
-- ground is Viewpoint's own (FloorDecals.snow: the vanilla e_newsnow_ground tiles). Items in hand
-- are copies of their model with the same texture (ISnow_CharSnow.lua snowModel) and show as they
-- are, without snow. The frost on the screen covers the whole view and stays.
--
-- With the submod "Immersive Snow - Viewpoint" (a Workshop item of its own,
-- Contents/mods/ImmersiveSnowViewpoint in this repository: a Java part loaded by ZombieBuddy,
-- tools/vpbridge) the Lua table ISnowVP is there and Viewpoint draws our snow itself:
--  * clothing shells: the bridge bakes each shell's snow into a texture of its own and has
--    Viewpoint draw the shell with it (CharacterShells.java), so the shells stay on while the view
--    is on (as long as its character hook works: ISnowVP.capturing());
--  * vehicle shells: the same with the shell's own shader baked into a texture (VehicleShells.java,
--    VehicleBake.java), drawn before the body so the snow covers it; they stay on
--    (ISnowVP.vehicles());
--  * items in hand and on the body with snow: the item's texture with the snow of its isnow_item_*
--    shader baked in replaces the texture of its draw (ItemTextures.java, ItemBake.java);
--  * ground decals: a few times a second the decal modules' render handlers run here with
--    ISnow.Decals.toViewpoint set, and Buffer:exportVP hands their entries around the player to the
--    bridge, which lays them on the ground of Viewpoint's G-buffer (GroundDecals.java);
--  * breath and blow-off: drawn from OnPostRender as before, at the screen position Viewpoint's own
--    camera gives (ISnowVP.project, as Viewpoint places names over heads), see VP.camera;
--  * the ground snow with a depth (bridge 1.2, SnowVolume.java): twice a second the ground cover
--    (ISnow.groundCover) and the squares cleared with a shovel near the player go to the bridge,
--    which raises a snow surface over Viewpoint's flat snow tiles, presses beds under corpses and
--    items and lifts them onto it, and paints the decals onto it. An older bridge has no
--    ISnowVP.snowDepth: the ground stays flat as before (not part of VP_API).
-- Without the submod (or with a Viewpoint version the bridge was not made for: ISnowVP.present() is
-- false then; or with a submod of another API than VP_API, older or newer than this mod)
-- everything that would come out wrong is taken off while the view is on, as before.
--
-- Whether the view is on: the bridge says it (viewpoint.core.View.enabled). Without it Viewpoint
-- tells Lua nothing (its Lua classes: Viewpoint.Mouse, Keys, Loot, FrameCaps, ModelPacks), so the
-- view is taken to be on when OnPostRender (every frame, in IngameState right after IsoWorld.render)
-- comes OFF_FRAMES times in a row with no RenderOpaqueObjectsInWorld for player 0 in between
-- (Viewpoint draws for player 0 only). That event needs a picked tile on the map
-- (FBORenderCell.renderOpaqueObjectsEvent, 42.21), so a frame or two may come without it;
-- OFF_FRAMES rides over those. Paused frames do not count either way, nor those with the world map
-- open: the game draws no world under it (seen in game, 42.21: 2 frames of 250 with the event), and
-- in MP the map does not pause. Only with Viewpoint there: its Java part makes the Lua table
-- Viewpoint (ZombieBuddy's Exposer), also on a server that does not list the mod (ModLua), so the
-- mod list is the second test.
--
-- Console: ISnow.Viewpoint.force(true | false | nil) holds the state (nil: detected again; works
-- without Viewpoint, to see what goes), ISnow.Viewpoint.stats(); with the bridge also
-- ISnowVP.stats(), ISnowVP.shells(false) (the shells left out), ISnowVP.vehicleShells(false),
-- ISnowVP.items(false), ISnowVP.rebake(), ISnowVP.dumpShells / dumpVehicleShells / dumpItems(dir, n),
-- ISnowVP.volume(false) (the ground snow flat again).

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_Decals"

local VP = {}
ISnow.Viewpoint = VP

local MOD_ID = "Viewpoint"
local OFF_FRAMES = 30   -- frames without the world drawn before the view counts as on (half a second)
local DECAL_FRAMES = 4  -- frames between two hand-overs of the ground decals to the bridge
local DECAL_RADIUS = 45 -- tiles around the player (the decal modules' RENDER_RADIUS)
local VOLUME_MS = 500   -- real ms between two hand-overs of the snow's depth (SnowVolume scans as often)
local VOLUME_RADIUS = 48 -- cleared squares this near the player go along (SnowVolume's window: 80 squares)
-- after the view comes on, the bridge's character hook gets this long to show it works before the
-- shells come off (it runs from Viewpoint's first frame on)
local BRIDGE_GRACE_MS = 3000

local loaded = nil      -- Viewpoint there (looked up once)
local on = false
local forced = nil
local quietFrames = 0   -- frames in a row without the world drawn
local drawn = false     -- the world was drawn in this frame
local onSince = nil     -- getTimestampMs() when the view came on
local decalFrames = 0
local nextVolumeMs = 0
local stats = { switches = 0, worldFrames = 0, quietFrames = 0, handovers = 0, decals = 0, errors = 0 }
local lastError = nil

-- The bridge's API this file is written for (ISnowVP.API in tools/vpbridge): the submod is a
-- Workshop item of its own, so a player may have an older or newer one; with another API it counts
-- as not there (the fallback: the snow taken off in the 3D view).
local VP_API = 1
local apiChecked = false
local apiOk = false

-- The bridge's Lua table, when the submod's Java part is loaded, its API is ours and Viewpoint is
-- there.
local function bridge()
    local b = ISnowVP
    if type(b) ~= "table" or not b.present then return nil end
    if not apiChecked then
        apiChecked = true
        local api = b.api and tonumber(b.api()) or 0
        apiOk = api == VP_API
        if not apiOk then
            print("[ImmersiveSnow] Immersive Snow - Viewpoint " .. tostring(b.version and b.version()) .. " speaks API " .. api ..
                ", this Immersive Snow API " .. VP_API .. ": update " .. (api < VP_API and "Immersive Snow - Viewpoint" or "Immersive Snow") ..
                "; until then the snow is taken off in Viewpoint's 3D view")
        end
    end
    return apiOk and b.present() and b or nil
end

local function isLoaded()
    if loaded == nil then
        local mods = getActivatedMods and getActivatedMods()
        loaded = type(Viewpoint) == "table"
            or (mods ~= nil and (mods:contains(MOD_ID) or mods:contains("\\" .. MOD_ID)))
    end
    return loaded
end

local function set(value)
    if value ~= on then
        on = value
        onSince = on and getTimestampMs() or nil
        stats.switches = stats.switches + 1
        local b = bridge()
        if not on and b then pcall(b.decalsClear) end
        print("[ImmersiveSnow] Viewpoint view " .. (on and "on" or "off") .. (b and " (bridge " .. b.version() .. ")" or ""))
    end
end

-- Whether Viewpoint draws the world now (see the top of this file).
function VP.active()
    if forced ~= nil then return forced end
    return on
end

function VP.force(value)
    forced = value
    return VP.active()
end

-- The bridge is there (the submod's Java part and Viewpoint).
function VP.bridged()
    return bridge() ~= nil
end

-- Whether the clothing shells must come off: the view is on and the bridge does not draw them
-- (no bridge, or its character hook has not run since the view came on).
function VP.hideShells()
    if not VP.active() then return false end
    local b = bridge()
    if not b or forced ~= nil then return true end
    if b.capturing() then return false end
    return not onSince or getTimestampMs() - onSince > BRIDGE_GRACE_MS
end

-- Whether the vehicle shells must come off: the view is on and the bridge does not draw them. With
-- the bridge they stay on as the view goes on and off: every shell shown or hidden makes the game
-- build all the vehicle's models anew (ISnow_VehicleSnow.lua, TOGGLE_MIN), a hitch of some 300 ms at
-- each press of the key with a car in sight.
function VP.hideVehicleShells()
    if not VP.active() then return false end
    local b = bridge()
    if not b or forced ~= nil then return true end
    return not (b.vehicles and b.vehicles())
end

-- The bridge when breath and blow-off can be placed with Viewpoint's camera (the view is on and the
-- bridge is there): ISnowVP.project(x, y, z), then px(), py(), pscale(). Nil otherwise.
function VP.camera()
    if not VP.active() or forced ~= nil then return nil end
    return bridge()
end

-- Whether breath and blow-off must not be drawn: the view is on and there is no camera to place
-- them with.
function VP.hideScreenParticles()
    return VP.active() and VP.camera() == nil
end

-- The snow's depth for the bridge's SnowVolume: the ground cover and the squares cleared with a shovel
-- around player 0 (its scan leaves them bare).
local function handOverVolume(b)
    local player = getSpecificPlayer(0)
    if not player then return end
    local px, py = player:getX(), player:getY()
    b.snowClearedBegin()
    local cleared = ISnow.Cleared
    if cleared and cleared.count() > 0 then
        for key in pairs(cleared.squares) do
            local x, y = cleared.parse(key)
            if x and math.abs(x - px) <= VOLUME_RADIUS and math.abs(y - py) <= VOLUME_RADIUS then
                b.snowCleared(x, y)
            end
        end
    end
    b.snowDepth(ISnow.groundCover())
end

-- The decal modules' render handlers, run with Decals.toViewpoint so their buffers go to the bridge.
local function handOverDecals(b)
    b.decalsBegin()
    ISnow.Decals.toViewpoint = true
    for _, h in ipairs(ISnow.handlers) do
        if h.event == "RenderOpaqueObjectsInWorld" and h.module ~= "Viewpoint" then
            local ok, err = pcall(h.fn, 0)
            if not ok then
                stats.errors = stats.errors + 1
                lastError = h.module .. ": " .. tostring(err)
            end
        end
    end
    ISnow.Decals.toViewpoint = false
    stats.decals = b.decalsEnd()
    stats.handovers = stats.handovers + 1
    -- a bridge before 1.2 has no snow depth
    if b.snowDepth then
        local now = getTimestampMs()
        if now >= nextVolumeMs then
            nextVolumeMs = now + VOLUME_MS
            handOverVolume(b)
        end
    end
end

local function onWorld(playerIndex)
    if playerIndex ~= nil and playerIndex ~= 0 then return end
    stats.worldFrames = stats.worldFrames + 1
    quietFrames = 0
    drawn = true
    -- the bridge knows better (the event may still come while its view is off)
    if not bridge() then set(false) end
end

local function mapOpen()
    local map = ISWorldMap_instance
    return map ~= nil and map:isVisible()
end

local function onFrame()
    local b = bridge()
    if b then
        set(b.active())
        drawn = false
        if on and forced == nil then
            decalFrames = decalFrames - 1
            if decalFrames <= 0 then
                decalFrames = DECAL_FRAMES
                local ok, err = pcall(handOverDecals, b)
                if not ok then
                    ISnow.Decals.toViewpoint = false
                    stats.errors = stats.errors + 1
                    lastError = tostring(err)
                end
            end
        end
        return
    end
    if drawn then
        drawn = false
        return
    end
    if not isLoaded() or isGamePaused() or not getSpecificPlayer(0) or mapOpen() then return end
    quietFrames = quietFrames + 1
    if quietFrames >= OFF_FRAMES then
        stats.quietFrames = stats.quietFrames + 1
        set(true)
    end
end

function VP.stats()
    local b = bridge()
    local out = string.format("[ImmersiveSnow] Viewpoint: loaded=%s active=%s forced=%s bridge=%s switches=%d world frames=%d quiet frames=%d (now %d) decal hand-overs=%d (last %d) errors=%d",
        tostring(isLoaded()), tostring(VP.active()), tostring(forced), b and b.version() or "no", stats.switches,
        stats.worldFrames, stats.quietFrames, quietFrames, stats.handovers, stats.decals, stats.errors)
    if lastError then out = out .. "\n[ImmersiveSnow] last error: " .. lastError end
    print(out)
    if b then out = out .. "\n" .. tostring(b.stats()) end
    return out
end

-- Tests: looks the mod up again and starts over.
function VP.reset()
    loaded, on, forced, quietFrames, drawn, onSince = nil, false, nil, 0, false, nil
    apiChecked, apiOk = false, false
end

ISnow.listen("RenderOpaqueObjectsInWorld", "Viewpoint", onWorld)
ISnow.listen("OnPostRender", "Viewpoint", onFrame)
