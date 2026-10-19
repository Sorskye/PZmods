-- Immersive Snow, MP server: passes on the snow each player shows (ISnow_CharSnow.lua,
-- "Multiplayer") to the other clients.
--
-- A client reports its own players only ("charSnow": s = steps of snow on the clothes, i = item
-- stage), when either changes; the server keeps the last report per player and sends it to every
-- client. "charSnowQuery" (id = online id) gets the kept report of that player back to the client
-- that asks: a client that joined later or has just met the player. Nothing is saved: every client
-- reports its players again after joining. Reports of players no longer online are dropped every
-- ten game minutes (online ids are given out again). Each report also puts the reported amount on
-- the server's copy of the player's HumanVisual (alignVisual).

if not isServer() then return end

require "ImmersiveSnow/ISnow_Config"

local MODULE = "ISnow"
local MAX_STEPS = 10   -- 1 / SHOW_STEP in ISnow_CharSnow.lua
local MAX_STAGE = 6    -- #ITEM_STAGES in ISnow_CharSnow.lua

local looks = {}   -- [online id] = { s, i }

local SHELL_PREFIX = "ISnow_CS_"   -- as ISnow_CharSnow.lua
local SHOW_STEP = 1 / MAX_STEPS

local function clampInt(v, hi)
    v = tonumber(v)
    if not v then return nil end
    return math.max(0, math.min(hi, math.floor(v)))
end

-- The server's copy of the player's HumanVisual brought in line with the snow it reports: shells
-- off without snow, else every shell at s steps. The copy is what the client sent last (the game's
-- HumanVisualPacket: IsoPlayer.syncVisuals from updateDirt and such, now and then) with the shells
-- of that moment, and the server sends it back on its own (GameServer.syncHumanVisual: hits, walking
-- through trees, timed actions, other mods' sendHumanVisual; ConnectedPacket on joining) to the
-- owner and everyone near. A copy from when it was snowier came back as full snow for a moment
-- (Workshop report 2026-10-12, Larry Ballsy Bear: characters flicker fully snow-covered about every
-- 30 s; snow shaken off indoors back after a while). Only the copy changes, nothing is sent: the
-- clients already show the reported look. The shell set is the owner's to fix (ISnow_CharSnow.lua,
-- ownMarkOf).
local function alignVisual(player, s)
    local hv = player:getHumanVisual()
    local bv = hv and hv:getBodyVisuals()
    if not bv then return 0 end
    local shells = {}
    for k = 0, bv:size() - 1 do
        local v = bv:get(k)
        local name = v and v:getClothingItemName()
        if name and string.sub(name, 1, #SHELL_PREFIX) == SHELL_PREFIX then table.insert(shells, v) end
    end
    for _, v in ipairs(shells) do
        if s == 0 then
            hv:removeBodyVisualFromItemType("ISnow." .. string.sub(v:getClothingItemName(), #"ISnow_" + 1))
        else
            local old = v:getTint()
            v:setTint(ImmutableColor.new(s * SHOW_STEP, old and old:getGreenFloat() or 0.75, old and old:getBlueFloat() or 1))
        end
    end
    return #shells
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE or not player or type(args) ~= "table" then return end
    if command == "charSnow" then
        -- a client reports its own players only: the id is the sender's, never taken from args
        local id = player:getOnlineID()
        local s, i = clampInt(args.s, MAX_STEPS), clampInt(args.i, MAX_STAGE)
        if not s or not i or id < 0 then return end
        -- also for the same look again (a client that joined anew under a kept id)
        pcall(alignVisual, player, s)
        local last = looks[id]
        if last and last.s == s and last.i == i then return end
        looks[id] = { s = s, i = i }
        sendServerCommand(MODULE, "charSnow", { id = id, s = s, i = i })
    elseif command == "charSnowQuery" then
        local id = tonumber(args.id)
        local look = id and looks[id]
        if look then sendServerCommand(player, MODULE, "charSnow", { id = id, s = look.s, i = look.i }) end
    end
end
Events.OnClientCommand.Add(onClientCommand)

-- Drops the reports of players that left.
local function dropGone()
    local players = ISnow.otherPlayers()
    if not players then return end
    local online = {}
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p then online[p:getOnlineID()] = true end
    end
    local gone = {}
    for id in pairs(looks) do
        if not online[id] then table.insert(gone, id) end
    end
    for _, id in ipairs(gone) do looks[id] = nil end
end
Events.EveryTenMinutes.Add(function() pcall(dropGone) end)
