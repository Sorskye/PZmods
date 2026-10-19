-- Immersive Snow: adds snow "shells" to every vehicle script, vanilla and modded.
--
-- A shell is an extra part (category nodisplay, no item) whose models are copies of a vehicle
-- ModelScript with a snow shader and parameters per snow stage: ISnow.VEHICLE_SNOW_PART for the
-- body, VEHICLE_SNOW_WHEEL_PART .. wheel id per wheel, VEHICLE_SNOW_PART_PREFIX .. part id per
-- separate body piece (door, hood, window, KI5 variants, truck bed...). The shaders put snow on
-- the up-facing surfaces and patches on the rest, keeping glass and rims clear but for their
-- edges, so no per-vehicle art is needed. ISnow_VehicleSnow.lua (client) decides what shows.
--
-- Why it works at runtime (B42.20, checked in projectzomboid.jar):
--  * VehicleScript:Load parses a body into the existing script, and LoadPart reuses a part with
--    the same id or appends a new one; nothing is reset. The Vehicle script type has no
--    ResetExisting flag, so text scripts behave the same way.
--  * VehicleParts.setScript rebuilds a vehicle's parts from its script, keeping saved parts by
--    id and creating missing ones, so vehicles from old saves get the shell part too.
--  * ModelManager.getLoadedModel loads a ModelScript's model lazily on first use, so model
--    scripts added with ScriptManager:addModelScript after boot are fine.
--  * Part models share the body model's transform (vanilla hoods and trunks use offset 0 with
--    the body's mesh file and scale), so a copy of the body ModelScript lines up with the body.
--  * Wheels: a part with `wheel = <id>` gets that wheel's transform (position, steering, spin)
--    for its models. The snow goes into an extra part per wheel instead of the tire part itself
--    because tire parts keep setAllModelsVisible = true (the default), which shows every model of
--    the part when a tire is installed. Physics finds tires by the name "Tire" .. wheel id, not by
--    the wheel field, so the extra parts do not count as tires. A snow wheel part only gets its
--    `wheel` with its first models (Shells.addVariant): the game's 3D vehicle preview
--    (UI3DScene$VehicleRenderData.initWheelModel, 42.21; the debug Vehicle Editor, mods' admin
--    panels) calls scriptPart.models.isEmpty() on every part with a wheel, and a part without
--    models has models = null, so the preview threw every frame and the rest of the UI stopped
--    drawing (reported by Minidoracat, Vehicle Spawn Control, 2026-10-06).
--  * Body pieces: BaseVehicle.updateTransform places a non-wheel model by its offset / rotate /
--    scale on the vehicle transform unless the part has a parent and the model an
--    attachmentNameParent, so a copy with the same values lines up. A part with `parent = X` gets
--    X's animation player (BaseVehicle$ModelInfo.getAnimationPlayer; vanilla windows in doors
--    work so), so the copy of a door has the door's pose. Part children are only used to find a
--    child window (VehiclePart.getChildWindow), which the snow parts have none of.
--  * Skinned pieces (Vanilla Vehicles Animated doors, hood, trunk, windows: static = FALSE,
--    boneWeight = FrontDoor.L 1.0 and the like, 42.21): ModelManager.addVehicle gives every
--    VehicleSubModelInstance modelInfo.getAnimationPlayer(), which for a part with a parent is the
--    player of the parent part's first ModelInfo (getModelInfoForPart). The shell copies static and
--    the bone weights, so it is drawn by the skinned isnow_vehiclesnow.vert with that player's
--    MatrixPalette: the door's snow swings with the door's bone, a window's with the window track
--    the engine plays on the door's player (window parts have parent = the door).
-- Must run on the server too: parts are synced by index, both sides need the same list.

require "ImmersiveSnow/ISnow_Config"

local Shells = {}
ISnow.VehicleShells = Shells

local VARIANTS = {}
for _, id in ipairs(ISnow.VEHICLE_SNOW_STAGES) do table.insert(VARIANTS, id) end
for _, id in ipairs(ISnow.VEHICLE_SNOW_ICE_STAGES) do table.insert(VARIANTS, id) end
-- snow and icing in one model: everywhere, wheels too (what the client shows, see ISnow_VehicleSnow.lua)
for _, id in ipairs(ISnow.VEHICLE_SNOW_BOTH_STAGES) do table.insert(VARIANTS, id) end
-- the icing with clean glass and glass frost: body and body piece shells only (wheels have no
-- glass, and no shader for them)
local NO_WHEEL = {}
for _, stages in ipairs({ ISnow.VEHICLE_SNOW_ICE_CLEAN_STAGES, ISnow.VEHICLE_SNOW_BOTH_CLEAN_STAGES,
        ISnow.VEHICLE_SNOW_GLASS_STAGES }) do
    for _, id in ipairs(stages) do
        table.insert(VARIANTS, id)
        NO_WHEEL[id] = true
    end
end
for _, id in ipairs(ISnow.VEHICLE_SNOW_DEBUG) do table.insert(VARIANTS, id) end
-- The shader stage of each stage for body shells without a mask (see maskedByScript): without glass
-- the clean-glass stages are the icing and one-pass ones, and the glass frost has nothing to draw
-- (no model; the client shows none on such a vehicle). Debug views keep the masked shaders.
local NOMASK_OF = {}
for i, id in ipairs(ISnow.VEHICLE_SNOW_STAGES) do NOMASK_OF[id] = id end
for i, id in ipairs(ISnow.VEHICLE_SNOW_ICE_STAGES) do
    NOMASK_OF[id] = id
    NOMASK_OF[ISnow.VEHICLE_SNOW_ICE_CLEAN_STAGES[i]] = id
end
for i, id in ipairs(ISnow.VEHICLE_SNOW_BOTH_STAGES) do
    NOMASK_OF[id] = id
    NOMASK_OF[ISnow.VEHICLE_SNOW_BOTH_CLEAN_STAGES[i]] = id
end
local IS_GLASS = {}
for _, id in ipairs(ISnow.VEHICLE_SNOW_GLASS_STAGES) do IS_GLASS[id] = true end
-- the first model of a snow wheel part, never shown: what the game's 3D vehicle preview draws of it
-- (see the top of this file), with the texture the snow shaders draw nothing for
local PREVIEW = ISnow.VEHICLE_SNOW_PREVIEW_ID
local ENSURE_IDS = {}
for _, id in ipairs(VARIANTS) do table.insert(ENSURE_IDS, id) end
table.insert(ENSURE_IDS, PREVIEW)

local SKIP_KEYS = { shader = true, texture = true }
-- Keys a model script may repeat (all are kept, in order); for any other key the last one wins.
local LIST_KEYS = { boneweight = true }

-- Source parts never given snow, by id (Lua patterns, lower case): inside or under the vehicle,
-- or wheels (they have their own snow parts). Other parts are filtered by category in game.
-- GloveBox stays in: KI5 trucks keep their bed / tank / crane there, next to the interior model.
local PART_SKIP = {
    "^isnow", "^tire", "^seat", "^radio", "^battery", "^engine$", "^heater",
    "^gastank", "muffler", "^brake", "^suspension", "^passengercompartment", "^headlight", "^lightbar",
    "^interior$",   -- Vanilla Vehicles Animated: the cab and the trunk / cargo decor
}
-- Models of a source part never given snow, by model script name (lower case): the cab inside
-- (Vanilla Vehicles Animated: "<car>_internals") and placeholder meshes (its VVA_Dummy on the
-- VVAAnchor_* light parts).
local MODEL_SKIP = { "interior", "internals", "dummy" }
-- Models drawn with the wheel shader (tyre / rim from their texture), besides the tyre models of
-- the vehicle's own Tire<wheel> parts: spare tyres and the like.
local WHEEL_MODEL = { "tire", "tyre", "wheel" }

local shellByModel = {}   -- ["body:"/"wheel<seed>:" .. model full type] = shell name prefix, or false if it failed
local stats = { scripts = 0, injected = 0, already = 0, noModel = 0, shells = 0, wheels = 0, failed = 0,
    parts = 0, partModels = 0, partSkipId = 0, modelSkipName = 0, modelAttached = 0, modelNoScript = 0,
    created = 0, ms = 0, variants = 0, variantModels = 0, noMask = 0 }
local piecesByScript = {} -- [vehicle script full name] = Shells.pieces list
local wheelsByScript = {} -- [vehicle script full name] = wheel part list (see Shells.wheels)
local errors = {}

local function logError(msg)
    if #errors < 50 then table.insert(errors, msg) end
    print("[ImmersiveSnow] vehicle shells: " .. msg)
end

-- Top-level "key = value" entries of a script block, nested blocks (attachments) skipped.
-- out[lower key] = list of { key, value }: every entry for LIST_KEYS, else only the last one.
-- Jumps from one separator ({ } , or a line break) to the next with string.find: it used to go
-- character by character (a string.sub and a table.insert each), over every model script of every
-- vehicle at every world load.
local SEPARATORS = "[{},\n\r]"
local function parseTopLevel(body, out, order)
    local open = string.find(body, "{", 1, true)
    if not open then return end
    local depth, buf = 1, {}
    local function flush()
        local entry = table.concat(buf)
        buf = {}
        local k, v = string.match(entry, "^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k then
            local lk = string.lower(k)
            if out[lk] == nil then
                table.insert(order, lk)
                out[lk] = {}
            end
            if not LIST_KEYS[lk] then out[lk] = {} end
            table.insert(out[lk], { key = k, value = v })
        end
    end
    local pos = open + 1
    while true do
        local i = string.find(body, SEPARATORS, pos)
        if not i then return end
        -- the text since the last separator lies at one depth
        if depth == 1 and i > pos then buf[#buf + 1] = string.sub(body, pos, i - 1) end
        local c = string.sub(body, i, i)
        if c == "{" then
            if depth == 1 then buf = {} end   -- drop the nested block's header
            depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 then flush() return end
        elseif depth == 1 then
            flush()
        end
        pos = i + 1
    end
end

local function sanitize(s)
    return (string.gsub(s, "[^%w]", "_"))
end

-- Full name of ModelScript ms, found by the name file. Some modded model scripts have no name
-- (getName nil, getFullType "<module>.null": the KI5 Containers! bodies, 42.21), and shells keyed
-- by getFullType all shared the first one's mesh (snow of a 40 ft container floating off a 20 ft
-- one); those go by the name they were looked up by.
local function modelName(ms, file)
    if ms:getName() ~= nil then return ms:getFullType() end
    if string.find(file, ".", 1, true) then return file end
    return ms:getModule():getName() .. "." .. file
end

-- Vehicle scripts that name no mask texture (textureMask): vanilla's burnt wrecks
-- (generated/vehicles/burntAndSmashedVehicles/burntvehicles.txt, 42.21) and the like. The engine
-- binds no TextureMask for them (ShaderProgram.setValue skips a null texture), so the body shader
-- read whatever another draw had left on that unit, and glass and missing parts flickered over the
-- wreck (reported by Django77, 2026-10-06). Their body shells use the shaders without the mask
-- (VEHICLE_SNOW_BODY_SHADER_NOMASK: NO_MASK in isnow_vehiclesnow.frag, nothing is glass).
-- Lua cannot read a VehicleScript$Skin (public fields, the class is not exposed; reflection only
-- works in -debug), and the script text does not tell either: most vehicles get their mask from
-- `template! = X`, and templates keep no text (getLoadedScriptBodies is empty, 42.21). What tells
-- is the wheels: the wrecks have none, and the engine itself takes a vehicle without wheels for
-- one (BaseVehicle sets its TextureRustA to 0). Checked in game 2026-10-06 against the skins read by
-- reflection, 266 vehicle scripts with KI5 packs: the 21 without a mask are exactly the 21 without
-- wheels (20 vanilla *Burnt, 92amgeneralM998Burnt). A script whose own text names a textureMask
-- keeps it, wheels or not.
local maskedByScript = {}   -- [vehicle script full name] = whether it has a mask

local function textNamesMask(vs)
    local bodies = vs:getLoadedScriptBodies()
    for i = 0, (bodies and bodies:size() or 0) - 1 do
        if string.find(bodies:get(i), "textureMask%s*=%s*[^%s,}]") then return true end
    end
    return false
end

-- Whether vehicle script vs has a mask texture (see maskedByScript).
function Shells.masked(vs)
    local key = vs:getFullName()
    local m = maskedByScript[key]
    if m == nil then
        m = vs:getWheelCount() > 0 or textNamesMask(vs)
        if not m then stats.noMask = stats.noMask + 1 end
        maskedByScript[key] = m
    end
    return m
end

-- Shell ModelScripts are made lazily, one variant at a time, right before a snow model is shown
-- (Shells.ensure, called by ISnow_VehicleSnow.lua): ScriptManager.addModelScript rebuilds the list of
-- every model script of the game on each call (the model ScriptType has the Clear flag, see
-- ScriptBucketCollection.getAllScripts, B42.20), about 0.5 ms with a big mod list, so making all
-- variants of all shells at boot took 14 s with 545 vehicle scripts and grew with the square of
-- their number: a black screen of minutes before the main menu and on every return to it. The
-- engine only looks a part model's ModelScript up when the model is made visible
-- (BaseVehicle.setModelVisible), and our parts have no items, so only Lua makes their models visible.
-- The source model text is read on the first ensure too, not at the world start.
local recipes = {}   -- [shell name prefix] = { module, script = source ModelScript, wheelSeed, noMask; common = model text, wheelTexture once read }

-- Records how to make the shell ModelScripts of one ModelScript; returns the name prefix or nil.
-- Body shells (wheelSeed nil) use a shader per variant that reads the vehicle's mask (their own
-- texture is never bound, see isnow_vehiclesnow.frag); wheel shells a shader per variant and noise
-- offset, so wheels with the same mesh differ, with the wheel's own texture, which tells tyre from
-- rim. noMask: a body shell for vehicles without a mask (see maskedByScript), with the shaders that
-- do without it.
local function createShell(sm, baseModule, bodyScript, wheelSeed, name, noMask)
    local bodies = bodyScript:getLoadedScriptBodies()
    if not bodies or bodies:size() == 0 then
        logError("no script text for model " .. name)
        return nil
    end
    local mesh = bodyScript:getMeshName()
    if not mesh or mesh == "" then
        logError("no mesh in model " .. name)
        return nil
    end
    local prefix = (wheelSeed and "ISnowWheel" .. wheelSeed .. "_" or noMask and "ISnowShellNM_" or "ISnowShell_")
        .. sanitize(name)
    recipes[prefix] = { module = baseModule, script = bodyScript, wheelSeed = wheelSeed, name = name,
        noMask = noMask }
    stats.shells = stats.shells + 1
    return prefix
end

-- The source model's text without its shader and texture (r.common) and its texture, read once;
-- false when it cannot be read.
local function readRecipe(r)
    if r.common ~= nil then return r.common ~= false end
    r.common = false
    local bodies = r.script:getLoadedScriptBodies()
    local props, order = {}, {}
    for i = 0, (bodies and bodies:size() or 0) - 1 do
        parseTopLevel(bodies:get(i), props, order)
    end
    if not props.mesh then
        logError("no mesh in model " .. r.name)
        return false
    end
    local lines = {}
    for _, lk in ipairs(order) do
        if not SKIP_KEYS[lk] then
            for _, e in ipairs(props[lk]) do
                table.insert(lines, "    " .. e.key .. " = " .. e.value .. ",")
            end
        end
    end
    r.common = table.concat(lines, "\n")
    r.wheelTexture = props.texture and props.texture[1].value or ISnow.VEHICLE_SNOW_TYRE_TEXTURE
    return true
end

-- Makes the shell ModelScript name (prefix .. "_" .. variant id) if it does not exist yet; true
-- when it exists afterwards. Only for names of this file's shells.
function Shells.ensure(name)
    if not name then return false end
    local sm = getScriptManager()
    if sm:getModelScript(name) then return true end
    for _, id in ipairs(ENSURE_IDS) do
        local suffix = "_" .. id
        if string.sub(name, -#suffix) == suffix then
            local r = recipes[string.sub(name, 1, #name - #suffix)]
            if r then
                if r.wheelSeed and NO_WHEEL[id] then return false end
                if id == PREVIEW and not r.wheelSeed then return false end
                if r.noMask and IS_GLASS[id] then return false end
                local okRead, read = pcall(readRecipe, r)
                if not okRead then
                    r.common = false
                    logError("model " .. tostring(name) .. ": " .. tostring(read))
                end
                if not (okRead and read) then return false end
                local shader, texture
                -- darker snow: its shaders (stages only, the debug views stay as they are)
                local dark = string.sub(id, 1, 4) ~= "dbg_" and ISnow.darkSnow()
                if id == PREVIEW then
                    -- any wheel shader: it draws nothing with this texture
                    shader = ISnow.VEHICLE_SNOW_WHEEL_SHADER .. ISnow.VEHICLE_SNOW_STAGES[1] .. "_" .. r.wheelSeed
                    texture = ISnow.VEHICLE_SNOW_PREVIEW_TEXTURE
                elseif r.wheelSeed then
                    local wid = (string.sub(id, 1, 4) ~= "dbg_" or ISnow.VEHICLE_SNOW_WHEEL_DEBUG[id]) and id or "dbg_normals"
                    shader = (dark and ISnow.VEHICLE_SNOW_WHEEL_SHADER_DARK or ISnow.VEHICLE_SNOW_WHEEL_SHADER)
                        .. wid .. "_" .. r.wheelSeed
                    texture = r.wheelTexture
                elseif r.noMask and NOMASK_OF[id] then
                    shader = (dark and ISnow.VEHICLE_SNOW_BODY_SHADER_NOMASK_DARK or ISnow.VEHICLE_SNOW_BODY_SHADER_NOMASK)
                        .. NOMASK_OF[id]
                    texture = "ImmersiveSnow/vsnow_" .. id
                else
                    shader = (dark and ISnow.VEHICLE_SNOW_BODY_SHADER_DARK or ISnow.VEHICLE_SNOW_BODY_SHADER) .. id
                    texture = "ImmersiveSnow/vsnow_" .. id
                end
                local ok, err = pcall(function()
                    local ms = ModelScript.new()
                    ms:setModule(r.module)
                    ms:InitLoadPP(name)
                    ms:Load(name, "model " .. name .. "\n{\n" .. r.common .. "\n    shader = " .. shader ..
                        ",\n    texture = " .. texture .. ",\n}\n")
                    sm:addModelScript(ms)
                end)
                if not ok then logError("model " .. name .. ": " .. tostring(err)) end
                stats.created = stats.created + 1
                return ok and sm:getModelScript(name) ~= nil
            end
        end
    end
    return false
end

-- "x y z" of a Vector3f (its tostring is "( 0.000E+0  5.500E-1  0.000E+0)").
local function vec3Text(v)
    local n = {}
    for s in string.gmatch(tostring(v), "[-+%d%.Ee]+") do
        local x = tonumber(s)
        if x then table.insert(n, string.format("%.4f", x)) end
    end
    if #n ~= 3 then return "0.0 0.0 0.0" end
    return table.concat(n, " ")
end

local function placeOf(model)
    if not model then return "0.0 0.0 0.0", "0.0 0.0 0.0", "1.0" end
    return vec3Text(model:getOffset()), vec3Text(model:getRotate()), tostring(model:getScale())
end

-- Shell prefix for a ModelScript (found by the name file), created once per model (and per noMask
-- for a body shell, see createShell); nil if it cannot have one.
local function shellFor(sm, baseModule, ms, wheelSeed, file, noMask)
    local name = modelName(ms, file)
    noMask = noMask and not wheelSeed or nil
    local key = (wheelSeed and "wheel" .. wheelSeed .. ":" or noMask and "bodynm:" or "body:") .. name
    local prefix = shellByModel[key]
    if prefix == nil then
        local ok, res = pcall(createShell, sm, baseModule, ms, wheelSeed, name, noMask)
        if not ok then logError("model " .. tostring(key) .. ": " .. tostring(res)) end
        prefix = ok and res or false
        shellByModel[key] = prefix
    end
    return prefix or nil
end

-- The snow parts of a vehicle script are described by blocks: { id = part id, extra = the part's
-- values, entries = { { slot, prefix, model = source VehicleScript.Model (nil: the body, no
-- transform), wheel } }, and for a snow wheel part tire = tyre part id, wheel = guessed wheel id };
-- a part's models are named slot .. variant id (no one-pass or glass frost variants for a wheel
-- shell).

-- Tyre parts of vehicle script vs: the parts named "Tire..." with models (not only "Tire" .. wheel
-- id: the B42 W900 has TireMiddleLeft / TireMiddleRight too), in part order.
local function tyreParts(vs)
    local out = {}
    for i = 0, vs:getPartCount() - 1 do
        local part = vs:getPart(i)
        local id = part:getId()
        if string.sub(id, 1, 4) == "Tire" and #id > 4 and part:getModelCount() > 0 then
            table.insert(out, part)
        end
    end
    return out
end

-- Wheel parts: for every tyre part with a model, the shells of that model, in a part
-- VEHICLE_SNOW_WHEEL_PART .. the tyre part id without "Tire". Which wheel a tyre part sits on is
-- its `wheel` field, which Lua cannot read from a script (a public field, reflection is debug
-- only), and the name does not tell: the B42 W900 puts TireRearLeft on wheel RearRight and
-- TireMiddleLeft on RearLeft, with model offsets that only fit those wheels (a shell on wheel
-- RearLeft with TireRearLeft's offset floated 2 m beside the truck). The part is meant for the
-- wheel of the same name, if there is one, for now; the client asks the tyre part of a real vehicle
-- (VehiclePart:getWheelIndex) for the right one before it shows anything (Shells.wheels). The
-- script part gets no wheel here, only with its first models (see the top of this file).
local function wheelBlocks(blocks, sm, baseModule, vs, wheels)
    for n, tire in ipairs(tyreParts(vs)) do
        local tireId = tire:getId()
        local suffix = string.sub(tireId, 5)
        local model = tire:getModel(0)
        local ms = model and sm:getModelScript(model:getFile())
        local prefix = ms and shellFor(sm, baseModule, ms, (n - 1) % ISnow.VEHICLE_SNOW_WHEEL_SEEDS, model:getFile())
        if prefix then
            local guess = vs:getWheelById(suffix) and suffix or nil
            local id = ISnow.VEHICLE_SNOW_WHEEL_PART .. suffix
            table.insert(blocks, { id = id, tire = tireId, wheel = guess, extra = "        setAllModelsVisible = false,\n",
                entries = { { slot = "", prefix = prefix, model = model, wheel = true } } })
            table.insert(wheels, { part = id, tire = tireId, wheel = guess, entry = blocks[#blocks].entries[1] })
        end
    end
end

-- The layout counts into stats only during the inject (Shells.addVariant lays a script out again).
local counting = true
local function count(key, n)
    if counting then stats[key] = stats[key] + n end
end

local function skippedById(id)
    local lid = string.lower(id)
    for _, pat in ipairs(PART_SKIP) do
        if string.find(lid, pat) then return true end
    end
    return false
end

local function matchesAny(name, patterns)
    local l = string.lower(name)
    for _, pat in ipairs(patterns) do
        if string.find(l, pat) then return true end
    end
    return false
end

-- Model files of the vehicle's tyre parts.
local function tyreFiles(vs)
    local files = {}
    for _, tire in ipairs(tyreParts(vs)) do
        for k = 0, tire:getModelCount() - 1 do
            files[tire:getModel(k):getFile() or ""] = true
        end
    end
    return files
end

-- Parts of separate body pieces: for every part with models (a door, hood, window, KI5 bumper
-- variants, truck bed...), a part with parent = that part and the shells of each of its models,
-- named "m" .. model index .. "_" .. variant; the client shows the ones whose source model is
-- visible. The parent makes the shells use the part's animation player
-- (BaseVehicle$ModelInfo.getAnimationPlayer), so they have the same pose as the piece (door
-- closed, window rolled down); the model transform does not depend on the parent unless the model
-- has an attachment, and those are skipped. Adds { src, models, glass } to pieces (glass[k]: the
-- model has the glass frost variants, i.e. it is not a wheel).
local function pieceBlocks(blocks, sm, baseModule, vs, pieces)
    local tyres = tyreFiles(vs)
    local noMask = not Shells.masked(vs)
    for i = 0, vs:getPartCount() - 1 do
        local part = vs:getPart(i)
        local id = part:getId()
        if part:getModelCount() > 0 and skippedById(id) then
            if string.sub(id, 1, 5) ~= "ISnow" then count("partSkipId", 1) end
        elseif part:getModelCount() > 0 then
            local entries, models, glass = {}, {}, {}
            for k = 0, part:getModelCount() - 1 do
                local model = part:getModel(k)
                local file = model:getFile()
                local ms = file and sm:getModelScript(file)
                if not ms then
                    count("modelNoScript", 1)
                elseif matchesAny(file, MODEL_SKIP) then
                    count("modelSkipName", 1)
                elseif model:getAttachmentNameParent() then
                    count("modelAttached", 1)
                else
                    local wheel = tyres[file] or matchesAny(file, WHEEL_MODEL)
                    local prefix = shellFor(sm, baseModule, ms, wheel and 0 or nil, file, noMask)
                    if prefix then
                        table.insert(entries, { slot = "m" .. k .. "_", prefix = prefix, model = model, wheel = wheel })
                        table.insert(models, k)
                        if not wheel then glass[k] = true end
                    else
                        count("modelNoScript", 1)
                    end
                end
            end
            if #models > 0 then
                table.insert(blocks, { id = ISnow.VEHICLE_SNOW_PART_PREFIX .. id,
                    extra = "        parent = " .. id .. ",\n        setAllModelsVisible = false,\n", entries = entries })
                table.insert(pieces, { src = id, models = models, glass = glass })
                count("partModels", #models)
            end
        end
    end
end

-- The snow part blocks of vehicle script vs, its body pieces (as Shells.pieces), nil and its wheel
-- parts (as Shells.wheels); nil, nil and why if its body has no shell.
local function layout(sm, baseModule, vs)
    local model = vs:getModelCount() > 0 and vs:getModel() or nil
    local file = model and model:getFile()
    local bodyScript = file and sm:getModelScript(file)
    if not bodyScript then return nil, nil, "noModel" end
    local prefix = shellFor(sm, baseModule, bodyScript, nil, file, not Shells.masked(vs))
    if not prefix then return nil, nil, "failed" end
    -- no items, so the engine never shows all its models; said anyway
    local blocks = { { id = ISnow.VEHICLE_SNOW_PART, extra = "        setAllModelsVisible = false,\n",
        entries = { { slot = "", prefix = prefix } } } }
    local pieces, wheels = {}, {}
    wheelBlocks(blocks, sm, baseModule, vs, wheels)
    pieceBlocks(blocks, sm, baseModule, vs, pieces)
    return blocks, pieces, nil, wheels
end

-- The parts are added at the world start without models: one model per variant and source model
-- was 47 per model, about 4 million VehicleScript$Model objects (over 1 GB) with 847 vehicle
-- scripts (KI5 packs, 84000 body piece models), and the game ran out of heap loading the world.
-- Shells.addVariant adds a variant's models to a script when the client first shows it, so the
-- server never has any and a client only those of the vehicles it sees, in the stages they reach.
-- VehicleScript.Load is the same either way: LoadPart finds the part by id and LoadModel appends a
-- model or reuses one by id (bytecode 42.21), and a vehicle's VehiclePart keeps the script's own
-- Part object (VehicleParts.setScript), so vehicles already in the world see the new models.
local function headerText(vs, blocks)
    local t = { "vehicle " .. vs:getName() .. "\n{\n" }
    for _, b in ipairs(blocks) do
        table.insert(t, "    part " .. b.id .. "\n    {\n        category = nodisplay,\n" .. b.extra .. "    }\n")
    end
    table.insert(t, "}\n")
    return table.concat(t)
end

local function injectOne(sm, baseModule, vs)
    stats.scripts = stats.scripts + 1
    local key = vs:getFullName()
    local already = vs:getPartById(ISnow.VEHICLE_SNOW_PART) ~= nil
    local blocks, pieces, why, wheels = layout(sm, baseModule, vs)
    if not blocks then
        stats[why] = stats[why] + 1
        piecesByScript[key] = {}
        wheelsByScript[key] = {}
        return
    end
    for _, b in ipairs(blocks) do
        if string.sub(b.id, 1, #ISnow.VEHICLE_SNOW_WHEEL_PART) == ISnow.VEHICLE_SNOW_WHEEL_PART then stats.wheels = stats.wheels + 1 end
    end
    stats.parts = stats.parts + #pieces
    if already then
        -- parts from an earlier inject (a world started again without the scripts reloaded, or
        -- Lua reloaded without them): only the shell recipes and the pieces
        stats.already = stats.already + 1
        piecesByScript[key] = pieces
        wheelsByScript[key] = wheels
        return
    end
    local ok, err = pcall(function() vs:Load(vs:getName(), headerText(vs, blocks)) end)
    if ok and vs:getPartById(ISnow.VEHICLE_SNOW_PART) then
        stats.injected = stats.injected + 1
        piecesByScript[key] = pieces
        wheelsByScript[key] = wheels
    else
        stats.failed = stats.failed + 1
        piecesByScript[key] = {}
        wheelsByScript[key] = {}
        logError("vehicle " .. tostring(key) .. ": " .. tostring(err or "part not added"))
    end
end

local IS_VARIANT = {}
for _, id in ipairs(VARIANTS) do IS_VARIANT[id] = true end
local added = {}   -- [vehicle script full name .. "/" .. variant id] = true once added (or tried)
local addedIds = {} -- [vehicle script full name] = the variant ids added, in order (for wheels bound later)

-- Makes the ModelScript of the first model of snow wheel part partId of vehicle script vs (the
-- PREVIEW stand-in). The 3D preview (initWheelModel) draws a part with a wheel by its first model
-- and looks that up every frame: one not made logged "Model missing" each time.
local function ensureFirstModel(vs, partId)
    local sp = vs:getPartById(partId)
    local model = sp and sp:getModelCount() > 0 and sp:getModel(0)
    if model then Shells.ensure(model:getFile()) end
end

-- Script text of the model of shell entry e for variant id.
local function modelText(e, id)
    local offset, rotate, scale = placeOf(e.model)
    return "        model " .. e.slot .. id .. "\n        {\n            file = " .. e.prefix .. "_" .. id ..
        ",\n            offset = " .. offset .. ",\n            rotate = " .. rotate .. ",\n            scale = " .. scale .. ",\n        }\n"
end

-- Script text of snow wheel part partId on wheel with the models of variants ids (the wheel ones),
-- the PREVIEW stand-in first when the script part has no models yet; nil when none to add.
local function wheelPartText(vs, partId, wheel, e, ids)
    local models = {}
    for _, id in ipairs(ids) do
        if not NO_WHEEL[id] then table.insert(models, modelText(e, id)) end
    end
    if #models == 0 then return nil, 0 end
    local n = #models
    if vs:getPartById(partId):getModelCount() == 0 then table.insert(models, 1, modelText(e, PREVIEW)) end
    return "    part " .. partId .. "\n    {\n        wheel = " .. wheel .. ",\n" .. table.concat(models) .. "    }\n", n
end

-- Adds the models of variant id to every snow part of vehicle script vs (client, on first use; see
-- headerText). Only to parts the script already has: a new part would shift the part indices MP
-- syncs by. A snow wheel part gets its models only with its wheel, in the same Load (see the top of
-- this file): the one Shells.wheels bound it to, else the guess; one on no wheel yet gets them when
-- it is bound (bindWheel), and one on none (a spare tyre) never. True when it added any.
function Shells.addVariant(vs, id)
    if not (vs and id and IS_VARIANT[id]) then return false end
    local key = vs:getFullName() .. "/" .. id
    if added[key] then return false end
    added[key] = true
    local n = 0
    local ok, err = pcall(function()
        local sm = getScriptManager()
        counting = false
        local blocks = layout(sm, sm:getModule("Base"), vs)
        counting = true
        if not blocks then return end
        local bound = {}
        for _, w in ipairs(wheelsByScript[vs:getFullName()] or {}) do bound[w.part] = w end
        local set, wheeled = {}, {}
        local t = { "vehicle " .. vs:getName() .. "\n{\n" }
        for _, b in ipairs(blocks) do
            if not vs:getPartById(b.id) then
                -- the script has not got this part (added after the inject): nothing
            elseif b.tire then
                local w = bound[b.id]
                local wheel = w and w.wheel or b.wheel
                local text, k = nil, 0
                if wheel then text, k = wheelPartText(vs, b.id, wheel, b.entries[1], { id }) end
                if text then
                    if w then set[w] = wheel end
                    table.insert(wheeled, b.id)
                    table.insert(t, text)
                    n = n + k
                end
            else
                local models = {}
                for _, e in ipairs(b.entries) do
                    if not (e.wheel and NO_WHEEL[id]) then table.insert(models, modelText(e, id)) end
                end
                if #models > 0 then
                    table.insert(t, "    part " .. b.id .. "\n    {\n" .. table.concat(models) .. "    }\n")
                    n = n + #models
                end
            end
        end
        local list = addedIds[vs:getFullName()] or {}
        addedIds[vs:getFullName()] = list
        table.insert(list, id)
        if n == 0 then return end
        table.insert(t, "}\n")
        vs:Load(vs:getName(), table.concat(t))
        for w, wheel in pairs(set) do w.set = wheel end
        for _, pid in ipairs(wheeled) do ensureFirstModel(vs, pid) end
    end)
    counting = true
    if not ok then
        logError("vehicle " .. tostring(vs:getFullName()) .. " variant " .. id .. ": " .. tostring(err))
        return false
    end
    stats.variants = stats.variants + 1
    stats.variantModels = stats.variantModels + n
    return n > 0
end

local function statsLine()
    return string.format("[ImmersiveSnow] vehicle shells: scripts=%d injected=%d already=%d noModel=%d shells=%d wheels=%d failed=%d" ..
        " | body pieces: parts=%d models=%d; skipped: parts byId=%d, models byName=%d attached=%d noScript=%d" ..
        " | %d ms; variants added: %d (%d models); shell models made so far: %d",
        stats.scripts, stats.injected, stats.already, stats.noModel, stats.shells, stats.wheels, stats.failed,
        stats.parts, stats.partModels, stats.partSkipId, stats.modelSkipName, stats.modelAttached, stats.modelNoScript,
        stats.ms, stats.variants, stats.variantModels, stats.created)
end

function Shells.inject()
    local created, variants, variantModels = stats.created, stats.variants, stats.variantModels
    for k in pairs(stats) do stats[k] = 0 end
    stats.created, stats.variants, stats.variantModels = created, variants, variantModels
    piecesByScript = {}
    wheelsByScript = {}
    local clock = getTimestampMs or function() return 0 end
    local t0 = clock()
    local sm = getScriptManager()
    local baseModule = sm:getModule("Base")
    local list = sm:getAllVehicleScripts()
    for i = 0, list:size() - 1 do
        injectOne(sm, baseModule, list:get(i))
    end
    stats.ms = clock() - t0
    print(statsLine())
end

local NO_PIECES = {}

-- Body pieces of vehicle script vs: list of { src = source part id, models = { source model index },
-- glass = { [source model index] = true when it has the glass frost variants (not a spare wheel) } };
-- the snow part is VEHICLE_SNOW_PART_PREFIX .. src and its model for source model k and variant v
-- is "m" .. k .. "_" .. v. Recorded by the inject; a script it has not seen (Lua reloaded) is laid
-- out on first use.
function Shells.pieces(vs)
    local key = vs:getFullName()
    local pieces = piecesByScript[key]
    if not pieces then
        pieces = NO_PIECES
        if vs:getPartById(ISnow.VEHICLE_SNOW_PART) then
            local sm = getScriptManager()
            counting = false
            local ok, _, res = pcall(layout, sm, sm:getModule("Base"), vs)
            counting = true
            if ok and res then pieces = res end
        end
        piecesByScript[key] = pieces
    end
    return pieces
end

local NO_WHEELS = {}

-- Binds snow wheel part w of vehicle script vs to the wheel its tyre part sits on, asked from
-- vehicle v (see wheelBlocks); left unbound (retried) while v has no such tyre part. The script
-- part gets that wheel with its first models (Shells.addVariant), or now: if it has models already,
-- or if variants were added to the script while it was on no wheel (then their models too).
local function bindWheel(vs, v, w)
    local tire = v:getPartById(w.tire)
    if not tire then return end
    local index = tire:getWheelIndex()
    local wheel = index >= 0 and index < vs:getWheelCount() and vs:getWheel(index):getId() or nil
    local sp = vs:getPartById(w.part)
    local ids = addedIds[vs:getFullName()]
    if wheel and sp and sp:getModelCount() == 0 and ids and #ids > 0 and w.entry then
        local ok, err = pcall(function()
            local text = wheelPartText(vs, w.part, wheel, w.entry, ids)
            if text then vs:Load(vs:getName(), "vehicle " .. vs:getName() .. "\n{\n" .. text .. "}\n") end
        end)
        if not ok then
            logError("vehicle " .. tostring(vs:getFullName()) .. " part " .. w.part .. ": " .. tostring(err))
            w.bound = false
            return
        end
        if sp:getModelCount() > 0 then
            w.set = wheel
            ensureFirstModel(vs, w.part)
        end
    elseif wheel and wheel ~= w.set and sp and sp:getModelCount() > 0 then
        -- BaseVehicle.setModelVisible takes the part's wheel index when a model is shown, and no
        -- model of this part has been shown yet
        local ok, err = pcall(function()
            vs:Load(vs:getName(), "vehicle " .. vs:getName() .. "\n{\n    part " .. w.part ..
                "\n    {\n        wheel = " .. wheel .. ",\n    }\n}\n")
        end)
        if not ok then
            logError("vehicle " .. tostring(vs:getFullName()) .. " part " .. w.part .. ": " .. tostring(err))
            w.bound = false
            return
        end
        w.set = wheel
        ensureFirstModel(vs, w.part)
    end
    if wheel then w.wheel = wheel end
    w.bound = wheel ~= nil
end

-- Snow wheel parts of vehicle v's script: list of { part = snow part id, tire = tyre part id,
-- wheel = wheel id the snow part is for, set = wheel id the script part has (nil until it has
-- models), bound = true when it sits on its tyre's wheel (show it only then) }. The first call for a
-- script binds its parts with v (client, before any is shown).
function Shells.wheels(v)
    local vs = v:getScript()
    if not vs then return NO_WHEELS end
    local key = vs:getFullName()
    local wheels = wheelsByScript[key]
    if not wheels then
        wheels = NO_WHEELS
        if vs:getPartById(ISnow.VEHICLE_SNOW_PART) then
            local sm = getScriptManager()
            counting = false
            local ok, _, _, _, res = pcall(layout, sm, sm:getModule("Base"), vs)
            counting = true
            if ok and res then wheels = res end
        end
        wheelsByScript[key] = wheels
    end
    for _, w in ipairs(wheels) do
        if w.bound == nil then bindWheel(vs, v, w) end
    end
    return wheels
end

-- Name prefix of the shell models for a vehicle script's body, nil if it has none.
function Shells.prefixFor(vs)
    local model = vs and vs:getModelCount() > 0 and vs:getModel()
    local bodyScript = model and getScriptManager():getModelScript(model:getFile())
    return bodyScript and shellByModel[(Shells.masked(vs) and "body:" or "bodynm:") .. modelName(bodyScript, model:getFile())]
        or nil
end

function Shells.variants()
    return VARIANTS
end

-- MP check (ISnow_VehicleSnow.lua, "Multiplayer"): parts are synced by index, so the server and
-- every client need the same parts on every vehicle script. [vehicle script full name] = part count.
function Shells.partCounts()
    local out = {}
    local list = getScriptManager():getAllVehicleScripts()
    for i = 0, list:size() - 1 do
        local vs = list:get(i)
        out[vs:getFullName()] = vs:getPartCount()
    end
    return out
end

local HASH_MOD = 2147483647   -- products stay well inside a double's exact integers

local function hashString(str)
    local h = 5381
    for k = 1, #str do h = (h * 33 + string.byte(str, k)) % HASH_MOD end
    return h
end

-- A number for the part counts that does not depend on the scripts' order, and how many scripts.
function Shells.signature()
    local sig, n = 0, 0
    for name, count in pairs(Shells.partCounts()) do
        sig = (sig + hashString(name) * (count + 1)) % HASH_MOD
        n = n + 1
    end
    return sig, n
end

-- Variants added and shell models made so far (a copy).
function Shells.counts()
    return { variants = stats.variants, created = stats.created }
end

function Shells.stats()
    print(statsLine())
    for _, e in ipairs(errors) do print("[ImmersiveSnow]   " .. e) end
end

local function safeInject()
    local ok, err = pcall(Shells.inject)
    if not ok then logError("inject failed: " .. tostring(err)) end
end

-- Only when a world starts, and after the mods that change vehicle scripts then. IsoWorld.init
-- raises OnInitWorld and later OnInitGlobalModData (GlobalModData.init, nothing loads chunks in
-- between), both on the client, in MP and on the server, after VehiclesDB2.init and before any
-- chunk (so any vehicle) is loaded (bytecode 42.21). Mods that rework vehicle scripts do it in
-- OnInitGlobalModData: Vanilla Vehicles Animated (VVA_core.lua) gives vanilla cars a body model
-- without doors and separate animated doors, hood, trunk and windows (skinned meshes with bones),
-- its SVU patch and 42AnimationsOrphanage the same. The inject used to run in OnInitWorld, before
-- them: it laid the parts out from the vanilla scripts, where those pieces had no models, so they
-- got no snow parts at all. OnInitWorld now only queues the inject as an OnInitGlobalModData
-- handler: added then, it runs after every handler added when the mods' Lua loaded
-- (Event.trigger calls them in the order added). The handler stays for a world started again
-- without Lua reloaded and only runs when OnInitWorld queued it.
-- Nothing in the main menu needs the parts, and injecting there too (OnGameBoot) cost about 2 s
-- with a big mod list at every start and every return to the menu, for nothing: loading a save
-- reloads Lua and the scripts with that save's mods, and the world start injects again.
local injectQueued, lateAdded = false, false

local function lateInject()
    if not injectQueued then return end
    injectQueued = false
    safeInject()
end

local function queueInject()
    injectQueued = true
    if not lateAdded then
        lateAdded = true
        Events.OnInitGlobalModData.Add(lateInject)
    end
end

Events.OnInitWorld.Add(queueInject)
