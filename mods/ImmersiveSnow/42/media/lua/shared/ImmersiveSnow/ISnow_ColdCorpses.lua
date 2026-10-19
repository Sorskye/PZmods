-- Immersive Snow: no flies over corpses and no sickness from their stench in frost (ViZOR, Workshop
-- 2026-10-06: "get rid of the flies hovering over the corpses", "if the temperature was below
-- freezing, there wasn't that stench that causes nausea either").
--
-- Vanilla (bytecode 42.21) never looks at the temperature for either. Both come from
-- BodyDamage.getSicknessFromCorpsesRate(corpses near): 0 with the sandbox option
-- DecayingCorpseHealthImpact = 1 ("None"), else from the sixth corpse on. The sickness (and the
-- mood from corpses) is that rate; the buzz (FliesSound) and the flies drawn over a corpse
-- (IsoGridSquare.hasFlies -> CorpseFlies) are only where that rate is above
-- ZomboidGlobals.foodSicknessDecrease. So while the outdoor air is at FREEZE_C or colder the option
-- is held at "None" here, and set back to its own value once it is above THAW_C (ColdCorpses in the
-- sandbox; off: never touched).
--
-- Flies already there: with "None" FliesSound.update returns at once, so the flies drawn and their
-- buzz stayed as they were till the thaw (seen in game). The option goes to FADE ("Low") first: there
-- FliesSound runs, but makes no flies (at most 25 - 5 corpses * 0.01 = 0.2 of the threshold) and
-- fades out the ones it looks at again (the chunks around a player, when the player comes into
-- another chunk; ~3 s), and the sickness from corpses is at most 0.2 of what it is at "Normal"; once
-- no square within FLY_RADIUS of a local player has had flies for FADE_MINUTES game minutes, "None".
-- The server has no flies (FliesSound is client side): "None" at once.
--
-- Every Lua state has its own SandboxOptions: SP one; in MP the server (the sickness: BodyDamage
-- runs there) and each client (the flies: FliesSound is drawn and played there) hold it each.
--
-- The option's own value must not get lost:
--  * GameWindow.save writes map_sand.bin before OnSave, so the held "None" can go into the save. The
--    own value is kept in the world's ModData (KEY) and set back first at every world start.
--  * A client gets the server's options when it joins, "None" while the server holds it: it asks the
--    server for the own value ("corpseImpact").
--  * Somebody setting the option meanwhile (a player in a sandbox editor, an admin): they want it so
--    in frost too. The mod lets go and turns ColdCorpses off (the Java option and SandboxVars, kept
--    in the save and seen in the sandbox, where it can be turned on again).
--  * The admin panel (ISServerSandboxOptionsUI, also in the SP debug menu) copies this client's
--    options and on Apply sends them all to the server (MP; SP: sets them here). Its copy shows
--    what is held ("None" in MP: the server's), so the admin sees why there is no stench. Left as
--    shown, it goes back as the own value (MP: the server writes it to its SandboxVars file; held
--    on); set to anything else, ColdCorpses goes off in the same Apply (a choice the server could
--    not tell from the own value sent back).
--  * ISnow.cleanSave() (before removing the mod) sets it back for good.

require "ImmersiveSnow/ISnow_Config"

local CC = {}
ISnow.ColdCorpses = CC

local OPTION = "DecayingCorpseHealthImpact"
local NONE = 1
local FADE = 2          -- "Low": no flies made, the ones there fade out (see the top)
local FADE_MINUTES = 3  -- game minutes without flies near before "None"
local FLY_RADIUS = 24   -- squares: the 3 x 3 chunks FliesSound looks at around a player
local FREEZE_C = 0      -- outdoor air at or below: no flies, no stench
local THAW_C = 1        -- above: as the sandbox has it again (a little apart: no flapping at 0)
local KEY = "ISnowCorpseImpact"   -- GameTime ModData: the option's own value while it is held at NONE
local SET = "ISnowCorpseSet"      -- GameTime ModData: what it is held at (NONE or FADE)
local MOD_OPTION = "ColdCorpses"
local MODULE = "ISnow"

local function option()
    local so = getSandboxOptions and getSandboxOptions()
    return so and so:getOptionByName(OPTION)
end

local function modData()
    local gt = getGameTime and getGameTime()
    return gt and gt:getModData()
end

-- The option's own value (the sandbox's), whether it is held or not; nil without the option.
function CC.own()
    local opt = option()
    if not opt then return nil end
    local md = modData()
    return md and md[KEY] or opt:getValue()
end

-- Whether it is held at NONE now.
function CC.holding()
    local md = modData()
    return md ~= nil and md[KEY] ~= nil
end

-- The Java option (what BodyDamage and FliesSound read) and its copy in the SandboxVars table (what
-- Lua reads, SandboxOptions.toLua).
local function set(opt, value)
    opt:setValue(value)
    if type(SandboxVars) == "table" then SandboxVars[OPTION] = value end
end

local function held(value) return value == NONE or value == FADE end

local function hold(opt, md, value)
    set(opt, value)
    md[SET] = value
end

local function setBack(opt, md)
    local own = md[KEY]
    md[KEY], md[SET] = nil, nil
    if own and held(opt:getValue()) then set(opt, own) end
end

-- ColdCorpses off for this save (somebody chose the corpse option while it was held).
local function turnOff()
    local so = getSandboxOptions and getSandboxOptions()
    local opt = so and so:getOptionByName("ImmersiveSnow." .. MOD_OPTION)
    if opt then opt:setValue(false) end
    if type(SandboxVars) == "table" then
        SandboxVars.ImmersiveSnow = SandboxVars.ImmersiveSnow or {}
        SandboxVars.ImmersiveSnow[MOD_OPTION] = false
    end
end

-- Somebody set the option while it was held: true when that is their choice (see the top).
local function chosen(opt, md)
    local v = opt:getValue()
    -- a save from before SET: as then, NONE or FADE is ours
    local mine = md[SET] or (held(v) and v)
    if v == mine then return false end
    local own = md[KEY]
    md[KEY], md[SET] = nil, nil
    -- the server's options came (client): the server tells a choice ("corpseImpact" off)
    if isClient() then return false end
    if isServer() and v == own then
        -- the admin panel's copy: left as shown (the own value back, held again), or set to the own
        -- value with ColdCorpses turned off in it
        if ISnow.worldOpt(MOD_OPTION) then return false end
    else
        turnOff()
    end
    print("[ImmersiveSnow] corpses in frost: " .. OPTION .. " set to " .. tostring(v) ..
        " while held, " .. MOD_OPTION .. " turned off for this save")
    if isServer() then sendServerCommand(MODULE, "corpseImpact", { own = v, held = false, off = true }) end
    return true
end

-- Whether a square within FLY_RADIUS of a local player has flies.
local function fliesNear()
    local cell = getCell()
    if not cell then return false end
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p then
            local px, py, pz = math.floor(p:getX()), math.floor(p:getY()), math.floor(p:getZ())
            for x = px - FLY_RADIUS, px + FLY_RADIUS do
                for y = py - FLY_RADIUS, py + FLY_RADIUS do
                    local sq = cell:getGridSquare(x, y, pz)
                    if sq and sq:hasFlies() then return true end
                end
            end
        end
    end
    return false
end

local quietMinutes = 0   -- game minutes at FADE without flies near

-- Holds the option or lets it go, by the outdoor air. Called at the world start, every game minute
-- and when the server tells the own value.
function CC.update()
    local opt, md = option(), modData()
    if not (opt and md) then return end
    if ISnow.saveCleaned then
        setBack(opt, md)
        return
    end
    if md[KEY] then chosen(opt, md) end
    local on = ISnow.worldOpt(MOD_OPTION)
    local temp = getClimateManager():getTemperature()
    local cold = on and (temp <= FREEZE_C or (md[KEY] ~= nil and temp <= THAW_C))
    if cold and not md[KEY] then
        local own = opt:getValue()
        if own ~= NONE then
            md[KEY] = own
            quietMinutes = 0
            -- "Low" as the own value: straight to None after its flies are gone, as from any other
            hold(opt, md, isServer() and NONE or FADE)
        end
    elseif not cold and md[KEY] then
        setBack(opt, md)
    end
    if cold and md[KEY] and opt:getValue() == FADE then
        if fliesNear() then
            quietMinutes = 0
        else
            quietMinutes = quietMinutes + 1
            if quietMinutes >= FADE_MINUTES then hold(opt, md, NONE) end
        end
    end
end

-- Sets the option back for good (ISnow.cleanSave); true when it was held.
function CC.restore()
    local opt, md = option(), modData()
    if not (opt and md and md[KEY]) then return false end
    setBack(opt, md)
    return true
end

function CC.stats()
    local opt = option()
    return string.format("corpses in frost: on=%s holding=%s option=%s own=%s outdoor=%.1f C",
        tostring(ISnow.worldOpt(MOD_OPTION)), tostring(CC.holding()), tostring(opt and opt:getValue()),
        tostring(CC.own()), getClimateManager():getTemperature())
end

local function safeUpdate()
    local ok, err = pcall(CC.update)
    if not ok then print("[ImmersiveSnow] corpses in frost: " .. tostring(err)) end
end

-- MP: the server tells a client the own value (it joined with the server's "None"), and the
-- admin panel's copy of the options gets it; and that ColdCorpses went off (off).
if isServer() then
    Events.OnClientCommand.Add(function(module, command, player, args)
        if module ~= MODULE or command ~= "corpseImpactQuery" or not player then return end
        local ok, own = pcall(CC.own)
        if ok and own then sendServerCommand(player, MODULE, "corpseImpact", { own = own, held = CC.holding() }) end
    end)
end

if isClient() then
    Events.OnServerCommand.Add(function(module, command, args)
        if module ~= MODULE or command ~= "corpseImpact" or type(args) ~= "table" then return end
        local own = tonumber(args.own)
        local opt, md = option(), modData()
        if not (own and opt and md) then return end
        if args.off then
            turnOff()
            md[KEY], md[SET] = nil, nil
            set(opt, own)
            return
        end
        -- joined while the server held it: what this client has is the server's "None"
        if args.held and own ~= NONE and held(opt:getValue()) then
            md[KEY], md[SET] = own, opt:getValue()
        end
        safeUpdate()
    end)
end

local function hookAdminPanel()
    local ui = ISServerSandboxOptionsUI
    if not (ui and ui.new and ui.settingsFromUI) or ui.ISnowNew then return end
    ui.ISnowNew = ui.new
    ui.new = function(...)
        local o = ui.ISnowNew(...)
        pcall(function()
            local md, opt = modData(), option()
            local mine = o and o.options and o.options:getOptionByName(OPTION)
            if not (mine and md and md[KEY] and opt) then return end
            local shown = isClient() and NONE or opt:getValue()
            mine:setValue(shown)
            o.ISnowCorpseShown = shown
        end)
        return o
    end
    ui.ISnowSettingsFromUI = ui.settingsFromUI
    ui.settingsFromUI = function(self, options, ...)
        local r = ui.ISnowSettingsFromUI(self, options, ...)
        pcall(function()
            local shown = self.ISnowCorpseShown
            local md, opt = modData(), option()
            local mine = shown and options and options:getOptionByName(OPTION)
            if not (mine and md and md[KEY] and opt) then return end
            if mine:getValue() == shown then
                -- left as shown: MP the own value to the server; SP what is held now (FADE may have
                -- gone to NONE while the panel was open: not a choice)
                if isClient() then mine:setValue(md[KEY]) elseif md[SET] then set(opt, md[SET]) end
            elseif isClient() then
                local cc = options:getOptionByName("ImmersiveSnow." .. MOD_OPTION)
                if cc then cc:setValue(false) end
            end
            -- SP: a value set here is a choice at the next update (chosen)
        end)
        return r
    end
end

-- Asked on the first tick with a local player in the world: a command sent on OnGameStart never
-- reaches the server (seen in game).
local asked = false
local function askServer()
    if asked or not getSpecificPlayer(0) then return end
    asked = true
    sendClientCommand(MODULE, "corpseImpactQuery", { ask = true })
end

local function onStart()
    safeUpdate()
    if not isServer() then hookAdminPanel() end
    if isClient() then
        Events.OnTick.Add(askServer)
    end
end

Events.OnGameStart.Add(onStart)
if Events.OnServerStarted then Events.OnServerStarted.Add(safeUpdate) end
Events.EveryOneMinute.Add(safeUpdate)
