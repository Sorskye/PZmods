-- Immersive Snow: snow on characters' clothes and on what they hold.
--
--  * Clothing: for every visible worn clothing item a body visual "shell" with the same mesh
--    (clothingItems/ISnow_CS_<key>.xml, item ISnow.CS_<key>, found by the item's model and texture in
--    ISnow_CharShellData.lua from tools/gen_char_snow.py; vanilla and modded clothes alike) drawn
--    with isnow_char_shell: the snow coating only, on the cloth, moving
--    with it; bare skin gets none. PopTemplateManager.populateCharacterModelSlot draws HumanVisual
--    body visuals after the clothes through addClothingItem, with ClothingItem.shader. The amount is
--    the body visual's tint (r = amount, g < 0.5 = debug view, g 1 = with icing: zombies only, b = how
--    many snow fields on top), which the shader gets as TintColour.
--    Hidden items and alternate models follow PopTemplateManager.isItemModelHidden / isItemModelAlt:
--    item A is hidden (alternate) if another worn item B has group:isHideModel(B, A) (isAltModel).
--  * Items in hand and on the body (back, belt): a runtime copy of the item's ModelScript with an isnow_item_<stage> shader (the
--    item's own look with snow over it), set per instance through the item's by-index model list,
--    which is never saved (a save never names a snow model, so removing the mod keeps the item's
--    model); put back when the item leaves the hands, the snow is gone, or the game loads.
--
-- Snow level 0..1 per character, in its ModData, per game hour:
--   + sqrt(snowIntensity) / CharSnowHours  outdoors (not in a vehicle) while it snows (the root:
--                                           light snowfall still shows on the clothes soon), up to
--                                           sqrt(snowIntensity) * CharSnowMax on players, at most a
--                                           full layer (moving about sheds what falls on them);
--                                           zombies: ZombieSnowHours, up to a full layer
--   - air temperature / 20 / CharSnowMeltHours  above 0 C, the temperature the character feels
--                                           (ClimateManager.getAirTemperatureForCharacter: indoors,
--                                           heat sources, vehicle heater); under a roof or in a
--                                           vehicle another 1 / CharSnowIndoorMeltHours (a cold
--                                           room above 0 C still melts it within half an hour)
--   - 1 / CharSnowBodyMeltHours             body heat, while no snow falls on it: indoors, in a
--                                           vehicle, or no snowfall (not zombies)
--   - precipitation / CharSnowRainMeltHours rain above 0 C
-- (all sandbox options, hours for a full layer: heavy snowfall, 20 C, above 0 C under a roof, body
-- heat, heavy rain)
-- The level is shown in steps of SHOW_STEP (every change rebuilds the character model).
-- The snow that melts on a player wets the clothes (ISnow_SnowWetness.lua).
--
-- Zombies get the same clothing shells (ISnow.opt("ZombieSnow")), see "Zombies" below.
-- In MP each client works out the level of its own players only and reports the look (steps of
-- SHOW_STEP, item stage) through the server to the other clients, see "Multiplayer" below.
--
-- Console: ISnow.CharSnow.set(level) sets the level, pin(level | nil) holds it (nil: back to the
-- weather), clothes(amount | "dbg" | nil) / hand(stage | nil) show a look directly (the weather
-- takes over at the next poll unless pinned), stats(). ISnow.cleanSave() before removing the mod
-- from a save (see "Taking the mod out of a save" at the end).

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_CompatViewpoint"

ISnow = ISnow or {}
local CS = {}
ISnow.CharSnow = CS

-- Project Viewpoint draws the world in 3D now and would draw the shells as plain copies of the
-- clothes in their tint, so none are shown, unless its submod's bridge draws them with their snow
-- (ISnow_CompatViewpoint.lua). The levels go on.
local function viewpoint() return ISnow.Viewpoint ~= nil and ISnow.Viewpoint.hideShells() end

local SHELL_PREFIX = "ISnow_CS_"
local amountOf = {}   -- [character] = amount (or "dbg") while the clothes carry snow
-- [local player] = ownMarkOf its HumanVisual when CS.clothes last built its shells; ownMarkOf (the
-- shell count in steps and the shell set) is set further down, with shownSteps and shellSig.
-- See pollCharacter.
local ownShown = {}
local ownMarkOf
-- Bags carry fewer snow fields on top than clothes (tint b scales the fields in the shader)
local BAG_FIELDS = 0.8
-- Tint g of the shells: zombies get the icing (1), players not (PLAYER_G: under the shader's ICED_G,
-- above its debug view); with darker snow (ISnow.darkSnow) the *_DARK ones (the shader's
-- DARK_PLAYER_G / DARK_ZOMBIE_G)
local PLAYER_G = 0.75
local ZOMBIE_G = 1
local PLAYER_G_DARK = 0.625
local ZOMBIE_G_DARK = 0.9375

local function tintG(chr)
    local dark = ISnow.darkSnow()
    if instanceof(chr, "IsoZombie") then return dark and ZOMBIE_G_DARK or ZOMBIE_G end
    return dark and PLAYER_G_DARK or PLAYER_G
end

local function shellItemType(xml) return "ISnow." .. string.sub(xml, #"ISnow_" + 1) end

local function startsWith(s, prefix) return s ~= nil and string.sub(s, 1, #prefix) == prefix end

-- What chr wears: { name = clothing item name, loc = body location (nil: none in the group, it
-- neither hides nor is hidden), vis = ItemVisual, bag }.
local function wornList(chr, group)
    local list = {}
    -- zombies have only item visuals, and so do other players on this client in MP (their worn items
    -- stay on their own client; SyncClothingPacket brings the item visuals, seen in game: none worn,
    -- the item visuals of all they wear); PopTemplateManager.isItemModelHidden takes their locations
    -- from the script items
    if instanceof(chr, "IsoZombie") or (instanceof(chr, "IsoPlayer") and not chr:isLocalPlayer()) then
        local ivs = chr:getItemVisuals()
        for i = 0, ivs:size() - 1 do
            local vis = ivs:get(i)
            local name = vis and vis:getClothingItemName()
            if name then
                local script = vis:getScriptItem()
                local loc = script and script:getBodyLocation()
                if loc and not group:getLocation(loc) then loc = nil end
                table.insert(list, { name = name, loc = loc, vis = vis, bag = startsWith(name, "Bag_") })
            end
        end
        return list
    end
    local worn = chr:getWornItems()
    for i = 0, worn:size() - 1 do
        local wi = worn:get(i)
        local item = wi:getItem()
        local vis = item and item:getVisual()
        -- the worn location (bags have no BodyLocation, only CanBeEquipped)
        local loc = wi:getLocation()
        if vis and loc and group:getLocation(loc) then
            table.insert(list, { name = vis:getClothingItemName(), loc = loc, vis = vis,
                bag = instanceof(item, "InventoryContainer") })
        end
    end
    return list
end

-- Shells are found by what a worn item really draws, not by its name, so modded items work when
-- their mesh is known (ISnow_CharShellData.lua has the vanilla meshes and those of the clothing mods
-- tools/gen_char_snow.py found): ISnow.CHAR_SHELL_MESHES["m:" / "f:" .. model] lists the shells with
-- that mesh for a male / female character, ISnow.CHAR_SHELLS[i] = { clothing item names (copies),
-- textures }.
local PAINTED = "*painted*"
local texIndexOf = {}   -- [shell index] = { [texture] = texture choice }

local function norm(path)
    return string.lower((string.gsub(path, "\\", "/")))
end

-- as norm_model in gen_char_snow.py: without "media/models_x/" and the file extension
local function normModel(path)
    local p = norm(path)
    p = string.gsub(p, "^media/models_x/", "")
    p = string.gsub(p, "^media/models/", "")
    p = string.gsub(p, "%.x$", "")
    p = string.gsub(p, "%.fbx$", "")
    p = string.gsub(p, "%.glb$", "")
    return p
end

local function shellTexIndex(i)
    local map = texIndexOf[i]
    if not map then
        map = {}
        for k, tex in ipairs(ISnow.CHAR_SHELLS[i][2]) do map[tex] = k - 1 end
        texIndexOf[i] = map
    end
    return map
end

-- The model (normalised, PAINTED for clothes painted on the body; nil: draws nothing) and texture a
-- worn item draws, as PopTemplateManager.addClothingItem picks them.
local function drawnLook(vis, female, alt)
    local ci = vis:getClothingItem()
    if not ci then return nil end
    local model = ci:getModel(female)
    if alt then
        local altModel = ci:getAltModel(female)
        if altModel and altModel ~= "" then model = altModel end
    end
    local painted = model == nil or model == ""
    if not painted and string.lower(model) == "null" then return nil end
    local choices, bases = ci:getTextureChoices(), ci:getBaseTextures()
    local list, idx
    if not painted and choices and choices:size() > 0 then
        list, idx = choices, vis:getTextureChoice()
    else
        list, idx = bases, vis:getBaseTexture()
    end
    if not list or list:size() == 0 then return nil end
    if not idx or idx < 0 or idx >= list:size() then idx = 0 end
    return painted and PAINTED or normModel(model), norm(list:get(idx))
end

-- Shell (index into ISnow.CHAR_SHELLS) and texture choice for a model and texture; nil if unknown.
-- Same mesh with a texture the shell does not have (a retexture mod): its first texture, used for
-- the opacity and the brightness of the cloth seen through the icing (the same UV layout, so the
-- seams and pockets match). Painted clothes need their own texture (it decides where the cloth is).
local function findShell(model, tex, female)
    local cands = ISnow.CHAR_SHELL_MESHES and ISnow.CHAR_SHELL_MESHES[(female and "f:" or "m:") .. model]
    if not cands then return nil end
    for _, i in ipairs(cands) do
        local k = shellTexIndex(i)[tex]
        if k then return i, k end
    end
    if model == PAINTED then return nil end
    return cands[1], 0
end

-- Inner layers that other worn items cover completely get no shell: vanilla still draws them
-- (BodyLocations.lua has no hide rule for them), and a shell is a whole extra model, for painted
-- clothes a whole body mesh, but it is inflated by only 1.5 mm, so under the covering item it is
-- never seen. [vanilla location] = sets of locations that cover it together (any one set is enough).
-- Only vanilla locations: a modded location may be anything. Checked in game by comparing
-- screenshots with and without these shells.
local COVERED_BY = {}
do
    local legs = { "base:pants", "base:pants_skinny", "base:pantsextra", "base:boilersuit", "base:fullsuit",
        "base:fullsuithead" }
    local hips = { "base:shortpants", "base:shortsshort", "base:dress", "base:longdress" }
    local chest = { "base:tshirt", "base:shirt", "base:shortsleeveshirt", "base:sweater", "base:sweaterhat",
        "base:dress", "base:longdress", "base:boilersuit", "base:fullsuit", "base:fullsuithead" }
    local function sets(list, with)
        local out = {}
        for _, loc in ipairs(list) do out[#out + 1] = with and { loc, with } or { loc } end
        return out
    end
    COVERED_BY["base:socks"] = sets(legs, "base:shoes")
    local bottom = sets(legs)
    for _, s in ipairs(sets(hips)) do bottom[#bottom + 1] = s end
    COVERED_BY["base:underwearbottom"] = bottom
    COVERED_BY["base:underweartop"] = sets(chest)
end
CS.skipCovered = true   -- console: false draws the covered shells too (for comparing)

local locNames = {}   -- [location] = lower-case name
local function locName(loc)
    if not loc then return nil end
    local name = locNames[loc]
    if not name then
        name = string.lower(tostring(loc))
        locNames[loc] = name
    end
    return name
end

-- Jewellery gets no snow: rings, watches and bracelets, piercings and earrings are a few pixels on
-- screen, and every shell is a whole extra model. Vanilla locations (BodyLocations.lua), by the
-- ItemBodyLocation values where the game has them.
local NO_SNOW = {}
do
    local fallback = { "base:left_ringfinger", "base:right_ringfinger", "base:leftwrist", "base:rightwrist",
        "base:ears", "base:eartop", "base:nose", "base:bellybutton" }
    for _, name in ipairs(fallback) do NO_SNOW[name] = true end
    local ids = { "LEFT_RING_FINGER", "RIGHT_RING_FINGER", "LEFT_MIDDLE_FINGER", "RIGHT_MIDDLE_FINGER",
        "LEFT_WRIST", "RIGHT_WRIST", "EARS", "EAR_TOP", "NOSE", "BELLY_BUTTON" }
    local enum = ItemBodyLocation
    for _, id in ipairs(ids) do
        local v = enum and enum[id]
        if v then NO_SNOW[locName(v)] = true end
    end
end

-- Small worn items, no snow in the low-end mode (ISnow.opt("CharSnowSmallItems") off): a little
-- of the character on screen each, but every shell is a whole extra model with a noise shader, and
-- gloves, socks, belt textures, ties, bandages and make-up are painted on the body (in vanilla 20 of
-- the 26 gloves, all socks and belts), so each of those is a whole body mesh. Vanilla locations
-- (BodyLocations.lua) by their ItemBodyLocation names: gloves, socks, belts and holsters, neck (ties,
-- chokers, necklaces), glasses and eye patches, make-up, bandages and wounds, knee and elbow pads,
-- shin pad and gaiter textures, ankle holster, tail.
local SMALL = {}
do
    local names = { "hands", "handsleft", "handsright", "socks", "belt", "beltextra", "neck", "neck_texture",
        "necklace", "necklace_long", "eyes", "lefteye", "righteye", "makeup_fullface", "makeup_eyes",
        "makeup_eyesshadow", "makeup_lips", "bandage", "wound", "knee_left", "knee_right", "elbow_left",
        "elbow_right", "calf_left_texture", "calf_right_texture", "gaiter_left", "gaiter_right",
        "ankleholster", "tail" }
    for _, name in ipairs(names) do SMALL["base:" .. name] = true end
    local ids = { "HANDS", "HANDS_LEFT", "HANDS_RIGHT", "SOCKS", "BELT", "BELT_EXTRA", "NECK", "NECK_TEXTURE",
        "NECKLACE", "NECKLACE_LONG", "EYES", "LEFT_EYE", "RIGHT_EYE", "MAKE_UP_FULL_FACE", "MAKE_UP_EYES",
        "MAKE_UP_EYES_SHADOW", "MAKE_UP_LIPS", "BANDAGE", "WOUND", "KNEE_LEFT", "KNEE_RIGHT", "ELBOW_LEFT",
        "ELBOW_RIGHT", "CALF_LEFT_TEXTURE", "CALF_RIGHT_TEXTURE", "GAITER_LEFT", "GAITER_RIGHT",
        "ANKLE_HOLSTER", "TAIL" }
    local enum = ItemBodyLocation
    for _, id in ipairs(ids) do
        local v = enum and enum[id]
        if v then SMALL[locName(v)] = true end
    end
end
CS.SMALL = SMALL   -- tests

-- [character] = whether its shells were made with the small items (ISnow.opt("CharSnowSmallItems")
-- then): a switch of the low-end mode rebuilds them
local smallOf = {}

-- Is worn item a covered by the others in list (COVERED_BY)?
local function isCovered(a, list)
    local rules = COVERED_BY[locName(a.loc)]
    if not rules or not CS.skipCovered then return false end
    local worn = {}
    for _, b in ipairs(list) do
        if b ~= a and b.loc then worn[locName(b.loc)] = true end
    end
    for _, set in ipairs(rules) do
        local all = true
        for _, loc in ipairs(set) do
            if not worn[loc] then all = false; break end
        end
        if all then return true end
    end
    return false
end

-- Caches for shellsFor (every zombie rebuild runs it; the rules and scripts do not change in a
-- game): whether location b hides / alternates location a of a group (BodyLocations.lua), and the
-- shell of what a clothing item draws, by clothing item, sex, alternate model and the visual's
-- texture choice and base texture (drawnLook takes one of them).
local pairRules = {}  -- [group] = { [b name] = { [a name] = { hide, alt } } }
local looks = {}      -- [ClothingItem] = { [key] = { model?, shell, texture } }

local function rulesOf(group, b, a)
    local byGroup = pairRules[group]
    if not byGroup then
        byGroup = {}
        pairRules[group] = byGroup
    end
    local bn, an = locName(b), locName(a)
    local byB = byGroup[bn]
    if not byB then
        byB = {}
        byGroup[bn] = byB
    end
    local r = byB[an]
    if not r then
        r = { group:isHideModel(b, a) and true or false, group:isAltModel(b, a) and true or false }
        byB[an] = r
    end
    return r[1], r[2]
end

-- Shell (index into ISnow.CHAR_SHELLS) and texture choice of worn item visual vis; whether it
-- draws a model at all.
local function shellOf(vis, female, alt)
    local ci = vis:getClothingItem()
    if not ci then return false end
    local tc, bt = vis:getTextureChoice() or -1, vis:getBaseTexture() or -1
    local key = ((female and 2 or 0) + (alt and 1 or 0)) * 16777216 + (tc + 1) * 4096 + (bt + 1)
    local byItem = looks[ci]
    if not byItem then
        byItem = {}
        looks[ci] = byItem
    end
    local r = byItem[key]
    if not r then
        local model, tex = drawnLook(vis, female, alt)
        local i, k
        if model then i, k = findShell(model, tex, female) end
        r = { model ~= nil, i, k }
        byItem[key] = r
    end
    return r[1], r[2], r[3]
end

-- HumanVisual.save writes the number of body visuals as a byte and load reads it back signed
-- (bytecode 42.21): over 127 the rest of the character is read from the wrong place. So a character
-- gets at most MAX_SHELLS shells, and none once it has MAX_BODY_VISUALS body visuals with the
-- others (zombie wounds and the like).
local MAX_SHELLS = 100
local MAX_BODY_VISUALS = 120
CS.MAX_SHELLS, CS.MAX_BODY_VISUALS = MAX_SHELLS, MAX_BODY_VISUALS   -- tests

-- Shell clothing item name -> its number of textures (ISnow.CHAR_SHELLS), made on first use.
local shellTextures = nil
local function shellTextureCount(name)
    if not shellTextures then
        shellTextures = {}
        for _, s in ipairs(ISnow.CHAR_SHELLS or {}) do
            for _, xml in ipairs(s[1]) do shellTextures[xml] = #s[2] end
        end
    end
    return shellTextures[name]
end

-- Whether hv has a shell this version does not make: a clothing item it no longer has, or a texture
-- choice outside its textures. Saves from before 0.5.2 Patch 1 hold painted shells with up to 664
-- textures (ISnow_CS_Painted1..10, now split into PaintedA1.. of up to 127 each, see MAX_CHOICES in
-- gen_char_snow.py), whose texture choice the save had cut to a byte: another texture's snow.
local function hasStaleShells(hv)
    local bv = hv:getBodyVisuals()
    for i = 0, bv:size() - 1 do
        local v = bv:get(i)
        local name = v:getClothingItemName()
        if startsWith(name, SHELL_PREFIX) then
            local n = shellTextureCount(name)
            local k = v:getTextureChoice()
            if not n or not k or k < 0 or k >= n then return true end
        end
    end
    return false
end
CS.hasStaleShells = hasStaleShells

-- Shell clothing items for what chr wears and the game draws (clothing item name -> { texture
-- choice, fields }); plus worn items without a shell. Clothes painted on the body (no mesh) get the
-- body mesh with their texture; the shader puts snow only where it is opaque.
local function shellsFor(chr, small)
    local group = chr:getBodyLocationGroup()
    local list = wornList(chr, group)
    local female = chr:isFemale()
    local shells, missing, slotsUsed = {}, {}, {}
    local count = 0
    if small == nil then small = ISnow.opt("CharSnowSmallItems") end
    for _, a in ipairs(list) do
        local hidden, alt = false, false
        for _, b in ipairs(list) do
            if b ~= a and a.loc and b.loc then
                local h, al = rulesOf(group, b.loc, a.loc)
                if h then hidden = true end
                if al then alt = true end
            end
        end
        local ln = locName(a.loc)
        if a.name and not hidden and not NO_SNOW[ln] and not (SMALL[ln] and not small) and not isCovered(a, list) then
            local model, i, k = shellOf(a.vis, female, alt)
            if model and not i then
                table.insert(missing, a.name)
            elseif i then
                -- one body visual per clothing item name: items on the same shell take its copies
                local names = ISnow.CHAR_SHELLS[i][1]
                local n = (slotsUsed[i] or 0) + 1
                if count >= MAX_SHELLS then
                    table.insert(missing, a.name .. " (shell limit)")
                elseif names[n] then
                    slotsUsed[i] = n
                    count = count + 1
                    shells[names[n]] = { texture = k, fields = a.bag and BAG_FIELDS or 1 }
                else
                    table.insert(missing, a.name .. " (no free copy)")
                end
            end
        end
    end
    return shells, missing
end

local function removeShells(hv)
    local bv = hv:getBodyVisuals()
    local names = {}
    for i = 0, bv:size() - 1 do
        local name = bv:get(i):getClothingItemName()
        if startsWith(name, SHELL_PREFIX) then table.insert(names, name) end
    end
    for _, name in ipairs(names) do hv:removeBodyVisualFromItemType(shellItemType(name)) end
    return #names
end

-- Gives the shells chr has the amount (keeping each one's fields, tint b); how many it has.
local function retint(chr, amount)
    local hv, g = chr:getHumanVisual(), tintG(chr)
    local bv = hv:getBodyVisuals()
    local n = 0
    for i = 0, bv:size() - 1 do
        local v = bv:get(i)
        if startsWith(v:getClothingItemName(), SHELL_PREFIX) then
            local old = v:getTint()
            v:setTint(ImmutableColor.new(amount, g, old and old:getBlueFloat() or 1))
            n = n + 1
        end
    end
    return n
end

local function isLocal(chr)
    return instanceof(chr, "IsoPlayer") and chr:isLocalPlayer()
end

-- [local player] = what it wore (wornKey) when its shells were built. The poll builds them again
-- when that changed, whatever event was missed (caxradar, 2026-10-04: a duffel bag's snow stayed
-- behind the character after it was taken off). ISUnequipAction:perform fires OnClothingUpdated
-- before complete() takes the item off (IsoGameCharacter: act.perform(), then act.complete(), 42.21);
-- in SP complete() fires it again, in MP complete() runs on the server and the client hears of it
-- only from the server's clothing sync; and a mod may change clothes without the event at all.
local wornKeyOf = {}
local function wornKey(chr)
    local worn = chr:getWornItems()
    local parts = {}
    for i = 0, worn:size() - 1 do
        local wi = worn:get(i)
        local item = wi:getItem()
        parts[#parts + 1] = tostring(wi:getLocation()) .. "=" .. tostring(item and item:getID())
    end
    return table.concat(parts, ",")
end

-- Snow coating amount 0..1 on chr's clothes ("dbg": camera-frame normals; nil removes it).
-- sameClothes: the caller knows chr wears what its shells were made for, so a new amount only
-- retints them (no shellsFor, no new body visuals; not when the low-end mode changed which small
-- items get shells); the model is rebuilt all the same.
function CS.clothes(amount, chr, sameClothes)
    chr = chr or getPlayer()
    local hv = chr:getHumanVisual()
    local small = ISnow.opt("CharSnowSmallItems")
    if sameClothes and type(amount) == "number" and type(amountOf[chr]) == "number" and smallOf[chr] == small then
        local n = retint(chr, amount)
        if n > 0 then
            amountOf[chr] = amount
            if ownMarkOf and isLocal(chr) then ownShown[chr] = ownMarkOf(hv) end
            chr:resetModel()
            return "retinted " .. n
        end
    end
    local removed = removeShells(hv)
    amountOf[chr] = amount
    smallOf[chr] = small
    local added, missing = 0, {}
    if amount then
        local shells
        shells, missing = shellsFor(chr, small)
        for shell, s in pairs(shells) do
            local tint = amount == "dbg" and ImmutableColor.new(1, 0, 1) or ImmutableColor.new(amount, tintG(chr), s.fields)
            if hv:getBodyVisuals():size() >= MAX_BODY_VISUALS then
                table.insert(missing, shellItemType(shell) .. " (body visual limit)")
            else
                local v = hv:addBodyVisualFromItemType(shellItemType(shell))
                if v then
                    v:setTint(tint)
                    v:setTextureChoice(s.texture)
                    added = added + 1
                else
                    table.insert(missing, "no item " .. shellItemType(shell))
                end
            end
        end
    end
    wornKeyOf[chr] = amount and isLocal(chr) and wornKey(chr) or nil
    if ownMarkOf and isLocal(chr) then ownShown[chr] = ownMarkOf(hv) end
    -- now, for zombies too (resetModelNextFrame left them without the shells in game); pollZombies
    -- rebuilds at most ZOMBIE_REBUILDS per poll
    chr:resetModel()
    return "removed " .. removed .. ", added " .. added ..
        (#missing > 0 and (", no shell for: " .. table.concat(missing, ", ")) or "")
end

-- Worn clothes changed: the shells follow.
local function onClothingUpdated(chr)
    if chr and amountOf[chr] then CS.clothes(amountOf[chr], chr) end
end
Events.OnClothingUpdated.Add(onClothingUpdated)

-- Script texts that rebuild ms under a new name: every loaded body as it is (attachment blocks
-- such as Bip01_Prop1/Prop2 place the item in the hand, and ModelScript.LoadAttachment updates an
-- attachment by id, so later bodies override earlier ones as at boot), then the shader alone.
local function modelScriptTexts(ms, name, shader)
    local bodies = ms:getLoadedScriptBodies()
    if not bodies or bodies:size() == 0 then return nil end
    local texts = {}
    for i = 0, bodies:size() - 1 do
        local body = bodies:get(i)
        local open = string.find(body, "{", 1, true)
        if open then table.insert(texts, "model " .. name .. "\n" .. string.sub(body, open)) end
    end
    if #texts == 0 then return nil end
    table.insert(texts, "model " .. name .. "\n{\n    shader = " .. shader .. ",\n}\n")
    return texts
end

local SNOW_ITEM_PREFIX = "ISnowItem_"

local function isSnowModel(name)
    return type(name) == "string" and string.find(name, SNOW_ITEM_PREFIX, 1, true) ~= nil
end

local function snowModel(modelName, id)
    if isSnowModel(modelName) then return nil, "already a snow model " .. modelName end
    local sm = getScriptManager()
    local ms = sm:getModelScript(modelName)
    if not ms then return nil, "no model script " .. tostring(modelName) end
    -- some modded model scripts have no name (getFullType "<module>.null", as the KI5 Containers!
    -- bodies): those go by the name they were looked up by, or they would all share one copy
    local full = ms:getFullType()
    if ms:getName() == nil then
        full = string.find(modelName, ".", 1, true) and modelName or (ms:getModule():getName() .. "." .. modelName)
    end
    local name = SNOW_ITEM_PREFIX .. string.gsub(full, "[^%w]", "_") .. "_" .. id
    if not sm:getModelScript(name) then
        local texts = modelScriptTexts(ms, name, (ISnow.darkSnow() and "isnow_itemd_" or "isnow_item_") .. id)
        if not texts then return nil, "no script text for " .. full end
        local copy = ModelScript.new()
        copy:setModule(ms:getModule())
        copy:InitLoadPP(name)
        for _, text in ipairs(texts) do copy:Load(name, text) end
        sm:addModelScript(copy)
    end
    return ms:getModule():getName() .. "." .. name
end

-- An item's model in hand comes from (bytecode, B42): HandWeapon.getWeaponSprite = the entry
-- modelIndex of weaponSpritesByIndex when that list is set and modelIndex ~= -1, else the
-- weaponSprite field; InventoryItem.getStaticModel = ModData.staticModel, else
-- staticModelsByIndex[modelIndex], else the script's. Attached to the body (back, belt)
-- ModelManager draws getStaticModel, for a HandWeapon: weaponSpritesByIndex[modelIndex], else its
-- staticModel field when set, else weaponSprite.
-- The snow model goes into a copy of that by-index list made for this item only (the item's list
-- is the script's, shared). The lists are never saved; weaponSprite, ModData.staticModel and
-- modelIndex are. So no saved field ever names a snow model (with the mod removed such an item
-- would have no model at all, seen in game): only modelIndex may change, from -1 to an index that
-- points into a list only while the mod runs. Without the lists modelIndex only picks the icon from
-- IconsForTexture (InventoryItem.synchWithVisual), so it is set to the texture index the item's
-- visual already takes its icon from; an item that would look different with the index (world
-- model from worldStaticModelsByIndex, a texture-dependent icon without a visual) gets no snow.
local KEY_INDEX = "ISnowOrigIndex"     -- modelIndex before the swap, while it differs
-- Older versions swapped saved fields; kept to repair their saves (restoreLegacy):
local KEY_ORIG = "ISnowOrigModel"      -- original model name while the item showed snow
local KEY_KIND = "ISnowOrigKind"       -- "sprite" (weaponSprite field), "list" or "static" (ModData)
local KEY_STATIC = "ISnowOrigStatic"   -- ModData.staticModel before the swap ("" when there was none)
local KEY_WSTATIC = "ISnowOrigWStatic" -- "sprite" weapons: their own staticModel field ("" when none)
local swapped = {}   -- [item] = key (stageKey) of the snow it shows
local tried = {}     -- [item] = key last asked for, shown or not
local itemOwner = {} -- [item] = character whose syncItems last had it
-- [item] = { list = before the swap, copy = ours, idx = modelIndex set, id/onBody = the stage
-- asked for, full = the snow model shown, index/hand/static = what the getters give (hookWeapons) }
local origList = {}

local function isWeapon(item)
    return instanceof(item, "HandWeapon")
end

-- Weapons without their own list draw the hand model on the body too once they have one, so the
-- body gets its own swap (with the body model).
local function stageKey(item, id, onBody)
    if not id then return nil end
    return (onBody and isWeapon(item)) and (id .. "@body") or id
end

local function modelList(item)
    if isWeapon(item) then return item:getWeaponSpritesByIndex() end
    return item:getStaticModelsByIndex()
end

local function setModelList(item, list)
    if isWeapon(item) then item:setWeaponSpritesByIndex(list) else item:setStaticModelsByIndex(list) end
end

-- The model item shows now (not swapped), in the hand or on the body.
local function baseModel(item, onBody)
    local list, idx = modelList(item), item:getModelIndex()
    if list and idx ~= -1 and idx < list:size() then return list:get(idx) end
    if isWeapon(item) then
        return onBody and item:getStaticModel() or item:getWeaponSprite()
    end
    return item:getStaticModel()
end

-- modelIndex for the swap, nil when a new one would change how the item looks without the mod.
local function swapIndex(item)
    local idx = item:getModelIndex()
    if idx ~= -1 then return idx end
    if item:getWorldStaticModelsByIndex() then return nil end
    local icons = item:getIconsForTexture()
    if not icons then return 0 end
    local vis = item:getVisual()
    if not vis then return nil end
    local k = vis:getBaseTexture()
    if k <= -1 then k = vis:getTextureChoice() end
    if k > -1 and k < icons:size() then return k end
    return nil
end

-- Puts back what older versions left in saved fields.
local function restoreLegacy(item)
    local md = item:getModData()
    local orig, kind = md[KEY_ORIG], md[KEY_KIND]
    if orig == nil then return end
    if kind == "static" then
        local prev = md[KEY_STATIC]
        md.staticModel = (prev ~= nil and prev ~= "") and prev or nil
    elseif kind ~= "list" and isWeapon(item) then
        item:setWeaponSprite(orig)
        local ws = md[KEY_WSTATIC]
        if ws ~= nil and ws ~= "" then item:setStaticModel(ws) end
    end
    md[KEY_ORIG], md[KEY_KIND], md[KEY_STATIC], md[KEY_WSTATIC] = nil, nil, nil, nil
end

-- Whether the model of item is still the swap made by setItemStage (another mod may have set its
-- own list or index since).
local function swapIntact(item)
    local o = origList[item]
    return o ~= nil and modelList(item) == o.copy and item:getModelIndex() == o.idx
end

-- Puts back the model from before the swap, only what is still ours: a list or index another mod
-- set meanwhile stays.
local function restoreItem(item)
    local o = origList[item]
    local md = item:getModData()
    local idx = md[KEY_INDEX]
    if o then
        if modelList(item) == o.copy then setModelList(item, o.list) end
        if idx ~= nil and item:getModelIndex() == o.idx then item:setModelIndex(idx) end
    elseif idx ~= nil then
        item:setModelIndex(idx)
    end
    md[KEY_INDEX] = nil
    origList[item] = nil
    swapped[item] = nil
end

-- A snow model name another mod copied from the getters into a saved field or the item's list
-- (they return the swap while it shows): the script's model again. Without this the item would
-- keep that model (the snow of whatever item it came from) for good.
local function repairItem(item)
    local md = item:getModData()
    if isSnowModel(md.staticModel) then md.staticModel = nil end
    local script = item:getScriptItem()
    if not script then return end
    if isWeapon(item) then
        local list = item:getWeaponSpritesByIndex()
        local fromList = list ~= nil and item:getModelIndex() ~= -1
        if not fromList and isSnowModel(item:getWeaponSprite()) then item:setWeaponSprite(script:getWeaponSprite()) end
        if not fromList and isSnowModel(item:getStaticModel()) then item:setStaticModel(script:getStaticModel()) end
    end
    local list = modelList(item)
    if list then
        for i = 0, list:size() - 1 do
            if isSnowModel(list:get(i)) then
                setModelList(item, isWeapon(item) and script:getWeaponSpritesByIndex() or script:getStaticModelsByIndex())
                break
            end
        end
    end
end

-- Shows snow stage id (nil: none) on item's model in the hand or, onBody, attached to the body.
local function setItemStageNow(item, id, onBody)
    restoreLegacy(item)
    local key = stageKey(item, id, onBody)
    tried[item] = key
    -- another mod set the model of item while it showed snow, past the hooks (from Java, or before
    -- they were in place): only what is still ours goes back (restoreItem), and the snow goes on the
    -- model that mod set
    if swapped[item] ~= nil and not swapIntact(item) then restoreItem(item) end
    -- no snow asked for and none shown this session: only a swap loaded from a save (KEY_INDEX) to
    -- put back (restoreSaved; before 0.5.2 Patch 1 it returned here and left such items swapped)
    if swapped[item] == key and (key ~= nil or item:getModData()[KEY_INDEX] == nil) then
        return key and baseModel(item, onBody)
    end
    restoreItem(item)
    repairItem(item)
    if not id then return nil end
    if not isWeapon(item) and item:getModData().staticModel ~= nil then return nil, "ModData.staticModel set" end
    local idx = swapIndex(item)
    if not idx then return nil, "no model index to use" end
    local orig = baseModel(item, onBody)
    if not orig or orig == "" then return nil, "no model" end
    local full, err = snowModel(orig, id)
    if not full then return nil, err end
    local list = modelList(item)
    local n = list and list:size() or 0
    local copy = ArrayList.new()
    for i = 0, math.max(idx + 1, n) - 1 do copy:add(i < n and list:get(i) or full) end
    copy:set(idx, full)
    origList[item] = { list = list, copy = copy, idx = idx, id = id, onBody = onBody, full = full,
        index = item:getModelIndex(), hand = isWeapon(item) and item:getWeaponSprite() or nil,
        static = item:getStaticModel() }
    if item:getModelIndex() ~= idx then
        item:getModData()[KEY_INDEX] = item:getModelIndex()
        item:setModelIndex(idx)
    end
    setModelList(item, copy)
    swapped[item] = key
    return full
end

-- Weapons in other mods' Lua (see hookWeapons). ownCalls > 0 while our own code runs: the
-- hooks pass its calls straight on.
local ownCalls = 0

local function setItemStage(item, id, onBody)
    ownCalls = ownCalls + 1
    local ok, a, b = pcall(setItemStageNow, item, id, onBody)
    ownCalls = ownCalls - 1
    if not ok then error(a) end
    return a, b
end

-- Whether item shows snow by a swap no longer intact, asked from outside setItemStage: as our own
-- call, past the weapon hooks (their getters give what was before the swap, so a weapon showing
-- snow read as not intact and was set again at every poll).
local function swapBroken(item)
    if swapped[item] == nil then return false end
    ownCalls = ownCalls + 1
    local ok, intact = pcall(swapIntact, item)
    ownCalls = ownCalls - 1
    return not (ok and intact)
end

-- Weapon mods pick a weapon's model in Lua (attachments, folding stocks, model replacements: Vanilla
-- Firearms Expansion, Totally's Vanilla Firearms Replacement) by reading and setting the same
-- fields the swap uses. Swapped, the getters would give them a snow model (another weapon showing
-- it when such a mod passes it on, the name saved in weaponSprite), and a model they set would be
-- hidden behind the swap. So for a swapped weapon the Lua getters (HandWeapon's class metatable;
-- the engine calls the Java methods directly) give what the weapon had before the swap, and a Lua
-- setter puts the weapon back first, sets what that mod asked for and swaps again: the snow goes on
-- the mod's model. The owner's model is rebuilt only when the snow model changes (a mod that sets
-- the same model every tick rebuilds nothing).
local WEAPON_GETTERS = { "getWeaponSprite", "getStaticModel", "getWeaponSpritesByIndex", "getModelIndex" }
local WEAPON_SETTERS = { "setWeaponSprite", "setStaticModel", "setWeaponSpritesByIndex", "setModelIndex" }
local weaponHooked = false

-- Lua setter f called on a swapped item (o = its origList entry): f on the model from before the
-- swap, then the same snow on what f set.
local function setUnderSnow(f, item, o, ...)
    ownCalls = ownCalls + 1
    pcall(restoreItem, item)
    ownCalls = ownCalls - 1
    local fok, r = pcall(f, item, ...)
    local ok, full = pcall(setItemStage, item, o.id, o.onBody)
    if not ok then full = nil end
    if full ~= o.full then
        local chr = itemOwner[item]
        if chr then chr:resetModelNextFrame() end
    end
    if not fok then error(r) end
    return r
end

local function hookWeapons()
    local mt = __classmetatables and HandWeapon and __classmetatables[HandWeapon.class]
    local index = mt and mt.__index
    if not index or not index.getWeaponSprite then return false end
    -- wrapped anew on a reload, around the originals
    local orig = index.ISnowOrigMethods or {}
    index.ISnowOrigMethods = orig
    for _, list in ipairs({ WEAPON_GETTERS, WEAPON_SETTERS }) do
        for _, m in ipairs(list) do
            if not orig[m] then orig[m] = index[m] end
            if not orig[m] then return false end
        end
    end
    local before = {
        getWeaponSprite = function(o) return o.hand end,
        getStaticModel = function(o) return o.static end,
        getWeaponSpritesByIndex = function(o) return o.list end,
        getModelIndex = function(o) return o.index end,
    }
    for _, m in ipairs(WEAPON_GETTERS) do
        local f, get = orig[m], before[m]
        index[m] = function(item, ...)
            local o = ownCalls == 0 and origList[item]
            if o and swapped[item] then return get(o) end
            return f(item, ...)
        end
    end
    for _, m in ipairs(WEAPON_SETTERS) do
        local f = orig[m]
        index[m] = function(item, ...)
            local o = ownCalls == 0 and swapped[item] and origList[item]
            if o then return setUnderSnow(f, item, o, ...) end
            return f(item, ...)
        end
    end
    weaponHooked = true
    return true
end
if not hookWeapons() then
    print("[ImmersiveSnow] HandWeapon model methods not hooked: weapon mods that set models in Lua may see snow models")
end

-- Gives the item in the primary hand the snow stage id ("s1".."s6", "dbgview"; nil restores it).
function CS.hand(id, chr)
    chr = chr or getPlayer()
    local item = chr:getPrimaryHandItem()
    if not item then return "nothing in the primary hand" end
    local model, err = setItemStage(item, id, false)
    chr:resetEquippedHandsModels()
    return item:getFullType() .. " -> " .. tostring(model or err)
end

function CS.stats(chr)
    chr = chr or getPlayer()
    local out = { "amount: " .. tostring(amountOf[chr]) }
    local bv = chr:getHumanVisual():getBodyVisuals()
    for i = 0, bv:size() - 1 do
        local v = bv:get(i)
        if startsWith(v:getClothingItemName(), SHELL_PREFIX) then
            table.insert(out, "shell " .. v:getClothingItemName() .. " clothing=" .. tostring(v:getClothingItem() ~= nil))
        end
    end
    local shells, missing = shellsFor(chr)
    local want = {}
    for s in pairs(shells) do table.insert(want, s) end
    table.insert(out, "for worn: " .. table.concat(want, ", "))
    if #missing > 0 then table.insert(out, "no shell: " .. table.concat(missing, ", ")) end
    local item = chr:getPrimaryHandItem()
    if item then
        table.insert(out, "hand: " .. item:getFullType() .. " static=" .. tostring(item:getStaticModel()) ..
            (instanceof(item, "HandWeapon") and (" sprite=" .. tostring(item:getWeaponSprite())) or ""))
    end
    return table.concat(out, "\n")
end

-- Snow building up with the weather ------------------------------------------

local POLL_TICKS = 60
local SHOW_STEP = 0.1
local MIN_LEVEL = 0.05
local MELT_REF_TEMP = 20       -- CharSnowMeltHours is the time a full layer takes at this temperature
local CATCHUP_HOURS = 2
local KEY_LEVEL = "ISnowCharLevel"
local KEY_AT = "ISnowCharAt"
local ITEM_STAGES = { "s1", "s2", "s3", "s4", "s5", "s6" }   -- isnow_item_<stage>, as gen_char_snow.py

local pinned = {}   -- [character] = level set with CS.pin
local shown = {}    -- [character] = amount shown on the clothes (false: none)
local itemStageOf = {}   -- [local player] = snow stage its items got at the last poll (nil: none)
local stats = { polls = 0, errors = 0, asleep = 0 }
local lastError = nil

local function clamp01(x) return math.max(0, math.min(1, x)) end

-- Index into ITEM_STAGES of the snow items show at level (0: none).
local function itemStageIndex(level)
    if level < MIN_LEVEL then return 0 end
    return math.max(1, math.min(#ITEM_STAGES, math.ceil(level * #ITEM_STAGES)))
end

-- Snow falling on and melting off a character per game hour: outside (under the sky, not in a
-- vehicle), at air temperature temp (that of its square: ClimateManager.getAirTemperatureForCharacter
-- is the square's air, a room, heat sources, and a vehicle's heater); bodyHeat: the living melt
-- some while no snow falls on them (a cold house or car in a days-long blizzard included).
-- opt: where the option values come from, ISnow.opt (default) or ISnow.worldOpt (see updateLevel).
local function snowRates(clim, outside, temp, bodyHeat, opt)
    opt = opt or ISnow.opt
    local snowing = clim:isSnowing()
    local gain, melt = 0, 0
    if snowing and outside then
        local hours = opt(bodyHeat and "CharSnowHours" or "ZombieSnowHours")
        gain = math.sqrt(math.max(0, clim:getSnowIntensity())) / math.max(0.05, hours)
    end
    if temp > 0 then
        melt = temp / MELT_REF_TEMP / math.max(0.05, opt("CharSnowMeltHours"))
        if not outside then melt = melt + 1 / math.max(0.05, opt("CharSnowIndoorMeltHours")) end
        if clim:isRaining() and outside then
            melt = melt + clim:getPrecipitationIntensity() / math.max(0.05, opt("CharSnowRainMeltHours"))
        end
    end
    if bodyHeat and not (snowing and outside) then melt = melt + 1 / math.max(0.05, opt("CharSnowBodyMeltHours")) end
    return gain, melt
end

CS.snowRates = snowRates   -- console / tests: gain, melt per game hour

-- The most snow falling snow leaves on a player: sqrt(snowIntensity) * CharSnowMax (by the root, as
-- the build-up), at most a full layer: as much as falls on them shaken off by moving about. At 1.5 a
-- full layer from intensity 0.44 up, 0.75 at 0.25. Snow above it (from heavier snowfall before) is
-- kept and melts as usual. Zombies stand still: a full layer.
local function snowCap(clim, opt)
    opt = opt or ISnow.opt
    return clamp01(math.sqrt(math.max(0, clim:getSnowIntensity())) * opt("CharSnowMax"))
end

CS.snowCap = snowCap

local function snowRate(clim, outside, temp, bodyHeat)
    local gain, melt = snowRates(clim, outside, temp, bodyHeat)
    return gain - melt
end

-- New snow level of chr at game time now (hours), the game hours since the last update and the
-- part of a full layer that melted meanwhile. In MP at the sandbox's rates, not this player's own
-- (Options > Mods): the level is what the others see (reportLook) and its melt wets the clothes.
-- With CharSnow off in the sandbox (the server's in MP; in SP this player's own when they replace
-- the sandbox) no snow builds up at all: none to see, to shake off (ISnow_ShakeSnow.lua) or to melt
-- into the clothes; snow left from before goes without wetting them. The time still passes for the
-- falling snow and the walking (ISnow_SnowWetness.lua). Only hidden by this player (Options > Mods)
-- it builds up and wets as usual.
local function snowBuildsUp()
    if not isClient() and ISnow.useOwn() then
        local own = ISnow.ownOpt("CharSnow")
        if own ~= nil then return own end
    end
    return ISnow.worldOpt("CharSnow")
end

local function updateLevel(chr, now)
    local md = chr:getModData()
    local level, at = md[KEY_LEVEL] or 0, md[KEY_AT]
    local dt, melted = 0, 0
    if at and now > at then dt = math.min(now - at, CATCHUP_HOURS) end
    if pinned[chr] then
        level, dt = pinned[chr], 0
    elseif not snowBuildsUp() then
        level = 0
    elseif dt > 0 then
        local clim = getClimateManager()
        local opt = isClient() and ISnow.worldOpt or ISnow.opt
        local outside = ISnow.snowFallsOnCharacter(chr)
        local gain, melt = snowRates(clim, outside, clim:getAirTemperatureForCharacter(chr), true, opt)
        local grown = math.min(1, level + gain * dt)
        if gain > 0 then grown = math.max(level, math.min(grown, snowCap(clim, opt))) end
        melted = math.min(grown, melt * dt)
        level = clamp01(grown - melted)
    end
    md[KEY_LEVEL] = level
    md[KEY_AT] = now
    return level, dt, melted
end

-- Items in hand and attached to the body (back, belt: AttachedItems) get snow stage id (nil:
-- none); items of chr that left both get their model back (only chr's: with several characters,
-- split screen or other players in MP, each one's poll would put back the others' items and the
-- next one swap them again, rebuilding the models every poll). Hands are rebuilt with
-- resetEquippedHandsModels, attached models only with the whole model. The low-end mode
-- (CharItemSnow off) shows none here only: the stage a player reports in MP stays the real one.
local function syncItems(chr, stage)
    if not ISnow.opt("CharItemSnow") then stage = nil end
    local keep = {}
    local handsChanged, bodyChanged = false, false
    local function sync(item, onBody)
        if not item or keep[item] then return end
        keep[item] = true
        itemOwner[item] = chr
        -- also when the swap is no longer intact (another mod set the model past the hooks)
        if tried[item] ~= stageKey(item, stage, onBody) or swapBroken(item) then
            local before, beforeModel = swapped[item], origList[item] and origList[item].full
            setItemStage(item, stage, onBody)
            if swapped[item] ~= before or (origList[item] and origList[item].full) ~= beforeModel then
                if onBody then bodyChanged = true else handsChanged = true end
            end
        end
    end
    sync(chr:getPrimaryHandItem(), false)
    sync(chr:getSecondaryHandItem(), false)
    local attached = chr:getAttachedItems()
    if attached then
        for i = 0, attached:size() - 1 do sync(attached:get(i):getItem(), true) end
    end
    for item in pairs(tried) do
        local owner = itemOwner[item]
        if not keep[item] and (owner == nil or owner == chr) then
            setItemStage(item, nil)
            itemOwner[item] = nil
        end
    end
    if bodyChanged then chr:resetModel() elseif handsChanged then chr:resetEquippedHandsModels() end
end

-- The swap's modelIndex is saved with the item (KEY_INDEX keeps the old one in its ModData), and
-- only the items in a local player's inventory are put back when a save loads (restoreSaved).
-- An item that leaves the hands or the body goes on at once into a container, onto the floor or to
-- another player and may be saved there (its chunk, an MP transfer): so it gets its model back
-- then (OnEquipPrimary / OnEquipSecondary / OnClothingUpdated), not at the next poll. all: every
-- item of chr, held or not (death). Nothing to rebuild: the item is no longer drawn on chr.
local function releaseItems(chr, all)
    local keep = {}
    if not all then
        local p, s = chr:getPrimaryHandItem(), chr:getSecondaryHandItem()
        if p then keep[p] = true end
        if s then keep[s] = true end
        local attached = chr:getAttachedItems()
        if attached then
            for i = 0, attached:size() - 1 do
                local item = attached:get(i):getItem()
                if item then keep[item] = true end
            end
        end
    end
    local gone = {}
    for item in pairs(swapped) do
        if itemOwner[item] == chr and not keep[item] then table.insert(gone, item) end
    end
    for _, item in ipairs(gone) do setItemStage(item, nil) end
    return #gone
end

-- Every swap back (OnSave, cleanSave); the next poll swaps what is still held again.
local function restoreAllItems()
    local list = {}
    for item in pairs(swapped) do table.insert(list, item) end
    for _, item in ipairs(list) do pcall(setItemStage, item, nil) end
    return #list
end

-- Steps of SHOW_STEP the clothes show at level (0: none).
local function levelSteps(level)
    if level < MIN_LEVEL then return 0 end
    return math.max(1, math.floor(level / SHOW_STEP + 0.5))
end

-- Steps of snow the shells of hv show (0: none).
local function shownSteps(hv)
    local bv = hv:getBodyVisuals()
    for i = 0, bv:size() - 1 do
        local v = bv:get(i)
        if startsWith(v:getClothingItemName(), SHELL_PREFIX) then
            local tint = v:getTint()
            return tint and math.max(1, math.floor(tint:getRedFloat() / SHOW_STEP + 0.5)) or 1
        end
    end
    return 0
end

-- Multiplayer -----------------------------------------------------------------
-- The level comes from what a character went through (outdoors or not, in a vehicle, the
-- temperature it felt, heat sources, the hours before another player saw it), which only its own
-- client knows; so no client works it out for other players. The owner reports the look instead:
-- steps of SHOW_STEP on the clothes and the item stage, two small numbers, only when one changes
-- (at most about 16 messages for a full layer). The server (ISnow_CharSnowServer.lua) keeps the
-- last one per player and passes it on to every client; a client that meets a player it has no
-- look for asks the server (a player that joins later, one that came into range). Other clients
-- then build the same shells from that player's item visuals (other clients have no worn items of
-- it, see wornList) and swap the same item models.
-- The shells are body visuals, so a sync of the player's HumanVisual by the game may bring the
-- owner's shells of that moment (HumanVisualPacket, on joining too: shells saved under the clothes
-- it wore then); a remote player whose shells differ from the report in amount, or whose shell set
-- is not what was built here and not what shellsFor gives, is built again.
-- Online ids are given out again: the looks of players no longer in ISnow.otherPlayers() are
-- dropped at every poll, so a new player under the id does not show the last one's snow.
local MP_MODULE = "ISnow"
local MP_QUERY_SECONDS = 10     -- a player with no look is asked about at most this often
local reported = {}  -- [local player] = steps * 100 + stage last sent
local remoteLook = {}                                -- [online id] = { s = steps, i = stage index }
local remoteShown = {} -- [remote player] = { s = steps asked, shown, sig = shell set built }
local queried = {}                                   -- [online id] = time of the last query, ms
local mpStats = { sent = 0, received = 0, queries = 0, rebuilt = 0 }

local function reportLook(chr, steps, stage)
    if not isClient() then return end
    local key = steps * 100 + stage
    if reported[chr] == key then return end
    reported[chr] = key
    mpStats.sent = mpStats.sent + 1
    sendClientCommand(chr, MP_MODULE, "charSnow", { s = steps, i = stage })
end

-- A shell set as a string: "name/texture choice/fields (tint b * 10)" of each shell, sorted.
local function shellKey(name, texture, fields)
    return string.format("%s/%d/%d", name, texture or -1, math.floor((fields or 1) * 10 + 0.5))
end

local function sigOf(keys)
    table.sort(keys)
    return table.concat(keys, ",")
end

-- The shell set hv has.
local function shellSig(hv)
    local keys = {}
    local bv = hv:getBodyVisuals()
    for i = 0, bv:size() - 1 do
        local v = bv:get(i)
        local name = v:getClothingItemName()
        if startsWith(name, SHELL_PREFIX) then
            local tint = v:getTint()
            table.insert(keys, shellKey(name, v:getTextureChoice(), tint and tint:getBlueFloat()))
        end
    end
    return sigOf(keys)
end

-- The shell set shellsFor gives chr.
local function wantedSig(chr)
    local keys = {}
    for name, s in pairs((shellsFor(chr))) do table.insert(keys, shellKey(name, s.texture, s.fields)) end
    return sigOf(keys)
end

-- The look a remote player reported, shown on it.
local function pollRemote(chr)
    local id = chr:getOnlineID()
    if not id or id < 0 then return end
    local look = remoteLook[id]
    if not look then
        local t = getTimestampMs()
        if not queried[id] or t - queried[id] > MP_QUERY_SECONDS * 1000 then
            queried[id] = t
            mpStats.queries = mpStats.queries + 1
            sendClientCommand(MP_MODULE, "charSnowQuery", { id = id })
        end
        return
    end
    local enabled = ISnow.opt("CharSnow")
    local steps = enabled and not viewpoint() and look.s or 0
    local hv = chr:getHumanVisual()
    local st = remoteShown[chr]
    -- also when its item visuals came and went without OnClothingUpdated here (a bag taken off,
    -- as wornKeyOf for local players)
    local nvis = chr:getItemVisuals():size()
    local rebuild = not st or st.s ~= steps or shownSteps(hv) ~= st.shown
            or (steps > 0 and smallOf[chr] ~= ISnow.opt("CharSnowSmallItems"))
            or (steps > 0 and st.nvis ~= nvis)
    if not rebuild and steps > 0 then
        -- the same amount, but not the shells built here: the game's sync, or a change of clothes
        -- (onClothingUpdated built them anew, then shellsFor agrees)
        local sig = shellSig(hv)
        if sig ~= st.sig then
            if sig == wantedSig(chr) then st.sig = sig else rebuild = true end
        end
    end
    if rebuild then
        mpStats.rebuilt = mpStats.rebuilt + 1
        CS.clothes(steps > 0 and steps * SHOW_STEP or nil, chr)
        remoteShown[chr] = { s = steps, shown = shownSteps(hv), sig = shellSig(hv), nvis = nvis }
    end
    syncItems(chr, enabled and ITEM_STAGES[look.i] or nil)
end

local function pollRemotes()
    local players = ISnow.otherPlayers()
    if not players then return end
    local online = {}
    for i = 0, players:size() - 1 do
        local chr = players:get(i)
        if chr then
            online[chr:getOnlineID()] = true
            if not chr:isLocalPlayer() and not chr:isDead() then pollRemote(chr) end
        end
    end
    -- players that left (as dropGone on the server); one back in the list is asked about again
    local gone = {}
    for id in pairs(remoteLook) do
        if not online[id] then table.insert(gone, id) end
    end
    for _, id in ipairs(gone) do
        remoteLook[id] = nil
        queried[id] = nil
    end
end

local function onServerCommand(module, command, args)
    if module ~= MP_MODULE or command ~= "charSnow" or type(args) ~= "table" then return end
    local id, s, i = tonumber(args.id), tonumber(args.s), tonumber(args.i)
    if not id or not s or not i then return end
    mpStats.received = mpStats.received + 1
    remoteLook[id] = { s = math.max(0, math.min(math.floor(1 / SHOW_STEP + 0.5), math.floor(s))),
        i = math.max(0, math.min(#ITEM_STAGES, math.floor(i))) }
    queried[id] = nil
end
Events.OnServerCommand.Add(onServerCommand)

-- Console: what was sent and received, and the look of every other player known here.
function CS.mp()
    local out = { string.format("client=%s sent=%d received=%d queries=%d rebuilt=%d", tostring(isClient()),
        mpStats.sent, mpStats.received, mpStats.queries, mpStats.rebuilt) }
    for id, look in pairs(remoteLook) do
        local chr = getPlayerByOnlineID and getPlayerByOnlineID(id)
        table.insert(out, string.format("  id %d: steps=%d stage=%d shown=%s", id, look.s, look.i,
            chr and tostring(shownSteps(chr:getHumanVisual())) or "not here"))
    end
    return table.concat(out, "\n")
end

-- The shells of a local player as CS.clothes left them (ownShown): their steps of snow and their
-- set. The game puts the HumanVisual back from elsewhere: in MP the server keeps a copy of the
-- player's (the last one the client sent through the game's own visual sync, with the shells of
-- that moment, and saved with them) and sends it back on joining and later on its own; shells that
-- came that way stayed on for good when the level had none, since shown said none (Workshop bug
-- report 2026-10-09, a hosted server: snow on the clothes after the snowfall, never melting, no
-- menu to shake it off, back about 30 s after joining, even in clear weather). Any other amount
-- than built, shells where none were built or none where they were, or other shells at the same
-- amount (made for clothes worn then) builds them again. The server keeps its copy at the reported
-- amount since (ISnow_CharSnowServer.lua, alignVisual), so this is left for joining and the set.
ownMarkOf = function(hv) return shownSteps(hv) .. "|" .. shellSig(hv) end
local NO_SHELLS = "0|"

local function pollCharacter(chr, now)
    local level, dt, melted = updateLevel(chr, now)
    if ISnow.SnowWetness and dt > 0 then
        local ok, err = pcall(ISnow.SnowWetness.update, chr, dt, melted)
        if not ok then
            stats.errors = stats.errors + 1
            lastError = "wetness: " .. tostring(err)
        end
    end
    local steps, stage = 0, 0
    if snowBuildsUp() then steps, stage = levelSteps(level), itemStageIndex(level) end
    -- the others see the snow this player has, even when the player hides it here (Options > Mods)
    reportLook(chr, steps, stage)
    if not ISnow.opt("CharSnow") then steps, stage = 0, 0 end
    local want = steps > 0 and not viewpoint() and steps * SHOW_STEP or false
    -- what it wears changed and no OnClothingUpdated rebuilt the shells (wornKeyOf)
    local rewear = want and shown[chr] and wornKeyOf[chr] ~= nil and wornKeyOf[chr] ~= wornKey(chr)
    local hv = chr:getHumanVisual()
    -- shells it has that were not built here (ownShown), or another amount than the poll put on
    local synced = ownMarkOf(hv) ~= (ownShown[chr] or NO_SHELLS)
        or shownSteps(hv) ~= (shown[chr] and levelSteps(shown[chr]) or 0)
    -- also when the low-end mode was switched (small items with or without shells)
    if rewear or synced or shown[chr] ~= want or (want and smallOf[chr] ~= ISnow.opt("CharSnowSmallItems")) then
        -- only the amount when it had snow already: a change of clothes rebuilds them at once
        -- (onClothingUpdated)
        CS.clothes(want or nil, chr, want and shown[chr] and not rewear and not synced and true or false)
        shown[chr] = want
    end
    itemStageOf[chr] = ITEM_STAGES[stage]
    syncItems(chr, ITEM_STAGES[stage])
end

-- Shaking the snow off (ISnow_ShakeSnow.lua): the level of chr's snow 0..1 as of the last poll,
-- and lowering it (never raising) to level. Snow shaken off is gone before updateLevel sees it, so
-- it does not melt into the clothes (the time since the last poll counts at the new level). The
-- look changes at once when a step or the item stage does; in MP it goes to the others as usual.
function CS.levelOf(chr)
    return chr:getModData()[KEY_LEVEL] or 0
end

function CS.shakeOff(chr, level)
    local md = chr:getModData()
    local old = md[KEY_LEVEL] or 0
    level = clamp01(level)
    if pinned[chr] or level >= old then return end
    md[KEY_LEVEL] = level
    if levelSteps(level) ~= levelSteps(old) or itemStageIndex(level) ~= itemStageIndex(old) then
        pollCharacter(chr, getGameTime():getWorldAgeHours())
    end
end

-- Quiet weather (ISnow.quietWeather) and nothing on chr to show or melt: its poll would change
-- nothing; only its clock moves on (else the first snowfall would add the time since then, up to
-- CATCHUP_HOURS, at once).
local function asleep(chr, quiet)
    if not quiet or pinned[chr] or shown[chr] or itemStageOf[chr] ~= nil then return false end
    -- shells a sync brought back (ownShown) go at its next poll
    if shownSteps(chr:getHumanVisual()) > 0 then return false end
    return (chr:getModData()[KEY_LEVEL] or 0) <= 0
end

local function poll()
    stats.polls = stats.polls + 1
    local now = getGameTime():getWorldAgeHours()
    local quiet = ISnow.quietWeather()
    for i = 0, getNumActivePlayers() - 1 do
        local chr = getSpecificPlayer(i)
        if chr and not chr:isDead() then
            if asleep(chr, quiet) then
                chr:getModData()[KEY_AT] = now
                stats.asleep = stats.asleep + 1
            else
                pollCharacter(chr, now)
            end
        end
    end
    if isClient() then pollRemotes() end
end

-- Zombies ---------------------------------------------------------------------
-- Zombies have no worn items and no OnClothingUpdated: their shells come from their item visuals,
-- and a change in how many they have (a helmet falling off) rebuilds them. They have no body heat.
-- The amount a zombie shows is its shell tint, which is saved with it (HumanVisual.save writes the
-- body visuals; HumanVisual.clear drops them when the zombie object is reused for another one), so
-- a zombie seen again or loaded from the save goes on from what it shows. Outdoors a zombie new to
-- us starts at the level of a zombie that has stood outside all the time (KEY_OUTDOOR, which starts
-- at the ground cover), whatever it shows: the shells saved with it may be from days ago (winter
-- snow on a zombie loaded in a thaw).

-- Outdoors with the ground bare (no snow falling, no snow drawn on it: a thaw took it, or the
-- erosion winter is over) a zombie loses its snow in this many game hours on top of the melt: the
-- ground cover goes within the hour in a thaw, and zombies kept their snow for hours more (no body
-- heat), white in a green town (ViZOR, Workshop 2026-10-06).
local ZOMBIE_BARE_MELT_HOURS = 1
local ZOMBIE_REBUILDS = 25    -- zombie models rebuilt per poll at most
local ZOMBIE_VIEW = 70        -- tiles from a player: farther zombies are not rebuilt (not seen)
local KEY_OUTDOOR = "ISnowOutdoorLevel"
local KEY_OUTDOOR_AT = "ISnowOutdoorAt"
-- [zombie] = { level, at, shown = steps its shells show, applied = steps asked for, nvis = item visuals then }
local zstate = {}
local zpass = 0   -- number of the pass through the zombie list (st.pass: the last one that met it)
local zstats = { tracked = 0, shown = 0, rebuilds = 0, retints = 0, skippedFar = 0, skippedUnseen = 0 }

-- Snow cover of the ground 0..1 as drawn (ISnow.groundCover: none outside the erosion winter).
local function groundCover() return ISnow.groundCover() end

-- Snow level of a zombie that stood outdoors all the time. Not followed yet (an MP client that has
-- just joined: its GameTime ModData is its own, a save from before the mod) or not for more than
-- CATCHUP_HOURS (a save loaded later): the ground cover, as vehicles met outdoors, so zombies in a
-- snowed-in town do not start bare and take half an hour to get their snow.
local function updateOutdoor(now, clim, bare)
    local md = getGameTime():getModData()
    local level, at = md[KEY_OUTDOOR] or 0, md[KEY_OUTDOOR_AT]
    if not at or now < at - ISnow.CLOCK_SLACK_HOURS or now - at > CATCHUP_HOURS then
        level = groundCover()
    elseif now > at then
        local rate = snowRate(clim, true, clim:getTemperature(), false)
        if bare then rate = rate - 1 / ZOMBIE_BARE_MELT_HOURS end
        level = clamp01(level + rate * (now - at))
    else
        -- MP: the server's clock sync set this client's clock back a little (ISnow_Config.lua)
        now = at
    end
    md[KEY_OUTDOOR] = level
    md[KEY_OUTDOOR_AT] = now
    return level
end

-- Whether a local player can see z: near (ZOMBIE_VIEW) and not hidden by the game (targetAlpha 0,
-- IsoGameCharacter.updateSeenVisibility: behind walls, out of the view cone), when it is not drawn
-- at all. Rebuilding only those spends the paced rebuilds on what is on screen; one that comes into
-- sight gets its snow at its next turn (within a second, while it fades in). nil: too far,
-- false: near but unseen.
local function seenByPlayer(z)
    local x, y = z:getX(), z:getY()
    local near = nil
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and math.abs(p:getX() - x) < ZOMBIE_VIEW and math.abs(p:getY() - y) < ZOMBIE_VIEW then
            if z:getTargetAlpha(i) > 0 then return true end
            near = false
        end
    end
    return near
end

-- The zombie list is gone through in POLL_TICKS slices, one per tick, so every zombie is still
-- updated about once per POLL_TICKS ticks, but no single frame takes the whole list and up to
-- ZOMBIE_REBUILDS model rebuilds (a stutter every second with a horde around). Rebuilds are paced
-- the same way: ZOMBIE_REBUILDS per POLL_TICKS ticks, at most ZOMBIE_REBUILD_BURST in one tick.
local ZOMBIE_REBUILD_BURST = 2
-- A rebuild is synchronous (IsoGameCharacter.resetModel: ModelManager.Reset builds every clothing
-- and shell model instance, bytecode 42.21) and a zombie with many clothes and their shells takes
-- a few ms: the second one of a tick only while this tick's rebuilds took under ZOMBIE_TICK_MS.
local ZOMBIE_TICK_MS = 3
local ztick = { start = 0, rebuilds = 0 }   -- this tick's pollZombies: when it started, rebuilds done
ISnow.perf = ISnow.perf or {}
local perf = ISnow.perf   -- zRebuilds / zMs of the last tick, for the hitch log (ISnow_VehicleSnow.lua)
local zcursor = 0          -- next index into the cell's zombie list
local zround = nil         -- { outdoor, enabled, tracked, shown, active = with any snow, quiet } of the pass
local rebuildTokens = ZOMBIE_REBUILD_BURST
-- A pass that starts with no snow falling, no snow outdoors and no zombie with snow in the last
-- pass (summer, most of the year) goes QUIET_SLOWER times slower: it only has to find zombies that
-- come with snow (loaded from a save) and let them melt, and snowfall ends it at once.
local QUIET_SLOWER = 10
local zticks = 0

local function pollZombie(z, now, clim, round)
    local cur = shownSteps(z:getHumanVisual())
    local st = zstate[z]
    -- zombie snow off (the low-end mode): only the shells still shown are taken off; the others are
    -- not followed (no level, no temperature) and forgotten with the pass, met anew when it is on
    if not round.enabled and cur == 0 and not (st and st.applied > 0) then return end
    local outside = ISnow.snowReaches(z)
    if not st or st.shown ~= cur then
        -- new to us, or its visual changed under us (loaded, reused for another zombie)
        st = { level = outside and round.outdoor or cur * SHOW_STEP, at = now, shown = cur,
            applied = cur, nvis = z:getItemVisuals():size() }
        -- shells from an older save this version does not make (hasStaleShells): built anew when seen
        if cur > 0 and hasStaleShells(z:getHumanVisual()) then st.applied = -1 end
        zstate[z] = st
    elseif now > st.at then
        -- no snow on it and none falling on it: the level stays 0 (melting only lowers it)
        if st.level > 0 or (outside and clim:isSnowing()) then
            local rate = snowRate(clim, outside, clim:getAirTemperatureForCharacter(z), false)
            if outside and round.bare then rate = rate - 1 / ZOMBIE_BARE_MELT_HOURS end
            st.level = clamp01(st.level + rate * math.min(now - st.at, CATCHUP_HOURS))
        end
        st.at = now
    end
    st.pass = zpass
    local vp = viewpoint()
    local want = round.enabled and not vp and levelSteps(st.level) or 0
    local nvis = want > 0 and z:getItemVisuals():size()
    if rebuildTokens >= 1 and (ztick.rebuilds == 0 or getTimestampMs() - ztick.start < ZOMBIE_TICK_MS)
            and (want ~= st.applied or (want > 0 and nvis ~= st.nvis)) then
        local seen = seenByPlayer(z)
        -- Viewpoint's view is not the isometric one the alpha is for: the shells come off all near
        if vp and seen == false then seen = true end
        if seen then
            rebuildTokens = rebuildTokens - 1
            ztick.rebuilds = ztick.rebuilds + 1
            zstats.rebuilds = zstats.rebuilds + 1
            -- the same item visuals as its shells were made for: only the amount changes
            local same = want > 0 and st.shown > 0 and st.applied > 0 and nvis == st.nvis
            if same then zstats.retints = zstats.retints + 1 end
            CS.clothes(want > 0 and want * SHOW_STEP or nil, z, same)
            -- applied keeps a zombie without clothes with a shell (shown stays 0) from retrying
            st.applied, st.nvis = want, z:getItemVisuals():size()
            st.shown = shownSteps(z:getHumanVisual())
        elseif seen == false then
            zstats.skippedUnseen = zstats.skippedUnseen + 1
        else
            zstats.skippedFar = zstats.skippedFar + 1
        end
    end
    if st.shown > 0 then round.shown = round.shown + 1 end
    if st.shown > 0 or st.level > 0 then round.active = round.active + 1 end
end

-- One slice of the zombie list; a new pass starts when the last one reached the end.
local function pollZombies(now)
    local cell = getCell()
    local list = cell and cell:getZombieList()
    if not list then return end
    local clim = getClimateManager()
    rebuildTokens = math.min(ZOMBIE_REBUILD_BURST, rebuildTokens + ZOMBIE_REBUILDS / POLL_TICKS)
    local size = list:size()
    if not zround or zcursor >= size then
        local lastActive = zround and zround.active
        -- zombies not met in the pass that ends (unloaded, back in the pool) are forgotten
        if zround then ISnow.prune(zstate, function(_, st) return st.pass == zpass end) end
        zpass = zpass + 1
        if zround then zstats.tracked, zstats.shown = zround.tracked, zround.shown end
        local bare = not clim:isSnowing() and groundCover() <= 0
        local outdoor = updateOutdoor(now, clim, bare)
        -- CharSnow as for the players (snowBuildsUp: the sandbox, in SP this player's own when they
        -- replace it) and hidden with it here; ZombieSnow on top
        zround = { outdoor = outdoor, bare = bare, enabled = snowBuildsUp() and ISnow.opt("CharSnow") and ISnow.opt("ZombieSnow"),
            tracked = 0, shown = 0, active = 0, quiet = lastActive == 0 and outdoor <= 0 and not clim:isSnowing() }
        zcursor = 0
    end
    zticks = zticks + 1
    if zround.quiet then
        if clim:isSnowing() then
            zround.quiet = false
        elseif zticks % QUIET_SLOWER ~= 0 then
            return
        end
    end
    local last = math.min(size, zcursor + math.ceil(size / POLL_TICKS)) - 1
    for i = zcursor, last do
        local z = list:get(i)
        if z and not z:isDead() then
            zround.tracked = zround.tracked + 1
            pollZombie(z, now, clim, zround)
        end
    end
    zcursor = last + 1
end

-- The tables keyed by characters and items keep them for good (Kahlua has no weak tables, see
-- ISnow.prune): every SWEEP_POLLS polls the players gone (dead, left the server) and the zombies
-- not tracked any more go, and the items those players last had get their own models back (a dead
-- player's items on the body kept the snow: dead players are not polled).
local SWEEP_POLLS = 30
local function sweep()
    local live = ISnow.liveCharacters()
    local function player(chr) return live[chr] end
    local function character(chr) return live[chr] or zstate[chr] ~= nil end
    for _, t in ipairs({ pinned, shown, ownShown, reported, remoteShown, itemStageOf, wornKeyOf }) do ISnow.prune(t, player) end
    ISnow.prune(amountOf, character)
    ISnow.prune(smallOf, character)
    local gone = {}
    for item, owner in pairs(itemOwner) do
        if not live[owner] then table.insert(gone, item) end
    end
    for _, item in ipairs(gone) do
        pcall(setItemStage, item, nil)
        itemOwner[item], tried[item], swapped[item], origList[item] = nil, nil, nil, nil
    end
end

local tickCounter = 0
local pollCount = 0
local function onTick()
    if ISnow.saveCleaned then return end   -- ISnow.cleanSave: the mod is about to be removed
    tickCounter = tickCounter + 1
    local ok, err
    if tickCounter % POLL_TICKS == 0 then
        ok, err = pcall(poll)
        if not ok then
            stats.errors = stats.errors + 1
            lastError = tostring(err)
        end
        pollCount = pollCount + 1
        if pollCount % SWEEP_POLLS == 0 then
            ok, err = pcall(sweep)
            if not ok then
                stats.errors = stats.errors + 1
                lastError = "sweep: " .. tostring(err)
            end
        end
    end
    ztick.start, ztick.rebuilds = getTimestampMs(), 0
    ok, err = pcall(pollZombies, getGameTime():getWorldAgeHours())
    if not ok then
        stats.errors = stats.errors + 1
        lastError = "zombies: " .. tostring(err)
    end
    perf.zRebuilds, perf.zMs = ztick.rebuilds, getTimestampMs() - ztick.start
end
ISnow.listen("OnTick", "CharSnow", onTick)
CS.onTick = onTick   -- for hooking by hand after a live reload (which cannot add Events)

-- A save may hold items that showed snow (saved while in hand): their modelIndex, or with older
-- versions their snow model, goes back; the next poll swaps again what is still in hand.
local function restoreSaved(chr)
    local inv = chr and chr:getInventory()
    if not inv then return end
    local items = inv:getAllEvalRecurse(function(item)
        -- hasModData first: getModData would give every item in the inventory a ModData table
        if not item:hasModData() then return false end
        local md = item:getModData()
        return md[KEY_ORIG] ~= nil or md[KEY_INDEX] ~= nil
    end)
    for i = 0, items:size() - 1 do setItemStage(items:get(i), nil) end
end
Events.OnCreatePlayer.Add(function(_, chr) pcall(restoreSaved, chr) end)

-- Items leaving the hands or the body get their model back at once (releaseItems).
local function onEquipChange(chr)
    if chr then pcall(releaseItems, chr) end
end
Events.OnEquipPrimary.Add(onEquipChange)
Events.OnEquipSecondary.Add(onEquipChange)
Events.OnClothingUpdated.Add(onEquipChange)

-- A world save (GameWindow.save: quitting, an MP client's save; OnSave comes before the map is
-- written) gets no swapped item: every swap goes back first, and OnPostSave swaps the held ones
-- again at once (else the next poll would). Players are saved on their own (PlayerDB: every 10 s,
-- and on quitting before OnSave): their held items keep the swap there, put back on load
-- (restoreSaved) or by ISnow.cleanSave.
Events.OnSave.Add(function() pcall(restoreAllItems) end)
Events.OnPostSave.Add(function()
    if ISnow.saveCleaned then return end
    for i = 0, getNumActivePlayers() - 1 do
        local chr = getSpecificPlayer(i)
        if chr and not chr:isDead() then pcall(syncItems, chr, itemStageOf[chr]) end
    end
end)

-- Corpses ---------------------------------------------------------------------
-- The corpse copies the body visuals (IsoDeadBody(IsoGameCharacter) -> HumanVisual.copyFrom) and
-- saves them with its chunk: before 0.5.2 Patch 1 the snow stayed on corpses for good (in summer
-- too, entries left in the save, warnings once the mod is removed), so since then the shells go
-- when a character dies. With CorpseKeepSnow (off by default; asked for on the Workshop,
-- 2026-10-08) they stay on, and the corpse's snow melts as a zombie's does (no body heat; in
-- warmth, in the rain, within ZOMBIE_BARE_MELT_HOURS outdoors on bare ground) but never grows:
-- corpses are not snowed over (tried for 0.5.2 and dropped). Its level is its shells' tint, like a
-- zombie's; when it drops a step the shells are retinted (or taken off at 0) and the corpse drawn
-- again (IsoDeadBody.invalidateCorpse: its atlas texture or its chunk's render level, 42.21).
-- There is no list of corpses: a corpse with snow is found where a character died with snow on
-- (looked at for DEATH_SECONDS, the corpse comes after the death animation) and by going over the
-- squares around the local players a few per tick (corpses loaded with their chunk); the ones found
-- are then followed on their own, once a second. With the option off (or the low-end mode, or
-- Project Viewpoint's 3D view without the submod) the corpses met with snow lose it.
-- MP: a client makes the corpse from its own copy of the zombie (DeadZombiePacket names the
-- character, 42.21), which has this client's shells; corpses the server streams in later have none.
-- All of it in one table K: this file is near the 200 locals a chunk may declare in all under
-- -debug (LexState.new_localvar keeps every local's line in actvarline[200], 42.21; for-loop
-- variables count too), past which it does not load at all (tools/luatest/compile_all.ps1).
local K = {
    RADIUS = 40,            -- tiles around a local player whose squares are looked at
    SQUARES = 8,            -- squares per tick (a pass round one player: about 14 s; new corpses come
                            -- from the deaths, the pass finds the ones loaded with their chunk)
    SQUARES_OFF = 1,        -- with the option off: only to take snow left from when it was on
    POLL_TICKS = 60,        -- the corpses followed melt once a second
    MAX = 300,              -- corpses followed at most (the others wait for a free place)
    DEATH_SECONDS = 15,     -- how long the square of a death is looked at for its corpse
    DEATH_REACH = 3,        -- and the squares this far round it
    states = {},            -- [IsoDeadBody] = { level, at, shown = steps its shells show }
    n = 0,                  -- corpses in states
    deaths = {},            -- { x, y, z, untilMs } of characters that died with snow on
    scan = { player = 0, i = 0, ticks = 0 },
    stats = { melted = 0, stripped = 0, retints = 0, passes = 0, found = 0 },
}

function K.keep()
    return ISnow.opt("CorpseKeepSnow") and ISnow.opt("CharSnow") and not viewpoint()
end
CS.keepOnCorpses = K.keep

-- Gives the shells of hv the amount, each keeping its g (icing or not) and b (fields).
function K.retint(hv, amount)
    local bv = hv:getBodyVisuals()
    for i = 0, bv:size() - 1 do
        local v = bv:get(i)
        if startsWith(v:getClothingItemName(), SHELL_PREFIX) then
            local old = v:getTint()
            v:setTint(ImmutableColor.new(amount, old and old:getGreenFloat() or ZOMBIE_G, old and old:getBlueFloat() or 1))
        end
    end
end

function K.forget(body)
    if K.states[body] then
        K.states[body] = nil
        K.n = K.n - 1
    end
end

function K.strip(body)
    local hv = body:getHumanVisual()
    if hv and removeShells(hv) > 0 then
        body:invalidateCorpse()
        K.stats.stripped = K.stats.stripped + 1
    end
    K.forget(body)
end

-- One corpse with shells (cur steps) at game time now.
function K.poll(body, cur, now, clim, keep)
    if not keep or hasStaleShells(body:getHumanVisual()) then return K.strip(body) end
    local sq = body:getSquare()
    local outside = sq ~= nil and ISnow.snowReaches(sq) and body:getZ() >= 0
    local st = K.states[body]
    if not st or st.shown ~= cur then
        if not st then
            if K.n >= K.MAX then return end
            K.n = K.n + 1
            K.stats.found = K.stats.found + 1
        end
        -- new to us (just died, loaded, drawn again): from what it shows; outdoors never more than
        -- a zombie that stood outside all the time (a corpse loaded in a thaw with winter snow)
        local level = cur * SHOW_STEP
        if outside then level = math.min(level, zround and zround.outdoor or groundCover()) end
        st = { level = level, at = now, shown = cur }
        K.states[body] = st
    end
    -- the clock set back (debug time of day, an MP client's clock sync): go on from now
    if now < st.at then st.at = now end
    if now > st.at then
        local temp = sq and clim:getAirTemperatureForSquare(sq) or clim:getTemperature()
        local _, melt = snowRates(clim, outside, temp, false)
        if outside and not clim:isSnowing() and groundCover() <= 0 then melt = melt + 1 / ZOMBIE_BARE_MELT_HOURS end
        st.level = clamp01(st.level - melt * math.min(now - st.at, CATCHUP_HOURS))
        st.at = now
    end
    local want = levelSteps(st.level)
    if want == 0 then
        K.strip(body)
        K.stats.melted = K.stats.melted + 1
    elseif want ~= cur then
        K.retint(body:getHumanVisual(), want * SHOW_STEP)
        body:invalidateCorpse()
        st.shown = want
        K.stats.retints = K.stats.retints + 1
    end
end

-- The corpses with snow on sq not followed yet (most squares have no static moving object at all:
-- that list is the square's own, getDeadBodys builds one).
function K.square(sq, now, clim, keep)
    local sm = sq:getStaticMovingObjects()
    if not sm or sm:size() == 0 then return end
    local bodies = sq:getDeadBodys()
    for b = 0, (bodies and bodies:size() or 0) - 1 do
        local body = bodies:get(b)
        if body and not K.states[body] and not body:isAnimal() and not body:isSkeleton() then
            local hv = body:getHumanVisual()
            local cur = hv and shownSteps(hv) or 0
            if cur > 0 then K.poll(body, cur, now, clim, keep) end
        end
    end
end

-- The corpses followed: melted, or forgotten when no longer on their square (burnt, picked up,
-- unloaded with their chunk).
function K.followed(now, clim, keep)
    local list = {}
    for body in pairs(K.states) do list[#list + 1] = body end
    for _, body in ipairs(list) do
        local sq = body:getSquare()
        local sm = sq and sq:getStaticMovingObjects()
        if not (sm and sm:contains(body)) then
            K.forget(body)
        else
            local cur = shownSteps(body:getHumanVisual())
            if cur > 0 then K.poll(body, cur, now, clim, keep) else K.forget(body) end
        end
    end
end

-- The squares of recent deaths and around them (a body knocked down lands up to about 2.5 tiles
-- away, seen in game), until their time is up.
function K.recentDeaths(now, clim, keep)
    local cell = getCell()
    local ms = getTimestampMs()
    for i = #K.deaths, 1, -1 do
        local d = K.deaths[i]
        for dx = -K.DEATH_REACH, K.DEATH_REACH do
            for dy = -K.DEATH_REACH, K.DEATH_REACH do
                local sq = cell:getGridSquare(d[1] + dx, d[2] + dy, d[3])
                if sq then K.square(sq, now, clim, keep) end
            end
        end
        if ms > d[4] then table.remove(K.deaths, i) end
    end
end

-- Every tick a few squares of the box round one local player, the players in turn; once a second
-- the corpses followed and the squares of recent deaths.
function K.tick(now)
    local cell = getCell()
    if not cell then return end
    local keep = K.keep()
    local clim = getClimateManager()
    local scan = K.scan
    scan.ticks = scan.ticks + 1
    if scan.ticks % K.POLL_TICKS == 0 then
        if K.n > 0 then K.followed(now, clim, keep) end
        if #K.deaths > 0 then K.recentDeaths(now, clim, keep) end
    end
    local p = getSpecificPlayer(scan.player)
    if not p then
        scan.player, scan.i = 0, 0
        return
    end
    local side = 2 * K.RADIUS + 1
    local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
    for _ = 1, keep and K.SQUARES or K.SQUARES_OFF do
        local i = scan.i
        local sq = cell:getGridSquare(px - K.RADIUS + i % side, py - K.RADIUS + math.floor(i / side), pz)
        if sq then K.square(sq, now, clim, keep) end
        scan.i = i + 1
        if scan.i >= side * side then
            scan.i = 0
            K.stats.passes = K.stats.passes + 1
            scan.player = scan.player + 1
            if scan.player >= getNumActivePlayers() then scan.player = 0 end
            return
        end
    end
end

function CS.corpses()
    local s = K.stats
    local msg = string.format("[ImmersiveSnow] corpses: keep=%s followed=%d found=%d melted=%d stripped=%d retints=%d deaths=%d passes=%d scan=%d/%d",
        tostring(K.keep()), K.n, s.found, s.melted, s.stripped, s.retints, #K.deaths, s.passes, K.scan.i, (2 * K.RADIUS + 1) ^ 2)
    print(msg)
    return msg
end
CS.corpseStates = K.states   -- tests

function CS.onTickCorpses()
    if ISnow.saveCleaned then return end
    local ok, err = pcall(K.tick, getGameTime():getWorldAgeHours())
    if not ok then
        stats.errors = stats.errors + 1
        lastError = "corpses: " .. tostring(err)
    end
end
ISnow.listen("OnTick", "CharSnowCorpses", CS.onTickCorpses)

-- A character dying with snow on: the shells go before it becomes a corpse unless they stay on it
-- (CorpseKeepSnow, above: then its square is looked at for the corpse). OnCharacterDeath comes from
-- DoDeath, at the start of the death; the corpse is made after the death animation
-- (IsoGameCharacter.die -> becomeCorpse, 42.21). Its items get their own models back either way
-- (the corpse keeps its inventory; the sweep only came to them later).
function CS.stripOnDeath(chr)
    local hv = chr and chr:getHumanVisual()
    if hv and shownSteps(hv) > 0 then
        if K.keep() then
            table.insert(K.deaths, { math.floor(chr:getX()), math.floor(chr:getY()), math.floor(chr:getZ()),
                getTimestampMs() + K.DEATH_SECONDS * 1000 })
        elseif removeShells(hv) > 0 then
            chr:resetModel()
        end
    end
    amountOf[chr] = nil
    if chr then releaseItems(chr, true) end
end
Events.OnCharacterDeath.Add(function(chr) pcall(CS.stripOnDeath, chr) end)

-- 0.5.1 Patch 2 slowed the build-up on players, CharSnowHours 0.5 -> 3 (with CharSnowMax): old SP
-- saves too (ISnow.migrateDefault).
Events.OnGameStart.Add(function()
    local ok, err = pcall(ISnow.migrateDefault, "charSnowHours051p2", "CharSnowHours", 0.5, 3)
    if not ok then print("[ImmersiveSnow] CharSnowHours not migrated: " .. tostring(err)) end
end)

-- Debug console --------------------------------------------------------------

function CS.set(level, chr)
    chr = chr or getPlayer()
    chr:getModData()[KEY_LEVEL] = clamp01(level)
    chr:getModData()[KEY_AT] = getGameTime():getWorldAgeHours()
    return "level " .. clamp01(level)
end

function CS.pin(level, chr)
    chr = chr or getPlayer()
    pinned[chr] = level and clamp01(level) or nil
    return "pinned " .. tostring(pinned[chr])
end

-- Player polls skipped asleep so far (quiet weather, nothing on the player; tests, debug console).
function CS.asleepPolls() return stats.asleep end

function CS.zombies()
    return string.format("zombies tracked=%d with snow=%d rebuilds=%d (retints %d) skippedFar=%d skippedUnseen=%d quiet=%s outdoorLevel=%.3f",
        zstats.tracked, zstats.shown, zstats.rebuilds, zstats.retints, zstats.skippedFar, zstats.skippedUnseen,
        tostring(zround and zround.quiet), getGameTime():getModData()[KEY_OUTDOOR] or 0)
end

function CS.weather(chr)
    chr = chr or getPlayer()
    local clim = getClimateManager()
    return string.format("level=%.3f shown=%s pinned=%s snowing=%s intensity=%.2f airTemp=%.1f outside=%s vehicle=%s polls=%d asleep=%d quietWeather=%s errors=%d%s",
        chr:getModData()[KEY_LEVEL] or 0, tostring(shown[chr]), tostring(pinned[chr]), tostring(clim:isSnowing()),
        clim:getSnowIntensity(), clim:getAirTemperatureForCharacter(chr), tostring(ISnow.snowReaches(chr)),
        tostring(chr:getVehicle() ~= nil), stats.polls, stats.asleep, tostring(ISnow.quietWeather()), stats.errors,
        lastError and ("\nlast error: " .. lastError) or "")
end

-- Taking the mod out of a save ------------------------------------------------
-- ISnow.cleanSave(radius) in the Lua console (README) before the mod is removed from a save: takes
-- out what the mod put into it, then stops the mod for the session (ISnow.saveCleaned), so the
-- next save is clean; save, quit and remove the mod. In SP, or in MP on each client for what it
-- has (its players, the others and the zombies as it sees them; vehicles there keep no levels):
--  * shells (body visuals: the save keeps them, without the mod only warnings in the log) on the
--    local and other players, the zombies of the cell and the corpses within radius tiles (default
--    CLEAN_RADIUS) of a local player
--  * item swaps: every swap back (modelIndex, KEY_INDEX, the keys of older versions) on the items
--    in hand, in the local players' inventories, on the floor, in containers and corpses within
--    radius and in the vehicles of the cell
--  * ModData keys: the players' level, the zombies' outdoor level (GameTime), the vehicles' levels
--    (ISnow.VehicleSnow.cleanSave), the global ModData "ImmersiveSnow" (migrations)
--  * the sandbox's "Decaying Corpse Health Impact" back to its own value if it is held at None in
--    frost (ISnow.ColdCorpses.restore)
-- Returns (and prints) what it did.
local CLEAN_RADIUS = 60
function CS.cleanSave(radius)
    radius = tonumber(radius) or CLEAN_RADIUS
    ISnow.saveCleaned = true
    local n = { shells = 0, characters = 0, items = 0, vehicles = 0 }
    local function strip(chr)
        local hv = chr and chr:getHumanVisual()
        local k = hv and removeShells(hv) or 0
        if k > 0 then
            n.shells, n.characters = n.shells + k, n.characters + 1
            if not instanceof(chr, "IsoDeadBody") then chr:resetModel() end
        end
    end
    local itemKeys = { KEY_INDEX, KEY_ORIG, KEY_KIND, KEY_STATIC, KEY_WSTATIC }
    -- hasModData first: getModData would give every item looked at a ModData table, saved with it
    local function hasKeys(item)
        if not (item and item:hasModData()) then return false end
        local md = item:getModData()
        for _, key in ipairs(itemKeys) do
            if md[key] ~= nil then return true end
        end
        return false
    end
    local function cleanItem(item)
        pcall(setItemStage, item, nil)
        local md = item:getModData()
        for _, key in ipairs(itemKeys) do md[key] = nil end
        n.items = n.items + 1
    end
    local function cleanContainer(container)
        if not container then return end
        local items = container:getAllEvalRecurse(hasKeys)
        for i = 0, items:size() - 1 do cleanItem(items:get(i)) end
    end
    n.items = restoreAllItems()
    for _, t in ipairs({ tried, swapped, origList, itemOwner }) do
        for k in pairs(t) do t[k] = nil end
    end

    for i = 0, getNumActivePlayers() - 1 do
        local chr = getSpecificPlayer(i)
        if chr then
            strip(chr)
            local md = chr:getModData()
            md[KEY_LEVEL], md[KEY_AT] = nil, nil
            cleanContainer(chr:getInventory())
        end
    end
    local others = isClient() and ISnow.otherPlayers() or nil
    for i = 0, (others and others:size() or 0) - 1 do
        local chr = others:get(i)
        if chr and not chr:isLocalPlayer() then strip(chr) end
    end
    local cell = getCell()
    local zombies = cell and cell:getZombieList()
    for i = 0, (zombies and zombies:size() or 0) - 1 do strip(zombies:get(i)) end
    for v in pairs(ISnow.liveVehicles()) do
        for p = 0, v:getPartCount() - 1 do cleanContainer(v:getPartByIndex(p):getItemContainer()) end
    end

    -- corpses, floor items and containers near the local players
    local minZ, maxZ = -1, 7
    pcall(function() minZ, maxZ = tonumber(cell:getMinZ()) or minZ, tonumber(cell:getMaxZ()) or maxZ end)
    local seen = {}
    for i = 0, (cell and getNumActivePlayers() or 0) - 1 do
        local chr = getSpecificPlayer(i)
        if chr then
            local px, py = math.floor(chr:getX()), math.floor(chr:getY())
            for x = px - radius, px + radius do
                for y = py - radius, py + radius do
                    for z = minZ, maxZ do
                        local sq = cell:getGridSquare(x, y, z)
                        if sq and not seen[sq] then
                            seen[sq] = true
                            local bodies = sq:getDeadBodys()
                            for b = 0, (bodies and bodies:size() or 0) - 1 do
                                local body = bodies:get(b)
                                strip(body)
                                cleanContainer(body:getContainer())
                            end
                            local floor = sq:getWorldObjects()
                            for w = 0, (floor and floor:size() or 0) - 1 do
                                local item = floor:get(w):getItem()
                                if hasKeys(item) then cleanItem(item) end
                                if instanceof(item, "InventoryContainer") then cleanContainer(item:getInventory()) end
                            end
                            local objects = sq:getObjects()
                            for o = 0, (objects and objects:size() or 0) - 1 do
                                local obj = objects:get(o)
                                for c = 0, obj:getContainerCount() - 1 do cleanContainer(obj:getContainerByIndex(c)) end
                            end
                        end
                    end
                end
            end
        end
    end

    local gmd = getGameTime():getModData()
    gmd[KEY_OUTDOOR], gmd[KEY_OUTDOOR_AT] = nil, nil
    if ModData and ModData.exists("ImmersiveSnow") then ModData.remove("ImmersiveSnow") end
    if ISnow.VehicleSnow and ISnow.VehicleSnow.cleanSave then n.vehicles = ISnow.VehicleSnow.cleanSave() end
    local corpses = ISnow.ColdCorpses and ISnow.ColdCorpses.restore()
    for _, t in ipairs({ amountOf, smallOf, shown, itemStageOf, wornKeyOf, pinned, zstate, remoteShown, remoteLook, K.states }) do
        for k in pairs(t) do t[k] = nil end
    end
    K.n = 0
    local msg = string.format("[ImmersiveSnow] save cleaned: %d snow shells off %d characters, %d items with their own " ..
        "model again, %d vehicles without snow levels%s. The mod is stopped until the game is loaded again: save, " ..
        "quit and remove it now.", n.shells, n.characters, n.items, n.vehicles,
        corpses and ", Decaying Corpse Health Impact set back from None" or "")
    print(msg)
    return msg
end
ISnow.cleanSave = CS.cleanSave
